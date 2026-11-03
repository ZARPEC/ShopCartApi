import { z } from 'zod';

export const ListarPedidosFiltrosSchema = z.object({
  idEstadoPedido: z.coerce.number().int().positive().optional(),
  idCliente: z.coerce.number().int().positive().optional(),
  fechaInicio: z.string().datetime().optional(),
  fechaFin: z.string().datetime().optional(),
  pagina: z.coerce.number().int().positive().default(1),
  limite: z.coerce.number().int().positive().max(100).default(10),
});

export const Top10FiltrosSchema = z.object({
  fechaInicio: z.string().datetime().optional(),
  fechaFin: z.string().datetime().optional(),
});

export const ConsultarBitacoraSchema = z.object({
  modulo: z.string().trim().optional(),
  entidad: z.string().trim().optional(),
  fechaInicio: z.string().datetime().optional(),
  fechaFin: z.string().datetime().optional(),
  pagina: z.coerce.number().int().positive().default(1),
  limite: z.coerce.number().int().positive().max(100).default(20),
});

export type ListarPedidosFiltros = z.infer<typeof ListarPedidosFiltrosSchema>;
export type Top10Filtros = z.infer<typeof Top10FiltrosSchema>;
export type ConsultarBitacoraInput = z.infer<typeof ConsultarBitacoraSchema>;
