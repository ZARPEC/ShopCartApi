import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { AppError } from '../shared/errors/AppError.js';

export interface UsuarioTokenPayload {
  idUsuario: number;
  correo: string;
  rol: 'CLIENTE' | 'OPERADOR' | 'ADMINISTRADOR';
}

declare global {
  namespace Express {
    interface Request {
      usuario?: UsuarioTokenPayload;
    }
  }
}

// 1. Verifica Access Token (Devuelve 401 si expiró o no existe)
export const autenticar = (req: Request, _res: Response, next: NextFunction): void => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(new AppError('No se proporcionó un token de autenticación.', 401, 'TOKEN_REQUERIDO', 'AUTENTICACION', 1));
  }

  const token = authHeader.split(' ')[1];

  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET) as UsuarioTokenPayload;
    req.usuario = payload;
    next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      return next(new AppError('El token de acceso ha expirado.', 401, 'TOKEN_EXPIRADO', 'AUTENTICACION', 1));
    }
    return next(new AppError('Token de acceso inválido.', 401, 'TOKEN_INVALIDO', 'AUTENTICACION', 1));
  }
};

// 2. Control de Roles (Devuelve 403 si el rol no tiene permiso)
export const autorizarRoles = (...rolesPermitidos: Array<'CLIENTE' | 'OPERADOR' | 'ADMINISTRADOR'>) => {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.usuario) {
      return next(new AppError('Usuario no autenticado.', 401, 'NO_AUTENTICADO', 'AUTENTICACION', 1));
    }

    if (!rolesPermitidos.includes(req.usuario.rol)) {
      return next(
        new AppError(
          `Acceso denegado. Se requiere uno de los siguientes roles: ${rolesPermitidos.join(', ')}.`,
          403,
          'ACCESO_PROHIBIDO',
          'AUTENTICACION',
          1
        )
      );
    }

    next();
  };
};