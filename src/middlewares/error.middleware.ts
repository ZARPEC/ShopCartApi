import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { getDbPool, sql } from '../config/database.js';
import { env } from '../config/env.js';
import { AppError } from '../shared/errors/AppError.js';

const sanitizarPayload = (body: unknown): string | null => {
  if (!body || typeof body !== 'object') return null;
  try {
    const copia = { ...(body as Record<string, unknown>) };
    const camposSensibles = ['password', 'contrasena', 'passwordHash', 'refreshToken', 'token'];
    for (const campo of camposSensibles) {
      if (campo in copia) {
        copia[campo] = '[censurado]';
      }
    }
    return JSON.stringify(copia);
  } catch {
    return null;
  }
};

export const errorHandler = async (
  err: unknown,
  req: Request,
  res: Response,
  _next: NextFunction
): Promise<void> => {
  let statusCode = 500;
  let codigoError = 'INTERNAL_SERVER_ERROR';
  let mensaje = 'Ocurrió un error interno al procesar la solicitud.';
  let modulo = 'SISTEMA';
  let severidad: 1 | 2 | 3 = 2;
  let detallesValidacion: unknown = undefined;

  if (err instanceof AppError) {
    statusCode = err.statusCode;
    codigoError = err.codigoError;
    mensaje = err.message;
    modulo = err.modulo;
    severidad = err.severidad;
  } else if (err instanceof ZodError) {
    statusCode = 400;
    codigoError = 'ESQUEMA_INVALIDO';
    mensaje = 'Los datos enviados no cumplen con el esquema requerido.';
    severidad = 1;
    detallesValidacion = err.issues.map((issue) => ({
      campo: issue.path.join('.'),
      mensaje: issue.message,
    }));
  } else if (err instanceof Error) {
    mensaje = err.message;
    // Si el error viene de un THROW de negocio dentro de un Stored Procedure de SQL Server (>= 50000)
    const sqlErr = err as Error & { number?: number; state?: number; procName?: string; lineNumber?: number };
    if (typeof sqlErr.number === 'number' && sqlErr.number >= 50000) {
      statusCode = 409;
      codigoError = `SQL_REGLA_NEGOCIO_${sqlErr.number}`;
      severidad = 1;
    }
  }

  // Registrar en dbo.BitacoraError mediante Stored Procedure con parámetros tipados
  try {
    const pool = await getDbPool();
    const errorObj = err instanceof Error ? (err as Error & { number?: number; state?: number; procName?: string; lineNumber?: number }) : null;

    await pool
      .request()
      .input('CodigoModulo', sql.VarChar(40), modulo)
      .input('IDSeveridadError', sql.TinyInt, severidad)
      .input('IDUsuario', sql.Int, null)
      .input('CodigoCorrelacion', sql.UniqueIdentifier, null)
      .input('OrigenError', sql.VarChar(30), errorObj?.procName ? 'SQL_SP' : 'BACKEND_MIDDLEWARE')
      .input('ObjetoOMetodo', sql.VarChar(200), errorObj?.procName || `${req.method} ${req.originalUrl}`)
      .input('NumeroLinea', sql.Int, errorObj?.lineNumber ?? null)
      .input('NumeroErrorSQL', sql.Int, errorObj?.number ?? null)
      .input('EstadoErrorSQL', sql.TinyInt, errorObj?.state ?? null)
      .input('CodigoErrorAplicacion', sql.VarChar(60), codigoError)
      .input('MensajeError', sql.NVarChar(2000), errorObj?.message || mensaje)
      .input('DetalleStackTrace', sql.NVarChar(sql.MAX), errorObj?.stack ?? null)
      .input('ParametrosContextoJson', sql.NVarChar(sql.MAX), sanitizarPayload(req.body))
      .input('MetodoHttp', sql.VarChar(10), req.method)
      .input('RutaEndpoint', sql.VarChar(300), req.originalUrl)
      .input('CodigoEstadoHttp', sql.SmallInt, statusCode)
      .input('DireccionIP', sql.VarChar(45), req.ip ?? null)
      .execute('dbo.SP_Sistema_RegistrarError');
  } catch (dbLogError) {
    console.error('No se pudo escribir en dbo.BitacoraError:', dbLogError);
  }

  res.status(statusCode).json({
    ok: false,
    codigo: codigoError,
    mensaje: statusCode === 500 && env.NODE_ENV === 'production'
      ? 'Ocurrió un error interno en el servidor.'
      : mensaje,
    ...(detallesValidacion ? { errores: detallesValidacion } : {}),
  });
};