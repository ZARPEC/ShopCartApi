USE ShopCartDB;
GO

/*==============================================================================
  1. VISTAS OBLIGATORIAS SEGÚN ESTÁNDAR DE PÁGINA 10:
     - VW_Dashboard_VentasPorCategoria
     - VW_Pedidos_Historial
==============================================================================*/

-- 1.1 VW_Dashboard_VentasPorCategoria
-- RF-08 Criterio: Solo considera pedidos completados, excluye cancelados (7) y descuenta devoluciones
CREATE OR ALTER VIEW dbo.VW_Dashboard_VentasPorCategoria
AS
SELECT 
    c.IDCategoria,
    c.Nombre AS CategoriaNombre,
    c.Slug AS CategoriaSlug,
    COUNT(DISTINCT p.IDPedido) AS TotalPedidos,
    SUM(pd.CantidadNeta) AS UnidadesVendidasNetas,
    -- Venta neta en Quetzales descontando devoluciones
    SUM(pd.TotalNetaLinea) - ISNULL(SUM(ROUND((pd.TotalNetaLinea / NULLIF(p.SubtotalBruto, 0)) * p.TotalDevueltoAcumulado, 2)), 0) AS VentasNetasQuetzales
FROM dbo.Pedido p
INNER JOIN dbo.PedidoDetalle pd ON p.IDPedido = pd.IDPedido
INNER JOIN dbo.VarianteProducto v ON pd.IDVarianteProducto = v.IDVarianteProducto
INNER JOIN dbo.Producto pr ON v.IDProducto = pr.IDProducto
INNER JOIN dbo.Categoria c ON pr.IDCategoria = c.IDCategoria
WHERE p.IDEstadoPedido NOT IN (7) -- Excluye CANCELADO
GROUP BY c.IDCategoria, c.Nombre, c.Slug;
GO

-- 1.2 VW_Pedidos_Historial
-- Vista consolidada del historial de pedidos con desglose de cliente, dirección, estado y montos netos
CREATE OR ALTER VIEW dbo.VW_Pedidos_Historial
AS
SELECT 
    p.IDPedido,
    p.NumeroPedido,
    p.FechaCreacion,
    p.FechaConfirmacionPago,
    p.FechaDespacho,
    p.FechaEntrega,
    p.FechaCancelacion,
    p.IDUsuario AS IDCliente,
    CONCAT(u.Nombres,' ',U.Apellidos) AS ClienteNombre,
    u.CorreoElectronico AS ClienteCorreo,
    p.IDEstadoPedido,
    e.Codigo AS CodigoEstado,
    e.Nombre AS NombreEstado,
    p.IDMetodoPago,
    m.Nombre AS MetodoPagoNombre,
    p.Moneda,
    p.SubtotalBruto,
    p.DescuentoCupon,
    p.CodigoCuponCongelado AS CuponAplicado,
    p.CostoEnvio,
    p.TotalPedido,
    p.TotalDevueltoAcumulado,
    (p.TotalPedido - p.TotalDevueltoAcumulado) AS TotalNetoFinal,
    p.EntregaNombreRecibe,
    p.EntregaTelefono,
    p.EntregaDepartamento,
    p.EntregaMunicipio,
    p.EntregaZona,
    p.EntregaDireccionExacta,
    p.ClaveIdempotencia
FROM dbo.Pedido p
INNER JOIN dbo.Usuario u ON p.IDUsuario = u.IDUsuario
INNER JOIN dbo.EstadoPedido e ON p.IDEstadoPedido = e.IDEstadoPedido
INNER JOIN dbo.MetodoPago m ON p.IDMetodoPago = m.IDMetodoPago;
GO

/*==============================================================================
  2. SP_Dashboard_MetricasGenerales (RF-08: Ventas por día, semana, mes, carritos)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Dashboard_MetricasGenerales
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @HoyInicio DATETIME2(3) = CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2(3));
    DECLARE @SemanaInicio DATETIME2(3) = DATEADD(DAY, -7, SYSDATETIME());
    DECLARE @MesInicio DATETIME2(3) = DATEADD(MONTH, -1, SYSDATETIME());

    -- Métricas del Día de hoy
    DECLARE @VentasHoy DECIMAL(12,2), @PedidosHoy INT;
    SELECT 
        @VentasHoy  = ISNULL(SUM(TotalPedido - TotalDevueltoAcumulado), 0.00),
        @PedidosHoy = COUNT(1)
    FROM dbo.Pedido
    WHERE FechaCreacion >= @HoyInicio AND IDEstadoPedido NOT IN (7);

    -- Métricas de la Semana (últimos 7 días)
    DECLARE @VentasSemana DECIMAL(12,2), @PedidosSemana INT;
    SELECT 
        @VentasSemana  = ISNULL(SUM(TotalPedido - TotalDevueltoAcumulado), 0.00),
        @PedidosSemana = COUNT(1)
    FROM dbo.Pedido
    WHERE FechaCreacion >= @SemanaInicio AND IDEstadoPedido NOT IN (7);

    -- Métricas del Mes (últimos 30 días)
    DECLARE @VentasMes DECIMAL(12,2), @PedidosMes INT;
    SELECT 
        @VentasMes  = ISNULL(SUM(TotalPedido - TotalDevueltoAcumulado), 0.00),
        @PedidosMes = COUNT(1)
    FROM dbo.Pedido
    WHERE FechaCreacion >= @MesInicio AND IDEstadoPedido NOT IN (7);

    -- Ticket promedio general (Ventas totales entre pedidos completados, Glosario pág. 4)
    DECLARE @TicketPromedio DECIMAL(12,2) = 0.00;
    IF @PedidosMes > 0
    BEGIN
        SET @TicketPromedio = ROUND(@VentasMes / @PedidosMes, 2);
    END;

    -- Conteo de Carritos Abandonados (Glosario pág. 4 y RF-08)
    -- Carritos activos con ítems pero sin actividad durante el periodo configurable
    DECLARE @MinutosAbandono INT = 60;
    SELECT @MinutosAbandono = CAST(Valor AS INT)
    FROM dbo.ConfiguracionSistema
    WHERE Clave = 'CARRITO_ABANDONADO_MINUTOS' AND Activo = 1;

    DECLARE @TotalCarritosAbandonados INT;
    SELECT @TotalCarritosAbandonados = COUNT(DISTINCT c.IDCarrito)
    FROM dbo.Carrito c
    INNER JOIN dbo.CarritoDetalle cd ON c.IDCarrito = cd.IDCarrito
    WHERE c.IDEstadoCarrito IN (1, 4) -- ACTIVO o marcado ABANDONADO
      AND c.FechaUltimaActividad < DATEADD(MINUTE, -@MinutosAbandono, SYSDATETIME());

    SELECT 
        @VentasHoy AS VentasHoyGTQ,
        @PedidosHoy AS PedidosHoy,
        @VentasSemana AS VentasSemanaGTQ,
        @PedidosSemana AS PedidosSemana,
        @VentasMes AS VentasMesGTQ,
        @PedidosMes AS PedidosMes,
        @TicketPromedio AS TicketPromedioMesGTQ,
        @TotalCarritosAbandonados AS CarritosAbandonadosActualmente;
END;
GO

/*==============================================================================
  3. SP_Dashboard_Top10Productos (RF-08: Los 10 productos más vendidos)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Dashboard_Top10Productos
    @FechaInicio DATETIME2(3) = NULL,
    @FechaFin    DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaInicio IS NULL SET @FechaInicio = DATEADD(MONTH, -1, SYSDATETIME());
    IF @FechaFin IS NULL SET @FechaFin = SYSDATETIME();

    SELECT TOP 10
        pr.IDProducto,
        pr.Nombre AS NombreProducto,
        pr.Slug,
        pr.Marca,
        c.Nombre AS CategoriaNombre,
        SUM(pd.CantidadNeta) AS UnidadesVendidasNetas,
        SUM(pd.TotalNetaLinea) AS TotalVentasQuetzales,
        (SELECT TOP 1 UrlImagen FROM dbo.ProductoImagen WHERE IDProducto = pr.IDProducto AND EsPrincipal = 1) AS UrlImagenPrincipal
    FROM dbo.PedidoDetalle pd
    INNER JOIN dbo.Pedido p ON pd.IDPedido = p.IDPedido
    INNER JOIN dbo.VarianteProducto v ON pd.IDVarianteProducto = v.IDVarianteProducto
    INNER JOIN dbo.Producto pr ON v.IDProducto = pr.IDProducto
    INNER JOIN dbo.Categoria c ON pr.IDCategoria = c.IDCategoria
    WHERE p.FechaCreacion BETWEEN @FechaInicio AND @FechaFin
      AND p.IDEstadoPedido NOT IN (7) -- Excluye cancelados
    GROUP BY pr.IDProducto, pr.Nombre, pr.Slug, pr.Marca, c.Nombre
    ORDER BY SUM(pd.CantidadNeta) DESC, SUM(pd.TotalNetaLinea) DESC;
END;
GO

/*==============================================================================
  4. SP_Dashboard_ListarPedidos (RF-08: Paginación y Filtros en Servidor)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Dashboard_ListarPedidos
    @IDEstadoPedido  TINYINT      = NULL,
    @IDCliente       INT          = NULL,
    @FechaInicio     DATETIME2(3) = NULL,
    @FechaFin        DATETIME2(3) = NULL,
    @Pagina          INT          = 1,
    @Limite          INT          = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @Limite < 1 SET @Limite = 10;
    IF @Limite > 100 SET @Limite = 100;

    DECLARE @Offset INT = (@Pagina - 1) * @Limite;
    DECLARE @TotalRegistros INT;

    SELECT @TotalRegistros = COUNT(1)
    FROM dbo.VW_Pedidos_Historial
    WHERE (@IDEstadoPedido IS NULL OR IDEstadoPedido = @IDEstadoPedido)
      AND (@IDCliente IS NULL OR IDCliente = @IDCliente)
      AND (@FechaInicio IS NULL OR FechaCreacion >= @FechaInicio)
      AND (@FechaFin IS NULL OR FechaCreacion <= @FechaFin);

    SELECT 
        IDPedido,
        NumeroPedido,
        FechaCreacion,
        ClienteNombre,
        ClienteCorreo,
        IDEstadoPedido,
        NombreEstado,
        TotalPedido,
        TotalDevueltoAcumulado,
        TotalNetoFinal,
        EntregaMunicipio,
        EntregaDepartamento,
        @TotalRegistros AS TotalRegistros,
        CEILING(CAST(@TotalRegistros AS FLOAT) / @Limite) AS TotalPaginas,
        @Pagina AS PaginaActual
    FROM dbo.VW_Pedidos_Historial
    WHERE (@IDEstadoPedido IS NULL OR IDEstadoPedido = @IDEstadoPedido)
      AND (@IDCliente IS NULL OR IDCliente = @IDCliente)
      AND (@FechaInicio IS NULL OR FechaCreacion >= @FechaInicio)
      AND (@FechaFin IS NULL OR FechaCreacion <= @FechaFin)
    ORDER BY FechaCreacion DESC
    OFFSET @Offset ROWS
    FETCH NEXT @Limite ROWS ONLY;
END;
GO

/*==============================================================================
  5. SP_Bitacora_ConsultarAuditoria (RF-09: Trazabilidad inmutable para Admin)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Bitacora_ConsultarAuditoria
    @CodigoModulo VARCHAR(40)  = NULL,
    @Entidad      VARCHAR(100) = NULL,
    @FechaInicio  DATETIME2(3) = NULL,
    @FechaFin     DATETIME2(3) = NULL,
    @Pagina       INT          = 1,
    @Limite       INT          = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @Limite < 1 SET @Limite = 20;
    IF @Limite > 100 SET @Limite = 100;

    DECLARE @Offset INT = (@Pagina - 1) * @Limite;
    DECLARE @TotalRegistros INT;

    SELECT @TotalRegistros = COUNT(1)
    FROM dbo.BitacoraAuditoria b
    INNER JOIN dbo.ModuloSistema m ON b.IDModuloSistema = m.IDModuloSistema
    WHERE (@CodigoModulo IS NULL OR m.Codigo = @CodigoModulo)
      AND (@Entidad IS NULL OR b.Entidad = @Entidad)
      AND (@FechaInicio IS NULL OR b.FechaRegistro >= @FechaInicio)
      AND (@FechaFin IS NULL OR b.FechaRegistro <= @FechaFin);

    SELECT 
        b.IDBitacoraAuditoria,
        m.Codigo AS CodigoModulo,
        m.Nombre AS NombreModulo,
        u.IDUsuario,
        CONCAT(u.Nombres,' ',U.Apellidos) AS UsuarioNombre,
        b.Entidad,
        b.IDRegistroEntidad,
        b.Accion,
        b.ResumenCambio,
        b.ValorAnteriorJson,
        b.ValorNuevoJson,
        b.DireccionIP,
        b.FechaRegistro,
        @TotalRegistros AS TotalRegistros,
        CEILING(CAST(@TotalRegistros AS FLOAT) / @Limite) AS TotalPaginas,
        @Pagina AS PaginaActual
    FROM dbo.BitacoraAuditoria b
    INNER JOIN dbo.ModuloSistema m ON b.IDModuloSistema = m.IDModuloSistema
    INNER JOIN dbo.Usuario u ON b.IDUsuario = u.IDUsuario
    WHERE (@CodigoModulo IS NULL OR m.Codigo = @CodigoModulo)
      AND (@Entidad IS NULL OR b.Entidad = @Entidad)
      AND (@FechaInicio IS NULL OR b.FechaRegistro >= @FechaInicio)
      AND (@FechaFin IS NULL OR b.FechaRegistro <= @FechaFin)
    ORDER BY b.FechaRegistro DESC
    OFFSET @Offset ROWS
    FETCH NEXT @Limite ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_Dashboard_VentasPorCategoria
AS
BEGIN
    SET NOCOUNT ON;

    -- El SP consulta la vista internamente en SQL Server
    SELECT * 
    FROM dbo.VW_Dashboard_VentasPorCategoria 
    ORDER BY VentasNetasQuetzales DESC;
END;
GO