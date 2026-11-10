import { Router } from 'express';
import { CheckoutController } from './checkout.controller.js';
import { autenticar, autorizarRoles } from '../../middlewares/auth.middleware.js';

const router = Router();
const controller = new CheckoutController();

router.post('/direcciones', autenticar, autorizarRoles('CLIENTE'), controller.crearDireccion);
router.get('/direcciones', autenticar, autorizarRoles('CLIENTE'), controller.listarDirecciones);

router.delete('/direcciones/:id', autenticar, controller.eliminarDireccion);
router.patch('/direcciones/:id/predeterminada', autenticar, controller.predeterminadaDireccion);

router.post('/reservar', autenticar, autorizarRoles('CLIENTE'), controller.iniciarReserva);
router.post('/pagar', autenticar, autorizarRoles('CLIENTE'), controller.confirmarPago);
router.post('/liberar-reserva', autenticar, controller.liberarReserva);

router.get('/mis-pedidos', autenticar, controller.misPedidos);
router.get('/mis-pedidos/:id', autenticar, controller.detalleMiPedido);
router.post('/pedidos/:id/devolucion', autenticar, autorizarRoles('CLIENTE'), controller.solicitarDevolucion);

router.post('/pedidos/:idPedido/cancelar', autenticar, autorizarRoles('CLIENTE', 'OPERADOR', 'ADMINISTRADOR'), controller.cancelarPedido);
router.patch('/pedidos/:idPedido/estado', autenticar, autorizarRoles('OPERADOR', 'ADMINISTRADOR'), controller.avanzarEstado);

export default router;