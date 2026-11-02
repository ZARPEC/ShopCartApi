import { Request, Response, NextFunction } from 'express';
import { InventarioService } from './inventario.service.js';
import { ConsultarKardexQuerySchema, RegistrarMovimientoSchema } from './inventario.schema.js';

export class InventarioController {
  private service = new InventarioService();

  registrarMovimiento = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = RegistrarMovimientoSchema.parse(req.body);
      const idUsuario = req.usuario!.idUsuario;
      const resultado = await this.service.registrarMovimiento(data, idUsuario, req.ip);
      res.status(201).json({
        ok: true,
        mensaje: 'Movimiento de inventario registrado en Kardex exitosamente.',
        movimiento: resultado,
      });
    } catch (error) {
      next(error);
    }
  };

  obtenerKardexPorVariante = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idVariante = Number(String(req.params.idVariante));
      const query = ConsultarKardexQuerySchema.parse(req.query);
      const resultado = await this.service.obtenerKardexPorVariante(idVariante, query);
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };
}