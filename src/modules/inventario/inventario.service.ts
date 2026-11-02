import { AppError } from '../../shared/errors/AppError.js';
import { InventarioRepository } from './inventario.repository.js';
import { ConsultarKardexQuery, RegistrarMovimientoInput } from './inventario.schema.js';

export class InventarioService {
  private repo = new InventarioRepository();

  async registrarMovimiento(input: RegistrarMovimientoInput, idUsuario: number, ip?: string) {
    return await this.repo.registrarMovimiento(input, idUsuario, ip);
  }

  async obtenerKardexPorVariante(idVarianteProducto: number, query: ConsultarKardexQuery) {
    const resultado = await this.repo.obtenerKardexPorVariante(idVarianteProducto, query);
    if (!resultado) {
      throw new AppError('La variante solicitada no existe.', 404, 'VARIANTE_NO_ENCONTRADA', 'INVENTARIO', 1);
    }

    const primerMov = resultado.movimientos[0];
    return {
      variante: resultado.resumenVariante,
      paginacion: {
        total: primerMov?.TotalRegistros ?? 0,
        totalPaginas: primerMov?.TotalPaginas ?? 0,
        paginaActual: query.pagina,
        limite: query.limite,
      },
      movimientos: resultado.movimientos,
    };
  }
}