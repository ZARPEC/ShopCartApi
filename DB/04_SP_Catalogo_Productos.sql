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
    @IncluirInactivos BIT           = 0,
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
    LEFT JOIN dbo.VarianteProducto v ON p.IDProducto = v.IDProducto AND (@IncluirInactivos = 1 OR v.Activo = 1)
    WHERE (@IncluirInactivos = 1 OR (p.Activo = 1 AND c.Activo = 1))
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
        p.Activo,
        c.Nombre AS CategoriaNombre,
        c.Slug AS CategoriaSlug,
        ISNULL(MIN(v.PrecioActual), 0.00) AS PrecioMinimo,
        ISNULL(MAX(v.PrecioActual), 0.00) AS PrecioMaximo,
        SUM(ISNULL(v.ExistenciaDisponible, 0)) AS StockTotalDisponible,
        COUNT(v.IDVarianteProducto) AS TotalVariantes,
        (SELECT TOP 1 UrlImagen FROM dbo.ProductoImagen WHERE IDProducto = p.IDProducto AND EsPrincipal = 1) AS UrlImagenPrincipal,
        @TotalRegistros AS TotalRegistros,
        CEILING(CAST(@TotalRegistros AS FLOAT) / @Limite) AS TotalPaginas,
        @Pagina AS PaginaActual
    FROM dbo.Producto p
    INNER JOIN dbo.Categoria c ON p.IDCategoria = c.IDCategoria
    LEFT JOIN dbo.VarianteProducto v ON p.IDProducto = v.IDProducto AND (@IncluirInactivos = 1 OR v.Activo = 1)
    WHERE (@IncluirInactivos = 1 OR (p.Activo = 1 AND c.Activo = 1))
      AND (@BuscarTexto IS NULL OR p.Nombre LIKE '%' + @BuscarTexto + '%' OR p.Descripcion LIKE '%' + @BuscarTexto + '%' OR p.Marca LIKE '%' + @BuscarTexto + '%')
      AND (@SlugCategoria IS NULL OR c.Slug = @SlugCategoria)
      AND (@PrecioMin IS NULL OR v.PrecioActual >= @PrecioMin)
      AND (@PrecioMax IS NULL OR v.PrecioActual <= @PrecioMax)
      AND (@SoloDisponibles = 0 OR v.ExistenciaDisponible > 0)
    GROUP BY p.IDProducto, p.Nombre, p.Slug, p.Marca, p.Activo, c.Nombre, c.Slug, p.FechaCreacion
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
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ListarProductos
    @BuscarTexto      NVARCHAR(100) = NULL,
    @SlugCategoria    VARCHAR(120)  = NULL,
    @PrecioMin        DECIMAL(12,2) = NULL,
    @PrecioMax        DECIMAL(12,2) = NULL,
    @SoloDisponibles  BIT           = 0,
    @IncluirInactivos BIT           = 0,
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

    -- Si viene un slug de categoría, identificar su ID para buscar esa categoría Y sus hijas
    DECLARE @IDCategoriaFiltro INT;
    IF @SlugCategoria IS NOT NULL AND LTRIM(RTRIM(@SlugCategoria)) <> ''
    BEGIN
        SELECT @IDCategoriaFiltro = IDCategoria FROM dbo.Categoria WHERE Slug = @SlugCategoria;
    END;

    -- 1. Contar total de productos coincidentes (incluye hijas si se filtró por el padre)
    SELECT @TotalRegistros = COUNT(DISTINCT p.IDProducto)
    FROM dbo.Producto p
    INNER JOIN dbo.Categoria c ON p.IDCategoria = c.IDCategoria
    LEFT JOIN dbo.VarianteProducto v ON p.IDProducto = v.IDProducto AND (@IncluirInactivos = 1 OR v.Activo = 1)
    WHERE (@IncluirInactivos = 1 OR (p.Activo = 1 AND c.Activo = 1))
      AND (@BuscarTexto IS NULL OR p.Nombre LIKE '%' + @BuscarTexto + '%' OR p.Descripcion LIKE '%' + @BuscarTexto + '%' OR p.Marca LIKE '%' + @BuscarTexto + '%')
      -- Jerarquía: Coincide con la categoría misma O con cualquiera de sus subcategorías hijas
      AND (
          @IDCategoriaFiltro IS NULL 
          OR p.IDCategoria = @IDCategoriaFiltro 
          OR c.IDCategoriaPadre = @IDCategoriaFiltro
      )
      AND (@PrecioMin IS NULL OR v.PrecioActual >= @PrecioMin)
      AND (@PrecioMax IS NULL OR v.PrecioActual <= @PrecioMax)
      AND (@SoloDisponibles = 0 OR v.ExistenciaDisponible > 0);

    -- 2. Devolver la página de productos
    SELECT 
        p.IDProducto,
        p.Nombre,
        p.Slug,
        p.Marca,
        p.Activo,
        c.IDCategoria,
        c.Nombre AS CategoriaNombre,
        c.Slug AS CategoriaSlug,
        c.IDCategoriaPadre,
        ISNULL(MIN(v.PrecioActual), 0.00) AS PrecioMinimo,
        ISNULL(MAX(v.PrecioActual), 0.00) AS PrecioMaximo,
        SUM(ISNULL(v.ExistenciaDisponible, 0)) AS StockTotalDisponible,
        COUNT(v.IDVarianteProducto) AS TotalVariantes,
        (SELECT TOP 1 UrlImagen FROM dbo.ProductoImagen WHERE IDProducto = p.IDProducto AND EsPrincipal = 1) AS UrlImagenPrincipal,
        @TotalRegistros AS TotalRegistros,
        CEILING(CAST(@TotalRegistros AS FLOAT) / @Limite) AS TotalPaginas,
        @Pagina AS PaginaActual
    FROM dbo.Producto p
    INNER JOIN dbo.Categoria c ON p.IDCategoria = c.IDCategoria
    LEFT JOIN dbo.VarianteProducto v ON p.IDProducto = v.IDProducto AND (@IncluirInactivos = 1 OR v.Activo = 1)
    WHERE (@IncluirInactivos = 1 OR (p.Activo = 1 AND c.Activo = 1))
      AND (@BuscarTexto IS NULL OR p.Nombre LIKE '%' + @BuscarTexto + '%' OR p.Descripcion LIKE '%' + @BuscarTexto + '%' OR p.Marca LIKE '%' + @BuscarTexto + '%')
      -- Jerarquía: Coincide con la categoría misma O con cualquiera de sus subcategorías hijas
      AND (
          @IDCategoriaFiltro IS NULL 
          OR p.IDCategoria = @IDCategoriaFiltro 
          OR c.IDCategoriaPadre = @IDCategoriaFiltro
      )
      AND (@PrecioMin IS NULL OR v.PrecioActual >= @PrecioMin)
      AND (@PrecioMax IS NULL OR v.PrecioActual <= @PrecioMax)
      AND (@SoloDisponibles = 0 OR v.ExistenciaDisponible > 0)
    GROUP BY p.IDProducto, p.Nombre, p.Slug, p.Marca, p.Activo, c.IDCategoria, c.Nombre, c.Slug, c.IDCategoriaPadre, p.FechaCreacion
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


/*==============================================================================
  SP_Catalogo_ActualizarProducto
     Permite corregir Nombre, Marca, Descripción y Categoría de un producto
     y registra el antes y después en BitacoraAuditoria .
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ActualizarProducto
    @IDProducto     INT,
    @IDCategoria    INT,
    @Nombre         NVARCHAR(200),
    @Descripcion    NVARCHAR(2000) = NULL,
    @Marca          NVARCHAR(100)  = NULL,
    @IDUsuarioAdmin INT            = 1,
    @DireccionIP    VARCHAR(45)    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE IDProducto = @IDProducto)
    BEGIN
        ;THROW 50016, N'El producto que intenta editar no existe.', 1;
    END;

    DECLARE @ValorAnterior NVARCHAR(MAX) = (
        SELECT IDProducto, IDCategoria, Nombre, Marca, Descripcion
        FROM dbo.Producto
        WHERE IDProducto = @IDProducto
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    BEGIN TRANSACTION;

    UPDATE dbo.Producto
    SET IDCategoria       = @IDCategoria,
        Nombre            = LTRIM(RTRIM(@Nombre)),
        Descripcion       = @Descripcion,
        Marca             = @Marca,
        FechaModificacion = SYSDATETIME()
    WHERE IDProducto = @IDProducto;

    DECLARE @IDModuloCatalogo TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'CATALOGO');

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema, IDUsuario, Entidad, IDRegistroEntidad,
        Accion, ResumenCambio, ValorAnteriorJson, ValorNuevoJson, DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloCatalogo, 2),
        @IDUsuarioAdmin,
        'Producto',
        CAST(@IDProducto AS VARCHAR(100)),
        'MODIFICACION',
        CONCAT(N'Modificación de datos del producto ID #', @IDProducto, N' (', @Nombre, N')'),
        @ValorAnterior,
        (SELECT @IDProducto AS IDProducto, @IDCategoria AS IDCategoria, @Nombre AS Nombre, @Marca AS Marca, @Descripcion AS Descripcion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT IDProducto, Nombre, Slug, Marca, Descripcion, IDCategoria
    FROM dbo.Producto
    WHERE IDProducto = @IDProducto;
END;
GO

/*==============================================================================
  SP_Catalogo_ActualizarVariante
     Permite corregir el nombre de la variante, SKU y PrecioActual (congelando
     los pedidos anteriores y auditando el cambio de precio en BitacoraAuditoria).
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ActualizarVariante
    @IDVarianteProducto INT,
    @NombreVariante     NVARCHAR(150),
    @PrecioActual       DECIMAL(12,2),
    @IDUsuarioAdmin     INT         = 1,
    @DireccionIP        VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PrecioActual <= 0
    BEGIN
        ;THROW 50017, N'El precio de la variante debe ser mayor a cero.', 1;
    END;

    DECLARE @SKU VARCHAR(60), @PrecioAnterior DECIMAL(12,2), @NombreAnterior NVARCHAR(150);

    SELECT 
        @SKU            = SKU,
        @PrecioAnterior = PrecioActual,
        @NombreAnterior = NombreVariante
    FROM dbo.VarianteProducto
    WHERE IDVarianteProducto = @IDVarianteProducto;

    IF @SKU IS NULL
    BEGIN
        ;THROW 50018, N'La variante especificada no existe.', 1;
    END;

    BEGIN TRANSACTION;

    UPDATE dbo.VarianteProducto
    SET NombreVariante    = LTRIM(RTRIM(@NombreVariante)),
        PrecioActual      = @PrecioActual,
        FechaModificacion = SYSDATETIME()
    WHERE IDVarianteProducto = @IDVarianteProducto;

    DECLARE @IDModuloCatalogo TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'CATALOGO');
    DECLARE @Accion VARCHAR(40) = CASE WHEN @PrecioAnterior <> @PrecioActual THEN 'CAMBIO_PRECIO' ELSE 'MODIFICACION' END;

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema, IDUsuario, Entidad, IDRegistroEntidad,
        Accion, ResumenCambio, ValorAnteriorJson, ValorNuevoJson, DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloCatalogo, 2),
        @IDUsuarioAdmin,
        'VarianteProducto',
        CAST(@IDVarianteProducto AS VARCHAR(100)),
        @Accion,
        CONCAT(N'Actualización de variante SKU ', @SKU, N': Q ', @PrecioAnterior, N' -> Q ', @PrecioActual),
        (SELECT @SKU AS SKU, @NombreAnterior AS NombreVariante, @PrecioAnterior AS PrecioActual FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT @SKU AS SKU, @NombreVariante AS NombreVariante, @PrecioActual AS PrecioActual FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT IDVarianteProducto, SKU, NombreVariante, PrecioActual, ExistenciaDisponible
    FROM dbo.VarianteProducto
    WHERE IDVarianteProducto = @IDVarianteProducto;
END;
GO



CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_EliminarImagenProducto
    @IDProductoImagen INT,
    @IDUsuarioAdmin   INT         = 1,
    @DireccionIP      VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @IDProducto INT, @UrlImagen NVARCHAR(500), @EsPrincipal BIT;

    SELECT 
        @IDProducto  = IDProducto, 
        @UrlImagen   = UrlImagen, 
        @EsPrincipal = EsPrincipal
    FROM dbo.ProductoImagen
    WHERE IDProductoImagen = @IDProductoImagen;

    IF @IDProducto IS NULL
    BEGIN
        ;THROW 50019, N'La imagen que intenta eliminar no existe o ya fue removida.', 1;
    END;

    BEGIN TRANSACTION;

    DELETE FROM dbo.ProductoImagen
    WHERE IDProductoImagen = @IDProductoImagen;

    -- Si se eliminó la imagen marcada como principal y quedan más imágenes para ese producto,
    -- promover automáticamente la primera imagen restante como la nueva principal
    IF @EsPrincipal = 1
    BEGIN
        DECLARE @SiguienteID INT;
        SELECT TOP 1 @SiguienteID = IDProductoImagen 
        FROM dbo.ProductoImagen 
        WHERE IDProducto = @IDProducto 
        ORDER BY OrdenVisualizacion ASC, IDProductoImagen ASC;

        IF @SiguienteID IS NOT NULL
        BEGIN
            UPDATE dbo.ProductoImagen 
            SET EsPrincipal = 1 
            WHERE IDProductoImagen = @SiguienteID;
        END;
    END;

    -- Registro en BitacoraAuditoria 
    DECLARE @IDModuloCatalogo TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'CATALOGO');

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema, IDUsuario, Entidad, IDRegistroEntidad,
        Accion, ResumenCambio, ValorAnteriorJson, ValorNuevoJson, DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloCatalogo, 2),
        @IDUsuarioAdmin,
        'ProductoImagen',
        CAST(@IDProductoImagen AS VARCHAR(100)),
        'ELIMINACION',
        CONCAT(N'Eliminación de imagen ID #', @IDProductoImagen, N' del producto #', @IDProducto),
        (SELECT @IDProductoImagen AS IDProductoImagen, @IDProducto AS IDProducto, @UrlImagen AS UrlImagen FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        NULL,
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT @IDProductoImagen AS IDProductoImagen, @IDProducto AS IDProducto, N'Imagen eliminada exitosamente.' AS Mensaje;
END;
GO


/*==============================================================================
  SP_Catalogo_ReactivarProducto (Vuelve a activar producto y variantes con auditoría)
==============================================================================*/
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ReactivarProducto
    @IDProducto     INT,
    @IDUsuarioAdmin INT         = 1,
    @DireccionIP    VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE IDProducto = @IDProducto)
    BEGIN
        THROW 50016, N'El producto que intenta reactivar no existe.', 1;
    END;

    BEGIN TRANSACTION;

    UPDATE dbo.Producto
    SET Activo = 1, FechaModificacion = SYSDATETIME()
    WHERE IDProducto = @IDProducto;

    UPDATE dbo.VarianteProducto
    SET Activo = 1, FechaModificacion = SYSDATETIME()
    WHERE IDProducto = @IDProducto;

    DECLARE @IDModuloCatalogo TINYINT = (SELECT IDModuloSistema FROM dbo.ModuloSistema WHERE Codigo = 'CATALOGO');

    INSERT INTO dbo.BitacoraAuditoria (
        IDModuloSistema, IDUsuario, Entidad, IDRegistroEntidad,
        Accion, ResumenCambio, ValorAnteriorJson, ValorNuevoJson, DireccionIP
    )
    VALUES (
        ISNULL(@IDModuloCatalogo, 2),
        @IDUsuarioAdmin,
        'Producto',
        CAST(@IDProducto AS VARCHAR(100)),
        'REACTIVACION',
        CONCAT(N'Reactivación del producto ID #', @IDProducto, N' en la tienda pública'),
        N'{"activo": false}',
        N'{"activo": true}',
        @DireccionIP
    );

    COMMIT TRANSACTION;

    SELECT @IDProducto AS IDProducto, N'Producto reactivado exitosamente.' AS Mensaje;
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


DBCC CHECKIDENT ('dbo.Categoria', RESEED);
DBCC CHECKIDENT ('dbo.Producto', RESEED);
DBCC CHECKIDENT ('dbo.VarianteProducto', RESEED);
DBCC CHECKIDENT ('dbo.ProductoImagen', RESEED);
DBCC CHECKIDENT ('dbo.MovimientoKardex', RESEED);
GO

DECLARE @IDCatTecno INT = (SELECT IDCategoria FROM dbo.Categoria WHERE Slug = 'tecnologia-celulares');
DECLARE @IDCatAudio INT = (SELECT IDCategoria FROM dbo.Categoria WHERE Slug = 'audio-accesorios');
DECLARE @IDCatHogar INT = (SELECT IDCategoria FROM dbo.Categoria WHERE Slug = 'hogar-electro');
DECLARE @IDCatModa  INT = (SELECT IDCategoria FROM dbo.Categoria WHERE Slug = 'moda-ropa');
DECLARE @IDProd INT;

-- Producto 6: Apple iPhone 15
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'apple-iphone-15-5g')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatTecno, @Nombre = N'Apple iPhone 15 Super Retina XDR', @Slug = 'apple-iphone-15-5g', @Descripcion = N'Chip A16 Bionic, Dynamic Island, cámara gran angular de 48 MP y conector USB-C.', @Marca = N'Apple';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'apple-iphone-15-5g');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'IPH-15-128-NG')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'IPH-15-128-NG', @NombreVariante = N'128GB - Negro', @PrecioActual = 6499.00, @ExistenciaInicial = 8;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'IPH-15-128-AZ')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'IPH-15-128-AZ', @NombreVariante = N'128GB - Azul',  @PrecioActual = 6499.00, @ExistenciaInicial = 5;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'IPH-15-256-NG')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'IPH-15-256-NG', @NombreVariante = N'256GB - Negro', @PrecioActual = 7399.00, @ExistenciaInicial = 3;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1695048133142-1a20484d2569?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Apple iPhone 15', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 7: Monitor Gamer LG UltraGear 27"
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'monitor-gamer-lg-ultragear-27')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatTecno, @Nombre = N'Monitor Gamer LG UltraGear 165Hz IPS', @Slug = 'monitor-gamer-lg-ultragear-27', @Descripcion = N'Panel IPS con 1ms de respuesta, tecnología AMD FreeSync Premium y bordes ultradelgados.', @Marca = N'LG';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'monitor-gamer-lg-ultragear-27');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'LG-UG-24-FHD')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'LG-UG-24-FHD', @NombreVariante = N'24 Pulgadas Full HD', @PrecioActual = 1399.00, @ExistenciaInicial = 10;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'LG-UG-27-QHD')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'LG-UG-27-QHD', @NombreVariante = N'27 Pulgadas QHD 2K',  @PrecioActual = 2199.00, @ExistenciaInicial = 6;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Monitor LG UltraGear', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 8: Tablet Samsung Galaxy Tab S9 FE
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'tablet-samsung-galaxy-tab-s9-fe')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatTecno, @Nombre = N'Tablet Samsung Galaxy Tab S9 FE 10.9" con S-Pen', @Slug = 'tablet-samsung-galaxy-tab-s9-fe', @Descripcion = N'Incluye lápiz óptico S-Pen en caja, certificación IP68 resistente al agua y pantalla de 90Hz.', @Marca = N'Samsung';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'tablet-samsung-galaxy-tab-s9-fe');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'TAB-S9FE-128-GR')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'TAB-S9FE-128-GR', @NombreVariante = N'128GB WiFi - Gris',  @PrecioActual = 3199.00, @ExistenciaInicial = 9;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'TAB-S9FE-256-MT')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'TAB-S9FE-256-MT', @NombreVariante = N'256GB WiFi - Menta', @PrecioActual = 3699.00, @ExistenciaInicial = 4;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Samsung Galaxy Tab S9 FE', @EsPrincipal = 1, @OrdenVisualizacion = 1;

/*------------------------------------------------------------------------------
  CATEGORÍA 2: AUDIO Y ACCESORIOS
------------------------------------------------------------------------------*/

-- Producto 9: Bocina Portátil JBL Flip 6
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'bocina-portatil-jbl-flip-6')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatAudio, @Nombre = N'Bocina Bluetooth Portátil JBL Flip 6 Impermeable', @Slug = 'bocina-portatil-jbl-flip-6', @Descripcion = N'Sonido JBL Original Pro de 2 vías, resistencia al agua y polvo IP67 y 12 horas de reproducción.', @Marca = N'JBL';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'bocina-portatil-jbl-flip-6');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'JBL-FLP6-NG')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'JBL-FLP6-NG', @NombreVariante = N'Color Negro', @PrecioActual = 949.00, @ExistenciaInicial = 14;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'JBL-FLP6-RJ')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'JBL-FLP6-RJ', @NombreVariante = N'Color Rojo',  @PrecioActual = 949.00, @ExistenciaInicial = 7;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'JBL-FLP6-AZ')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'JBL-FLP6-AZ', @NombreVariante = N'Color Azul',  @PrecioActual = 949.00, @ExistenciaInicial = 0;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Bocina JBL Flip 6', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 10: Mouse Inalámbrico Logitech MX Master 3S
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'mouse-logitech-mx-master-3s')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatAudio, @Nombre = N'Mouse Ergonómico Inalámbrico Logitech MX Master 3S', @Slug = 'mouse-logitech-mx-master-3s', @Descripcion = N'Sensor óptico de 8000 DPI que funciona sobre cristal, clics silenciosos y rueda electromagnética MagSpeed.', @Marca = N'Logitech';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'mouse-logitech-mx-master-3s');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'LOG-MX3S-GR')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'LOG-MX3S-GR', @NombreVariante = N'Grafito Oscuro', @PrecioActual = 799.00, @ExistenciaInicial = 11;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'LOG-MX3S-PL')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'LOG-MX3S-PL', @NombreVariante = N'Gris Pálido',    @PrecioActual = 799.00, @ExistenciaInicial = 6;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Mouse Logitech MX Master 3S', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 11: Teclado Mecánico Keychron K2 Wireless
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'teclado-mecanico-keychron-k2-wireless')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatAudio, @Nombre = N'Teclado Mecánico Inalámbrico Keychron K2 RGB 75%', @Slug = 'teclado-mecanico-keychron-k2-wireless', @Descripcion = N'Compatible con Windows y Mac, conecta hasta 3 dispositivos por Bluetooth o cable USB Tipo C.', @Marca = N'Keychron';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'teclado-mecanico-keychron-k2-wireless');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'KEY-K2-RED')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'KEY-K2-RED',   @NombreVariante = N'Switch Red (Lineal Silencioso)', @PrecioActual = 749.00, @ExistenciaInicial = 8;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'KEY-K2-BROWN')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'KEY-K2-BROWN', @NombreVariante = N'Switch Brown (Táctil)',          @PrecioActual = 749.00, @ExistenciaInicial = 10;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1595225476474-87563907a212?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Teclado Mecánico Keychron K2', @EsPrincipal = 1, @OrdenVisualizacion = 1;

/*------------------------------------------------------------------------------
  CATEGORÍA 3: HOGAR Y ELECTRODOMÉSTICOS
------------------------------------------------------------------------------*/

-- Producto 12: Cafetera Espresso DeLonghi Dedica
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'cafetera-espresso-delonghi-dedica')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatHogar, @Nombre = N'Cafetera Espresso Manual DeLonghi Dedica 15 Bares', @Slug = 'cafetera-espresso-delonghi-dedica', @Descripcion = N'Bomba profesional de 15 bares de presión, espumador de leche ajustable para cappuccino y cuerpo de acero inoxidable.', @Marca = N'DeLonghi';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'cafetera-espresso-delonghi-dedica');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'DEL-DED-INOX')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'DEL-DED-INOX', @NombreVariante = N'Acero Inoxidable', @PrecioActual = 1899.00, @ExistenciaInicial = 5;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'DEL-DED-NEGR')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'DEL-DED-NEGR', @NombreVariante = N'Negro Mate',       @PrecioActual = 1850.00, @ExistenciaInicial = 4;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1517668808822-9ebb02f2a0e6?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Cafetera Espresso DeLonghi', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 13: Licuadora Ninja Professional 1000W
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'licuadora-ninja-professional-1000w')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatHogar, @Nombre = N'Licuadora Ninja Professional 1000W Total Crushing', @Slug = 'licuadora-ninja-professional-1000w', @Descripcion = N'Cuchillas verticales de acero inoxidable para triturar hielo y fruta congelada en segundos.', @Marca = N'Ninja';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'licuadora-ninja-professional-1000w');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'NIN-BL610-2L')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'NIN-BL610-2L', @NombreVariante = N'Vaso XL 2.1 Litros (1000W)', @PrecioActual = 899.00, @ExistenciaInicial = 12;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1570222094114-d054a817e56b?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Licuadora Ninja Professional', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 14: Aspiradora Robot Xiaomi Vacuum S10
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'aspiradora-robot-xiaomi-vacuum-s10')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatHogar, @Nombre = N'Aspiradora y Trapeadora Robot Xiaomi Vacuum S10 Laser', @Slug = 'aspiradora-robot-xiaomi-vacuum-s10', @Descripcion = N'Navegación láser LDS con mapeo inteligente desde la app Mi Home y potencia de succión de 4000 Pa.', @Marca = N'Xiaomi';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'aspiradora-robot-xiaomi-vacuum-s10');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'XIA-VAC-S10-BL')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'XIA-VAC-S10-BL', @NombreVariante = N'Color Blanco Estándar', @PrecioActual = 2150.00, @ExistenciaInicial = 6;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1518640467707-6811f4a6ab73?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Aspiradora Robot Xiaomi', @EsPrincipal = 1, @OrdenVisualizacion = 1;

/*------------------------------------------------------------------------------
  CATEGORÍA 4: MODA Y ROPA
------------------------------------------------------------------------------*/

-- Producto 15: Tenis Deportivos Nike Air Zoom Pegasus
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'tenis-nike-air-zoom-pegasus-40')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatModa, @Nombre = N'Tenis para Correr Nike Air Zoom Pegasus 40', @Slug = 'tenis-nike-air-zoom-pegasus-40', @Descripcion = N'Amortiguación React con doble unidad Zoom Air para entrenamientos diarios en asfalto.', @Marca = N'Nike';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'tenis-nike-air-zoom-pegasus-40');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'NIK-PEG40-40')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'NIK-PEG40-40', @NombreVariante = N'Negro/Blanco - Talla 40', @PrecioActual = 999.00, @ExistenciaInicial = 5;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'NIK-PEG40-41')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'NIK-PEG40-41', @NombreVariante = N'Negro/Blanco - Talla 41', @PrecioActual = 999.00, @ExistenciaInicial = 8;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'NIK-PEG40-42')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'NIK-PEG40-42', @NombreVariante = N'Negro/Blanco - Talla 42', @PrecioActual = 999.00, @ExistenciaInicial = 7;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'NIK-PEG40-43')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'NIK-PEG40-43', @NombreVariante = N'Negro/Blanco - Talla 43', @PrecioActual = 999.00, @ExistenciaInicial = 0;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Tenis Nike Air Zoom', @EsPrincipal = 1, @OrdenVisualizacion = 1;

-- Producto 16: Chumpa Impermeable Columbia Watertight II
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Slug = 'chumpa-impermeable-columbia-watertight')
    EXEC dbo.SP_Catalogo_CrearProducto @IDCategoria = @IDCatModa, @Nombre = N'Chumpa Impermeable Columbia Watertight II con Capucha', @Slug = 'chumpa-impermeable-columbia-watertight', @Descripcion = N'Tecnología Omni-Tech con costuras selladas 100% impermeables y transpirables, empacable en su propio bolsillo.', @Marca = N'Columbia';

SET @IDProd = (SELECT IDProducto FROM dbo.Producto WHERE Slug = 'chumpa-impermeable-columbia-watertight');
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'COL-WT2-AZ-M')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'COL-WT2-AZ-M',  @NombreVariante = N'Azul Marino / Talla M',  @PrecioActual = 695.00, @ExistenciaInicial = 9;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'COL-WT2-AZ-L')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'COL-WT2-AZ-L',  @NombreVariante = N'Azul Marino / Talla L',  @PrecioActual = 695.00, @ExistenciaInicial = 11;
IF NOT EXISTS (SELECT 1 FROM dbo.VarianteProducto WHERE SKU = 'COL-WT2-NG-L')
    EXEC dbo.SP_Catalogo_CrearVariante @IDProducto = @IDProd, @SKU = 'COL-WT2-NG-L',  @NombreVariante = N'Negro / Talla L',        @PrecioActual = 695.00, @ExistenciaInicial = 6;
IF NOT EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE IDProducto = @IDProd)
    EXEC dbo.SP_Catalogo_AgregarImagenProducto @IDProducto = @IDProd, @UrlImagen = N'https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=800&q=80', @TextoAlternativo = N'Chumpa Columbia Watertight', @EsPrincipal = 1, @OrdenVisualizacion = 1;

SELECT COUNT(1) AS TotalProductosActivosEnCatalogo FROM dbo.Producto WHERE Activo = 1;
GO