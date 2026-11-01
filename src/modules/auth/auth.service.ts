import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { env } from '../../config/env.js';
import { AppError } from '../../shared/errors/AppError.js';
import { AuthRepository } from './auth.repository.js';
import { LoginInput, RegistroInput } from './auth.schema.js';

export class AuthService {
  private repo = new AuthRepository();

  private hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  private generarTokens(idUsuario: number, correo: string, rol: 'CLIENTE' | 'OPERADOR' | 'ADMINISTRADOR') {
    const accessToken = jwt.sign(
      { idUsuario, correo, rol },
      env.JWT_ACCESS_SECRET,
      { expiresIn: env.JWT_ACCESS_EXPIRES_IN as any }
    );
    const rawRefreshToken = crypto.randomBytes(40).toString('hex');
    const expiracionRefresh = new Date();
    expiracionRefresh.setDate(expiracionRefresh.getDate() + env.JWT_REFRESH_EXPIRES_DAYS);

    return { accessToken, rawRefreshToken, expiracionRefresh };
  }

  async registrar(input: RegistroInput) {
    const hash = await bcrypt.hash(input.password, env.BCRYPT_SALT_ROUNDS);
    return await this.repo.registrarCliente(input.nombres, input.apellidos, input.correoElectronico, hash, input.telefono);
  }

async login(input: LoginInput, ip?: string, userAgent?: string) {
  const usuario = await this.repo.obtenerUsuarioPorCorreo(input.correoElectronico);

  if (!usuario) {
    throw new AppError('Credenciales incorrectas.', 401, 'CREDENCIALES_INVALIDAS', 'AUTENTICACION', 1);
  }

  if (!usuario.Activo) {
    throw new AppError('El usuario se encuentra desactivado.', 403, 'USUARIO_INACTIVO', 'AUTENTICACION', 1);
  }

  // 1. Si ya está bloqueado, se rechaza inmediatamente sin comparar contraseñas
  if (usuario.EstaBloqueado === 1) {
    throw new AppError(
      `Cuenta bloqueada temporalmente por múltiples intentos fallidos. Intente de nuevo en ${usuario.MinutosRestantesBloqueo} minutos.`,
      403,
      'CUENTA_BLOQUEADA',
      'AUTENTICACION',
      1
    );
  }

  const passwordValida = await bcrypt.compare(input.password, usuario.PasswordHash);

  // 2. Si la contraseña es incorrecta, se registra el fallo
  if (!passwordValida) {
    const resultado = await this.repo.registrarResultadoLogin(usuario.IDUsuario, false);

    // Si este intento provocó el bloqueo (intento 5):
    if (resultado.FueBloqueado === 1) {
      throw new AppError(
        'Ha superado el límite de intentos permitidos. Su cuenta ha sido bloqueada temporalmente por 15 minutos.',
        403,
        'CUENTA_BLOQUEADA',
        'AUTENTICACION',
        1
      );
    }

    throw new AppError(`Credenciales incorrectas. quedan ${5-resultado.IntentosActuales} intentos.` , 401, 'CREDENCIALES_INVALIDAS', 'AUTENTICACION', 1);
  }

  // 3. Login exitoso: se limpian los intentos fallidos
  await this.repo.registrarResultadoLogin(usuario.IDUsuario, true);

  const { accessToken, rawRefreshToken, expiracionRefresh } = this.generarTokens(
    usuario.IDUsuario,
    usuario.CorreoElectronico,
    usuario.CodigoRol
  );

  const familiaToken = crypto.randomUUID();
  const tokenHash = this.hashToken(rawRefreshToken);
  await this.repo.guardarRefreshToken(usuario.IDUsuario, tokenHash, familiaToken, expiracionRefresh, ip, userAgent);

  return {
    usuario: {
      idUsuario: usuario.IDUsuario,
      nombreCompleto: usuario.NombreCompleto,
      correoElectronico: usuario.CorreoElectronico,
      rol: usuario.CodigoRol,
    },
    accessToken,
    rawRefreshToken,
  };
}

  async refrescar(refreshTokenPlano: string, ip?: string, userAgent?: string) {
    if (!refreshTokenPlano) {
      throw new AppError('Refresh token no proporcionado.', 401, 'TOKEN_REQUERIDO', 'AUTENTICACION', 1);
    }

    const tokenHashActual = this.hashToken(refreshTokenPlano);
    const nuevoRefreshToken = crypto.randomBytes(40).toString('hex');
    const nuevoTokenHash = this.hashToken(nuevoRefreshToken);

    const nuevaExp = new Date();
    nuevaExp.setDate(nuevaExp.getDate() + env.JWT_REFRESH_EXPIRES_DAYS);

    const usuario = await this.repo.rotarRefreshToken(tokenHashActual, nuevoTokenHash, nuevaExp, ip, userAgent);

    const accessToken = jwt.sign(
      { idUsuario: usuario.IDUsuario, correo: usuario.CorreoElectronico, rol: usuario.CodigoRol },
      env.JWT_ACCESS_SECRET,
      { expiresIn: env.JWT_ACCESS_EXPIRES_IN as any }
    );

    return {
      accessToken,
      rawRefreshToken: nuevoRefreshToken,
      usuario,
    };
  }

  async logout(refreshTokenPlano?: string) {
    if (refreshTokenPlano) {
      await this.repo.revocarRefreshToken(this.hashToken(refreshTokenPlano));
    }
  }
}