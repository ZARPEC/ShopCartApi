import { Router } from 'express';
import { CarritoController } from './carrito.controller.js';
import { autenticar, autorizarRoles } from '../../middlewares/auth.middleware.js';
import { autenticarClienteOInvitado} from '../../middlewares/optionalAuth.middleware.js';

const router = Router();
const controller = new CarritoController();

// Rutas del Carrito (Soportan Cliente con JWT o Visitante con header x-guest-token)
router.get('/', autenticarClienteOInvitado, controller.obtenerCarrito);
router.post('/items', autenticarClienteOInvitado, controller.agregarItem);
router.put('/items/:idVariante', autenticarClienteOInvitado, controller.actualizarCantidadItem);
router.delete('/items/:idVariante', autenticarClienteOInvitado, controller.eliminarItem);

// Aplicación de Cupones al Carrito 
router.post('/cupon', autenticarClienteOInvitado, controller.aplicarCupon);
router.delete('/cupon', autenticarClienteOInvitado, controller.removerCupon);

// Administración de Cupones 
router.get('/cupones/admin', autenticar, autorizarRoles('ADMINISTRADOR'), controller.listarCupones);
router.post('/cupones/admin', autenticar, autorizarRoles('ADMINISTRADOR'), controller.crearCupon);

export default router;