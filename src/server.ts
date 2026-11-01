import express, { Request, Response, NextFunction } from "express";
import cors from "cors";
import helmet from "helmet";
import cookieParser from "cookie-parser";
import { env } from "./config/env.js";
import { getDbPool, sql } from "./config/database.js";
import { errorHandler } from "./middlewares/error.middleware.js";
import { AppError } from "./shared/errors/AppError.js";
import authRoutes from "./modules/auth/auth.routes.js";
import catalogoRoutes from './modules/catalogo/catalogo.routes.js';
const app = express();

// 1. Middlewares de seguridad (Sección 06: CORS configurado y cabeceras básicas)
app.use(helmet());
app.use(
  cors({
    origin: env.CORS_ORIGIN,
    credentials: true,
  }),
);
app.use(express.json({ limit: "1mb" }));
app.use(cookieParser());

app.use("/api/auth", authRoutes);
app.use('/api/catalogo', catalogoRoutes);

// 2. Endpoint de salud que verifica la conexión a SQL Server mediante Stored Procedure
app.get(
  "/api/health",
  async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const pool = await getDbPool();
      const resultado = await pool
        .request()
        .input("CodigoModulo", sql.VarChar(40), null)
        .execute("dbo.SP_Sistema_ObtenerConfiguraciones");

      res.status(200).json({
        ok: true,
        mensaje:
          "API ShopCart conectada a SQL Server mediante Stored Procedures",
        totalConfiguracionesActivas: resultado.recordset.length,
        configuraciones: resultado.recordset,
      });
    } catch (error) {
      next(error);
    }
  },
);

// 3. Ruta no encontrada (404)
app.use((req: Request, _res: Response, next: NextFunction) => {
  next(
    new AppError(
      `La ruta ${req.method} ${req.originalUrl} no existe.`,
      404,
      "RUTA_NO_ENCONTRADA",
      "SISTEMA",
      1,
    ),
  );
});

// 4. Middleware centralizado de errores (guarda en dbo.BitacoraError)
app.use(errorHandler);

const iniciarServidor = async (): Promise<void> => {
  try {
    await getDbPool();
    app.listen(env.PORT, "0.0.0.0", () => {
      console.log(
        `Servidor ShopCart ejecutándose en http://localhost:${env.PORT}`,
      );
    });
  } catch (error) {
    console.error("Fallo crítico al iniciar el servidor:", error);
    process.exit(1);
  }
};

iniciarServidor();
