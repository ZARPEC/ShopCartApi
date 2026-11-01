import { z } from 'zod';

export const RegistroSchema = z.object({
  nombres: z.string().trim().min(2, 'Los nombres deben tener al menos 2 caracteres').max(100),
  apellidos: z.string().trim().min(2, 'Los apellidos deben tener al menos 2 caracteres').max(100),
  correoElectronico: z.string().trim().email('Formato de correo electrónico inválido').max(255),
  password: z
    .string()
    .min(8, 'La contraseña debe tener al menos 8 caracteres')
    .regex(/[A-Z]/, 'Debe contener al menos una letra mayúscula')
    .regex(/[a-z]/, 'Debe contener al menos una letra minúscula')
    .regex(/[0-9]/, 'Debe contener al menos un número'),
  telefono: z.string().trim().max(30).optional(),
});

export const LoginSchema = z.object({
  correoElectronico: z.string().trim().email('Correo inválido'),
  password: z.string().min(1, 'La contraseña es requerida'),
});

export type RegistroInput = z.infer<typeof RegistroSchema>;
export type LoginInput = z.infer<typeof LoginSchema>;