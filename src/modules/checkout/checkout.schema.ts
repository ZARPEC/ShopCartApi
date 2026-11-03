import { z } from 'zod';

export const CrearDireccionSchema = z.object({
  alias: z.string().trim().min(2).max(60),
  nombreRecibe: z.string().trim().min(3).max(150),
  telefonoContacto: z.string().trim().min(8).max(30),
  departamento: z.string().trim().min(2).max(100),
  municipio: z.string().trim().min(2).max(100),
  zona: z.string().trim().max(20).optional(),
  direccionExacta: z.string().trim().min(5).max(500),
  referencias: z.string().trim().max(400).optional(),
  esPredeterminada: z.boolean().default(false),
});

export const IniciarReservaSchema = z.object({
  idCarrito: z.number().int().positive().optional(),
});

export const ConfirmarPagoSchema = z.object({
  idDireccionCliente: z.number().int().positive('Debe seleccionar una dirección de entrega'),
  idMetodoPago: z.number().int().positive('Debe seleccionar un método de pago'),
  claveIdempotencia: z.string().trim().min(10, 'La clave de idempotencia es requerida').max(100),
  notasCliente: z.string().trim().max(500).optional(),
});

export const AvanzarEstadoPedidoSchema = z.object({
  idEstadoNuevo: z.number().int().positive(),
  motivo: z.string().trim().max(500).optional(),
});

export const CancelarPedidoSchema = z.object({
  motivo: z.string().trim().min(5, 'Debe indicar un motivo de cancelación').max(500),
});

export const RegistrarDevolucionSchema = z.object({
  idPedidoDetalle: z.number().int().positive(),
  cantidadDevolver: z.number().int().positive(),
  motivo: z.string().trim().min(5, 'Debe indicar el motivo de la devolución').max(500),
});

export type CrearDireccionInput = z.infer<typeof CrearDireccionSchema>;
export type IniciarReservaInput = z.infer<typeof IniciarReservaSchema>;
export type ConfirmarPagoInput = z.infer<typeof ConfirmarPagoSchema>;
export type AvanzarEstadoPedidoInput = z.infer<typeof AvanzarEstadoPedidoSchema>;
export type CancelarPedidoInput = z.infer<typeof CancelarPedidoSchema>;
export type RegistrarDevolucionInput = z.infer<typeof RegistrarDevolucionSchema>;