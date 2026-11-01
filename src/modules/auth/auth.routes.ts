import { Router } from 'express';
import { AuthController } from './auth.controller.js';
import { autenticar, autorizarRoles } from '../../middlewares/auth.middleware.js';

const router = Router();
const controller = new AuthController();

router.post('/registro', controller.registrar);
router.post('/login', controller.login);
router.post('/refresh', controller.refrescar);
router.post('/logout', controller.logout);

// Rutas protegidas de prueba
router.get('/perfil', autenticar, controller.perfil);
router.get('/solo-operador', autenticar, autorizarRoles('OPERADOR', 'ADMINISTRADOR'), controller.perfil);
router.get('/solo-admin', autenticar, autorizarRoles('ADMINISTRADOR'), controller.perfil);

export default router;