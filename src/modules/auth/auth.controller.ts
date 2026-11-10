import { Request, Response, NextFunction } from 'express';
import { AuthService } from './auth.service.js';
import { LoginSchema, RegistroSchema } from './auth.schema.js';
import { AppError } from '../../shared/errors/AppError.js';
import { AuthRepository } from './auth.repository.js';
import bcrypt from 'bcryptjs';
import { env } from '../../config/env.js';

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

  crearEmpleado = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { idRol, nombres, apellidos, correoElectronico, telefono, password } = req.body;
    const passwordHash = await bcrypt.hash(password, env.BCRYPT_SALT_ROUNDS);
    const repo = new AuthRepository();
    const empleado = await repo.crearEmpleado(
      { idRol: Number(idRol), nombres, apellidos, correoElectronico, telefono, passwordHash },
      req.usuario?.idUsuario ?? 1,
      req.ip
    );
    res.status(201).json({ ok: true, empleado });
  } catch (error) {
    next(error);
  }
};

listarUsuarios = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const buscar = req.query.buscar ? String(req.query.buscar) : undefined;
    const rol = req.query.rol ? Number(req.query.rol) : undefined;
    const repo = new AuthRepository();
    const usuarios = await repo.listarUsuarios(buscar, rol);
    res.status(200).json({ ok: true, usuarios });
  } catch (error) {
    next(error);
  }
};

cambiarEstadoUsuario = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const idUsuarioTarget = Number(req.params.id);
    const { activo } = req.body;
    const repo = new AuthRepository();
    const resultado = await repo.cambiarEstadoUsuario(
      idUsuarioTarget,
      Boolean(activo),
      req.usuario?.idUsuario ?? 1,
      req.ip
    );
    res.status(200).json({ ok: true, ...resultado });
  } catch (error) {
    next(error);
  }
};
}