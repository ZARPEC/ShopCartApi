import sql, { ConnectionPool, config as SqlConfig } from 'mssql';
import { env } from './env.js';

const dbConfig: SqlConfig = {
  user: env.DB_USER,
  password: env.DB_PASSWORD,
  server: env.DB_HOST,
  port: env.DB_PORT,
  database: env.DB_NAME,
  pool: {
    max: env.DB_POOL_MAX,
    min: env.DB_POOL_MIN,
    idleTimeoutMillis: 30000,
  },
  options: {
    encrypt: env.DB_ENCRYPT,
    trustServerCertificate: env.DB_TRUST_SERVER_CERTIFICATE,
    enableArithAbort: true,
  },
};

let poolPromise: Promise<ConnectionPool> | null = null;

export const getDbPool = async (): Promise<ConnectionPool> => {
  if (!poolPromise) {
    const pool = new sql.ConnectionPool(dbConfig);
    poolPromise = pool
      .connect()
      .then((connectedPool) => {
        console.log(`Conectado exitosamente a SQL Server: ${env.DB_NAME}`);
        return connectedPool;
      })
      .catch((error: unknown) => {
        poolPromise = null;
        console.error('Error al conectar con SQL Server:', error);
        throw error;
      });
  }
  return poolPromise;
};

export { sql };