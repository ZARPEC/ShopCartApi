import { Request, Response, NextFunction } from 'express';
import { AppError } from '../../shared/errors/AppError.js';
import { CarritoRepository } from './carrito.repository.js';
import {
  ActualizarCantidadItemSchema,
  AgregarItemCarritoSchema,
  AplicarCuponCarritoSchema,
  CrearCuponSchema,
} from './carrito.schema.js';

export class CarritoController {
  private repo = new CarritoRepository();

  private extraerIdentidad(req: Request, tokenEnBody?: string) {
    const idUsuario = req.usuario?.idUsuario ?? null;
    const headerGuest = req.headers['x-guest-token'];
    const tokenInvitado =
      tokenEnBody ||
      (typeof headerGuest === 'string' ? headerGuest : null) ||
      (typeof req.query.tokenInvitado === 'string' ? req.query.tokenInvitado : null);

    if (!idUsuario && !tokenInvitado) {
      throw new AppError(
        'Debe iniciar sesión o enviar un x-guest-token para gestionar el carrito.',
        400,
        'IDENTIDAD_CARRITO_REQUERIDA',
        'CARRITO',
        1
      );
    }

    return { idUsuario, tokenInvitado };
  }

  obtenerCarrito = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { idUsuario, tokenInvitado } = this.extraerIdentidad(req);
      const carrito = await this.repo.obtenerCarrito(idUsuario, tokenInvitado);
      res.status(200).json({ ok: true, ...carrito });
    } catch (error) {
      next(error);
    }
  };

  agregarItem = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = AgregarItemCarritoSchema.parse(req.body);
      const { idUsuario, tokenInvitado } = this.extraerIdentidad(req, data.tokenInvitado);
      const carrito = await this.repo.agregarOActualizarItem(
        idUsuario,
        tokenInvitado,
        data.idVarianteProducto,
        data.cantidad,
        true
      );
      res.status(200).json({ ok: true, mensaje: 'Producto agregado al carrito.', ...carrito });
    } catch (error) {
      next(error);
    }
  };

  actualizarCantidadItem = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idVariante = Number(String(req.params.idVariante));
      const data = ActualizarCantidadItemSchema.parse(req.body);
      const { idUsuario, tokenInvitado } = this.extraerIdentidad(req, data.tokenInvitado);
      const carrito = await this.repo.agregarOActualizarItem(
        idUsuario,
        tokenInvitado,
        idVariante,
        data.cantidad,
        false
      );
      res.status(200).json({ ok: true, mensaje: 'Cantidad actualizada.', ...carrito });
    } catch (error) {
      next(error);
    }
  };

  eliminarItem = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idVariante = Number(String(req.params.idVariante));
      const { idUsuario, tokenInvitado } = this.extraerIdentidad(req);
      const carrito = await this.repo.eliminarItem(idUsuario, tokenInvitado, idVariante);
      res.status(200).json({ ok: true, mensaje: 'Producto eliminado del carrito.', ...carrito });
    } catch (error) {
      next(error);
    }
  };

  aplicarCupon = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = AplicarCuponCarritoSchema.parse(req.body);
      const { idUsuario, tokenInvitado } = this.extraerIdentidad(req, data.tokenInvitado);
      const carrito = await this.repo.aplicarCupon(idUsuario, tokenInvitado, data.codigoCupon);
      res.status(200).json({ ok: true, mensaje: 'Cupón aplicado exitosamente.', ...carrito });
    } catch (error) {
      next(error);
    }
  };

  removerCupon = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { idUsuario, tokenInvitado } = this.extraerIdentidad(req);
      const carrito = await this.repo.removerCupon(idUsuario, tokenInvitado);
      res.status(200).json({ ok: true, mensaje: 'Cupón removido del carrito.', ...carrito });
    } catch (error) {
      next(error);
    }
  };

  listarCupones = async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const cupones = await this.repo.listarCupones();
      res.status(200).json({ ok: true, cupones });
    } catch (error) {
      next(error);
    }
  };

  crearCupon = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = CrearCuponSchema.parse(req.body);
      const cupon = await this.repo.crearCupon(data, req.usuario!.idUsuario, req.ip);
      res.status(201).json({ ok: true, mensaje: 'Cupón creado exitosamente.', cupon });
    } catch (error) {
      next(error);
    }
  };
}