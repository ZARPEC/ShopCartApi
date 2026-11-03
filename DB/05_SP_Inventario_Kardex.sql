USE ShopCartDB;
GO

/*==============================================================================
  1. SP_Inventario_RegistrarMovimiento
     Permite a OPERADOR y ADMINISTRADOR registrar:
     - 1 = ENTRADA_COMPRA
     - 3 = AJUSTE_POSITIVO
     - 4 = AJUSTE_NEGATIVO
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Inventario_RegistrarMovimiento
    @IDVarianteProducto     INT,
    @CodigoTipoMovimiento   VARCHAR(40),    -- 'ENTRADA_COMPRA', 'AJUSTE_POSITIVO', 'AJUSTE_NEGATIVO'
    @Cantidad               INT,
    @Motivo                 NVARCHAR(500),
    @CostoUnitario          DECIMAL(12,2) = NULL,
    @IDUsuario              INT,
    @DireccionIP            VARCHAR(45)   = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Cantidad <= 0
    BEGIN
        ;THROW 50020, N'La cantidad del movimiento debe ser mayor a cero.', 1;
    END;

    IF @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo))) < 5
    BEGIN
        ;THROW 50021, N'Todo movimiento o ajuste manual exige un motivo descriptivo (mínimo 5 caracteres).', 1;
    END;

    DECLARE @IDTipoMovimiento TINYINT;
    DECLARE @FactorSigno SMALLINT;

    SELECT 
        @IDTipoMovimiento = IDTipoMovimientoKardex,
        @FactorSigno      = FactorSigno
    FROM dbo.TipoMovimientoKardex
    WHERE Codigo = @CodigoTipoMovimiento
      AND Codigo IN ('ENTRADA_COMPRA', 'AJUSTE_POSITIVO', 'AJUSTE_NEGATIVO')
      AND Activo = 1;

    IF @IDTipoMovimiento IS NULL
    BEGIN
        ;THROW 50022, N'El tipo de movimiento indicado no es válido para operación manual.', 1;
    END;

    BEGIN TRANSACTION;

    DECLARE @ExistenciaFisicaActual INT;
    DECLARE @ExistenciaReservadaActual INT;
    DECLARE @SKU VARCHAR(60);

    -- Bloqueo de fila (UPDLOCK, ROWLOCK) para evitar condiciones de carrera en accesos simultáneos
    SELECT 
        @ExistenciaFisicaActual    = ExistenciaFisica,
        @ExistenciaReservadaActual = ExistenciaReservada,
        @SKU                       = SKU
    FROM dbo.VarianteProducto WITH (UPDLOCK, ROWLOCK)
    WHERE IDVarianteProducto = @IDVarianteProducto;

    IF @SKU IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50023, N'La variante de producto especificada no existe.', 1;
    END;

    DECLARE @ExistenciaNueva INT = @ExistenciaFisicaActual + (@Cantidad * @FactorSigno);

    IF @ExistenciaNueva < 0
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50024, N'El ajuste no puede dejar la existencia física en negativo.', 1;
    END;

    IF @ExistenciaNueva < @ExistenciaReservadaActual
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50025, N'El ajuste negativo no puede comprometer unidades que se encuentran reservadas en checkout.', 1;
    END;

    -- 1. Actualizar existencia en VarianteProducto
    UPDATE dbo.VarianteProducto
    SET ExistenciaFisica  = @ExistenciaNueva,
        FechaModificacion = SYSDATETIME()
    WHERE IDVarianteProducto = @IDVarianteProducto;

    -- 2. Insertar en MovimientoKardex
    INSERT INTO dbo.MovimientoKardex (
        IDVarianteProducto,
        IDTipoMovimientoKardex,
        IDUsuario,
        Cantidad,
        FactorSigno,
        ExistenciaAnterior,
        ExistenciaNueva,
        CostoUnitario,
        Motivo
    )
    VALUES (
        @IDVarianteProducto,
        @IDTipoMovimiento,
        @IDUsuario,
        @Cantidad,
        @FactorSigno,
        @ExistenciaFisicaActual,
        @ExistenciaNueva,
        @CostoUnitario,
        LTRIM(RTRIM(@Motivo))
    );

    DECLARE @IDMovimientoKardex BIGINT = SCOPE_IDENTITY();

    -- 3. Registrar en BitacoraAuditoria
    DECLARE @IDModuloInventario TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'INVENTARIO');

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema,
        IDUsuario,
        Entidad,
        IDRegistroEntidad,
        Accion,
        ResumenCambio,
        ValorAnteriorJson,
        ValorNuevoJson,
        DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloInventario, 3),
        @IDUsuario,
        'VarianteProducto',
        CAST(@IDVarianteProducto AS VARCHAR(100)),
        'AJUSTE_EXISTENCIA',
        CONCAT(N'Movimiento ', @CodigoTipoMovimiento, N' en SKU ', @SKU, N': ', @ExistenciaFisicaActual, N' -> ', @ExistenciaNueva),
        (SELECT @SKU AS SKU, @ExistenciaFisicaActual AS ExistenciaFisica FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT @SKU AS SKU, @ExistenciaNueva AS ExistenciaFisica, @CodigoTipoMovimiento AS TipoMovimiento, @Cantidad AS Cantidad, @Motivo AS Motivo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT 
        @IDMovimientoKardex AS IDMovimientoKardex,
        @IDVarianteProducto AS IDVarianteProducto,
        @SKU AS SKU,
        @CodigoTipoMovimiento AS TipoMovimiento,
        @ExistenciaFisicaActual AS ExistenciaAnterior,
        @ExistenciaNueva AS ExistenciaNueva,
        (@ExistenciaNueva - @ExistenciaReservadaActual) AS ExistenciaDisponible;
END;
GO

/*==============================================================================
  2. SP_Inventario_ObtenerKardexPorVariante
     Devuelve el estado actual de la variante 
	 y el historial paginado de movimientos.
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Inventario_ObtenerKardexPorVariante
    @IDVarianteProducto INT,
    @Pagina             INT = 1,
    @Limite             INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @Limite < 1 SET @Limite = 20;
    IF @Limite > 100 SET @Limite = 100;

    DECLARE @Offset INT = (@Pagina - 1) * @Limite;

    -- 1. Resumen de cuadratura de la variante (Criterio RF-03: Existencia actual = Suma del Kardex)
    SELECT 
        v.IDVarianteProducto,
        v.SKU,
        p.Nombre AS NombreProducto,
        v.NombreVariante,
        v.ExistenciaFisica,
        v.ExistenciaReservada,
        v.ExistenciaDisponible,
        ISNULL((SELECT SUM(k.CantidadConSigno) FROM dbo.MovimientoKardex k WHERE k.IDVarianteProducto = v.IDVarianteProducto), 0) AS SumaMovimientosKardex,
        CASE 
            WHEN v.ExistenciaFisica = ISNULL((SELECT SUM(k.CantidadConSigno) FROM dbo.MovimientoKardex k WHERE k.IDVarianteProducto = v.IDVarianteProducto), 0)
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS KardexCuadrado
    FROM dbo.VarianteProducto v
    INNER JOIN dbo.Producto p ON v.IDProducto = p.IDProducto
    WHERE v.IDVarianteProducto = @IDVarianteProducto;

    -- 2. Historial de movimientos del Kardex paginado
    DECLARE @TotalMovimientos INT = (
        SELECT COUNT(1) FROM dbo.MovimientoKardex WHERE IDVarianteProducto = @IDVarianteProducto
    );

    SELECT 
        k.IDMovimientoKardex,
        t.Codigo AS CodigoTipoMovimiento,
        t.Nombre AS NombreTipoMovimiento,
        k.Cantidad,
        k.FactorSigno,
        k.CantidadConSigno,
        k.ExistenciaAnterior,
        k.ExistenciaNueva,
        k.CostoUnitario,
        k.Motivo,
        k.IDPedido,
        k.IDDevolucion,
        u.IDUsuario,
        CONCAT(u.Nombres,'', u.Apellidos) AS NombreUsuario,
        k.FechaMovimiento,
        @TotalMovimientos AS TotalRegistros,
        CEILING(CAST(@TotalMovimientos AS FLOAT) / @Limite) AS TotalPaginas,
        @Pagina AS PaginaActual
    FROM dbo.MovimientoKardex k
    INNER JOIN dbo.TipoMovimientoKardex t ON k.IDTipoMovimientoKardex = t.IDTipoMovimientoKardex
    INNER JOIN dbo.Usuario u ON k.IDUsuario = u.IDUsuario
    WHERE k.IDVarianteProducto = @IDVarianteProducto
    ORDER BY k.IDMovimientoKardex DESC
    OFFSET @Offset ROWS
    FETCH NEXT @Limite ROWS ONLY;
END;
GO