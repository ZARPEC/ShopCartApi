import { Router } from 'express';
import { DashboardController } from './dashboard.controller.js';
import { autenticar, autorizarRoles } from '../../middlewares/auth.middleware.js';

const router = Router();
const controller = new DashboardController();

router.get('/metricas', autenticar, autorizarRoles('ADMINISTRADOR', 'OPERADOR'), controller.obtenerResumen);
router.get('/top-productos', autenticar, autorizarRoles('ADMINISTRADOR', 'OPERADOR'), controller.obtenerTop10);
router.get('/pedidos', autenticar, autorizarRoles('ADMINISTRADOR', 'OPERADOR'), controller.listarPedidos);

router.get('/bitacora', autenticar, autorizarRoles('ADMINISTRADOR'), controller.consultarBitacora);

export default router;