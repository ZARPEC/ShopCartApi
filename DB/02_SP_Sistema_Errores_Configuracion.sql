
USE ShopCartDB;
GO

-- 1. SP_Sistema_RegistrarError: Guarda cualquier excepción capturada en un bloque catch
CREATE OR ALTER PROCEDURE dbo.SP_Sistema_RegistrarError
    @CodigoModulo           VARCHAR(40)      = 'SISTEMA',
    @IDSeveridadError       TINYINT          = 2,          -- 1 = WARNING, 2 = ERROR, 3 = CRITICAL
    @IDUsuario              INT              = NULL,
    @CodigoCorrelacion      UNIQUEIDENTIFIER = NULL,
    @OrigenError            VARCHAR(30)      = 'BACKEND_MIDDLEWARE',
    @ObjetoOMetodo          VARCHAR(200),
    @NumeroLinea            INT              = NULL,
    @NumeroErrorSQL         INT              = NULL,
    @EstadoErrorSQL         TINYINT          = NULL,
    @CodigoErrorAplicacion  VARCHAR(60)      = NULL,
    @MensajeError           NVARCHAR(2000),
    @DetalleStackTrace      NVARCHAR(MAX)    = NULL,
    @ParametrosContextoJson NVARCHAR(MAX)    = NULL,
    @MetodoHttp             VARCHAR(10)      = NULL,
    @RutaEndpoint           VARCHAR(300)     = NULL,
    @CodigoEstadoHttp       SMALLINT         = NULL,
    @DireccionIP            VARCHAR(45)      = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IDModuloSistema TINYINT;

    SELECT @IDModuloSistema = IDModuloSistema
    FROM dbo.ModuloSistema
    WHERE Codigo = @CodigoModulo;

    IF @IDModuloSistema IS NULL
    BEGIN
        SELECT @IDModuloSistema = IDModuloSistema
        FROM dbo.ModuloSistema
        WHERE Codigo = 'SISTEMA';
    END;

    -- Validar que si viene JSON inválido no falle la inserción del error
    IF @ParametrosContextoJson IS NOT NULL AND ISJSON(@ParametrosContextoJson) = 0
    BEGIN
        SET @ParametrosContextoJson = NULL;
    END;

    INSERT INTO dbo.BitacoraError (
        IDModuloSistema,
        IDSeveridadError,
        IDUsuario,
        CodigoCorrelacion,
        OrigenError,
        ObjetoOMetodo,
        NumeroLinea,
        NumeroErrorSQL,
        EstadoErrorSQL,
        CodigoErrorAplicacion,
        MensajeError,
        DetalleStackTrace,
        ParametrosContextoJson,
        MetodoHttp,
        RutaEndpoint,
        CodigoEstadoHttp,
        DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloSistema, 10),
        CASE WHEN @IDSeveridadError IN (1, 2, 3) THEN @IDSeveridadError ELSE 2 END,
        @IDUsuario,
        @CodigoCorrelacion,
        CASE WHEN @OrigenError IN ('SQL_SP', 'BACKEND_SERVICIO', 'BACKEND_CONTROLADOR', 'BACKEND_MIDDLEWARE', 'TAREA_PROGRAMADA')
             THEN @OrigenError ELSE 'BACKEND_MIDDLEWARE' END,
        LEFT(@ObjetoOMetodo, 200),
        @NumeroLinea,
        @NumeroErrorSQL,
        @EstadoErrorSQL,
        @CodigoErrorAplicacion,
        LEFT(@MensajeError, 2000),
        @DetalleStackTrace,
        @ParametrosContextoJson,
        @MetodoHttp,
        @RutaEndpoint,
        @CodigoEstadoHttp,
        @DireccionIP
    );

    SELECT SCOPE_IDENTITY() AS IDBitacoraError;
END;
GO

-- 2. SP_Sistema_ObtenerConfiguraciones: Obtiene los parámetros activos de ConfiguracionSistema
CREATE OR ALTER PROCEDURE dbo.SP_Sistema_ObtenerConfiguraciones
    @CodigoModulo VARCHAR(40) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.IDConfiguracionSistema,
        m.Codigo AS CodigoModulo,
        m.Nombre AS NombreModulo,
        c.Clave,
        c.Valor,
        c.TipoDato,
        c.ValorMinimo,
        c.ValorMaximo,
        c.Descripcion,
        c.EsEditableAdmin,
        c.FechaModificacion
    FROM dbo.ConfiguracionSistema c
    INNER JOIN dbo.ModuloSistema m ON c.IDModuloSistema = m.IDModuloSistema
    WHERE c.Activo = 1
      AND (@CodigoModulo IS NULL OR m.Codigo = @CodigoModulo)
    ORDER BY m.IDModuloSistema, c.Clave;
END;
GO