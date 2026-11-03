// src/workers/reservas.worker.ts
import { CheckoutRepository } from '../modules/checkout/checkout.repository.js';
import { getDbPool } from '../config/database.js';
import { registrarErrorEnBD } from '../middlewares/error.middleware.js';

export const iniciarWorkerReservas = () => {
  const checkoutRepo = new CheckoutRepository();
  const INTERVALO_MS = 30000;

  setInterval(async () => {
    try {
      await checkoutRepo.liberarReservasVencidas();
      const pool = await getDbPool();
      await pool.request().execute('dbo.SP_Carrito_MarcarCarritosAbandonados');
    } catch (error) {
      console.error('Error en worker:', error);
      await registrarErrorEnBD(error, 'TAREA_PROGRAMADA', 'reservas.worker.ts');
    }
  }, INTERVALO_MS);
};