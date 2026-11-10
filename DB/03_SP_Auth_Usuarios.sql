USE ShopCartDB;
GO

/*==============================================================================
  SP_Auth_RegistrarCliente: Registro de clientes con rol CLIENTE (RF-01)
==============================================================================*/


CREATE OR ALTER PROCEDURE dbo.SP_Auth_RegistrarCliente
    @Nombres           NVARCHAR(100),
    @Apellidos         NVARCHAR(100),
    @CorreoElectronico VARCHAR(255),
    @PasswordHash      VARCHAR(255),
    @Telefono          VARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE CorreoElectronico = @CorreoElectronico)
    BEGIN
        THROW 50001, N'El correo electrónico ya se encuentra registrado.', 1;
    END;

    DECLARE @IDRolCliente TINYINT;
    SELECT @IDRolCliente = IDRol FROM dbo.Rol WHERE Codigo = 'CLIENTE';

    INSERT INTO dbo.Usuario (
        IDRol,
        Nombres,
        Apellidos,
        CorreoElectronico,
        PasswordHash,
        Telefono,
        Activo
    )
    VALUES (
        @IDRolCliente,
        @Nombres,
        @Apellidos,
        @CorreoElectronico,
        @PasswordHash,
        @Telefono,
        1
    );

    SELECT 
        u.IDUsuario,
        u.Nombres,
        u.Apellidos,
        u.CorreoElectronico,
        r.Codigo AS CodigoRol,
        r.Nombre AS NombreRol
    FROM dbo.Usuario u
    INNER JOIN dbo.Rol r ON u.IDRol = r.IDRol
    WHERE u.IDUsuario = SCOPE_IDENTITY();
END;
GO

/*==============================================================================
   SP_Auth_ObtenerUsuarioPorCorreo: Para validar login y contraseñas
==============================================================================*/
-- 1. SP_Auth_ObtenerUsuarioPorCorreo: Evalúa el bloqueo directamente en SQL Server
CREATE OR ALTER PROCEDURE dbo.SP_Auth_ObtenerUsuarioPorCorreo
    @CorreoElectronico VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        u.IDUsuario,
        u.IDRol,
        r.Codigo AS CodigoRol,
        r.Nombre AS NombreRol,
        u.Nombres,
        u.Apellidos,
        u.CorreoElectronico,
        u.PasswordHash,
        u.IntentosFallidosLogin,
        u.BloqueadoHasta,
        u.Activo,
         -- se valida si no esta bloqueado con los 15 min
        CASE 
            WHEN u.BloqueadoHasta IS NOT NULL AND u.BloqueadoHasta > SYSDATETIME() 
            THEN 1 
            ELSE 0 
        END AS EstaBloqueado,
        CASE 
            WHEN u.BloqueadoHasta IS NOT NULL AND u.BloqueadoHasta > SYSDATETIME() 
            THEN DATEDIFF(MINUTE, SYSDATETIME(), u.BloqueadoHasta) + 1 
            ELSE 0 
        END AS MinutosRestantesBloqueo
    FROM dbo.Usuario u
    INNER JOIN dbo.Rol r ON u.IDRol = r.IDRol
    WHERE u.CorreoElectronico = @CorreoElectronico;
END;
GO

-- 2. SP_Auth_RegistrarResultadoLogin: Informa si este intento provocó el bloqueo
CREATE OR ALTER PROCEDURE dbo.SP_Auth_RegistrarResultadoLogin
    @IDUsuario     INT,
    @EsExitoso     BIT,
    @MaxIntentos   TINYINT = 5,
    @MinutosBloqueo INT = 15
AS
BEGIN
    SET NOCOUNT ON;

    IF @EsExitoso = 1
    BEGIN
        UPDATE dbo.Usuario
        SET IntentosFallidosLogin = 0,
            BloqueadoHasta = NULL,
            UltimoAcceso = SYSDATETIME(),
            FechaModificacion = SYSDATETIME()
        WHERE IDUsuario = @IDUsuario;

        SELECT 0 AS FueBloqueado, 0 AS IntentosActuales;
    END
    ELSE
    BEGIN
        UPDATE dbo.Usuario
        SET IntentosFallidosLogin = IntentosFallidosLogin + 1,
            BloqueadoHasta = CASE 
                WHEN (IntentosFallidosLogin + 1) >= @MaxIntentos 
                THEN DATEADD(MINUTE, @MinutosBloqueo, SYSDATETIME())
                ELSE NULL 
            END,
            FechaModificacion = SYSDATETIME()
        WHERE IDUsuario = @IDUsuario;

        SELECT 
            CASE 
                WHEN BloqueadoHasta IS NOT NULL AND BloqueadoHasta > SYSDATETIME() 
                THEN 1 
                ELSE 0 
            END AS FueBloqueado,
            IntentosFallidosLogin AS IntentosActuales
        FROM dbo.Usuario
        WHERE IDUsuario = @IDUsuario;
    END;
END;
GO

/*==============================================================================
 SP_Auth_GuardarRefreshToken: Almacena sesión con rotación
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Auth_GuardarRefreshToken
    @IDUsuario       INT,
    @TokenHash       VARCHAR(128),
    @FamiliaToken    UNIQUEIDENTIFIER,
    @FechaExpiracion DATETIME2(3),
    @DireccionIP     VARCHAR(45) = NULL,
    @AgenteUsuario   NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.RefreshToken (
        IDUsuario,
        TokenHash,
        FamiliaToken,
        FechaExpiracion,
        DireccionIP,
        AgenteUsuario
    )
    VALUES (
        @IDUsuario,
        @TokenHash,
        @FamiliaToken,
        @FechaExpiracion,
        @DireccionIP,
        @AgenteUsuario
    );

    SELECT SCOPE_IDENTITY() AS IDRefreshToken;
END;
GO

/*==============================================================================
 SP_Auth_RotarRefreshToken: Detecta reuso fraudulento o emite nuevo token
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Auth_RotarRefreshToken
    @TokenHashActual VARCHAR(128),
    @NuevoTokenHash  VARCHAR(128),
    @NuevaExpiracion DATETIME2(3),
    @DireccionIP     VARCHAR(45) = NULL,
    @AgenteUsuario   NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @IDTokenActual BIGINT;
    DECLARE @IDUsuario INT;
    DECLARE @FamiliaToken UNIQUEIDENTIFIER;
    DECLARE @FechaRevocacion DATETIME2(3);
    DECLARE @FechaExpiracion DATETIME2(3);

    SELECT 
        @IDTokenActual   = IDRefreshToken,
        @IDUsuario       = IDUsuario,
        @FamiliaToken    = FamiliaToken,
        @FechaRevocacion = FechaRevocacion,
        @FechaExpiracion = FechaExpiracion
    FROM dbo.RefreshToken
    WHERE TokenHash = @TokenHashActual;

    -- Si el token no existe
    IF @IDTokenActual IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50002, N'Token de sesión inválido.', 1;
    END;

    -- Si el token ya había sido revocado (ALERTA DE REUSO / ROBO DE TOKEN):
    -- Revocar todos los tokens de esa familia por seguridad
    IF @FechaRevocacion IS NOT NULL
    BEGIN
        UPDATE dbo.RefreshToken
        SET FechaRevocacion = SYSDATETIME(),
            MotivoRevocacion = N'Intento de reuso detectado en la rotación'
        WHERE FamiliaToken = @FamiliaToken
          AND FechaRevocacion IS NULL;

        ROLLBACK TRANSACTION;
        THROW 50003, N'Sesión comprometida. Inicie sesión nuevamente.', 1;
    END;

    -- Si ya expiró
    IF @FechaExpiracion < SYSDATETIME()
    BEGIN
        UPDATE dbo.RefreshToken
        SET FechaRevocacion = SYSDATETIME(),
            MotivoRevocacion = N'Expirado'
        WHERE IDRefreshToken = @IDTokenActual;

        ROLLBACK TRANSACTION;
        THROW 50004, N'La sesión ha expirado.', 1;
    END;

    -- 1. Crear el nuevo token hijo
    DECLARE @IDNuevoToken BIGINT;

    INSERT INTO dbo.RefreshToken (
        IDUsuario,
        TokenHash,
        FamiliaToken,
        FechaExpiracion,
        DireccionIP,
        AgenteUsuario
    )
    VALUES (
        @IDUsuario,
        @NuevoTokenHash,
        @FamiliaToken,
        @NuevaExpiracion,
        @DireccionIP,
        @AgenteUsuario
    );

    SET @IDNuevoToken = SCOPE_IDENTITY();

    -- 2. Revocar el token anterior y apuntarlo al reemplazo
    UPDATE dbo.RefreshToken
    SET FechaRevocacion = SYSDATETIME(),
        MotivoRevocacion = N'Rotación normal de sesión',
        IDRefreshTokenReemplazado = @IDNuevoToken
    WHERE IDRefreshToken = @IDTokenActual;

    COMMIT TRANSACTION;

    -- Devolver datos del usuario para emitir el nuevo Access Token
	SELECT 
		u.IDUsuario,
		u.Nombres,
		u.Apellidos,
		u.CorreoElectronico,
		r.Codigo AS CodigoRol
	FROM dbo.Usuario u
	INNER JOIN dbo.Rol r ON u.IDRol = r.IDRol
	WHERE u.IDUsuario = @IDUsuario AND u.Activo = 1;
END;
GO

/*==============================================================================
   SP_Auth_RevocarRefreshToken: Para el Logout
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Auth_RevocarRefreshToken
    @TokenHash VARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.RefreshToken
    SET FechaRevocacion = SYSDATETIME(),
        MotivoRevocacion = N'Cierre de sesión voluntario'
    WHERE TokenHash = @TokenHash
      AND FechaRevocacion IS NULL;
END;
GO

/*==============================================================================
  SP_Auth_CrearEmpleado (Solo Administrador)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Auth_CrearEmpleado
    @IDRol             TINYINT,       -- 2 = OPERADOR, 3 = ADMINISTRADOR
    @Nombres           NVARCHAR(100),
    @Apellidos         NVARCHAR(100),
    @CorreoElectronico VARCHAR(150),
    @Telefono          VARCHAR(20)    = NULL,
    @PasswordHash      VARCHAR(255),
    @IDUsuarioAdmin    INT            = 1,
    @DireccionIP       VARCHAR(45)    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @CorreoElectronico = LOWER(LTRIM(RTRIM(@CorreoElectronico)));

    -- Validar que el rol sea empleado (2 = Operador, 3 = Administrador)
    IF @IDRol NOT IN (2, 3)
    BEGIN
        ;THROW 50005, N'El rol especificado para el empleado no es válido (solo Operador o Administrador).', 1;
    END;

    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE CorreoElectronico = @CorreoElectronico)
    BEGIN
        ;THROW 50001, N'El correo electrónico ya se encuentra registrado en el sistema.', 1;
    END;

    DECLARE @NuevoIDUsuario INT;

    BEGIN TRANSACTION;

    INSERT INTO dbo.Usuario (
        IDRol, Nombres, Apellidos, CorreoElectronico, Telefono, PasswordHash, Activo
    )
    VALUES (
        @IDRol, LTRIM(RTRIM(@Nombres)), LTRIM(RTRIM(@Apellidos)), @CorreoElectronico, @Telefono, @PasswordHash, 1
    );

    SET @NuevoIDUsuario = SCOPE_IDENTITY();

    -- Registrar auditoría inmutable de creación de empleado (RF-09)
    DECLARE @IDModuloAuth TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'AUTENTICACION');
    DECLARE @NombreRol NVARCHAR(50) = (SELECT Nombre FROM dbo.Rol WHERE IDRol = @IDRol);

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema, IDUsuario, Entidad, IDRegistroEntidad,
        Accion, ResumenCambio, ValorAnteriorJson, ValorNuevoJson, DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloAuth, 1),
        @IDUsuarioAdmin,
        'Usuario',
        CAST(@NuevoIDUsuario AS VARCHAR(100)),
        'CREACION',
        CONCAT(N'Creación de empleado ', @Nombres, N' ', @Apellidos, N' con rol ', @NombreRol, N' (', @CorreoElectronico, N')'),
        NULL,
        (SELECT @NuevoIDUsuario AS IDUsuario, @IDRol AS IDRol, @NombreRol AS Rol, @CorreoElectronico AS Correo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT 
        u.IDUsuario,
        u.IDRol,
        r.Codigo AS CodigoRol,
        r.Nombre AS NombreRol,
        u.Nombres,
        u.Apellidos,
        u.CorreoElectronico,
        u.Telefono,
        u.Activo,
        u.FechaCreacion
    FROM dbo.Usuario u
    INNER JOIN dbo.Rol r ON u.IDRol = r.IDRol
    WHERE u.IDUsuario = @NuevoIDUsuario;
END;
GO

/*==============================================================================
  SP_Auth_ListarUsuarios (Búsqueda y filtro por rol para el panel Admin)
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.SP_Auth_ListarUsuarios
    @BuscarTexto NVARCHAR(100) = NULL,
    @IDRol       TINYINT       = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        u.IDUsuario,
        u.IDRol,
        r.Codigo AS CodigoRol,
        r.Nombre AS NombreRol,
        u.Nombres,
        u.Apellidos,
        u.CorreoElectronico,
        u.Telefono,
        u.Activo,
        u.IntentosFallidosLogin,
        u.BloqueadoHasta,
        u.FechaCreacion,
        u.UltimoAcceso
    FROM dbo.Usuario u
    INNER JOIN dbo.Rol r ON u.IDRol = r.IDRol
    WHERE (@IDRol IS NULL OR u.IDRol = @IDRol)
      AND (
          @BuscarTexto IS NULL 
          OR u.Nombres LIKE '%' + @BuscarTexto + '%' 
          OR u.Apellidos LIKE '%' + @BuscarTexto + '%' 
          OR u.CorreoElectronico LIKE '%' + @BuscarTexto + '%'
      )
    ORDER BY u.IDRol DESC, u.FechaCreacion DESC;
END;
GO



/*==============================================================================
  3. SP_Auth_CambiarEstadoUsuario (Desactivar o reactivar acceso a empleados)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Auth_CambiarEstadoUsuario
    @IDUsuarioTarget INT,
    @Activo          BIT,
    @IDUsuarioAdmin  INT         = 1,
    @DireccionIP     VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDUsuarioTarget = @IDUsuarioAdmin AND @Activo = 0
    BEGIN
        THROW 50006, N'No puedes desactivar tu propia cuenta de Administrador.', 1;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE IDUsuario = @IDUsuarioTarget)
    BEGIN
        THROW 50007, N'El usuario especificado no existe.', 1;
    END;

    BEGIN TRANSACTION;

    UPDATE dbo.Usuario
    SET Activo = @Activo,
        FechaModificacion = SYSDATETIME()
    WHERE IDUsuario = @IDUsuarioTarget;

    -- Si se desactiva, revocar de inmediato todos sus refresh tokens de sesión
    IF @Activo = 0
    BEGIN
        UPDATE dbo.RefreshToken
        SET FechaRevocacion = SYSDATETIME(),
            MotivoRevocacion = N'Cuenta desactivada por el Administrador'
        WHERE IDUsuario = @IDUsuarioTarget
          AND FechaRevocacion IS NULL;
    END;

    DECLARE @IDModuloAuth TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'AUTENTICACION');
    DECLARE @Accion VARCHAR(40) = CASE WHEN @Activo = 1 THEN 'REACTIVACION' ELSE 'DESACTIVACION' END;

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema, IDUsuario, Entidad, IDRegistroEntidad,
        Accion, ResumenCambio, ValorAnteriorJson, ValorNuevoJson, DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloAuth, 1),
        @IDUsuarioAdmin,
        'Usuario',
        CAST(@IDUsuarioTarget AS VARCHAR(100)),
        @Accion,
        CONCAT(N'Cambio de estado del usuario ID #', @IDUsuarioTarget, N' a: ', CASE WHEN @Activo = 1 THEN 'ACTIVO' ELSE 'INACTIVO' END),
        (SELECT CASE WHEN @Activo = 1 THEN 0 ELSE 1 END AS Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT @Activo AS Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT IDUsuario, Activo, N'Estado del usuario actualizado exitosamente.' AS Mensaje
    FROM dbo.Usuario
    WHERE IDUsuario = @IDUsuarioTarget;
END;
GO

/*==============================================================================
  SP_Auth_ActualizarPerfil
     Permite al usuario editar sus nombres, apellidos y teléfono.
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Auth_ActualizarPerfil
    @IDUsuario  INT,
    @Nombres    NVARCHAR(100),
    @Apellidos  NVARCHAR(100),
    @Telefono   VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE IDUsuario = @IDUsuario AND Activo = 1)
    BEGIN
        ;THROW 50007, N'Usuario no encontrado o inactivo.', 1;
    END;

    UPDATE dbo.Usuario
    SET Nombres           = LTRIM(RTRIM(@Nombres)),
        Apellidos         = LTRIM(RTRIM(@Apellidos)),
        Telefono          = @Telefono,
        FechaModificacion = SYSDATETIME()
    WHERE IDUsuario = @IDUsuario;

    SELECT 
        u.IDUsuario,
        u.Nombres,
        u.Apellidos,
        CONCAT(u.Nombres, ' ', u.Apellidos) AS NombreCompleto,
        u.CorreoElectronico,
        u.Telefono,
        r.Codigo AS Rol
    FROM dbo.Usuario u
    INNER JOIN dbo.Rol r ON u.IDRol = r.IDRol
    WHERE u.IDUsuario = @IDUsuario;
END;
GO

/*==============================================================================
  SP_Auth_CambiarPassword
     Actualiza la contraseña hasheada del usuario y revoca sus refresh tokens anteriores.
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Auth_CambiarPassword
    @IDUsuario          INT,
    @NuevoPasswordHash  VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE IDUsuario = @IDUsuario AND Activo = 1)
    BEGIN
        ;THROW 50007, N'Usuario no encontrado o inactivo.', 1;
    END;

    BEGIN TRANSACTION;

    UPDATE dbo.Usuario
    SET PasswordHash      = @NuevoPasswordHash,
        FechaModificacion = SYSDATETIME()
    WHERE IDUsuario = @IDUsuario;

    -- Revocar todos los refresh tokens previos por seguridad
    UPDATE dbo.RefreshToken
    SET FechaRevocacion = SYSDATETIME(),
        MotivoRevocacion = N'Cambio voluntario de contraseña por el usuario'
    WHERE IDUsuario = @IDUsuario AND FechaRevocacion IS NULL;

    COMMIT TRANSACTION;

    SELECT @IDUsuario AS IDUsuario, N'Contraseña actualizada exitosamente.' AS Mensaje;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_Auth_ObtenerUsuarioPorId
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        u.IDUsuario,
        u.Nombres,
        u.Apellidos,
        CONCAT(u.Nombres, ' ', u.Apellidos) AS NombreCompleto,
        u.CorreoElectronico,
        u.Telefono,
        u.PasswordHash,
        u.Activo,
        r.Codigo AS Rol
    FROM dbo.Usuario u
    INNER JOIN dbo.Rol r ON u.IDRol = r.IDRol
    WHERE u.IDUsuario = @IDUsuario AND u.Activo = 1;
END;
GO