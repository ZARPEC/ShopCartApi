import { getDbPool, sql } from "../../config/database.js";
import {
  ConsultarBitacoraInput,
  ListarPedidosFiltros,
  Top10Filtros,
} from "./dashboard.schema.js";

export class DashboardRepository {
  async obtenerMetricasGenerales() {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .execute("dbo.SP_Dashboard_MetricasGenerales");
    return result.recordset[0];
  }

  async obtenerVentasPorCategoria() {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .execute("dbo.SP_Dashboard_VentasPorCategoria");
    return result.recordset;
  }

  async obtenerTop10Productos(filtros: Top10Filtros) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input(
        "FechaInicio",
        sql.DateTime2(3),
        filtros.fechaInicio ? new Date(filtros.fechaInicio) : null,
      )
      .input(
        "FechaFin",
        sql.DateTime2(3),
        filtros.fechaFin ? new Date(filtros.fechaFin) : null,
      )
      .execute("dbo.SP_Dashboard_Top10Productos");
    return result.recordset;
  }

  async listarPedidos(filtros: ListarPedidosFiltros) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDEstadoPedido", sql.TinyInt, filtros.idEstadoPedido ?? null)
      .input("IDCliente", sql.Int, filtros.idCliente ?? null)
      .input(
        "FechaInicio",
        sql.DateTime2(3),
        filtros.fechaInicio ? new Date(filtros.fechaInicio) : null,
      )
      .input(
        "FechaFin",
        sql.DateTime2(3),
        filtros.fechaFin ? new Date(filtros.fechaFin) : null,
      )
      .input("Pagina", sql.Int, filtros.pagina)
      .input("Limite", sql.Int, filtros.limite)
      .execute("dbo.SP_Dashboard_ListarPedidos");
    return result.recordset;
  }

  async consultarBitacoraAuditoria(filtros: ConsultarBitacoraInput) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("CodigoModulo", sql.VarChar(40), filtros.modulo ?? null)
      .input("Entidad", sql.VarChar(100), filtros.entidad ?? null)
      .input(
        "FechaInicio",
        sql.DateTime2(3),
        filtros.fechaInicio ? new Date(filtros.fechaInicio) : null,
      )
      .input(
        "FechaFin",
        sql.DateTime2(3),
        filtros.fechaFin ? new Date(filtros.fechaFin) : null,
      )
      .input("Pagina", sql.Int, filtros.pagina)
      .input("Limite", sql.Int, filtros.limite)
      .execute("dbo.SP_Bitacora_ConsultarAuditoria");
    return result.recordset;
  }

  async listarDevolucionesPendientes() {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .execute("dbo.SP_Devoluciones_ListarPendientes");
    return result.recordset;
  }

  async aprobarDevolucion(
    idDevolucion: number,
    idOperador: number,
    ip?: string,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDDevolucion", sql.Int, idDevolucion)
      .input("IDUsuarioOperador", sql.Int, idOperador)
      .input("DireccionIP", sql.VarChar(45), ip ?? null)
      .execute("dbo.SP_Devoluciones_Aprobar");
    return result.recordset[0];
  }

  async rechazarDevolucion(
    idDevolucion: number,
    idOperador: number,
    motivo: string,
    ip?: string,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDDevolucion", sql.Int, idDevolucion)
      .input("IDUsuarioOperador", sql.Int, idOperador)
      .input("MotivoRechazo", sql.NVarChar(500), motivo)
      .input("DireccionIP", sql.VarChar(45), ip ?? null)
      .execute("dbo.SP_Devoluciones_Rechazar");
    return result.recordset[0];
  }
}
