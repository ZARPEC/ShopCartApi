import { getDbPool, sql } from '../../config/database.js';
import {
  ICategoria,
  IProductoDetalle,
  IProductoItemPaginado,
  IVarianteDetalle,
} from './catalogo.types.js';

import {
  CrearCategoriaInput,
  CrearProductoInput,
  CrearVarianteInput,
  ListarProductosQuery,
} from './catalogo.schema.js';

export class CatalogoRepository {
  async listarCategorias(soloActivas = true): Promise<ICategoria[]> {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('SoloActivas', sql.Bit, soloActivas)
      .execute<ICategoria>('dbo.SP_Catalogo_ListarCategorias');
    return result.recordset;
  }

  async crearCategoria(input: CrearCategoriaInput) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('Nombre', sql.NVarChar(100), input.nombre)
      .input('Slug', sql.VarChar(120), input.slug)
      .input('Descripcion', sql.NVarChar(400), input.descripcion ?? null)
      .input('IDCategoriaPadre', sql.Int, input.idCategoriaPadre ?? null)
      .execute('dbo.SP_Catalogo_CrearCategoria');
    return result.recordset[0];
  }

  async listarProductos(filtros: ListarProductosQuery): Promise<IProductoItemPaginado[]> {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('BuscarTexto', sql.NVarChar(100), filtros.buscar ?? null)
      .input('SlugCategoria', sql.VarChar(120), filtros.categoria ?? null)
      .input('PrecioMin', sql.Decimal(12, 2), filtros.precioMin ?? null)
      .input('PrecioMax', sql.Decimal(12, 2), filtros.precioMax ?? null)
      .input('SoloDisponibles', sql.Bit, filtros.soloDisponibles ? 1 : 0)
      .input('Orden', sql.VarChar(20), filtros.orden)
      .input('Pagina', sql.Int, filtros.pagina)
      .input('Limite', sql.Int, filtros.limite)
      .execute<IProductoItemPaginado>('dbo.SP_Catalogo_ListarProductos');
    return result.recordset;
  }

async obtenerProductoPorSlug(slug: string): Promise<IProductoDetalle | null> {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('Slug', sql.VarChar(220), slug)
      .execute('dbo.SP_Catalogo_ObtenerDetalleProducto');

    const tablas = result.recordsets as sql.IRecordSet<any>[];
    const producto = tablas[0]?.[0] || null;
    const variantes: IVarianteDetalle[] = (tablas[1] as IVarianteDetalle[]) || [];
    const imagenes = tablas[2] || [];

    return producto ? { ...producto, variantes, imagenes } : null;
  }

  async crearProducto(input: CrearProductoInput) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDCategoria', sql.Int, input.idCategoria)
      .input('Nombre', sql.NVarChar(200), input.nombre)
      .input('Slug', sql.VarChar(220), input.slug)
      .input('Descripcion', sql.NVarChar(2000), input.descripcion ?? null)
      .input('Marca', sql.NVarChar(100), input.marca ?? null)
      .input('PorcentajeIVA', sql.Decimal(5, 2), input.porcentajeIVA)
      .execute('dbo.SP_Catalogo_CrearProducto');
    return result.recordset[0];
  }

  async crearVariante(idProducto: number, input: CrearVarianteInput, idUsuarioOperador: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDProducto', sql.Int, idProducto)
      .input('SKU', sql.VarChar(60), input.sku)
      .input('NombreVariante', sql.NVarChar(150), input.nombreVariante)
      .input('PrecioActual', sql.Decimal(12, 2), input.precioActual)
      .input('ExistenciaInicial', sql.Int, input.existenciaInicial)
      .input('StockMinimoAlerta', sql.Int, input.stockMinimoAlerta)
      .input('IDUsuarioOperador', sql.Int, idUsuarioOperador)
      .execute('dbo.SP_Catalogo_CrearVariante');
    return result.recordset[0];
  }

  async desactivarProducto(idProducto: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDProducto', sql.Int, idProducto)
      .execute('dbo.SP_Catalogo_DesactivarProducto');
    return result.recordset[0];
  }
}