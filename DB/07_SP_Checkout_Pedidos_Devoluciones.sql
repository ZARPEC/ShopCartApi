USE ShopCartDB;
GO

/*==============================================================================
  1. SP_Direcciones_RegistrarOListar
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Direcciones_Registrar
    @IDUsuario          INT,
    @Alias              NVARCHAR(60),
    @NombreRecibe       NVARCHAR(150),
    @TelefonoContacto   VARCHAR(30),
    @Departamento       NVARCHAR(100),
    @Municipio          NVARCHAR(100),
    @Zona               VARCHAR(20) = NULL,
    @DireccionExacta    NVARCHAR(500),
    @Referencias        NVARCHAR(400) = NULL,
    @EsPredeterminada   BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    IF @EsPredeterminada = 1
    BEGIN
        UPDATE dbo.DireccionCliente
        SET EsPredeterminada = 0
        WHERE IDUsuario = @IDUsuario;
    END;

    INSERT INTO dbo.DireccionCliente (
        IDUsuario, Alias, NombreRecibe, TelefonoContacto,
        Departamento, Municipio, Zona, DireccionExacta, Referencias, EsPredeterminada, Activo
    )
    VALUES (
        @IDUsuario, @Alias, @NombreRecibe, @TelefonoContacto,
        @Departamento, @Municipio, @Zona, @DireccionExacta, @Referencias, @EsPredeterminada, 1
    );

    DECLARE @IDDireccion INT = SCOPE_IDENTITY();
    COMMIT TRANSACTION;

    SELECT * FROM dbo.DireccionCliente WHERE IDDireccionCliente = @IDDireccion;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_Direcciones_ListarPorUsuario
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.DireccionCliente WHERE IDUsuario = @IDUsuario AND Activo = 1 ORDER BY EsPredeterminada DESC, IDDireccionCliente DESC;
END;
GO

/*==============================================================================
  2. SP_Checkout_IniciarReserva 
     Protegido con UPDLOCK, ROWLOCK para compras simultáneas de la última unidad.
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Checkout_IniciarReserva
    @IDUsuario     INT,
    @IDCarrito     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Si no viene IDCarrito, buscar el activo del usuario
    IF @IDCarrito IS NULL
    BEGIN
        SELECT TOP 1 @IDCarrito = IDCarrito 
        FROM dbo.Carrito 
        WHERE IDUsuario = @IDUsuario AND IDEstadoCarrito IN (1, 2) 
        ORDER BY IDCarrito DESC;
    END;

    IF @IDCarrito IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.CarritoDetalle WHERE IDCarrito = @IDCarrito)
    BEGIN
        ;THROW 50050, N'El carrito está vacío o no existe.', 1;
    END;

    -- Leer minutos configurados en ConfiguracionSistema (por defecto 15)
    DECLARE @MinutosReserva INT = 15;
    SELECT @MinutosReserva = CAST(Valor AS INT)
    FROM dbo.ConfiguracionSistema
    WHERE Clave = 'CHECKOUT_TIEMPO_RESERVA_MIN' AND Activo = 1;

    BEGIN TRANSACTION;

    -- Cancelar reservas activas anteriores que pudiera tener este mismo carrito
    UPDATE v
    SET v.ExistenciaReservada = v.ExistenciaReservada - r.CantidadReservada
    FROM dbo.VarianteProducto v
    INNER JOIN dbo.ReservaInventario r ON v.IDVarianteProducto = r.IDVarianteProducto
    WHERE r.IDCarrito = @IDCarrito AND r.IDEstadoReserva = 1;

    UPDATE dbo.ReservaInventario
    SET IDEstadoReserva = 4, FechaResolucion = SYSDATETIME() -- 4 = LIBERADA_CANCELACION
    WHERE IDCarrito = @IDCarrito AND IDEstadoReserva = 1;

    -- Validar y reservar cada variante del carrito con bloqueo estricto (UPDLOCK)
    DECLARE @IDVariante INT, @CantidadPedida INT, @SKU VARCHAR(60), @StockDisponible INT;

    DECLARE curItems CURSOR LOCAL FAST_FORWARD FOR
        SELECT cd.IDVarianteProducto, cd.Cantidad
        FROM dbo.CarritoDetalle cd
        WHERE cd.IDCarrito = @IDCarrito;

    OPEN curItems;
    FETCH NEXT FROM curItems INTO @IDVariante, @CantidadPedida;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Bloqueo atómico a nivel de fila contra sobreventa
        SELECT 
            @SKU = SKU,
            @StockDisponible = (ExistenciaFisica - ExistenciaReservada)
        FROM dbo.VarianteProducto WITH (UPDLOCK, ROWLOCK)
        WHERE IDVarianteProducto = @IDVariante AND Activo = 1;

        IF @SKU IS NULL OR @StockDisponible < @CantidadPedida
        BEGIN
            CLOSE curItems;
            DEALLOCATE curItems;
            ROLLBACK TRANSACTION;

            DECLARE @MsjSinStock NVARCHAR(300) = CONCAT(
                N'No hay suficiente existencia disponible para el producto (SKU: ', ISNULL(@SKU, 'DESCONOCIDO'), 
                N'). Disponibles: ', ISNULL(@StockDisponible, 0), N', solicitadas: ', @CantidadPedida, N'.'
            );
            THROW 50051, @MsjSinStock, 1;
        END;

        -- Reservar las unidades
        UPDATE dbo.VarianteProducto
        SET ExistenciaReservada = ExistenciaReservada + @CantidadPedida
        WHERE IDVarianteProducto = @IDVariante;

        INSERT INTO dbo.ReservaInventario (
            IDCarrito, IDVarianteProducto, IDUsuario, IDEstadoReserva,
            CantidadReservada, ClaveIdempotencia, FechaExpiracion
        )
        VALUES (
            @IDCarrito, @IDVariante, @IDUsuario, 1, -- 1 = ACTIVA
            @CantidadPedida, CAST(NEWID() AS VARCHAR(100)), DATEADD(MINUTE, @MinutosReserva, SYSDATETIME())
        );

        FETCH NEXT FROM curItems INTO @IDVariante, @CantidadPedida;
    END;

    CLOSE curItems;
    DEALLOCATE curItems;

    -- Poner carrito en estado EN_CHECKOUT (2)
    UPDATE dbo.Carrito SET IDEstadoCarrito = 2, FechaUltimaActividad = SYSDATETIME() WHERE IDCarrito = @IDCarrito;

    COMMIT TRANSACTION;

    SELECT 
        @IDCarrito AS IDCarrito,
        @MinutosReserva AS MinutosReserva,
        DATEADD(MINUTE, @MinutosReserva, SYSDATETIME()) AS ExpiraEn,
        N'Existencias reservadas por 15 minutos exitosamente.' AS Mensaje;
END;
GO

/*==============================================================================
  3. SP_Checkout_ConfirmarPagoYCrearPedido 
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Checkout_ConfirmarPagoYCrearPedido
    @IDUsuario          INT,
    @IDDireccionCliente INT,
    @IDMetodoPago       TINYINT,
    @ClaveIdempotencia  VARCHAR(100),
    @NotasCliente       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Si la clave ya fue procesada, devolver el pedido existente sin duplicar cobro
    IF EXISTS (SELECT 1 FROM dbo.Pedido WHERE ClaveIdempotencia = @ClaveIdempotencia)
    BEGIN
        SELECT 
            IDPedido, NumeroPedido, TotalPedido, IDEstadoPedido, 
            FechaCreacion, 1 AS EsRespuestaIdempotente
        FROM dbo.Pedido 
        WHERE ClaveIdempotencia = @ClaveIdempotencia;
        RETURN;
    END;

    -- Buscar carrito activo del usuario
    DECLARE @IDCarrito INT, @IDCupon INT;
    SELECT TOP 1 @IDCarrito = IDCarrito, @IDCupon = IDCupon
    FROM dbo.Carrito
    WHERE IDUsuario = @IDUsuario AND IDEstadoCarrito IN (1, 2)
    ORDER BY IDCarrito DESC;

    IF @IDCarrito IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.CarritoDetalle WHERE IDCarrito = @IDCarrito)
    BEGIN
        ;THROW 50052, N'No hay productos en el carrito para procesar el pedido.', 1;
    END;

    -- Validar dirección de entrega (debe pertenecer al usuario)
    DECLARE @NomRecibe NVARCHAR(150), @Tel VARCHAR(30), @Depto NVARCHAR(100), @Muni NVARCHAR(100), @Zona VARCHAR(20), @DirExacta NVARCHAR(500), @Ref NVARCHAR(400);

    SELECT 
        @NomRecibe = NombreRecibe, @Tel = TelefonoContacto, @Depto = Departamento,
        @Muni = Municipio, @Zona = Zona, @DirExacta = DireccionExacta, @Ref = Referencias
    FROM dbo.DireccionCliente
    WHERE IDDireccionCliente = @IDDireccionCliente AND IDUsuario = @IDUsuario AND Activo = 1;

    IF @NomRecibe IS NULL
    BEGIN
        ;THROW 50053, N'La dirección de entrega especificada no es válida.', 1;
    END;

    BEGIN TRANSACTION;

    -- Calcular importes y descuento exacto con la función tipo tabla FU_Cupones_CalculoDescuento
    DECLARE @SubtotalBruto DECIMAL(12,2), @DescuentoCupon DECIMAL(12,2), @TotalPedido DECIMAL(12,2);
    DECLARE @CuponValido BIT, @MsjCupon NVARCHAR(300);

    SELECT 
        @SubtotalBruto   = SubtotalCarrito,
        @DescuentoCupon  = MontoDescuento,
        @TotalPedido     = TotalConDescuento,
        @CuponValido     = EsValido,
        @MsjCupon        = MensajeValidacion
    FROM dbo.FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon, @IDUsuario);

    IF @IDCupon IS NOT NULL AND @CuponValido = 0
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50054, @MsjCupon, 1;
    END;

    -- Calcular costo de envío según ConfiguracionSistema
    DECLARE @CostoEnvio DECIMAL(12,2) = 25.00;
    DECLARE @MontoMinimoEnvioGratis DECIMAL(12,2) = 500.00;

    SELECT @CostoEnvio = CAST(Valor AS DECIMAL(12,2)) FROM dbo.ConfiguracionSistema WHERE Clave = 'ENVIO_COSTO_ESTANDAR_GTQ' AND Activo = 1;
    SELECT @MontoMinimoEnvioGratis = CAST(Valor AS DECIMAL(12,2)) FROM dbo.ConfiguracionSistema WHERE Clave = 'ENVIO_GRATIS_MONTO_MINIMO_GTQ' AND Activo = 1;

    IF @SubtotalBruto >= @MontoMinimoEnvioGratis
    BEGIN
        SET @CostoEnvio = 0.00;
    END;

    SET @TotalPedido = (@SubtotalBruto - @DescuentoCupon) + @CostoEnvio;

    -- Desglose de IVA 12% incluido
    DECLARE @MontoIVA DECIMAL(12,2) = ROUND(@TotalPedido - (@TotalPedido / 1.12), 2);

    -- Generar número correlativo de pedido legible
    DECLARE @NumeroPedido VARCHAR(30) = CONCAT('ORD-', FORMAT(SYSDATETIME(), 'yyyyMMdd'), '-', SUBSTRING(REPLACE(NEWID(), '-', ''), 1, 6));
    DECLARE @CodigoCupon VARCHAR(50) = (SELECT Codigo FROM dbo.Cupon WHERE IDCupon = @IDCupon);

    -- 1. Insertar Cabecera de Pedido (Precios, IVA y Dirección Congelados)
    INSERT INTO dbo.Pedido (
        NumeroPedido, IDUsuario, IDCarritoOrigen, IDEstadoPedido, IDMetodoPago,
        IDCupon, CodigoCuponCongelado, Moneda, PorcentajeIVACongelado,
        SubtotalBruto, DescuentoCupon, CostoEnvio, TotalPedido, MontoIVAIncluido,
        IDDireccionCliente, EntregaNombreRecibe, EntregaTelefono, EntregaDepartamento,
        EntregaMunicipio, EntregaZona, EntregaDireccionExacta, EntregaReferencias,
        ClaveIdempotencia, NotasCliente, FechaConfirmacionPago
    )
    VALUES (
        @NumeroPedido, @IDUsuario, @IDCarrito, 1, @IDMetodoPago, -- 1 = PAGADO / CONFIRMADO
        @IDCupon, @CodigoCupon, 'GTQ', 12.00,
        @SubtotalBruto, @DescuentoCupon, @CostoEnvio, @TotalPedido, @MontoIVA,
        @IDDireccionCliente, @NomRecibe, @Tel, @Depto,
        @Muni, @Zona, @DirExacta, @Ref,
        @ClaveIdempotencia, @NotasCliente, SYSDATETIME()
    );

    DECLARE @IDPedido INT = SCOPE_IDENTITY();

    -- 2. Insertar Detalle de Líneas, descontar inventario y registrar Kardex (RF-03, RF-06)
    DECLARE @IDVariante INT, @Cantidad INT, @PrecioActual DECIMAL(12,2), @SKU VARCHAR(60), @NomProd NVARCHAR(200), @NomVar NVARCHAR(150);
    DECLARE @ExistFisicaActual INT, @ExistReservadaActual INT;

    DECLARE curLineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT 
            cd.IDVarianteProducto, cd.Cantidad, v.PrecioActual, v.SKU, 
            p.Nombre, v.NombreVariante, v.ExistenciaFisica, v.ExistenciaReservada
        FROM dbo.CarritoDetalle cd
        INNER JOIN dbo.VarianteProducto v WITH (UPDLOCK, ROWLOCK) ON cd.IDVarianteProducto = v.IDVarianteProducto
        INNER JOIN dbo.Producto p ON v.IDProducto = p.IDProducto
        WHERE cd.IDCarrito = @IDCarrito;

    OPEN curLineas;
    FETCH NEXT FROM curLineas INTO @IDVariante, @Cantidad, @PrecioActual, @SKU, @NomProd, @NomVar, @ExistFisicaActual, @ExistReservadaActual;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- distribucion del descuento de cupón en la línea para reportes contables
        DECLARE @DescuentoLinea DECIMAL(12,2) = 0.00;
        IF @SubtotalBruto > 0 AND @DescuentoCupon > 0
        BEGIN
            SET @DescuentoLinea = ROUND(((@Cantidad * @PrecioActual) / @SubtotalBruto) * @DescuentoCupon, 2);
        END;

        -- Congelar la línea del pedido
        INSERT INTO dbo.PedidoDetalle (
            IDPedido, IDVarianteProducto, SKUCongelado, NombreProductoCongelado,
            AtributosVarianteCongelados, CantidadComprada, CantidadDevuelta,
            PrecioUnitarioCongelado, DescuentoProrrateadoLinea
        )
        VALUES (
            @IDPedido, @IDVariante, @SKU, @NomProd,
            @NomVar, @Cantidad, 0,
            @PrecioActual, @DescuentoLinea
        );

        -- Descontar existencia física y liberar reserva
        DECLARE @NuevaFisica INT = @ExistFisicaActual - @Cantidad;
        DECLARE @NuevaReservada INT = CASE 
            WHEN @ExistReservadaActual >= @Cantidad THEN (@ExistReservadaActual - @Cantidad) 
            ELSE 0 
        END;

        UPDATE dbo.VarianteProducto
        SET ExistenciaFisica    = @NuevaFisica,
            ExistenciaReservada = @NuevaReservada,
            FechaModificacion   = SYSDATETIME()
        WHERE IDVarianteProducto = @IDVariante;

        -- Salida oficial en Kardex
        INSERT INTO dbo.MovimientoKardex (
            IDVarianteProducto, IDTipoMovimientoKardex, IDUsuario, IDPedido,
            Cantidad, FactorSigno, ExistenciaAnterior, ExistenciaNueva,
            CostoUnitario, Motivo
        )
        VALUES (
            @IDVariante, 2, @IDUsuario, @IDPedido,
            @Cantidad, -1, @ExistFisicaActual, @NuevaFisica,
            @PrecioActual, CONCAT(N'Venta confirmada en Pedido ', @NumeroPedido)
        );

        FETCH NEXT FROM curLineas INTO @IDVariante, @Cantidad, @PrecioActual, @SKU, @NomProd, @NomVar, @ExistFisicaActual, @ExistReservadaActual;
    END;

    CLOSE curLineas;
    DEALLOCATE curLineas;

    -- 3. Confirmar la reserva en ReservaInventario
    UPDATE dbo.ReservaInventario
    SET IDEstadoReserva = 2, IDPedidoAsociado = @IDPedido, FechaResolucion = SYSDATETIME() -- 2 = CONFIRMADA_PEDIDO
    WHERE IDCarrito = @IDCarrito AND IDEstadoReserva = 1;

    -- 4. Registrar uso del Cupón si aplica
    IF @IDCupon IS NOT NULL AND @DescuentoCupon > 0
    BEGIN
        INSERT INTO dbo.CuponUso (IDCupon, IDPedido, IDUsuario, MontoDescuentoAplicado)
        VALUES (@IDCupon, @IDPedido, @IDUsuario, @DescuentoCupon);

        UPDATE dbo.Cupon
        SET UsosActuales = UsosActuales + 1, FechaModificacion = SYSDATETIME()
        WHERE IDCupon = @IDCupon;
    END;

    -- 5. Registrar Transacción de Pago Aprobada
    INSERT INTO dbo.TransaccionPago (
        IDPedido, IDMetodoPago, ClaveIdempotenciaPago, MontoTransaccion,
        EstadoPago, ReferenciaAutorizacion, MensajeRespuesta
    )
    VALUES (
        @IDPedido, @IDMetodoPago, @ClaveIdempotencia, @TotalPedido,
        'APROBADO', CONCAT('AUTH-', SUBSTRING(REPLACE(NEWID(), '-', ''), 1, 8)), N'Cobro procesado exitosamente'
    );

    -- 6. Registrar en Historial de Estados del Pedido
    INSERT INTO dbo.PedidoHistorialEstado (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario, MotivoOComentario)
    VALUES (@IDPedido, NULL, 1, @IDUsuario, N'Pedido creado y pagado exitosamente en checkout');

    -- 7. Marcar Carrito como CONVERTIDO (3)
    UPDATE dbo.Carrito SET IDEstadoCarrito = 3, FechaUltimaActividad = SYSDATETIME() WHERE IDCarrito = @IDCarrito;

    COMMIT TRANSACTION;

    SELECT 
        p.IDPedido,
        p.NumeroPedido,
        p.SubtotalBruto,
        p.DescuentoCupon,
        p.CostoEnvio,
        p.TotalPedido,
        p.MontoIVAIncluido,
        e.Nombre AS EstadoPedido,
        p.FechaCreacion,
        0 AS EsRespuestaIdempotente
    FROM dbo.Pedido p
    INNER JOIN dbo.EstadoPedido e ON p.IDEstadoPedido = e.IDEstadoPedido
    WHERE p.IDPedido = @IDPedido;
END;
GO

/*==============================================================================
  4. SP_Pedidos_AvanzarEstado 
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Pedidos_AvanzarEstado
    @IDPedido         INT,
    @IDEstadoNuevo    TINYINT,
    @IDUsuarioOperador INT,
    @Motivo           NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @IDEstadoActual TINYINT;
    SELECT @IDEstadoActual = IDEstadoPedido FROM dbo.Pedido WHERE IDPedido = @IDPedido;

    IF @IDEstadoActual IS NULL
    BEGIN
        ;THROW 50060, N'El pedido especificado no existe.', 1;
    END;

    -- una transición de estado no permitida se rechaza en el backend y en la BD
    IF NOT EXISTS (
        SELECT 1 FROM dbo.TransicionEstadoPedido 
        WHERE IDEstadoOrigen = @IDEstadoActual AND IDEstadoDestino = @IDEstadoNuevo AND Activo = 1
    )
    BEGIN
        DECLARE @MsjTransicion NVARCHAR(300) = CONCAT(
            N'Transición no permitida desde el estado actual (', @IDEstadoActual, N') hacia el estado (', @IDEstadoNuevo, N').'
        );
        THROW 50061, @MsjTransicion, 1;
    END;

    BEGIN TRANSACTION;

    UPDATE dbo.Pedido
    SET IDEstadoPedido = @IDEstadoNuevo,
        FechaDespacho = CASE WHEN @IDEstadoNuevo = 3 THEN SYSDATETIME() ELSE FechaDespacho END,
        FechaEntrega  = CASE WHEN @IDEstadoNuevo = 4 THEN SYSDATETIME() ELSE FechaEntrega END,
        FechaModificacion = SYSDATETIME()
    WHERE IDPedido = @IDPedido;

    -- Registrar en PedidoHistorialEstado
    INSERT INTO dbo.PedidoHistorialEstado (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario, MotivoOComentario)
    VALUES (@IDPedido, @IDEstadoActual, @IDEstadoNuevo, @IDUsuarioOperador, @Motivo);

    COMMIT TRANSACTION;

    SELECT 
        p.IDPedido, p.NumeroPedido, e.Codigo AS CodigoEstado, e.Nombre AS NombreEstado, p.FechaModificacion
    FROM dbo.Pedido p
    INNER JOIN dbo.EstadoPedido e ON p.IDEstadoPedido = e.IDEstadoPedido
    WHERE p.IDPedido = @IDPedido;
END;
GO

/*==============================================================================
  5. SP_Pedidos_CancelarPedido 
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Pedidos_CancelarPedido
    @IDPedido   INT,
    @IDUsuario  INT,
    @Motivo     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo))) < 5
    BEGIN
        ;THROW 50062, N'La cancelación de un pedido exige un motivo explicativo.', 1;
    END;

    DECLARE @IDEstadoActual TINYINT, @NumeroPedido VARCHAR(30);
    SELECT @IDEstadoActual = IDEstadoPedido, @NumeroPedido = NumeroPedido FROM dbo.Pedido WHERE IDPedido = @IDPedido;

    -- Un pedido puede cancelarse mientras no haya sido despachado
    IF @IDEstadoActual NOT IN (1, 2) -- Solo PAGADO (1) o EN_PREPARACION (2)
    BEGIN
        ;THROW 50063, N'El pedido ya fue despachado o finalizado y no puede ser cancelado.', 1;
    END;

    BEGIN TRANSACTION;

    -- 1. Reintegrar inventario al Kardex por cada línea del pedido (5 = ENTRADA_CANCELACION)
    DECLARE @IDVariante INT, @Cantidad INT, @PrecioCongelado DECIMAL(12,2), @FisicaActual INT;

    DECLARE curCancel CURSOR LOCAL FAST_FORWARD FOR
        SELECT pd.IDVarianteProducto, pd.CantidadComprada, pd.PrecioUnitarioCongelado, v.ExistenciaFisica
        FROM dbo.PedidoDetalle pd
        INNER JOIN dbo.VarianteProducto v WITH (UPDLOCK, ROWLOCK) ON pd.IDVarianteProducto = v.IDVarianteProducto
        WHERE pd.IDPedido = @IDPedido;

    OPEN curCancel;
    FETCH NEXT FROM curCancel INTO @IDVariante, @Cantidad, @PrecioCongelado, @FisicaActual;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE dbo.VarianteProducto
        SET ExistenciaFisica  = ExistenciaFisica + @Cantidad,
            FechaModificacion = SYSDATETIME()
        WHERE IDVarianteProducto = @IDVariante;

        INSERT INTO dbo.MovimientoKardex (
            IDVarianteProducto, IDTipoMovimientoKardex, IDUsuario, IDPedido,
            Cantidad, FactorSigno, ExistenciaAnterior, ExistenciaNueva,
            CostoUnitario, Motivo
        )
        VALUES (
            @IDVariante, 5, @IDUsuario, @IDPedido,
            @Cantidad, 1, @FisicaActual, (@FisicaActual + @Cantidad),
            @PrecioCongelado, CONCAT(N'Reintegro por cancelación de pedido ', @NumeroPedido, N': ', @Motivo)
        );

        FETCH NEXT FROM curCancel INTO @IDVariante, @Cantidad, @PrecioCongelado, @FisicaActual;
    END;

    CLOSE curCancel;
    DEALLOCATE curCancel;

    -- 2. Cambiar estado a CANCELADO (7)
    UPDATE dbo.Pedido
    SET IDEstadoPedido    = 7,
        FechaCancelacion  = SYSDATETIME(),
        MotivoCancelacion = @Motivo,
        FechaModificacion = SYSDATETIME()
    WHERE IDPedido = @IDPedido;

    INSERT INTO dbo.PedidoHistorialEstado (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario, MotivoOComentario)
    VALUES (@IDPedido, @IDEstadoActual, 7, @IDUsuario, @Motivo);

    COMMIT TRANSACTION;

    SELECT @IDPedido AS IDPedido, @NumeroPedido AS NumeroPedido, N'Pedido cancelado y existencias reintegradas al Kardex.' AS Mensaje;
END;
GO

/*==============================================================================
  6. SP_Pedidos_RegistrarDevolucion 
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Pedidos_RegistrarDevolucion
    @IDPedido           INT,
    @IDPedidoDetalle    INT,
    @CantidadDevolver   INT,
    @Motivo             NVARCHAR(500),
    @IDUsuarioOperador  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @CantidadDevolver <= 0
    BEGIN
        ;THROW 50070, N'La cantidad a devolver debe ser mayor a cero.', 1;
    END;

    DECLARE @IDEstadoPedido TINYINT, @NumeroPedido VARCHAR(30);
    SELECT @IDEstadoPedido = IDEstadoPedido, @NumeroPedido = NumeroPedido FROM dbo.Pedido WHERE IDPedido = @IDPedido;

    -- Solo pedidos entregados permiten devolución
    IF @IDEstadoPedido NOT IN (4, 5) -- ENTREGADO (4) o DEVUELTO_PARCIAL (5)
    BEGIN
        ;THROW 50071, N'Solo se pueden procesar devoluciones sobre pedidos que ya hayan sido entregados.', 1;
    END;

    DECLARE @IDVariante INT, @Comprada INT, @DevueltaActual INT, @PrecioUnitario DECIMAL(12,2), @FisicaActual INT;

    SELECT 
        @IDVariante       = pd.IDVarianteProducto,
        @Comprada         = pd.CantidadComprada,
        @DevueltaActual   = pd.CantidadDevuelta,
        @PrecioUnitario   = pd.PrecioUnitarioCongelado,
        @FisicaActual     = v.ExistenciaFisica
    FROM dbo.PedidoDetalle pd
    INNER JOIN dbo.VarianteProducto v WITH (UPDLOCK, ROWLOCK) ON pd.IDVarianteProducto = v.IDVarianteProducto
    WHERE pd.IDPedidoDetalle = @IDPedidoDetalle AND pd.IDPedido = @IDPedido;

    IF @IDVariante IS NULL
    BEGIN
        ;THROW 50072, N'La línea de pedido especificada no existe.', 1;
    END;

    --  No se puede devolver más cantidad de la vendida en cada línea del pedido
    IF (@DevueltaActual + @CantidadDevolver) > @Comprada
    BEGIN
        DECLARE @MsjDev NVARCHAR(300) = CONCAT(
            N'No se puede devolver más de lo comprado. Compradas: ', @Comprada, 
            N', ya devueltas: ', @DevueltaActual, N', solicitadas a devolver: ', @CantidadDevolver, N'.'
        );
        THROW 50073, @MsjDev, 1;
    END;

    BEGIN TRANSACTION;

    DECLARE @MontoReembolsoLinea DECIMAL(12,2) = CAST(@CantidadDevolver * @PrecioUnitario AS DECIMAL(12,2));
    DECLARE @NumeroDevolucion VARCHAR(30) = CONCAT('DEV-', FORMAT(SYSDATETIME(), 'yyyyMMdd'), '-', SUBSTRING(REPLACE(NEWID(), '-', ''), 1, 6));

    -- 1. Crear registro de Devolución
    INSERT INTO dbo.Devolucion (
        NumeroDevolucion, IDPedido, IDEstadoDevolucion, IDUsuarioSolicita,
        IDUsuarioProcesa, EsDevolucionTotal, MotivoDevolucion, MontoTotalReembolsado, FechaProcesamiento
    )
    VALUES (
        @NumeroDevolucion, @IDPedido, 2, @IDUsuarioOperador, -- 2 = APROBADA
        @IDUsuarioOperador, 0, @Motivo, @MontoReembolsoLinea, SYSDATETIME()
    );

    DECLARE @IDDevolucion INT = SCOPE_IDENTITY();

    INSERT INTO dbo.DevolucionDetalle (IDDevolucion, IDPedidoDetalle, IDVarianteProducto, CantidadDevuelta, MontoReembolsadoLinea, MotivoLinea)
    VALUES (@IDDevolucion, @IDPedidoDetalle, @IDVariante, @CantidadDevolver, @MontoReembolsoLinea, @Motivo);

    -- 2. Actualizar línea del pedido
    UPDATE dbo.PedidoDetalle
    SET CantidadDevuelta = CantidadDevuelta + @CantidadDevolver
    WHERE IDPedidoDetalle = @IDPedidoDetalle;

    -- 3. Reintegrar inventario al Kardex (RF-03: 6 = ENTRADA_DEVOLUCION)
    UPDATE dbo.VarianteProducto
    SET ExistenciaFisica  = ExistenciaFisica + @CantidadDevolver,
        FechaModificacion = SYSDATETIME()
    WHERE IDVarianteProducto = @IDVariante;

    INSERT INTO dbo.MovimientoKardex (
        IDVarianteProducto, IDTipoMovimientoKardex, IDUsuario, IDPedido, IDDevolucion,
        Cantidad, FactorSigno, ExistenciaAnterior, ExistenciaNueva, CostoUnitario, Motivo
    )
    VALUES (
        @IDVariante, 6, @IDUsuarioOperador, @IDPedido, @IDDevolucion,
        @CantidadDevolver, 1, @FisicaActual, (@FisicaActual + @CantidadDevolver),
        @PrecioUnitario, CONCAT(N'Devolución aprobada ', @NumeroDevolucion, N' en Pedido ', @NumeroPedido, N': ', @Motivo)
    );

    -- 4. Actualizar total devuelto acumulado y estado del pedido
    UPDATE dbo.Pedido
    SET TotalDevueltoAcumulado = TotalDevueltoAcumulado + @MontoReembolsoLinea,
        FechaModificacion      = SYSDATETIME()
    WHERE IDPedido = @IDPedido;

    -- Determinar si el pedido pasó a DEVUELTO_TOTAL (6) o DEVUELTO_PARCIAL (5)
    DECLARE @TotalComprado INT = (SELECT SUM(CantidadComprada) FROM dbo.PedidoDetalle WHERE IDPedido = @IDPedido);
    DECLARE @TotalDevuelto INT = (SELECT SUM(CantidadDevuelta) FROM dbo.PedidoDetalle WHERE IDPedido = @IDPedido);
    DECLARE @NuevoEstado TINYINT = CASE WHEN @TotalDevuelto >= @TotalComprado THEN 6 ELSE 5 END;

    IF @IDEstadoPedido <> @NuevoEstado
    BEGIN
        UPDATE dbo.Pedido SET IDEstadoPedido = @NuevoEstado WHERE IDPedido = @IDPedido;
        INSERT INTO dbo.PedidoHistorialEstado (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario, MotivoOComentario)
        VALUES (@IDPedido, @IDEstadoPedido, @NuevoEstado, @IDUsuarioOperador, CONCAT(N'Actualización por devolución ', @NumeroDevolucion));
    END;

    COMMIT TRANSACTION;

    SELECT 
        @IDDevolucion AS IDDevolucion,
        @NumeroDevolucion AS NumeroDevolucion,
        @CantidadDevolver AS CantidadDevuelta,
        @MontoReembolsoLinea AS MontoReembolsado,
        N'Devolución procesada y unidades reintegradas al Kardex.' AS Mensaje;
END;
GO

/*==============================================================================
  7. SP_Inventario_LiberarReservasVencidas
     Una reserva vencida libera la existencia sin intervención manual
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Inventario_LiberarReservasVencidas
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ReservasExpiradas TABLE (
        IDReserva           BIGINT,
        IDVarianteProducto  INT,
        Cantidad            INT
    );

    BEGIN TRANSACTION;

    -- Seleccionar y bloquear reservas activas cuya vigencia ya caducó
    INSERT INTO @ReservasExpiradas (IDReserva, IDVarianteProducto, Cantidad)
    SELECT IDReservaInventario, IDVarianteProducto, CantidadReservada
    FROM dbo.ReservaInventario WITH (UPDLOCK, ROWLOCK)
    WHERE IDEstadoReserva = 1 AND FechaExpiracion < SYSDATETIME();

    IF EXISTS (SELECT 1 FROM @ReservasExpiradas)
    BEGIN
        -- Devolver las unidades reservadas a ExistenciaDisponible
        UPDATE v
        SET v.ExistenciaReservada = CASE 
            WHEN v.ExistenciaReservada >= r.CantidadTotal 
            THEN (v.ExistenciaReservada - r.CantidadTotal)
            ELSE 0 
        END,
        v.FechaModificacion = SYSDATETIME()
        FROM dbo.VarianteProducto v
        INNER JOIN (
            SELECT IDVarianteProducto, SUM(Cantidad) AS CantidadTotal
            FROM @ReservasExpiradas
            GROUP BY IDVarianteProducto
        ) r ON v.IDVarianteProducto = r.IDVarianteProducto;

        -- Marcar reservas como EXPIRADA (3)
        UPDATE r
        SET r.IDEstadoReserva = 3,
            r.FechaResolucion = SYSDATETIME()
        FROM dbo.ReservaInventario r
        INNER JOIN @ReservasExpiradas exp ON r.IDReservaInventario = exp.IDReserva;
    END;

    COMMIT TRANSACTION;

    SELECT COUNT(1) AS TotalReservasLiberadas FROM @ReservasExpiradas;
END;
GO