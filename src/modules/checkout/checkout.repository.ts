import { getDbPool, sql } from "../../config/database.js";
import {
  AvanzarEstadoPedidoInput,
  CancelarPedidoInput,
  ConfirmarPagoInput,
  CrearDireccionInput,
  RegistrarDevolucionInput,
} from "./checkout.schema.js";

export class CheckoutRepository {
  async crearDireccion(input: CrearDireccionInput, idUsuario: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDUsuario", sql.Int, idUsuario)
      .input("Alias", sql.NVarChar(60), input.alias)
      .input("NombreRecibe", sql.NVarChar(150), input.nombreRecibe)
      .input("TelefonoContacto", sql.VarChar(30), input.telefonoContacto)
      .input("Departamento", sql.NVarChar(100), input.departamento)
      .input("Municipio", sql.NVarChar(100), input.municipio)
      .input("Zona", sql.VarChar(20), input.zona ?? null)
      .input("DireccionExacta", sql.NVarChar(500), input.direccionExacta)
      .input("Referencias", sql.NVarChar(400), input.referencias ?? null)
      .input("EsPredeterminada", sql.Bit, input.esPredeterminada ? 1 : 0)
      .execute("dbo.SP_Direcciones_Registrar");
    return result.recordset[0];
  }

  async listarDirecciones(idUsuario: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDUsuario", sql.Int, idUsuario)
      .execute("dbo.SP_Direcciones_ListarPorUsuario");
    return result.recordset;
  }

  async iniciarReserva(idUsuario: number, idCarrito?: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDUsuario", sql.Int, idUsuario)
      .input("IDCarrito", sql.Int, idCarrito ?? null)
      .execute("dbo.SP_Checkout_IniciarReserva");
    return result.recordset[0];
  }

  async confirmarPago(input: ConfirmarPagoInput, idUsuario: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDUsuario", sql.Int, idUsuario)
      .input("IDDireccionCliente", sql.Int, input.idDireccionCliente)
      .input("IDMetodoPago", sql.TinyInt, input.idMetodoPago)
      .input("ClaveIdempotencia", sql.VarChar(100), input.claveIdempotencia)
      .input("NotasCliente", sql.NVarChar(500), input.notasCliente ?? null)
      .execute("dbo.SP_Checkout_ConfirmarPagoYCrearPedido");
    return result.recordset[0];
  }

  async avanzarEstadoPedido(
    idPedido: number,
    input: AvanzarEstadoPedidoInput,
    idUsuarioOperador: number,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDPedido", sql.Int, idPedido)
      .input("IDEstadoNuevo", sql.TinyInt, input.idEstadoNuevo)
      .input("IDUsuarioOperador", sql.Int, idUsuarioOperador)
      .input("Motivo", sql.NVarChar(500), input.motivo ?? null)
      .execute("dbo.SP_Pedidos_AvanzarEstado");
    return result.recordset[0];
  }

  async cancelarPedido(
    idPedido: number,
    input: CancelarPedidoInput,
    idUsuario: number,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDPedido", sql.Int, idPedido)
      .input("IDUsuario", sql.Int, idUsuario)
      .input("Motivo", sql.NVarChar(500), input.motivo)
      .execute("dbo.SP_Pedidos_CancelarPedido");
    return result.recordset[0];
  }

  async registrarDevolucion(
    idPedido: number,
    input: RegistrarDevolucionInput,
    idUsuarioOperador: number,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDPedido", sql.Int, idPedido)
      .input("IDPedidoDetalle", sql.Int, input.idPedidoDetalle)
      .input("CantidadDevolver", sql.Int, input.cantidadDevolver)
      .input("Motivo", sql.NVarChar(500), input.motivo)
      .input("IDUsuarioOperador", sql.Int, idUsuarioOperador)
      .execute("dbo.SP_Pedidos_RegistrarDevolucion");
    return result.recordset[0];
  }

  async liberarReservasVencidas() {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .execute("dbo.SP_Inventario_LiberarReservasVencidas");
    return result.recordset[0]?.TotalReservasLiberadas ?? 0;
  }

  async listarPedidosPorUsuario(idUsuario: number, pagina = 1, limite = 10) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDUsuario", sql.Int, idUsuario)
      .input("Pagina", sql.Int, pagina)
      .input("Limite", sql.Int, limite)
      .execute("dbo.SP_Pedidos_ListarPorUsuario");
    return result.recordset;
  }

  async obtenerDetallePedidoCliente(idPedido: number, idUsuario: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDPedido", sql.Int, idPedido)
      .input("IDUsuario", sql.Int, idUsuario)
      .execute("dbo.SP_Pedidos_ObtenerDetalleCliente");

    const recordsets = Array.isArray(result.recordsets)
      ? result.recordsets
      : Object.values(result.recordsets);
    const encabezado = recordsets[0]?.[0] || null;
    const lineas = recordsets[1] || [];
    return encabezado ? { ...encabezado, lineas } : null;
  }

  async liberarReserva(idCarrito: number, idUsuario?: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDCarrito", sql.Int, idCarrito)
      .input("IDUsuario", sql.Int, idUsuario ?? null)
      .execute("dbo.SP_Checkout_LiberarReserva");
    return result.recordset[0];
  }
  async eliminarDireccion(idDireccion: number, idUsuario: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDDireccionCliente", sql.Int, idDireccion)
      .input("IDUsuario", sql.Int, idUsuario)
      .execute("dbo.SP_Checkout_EliminarDireccion");
    return result.recordset[0];
  }

  async predeterminadaDireccion(idDireccion: number, idUsuario: number) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDDireccionCliente", sql.Int, idDireccion)
      .input("IDUsuario", sql.Int, idUsuario)
      .execute("dbo.SP_Checkout_EstablecerDireccionPredeterminada");
    return result.recordset[0];
  }

  async procesarDevolucion(
    idPedido: number,
    idOperador: number,
    motivo: string,
    lineas: Array<{ idPedidoDetalle: number; cantidad: number }>,
    ip?: string,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDPedido", sql.Int, idPedido)
      .input("IDUsuarioOperador", sql.Int, idOperador)
      .input("MotivoDevolucion", sql.NVarChar(500), motivo)
      .input("LineasJson", sql.NVarChar(sql.MAX), JSON.stringify(lineas))
      .input("DireccionIP", sql.VarChar(45), ip ?? null)
      .execute("dbo.SP_Pedidos_ProcesarDevolucion");
    return result.recordset[0];
  }

  async solicitarDevolucionCliente(
    idPedido: number,
    idUsuario: number,
    motivo: string,
    lineas: any[],
    ip?: string,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDPedido", sql.Int, idPedido)
      .input("IDUsuarioCliente", sql.Int, idUsuario)
      .input("MotivoDevolucion", sql.NVarChar(500), motivo)
      .input("LineasJson", sql.NVarChar(sql.MAX), JSON.stringify(lineas))
      .input("DireccionIP", sql.VarChar(45), ip ?? null)
      .execute("dbo.SP_Pedidos_SolicitarDevolucionCliente");
    return result.recordset[0];
  }
}
