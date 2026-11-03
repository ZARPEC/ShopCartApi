import { Router } from 'express';
import { CheckoutController } from './checkout.controller.js';
import { autenticar, autorizarRoles } from '../../middlewares/auth.middleware.js';

const router = Router();
const controller = new CheckoutController();

router.post('/direcciones', autenticar, autorizarRoles('CLIENTE'), controller.crearDireccion);
router.get('/direcciones', autenticar, autorizarRoles('CLIENTE'), controller.listarDirecciones);

router.post('/reservar', autenticar, autorizarRoles('CLIENTE'), controller.iniciarReserva);
router.post('/pagar', autenticar, autorizarRoles('CLIENTE'), controller.confirmarPago);

router.post('/pedidos/:idPedido/cancelar', autenticar, autorizarRoles('CLIENTE', 'OPERADOR', 'ADMINISTRADOR'), controller.cancelarPedido);
router.patch('/pedidos/:idPedido/estado', autenticar, autorizarRoles('OPERADOR', 'ADMINISTRADOR'), controller.avanzarEstado);
router.post('/pedidos/:idPedido/devolucion', autenticar, autorizarRoles('OPERADOR', 'ADMINISTRADOR'), controller.registrarDevolucion);

export default router;