USE ShopCartDB;
GO

-- SP para que el Administrador agregue imágenes a un producto o variante
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_AgregarImagenProducto
    @IDProducto         INT,
    @IDVarianteProducto INT = NULL,
    @UrlImagen          NVARCHAR(500),
    @TextoAlternativo   NVARCHAR(200) = NULL,
    @EsPrincipal        BIT = 0,
    @OrdenVisualizacion SMALLINT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE IDProducto = @IDProducto)
    BEGIN
        ;THROW 50016, N'El producto especificado no existe.', 1;
    END;

    BEGIN TRANSACTION;

    -- Si esta nueva imagen se marca como principal, desmarcar la principal anterior de ese producto
    IF @EsPrincipal = 1
    BEGIN
        UPDATE dbo.ProductoImagen
        SET EsPrincipal = 0
        WHERE IDProducto = @IDProducto AND EsPrincipal = 1;
    END;

    INSERT INTO dbo.ProductoImagen (
        IDProducto, IDVarianteProducto, UrlImagen, 
        TextoAlternativo, EsPrincipal, OrdenVisualizacion, Activo
    )
    VALUES (
        @IDProducto, @IDVarianteProducto, @UrlImagen, 
        @TextoAlternativo, @EsPrincipal, @OrdenVisualizacion, 1
    );

    COMMIT TRANSACTION;

    SELECT SCOPE_IDENTITY() AS IDProductoImagen, @UrlImagen AS UrlImagen, @EsPrincipal AS EsPrincipal;
END;
GO

/*==============================================================================
  SP_Catalogo_CrearCategoria
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_CrearCategoria
    @Nombre           NVARCHAR(100),
    @Slug             VARCHAR(120),
    @Descripcion      NVARCHAR(400) = NULL,
    @IDCategoriaPadre INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.Categoria WHERE Slug = @Slug OR Nombre = @Nombre)
    BEGIN
        ;THROW 50011, N'Ya existe una categoría con ese nombre o slug.', 1;
    END;

    INSERT INTO dbo.Categoria (Nombre, Slug, Descripcion, IDCategoriaPadre, Activo)
    VALUES (@Nombre, @Slug, @Descripcion, @IDCategoriaPadre, 1);

    SELECT SCOPE_IDENTITY() AS IDCategoria, @Nombre AS Nombre, @Slug AS Slug;
END;
GO

/*==============================================================================
  SP_Catalogo_ListarCategorias
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ListarCategorias
    @SoloActivas BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        c.IDCategoria,
        c.IDCategoriaPadre,
        c.Nombre,
        c.Slug,
        c.Descripcion,
        c.Activo,
        (SELECT COUNT(1) FROM dbo.Producto p WHERE p.IDCategoria = c.IDCategoria AND p.Activo = 1) AS TotalProductos
    FROM dbo.Categoria c
    WHERE (@SoloActivas = 0 OR c.Activo = 1)
    ORDER BY c.Nombre ASC;
END;
GO

/*==============================================================================
  SP_Catalogo_CrearProducto
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_CrearProducto
    @IDCategoria   INT,
    @Nombre        NVARCHAR(200),
    @Slug          VARCHAR(220),
    @Descripcion   NVARCHAR(2000) = NULL,
    @Marca         NVARCHAR(100) = NULL,
    @PorcentajeIVA DECIMAL(5,2) = 12.00
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Categoria WHERE IDCategoria = @IDCategoria AND Activo = 1)
    BEGIN
        ;THROW 50012, N'La categoría especificada no existe o está inactiva.', 1;
    END;

    IF EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = @Slug)
    BEGIN
        ;THROW 50013, N'Ya existe un producto con ese slug.', 1;
    END;

    INSERT INTO dbo.Producto (IDCategoria, Nombre, Slug, Descripcion, Marca, PorcentajeIVA, Activo)
    VALUES (@IDCategoria, @Nombre, @Slug, @Descripcion, @Marca, @PorcentajeIVA, 1);

    SELECT SCOPE_IDENTITY() AS IDProducto, @Nombre AS Nombre, @Slug AS Slug;
END;
GO

/*==============================================================================
  SP_Catalogo_CrearVariante (Con registro automático en Kardex RF-03)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_CrearVariante
    @IDProducto          INT,
    @SKU                 VARCHAR(60),
    @NombreVariante      NVARCHAR(150),
    @PrecioActual        DECIMAL(12,2),
    @ExistenciaInicial   INT = 0,
    @StockMinimoAlerta   INT = 5,
    @IDUsuarioOperador   INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE IDProducto = @IDProducto)
    BEGIN
        ;THROW 50014, N'El producto padre no existe.', 1;
    END;

    IF @SKU IS NULL OR LTRIM(RTRIM(@SKU)) = ''
    BEGIN
        SET @SKU = 'SKU-' + CAST(@IDProducto AS VARCHAR(10)) + '-' + UPPER(SUBSTRING(REPLACE(NEWID(), '-', ''), 1, 6));
    END;


    IF EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = @SKU)
    BEGIN
        ;THROW 50015, N'El SKU especificado ya existe.', 1;
    END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.VarianteProducto (
        IDProducto, SKU, NombreVariante, PrecioActual, 
        ExistenciaFisica, ExistenciaReservada, StockMinimoAlerta, Activo
    )
    VALUES (
        @IDProducto, @SKU, @NombreVariante, @PrecioActual, 
        @ExistenciaInicial, 0, @StockMinimoAlerta, 1
    );

    DECLARE @IDVariante INT = SCOPE_IDENTITY();

    -- Registrar inventario inicial en Kardex si viene con stock (RF-03)
    IF @ExistenciaInicial > 0
    BEGIN
        INSERT INTO dbo.MovimientoKardex (
            IDVarianteProducto, IDTipoMovimientoKardex, IDUsuario,
            Cantidad, FactorSigno, ExistenciaAnterior, ExistenciaNueva,
            CostoUnitario, Motivo
        )
        VALUES (
            @IDVariante, 1, @IDUsuarioOperador, -- 1 = ENTRADA_COMPRA
            @ExistenciaInicial, 1, 0, @ExistenciaInicial,
            @PrecioActual, N'Inventario inicial al crear variante'
        );
    END;

    COMMIT TRANSACTION;

    SELECT @IDVariante AS IDVarianteProducto, @SKU AS SKU, @NombreVariante AS NombreVariante;
END;
GO

/*==============================================================================
   SP_Catalogo_ListarProductos 
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ListarProductos
    @BuscarTexto      NVARCHAR(100) = NULL,
    @SlugCategoria    VARCHAR(120)  = NULL,
    @PrecioMin        DECIMAL(12,2) = NULL,
    @PrecioMax        DECIMAL(12,2) = NULL,
    @SoloDisponibles  BIT           = 0,
    @Orden            VARCHAR(20)   = 'recientes',
    @Pagina           INT           = 1,
    @Limite           INT           = 12
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @Limite < 1 SET @Limite = 12;
    IF @Limite > 100 SET @Limite = 100;

    DECLARE @Offset INT = (@Pagina - 1) * @Limite;
    DECLARE @TotalRegistros INT;

    SELECT @TotalRegistros = COUNT(DISTINCT p.IDProducto)
    FROM dbo.Producto p
    INNER JOIN dbo.Categoria c ON p.IDCategoria = c.IDCategoria
    LEFT JOIN dbo.VarianteProducto v ON p.IDProducto = v.IDProducto AND v.Activo = 1
    WHERE p.Activo = 1
      AND c.Activo = 1
      AND (@BuscarTexto IS NULL OR p.Nombre LIKE '%' + @BuscarTexto + '%' OR p.Descripcion LIKE '%' + @BuscarTexto + '%' OR p.Marca LIKE '%' + @BuscarTexto + '%')
      AND (@SlugCategoria IS NULL OR c.Slug = @SlugCategoria)
      AND (@PrecioMin IS NULL OR v.PrecioActual >= @PrecioMin)
      AND (@PrecioMax IS NULL OR v.PrecioActual <= @PrecioMax)
      AND (@SoloDisponibles = 0 OR v.ExistenciaDisponible > 0);

    SELECT 
        p.IDProducto,
        p.Nombre,
        p.Slug,
        p.Marca,
        c.Nombre AS CategoriaNombre,
        c.Slug AS CategoriaSlug,
        MIN(v.PrecioActual) AS PrecioMinimo,
        MAX(v.PrecioActual) AS PrecioMaximo,
        SUM(ISNULL(v.ExistenciaDisponible, 0)) AS StockTotalDisponible,
        COUNT(v.IDVarianteProducto) AS TotalVariantes,
        (SELECT TOP 1 UrlImagen FROM dbo.ProductoImagen WHERE IDProducto = p.IDProducto AND EsPrincipal = 1) AS UrlImagenPrincipal,
        @TotalRegistros AS TotalRegistros,
        CEILING(CAST(@TotalRegistros AS FLOAT) / @Limite) AS TotalPaginas,
        @Pagina AS PaginaActual
    FROM dbo.Producto p
    INNER JOIN dbo.Categoria c ON p.IDCategoria = c.IDCategoria
    LEFT JOIN dbo.VarianteProducto v ON p.IDProducto = v.IDProducto AND v.Activo = 1
    WHERE p.Activo = 1
      AND c.Activo = 1
      AND (@BuscarTexto IS NULL OR p.Nombre LIKE '%' + @BuscarTexto + '%' OR p.Descripcion LIKE '%' + @BuscarTexto + '%' OR p.Marca LIKE '%' + @BuscarTexto + '%')
      AND (@SlugCategoria IS NULL OR c.Slug = @SlugCategoria)
      AND (@PrecioMin IS NULL OR v.PrecioActual >= @PrecioMin)
      AND (@PrecioMax IS NULL OR v.PrecioActual <= @PrecioMax)
      AND (@SoloDisponibles = 0 OR v.ExistenciaDisponible > 0)
    GROUP BY p.IDProducto, p.Nombre, p.Slug, p.Marca, c.Nombre, c.Slug, p.FechaCreacion
    ORDER BY 
        CASE WHEN @Orden = 'precio_asc' THEN MIN(v.PrecioActual) END ASC,
        CASE WHEN @Orden = 'precio_desc' THEN MAX(v.PrecioActual) END DESC,
        CASE WHEN @Orden = 'nombre' THEN p.Nombre END ASC,
        CASE WHEN @Orden = 'recientes' OR @Orden IS NULL THEN p.FechaCreacion END DESC
    OFFSET @Offset ROWS
    FETCH NEXT @Limite ROWS ONLY;
END;
GO

/*==============================================================================
  SP_Catalogo_ObtenerDetalleProducto 
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ObtenerDetalleProducto
    @Slug VARCHAR(220)
AS
BEGIN
    SET NOCOUNT ON;

    -- Tabla 0: Cabecera del producto
    SELECT 
        p.IDProducto,
        p.Nombre,
        p.Slug,
        p.Descripcion,
        p.Marca,
        p.PorcentajeIVA,
        c.IDCategoria,
        c.Nombre AS CategoriaNombre,
        c.Slug AS CategoriaSlug
    FROM dbo.Producto p
    INNER JOIN dbo.Categoria c ON p.IDCategoria = c.IDCategoria
    WHERE p.Slug = @Slug AND p.Activo = 1;

    -- Variantes vendibles
    SELECT 
        v.IDVarianteProducto,
        v.IDProducto,
        v.SKU,
        v.NombreVariante,
        v.PrecioActual,
        v.ExistenciaDisponible,
        CASE WHEN v.ExistenciaDisponible > 0 THEN 1 ELSE 0 END AS TieneStock
    FROM dbo.VarianteProducto v
    INNER JOIN dbo.Producto p ON v.IDProducto = p.IDProducto
    WHERE p.Slug = @Slug AND v.Activo = 1
    ORDER BY v.PrecioActual ASC;

    -- Galería de imágenes del producto
    SELECT 
        img.IDProductoImagen,
        img.IDVarianteProducto,
        img.UrlImagen,
        img.TextoAlternativo,
        img.EsPrincipal,
        img.OrdenVisualizacion
    FROM dbo.ProductoImagen img
    INNER JOIN dbo.Producto p ON img.IDProducto = p.IDProducto
    WHERE p.Slug = @Slug AND img.Activo = 1
    ORDER BY img.EsPrincipal DESC, img.OrdenVisualizacion ASC;
END;
GO

/*==============================================================================
  SP_Catalogo_DesactivarProducto
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_DesactivarProducto
    @IDProducto INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE IDProducto = @IDProducto)
    BEGIN
        ;THROW 50016, N'El producto no existe.', 1;
    END;

    UPDATE dbo.Producto
    SET Activo = 0, FechaModificacion = SYSDATETIME()
    WHERE IDProducto = @IDProducto;

    UPDATE dbo.VarianteProducto
    SET Activo = 0, FechaModificacion = SYSDATETIME()
    WHERE IDProducto = @IDProducto;

    SELECT @IDProducto AS IDProducto, N'Producto desactivado exitosamente.' AS Mensaje;
END;
GO

DISABLE TRIGGER dbo.TR_MovimientoKardex_Inmutable ON dbo.MovimientoKardex;
DISABLE TRIGGER dbo.TR_BitacoraAuditoria_Inmutable ON dbo.BitacoraAuditoria;
GO

/*==============================================================================
   DATOS (Categorías departamentales, productos y variantes)
==============================================================================*/
-- Limpiar catálogo previo si existiera para evitar duplicados al recargar
DELETE FROM dbo.MovimientoKardex;
DELETE FROM dbo.VarianteAtributo;
DELETE FROM dbo.ProductoImagen;
DELETE FROM dbo.VarianteProducto;
DELETE FROM dbo.Producto;
DELETE FROM dbo.Categoria;
DBCC CHECKIDENT ('dbo.Categoria', RESEED, 0);
DBCC CHECKIDENT ('dbo.Producto', RESEED, 0);
DBCC CHECKIDENT ('dbo.VarianteProducto', RESEED, 0);
DBCC CHECKIDENT ('dbo.MovimientoKardex', RESEED, 0);
GO

ENABLE TRIGGER dbo.TR_MovimientoKardex_Inmutable ON dbo.MovimientoKardex;
ENABLE TRIGGER dbo.TR_BitacoraAuditoria_Inmutable ON dbo.BitacoraAuditoria;

-- 1. Categorías departamentales 
EXEC dbo.SP_Catalogo_CrearCategoria @Nombre = N'Tecnología y Celulares', @Slug = 'tecnologia-celulares', @Descripcion = N'Smartphones, Laptops y Tablets';
EXEC dbo.SP_Catalogo_CrearCategoria @Nombre = N'Audio y Accesorios',      @Slug = 'audio-accesorios',     @Descripcion = N'Audífonos inalámbricos y bocinas';
EXEC dbo.SP_Catalogo_CrearCategoria @Nombre = N'Hogar y Electrodomésticos',@Slug = 'hogar-electro',        @Descripcion = N'Freidoras de aire, cafeteras y licuadoras';
EXEC dbo.SP_Catalogo_CrearCategoria @Nombre = N'Moda y Ropa',             @Slug = 'moda-ropa',            @Descripcion = N'Ropa urbana, camisetas y calzado';
GO

-- 2. Productos 
-- Producto 1: Smartphone Samsung
EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = 1, @Nombre = N'Samsung Galaxy A54 5G', @Slug = 'samsung-galaxy-a54-5g', @Descripcion = N'Pantalla Super AMOLED 120Hz, cámara de 50MP con OIS y batería de 5000 mAh.', @Marca = N'Samsung';
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 1, @SKU = 'SAM-A54-128-NG', @NombreVariante = N'128GB - Color Grafito', @PrecioActual = 2499.00, @ExistenciaInicial = 10;
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 1, @SKU = 'SAM-A54-256-BL', @NombreVariante = N'256GB - Color Blanco',  @PrecioActual = 2899.00, @ExistenciaInicial = 6;
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 1, @SKU = 'SAM-A54-128-LV', @NombreVariante = N'128GB - Color Lavanda', @PrecioActual = 2499.00, @ExistenciaInicial = 0; -- Agotado para probar botón tachado

-- Producto 2: 
EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = 1, @Nombre = N'Laptop HP 15-dy Core i5', @Slug = 'laptop-hp-15-dy-core-i5', @Descripcion = N'Intel Core i5 12va Gen, pantalla 15.6 pulgadas FHD y teclado numérico.', @Marca = N'HP';
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 2, @SKU = 'HP-15-8-256',  @NombreVariante = N'8GB RAM / 256GB SSD',  @PrecioActual = 4299.00, @ExistenciaInicial = 5;
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 2, @SKU = 'HP-15-16-512', @NombreVariante = N'16GB RAM / 512GB SSD', @PrecioActual = 5199.00, @ExistenciaInicial = 4;

-- Producto 3:
EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = 2, @Nombre = N'Audífonos Inalámbricos Sony WH-CH520', @Slug = 'audifonos-sony-wh-ch520', @Descripcion = N'Bluetooth con hasta 50 horas de batería y conexión multipunto.', @Marca = N'Sony';
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 3, @SKU = 'SNY-CH520-NG', @NombreVariante = N'Color Negro', @PrecioActual = 399.00, @ExistenciaInicial = 18;
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 3, @SKU = 'SNY-CH520-AZ', @NombreVariante = N'Color Azul',  @PrecioActual = 399.00, @ExistenciaInicial = 12;

-- Producto 4: 
EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = 3, @Nombre = N'Freidora de Aire Oster Digital 4L', @Slug = 'freidora-aire-oster-digital-4l', @Descripcion = N'Capacidad de 4 litros con panel táctil y recubrimiento antiadherente.', @Marca = N'Oster';
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 4, @SKU = 'OST-FR-4L-NG', @NombreVariante = N'Negro Mate 4 Litros', @PrecioActual = 649.00, @ExistenciaInicial = 8;

-- Producto 5:
EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = 4, @Nombre = N'Camiseta Oversized Fit Alto Gramaje', @Slug = 'camiseta-oversized-alto-gramaje', @Descripcion = N'Camiseta 100% algodón de 240 gramos corte holgado.', @Marca = N'ShopCart Basic';
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 5, @SKU = 'CAM-OVR-NG-S',  @NombreVariante = N'Negro / Talla S',  @PrecioActual = 135.00, @ExistenciaInicial = 0;
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 5, @SKU = 'CAM-OVR-NG-M',  @NombreVariante = N'Negro / Talla M',  @PrecioActual = 135.00, @ExistenciaInicial = 15;
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 5, @SKU = 'CAM-OVR-NG-L',  @NombreVariante = N'Negro / Talla L',  @PrecioActual = 135.00, @ExistenciaInicial = 20;
EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = 5, @SKU = 'CAM-OVR-NG-XL', @NombreVariante = N'Negro / Talla XL', @PrecioActual = 135.00, @ExistenciaInicial = 5;
GO



--3. Insertar imágenes reales para los 5 productos semilla (Unsplash CDN libre de derechos)
DELETE FROM dbo.ProductoImagen;
DBCC CHECKIDENT ('dbo.ProductoImagen', RESEED, 0);

-- Producto 1: Samsung Galaxy A54 5G
EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = 1, @UrlImagen = N'https://images.unsplash.com/photo-1610945415295-d9bbf067e59c?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Samsung Galaxy A54 5G Frontal', @EsPrincipal = 1, @OrdenVisualizacion = 1;
EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = 1, @UrlImagen = N'https://images.unsplash.com/photo-1598327105666-5b89351aff97?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Samsung Galaxy A54 5G Cámara', @EsPrincipal = 0, @OrdenVisualizacion = 2;

-- Producto 2: Laptop HP 15-dy Core i5
EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = 2, @UrlImagen = N'https://images.unsplash.com/photo-1588872657578-7efd1f1555ed?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Laptop HP 15.6 pulgadas', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 3: Audífonos Sony WH-CH520
EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = 3, @UrlImagen = N'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Audífonos Inalámbricos Sony', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 4: Freidora de Aire Oster 4L
EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = 4, @UrlImagen = N'https://images.unsplash.com/photo-1585515320310-259814833e62?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Freidora de Aire Digital Oster', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 5: Camiseta Oversized Fit
EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = 5, @UrlImagen = N'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Camiseta Oversized Negra', @EsPrincipal = 1, @OrdenVisualizacion = 1;
GO