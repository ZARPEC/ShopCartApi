import { Request, Response, NextFunction } from 'express';
import { AuthService } from './auth.service.js';
import { LoginSchema, RegistroSchema } from './auth.schema.js';
import { AppError } from '../../shared/errors/AppError.js';

export class AuthController {
  private service = new AuthService();

  private setRefreshCookie(res: Response, token: string) {
    res.cookie('refreshToken', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      maxAge: 7 * 24 * 60 * 60 * 1000, // 7 días
    });
  }

  registrar = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = RegistroSchema.parse(req.body);
      const cliente = await this.service.registrar(data);
      res.status(201).json({ ok: true, mensaje: 'Cliente registrado con éxito.', usuario: cliente });
    } catch (error) {
      next(error)
    }
  };

  login = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = LoginSchema.parse(req.body);
      const { usuario, accessToken, rawRefreshToken } = await this.service.login(data, req.ip, req.headers['user-agent']);
      this.setRefreshCookie(res, rawRefreshToken);
      res.status(200).json({ ok: true, usuario, accessToken });
    } catch (error) {
      next(error);
    }
  };

  refrescar = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const token = req.cookies?.refreshToken;
      const { usuario, accessToken, rawRefreshToken } = await this.service.refrescar(token, req.ip, req.headers['user-agent']);
      this.setRefreshCookie(res, rawRefreshToken);
      res.status(200).json({ ok: true, usuario, accessToken });
    } catch (error) {
      next(
        new AppError(
      `Ocurrio un error al procesar la solicitud en ${req.method} ${req.originalUrl}.`,
      500,
      'ERROR_INTERNO',
      'SISTEMA',
      1
    )
      );
    }
  };

  logout = async (req: Request, res: Response, next: NextFunction) => {
    try {
      await this.service.logout(req.cookies?.refreshToken);
      res.clearCookie('refreshToken');
      res.status(200).json({ ok: true, mensaje: 'Sesión cerrada correctamente.' });
    } catch (error) {
      next(
        new AppError(
      `Ocurrio un error al procesar la solicitud en ${req.method} ${req.originalUrl}.`,
      500,
      'ERROR_INTERNO',
      'SISTEMA',
      1
    )
      );
    }
  };

  perfil = async (req: Request, res: Response) => {
    res.status(200).json({ ok: true, usuario: req.usuario });
  };
}