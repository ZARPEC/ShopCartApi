export type CodigoModuloType =
  | 'AUTENTICACION'
  | 'CATALOGO'
  | 'INVENTARIO'
  | 'CARRITO'
  | 'CUPONES'
  | 'CHECKOUT'
  | 'PEDIDOS'
  | 'DASHBOARD'
  | 'BITACORA'
  | 'SISTEMA';

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly codigoError: string;
  public readonly modulo: CodigoModuloType;
  public readonly severidad: 1 | 2 | 3;
  public readonly esOperacional: boolean;
  public readonly errorOriginal?: unknown;
  constructor(
    mensaje: string,
    statusCode = 400,
    codigoError = 'ERROR_NEGOCIO',
    modulo: CodigoModuloType = 'SISTEMA',
    severidad: 1 | 2 | 3 = 1,
    errorOriginal?: unknown
  ) {
    super(mensaje);
    this.errorOriginal = errorOriginal;
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.codigoError = codigoError;
    this.modulo = modulo;
    this.severidad = severidad;
    this.esOperacional = true;
    Error.captureStackTrace(this, this.constructor);
  }
}