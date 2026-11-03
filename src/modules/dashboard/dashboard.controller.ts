import { Request, Response, NextFunction } from 'express';
import { DashboardRepository } from './dashboard.repository.js';
import {
  ConsultarBitacoraSchema,
  ListarPedidosFiltrosSchema,
  Top10FiltrosSchema,
} from './dashboard.schema.js';

export class DashboardController {
  private repo = new DashboardRepository();

  obtenerResumen = async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const metricas = await this.repo.obtenerMetricasGenerales();
      const categorias = await this.repo.obtenerVentasPorCategoria();
      res.status(200).json({ ok: true, metricas, ventasPorCategoria: categorias });
    } catch (error) {
      next(error);
    }
  };

  obtenerTop10 = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const filtros = Top10FiltrosSchema.parse(req.query);
      const top10 = await this.repo.obtenerTop10Productos(filtros);
      res.status(200).json({ ok: true, top10 });
    } catch (error) {
      next(error);
    }
  };

  listarPedidos = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const filtros = ListarPedidosFiltrosSchema.parse(req.query);
      const pedidos = await this.repo.listarPedidos(filtros);
      const primerReg = pedidos[0];
      res.status(200).json({
        ok: true,
        paginacion: {
          total: primerReg?.TotalRegistros ?? 0,
          totalPaginas: primerReg?.TotalPaginas ?? 0,
          paginaActual: filtros.pagina,
          limite: filtros.limite,
        },
        pedidos,
      });
    } catch (error) {
      next(error);
    }
  };

  consultarBitacora = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const filtros = ConsultarBitacoraSchema.parse(req.query);
      const bitacora = await this.repo.consultarBitacoraAuditoria(filtros);
      const primerReg = bitacora[0];
      res.status(200).json({
        ok: true,
        paginacion: {
          total: primerReg?.TotalRegistros ?? 0,
          totalPaginas: primerReg?.TotalPaginas ?? 0,
          paginaActual: filtros.pagina,
          limite: filtros.limite,
        },
        registros: bitacora,
      });
    } catch (error) {
      next(error);
    }
  };
}