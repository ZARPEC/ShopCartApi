import { z } from 'zod';

export const AgregarItemCarritoSchema = z.object({
  idVarianteProducto: z.number().int().positive('El ID de la variante es obligatorio'),
  cantidad: z.number().int().positive('La cantidad debe ser mayor a 0'),
  tokenInvitado: z.string().trim().min(5).max(100).optional(),
});

export const ActualizarCantidadItemSchema = z.object({
  cantidad: z.number().int().positive('La cantidad debe ser mayor a 0'),
  tokenInvitado: z.string().trim().min(5).max(100).optional(),
});

export const AplicarCuponCarritoSchema = z.object({
  codigoCupon: z.string().trim().min(2, 'Ingrese un código de cupón válido').max(50),
  tokenInvitado: z.string().trim().min(5).max(100).optional(),
});

export const CrearCuponSchema = z.object({
  codigo: z.string().trim().min(3).max(50),
  descripcion: z.string().trim().min(5).max(300),
  idTipoDescuentoCupon: z.union([z.literal(1), z.literal(2)]), // 1 = PORCENTAJE, 2 = MONTO_FIJO
  valorDescuento: z.number().positive(),
  idAmbitoCupon: z.union([z.literal(1), z.literal(2)]), // 1 = CARRITO_COMPLETO, 2 = CATEGORIA
  idCategoria: z.number().int().positive().optional(),
  montoMinimoCompra: z.number().nonnegative().default(0),
  montoMaximoDescuento: z.number().positive().optional(),
  limiteTotalUsos: z.number().int().positive(),
  limiteUsosPorCliente: z.number().int().positive().default(1),
  fechaInicioVigencia: z.string().datetime(),
  fechaFinVigencia: z.string().datetime(),
});

export type AgregarItemCarritoInput = z.infer<typeof AgregarItemCarritoSchema>;
export type ActualizarCantidadItemInput = z.infer<typeof ActualizarCantidadItemSchema>;
export type AplicarCuponCarritoInput = z.infer<typeof AplicarCuponCarritoSchema>;
export type CrearCuponInput = z.infer<typeof CrearCuponSchema>;