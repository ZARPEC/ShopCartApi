import { Router } from 'express';
import { InventarioController } from './inventario.controller.js';
import { autenticar, autorizarRoles } from '../../middlewares/auth.middleware.js';

const router = Router();
const controller = new InventarioController();

router.post(
  '/movimientos',
  autenticar,
  autorizarRoles('OPERADOR', 'ADMINISTRADOR'),
  controller.registrarMovimiento
);

router.get(
  '/kardex/:idVariante',
  autenticar,
  autorizarRoles('OPERADOR', 'ADMINISTRADOR'),
  controller.obtenerKardexPorVariante
);

export default router;