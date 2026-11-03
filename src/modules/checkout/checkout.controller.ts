import { Request, Response, NextFunction } from 'express';
import { CheckoutRepository } from './checkout.repository.js';
import {
  AvanzarEstadoPedidoSchema,
  CancelarPedidoSchema,
  ConfirmarPagoSchema,
  CrearDireccionSchema,
  IniciarReservaSchema,
  RegistrarDevolucionSchema,
} from './checkout.schema.js';

export class CheckoutController {
  private repo = new CheckoutRepository();

  crearDireccion = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = CrearDireccionSchema.parse(req.body);
      const direccion = await this.repo.crearDireccion(data, req.usuario!.idUsuario);
      res.status(201).json({ ok: true, mensaje: 'Dirección registrada.', direccion });
    } catch (error) {
      next(error);
    }
  };

  listarDirecciones = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const direcciones = await this.repo.listarDirecciones(req.usuario!.idUsuario);
      res.status(200).json({ ok: true, direcciones });
    } catch (error) {
      next(error);
    }
  };

  iniciarReserva = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = IniciarReservaSchema.parse(req.body);
      const reserva = await this.repo.iniciarReserva(req.usuario!.idUsuario, data.idCarrito);
      res.status(200).json({ ok: true, ...reserva });
    } catch (error) {
      next(error);
    }
  };

  confirmarPago = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = ConfirmarPagoSchema.parse(req.body);
      const pedido = await this.repo.confirmarPago(data, req.usuario!.idUsuario);
      res.status(201).json({ ok: true, mensaje: 'Pedido creado exitosamente.', pedido });
    } catch (error) {
      next(error);
    }
  };

  avanzarEstado = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idPedido = Number(String(req.params.idPedido));
      const data = AvanzarEstadoPedidoSchema.parse(req.body);
      const resultado = await this.repo.avanzarEstadoPedido(idPedido, data, req.usuario!.idUsuario);
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  cancelarPedido = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idPedido = Number(String(req.params.idPedido));
      const data = CancelarPedidoSchema.parse(req.body);
      const resultado = await this.repo.cancelarPedido(idPedido, data, req.usuario!.idUsuario);
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  registrarDevolucion = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idPedido = Number(String(req.params.idPedido));
      const data = RegistrarDevolucionSchema.parse(req.body);
      const resultado = await this.repo.registrarDevolucion(idPedido, data, req.usuario!.idUsuario);
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };
}