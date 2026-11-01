import { z } from 'zod';

export const ListarProductosQuerySchema = z.object({
  buscar: z.string().trim().optional(),
  categoria: z.string().trim().optional(),
  precioMin: z.coerce.number().positive().optional(),
  precioMax: z.coerce.number().positive().optional(),
  soloDisponibles: z    
    .string()
    .optional()
    .transform((val) => val === 'true'),
  orden: z.enum(['precio_asc', 'precio_desc', 'nombre', 'recientes']).default('recientes'),
  pagina: z.coerce.number().int().positive().default(1),
  limite: z.coerce.number().int().positive().max(100).default(12),
});

export const CrearCategoriaSchema = z.object({
  nombre: z.string().trim().min(3).max(100),
  slug: z.string().trim().min(3).max(120).regex(/^[a-z0-9-]+$/, 'El slug debe contener solo minúsculas y guiones'),
  descripcion: z.string().trim().max(400).optional(),
  idCategoriaPadre: z.number().int().positive().optional(),
});

export const CrearProductoSchema = z.object({
  idCategoria: z.number().int().positive(),
  nombre: z.string().trim().min(3).max(200),
  slug: z.string().trim().min(3).max(220).regex(/^[a-z0-9-]+$/, 'El slug debe contener solo minúsculas y guiones'),
  descripcion: z.string().trim().max(2000).optional(),
  marca: z.string().trim().max(100).optional(),
  porcentajeIVA: z.number().min(0).max(100).default(12.0),
});

export const CrearVarianteSchema = z.object({
  sku: z.string().trim().max(60).optional(), 
  nombreVariante: z.string().trim().min(2).max(150),
  precioActual: z.number().positive('El precio debe ser mayor a 0'),
  existenciaInicial: z.number().int().nonnegative().default(0),
  stockMinimoAlerta: z.number().int().nonnegative().default(5),
});

export type ListarProductosQuery = z.infer<typeof ListarProductosQuerySchema>;
export type CrearCategoriaInput = z.infer<typeof CrearCategoriaSchema>;
export type CrearProductoInput = z.infer<typeof CrearProductoSchema>;
export type CrearVarianteInput = z.infer<typeof CrearVarianteSchema>;