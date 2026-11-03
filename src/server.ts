import express, { Request, Response, NextFunction } from "express";
import cors from "cors";
import helmet from "helmet";
import cookieParser from "cookie-parser";
import { env } from "./config/env.js";
import { getDbPool } from "./config/database.js";
import { errorHandler } from "./middlewares/error.middleware.js";
import { AppError } from "./shared/errors/AppError.js";
import authRoutes from "./modules/auth/auth.routes.js";
import catalogoRoutes from './modules/catalogo/catalogo.routes.js';
import inventarioRoutes from './modules/inventario/inventario.routes.js';
import carritoRoutes from './modules/carrito/carrito.routes.js';
import checkoutRoutes from './modules/checkout/checkout.routes.js';
import dashboardRoutes from './modules/dashboard/dashboard.routes.js';
import { iniciarWorkerReservas } from './workers/reservas.worker.js';
const app = express();

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
app.use('/api/inventario', inventarioRoutes);
app.use('/api/carrito', carritoRoutes);
app.use('/api/checkout', checkoutRoutes);
app.use('/api/dashboard', dashboardRoutes);

//  Ruta no encontrada (404)
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

//  Middleware centralizado de errores (guarda en dbo.BitacoraError)
app.use(errorHandler);

const iniciarServidor = async (): Promise<void> => {
  try {
    await getDbPool();
    iniciarWorkerReservas();
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
