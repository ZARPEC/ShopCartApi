
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_ID(N'ShopCartDB') IS NULL
BEGIN
    CREATE DATABASE ShopCartDB;
END
GO

USE ShopCartDB;
GO


-- Catálogo de Módulos del Sistema (Usado para filtrar Bitácora RF-09, Errores y Configuraciones)
CREATE TABLE dbo.ModuloSistema (
    IDModuloSistema     TINYINT IDENTITY(1,1) NOT NULL,
    Codigo              VARCHAR(40)           NOT NULL,
    Nombre              NVARCHAR(100)         NOT NULL,
    Descripcion         NVARCHAR(300)         NULL,
    Activo              BIT                   NOT NULL CONSTRAINT DF_ModuloSistema_Activo DEFAULT (1),
    FechaCreacion       DATETIME2(3)          NOT NULL CONSTRAINT DF_ModuloSistema_FechaCreacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_ModuloSistema PRIMARY KEY CLUSTERED (IDModuloSistema),
    CONSTRAINT UQ_ModuloSistema_Codigo UNIQUE (Codigo),
    CONSTRAINT UQ_ModuloSistema_Nombre UNIQUE (Nombre)
);
GO

-- Tabla de Configuraciones del Sistema
-- Almacena reglas y parámetros operativos de ShopCart 
CREATE TABLE dbo.ConfiguracionSistema (
    IDConfiguracionSistema  INT IDENTITY(1,1) NOT NULL,
    IDModuloSistema         TINYINT           NOT NULL,
    Clave                   VARCHAR(100)      NOT NULL,
    Valor                   NVARCHAR(500)     NOT NULL,
    TipoDato                VARCHAR(20)       NOT NULL,
    ValorMinimo             DECIMAL(18,4)     NULL,
    ValorMaximo             DECIMAL(18,4)     NULL,
    Descripcion             NVARCHAR(400)     NOT NULL,
    EsEditableAdmin         BIT               NOT NULL CONSTRAINT DF_ConfiguracionSistema_Editable DEFAULT (1),
    Activo                  BIT               NOT NULL CONSTRAINT DF_ConfiguracionSistema_Activo DEFAULT (1),
    FechaCreacion           DATETIME2(3)      NOT NULL CONSTRAINT DF_ConfiguracionSistema_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaModificacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_ConfiguracionSistema_FechaModificacion DEFAULT (SYSDATETIME()),
    IDUsuarioModificacion   INT               NULL, --  FK tabla Usuario
    CONSTRAINT PK_ConfiguracionSistema PRIMARY KEY CLUSTERED (IDConfiguracionSistema),
    CONSTRAINT UQ_ConfiguracionSistema_Clave UNIQUE (Clave),
    CONSTRAINT FK_ConfiguracionSistema_ModuloSistema FOREIGN KEY (IDModuloSistema) REFERENCES dbo.ModuloSistema (IDModuloSistema),
    CONSTRAINT CK_ConfiguracionSistema_TipoDato CHECK (TipoDato IN ('INT', 'DECIMAL', 'BOOL', 'STRING', 'JSON')),
    CONSTRAINT CK_ConfiguracionSistema_Rango CHECK (ValorMinimo IS NULL OR ValorMaximo IS NULL OR ValorMaximo >= ValorMinimo)
);
GO

-- Catálogo de Niveles de Severidad de Errores
CREATE TABLE dbo.SeveridadError (
    IDSeveridadError    TINYINT       NOT NULL,
    Codigo              VARCHAR(30)   NOT NULL,
    Nombre              NVARCHAR(60)  NOT NULL,
    Descripcion         NVARCHAR(250) NOT NULL,
    CONSTRAINT PK_SeveridadError PRIMARY KEY CLUSTERED (IDSeveridadError),
    CONSTRAINT UQ_SeveridadError_Codigo UNIQUE (Codigo)
);
GO


-- Catálogo de Roles (Cliente, Operador, Administrador)
CREATE TABLE dbo.Rol (
    IDRol               TINYINT IDENTITY(1,1) NOT NULL,
    Codigo              VARCHAR(30)           NOT NULL,
    Nombre              NVARCHAR(60)          NOT NULL,
    Descripcion         NVARCHAR(250)         NOT NULL,
    Activo              BIT                   NOT NULL CONSTRAINT DF_Rol_Activo DEFAULT (1),
    FechaCreacion       DATETIME2(3)          NOT NULL CONSTRAINT DF_Rol_FechaCreacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Rol PRIMARY KEY CLUSTERED (IDRol),
    CONSTRAINT UQ_Rol_Codigo UNIQUE (Codigo),
    CONSTRAINT UQ_Rol_Nombre UNIQUE (Nombre)
);
GO

-- Tabla de Usuarios 
CREATE TABLE dbo.Usuario (
    IDUsuario               INT IDENTITY(1,1) NOT NULL,
    IDRol                   TINYINT           NOT NULL,
    Nombres 				NVARCHAR(100)	  NOT NULL,
	Apellidos				NVARCHAR(100)	  NOT NULL,
    CorreoElectronico       VARCHAR(255)      NOT NULL,
    PasswordHash            VARCHAR(255)      NOT NULL,
    Telefono                VARCHAR(30)       NULL,
    IntentosFallidosLogin   TINYINT           NOT NULL CONSTRAINT DF_Usuario_IntentosFallidos DEFAULT (0),
    BloqueadoHasta          DATETIME2(3)      NULL,
    UltimoAcceso            DATETIME2(3)      NULL,
    Activo                  BIT               NOT NULL CONSTRAINT DF_Usuario_Activo DEFAULT (1),
    FechaCreacion           DATETIME2(3)      NOT NULL CONSTRAINT DF_Usuario_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaModificacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_Usuario_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Usuario PRIMARY KEY CLUSTERED (IDUsuario),
    CONSTRAINT UQ_Usuario_CorreoElectronico UNIQUE (CorreoElectronico),
    CONSTRAINT FK_Usuario_Rol FOREIGN KEY (IDRol) REFERENCES dbo.Rol (IDRol),
    CONSTRAINT CK_Usuario_CorreoFormato CHECK (CorreoElectronico LIKE '%_@__%.__%')
);
GO

-- Vincular UsuarioModificacion en ConfiguracionSistema
ALTER TABLE dbo.ConfiguracionSistema
ADD CONSTRAINT FK_ConfiguracionSistema_UsuarioModificacion
FOREIGN KEY (IDUsuarioModificacion) REFERENCES dbo.Usuario (IDUsuario);
GO

-- Tabla de Sesiones y Refresh Tokens con Rotación 
CREATE TABLE dbo.RefreshToken (
    IDRefreshToken              BIGINT IDENTITY(1,1) NOT NULL,
    IDUsuario                   INT                  NOT NULL,
    TokenHash                   VARCHAR(128)         NOT NULL,
    FamiliaToken                UNIQUEIDENTIFIER     NOT NULL, -- Detecta reuso de tokens robados en la rotación
    IDRefreshTokenReemplazado   BIGINT               NULL,     -- Apunta al nuevo token generado al rotar
    DireccionIP                 VARCHAR(45)          NULL,
    AgenteUsuario               NVARCHAR(300)        NULL,
    FechaCreacion               DATETIME2(3)         NOT NULL CONSTRAINT DF_RefreshToken_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaExpiracion             DATETIME2(3)         NOT NULL,
    FechaRevocacion             DATETIME2(3)         NULL,
    MotivoRevocacion            NVARCHAR(200)        NULL,
    CONSTRAINT PK_RefreshToken PRIMARY KEY CLUSTERED (IDRefreshToken),
    CONSTRAINT UQ_RefreshToken_TokenHash UNIQUE (TokenHash),
    CONSTRAINT FK_RefreshToken_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT FK_RefreshToken_Reemplazado FOREIGN KEY (IDRefreshTokenReemplazado) REFERENCES dbo.RefreshToken (IDRefreshToken),
    CONSTRAINT CK_RefreshToken_Fechas CHECK (FechaExpiracion > FechaCreacion)
);
GO

-- Direcciones de Entrega del Cliente 
CREATE TABLE dbo.DireccionCliente (
    IDDireccionCliente  INT IDENTITY(1,1) NOT NULL,
    IDUsuario           INT               NOT NULL,
    Alias               NVARCHAR(60)      NOT NULL, -- Ej: 'Casa', 'Oficina'
    NombreRecibe        NVARCHAR(150)     NOT NULL,
    TelefonoContacto    VARCHAR(30)       NOT NULL,
    Departamento        NVARCHAR(100)     NOT NULL,
    Municipio           NVARCHAR(100)     NOT NULL,
    Zona                VARCHAR(20)       NULL,
    DireccionExacta     NVARCHAR(500)     NOT NULL,
    Referencias         NVARCHAR(400)     NULL,
    EsPredeterminada    BIT               NOT NULL CONSTRAINT DF_DireccionCliente_Predeterminada DEFAULT (0),
    Activo              BIT               NOT NULL CONSTRAINT DF_DireccionCliente_Activo DEFAULT (1),
    FechaCreacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_DireccionCliente_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaModificacion   DATETIME2(3)      NOT NULL CONSTRAINT DF_DireccionCliente_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_DireccionCliente PRIMARY KEY CLUSTERED (IDDireccionCliente),
    CONSTRAINT FK_DireccionCliente_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario)
);
GO

-- Tabla de Bitácora de Errores / Excepciones Catch 
CREATE TABLE dbo.BitacoraError (
    IDBitacoraError         BIGINT IDENTITY(1,1) NOT NULL,
    IDModuloSistema         TINYINT              NOT NULL,
    IDSeveridadError        TINYINT              NOT NULL CONSTRAINT DF_BitacoraError_Severidad DEFAULT (2),
    IDUsuario               INT                  NULL,     -- Usuario autenticado en la petición (si existe sesión)
    CodigoCorrelacion       UNIQUEIDENTIFIER     NULL,     -- RequestId para rastrear el fallo entre Express y SQL Server
    OrigenError             VARCHAR(30)          NOT NULL, -- 'SQL_SP', 'BACKEND_SERVICIO', 'BACKEND_CONTROLADOR', 'BACKEND_MIDDLEWARE'
    ObjetoOMetodo           VARCHAR(200)         NOT NULL, -- Ej: 'SP_Pedidos_CrearPedido' o 'CheckoutService.confirmarCompra'
    NumeroLinea             INT                  NULL,     -- ERROR_LINE() en SQL Server o línea del archivo en TypeScript
    NumeroErrorSQL          INT                  NULL,     -- ERROR_NUMBER() cuando proviene de un bloque CATCH de SQL Server
    EstadoErrorSQL          TINYINT              NULL,     -- ERROR_STATE() cuando proviene de SQL Server
    CodigoErrorAplicacion   VARCHAR(60)          NULL,     -- Ej: 'STOCK_INSUFICIENTE', 'CUPON_VENCIDO', 'TRANSICION_INVALIDA'
    MensajeError            NVARCHAR(2000)       NOT NULL, -- ERROR_MESSAGE() en SQL o error.message en el catch de Node.js
    DetalleStackTrace       NVARCHAR(MAX)        NULL,     -- Stack trace completo capturado en el catch del backend
    ParametrosContextoJson  NVARCHAR(MAX)        NULL,     -- Parámetros de entrada o payload sanitizado en formato JSON
    MetodoHttp              VARCHAR(10)          NULL,     -- GET, POST, PUT, PATCH, DELETE
    RutaEndpoint            VARCHAR(300)         NULL,     -- Ej: '/api/v1/checkout/pago'
    CodigoEstadoHttp        SMALLINT             NULL,     -- Ej: 400, 401, 403, 404, 409, 422, 500
    DireccionIP             VARCHAR(45)          NULL,
    Resuelto                BIT                  NOT NULL CONSTRAINT DF_BitacoraError_Resuelto DEFAULT (0),
    NotasResolucion         NVARCHAR(500)        NULL,
    FechaRegistro           DATETIME2(3)         NOT NULL CONSTRAINT DF_BitacoraError_FechaRegistro DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_BitacoraError PRIMARY KEY CLUSTERED (IDBitacoraError),
    CONSTRAINT FK_BitacoraError_ModuloSistema FOREIGN KEY (IDModuloSistema) REFERENCES dbo.ModuloSistema (IDModuloSistema),
    CONSTRAINT FK_BitacoraError_SeveridadError FOREIGN KEY (IDSeveridadError) REFERENCES dbo.SeveridadError (IDSeveridadError),
    CONSTRAINT FK_BitacoraError_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT CK_BitacoraError_OrigenError CHECK (OrigenError IN ('SQL_SP', 'BACKEND_SERVICIO', 'BACKEND_CONTROLADOR', 'BACKEND_MIDDLEWARE', 'TAREA_PROGRAMADA')),
    CONSTRAINT CK_BitacoraError_ContextoJson CHECK (ParametrosContextoJson IS NULL OR ISJSON(ParametrosContextoJson) = 1),
    CONSTRAINT CK_BitacoraError_CodigoHttp CHECK (CodigoEstadoHttp IS NULL OR (CodigoEstadoHttp >= 100 AND CodigoEstadoHttp <= 599))
);
GO

-- Categorías de Productos 
CREATE TABLE dbo.Categoria (
    IDCategoria         INT IDENTITY(1,1) NOT NULL,
    IDCategoriaPadre    INT               NULL,
    Nombre              NVARCHAR(100)     NOT NULL,
    Slug                VARCHAR(120)      NOT NULL,
    Descripcion         NVARCHAR(400)     NULL,
    Activo              BIT               NOT NULL CONSTRAINT DF_Categoria_Activo DEFAULT (1),
    FechaCreacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_Categoria_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaModificacion   DATETIME2(3)      NOT NULL CONSTRAINT DF_Categoria_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Categoria PRIMARY KEY CLUSTERED (IDCategoria),
    CONSTRAINT UQ_Categoria_Nombre UNIQUE (Nombre),
    CONSTRAINT UQ_Categoria_Slug UNIQUE (Slug),
    CONSTRAINT FK_Categoria_CategoriaPadre FOREIGN KEY (IDCategoriaPadre) REFERENCES dbo.Categoria (IDCategoria),
    CONSTRAINT CK_Categoria_NoAutoReferencia CHECK (IDCategoriaPadre IS NULL OR IDCategoriaPadre <> IDCategoria)
);
GO

-- Productos Maestro 
CREATE TABLE dbo.Producto (
    IDProducto          INT IDENTITY(1,1) NOT NULL,
    IDCategoria         INT               NOT NULL,
    Nombre              NVARCHAR(200)     NOT NULL,
    Slug                VARCHAR(220)      NOT NULL,
    Descripcion         NVARCHAR(2000)    NULL,
    Marca               NVARCHAR(100)     NULL,
    PorcentajeIVA       DECIMAL(5,2)      NOT NULL CONSTRAINT DF_Producto_PorcentajeIVA DEFAULT (12.00), -- Precios incluyen IVA 12%
    Activo              BIT               NOT NULL CONSTRAINT DF_Producto_Activo DEFAULT (1),
    FechaCreacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_Producto_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaModificacion   DATETIME2(3)      NOT NULL CONSTRAINT DF_Producto_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Producto PRIMARY KEY CLUSTERED (IDProducto),
    CONSTRAINT UQ_Producto_Slug UNIQUE (Slug),
    CONSTRAINT FK_Producto_Categoria FOREIGN KEY (IDCategoria) REFERENCES dbo.Categoria (IDCategoria),
    CONSTRAINT CK_Producto_PorcentajeIVA CHECK (PorcentajeIVA >= 0.00 AND PorcentajeIVA <= 100.00)
);
GO

-- Tipos de Atributo de Variante (Ej: 'Talla', 'Color', 'Material', 'Capacidad')
CREATE TABLE dbo.TipoAtributo (
    IDTipoAtributo      INT IDENTITY(1,1) NOT NULL,
    Nombre              NVARCHAR(60)      NOT NULL,
    Descripcion         NVARCHAR(200)     NULL,
    Activo              BIT               NOT NULL CONSTRAINT DF_TipoAtributo_Activo DEFAULT (1),
    CONSTRAINT PK_TipoAtributo PRIMARY KEY CLUSTERED (IDTipoAtributo),
    CONSTRAINT UQ_TipoAtributo_Nombre UNIQUE (Nombre)
);
GO

-- Valores de Atributo 
CREATE TABLE dbo.ValorAtributo (
    IDValorAtributo     INT IDENTITY(1,1) NOT NULL,
    IDTipoAtributo      INT               NOT NULL,
    Valor               NVARCHAR(80)      NOT NULL,
    CodigoColorHex      CHAR(7)           NULL, -- Ej: '#FF0000' cuando el atributo es Color
    OrdenVisualizacion  SMALLINT          NOT NULL CONSTRAINT DF_ValorAtributo_Orden DEFAULT (1),
    Activo              BIT               NOT NULL CONSTRAINT DF_ValorAtributo_Activo DEFAULT (1),
    CONSTRAINT PK_ValorAtributo PRIMARY KEY CLUSTERED (IDValorAtributo),
    CONSTRAINT UQ_ValorAtributo_Tipo_Valor UNIQUE (IDTipoAtributo, Valor),
    -- Índice único compuesto adicional para permitir FK compuesta desde VarianteAtributo (3FN estricta)
    CONSTRAINT UQ_ValorAtributo_Tipo_IDValor UNIQUE (IDTipoAtributo, IDValorAtributo),
    CONSTRAINT FK_ValorAtributo_TipoAtributo FOREIGN KEY (IDTipoAtributo) REFERENCES dbo.TipoAtributo (IDTipoAtributo),
    CONSTRAINT CK_ValorAtributo_ColorHex CHECK (CodigoColorHex IS NULL OR CodigoColorHex LIKE '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]')
);
GO

--  Variantes Vendibles del Producto 
CREATE TABLE dbo.VarianteProducto (
    IDVarianteProducto      INT IDENTITY(1,1) NOT NULL,
    IDProducto              INT               NOT NULL,
    SKU                     VARCHAR(60)       NOT NULL,
    NombreVariante          NVARCHAR(150)     NOT NULL, -- Ej: 'Talla M - Color Azul'
    PrecioActual            DECIMAL(12,2)     NOT NULL, 
    CostoReferencia         DECIMAL(12,2)     NULL,
    ExistenciaFisica        INT               NOT NULL CONSTRAINT DF_VarianteProducto_ExistenciaFisica DEFAULT (0),
    ExistenciaReservada     INT               NOT NULL CONSTRAINT DF_VarianteProducto_ExistenciaReservada DEFAULT (0),
    ExistenciaDisponible    AS (ExistenciaFisica - ExistenciaReservada) PERSISTED,
    StockMinimoAlerta       INT               NOT NULL CONSTRAINT DF_VarianteProducto_StockMinimo DEFAULT (5),
    Activo                  BIT               NOT NULL CONSTRAINT DF_VarianteProducto_Activo DEFAULT (1),
    VersionFila             ROWVERSION        NOT NULL,
    FechaCreacion           DATETIME2(3)      NOT NULL CONSTRAINT DF_VarianteProducto_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaModificacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_VarianteProducto_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_VarianteProducto PRIMARY KEY CLUSTERED (IDVarianteProducto),
    CONSTRAINT UQ_VarianteProducto_SKU UNIQUE (SKU),
    CONSTRAINT FK_VarianteProducto_Producto FOREIGN KEY (IDProducto) REFERENCES dbo.Producto (IDProducto),
    CONSTRAINT CK_VarianteProducto_PrecioPositivo CHECK (PrecioActual >= 0.00),
    CONSTRAINT CK_VarianteProducto_CostoPositivo CHECK (CostoReferencia IS NULL OR CostoReferencia >= 0.00),
    CONSTRAINT CK_VarianteProducto_ExistenciaFisicaNoNegativa CHECK (ExistenciaFisica >= 0),
    CONSTRAINT CK_VarianteProducto_ExistenciaReservadaNoNegativa CHECK (ExistenciaReservada >= 0),
    CONSTRAINT CK_VarianteProducto_SinSobreventa CHECK (ExistenciaFisica >= ExistenciaReservada),
    CONSTRAINT CK_VarianteProducto_StockMinimo CHECK (StockMinimoAlerta >= 0)
);
GO

-- Relación Normalizada Variante <-> Atributos (Garantiza 1 valor por TipoAtributo en cada Variante)
CREATE TABLE dbo.VarianteAtributo (
    IDVarianteAtributo  INT IDENTITY(1,1) NOT NULL,
    IDVarianteProducto  INT               NOT NULL,
    IDTipoAtributo      INT               NOT NULL,
    IDValorAtributo     INT               NOT NULL,
    CONSTRAINT PK_VarianteAtributo PRIMARY KEY CLUSTERED (IDVarianteAtributo),
    CONSTRAINT UQ_VarianteAtributo_Variante_Tipo UNIQUE (IDVarianteProducto, IDTipoAtributo),
    CONSTRAINT FK_VarianteAtributo_VarianteProducto FOREIGN KEY (IDVarianteProducto) REFERENCES dbo.VarianteProducto (IDVarianteProducto),
    CONSTRAINT FK_VarianteAtributo_TipoValor FOREIGN KEY (IDTipoAtributo, IDValorAtributo) REFERENCES dbo.ValorAtributo (IDTipoAtributo, IDValorAtributo)
);
GO

-- Imágenes del Producto y/o Variante 
CREATE TABLE dbo.ProductoImagen (
    IDProductoImagen    INT IDENTITY(1,1) NOT NULL,
    IDProducto          INT               NOT NULL,
    IDVarianteProducto  INT               NULL, -- Opcional si la imagen corresponde a una variante específica
    UrlImagen           NVARCHAR(500)     NOT NULL,
    TextoAlternativo    NVARCHAR(200)     NULL,
    EsPrincipal         BIT               NOT NULL CONSTRAINT DF_ProductoImagen_EsPrincipal DEFAULT (0),
    OrdenVisualizacion  SMALLINT          NOT NULL CONSTRAINT DF_ProductoImagen_Orden DEFAULT (1),
    Activo              BIT               NOT NULL CONSTRAINT DF_ProductoImagen_Activo DEFAULT (1),
    FechaCreacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_ProductoImagen_FechaCreacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_ProductoImagen PRIMARY KEY CLUSTERED (IDProductoImagen),
    CONSTRAINT FK_ProductoImagen_Producto FOREIGN KEY (IDProducto) REFERENCES dbo.Producto (IDProducto),
    CONSTRAINT FK_ProductoImagen_VarianteProducto FOREIGN KEY (IDVarianteProducto) REFERENCES dbo.VarianteProducto (IDVarianteProducto)
);
GO


--  Catálogo de Tipos de Descuento de Cupón 
CREATE TABLE dbo.TipoDescuentoCupon (
    IDTipoDescuentoCupon TINYINT       NOT NULL,
    Codigo               VARCHAR(30)   NOT NULL, -- 'PORCENTAJE', 'MONTO_FIJO'
    Nombre               NVARCHAR(60)  NOT NULL,
    CONSTRAINT PK_TipoDescuentoCupon PRIMARY KEY CLUSTERED (IDTipoDescuentoCupon),
    CONSTRAINT UQ_TipoDescuentoCupon_Codigo UNIQUE (Codigo)
);
GO

-- Catálogo de Ámbito de Aplicación del Cupón 
CREATE TABLE dbo.AmbitoCupon (
    IDAmbitoCupon       TINYINT       NOT NULL,
    Codigo              VARCHAR(30)   NOT NULL, -- 'CARRITO_COMPLETO', 'CATEGORIA'
    Nombre              NVARCHAR(60)  NOT NULL,
    CONSTRAINT PK_AmbitoCupon PRIMARY KEY CLUSTERED (IDAmbitoCupon),
    CONSTRAINT UQ_AmbitoCupon_Codigo UNIQUE (Codigo)
);
GO

-- Tabla de Cupones 
CREATE TABLE dbo.Cupon (
    IDCupon                 INT IDENTITY(1,1) NOT NULL,
    Codigo                  VARCHAR(50)       NOT NULL,
    Descripcion             NVARCHAR(300)     NOT NULL,
    IDTipoDescuentoCupon    TINYINT           NOT NULL, -- 1 = PORCENTAJE, 2 = MONTO_FIJO
    ValorDescuento          DECIMAL(12,2)     NOT NULL,
    IDAmbitoCupon           TINYINT           NOT NULL, -- 1 = CARRITO_COMPLETO, 2 = CATEGORIA
    IDCategoria             INT               NULL,     -- Obligatorio cuando IDAmbitoCupon = 2 (CATEGORIA)
    MontoMinimoCompra       DECIMAL(12,2)     NOT NULL CONSTRAINT DF_Cupon_MontoMinimo DEFAULT (0.00),
    MontoMaximoDescuento    DECIMAL(12,2)     NULL,     -- Tope para cupones porcentuales
    LimiteTotalUsos         INT               NOT NULL,
    LimiteUsosPorCliente    INT               NOT NULL CONSTRAINT DF_Cupon_LimitePorCliente DEFAULT (1),
    UsosActuales            INT               NOT NULL CONSTRAINT DF_Cupon_UsosActuales DEFAULT (0),
    FechaInicioVigencia     DATETIME2(3)      NOT NULL,
    FechaFinVigencia        DATETIME2(3)      NOT NULL,
    Activo                  BIT               NOT NULL CONSTRAINT DF_Cupon_Activo DEFAULT (1),
    VersionFila             ROWVERSION        NOT NULL,
    FechaCreacion           DATETIME2(3)      NOT NULL CONSTRAINT DF_Cupon_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaModificacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_Cupon_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Cupon PRIMARY KEY CLUSTERED (IDCupon),
    CONSTRAINT UQ_Cupon_Codigo UNIQUE (Codigo),
    CONSTRAINT FK_Cupon_TipoDescuento FOREIGN KEY (IDTipoDescuentoCupon) REFERENCES dbo.TipoDescuentoCupon (IDTipoDescuentoCupon),
    CONSTRAINT FK_Cupon_AmbitoCupon FOREIGN KEY (IDAmbitoCupon) REFERENCES dbo.AmbitoCupon (IDAmbitoCupon),
    CONSTRAINT FK_Cupon_Categoria FOREIGN KEY (IDCategoria) REFERENCES dbo.Categoria (IDCategoria),
    CONSTRAINT CK_Cupon_ValorDescuentoPositivo CHECK (ValorDescuento > 0.00),
    -- Si es porcentaje (1), no puede exceder 100%
    CONSTRAINT CK_Cupon_PorcentajeValido CHECK (IDTipoDescuentoCupon <> 1 OR ValorDescuento <= 100.00),
    -- Si aplica por categoría (2), IDCategoria no puede ser NULL; si es carrito completo (1), IDCategoria debe ser NULL
    CONSTRAINT CK_Cupon_AmbitoCategoriaConsistente CHECK (
        (IDAmbitoCupon = 1 AND IDCategoria IS NULL) OR
        (IDAmbitoCupon = 2 AND IDCategoria IS NOT NULL)
    ),
    CONSTRAINT CK_Cupon_MontoMinimoNoNegativo CHECK (MontoMinimoCompra >= 0.00),
    CONSTRAINT CK_Cupon_MontoMaximoPositivo CHECK (MontoMaximoDescuento IS NULL OR MontoMaximoDescuento > 0.00),
    CONSTRAINT CK_Cupon_LimitesPositivos CHECK (LimiteTotalUsos > 0 AND LimiteUsosPorCliente > 0 AND LimiteUsosPorCliente <= LimiteTotalUsos),
    CONSTRAINT CK_Cupon_NoExcederLimiteTotal CHECK (UsosActuales >= 0 AND UsosActuales <= LimiteTotalUsos),
    CONSTRAINT CK_Cupon_VigenciaValida CHECK (FechaFinVigencia > FechaInicioVigencia)
);
GO

/*==============================================================================
  SECCIÓN 4: CARRITO DE COMPRAS Y CARRITO DE INVITADO (RF-04 y Glosario)
==============================================================================*/

-- 4.1 Catálogo de Estados del Carrito
CREATE TABLE dbo.EstadoCarrito (
    IDEstadoCarrito     TINYINT       NOT NULL,
    Codigo              VARCHAR(30)   NOT NULL, -- 'ACTIVO', 'EN_CHECKOUT', 'CONVERTIDO', 'ABANDONADO'
    Nombre              NVARCHAR(60)  NOT NULL,
    CONSTRAINT PK_EstadoCarrito PRIMARY KEY CLUSTERED (IDEstadoCarrito),
    CONSTRAINT UQ_EstadoCarrito_Codigo UNIQUE (Codigo)
);
GO

-- Cabecera del Carrito
CREATE TABLE dbo.Carrito (
    IDCarrito               INT IDENTITY(1,1) NOT NULL,
    IDUsuario               INT               NULL,     -- Cliente autenticado
    TokenInvitado           VARCHAR(100)      NULL,     -- Visitante sin sesión 
    IDEstadoCarrito         TINYINT           NOT NULL CONSTRAINT DF_Carrito_Estado DEFAULT (1),
    IDCupon                 INT               NULL,  
    FechaCreacion           DATETIME2(3)      NOT NULL CONSTRAINT DF_Carrito_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaUltimaActividad    DATETIME2(3)      NOT NULL CONSTRAINT DF_Carrito_FechaUltimaActividad DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Carrito PRIMARY KEY CLUSTERED (IDCarrito),
    CONSTRAINT FK_Carrito_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT FK_Carrito_EstadoCarrito FOREIGN KEY (IDEstadoCarrito) REFERENCES dbo.EstadoCarrito (IDEstadoCarrito),
    CONSTRAINT FK_Carrito_Cupon FOREIGN KEY (IDCupon) REFERENCES dbo.Cupon (IDCupon),
    -- Debe pertenecer al menos a un usuario registrado o tener un token de invitado
    CONSTRAINT CK_Carrito_PropietarioValido CHECK (IDUsuario IS NOT NULL OR TokenInvitado IS NOT NULL)
);
GO

-- 4.3 Detalle de Líneas del Carrito 
CREATE TABLE dbo.CarritoDetalle (
    IDCarritoDetalle            INT IDENTITY(1,1) NOT NULL,
    IDCarrito                   INT               NOT NULL,
    IDVarianteProducto          INT               NOT NULL,
    Cantidad                    INT               NOT NULL,
    PrecioUnitarioReferencia    DECIMAL(12,2)     NOT NULL, 
    FechaAgregado               DATETIME2(3)      NOT NULL CONSTRAINT DF_CarritoDetalle_FechaAgregado DEFAULT (SYSDATETIME()),
    FechaModificacion           DATETIME2(3)      NOT NULL CONSTRAINT DF_CarritoDetalle_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_CarritoDetalle PRIMARY KEY CLUSTERED (IDCarritoDetalle),
    CONSTRAINT UQ_CarritoDetalle_Carrito_Variante UNIQUE (IDCarrito, IDVarianteProducto),
    CONSTRAINT FK_CarritoDetalle_Carrito FOREIGN KEY (IDCarrito) REFERENCES dbo.Carrito (IDCarrito),
    CONSTRAINT FK_CarritoDetalle_VarianteProducto FOREIGN KEY (IDVarianteProducto) REFERENCES dbo.VarianteProducto (IDVarianteProducto),
    CONSTRAINT CK_CarritoDetalle_CantidadPositiva CHECK (Cantidad > 0),
    CONSTRAINT CK_CarritoDetalle_PrecioNoNegativo CHECK (PrecioUnitarioReferencia >= 0.00)
);
GO

-- Catálogo de Estados del Pedido y Reglas de Negocio por Estado 
CREATE TABLE dbo.EstadoPedido (
    IDEstadoPedido              TINYINT       NOT NULL,
    Codigo                      VARCHAR(30)   NOT NULL,
    Nombre                      NVARCHAR(80)  NOT NULL,
    Descripcion                 NVARCHAR(250) NOT NULL,
    PermiteCancelacion          BIT           NOT NULL CONSTRAINT DF_EstadoPedido_PermiteCancelacion DEFAULT (0),
    PermiteDevolucion           BIT           NOT NULL CONSTRAINT DF_EstadoPedido_PermiteDevolucion DEFAULT (0),
    EsEstadoFinal               BIT           NOT NULL CONSTRAINT DF_EstadoPedido_EsEstadoFinal DEFAULT (0),
    ConsiderarEnReporteVentas   BIT           NOT NULL CONSTRAINT DF_EstadoPedido_ConsiderarReporte DEFAULT (0),
    OrdenCicloVida              TINYINT       NOT NULL,
    CONSTRAINT PK_EstadoPedido PRIMARY KEY CLUSTERED (IDEstadoPedido),
    CONSTRAINT UQ_EstadoPedido_Codigo UNIQUE (Codigo),
    CONSTRAINT UQ_EstadoPedido_Nombre UNIQUE (Nombre)
);
GO

-- Matriz de Transiciones de Estado Permitidas
CREATE TABLE dbo.TransicionEstadoPedido (
    IDTransicionEstadoPedido    INT IDENTITY(1,1) NOT NULL,
    IDEstadoOrigen              TINYINT           NOT NULL,
    IDEstadoDestino             TINYINT           NOT NULL,
    RequiereMotivo              BIT               NOT NULL CONSTRAINT DF_TransicionEstado_RequiereMotivo DEFAULT (0),
    ReintegraInventario         BIT               NOT NULL CONSTRAINT DF_TransicionEstado_ReintegraInv DEFAULT (0),
    Activo                      BIT               NOT NULL CONSTRAINT DF_TransicionEstado_Activo DEFAULT (1),
    CONSTRAINT PK_TransicionEstadoPedido PRIMARY KEY CLUSTERED (IDTransicionEstadoPedido),
    CONSTRAINT UQ_TransicionEstadoPedido_Origen_Destino UNIQUE (IDEstadoOrigen, IDEstadoDestino),
    CONSTRAINT FK_TransicionEstadoPedido_Origen FOREIGN KEY (IDEstadoOrigen) REFERENCES dbo.EstadoPedido (IDEstadoPedido),
    CONSTRAINT FK_TransicionEstadoPedido_Destino FOREIGN KEY (IDEstadoDestino) REFERENCES dbo.EstadoPedido (IDEstadoPedido),
    CONSTRAINT CK_TransicionEstadoPedido_Distintos CHECK (IDEstadoOrigen <> IDEstadoDestino)
);
GO

-- Catálogo de Métodos de Pago
CREATE TABLE dbo.MetodoPago (
    IDMetodoPago        TINYINT IDENTITY(1,1) NOT NULL,
    Codigo              VARCHAR(30)           NOT NULL,
    Nombre              NVARCHAR(80)          NOT NULL,
    Activo              BIT                   NOT NULL CONSTRAINT DF_MetodoPago_Activo DEFAULT (1),
    CONSTRAINT PK_MetodoPago PRIMARY KEY CLUSTERED (IDMetodoPago),
    CONSTRAINT UQ_MetodoPago_Codigo UNIQUE (Codigo)
);
GO

-- Cabecera de Pedidos
CREATE TABLE dbo.Pedido (
    IDPedido                INT IDENTITY(1,1) NOT NULL,
    NumeroPedido            VARCHAR(30)       NOT NULL, -- Ej: 'ORD-20261027-00001'
    IDUsuario               INT               NOT NULL,
    IDCarritoOrigen         INT               NULL,
    IDEstadoPedido          TINYINT           NOT NULL,
    IDMetodoPago            TINYINT           NOT NULL,
    IDCupon                 INT               NULL,
    CodigoCuponCongelado    VARCHAR(50)       NULL,
    Moneda                  CHAR(3)           NOT NULL CONSTRAINT DF_Pedido_Moneda DEFAULT ('GTQ'),
    PorcentajeIVACongelado  DECIMAL(5,2)      NOT NULL CONSTRAINT DF_Pedido_IVA DEFAULT (12.00),
    SubtotalBruto           DECIMAL(12,2)     NOT NULL,
    DescuentoCupon          DECIMAL(12,2)     NOT NULL CONSTRAINT DF_Pedido_DescuentoCupon DEFAULT (0.00),
    CostoEnvio              DECIMAL(12,2)     NOT NULL CONSTRAINT DF_Pedido_CostoEnvio DEFAULT (0.00),
    TotalPedido             DECIMAL(12,2)     NOT NULL,
    MontoIVAIncluido        DECIMAL(12,2)     NOT NULL,
    TotalDevueltoAcumulado  DECIMAL(12,2)     NOT NULL CONSTRAINT DF_Pedido_TotalDevuelto DEFAULT (0.00),
    IDDireccionCliente      INT               NOT NULL,
    EntregaNombreRecibe     NVARCHAR(150)     NOT NULL,
    EntregaTelefono         VARCHAR(30)       NOT NULL,
    EntregaDepartamento     NVARCHAR(100)     NOT NULL,
    EntregaMunicipio        NVARCHAR(100)     NOT NULL,
    EntregaZona             VARCHAR(20)       NULL,
    EntregaDireccionExacta  NVARCHAR(500)     NOT NULL,
    EntregaReferencias      NVARCHAR(400)     NULL,
    ClaveIdempotencia       VARCHAR(100)      NOT NULL,
    NotasCliente            NVARCHAR(500)     NULL,
    MotivoCancelacion       NVARCHAR(500)     NULL,
    FechaCreacion           DATETIME2(3)      NOT NULL CONSTRAINT DF_Pedido_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaConfirmacionPago   DATETIME2(3)      NULL,
    FechaDespacho           DATETIME2(3)      NULL,
    FechaEntrega            DATETIME2(3)      NULL,
    FechaCancelacion        DATETIME2(3)      NULL,
    FechaModificacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_Pedido_FechaModificacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Pedido PRIMARY KEY CLUSTERED (IDPedido),
    CONSTRAINT UQ_Pedido_NumeroPedido UNIQUE (NumeroPedido),
    CONSTRAINT UQ_Pedido_ClaveIdempotencia UNIQUE (ClaveIdempotencia),
    CONSTRAINT FK_Pedido_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT FK_Pedido_CarritoOrigen FOREIGN KEY (IDCarritoOrigen) REFERENCES dbo.Carrito (IDCarrito),
    CONSTRAINT FK_Pedido_EstadoPedido FOREIGN KEY (IDEstadoPedido) REFERENCES dbo.EstadoPedido (IDEstadoPedido),
    CONSTRAINT FK_Pedido_MetodoPago FOREIGN KEY (IDMetodoPago) REFERENCES dbo.MetodoPago (IDMetodoPago),
    CONSTRAINT FK_Pedido_Cupon FOREIGN KEY (IDCupon) REFERENCES dbo.Cupon (IDCupon),
    CONSTRAINT FK_Pedido_DireccionCliente FOREIGN KEY (IDDireccionCliente) REFERENCES dbo.DireccionCliente (IDDireccionCliente),
    CONSTRAINT CK_Pedido_MontosNoNegativos CHECK (
        SubtotalBruto >= 0.00 AND
        DescuentoCupon >= 0.00 AND
        CostoEnvio >= 0.00 AND
        TotalPedido >= 0.00 AND
        MontoIVAIncluido >= 0.00 AND
        TotalDevueltoAcumulado >= 0.00
    ),
	-- nunca dejar en 0 el carrito
    CONSTRAINT CK_Pedido_DescuentoNoSuperaSubtotal CHECK (DescuentoCupon <= SubtotalBruto),
    CONSTRAINT CK_Pedido_CuadraturaTotal CHECK (TotalPedido = (SubtotalBruto - DescuentoCupon) + CostoEnvio),
    CONSTRAINT CK_Pedido_DevolucionNoSuperaTotal CHECK (TotalDevueltoAcumulado <= TotalPedido)
);
GO

-- Detalle de Líneas del Pedido
CREATE TABLE dbo.PedidoDetalle (
    IDPedidoDetalle             INT IDENTITY(1,1) NOT NULL,
    IDPedido                    INT               NOT NULL,
    IDVarianteProducto          INT               NOT NULL,
    SKUCongelado                VARCHAR(60)       NOT NULL,
    NombreProductoCongelado     NVARCHAR(200)     NOT NULL,
    AtributosVarianteCongelados NVARCHAR(200)     NOT NULL,
    CantidadComprada            INT               NOT NULL,
    CantidadDevuelta            INT               NOT NULL CONSTRAINT DF_PedidoDetalle_CantidadDevuelta DEFAULT (0),
    CantidadNeta                AS (CantidadComprada - CantidadDevuelta) PERSISTED,
    PrecioUnitarioCongelado     DECIMAL(12,2)     NOT NULL, 
    DescuentoProrrateadoLinea   DECIMAL(12,2)     NOT NULL CONSTRAINT DF_PedidoDetalle_DescuentoLinea DEFAULT (0.00),
    SubtotalBrutoLinea          AS (CAST(CantidadComprada * PrecioUnitarioCongelado AS DECIMAL(12,2))) PERSISTED,
    TotalNetaLinea              AS (CAST((CantidadComprada * PrecioUnitarioCongelado) - DescuentoProrrateadoLinea AS DECIMAL(12,2))) PERSISTED,
    CONSTRAINT PK_PedidoDetalle PRIMARY KEY CLUSTERED (IDPedidoDetalle),
    CONSTRAINT UQ_PedidoDetalle_Pedido_Variante UNIQUE (IDPedido, IDVarianteProducto),
    CONSTRAINT UQ_PedidoDetalle_IDPedidoDetalle_Variante UNIQUE (IDPedidoDetalle, IDVarianteProducto),
    CONSTRAINT FK_PedidoDetalle_Pedido FOREIGN KEY (IDPedido) REFERENCES dbo.Pedido (IDPedido),
    CONSTRAINT FK_PedidoDetalle_VarianteProducto FOREIGN KEY (IDVarianteProducto) REFERENCES dbo.VarianteProducto (IDVarianteProducto),
    CONSTRAINT CK_PedidoDetalle_CantidadPositiva CHECK (CantidadComprada > 0),
    CONSTRAINT CK_PedidoDetalle_LimiteDevolucionLinea CHECK (CantidadDevuelta >= 0 AND CantidadDevuelta <= CantidadComprada),
    CONSTRAINT CK_PedidoDetalle_PrecioCongeladoNoNegativo CHECK (PrecioUnitarioCongelado >= 0.00),
    CONSTRAINT CK_PedidoDetalle_DescuentoValido CHECK (
        DescuentoProrrateadoLinea >= 0.00 AND
        DescuentoProrrateadoLinea <= (CantidadComprada * PrecioUnitarioCongelado)
    )
);
GO

--  Registro de Uso de Cupones por Pedido y Cliente 
CREATE TABLE dbo.CuponUso (
    IDCuponUso              INT IDENTITY(1,1) NOT NULL,
    IDCupon                 INT               NOT NULL,
    IDPedido                INT               NOT NULL,
    IDUsuario               INT               NOT NULL,
    MontoDescuentoAplicado  DECIMAL(12,2)     NOT NULL,
    FechaUso                DATETIME2(3)      NOT NULL CONSTRAINT DF_CuponUso_FechaUso DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_CuponUso PRIMARY KEY CLUSTERED (IDCuponUso),
    CONSTRAINT UQ_CuponUso_Pedido UNIQUE (IDPedido),
    CONSTRAINT FK_CuponUso_Cupon FOREIGN KEY (IDCupon) REFERENCES dbo.Cupon (IDCupon),
    CONSTRAINT FK_CuponUso_Pedido FOREIGN KEY (IDPedido) REFERENCES dbo.Pedido (IDPedido),
    CONSTRAINT FK_CuponUso_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT CK_CuponUso_MontoPositivo CHECK (MontoDescuentoAplicado > 0.00)
);
GO

-- Transacciones de Pago e Idempotencia de Cobro
CREATE TABLE dbo.TransaccionPago (
    IDTransaccionPago       BIGINT IDENTITY(1,1) NOT NULL,
    IDPedido                INT                  NOT NULL,
    IDMetodoPago            TINYINT              NOT NULL,
    ClaveIdempotenciaPago   VARCHAR(100)         NOT NULL,
    MontoTransaccion        DECIMAL(12,2)        NOT NULL,
    EstadoPago              VARCHAR(30)          NOT NULL, -- 'PENDIENTE', 'APROBADO', 'RECHAZADO', 'REEMBOLSADO'
    ReferenciaAutorizacion  VARCHAR(100)         NULL,
    MensajeRespuesta        NVARCHAR(400)        NULL,
    FechaTransaccion        DATETIME2(3)         NOT NULL CONSTRAINT DF_TransaccionPago_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_TransaccionPago PRIMARY KEY CLUSTERED (IDTransaccionPago),
    CONSTRAINT UQ_TransaccionPago_ClaveIdempotencia UNIQUE (ClaveIdempotenciaPago),
    CONSTRAINT FK_TransaccionPago_Pedido FOREIGN KEY (IDPedido) REFERENCES dbo.Pedido (IDPedido),
    CONSTRAINT FK_TransaccionPago_MetodoPago FOREIGN KEY (IDMetodoPago) REFERENCES dbo.MetodoPago (IDMetodoPago),
    CONSTRAINT CK_TransaccionPago_MontoPositivo CHECK (MontoTransaccion >= 0.00),
    CONSTRAINT CK_TransaccionPago_Estado CHECK (EstadoPago IN ('PENDIENTE', 'APROBADO', 'RECHAZADO', 'REEMBOLSADO'))
);
GO

-- Historial de Cambios de Estado del Pedido
CREATE TABLE dbo.PedidoHistorialEstado (
    IDPedidoHistorialEstado BIGINT IDENTITY(1,1) NOT NULL,
    IDPedido                INT                  NOT NULL,
    IDEstadoAnterior        TINYINT              NULL, -- NULL únicamente en la creación inicial del pedido
    IDEstadoNuevo           TINYINT              NOT NULL,
    IDUsuario               INT                  NOT NULL,
    MotivoOComentario       NVARCHAR(500)        NULL,
    FechaCambio             DATETIME2(3)         NOT NULL CONSTRAINT DF_PedidoHistorialEstado_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_PedidoHistorialEstado PRIMARY KEY CLUSTERED (IDPedidoHistorialEstado),
    CONSTRAINT FK_PedidoHistorialEstado_Pedido FOREIGN KEY (IDPedido) REFERENCES dbo.Pedido (IDPedido),
    CONSTRAINT FK_PedidoHistorialEstado_EstadoAnterior FOREIGN KEY (IDEstadoAnterior) REFERENCES dbo.EstadoPedido (IDEstadoPedido),
    CONSTRAINT FK_PedidoHistorialEstado_EstadoNuevo FOREIGN KEY (IDEstadoNuevo) REFERENCES dbo.EstadoPedido (IDEstadoPedido),
    CONSTRAINT FK_PedidoHistorialEstado_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT FK_PedidoHistorialEstado_TransicionValida FOREIGN KEY (IDEstadoAnterior, IDEstadoNuevo)
        REFERENCES dbo.TransicionEstadoPedido (IDEstadoOrigen, IDEstadoDestino)
);
GO

-- Catálogo de Estados de Devolución
CREATE TABLE dbo.EstadoDevolucion (
    IDEstadoDevolucion  TINYINT       NOT NULL,
    Codigo              VARCHAR(30)   NOT NULL, -- 'SOLICITADA', 'APROBADA', 'RECHAZADA'
    Nombre              NVARCHAR(60)  NOT NULL,
    CONSTRAINT PK_EstadoDevolucion PRIMARY KEY CLUSTERED (IDEstadoDevolucion),
    CONSTRAINT UQ_EstadoDevolucion_Codigo UNIQUE (Codigo)
);
GO

-- Cabecera de Devoluciones Totales o Parciales
CREATE TABLE dbo.Devolucion (
    IDDevolucion            INT IDENTITY(1,1) NOT NULL,
    NumeroDevolucion        VARCHAR(30)       NOT NULL,
    IDPedido                INT               NOT NULL,
    IDEstadoDevolucion      TINYINT           NOT NULL,
    IDUsuarioSolicita       INT               NOT NULL,
    IDUsuarioProcesa        INT               NULL,
    EsDevolucionTotal       BIT               NOT NULL CONSTRAINT DF_Devolucion_EsTotal DEFAULT (0),
    MotivoDevolucion        NVARCHAR(500)     NOT NULL,
    MontoTotalReembolsado   DECIMAL(12,2)     NOT NULL,
    FechaSolicitud          DATETIME2(3)      NOT NULL CONSTRAINT DF_Devolucion_FechaSolicitud DEFAULT (SYSDATETIME()),
    FechaProcesamiento      DATETIME2(3)      NULL,
    CONSTRAINT PK_Devolucion PRIMARY KEY CLUSTERED (IDDevolucion),
    CONSTRAINT UQ_Devolucion_NumeroDevolucion UNIQUE (NumeroDevolucion),
    CONSTRAINT FK_Devolucion_Pedido FOREIGN KEY (IDPedido) REFERENCES dbo.Pedido (IDPedido),
    CONSTRAINT FK_Devolucion_EstadoDevolucion FOREIGN KEY (IDEstadoDevolucion) REFERENCES dbo.EstadoDevolucion (IDEstadoDevolucion),
    CONSTRAINT FK_Devolucion_UsuarioSolicita FOREIGN KEY (IDUsuarioSolicita) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT FK_Devolucion_UsuarioProcesa FOREIGN KEY (IDUsuarioProcesa) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT CK_Devolucion_MontoPositivo CHECK (MontoTotalReembolsado > 0.00)
);
GO

-- Detalle de Devolución por Línea de Pedido 
CREATE TABLE dbo.DevolucionDetalle (
    IDDevolucionDetalle     INT IDENTITY(1,1) NOT NULL,
    IDDevolucion            INT               NOT NULL,
    IDPedidoDetalle         INT               NOT NULL,
    IDVarianteProducto      INT               NOT NULL,
    CantidadDevuelta        INT               NOT NULL,
    MontoReembolsadoLinea   DECIMAL(12,2)     NOT NULL,
    MotivoLinea             NVARCHAR(300)     NULL,
    CONSTRAINT PK_DevolucionDetalle PRIMARY KEY CLUSTERED (IDDevolucionDetalle),
    CONSTRAINT UQ_DevolucionDetalle_Devolucion_Linea UNIQUE (IDDevolucion, IDPedidoDetalle),
    CONSTRAINT FK_DevolucionDetalle_Devolucion FOREIGN KEY (IDDevolucion) REFERENCES dbo.Devolucion (IDDevolucion),
    CONSTRAINT FK_DevolucionDetalle_PedidoDetalleVariante FOREIGN KEY (IDPedidoDetalle, IDVarianteProducto)
        REFERENCES dbo.PedidoDetalle (IDPedidoDetalle, IDVarianteProducto),
    CONSTRAINT CK_DevolucionDetalle_CantidadPositiva CHECK (CantidadDevuelta > 0),
    CONSTRAINT CK_DevolucionDetalle_MontoNoNegativo CHECK (MontoReembolsadoLinea >= 0.00)
);
GO


-- Catálogo de Estados de Reserva de Existencia
CREATE TABLE dbo.EstadoReserva (
    IDEstadoReserva     TINYINT       NOT NULL,
    Codigo              VARCHAR(30)   NOT NULL, -- 'ACTIVA', 'CONFIRMADA_PEDIDO', 'EXPIRADA', 'LIBERADA_CANCELACION'
    Nombre              NVARCHAR(60)  NOT NULL,
    CONSTRAINT PK_EstadoReserva PRIMARY KEY CLUSTERED (IDEstadoReserva),
    CONSTRAINT UQ_EstadoReserva_Codigo UNIQUE (Codigo)
);
GO

--  Reservas Temporales de Existencia durante Checkout 
CREATE TABLE dbo.ReservaInventario (
    IDReservaInventario     BIGINT IDENTITY(1,1) NOT NULL,
    IDCarrito               INT                  NOT NULL,
    IDVarianteProducto      INT                  NOT NULL,
    IDUsuario               INT                  NULL,
    IDEstadoReserva         TINYINT              NOT NULL CONSTRAINT DF_ReservaInventario_Estado DEFAULT (1), -- 1 = ACTIVA
    CantidadReservada       INT                  NOT NULL,
    ClaveIdempotencia       VARCHAR(100)         NOT NULL,
    IDPedidoAsociado        INT                  NULL,
    FechaCreacion           DATETIME2(3)         NOT NULL CONSTRAINT DF_ReservaInventario_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaExpiracion         DATETIME2(3)         NOT NULL, 
    FechaResolucion         DATETIME2(3)         NULL,     
    CONSTRAINT PK_ReservaInventario PRIMARY KEY CLUSTERED (IDReservaInventario),
    CONSTRAINT FK_ReservaInventario_Carrito FOREIGN KEY (IDCarrito) REFERENCES dbo.Carrito (IDCarrito),
    CONSTRAINT FK_ReservaInventario_VarianteProducto FOREIGN KEY (IDVarianteProducto) REFERENCES dbo.VarianteProducto (IDVarianteProducto),
    CONSTRAINT FK_ReservaInventario_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT FK_ReservaInventario_EstadoReserva FOREIGN KEY (IDEstadoReserva) REFERENCES dbo.EstadoReserva (IDEstadoReserva),
    CONSTRAINT FK_ReservaInventario_Pedido FOREIGN KEY (IDPedidoAsociado) REFERENCES dbo.Pedido (IDPedido),
    CONSTRAINT CK_ReservaInventario_CantidadPositiva CHECK (CantidadReservada > 0),
    CONSTRAINT CK_ReservaInventario_Vigencia CHECK (FechaExpiracion > FechaCreacion)
);
GO

-- Catálogo de Tipos de Movimiento de Kardex 
CREATE TABLE dbo.TipoMovimientoKardex (
    IDTipoMovimientoKardex  TINYINT       NOT NULL,
    Codigo                  VARCHAR(40)   NOT NULL, -- 'ENTRADA_COMPRA', 'SALIDA_VENTA', 'AJUSTE_POSITIVO', 'AJUSTE_NEGATIVO', 'ENTRADA_CANCELACION', 'ENTRADA_DEVOLUCION'
    Nombre                  NVARCHAR(80)  NOT NULL,
    FactorSigno             SMALLINT      NOT NULL, -- +1 suma a ExistenciaFisica, -1 resta a ExistenciaFisica
    EsAjusteManual          BIT           NOT NULL CONSTRAINT DF_TipoMovimientoKardex_AjusteManual DEFAULT (0),
    Activo                  BIT           NOT NULL CONSTRAINT DF_TipoMovimientoKardex_Activo DEFAULT (1),
    CONSTRAINT PK_TipoMovimientoKardex PRIMARY KEY CLUSTERED (IDTipoMovimientoKardex),
    CONSTRAINT UQ_TipoMovimientoKardex_Codigo UNIQUE (Codigo),
    CONSTRAINT CK_TipoMovimientoKardex_FactorSigno CHECK (FactorSigno IN (1, -1))
);
GO

-- Kardex de Movimientos de Inventario 
CREATE TABLE dbo.MovimientoKardex (
    IDMovimientoKardex      BIGINT IDENTITY(1,1) NOT NULL,
    IDVarianteProducto      INT                  NOT NULL,
    IDTipoMovimientoKardex  TINYINT              NOT NULL,
    IDUsuario               INT                  NOT NULL, 
    IDPedido                INT                  NULL,
    IDDevolucion            INT                  NULL,
    Cantidad                INT                  NOT NULL,
    FactorSigno             SMALLINT             NOT NULL, 
    CantidadConSigno        AS (Cantidad * FactorSigno) PERSISTED,
    ExistenciaAnterior      INT                  NOT NULL,
    ExistenciaNueva         INT                  NOT NULL,
    CostoUnitario           DECIMAL(12,2)        NULL,
    Motivo                  NVARCHAR(500)        NOT NULL, 
    FechaMovimiento         DATETIME2(3)         NOT NULL CONSTRAINT DF_MovimientoKardex_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_MovimientoKardex PRIMARY KEY CLUSTERED (IDMovimientoKardex),
    CONSTRAINT FK_MovimientoKardex_VarianteProducto FOREIGN KEY (IDVarianteProducto) REFERENCES dbo.VarianteProducto (IDVarianteProducto),
    CONSTRAINT FK_MovimientoKardex_TipoMovimiento FOREIGN KEY (IDTipoMovimientoKardex) REFERENCES dbo.TipoMovimientoKardex (IDTipoMovimientoKardex),
    CONSTRAINT FK_MovimientoKardex_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT FK_MovimientoKardex_Pedido FOREIGN KEY (IDPedido) REFERENCES dbo.Pedido (IDPedido),
    CONSTRAINT FK_MovimientoKardex_Devolucion FOREIGN KEY (IDDevolucion) REFERENCES dbo.Devolucion (IDDevolucion),
    CONSTRAINT CK_MovimientoKardex_CantidadPositiva CHECK (Cantidad > 0),
    CONSTRAINT CK_MovimientoKardex_FactorSigno CHECK (FactorSigno IN (1, -1)),
    CONSTRAINT CK_MovimientoKardex_SinExistenciaNegativa CHECK (ExistenciaAnterior >= 0 AND ExistenciaNueva >= 0),
    CONSTRAINT CK_MovimientoKardex_CuadraturaSaldo CHECK (ExistenciaNueva = ExistenciaAnterior + (Cantidad * FactorSigno)),
    CONSTRAINT CK_MovimientoKardex_MotivoNoVacio CHECK (LEN(LTRIM(RTRIM(Motivo))) >= 3)
);
GO


CREATE TABLE dbo.BitacoraAuditoria (
    IDBitacoraAuditoria     BIGINT IDENTITY(1,1) NOT NULL,
    IDModuloSistema         TINYINT              NOT NULL,
    IDUsuario               INT                  NOT NULL,
    Entidad                 VARCHAR(100)         NOT NULL, -- Ej: 'Producto', 'VarianteProducto', 'Cupon', 'Pedido'
    IDRegistroEntidad       VARCHAR(100)         NOT NULL, -- ID del registro afectado
    Accion                  VARCHAR(40)          NOT NULL, 
    ResumenCambio           NVARCHAR(500)        NOT NULL,
    ValorAnteriorJson       NVARCHAR(MAX)        NULL,
    ValorNuevoJson          NVARCHAR(MAX)        NOT NULL,
    DireccionIP             VARCHAR(45)          NULL,
    FechaRegistro           DATETIME2(3)         NOT NULL CONSTRAINT DF_BitacoraAuditoria_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_BitacoraAuditoria PRIMARY KEY CLUSTERED (IDBitacoraAuditoria),
    CONSTRAINT FK_BitacoraAuditoria_ModuloSistema FOREIGN KEY (IDModuloSistema) REFERENCES dbo.ModuloSistema (IDModuloSistema),
    CONSTRAINT FK_BitacoraAuditoria_Usuario FOREIGN KEY (IDUsuario) REFERENCES dbo.Usuario (IDUsuario),
    CONSTRAINT CK_BitacoraAuditoria_AccionValida CHECK (
        Accion IN ('CREACION', 'MODIFICACION', 'DESACTIVACION', 'REACTIVACION', 'CAMBIO_PRECIO', 'AJUSTE_EXISTENCIA', 'CAMBIO_ESTADO')
    ),
    CONSTRAINT CK_BitacoraAuditoria_JsonValido CHECK (
        (ValorAnteriorJson IS NULL OR ISJSON(ValorAnteriorJson) = 1) AND
        ISJSON(ValorNuevoJson) = 1
    )
);
GO

-- Trigger para proteger en Base de Datos
CREATE OR ALTER TRIGGER dbo.TR_BitacoraAuditoria_Inmutable
ON dbo.BitacoraAuditoria
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 50009, N'Violación de integridad (RF-09): Los registros de BitacoraAuditoria son inmutables y no pueden modificarse ni eliminarse.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_MovimientoKardex_Inmutable
ON dbo.MovimientoKardex
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 50010, N'Violación de integridad (RF-03): El historial del Kardex es inmutable y no permite modificaciones ni eliminaciones; registre un nuevo movimiento de ajuste.', 1;
END;
GO

-- Catálogo de Productos y Búsqueda por filtros 
CREATE NONCLUSTERED INDEX IX_Producto_Categoria_Activo
    ON dbo.Producto (IDCategoria, Activo)
    INCLUDE (Nombre, Slug, Marca);

CREATE NONCLUSTERED INDEX IX_VarianteProducto_Producto_Precio_Disponible
    ON dbo.VarianteProducto (IDProducto, Activo, PrecioActual, ExistenciaDisponible)
    INCLUDE (SKU, NombreVariante, ExistenciaFisica, ExistenciaReservada);

-- Kardex y Reservas Vencidas 
CREATE NONCLUSTERED INDEX IX_MovimientoKardex_Variante_Fecha
    ON dbo.MovimientoKardex (IDVarianteProducto, FechaMovimiento DESC)
    INCLUDE (IDTipoMovimientoKardex, CantidadConSigno, ExistenciaAnterior, ExistenciaNueva, IDUsuario);

CREATE NONCLUSTERED INDEX IX_ReservaInventario_Expiracion_Activas
    ON dbo.ReservaInventario (IDEstadoReserva, FechaExpiracion)
    INCLUDE (IDVarianteProducto, CantidadReservada, IDCarrito)
    WHERE IDEstadoReserva = 1; 

-- Carrito y Detección de Carritos Abandonados
CREATE NONCLUSTERED INDEX IX_Carrito_Usuario_Estado
    ON dbo.Carrito (IDUsuario, IDEstadoCarrito)
    INCLUDE (TokenInvitado, IDCupon, FechaUltimaActividad);

CREATE NONCLUSTERED INDEX IX_Carrito_TokenInvitado
    ON dbo.Carrito (TokenInvitado, IDEstadoCarrito)
    WHERE TokenInvitado IS NOT NULL;

CREATE NONCLUSTERED INDEX IX_Carrito_Actividad_Abandonados
    ON dbo.Carrito (IDEstadoCarrito, FechaUltimaActividad)
    INCLUDE (IDUsuario, TokenInvitado);

-- Pedidos y Dashboard de Ventas 
CREATE NONCLUSTERED INDEX IX_Pedido_FechaCreacion_Estado
    ON dbo.Pedido (FechaCreacion DESC, IDEstadoPedido)
    INCLUDE (IDUsuario, NumeroPedido, SubtotalBruto, DescuentoCupon, TotalPedido, TotalDevueltoAcumulado);

CREATE NONCLUSTERED INDEX IX_Pedido_Usuario_Fecha
    ON dbo.Pedido (IDUsuario, FechaCreacion DESC)
    INCLUDE (NumeroPedido, IDEstadoPedido, TotalPedido);

CREATE NONCLUSTERED INDEX IX_PedidoDetalle_Variante_Ventas
    ON dbo.PedidoDetalle (IDVarianteProducto)
    INCLUDE (IDPedido, CantidadComprada, CantidadDevuelta, CantidadNeta, PrecioUnitarioCongelado, TotalNetaLinea);

-- Uso de Cupones por Cliente 
CREATE NONCLUSTERED INDEX IX_CuponUso_Cupon_Usuario
    ON dbo.CuponUso (IDCupon, IDUsuario)
    INCLUDE (IDPedido, MontoDescuentoAplicado);

-- Bitácoras 
CREATE NONCLUSTERED INDEX IX_BitacoraAuditoria_Modulo_Fecha
    ON dbo.BitacoraAuditoria (IDModuloSistema, FechaRegistro DESC)
    INCLUDE (IDUsuario, Entidad, IDRegistroEntidad, Accion, ResumenCambio);

CREATE NONCLUSTERED INDEX IX_BitacoraError_Modulo_Fecha
    ON dbo.BitacoraError (IDModuloSistema, FechaRegistro DESC)
    INCLUDE (IDSeveridadError, OrigenError, ObjetoOMetodo, CodigoErrorAplicacion, Resuelto);

CREATE NONCLUSTERED INDEX IX_BitacoraError_CodigoCorrelacion
    ON dbo.BitacoraError (CodigoCorrelacion)
    WHERE CodigoCorrelacion IS NOT NULL;
GO


-- Módulos del Sistema
INSERT INTO dbo.ModuloSistema (Codigo, Nombre, Descripcion) VALUES
('AUTENTICACION', N'Autenticación y Acceso', N'Gestión de usuarios, roles, JWT y refresh tokens (RF-01)'),
('CATALOGO',      N'Catálogo de Productos',  N'Categorías, productos, variantes, SKUs y precios (RF-02)'),
('INVENTARIO',    N'Inventario y Kardex',    N'Existencias físicas, reservas y movimientos de kardex (RF-03)'),
('CARRITO',       N'Carrito de Compras',     N'Carritos de clientes y visitantes invitados (RF-04)'),
('CUPONES',       N'Cupones y Promociones',  N'Descuentos porcentuales y fijos con reglas de vigencia (RF-05)'),
('CHECKOUT',      N'Checkout y Pago',        N'Reserva temporal de 15 min, cobro idempotente y creación atómica (RF-06)'),
('PEDIDOS',       N'Pedidos y Devoluciones', N'Ciclo de vida de pedidos, estados y devoluciones (RF-07)'),
('DASHBOARD',     N'Dashboard y Reportes',   N'Indicadores de ventas, top productos y carritos abandonados (RF-08)'),
('BITACORA',      N'Bitácora de Auditoría',  N'Trazabilidad inmutable de cambios críticos (RF-09)'),
('SISTEMA',       N'Configuración General',  N'Parámetros globales de tienda, impuestos y registro centralizado de errores');

-- Severidades de Error
INSERT INTO dbo.SeveridadError (IDSeveridadError, Codigo, Nombre, Descripcion) VALUES
(1, 'WARNING',  N'Advertencia', N'Validación de negocio o condición controlada (ej. cupón vencido, stock insuficiente al pagar)'),
(2, 'ERROR',    N'Error',       N'Excepción capturada en un bloque catch del backend o de un Stored Procedure'),
(3, 'CRITICAL', N'Crítico',     N'Fallo grave de base de datos, transacción abortada o servicio no disponible');

-- 9.3 Roles
INSERT INTO dbo.Rol (Codigo, Nombre, Descripcion) VALUES
('CLIENTE',       N'Cliente',       N'Compra y consulta únicamente su propia información: carrito, pedidos y direcciones'),
('OPERADOR',      N'Operador',      N'Gestiona preparación y despacho de pedidos, devoluciones y movimientos de inventario'),
('ADMINISTRADOR', N'Administrador', N'Acceso total: gestiona catálogo, precios, cupones, usuarios, reportes, configuración y bitácoras');

-- 9.4 Tipos y Ámbitos de Cupón 
INSERT INTO dbo.TipoDescuentoCupon (IDTipoDescuentoCupon, Codigo, Nombre) VALUES
(1, 'PORCENTAJE', N'Porcentaje (%)'),
(2, 'MONTO_FIJO', N'Monto Fijo (Q)');

INSERT INTO dbo.AmbitoCupon (IDAmbitoCupon, Codigo, Nombre) VALUES
(1, 'CARRITO_COMPLETO', N'Aplica a todo el carrito'),
(2, 'CATEGORIA',        N'Aplica solo a una categoría específica');

-- 9.5 Estados del Carrito 
INSERT INTO dbo.EstadoCarrito (IDEstadoCarrito, Codigo, Nombre) VALUES
(1, 'ACTIVO',      N'Activo'),
(2, 'EN_CHECKOUT', N'En proceso de Checkout'),
(3, 'CONVERTIDO',  N'Convertido en Pedido'),
(4, 'ABANDONADO',  N'Carrito Abandonado'),
(5, 'FUSIONADO',   N'Fusionado con sesión de Cliente');

-- 9.6 Estados del Pedido y Matriz de Transiciones Permitidas
INSERT INTO dbo.EstadoPedido (IDEstadoPedido, Codigo, Nombre, Descripcion, PermiteCancelacion, PermiteDevolucion, EsEstadoFinal, ConsiderarEnReporteVentas, OrdenCicloVida) VALUES
(1, 'PAGADO',           N'Pagado / Confirmado', N'Pedido confirmado con pago aprobado; pendiente de preparación', 1, 0, 0, 1, 1),
(2, 'EN_PREPARACION',   N'En Preparación',      N'El operador está empacando los productos en bodega',            1, 0, 0, 1, 2),
(3, 'DESPACHADO',       N'Despachado / En Ruta',N'El pedido salió de bodega; ya no permite cancelación directa',   0, 0, 0, 1, 3),
(4, 'ENTREGADO',        N'Entregado',           N'Pedido entregado al cliente; habilita devoluciones',            0, 1, 0, 1, 4),
(5, 'DEVUELTO_PARCIAL', N'Devuelto Parcial',    N'Entregado con devolución parcial de una o más líneas',          0, 1, 0, 1, 5),
(6, 'DEVUELTO_TOTAL',   N'Devuelto Total',      N'Totalidad de unidades devueltas y reintegradas al kardex',      0, 0, 1, 0, 6),
(7, 'CANCELADO',        N'Cancelado',           N'Cancelado antes del despacho; existencias reintegradas',        0, 0, 1, 0, 7);

-- Transiciones válidas del ciclo de vida del pedido 
INSERT INTO dbo.TransicionEstadoPedido (IDEstadoOrigen, IDEstadoDestino, RequiereMotivo, ReintegraInventario) VALUES
(1, 2, 0, 0), -- PAGADO -> EN_PREPARACION
(1, 7, 1, 1), -- PAGADO -> CANCELADO (Antes de despacho, reintegra inventario)
(2, 3, 0, 0), -- EN_PREPARACION -> DESPACHADO
(2, 7, 1, 1), -- EN_PREPARACION -> CANCELADO (Antes de despacho, reintegra inventario)
(3, 4, 0, 0), -- DESPACHADO -> ENTREGADO
(4, 5, 1, 1), -- ENTREGADO -> DEVUELTO_PARCIAL
(4, 6, 1, 1), -- ENTREGADO -> DEVUELTO_TOTAL
(5, 6, 1, 1); -- DEVUELTO_PARCIAL -> DEVUELTO_TOTAL

-- Estados de Reserva y Devolución
INSERT INTO dbo.EstadoReserva (IDEstadoReserva, Codigo, Nombre) VALUES
(1, 'ACTIVA',               N'Reserva Activa (15 min)'),
(2, 'CONFIRMADA_PEDIDO',    N'Confirmada en Pedido'),
(3, 'EXPIRADA',             N'Expirada por Tiempo'),
(4, 'LIBERADA_CANCELACION', N'Liberada por el Cliente');

INSERT INTO dbo.EstadoDevolucion (IDEstadoDevolucion, Codigo, Nombre) VALUES
(1, 'SOLICITADA', N'Solicitada'),
(2, 'APROBADA',   N'Aprobada y Reintegrada a Kardex'),
(3, 'RECHAZADA',  N'Rechazada');

-- Métodos de Pago
INSERT INTO dbo.MetodoPago (Codigo, Nombre) VALUES
('TARJETA_CREDITO_DEBITO', N'Tarjeta de Crédito o Débito'),
('TRANSFERENCIA_BANCARIA', N'Transferencia Bancaria'),
('PAGO_CONTRA_ENTREGA',    N'Efectivo Contra Entrega');

-- Tipos de Movimiento de Kardex 
INSERT INTO dbo.TipoMovimientoKardex (IDTipoMovimientoKardex, Codigo, Nombre, FactorSigno, EsAjusteManual) VALUES
(1, 'ENTRADA_COMPRA',      N'Entrada por Compra / Abastecimiento', +1, 0),
(2, 'SALIDA_VENTA',        N'Salida por Venta Confirmada',         -1, 0),
(3, 'AJUSTE_POSITIVO',     N'Ajuste Manual Positivo de Inventario',+1, 1),
(4, 'AJUSTE_NEGATIVO',     N'Ajuste Manual Negativo de Inventario',-1, 1),
(5, 'ENTRADA_CANCELACION', N'Reintegro por Cancelación de Pedido', +1, 0),
(6, 'ENTRADA_DEVOLUCION',  N'Reintegro por Devolución de Cliente', +1, 0);

--  Configuraciones Operativas y de Negocio propias de ShopCart
INSERT INTO dbo.ConfiguracionSistema (IDModuloSistema, Clave, Valor, TipoDato, ValorMinimo, ValorMaximo, Descripcion) VALUES
(6,  'CHECKOUT_TIEMPO_RESERVA_MIN',       '15',    'INT',     1,   60,     N'Minutos que dura la reserva temporal de existencia al iniciar el checkout (RF-06)'),
(4,  'CARRITO_ABANDONADO_MINUTOS',        '60',    'INT',     10,  10080,  N'Minutos sin actividad para considerar un carrito con productos como abandonado (Glosario p.4)'),
(2,  'IMPUESTO_IVA_PORCENTAJE',           '12.00', 'DECIMAL', 0,   100,    N'Porcentaje de IVA incluido en los precios publicados en Quetzales (Sección 02)'),
(10, 'MONEDA_CODIGO_ISO',                 'GTQ',   'STRING',  NULL,NULL,   N'Código ISO de la moneda oficial de la plataforma (Quetzales)'),
(6,  'ENVIO_COSTO_ESTANDAR_GTQ',          '25.00', 'DECIMAL', 0,   500,    N'Costo de envío estándar en Quetzales aplicado durante el checkout (RF-06)'),
(6,  'ENVIO_GRATIS_MONTO_MINIMO_GTQ',     '500.00','DECIMAL', 0,   10000,  N'Monto mínimo de compra en Quetzales para otorgar envío gratuito'),
(3,  'INVENTARIO_STOCK_MINIMO_DEFAULT',   '5',     'INT',     0,   1000,   N'Umbral predeterminado para alertas de bajo inventario en variantes nuevas'),
(2,  'PAGINACION_LIMITE_MAXIMO',          '100',   'INT',     10,  500,    N'Cantidad máxima de registros permitidos por página en listados del servidor (RF-02 y RF-08)'),
(1,  'AUTH_MAX_INTENTOS_FALLIDOS',        '5',     'INT',     3,   15,     N'Intentos fallidos de inicio de sesión antes de bloquear temporalmente la cuenta (RF-01 / Extra)'),
(1,  'AUTH_TIEMPO_BLOQUEO_MINUTOS',       '15',    'INT',     1,   120,    N'Minutos que permanece bloqueada una cuenta tras superar los intentos fallidos de login');
GO


IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_BitacoraAuditoria_AccionValida')
BEGIN
    ALTER TABLE dbo.BitacoraAuditoria DROP CONSTRAINT CK_BitacoraAuditoria_AccionValida;
END;
GO

ALTER TABLE dbo.BitacoraAuditoria ADD CONSTRAINT CK_BitacoraAuditoria_AccionValida CHECK (
    Accion IN ('CREACION', 'MODIFICACION', 'DESACTIVACION', 'REACTIVACION', 'CAMBIO_PRECIO', 'AJUSTE_EXISTENCIA', 'CAMBIO_ESTADO', 'ELIMINACION', 'DEVOLUCION')
);
GO