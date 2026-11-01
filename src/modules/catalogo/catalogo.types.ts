export interface ICategoria {
  IDCategoria: number;
  IDCategoriaPadre: number | null;
  Nombre: string;
  Slug: string;
  Descripcion: string | null;
  Activo: boolean;
  TotalProductos: number;
}

export interface IProductoItemPaginado {
  IDProducto: number;
  Nombre: string;
  Slug: string;
  Marca: string | null;
  CategoriaNombre: string;
  CategoriaSlug: string;
  PrecioMinimo: number;
  PrecioMaximo: number;
  StockTotalDisponible: number;
  TotalVariantes: number;
  UrlImagenPrincipal: string | null;
  TotalRegistros: number;
  TotalPaginas: number;
  PaginaActual: number;
}

export interface IVarianteDetalle {
  IDVarianteProducto: number;
  IDProducto: number;
  SKU: string;
  NombreVariante: string;
  PrecioActual: number;
  ExistenciaDisponible: number;
  TieneStock: number;
}

export interface IProductoDetalle {
  IDProducto: number;
  Nombre: string;
  Slug: string;
  Descripcion: string | null;
  Marca: string | null;
  PorcentajeIVA: number;
  IDCategoria: number;
  CategoriaNombre: string;
  CategoriaSlug: string;
  variantes: IVarianteDetalle[];
}