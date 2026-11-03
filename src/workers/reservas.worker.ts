import {NextFunction } from "express";
import { CheckoutRepository } from '../modules/checkout/checkout.repository.js';

export const iniciarWorkerReservas = () => {
  const checkoutRepo = new CheckoutRepository();
  const INTERVALO_MS = 30000; // Se ejecuta cada 30 segundos

  setInterval(async (next: NextFunction) => {
    try {
      const liberadas = await checkoutRepo.liberarReservasVencidas();

    } catch (error) {
     next(error);
    }
  }, INTERVALO_MS);
};