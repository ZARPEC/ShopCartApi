import { getDbPool, sql } from '../../config/database.js';
import { ConsultarKardexQuery, RegistrarMovimientoInput } from './inventario.schema.js';

export class InventarioRepository {
  async registrarMovimiento(input: RegistrarMovimientoInput, idUsuario: number, ip?: string) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDVarianteProducto', sql.Int, input.idVarianteProducto)
      .input('CodigoTipoMovimiento', sql.VarChar(40), input.tipoMovimiento)
      .input('Cantidad', sql.Int, input.cantidad)
      .input('Motivo', sql.NVarChar(500), input.motivo)
      .input('CostoUnitario', sql.Decimal(12, 2), input.costoUnitario ?? null)
      .input('IDUsuario', sql.Int, idUsuario)
      .input('DireccionIP', sql.VarChar(45), ip ?? null)
      .execute('dbo.SP_Inventario_RegistrarMovimiento');

    return result.recordset[0];
  }

  async obtenerKardexPorVariante(idVarianteProducto: number, query: ConsultarKardexQuery) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDVarianteProducto', sql.Int, idVarianteProducto)
      .input('Pagina', sql.Int, query.pagina)
      .input('Limite', sql.Int, query.limite)
      .execute('dbo.SP_Inventario_ObtenerKardexPorVariante');

    const tablas = result.recordsets as sql.IRecordSet<any>[];
    const resumenVariante = tablas[0]?.[0] || null;
    const movimientos = tablas[1] || [];

    return resumenVariante ? { resumenVariante, movimientos } : null;
  }
}