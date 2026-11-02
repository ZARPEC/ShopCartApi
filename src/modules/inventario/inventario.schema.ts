import { z } from 'zod';

export const RegistrarMovimientoSchema = z.object({
  idVarianteProducto: z.number().int().positive('El ID de la variante es requerido'),
  tipoMovimiento: z.enum(['ENTRADA_COMPRA', 'AJUSTE_POSITIVO', 'AJUSTE_NEGATIVO']),
  cantidad: z.number().int().positive('La cantidad debe ser un entero mayor a 0'),
  motivo: z.string().trim().min(5, 'El motivo es obligatorio y debe tener al menos 5 caracteres').max(500),
  costoUnitario: z.number().nonnegative().optional(),
});

export const ConsultarKardexQuerySchema = z.object({
  pagina: z.coerce.number().int().positive().default(1),
  limite: z.coerce.number().int().positive().max(100).default(20),
});

export type RegistrarMovimientoInput = z.infer<typeof RegistrarMovimientoSchema>;
export type ConsultarKardexQuery = z.infer<typeof ConsultarKardexQuerySchema>;