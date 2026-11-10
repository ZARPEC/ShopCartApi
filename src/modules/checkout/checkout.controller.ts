import { Request, Response, NextFunction } from "express";
import { CheckoutRepository } from "./checkout.repository.js";
import {
  AvanzarEstadoPedidoSchema,
  CancelarPedidoSchema,
  ConfirmarPagoSchema,
  CrearDireccionSchema,
  IniciarReservaSchema,
  RegistrarDevolucionSchema,
} from "./checkout.schema.js";

export class CheckoutController {
  private repo = new CheckoutRepository();

  crearDireccion = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = CrearDireccionSchema.parse(req.body);
      const direccion = await this.repo.crearDireccion(
        data,
        req.usuario!.idUsuario,
      );
      res
        .status(201)
        .json({ ok: true, mensaje: "Dirección registrada.", direccion });
    } catch (error) {
      next(error);
    }
  };

  listarDirecciones = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const direcciones = await this.repo.listarDirecciones(
        req.usuario!.idUsuario,
      );
      res.status(200).json({ ok: true, direcciones });
    } catch (error) {
      next(error);
    }
  };

  iniciarReserva = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = IniciarReservaSchema.parse(req.body);
      const reserva = await this.repo.iniciarReserva(
        req.usuario!.idUsuario,
        data.idCarrito,
      );
      res.status(200).json({ ok: true, ...reserva });
    } catch (error) {
      next(error);
    }
  };

  confirmarPago = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = ConfirmarPagoSchema.parse(req.body);
      const pedido = await this.repo.confirmarPago(
        data,
        req.usuario!.idUsuario,
      );
      res
        .status(201)
        .json({ ok: true, mensaje: "Pedido creado exitosamente.", pedido });
    } catch (error) {
      next(error);
    }
  };

  avanzarEstado = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idPedido = Number(String(req.params.idPedido));
      const data = AvanzarEstadoPedidoSchema.parse(req.body);
      const resultado = await this.repo.avanzarEstadoPedido(
        idPedido,
        data,
        req.usuario!.idUsuario,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  cancelarPedido = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idPedido = Number(String(req.params.idPedido));
      const data = CancelarPedidoSchema.parse(req.body);
      const resultado = await this.repo.cancelarPedido(
        idPedido,
        data,
        req.usuario!.idUsuario,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  registrarDevolucion = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const idPedido = Number(String(req.params.idPedido));
      const data = RegistrarDevolucionSchema.parse(req.body);
      const resultado = await this.repo.registrarDevolucion(
        idPedido,
        data,
        req.usuario!.idUsuario,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  misPedidos = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idUsuario = req.usuario!.idUsuario;
      const pagina = Number(req.query.pagina) || 1;
      const limite = Number(req.query.limite) || 10;
      const repo = new CheckoutRepository();
      const pedidos = await repo.listarPedidosPorUsuario(
        idUsuario,
        pagina,
        limite,
      );
      res.status(200).json({ ok: true, pedidos });
    } catch (error) {
      next(error);
    }
  };

  detalleMiPedido = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idPedido = Number(req.params.id);
      const idUsuario = req.usuario!.idUsuario;
      const repo = new CheckoutRepository();
      const pedido = await repo.obtenerDetallePedidoCliente(
        idPedido,
        idUsuario,
      );
      res.status(200).json({ ok: true, pedido });
    } catch (error) {
      next(error);
    }
  };

  liberarReserva = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { idCarrito } = req.body;
      const repo = new CheckoutRepository();
      const resultado = await repo.liberarReserva(
        Number(idCarrito),
        req.usuario?.idUsuario,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  eliminarDireccion = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const repo = new CheckoutRepository();
      await repo.eliminarDireccion(
        Number(req.params.id),
        req.usuario!.idUsuario,
      );
      res.status(200).json({ ok: true });
    } catch (error) {
      next(error);
    }
  };

  predeterminadaDireccion = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const repo = new CheckoutRepository();
      await repo.predeterminadaDireccion(
        Number(req.params.id),
        req.usuario!.idUsuario,
      );
      res.status(200).json({ ok: true });
    } catch (error) {
      next(error);
    }
  };

  procesarDevolucion = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const idPedido = Number(req.params.id);
      const { motivo, lineas } = req.body;
      const repo = new CheckoutRepository();
      const resultado = await repo.procesarDevolucion(
        idPedido,
        req.usuario!.idUsuario,
        motivo,
        lineas,
        req.ip,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  solicitarDevolucion = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const idPedido = Number(req.params.id);
      const { motivo, lineas } = req.body;
      const repo = new CheckoutRepository();
      const resultado = await repo.solicitarDevolucionCliente(
        idPedido,
        req.usuario!.idUsuario,
        motivo,
        lineas,
        req.ip,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };
}
