import { getDbPool, sql } from '../../config/database.js';
import { CrearCuponInput } from './carrito.schema.js';

export class CarritoRepository {
  private formatearRespuestaCarrito(result: sql.IProcedureResult<any>) {
    const tablas = result.recordsets as sql.IRecordSet<any>[];
    const items = tablas[0] || [];
    const resumen = tablas[1]?.[0] || null;
    return { resumen, items };
  }

  async obtenerCarrito(idUsuario: number | null, tokenInvitado: string | null) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDUsuario', sql.Int, idUsuario)
      .input('TokenInvitado', sql.VarChar(100), tokenInvitado)
      .execute('dbo.SP_Carrito_ObtenerDetalleCompleto');
    return this.formatearRespuestaCarrito(result);
  }

  async agregarOActualizarItem(
    idUsuario: number | null,
    tokenInvitado: string | null,
    idVarianteProducto: number,
    cantidad: number,
    esSuma: boolean
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDUsuario', sql.Int, idUsuario)
      .input('TokenInvitado', sql.VarChar(100), tokenInvitado)
      .input('IDVarianteProducto', sql.Int, idVarianteProducto)
      .input('Cantidad', sql.Int, cantidad)
      .input('EsSuma', sql.Bit, esSuma ? 1 : 0)
      .execute('dbo.SP_Carrito_AgregarOActualizarItem');
    return this.formatearRespuestaCarrito(result);
  }

  async eliminarItem(idUsuario: number | null, tokenInvitado: string | null, idVarianteProducto: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDUsuario', sql.Int, idUsuario)
      .input('TokenInvitado', sql.VarChar(100), tokenInvitado)
      .input('IDVarianteProducto', sql.Int, idVarianteProducto)
      .execute('dbo.SP_Carrito_EliminarItem');
    return this.formatearRespuestaCarrito(result);
  }

  async aplicarCupon(idUsuario: number | null, tokenInvitado: string | null, codigoCupon: string) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDUsuario', sql.Int, idUsuario)
      .input('TokenInvitado', sql.VarChar(100), tokenInvitado)
      .input('CodigoCupon', sql.VarChar(50), codigoCupon)
      .execute('dbo.SP_Carrito_AplicarCupon');
    return this.formatearRespuestaCarrito(result);
  }

  async removerCupon(idUsuario: number | null, tokenInvitado: string | null) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('IDUsuario', sql.Int, idUsuario)
      .input('TokenInvitado', sql.VarChar(100), tokenInvitado)
      .execute('dbo.SP_Carrito_RemoverCupon');
    return this.formatearRespuestaCarrito(result);
  }

  async listarCupones() {
    const pool = await getDbPool();
    const result = await pool.request().execute('dbo.SP_Cupones_ListarCupones');
    return result.recordset;
  }

  async crearCupon(input: CrearCuponInput, idUsuarioAdmin: number, ip?: string) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input('Codigo', sql.VarChar(50), input.codigo)
      .input('Descripcion', sql.NVarChar(300), input.descripcion)
      .input('IDTipoDescuentoCupon', sql.TinyInt, input.idTipoDescuentoCupon)
      .input('ValorDescuento', sql.Decimal(12, 2), input.valorDescuento)
      .input('IDAmbitoCupon', sql.TinyInt, input.idAmbitoCupon)
      .input('IDCategoria', sql.Int, input.idCategoria ?? null)
      .input('MontoMinimoCompra', sql.Decimal(12, 2), input.montoMinimoCompra)
      .input('MontoMaximoDescuento', sql.Decimal(12, 2), input.montoMaximoDescuento ?? null)
      .input('LimiteTotalUsos', sql.Int, input.limiteTotalUsos)
      .input('LimiteUsosPorCliente', sql.Int, input.limiteUsosPorCliente)
      .input('FechaInicioVigencia', sql.DateTime2(3), new Date(input.fechaInicioVigencia))
      .input('FechaFinVigencia', sql.DateTime2(3), new Date(input.fechaFinVigencia))
      .input('IDUsuarioAdmin', sql.Int, idUsuarioAdmin)
      .input('DireccionIP', sql.VarChar(45), ip ?? null)
      .execute('dbo.SP_Cupones_CrearCupon');
    return result.recordset[0];
  }
}