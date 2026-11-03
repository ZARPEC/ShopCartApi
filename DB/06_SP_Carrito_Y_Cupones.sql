USE ShopCartDB;
GO

/*==============================================================================
  1. FUNCIÓN TIPO TABLA: dbo.FU_Cupones_CalculoDescuento
     Calcula el subtotal elegible del carrito (todo el carrito o solo la categoría
     del cupón), valida vigencia, cupo y monto mínimo, y devuelve el descuento
     exacto en DECIMAL(12,2) asegurando que nunca deje el total debajo de cero.
==============================================================================*/
CREATE OR ALTER FUNCTION dbo.FU_Cupones_CalculoDescuento (
    @IDCarrito  INT,
    @IDCupon    INT,
    @IDUsuario  INT = NULL
)
RETURNS @Resultado TABLE (
    EsValido                BIT           NOT NULL,
    CodigoRechazo           VARCHAR(50)   NULL,
    MensajeValidacion       NVARCHAR(300) NOT NULL,
    SubtotalCarrito         DECIMAL(12,2) NOT NULL,
    SubtotalElegibleCupon   DECIMAL(12,2) NOT NULL,
    MontoDescuento          DECIMAL(12,2) NOT NULL,
    TotalConDescuento       DECIMAL(12,2) NOT NULL
)
AS
BEGIN
    DECLARE @SubtotalCarrito DECIMAL(12,2) = 0.00;
    DECLARE @SubtotalElegible DECIMAL(12,2) = 0.00;

    SELECT @SubtotalCarrito = ISNULL(SUM(CAST(cd.Cantidad * v.PrecioActual AS DECIMAL(12,2))), 0.00)
    FROM dbo.CarritoDetalle cd
    INNER JOIN dbo.VarianteProducto v ON cd.IDVarianteProducto = v.IDVarianteProducto
    WHERE cd.IDCarrito = @IDCarrito;

    -- Si no hay cupón asignado, devolver subtotal sin descuento
    IF @IDCupon IS NULL
    BEGIN
        INSERT INTO @Resultado VALUES (1, NULL, N'Sin cupón aplicado.', @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito);
        RETURN;
    END;

    DECLARE @Codigo VARCHAR(50);
    DECLARE @IDTipoDescuento TINYINT;
    DECLARE @ValorDescuento DECIMAL(12,2);
    DECLARE @IDAmbito TINYINT;
    DECLARE @IDCategoriaCupon INT;
    DECLARE @MontoMinimo DECIMAL(12,2);
    DECLARE @MontoMaximo DECIMAL(12,2);
    DECLARE @LimiteTotal INT;
    DECLARE @LimitePorCliente INT;
    DECLARE @UsosActuales INT;
    DECLARE @FechaInicio DATETIME2(3);
    DECLARE @FechaFin DATETIME2(3);
    DECLARE @Activo BIT;

    SELECT 
        @Codigo           = Codigo,
        @IDTipoDescuento  = IDTipoDescuentoCupon,
        @ValorDescuento   = ValorDescuento,
        @IDAmbito         = IDAmbitoCupon,
        @IDCategoriaCupon = IDCategoria,
        @MontoMinimo      = MontoMinimoCompra,
        @MontoMaximo      = MontoMaximoDescuento,
        @LimiteTotal      = LimiteTotalUsos,
        @LimitePorCliente = LimiteUsosPorCliente,
        @UsosActuales     = UsosActuales,
        @FechaInicio      = FechaInicioVigencia,
        @FechaFin         = FechaFinVigencia,
        @Activo           = Activo
    FROM dbo.Cupon
    WHERE IDCupon = @IDCupon;

    IF @Codigo IS NULL OR @Activo = 0
    BEGIN
        INSERT INTO @Resultado VALUES (0, 'CUPON_INACTIVO', N'El cupón no existe o se encuentra desactivado.', @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito);
        RETURN;
    END;

    -- Validar vigencia
    IF SYSDATETIME() < @FechaInicio
    BEGIN
        INSERT INTO @Resultado VALUES (0, 'CUPON_NO_INICIADO', N'El cupón aún no ha iniciado su periodo de vigencia.', @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito);
        RETURN;
    END;

    IF SYSDATETIME() > @FechaFin
    BEGIN
        INSERT INTO @Resultado VALUES (0, 'CUPON_VENCIDO', N'El cupón ha vencido y ya no puede aplicarse.', @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito);
        RETURN;
    END;

    -- Validar límite total de usos 
    IF @UsosActuales >= @LimiteTotal
    BEGIN
        INSERT INTO @Resultado VALUES (0, 'CUPON_AGOTADO', N'El cupón ha alcanzado su límite máximo de usos.', @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito);
        RETURN;
    END;

    -- Validar límite de usos por cliente si está autenticado
    IF @IDUsuario IS NOT NULL
    BEGIN
        DECLARE @UsosCliente INT = (
            SELECT COUNT(1) FROM dbo.CuponUso WHERE IDCupon = @IDCupon AND IDUsuario = @IDUsuario
        );
        IF @UsosCliente >= @LimitePorCliente
        BEGIN
            INSERT INTO @Resultado VALUES (0, 'CUPON_LIMITE_CLIENTE', N'Ya has alcanzado el límite de usos permitidos de este cupón para tu cuenta.', @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito);
            RETURN;
        END;
    END;

    -- Validar monto mínimo de compra 
    IF @SubtotalCarrito < @MontoMinimo
    BEGIN
        INSERT INTO @Resultado VALUES (
            0, 
            'CUPON_MONTO_MINIMO', 
            CONCAT(N'El cupón requiere un monto mínimo de compra de Q ', FORMAT(@MontoMinimo, 'N2'), N'.'), 
            @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito
        );
        RETURN;
    END;

    -- Calcular subtotal elegible según el ámbito (1 = Todo el carrito, 2 = Categoría específica)
    IF @IDAmbito = 1
    BEGIN
        SET @SubtotalElegible = @SubtotalCarrito;
    END
    ELSE
    BEGIN
        SELECT @SubtotalElegible = ISNULL(SUM(CAST(cd.Cantidad * v.PrecioActual AS DECIMAL(12,2))), 0.00)
        FROM dbo.CarritoDetalle cd
        INNER JOIN dbo.VarianteProducto v ON cd.IDVarianteProducto = v.IDVarianteProducto
        INNER JOIN dbo.Producto p ON v.IDProducto = p.IDProducto
        WHERE cd.IDCarrito = @IDCarrito
          AND p.IDCategoria = @IDCategoriaCupon;

        IF @SubtotalElegible <= 0.00
        BEGIN
            INSERT INTO @Resultado VALUES (0, 'CUPON_SIN_PRODUCTOS_CATEGORIA', N'Tu carrito no contiene productos de la categoría requerida por este cupón.', @SubtotalCarrito, 0.00, 0.00, @SubtotalCarrito);
            RETURN;
        END;
    END;

    -- Calcular descuento en DECIMAL(12,2) sin errores de redondeo
    DECLARE @DescuentoCalculado DECIMAL(12,2) = 0.00;

    IF @IDTipoDescuento = 1 -- PORCENTAJE
    BEGIN
        SET @DescuentoCalculado = ROUND(@SubtotalElegible * (@ValorDescuento / 100.00), 2);
        IF @MontoMaximo IS NOT NULL AND @DescuentoCalculado > @MontoMaximo
        BEGIN
            SET @DescuentoCalculado = @MontoMaximo;
        END;
    END
    ELSE -- MONTO FIJO
    BEGIN
        SET @DescuentoCalculado = @ValorDescuento;
    END;

    -- validar que no quede en 0 el carrito
    IF @DescuentoCalculado > @SubtotalElegible
    BEGIN
        SET @DescuentoCalculado = @SubtotalElegible;
    END;

    IF @DescuentoCalculado > @SubtotalCarrito
    BEGIN
        SET @DescuentoCalculado = @SubtotalCarrito;
    END;

    INSERT INTO @Resultado VALUES (
        1,
        NULL,
        N'Cupón aplicado correctamente.',
        @SubtotalCarrito,
        @SubtotalElegible,
        @DescuentoCalculado,
        (@SubtotalCarrito - @DescuentoCalculado)
    );
    RETURN;
END;
GO

/*==============================================================================
  SP_Cupones_CrearCupon 
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Cupones_CrearCupon
    @Codigo               VARCHAR(50),
    @Descripcion          NVARCHAR(300),
    @IDTipoDescuentoCupon TINYINT,       -- 1 = PORCENTAJE, 2 = MONTO_FIJO
    @ValorDescuento       DECIMAL(12,2),
    @IDAmbitoCupon        TINYINT,       -- 1 = CARRITO_COMPLETO, 2 = CATEGORIA
    @IDCategoria          INT           = NULL,
    @MontoMinimoCompra    DECIMAL(12,2) = 0.00,
    @MontoMaximoDescuento DECIMAL(12,2) = NULL,
    @LimiteTotalUsos      INT,
    @LimiteUsosPorCliente INT           = 1,
    @FechaInicioVigencia  DATETIME2(3),
    @FechaFinVigencia     DATETIME2(3),
    @IDUsuarioAdmin       INT,
    @DireccionIP          VARCHAR(45)   = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));

    IF EXISTS (SELECT 1 FROM dbo.Cupon WHERE Codigo = @Codigo)
    BEGIN
        ;THROW 50030, N'Ya existe un cupón registrado con ese código.', 1;
    END;

    IF @IDTipoDescuentoCupon = 1 AND (@ValorDescuento <= 0 OR @ValorDescuento > 100)
    BEGIN
        ;THROW 50031, N'El descuento porcentual debe estar entre 0.01% y 100%.', 1;
    END;

    IF @IDAmbitoCupon = 2 AND @IDCategoria IS NULL
    BEGIN
        ;THROW 50032, N'Cuando el cupón aplica por categoría debe indicar la categoría.', 1;
    END;

    IF @FechaFinVigencia <= @FechaInicioVigencia
    BEGIN
        ;THROW 50033, N'La fecha de fin de vigencia debe ser posterior a la fecha de inicio.', 1;
    END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.Cupon (
        Codigo, Descripcion, IDTipoDescuentoCupon, ValorDescuento,
        IDAmbitoCupon, IDCategoria, MontoMinimoCompra, MontoMaximoDescuento,
        LimiteTotalUsos, LimiteUsosPorCliente, UsosActuales,
        FechaInicioVigencia, FechaFinVigencia, Activo
    )
    VALUES (
        @Codigo, @Descripcion, @IDTipoDescuentoCupon, @ValorDescuento,
        @IDAmbitoCupon, CASE WHEN @IDAmbitoCupon = 2 THEN @IDCategoria ELSE NULL END,
        @MontoMinimoCompra, @MontoMaximoDescuento,
        @LimiteTotalUsos, @LimiteUsosPorCliente, 0,
        @FechaInicioVigencia, @FechaFinVigencia, 1
    );

    DECLARE @IDCupon INT = SCOPE_IDENTITY();
    DECLARE @IDModuloCupones TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'CUPONES');

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema, IDUsuario, Entidad, IDRegistroEntidad,
        Accion, ResumenCambio, ValorAnteriorJson, ValorNuevoJson, DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloCupones, 5),
        @IDUsuarioAdmin,
        'Cupon',
        CAST(@IDCupon AS VARCHAR(100)),
        'CREACION',
        CONCAT(N'Creación de cupón ', @Codigo),
        NULL,
        (SELECT @IDCupon AS IDCupon, @Codigo AS Codigo, @ValorDescuento AS ValorDescuento, @LimiteTotalUsos AS LimiteTotalUsos FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT * FROM dbo.Cupon WHERE IDCupon = @IDCupon;
END;
GO

/*==============================================================================
  3. SP_Cupones_ListarCupones (Admin)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Cupones_ListarCupones
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        cp.IDCupon,
        cp.Codigo,
        cp.Descripcion,
        cp.IDTipoDescuentoCupon,
        td.Codigo AS TipoDescuentoCodigo,
        cp.ValorDescuento,
        cp.IDAmbitoCupon,
        am.Codigo AS AmbitoCodigo,
        cp.IDCategoria,
        cat.Nombre AS NombreCategoria,
        cp.MontoMinimoCompra,
        cp.MontoMaximoDescuento,
        cp.LimiteTotalUsos,
        cp.LimiteUsosPorCliente,
        cp.UsosActuales,
        (cp.LimiteTotalUsos - cp.UsosActuales) AS UsosDisponibles,
        cp.FechaInicioVigencia,
        cp.FechaFinVigencia,
        cp.Activo
    FROM dbo.Cupon cp
    INNER JOIN dbo.TipoDescuentoCupon td ON cp.IDTipoDescuentoCupon = td.IDTipoDescuentoCupon
    INNER JOIN dbo.AmbitoCupon am ON cp.IDAmbitoCupon = am.IDAmbitoCupon
    LEFT JOIN dbo.Categoria cat ON cp.IDCategoria = cat.IDCategoria
    ORDER BY cp.IDCupon DESC;
END;
GO

/*==============================================================================
  4. SP_Carrito_ObtenerDetalleCompleto
     Obtiene (o crea si no existe) el carrito activo del Cliente o del Invitado,
     sus líneas con precios vigentes y el resumen exacto (Subtotal, Descuento, Total).
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Carrito_ObtenerDetalleCompleto
    @IDUsuario     INT          = NULL,
    @TokenInvitado VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @IDUsuario IS NULL AND (@TokenInvitado IS NULL OR LTRIM(RTRIM(@TokenInvitado)) = '')
    BEGIN
        ;THROW 50040, N'Se requiere un usuario autenticado o un token de invitado para consultar el carrito.', 1;
    END;

    DECLARE @IDCarrito INT;

    -- Buscar carrito activo (IDEstadoCarrito = 1 'ACTIVO' o 2 'EN_CHECKOUT')
    IF @IDUsuario IS NOT NULL
    BEGIN
        SELECT TOP 1 @IDCarrito = IDCarrito
        FROM dbo.Carrito
        WHERE IDUsuario = @IDUsuario AND IDEstadoCarrito IN (1, 2)
        ORDER BY IDCarrito DESC;
    END
    ELSE
    BEGIN
        SELECT TOP 1 @IDCarrito = IDCarrito
        FROM dbo.Carrito
        WHERE TokenInvitado = @TokenInvitado AND IDUsuario IS NULL AND IDEstadoCarrito IN (1, 2)
        ORDER BY IDCarrito DESC;
    END;

    -- Si no tiene carrito activo aún, crearle uno nuevo en estado ACTIVO (1)
    IF @IDCarrito IS NULL
    BEGIN
        INSERT INTO dbo.Carrito (IDUsuario, TokenInvitado, IDEstadoCarrito)
        VALUES (@IDUsuario, CASE WHEN @IDUsuario IS NULL THEN @TokenInvitado ELSE NULL END, 1);

        SET @IDCarrito = SCOPE_IDENTITY();
    END;

    DECLARE @IDCuponActual INT = (SELECT IDCupon FROM dbo.Carrito WHERE IDCarrito = @IDCarrito);

    -- Tabla 0: Líneas del carrito con precios y stock disponible al instante
    SELECT 
        cd.IDCarritoDetalle,
        cd.IDCarrito,
        cd.IDVarianteProducto,
        v.SKU,
        p.IDProducto,
        p.Nombre AS NombreProducto,
        p.Slug AS SlugProducto,
        v.NombreVariante,
        cd.Cantidad,
        v.PrecioActual AS PrecioUnitarioActual,
        CAST(cd.Cantidad * v.PrecioActual AS DECIMAL(12,2)) AS SubtotalLinea,
        v.ExistenciaDisponible,
        (SELECT TOP 1 UrlImagen FROM dbo.ProductoImagen WHERE IDProducto = p.IDProducto AND EsPrincipal = 1) AS UrlImagen
    FROM dbo.CarritoDetalle cd
    INNER JOIN dbo.VarianteProducto v ON cd.IDVarianteProducto = v.IDVarianteProducto
    INNER JOIN dbo.Producto p ON v.IDProducto = p.IDProducto
    WHERE cd.IDCarrito = @IDCarrito
    ORDER BY cd.IDCarritoDetalle ASC;

    -- Tabla 1: Resumen financiero del carrito (Subtotal, Descuento de Cupón y Total sin errores de redondeo)
    SELECT 
        c.IDCarrito,
        c.IDUsuario,
        c.TokenInvitado,
        c.IDCupon,
        cp.Codigo AS CodigoCupon,
        cp.Descripcion AS DescripcionCupon,
        ISNULL((SELECT SUM(Cantidad) FROM dbo.CarritoDetalle WHERE IDCarrito = @IDCarrito), 0) AS TotalUnidades,
        calc.SubtotalCarrito AS Subtotal,
        calc.MontoDescuento AS Descuento,
        calc.TotalConDescuento AS Total,
        calc.EsValido AS CuponEsValido,
        calc.MensajeValidacion AS MensajeCupon
    FROM dbo.Carrito c
    LEFT JOIN dbo.Cupon cp ON c.IDCupon = cp.IDCupon
    CROSS APPLY dbo.FU_Cupones_CalculoDescuento(@IDCarrito, @IDCuponActual, @IDUsuario) calc
    WHERE c.IDCarrito = @IDCarrito;
END;
GO

/*==============================================================================
  5. SP_Carrito_AgregarOActualizarItem
     Si @EsSuma = 1 suma la cantidad a la ya existente en el carrito; si @EsSuma = 0 la reemplaza.
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Carrito_AgregarOActualizarItem
    @IDUsuario          INT          = NULL,
    @TokenInvitado      VARCHAR(100) = NULL,
    @IDVarianteProducto INT,
    @Cantidad           INT,
    @EsSuma             BIT          = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Cantidad <= 0
    BEGIN
        ;THROW 50041, N'La cantidad debe ser mayor a cero.', 1;
    END;

    DECLARE @ExistenciaDisponible INT;
    DECLARE @PrecioActual DECIMAL(12,2);
    DECLARE @VarianteActiva BIT;
    DECLARE @ProductoActivo BIT;

    SELECT 
        @ExistenciaDisponible = v.ExistenciaDisponible,
        @PrecioActual         = v.PrecioActual,
        @VarianteActiva       = v.Activo,
        @ProductoActivo       = p.Activo
    FROM dbo.VarianteProducto v
    INNER JOIN dbo.Producto p ON v.IDProducto = p.IDProducto
    WHERE v.IDVarianteProducto = @IDVarianteProducto;

    IF @VarianteActiva IS NULL OR @VarianteActiva = 0 OR @ProductoActivo = 0
    BEGIN
        ;THROW 50042, N'El producto o variante seleccionada no está disponible en la tienda.', 1;
    END;

    -- Obtener o crear el carrito activo
    DECLARE @IDCarrito INT;

    IF @IDUsuario IS NOT NULL
    BEGIN
        SELECT TOP 1 @IDCarrito = IDCarrito
        FROM dbo.Carrito
        WHERE IDUsuario = @IDUsuario AND IDEstadoCarrito IN (1, 2)
        ORDER BY IDCarrito DESC;
    END
    ELSE
    BEGIN
        SELECT TOP 1 @IDCarrito = IDCarrito
        FROM dbo.Carrito
        WHERE TokenInvitado = @TokenInvitado AND IDUsuario IS NULL AND IDEstadoCarrito IN (1, 2)
        ORDER BY IDCarrito DESC;
    END;

    IF @IDCarrito IS NULL
    BEGIN
        INSERT INTO dbo.Carrito (IDUsuario, TokenInvitado, IDEstadoCarrito)
        VALUES (@IDUsuario, CASE WHEN @IDUsuario IS NULL THEN @TokenInvitado ELSE NULL END, 1);

        SET @IDCarrito = SCOPE_IDENTITY();
    END;

    DECLARE @CantidadActualEnCarrito INT = 0;

    SELECT @CantidadActualEnCarrito = Cantidad
    FROM dbo.CarritoDetalle
    WHERE IDCarrito = @IDCarrito AND IDVarianteProducto = @IDVarianteProducto;

    DECLARE @CantidadFinal INT = CASE 
        WHEN @EsSuma = 1 THEN (@CantidadActualEnCarrito + @Cantidad)
        ELSE @Cantidad
    END;

    -- validar existencia disponible
    IF @CantidadFinal > @ExistenciaDisponible
    BEGIN
        DECLARE @MsjStock NVARCHAR(300) = CONCAT(
            N'No se puede agregar la cantidad solicitada (', @CantidadFinal, 
            N'). Existencia disponible actualmente: ', @ExistenciaDisponible, N' unidades.'
        );
        THROW 50043, @MsjStock, 1;
    END;

    BEGIN TRANSACTION;

    IF @CantidadActualEnCarrito > 0
    BEGIN
        UPDATE dbo.CarritoDetalle
        SET Cantidad                 = @CantidadFinal,
            PrecioUnitarioReferencia = @PrecioActual,
            FechaModificacion        = SYSDATETIME()
        WHERE IDCarrito = @IDCarrito AND IDVarianteProducto = @IDVarianteProducto;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.CarritoDetalle (IDCarrito, IDVarianteProducto, Cantidad, PrecioUnitarioReferencia)
        VALUES (@IDCarrito, @IDVarianteProducto, @CantidadFinal, @PrecioActual);
    END;

    UPDATE dbo.Carrito
    SET FechaUltimaActividad = SYSDATETIME(),
        IDEstadoCarrito      = 1 -- Si estaba marcado como abandonado, vuelve a ACTIVO
    WHERE IDCarrito = @IDCarrito;

    COMMIT TRANSACTION;

    -- Devolver el estado actualizado del carrito
    EXEC dbo.SP_Carrito_ObtenerDetalleCompleto @IDUsuario = @IDUsuario, @TokenInvitado = @TokenInvitado;
END;
GO

/*==============================================================================
  6. SP_Carrito_EliminarItem
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Carrito_EliminarItem
    @IDUsuario          INT          = NULL,
    @TokenInvitado      VARCHAR(100) = NULL,
    @IDVarianteProducto INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IDCarrito INT;

    IF @IDUsuario IS NOT NULL
        SELECT TOP 1 @IDCarrito = IDCarrito FROM dbo.Carrito WHERE IDUsuario = @IDUsuario AND IDEstadoCarrito IN (1, 2) ORDER BY IDCarrito DESC;
    ELSE
        SELECT TOP 1 @IDCarrito = IDCarrito FROM dbo.Carrito WHERE TokenInvitado = @TokenInvitado AND IDUsuario IS NULL AND IDEstadoCarrito IN (1, 2) ORDER BY IDCarrito DESC;

    IF @IDCarrito IS NOT NULL
    BEGIN
        DELETE FROM dbo.CarritoDetalle
        WHERE IDCarrito = @IDCarrito AND IDVarianteProducto = @IDVarianteProducto;

        UPDATE dbo.Carrito
        SET FechaUltimaActividad = SYSDATETIME()
        WHERE IDCarrito = @IDCarrito;
    END;

    EXEC dbo.SP_Carrito_ObtenerDetalleCompleto @IDUsuario = @IDUsuario, @TokenInvitado = @TokenInvitado;
END;
GO

/*==============================================================================
  7. SP_Carrito_AplicarCupon
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Carrito_AplicarCupon
    @IDUsuario     INT          = NULL,
    @TokenInvitado VARCHAR(100) = NULL,
    @CodigoCupon   VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SET @CodigoCupon = UPPER(LTRIM(RTRIM(@CodigoCupon)));

    DECLARE @IDCarrito INT;

    IF @IDUsuario IS NOT NULL
        SELECT TOP 1 @IDCarrito = IDCarrito FROM dbo.Carrito WHERE IDUsuario = @IDUsuario AND IDEstadoCarrito IN (1, 2) ORDER BY IDCarrito DESC;
    ELSE
        SELECT TOP 1 @IDCarrito = IDCarrito FROM dbo.Carrito WHERE TokenInvitado = @TokenInvitado AND IDUsuario IS NULL AND IDEstadoCarrito IN (1, 2) ORDER BY IDCarrito DESC;

    IF @IDCarrito IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.CarritoDetalle WHERE IDCarrito = @IDCarrito)
    BEGIN
        ;THROW 50044, N'Debes agregar productos al carrito antes de aplicar un cupón.', 1;
    END;

    DECLARE @IDCupon INT = (SELECT IDCupon FROM dbo.Cupon WHERE Codigo = @CodigoCupon);

    IF @IDCupon IS NULL
    BEGIN
        ;THROW 50045, N'El código de cupón ingresado no existe.', 1;
    END;

    -- Evaluar reglas con la función tipo tabla FU_Cupones_CalculoDescuento
    DECLARE @EsValido BIT;
    DECLARE @MensajeValidacion NVARCHAR(300);

    SELECT 
        @EsValido          = EsValido,
        @MensajeValidacion = MensajeValidacion
    FROM dbo.FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon, @IDUsuario);

    IF @EsValido = 0
    BEGIN
        ;THROW 50046, @MensajeValidacion, 1;
    END;

    UPDATE dbo.Carrito
    SET IDCupon              = @IDCupon,
        FechaUltimaActividad = SYSDATETIME()
    WHERE IDCarrito = @IDCarrito;

    EXEC dbo.SP_Carrito_ObtenerDetalleCompleto @IDUsuario = @IDUsuario, @TokenInvitado = @TokenInvitado;
END;
GO

/*==============================================================================
  8. SP_Carrito_RemoverCupon
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Carrito_RemoverCupon
    @IDUsuario     INT          = NULL,
    @TokenInvitado VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Carrito
    SET IDCupon              = NULL,
        FechaUltimaActividad = SYSDATETIME()
    WHERE (@IDUsuario IS NOT NULL AND IDUsuario = @IDUsuario AND IDEstadoCarrito IN (1, 2))
       OR (@IDUsuario IS NULL AND TokenInvitado = @TokenInvitado AND IDEstadoCarrito IN (1, 2));

    EXEC dbo.SP_Carrito_ObtenerDetalleCompleto @IDUsuario = @IDUsuario, @TokenInvitado = @TokenInvitado;
END;
GO

/*==============================================================================
  9. CUPONES DE PRUEBA 
==============================================================================*/
IF NOT EXISTS (SELECT 1 FROM dbo.Cupon WHERE Codigo = 'SHOP10')
BEGIN
    INSERT INTO dbo.Cupon (
        Codigo, Descripcion, IDTipoDescuentoCupon, ValorDescuento,
        IDAmbitoCupon, IDCategoria, MontoMinimoCompra, MontoMaximoDescuento,
        LimiteTotalUsos, LimiteUsosPorCliente, UsosActuales,
        FechaInicioVigencia, FechaFinVigencia, Activo
    )
    VALUES 
    -- 1. Cupón 10% en todo el carrito (compra mínima Q 200)
    ('SHOP10', N'10% de descuento en toda la tienda en compras mayores a Q 200', 1, 10.00, 1, NULL, 200.00, 500.00, 50, 2, 0, DATEADD(DAY, -5, SYSDATETIME()), DATEADD(DAY, 30, SYSDATETIME()), 1),
    -- 2. Cupón Q 50 fijos en Tecnología y Celulares (IDCategoria = 1, compra mínima Q 1,000)
    ('TECNO50', N'Q 50.00 de descuento en Tecnología y Celulares', 2, 50.00, 2, 1, 1000.00, NULL, 20, 1, 0, DATEADD(DAY, -5, SYSDATETIME()), DATEADD(DAY, 30, SYSDATETIME()), 1),
    -- 3. Cupón vencido (para demostrar el mensaje específico en la defensa técnica)
    ('EXPIRADO20', N'Cupón vencido de prueba', 1, 20.00, 1, NULL, 100.00, NULL, 10, 1, 0, DATEADD(DAY, -30, SYSDATETIME()), DATEADD(DAY, -1, SYSDATETIME()), 1);
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_Carrito_MarcarCarritosAbandonados
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MinutosAbandono INT = 60;
    SELECT @MinutosAbandono = CAST(Valor AS INT)
    FROM dbo.ConfiguracionSistema
    WHERE Clave = 'CARRITO_ABANDONADO_MINUTOS' AND Activo = 1;

    -- Pasa a ABANDONADO (4) cualquier carrito con productos que no tenga actividad
    UPDATE c
    SET c.IDEstadoCarrito = 4
    FROM dbo.Carrito c
    INNER JOIN dbo.CarritoDetalle cd ON c.IDCarrito = cd.IDCarrito
    WHERE c.IDEstadoCarrito = 1 -- Solo los que estaban en ACTIVO
      AND c.FechaUltimaActividad < DATEADD(MINUTE, -@MinutosAbandono, SYSDATETIME());

    SELECT @@ROWCOUNT AS TotalCarritosMarcadosAbandonados;
END;
GO