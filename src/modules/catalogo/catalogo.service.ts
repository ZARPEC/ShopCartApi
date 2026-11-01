import { AppError } from '../../shared/errors/AppError.js';
import { CatalogoRepository } from './catalogo.repository.js';
import {
  CrearCategoriaInput,
  CrearProductoInput,
  CrearVarianteInput,
  ListarProductosQuery,
} from './catalogo.schema.js';

export class CatalogoService {
  private repo = new CatalogoRepository();

  async listarCategorias() {
    return await this.repo.listarCategorias(true);
  }

  async crearCategoria(input: CrearCategoriaInput) {
    return await this.repo.crearCategoria(input);
  }

  async listarProductos(filtros: ListarProductosQuery) {
    const productos = await this.repo.listarProductos(filtros);
    const primerRegistro = productos[0];

    return {
      total: primerRegistro?.TotalRegistros ?? 0,
      totalPaginas: primerRegistro?.TotalPaginas ?? 0,
      paginaActual: filtros.pagina,
      limite: filtros.limite,
      datos: productos,
    };
  }

  async obtenerProductoPorSlug(slug: string) {
    const detalle = await this.repo.obtenerProductoPorSlug(slug);
    if (!detalle) {
      throw new AppError('El producto solicitado no existe o se encuentra inactivo.', 404, 'PRODUCTO_NO_ENCONTRADO', 'CATALOGO', 1);
    }
    return detalle;
  }

  async crearProducto(input: CrearProductoInput) {
    return await this.repo.crearProducto(input);
  }

  async crearVariante(idProducto: number, input: CrearVarianteInput, idUsuarioOperador: number) {
    return await this.repo.crearVariante(idProducto, input, idUsuarioOperador);
  }

  async desactivarProducto(idProducto: number) {
    return await this.repo.desactivarProducto(idProducto);
  }
}