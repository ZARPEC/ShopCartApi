import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { AppError } from '../shared/errors/AppError.js';
import { UsuarioTokenPayload } from './auth.middleware.js';

export const autenticarClienteOInvitado = (req: Request, _res: Response, next: NextFunction): void => {
  const authHeader = req.headers.authorization;

  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1];
    try {
      const payload = jwt.verify(token, env.JWT_ACCESS_SECRET) as UsuarioTokenPayload;

      // RF-01: Solo el rol CLIENTE puede usar el carrito; Operador y Administrador devuelven 403
      if (payload.rol !== 'CLIENTE') {
        return next(
          new AppError(
            'Las cuentas de Operador y Administrador son de gestión interna. Para comprar en la tienda utiliza una cuenta de Cliente.',
            403,
            'ROL_NO_PERMITIDO_PARA_COMPRAS',
            'CARRITO',
            1
          )
        );
      }

      req.usuario = payload;
    } catch (error) {
      if (error instanceof jwt.TokenExpiredError) {
        return next(new AppError('El token de acceso ha expirado.', 401, 'TOKEN_EXPIRADO', 'AUTENTICACION', 1));
      }
      return next(new AppError('Token de acceso inválido.', 401, 'TOKEN_INVALIDO', 'AUTENTICACION', 1));
    }
  }

  next();
};