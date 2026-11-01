import { Router } from 'express';
import { CatalogoController } from './catalogo.controller.js';
import { autenticar, autorizarRoles } from '../../middlewares/auth.middleware.js';

const router = Router();
const controller = new CatalogoController();

// Rutas Públicas (Cualquier visitante las puede ver sin iniciar sesión)
router.get('/categorias', controller.listarCategorias);
router.get('/productos', controller.listarProductos);
router.get('/productos/:slug', controller.obtenerProductoPorSlug);

// Rutas de Administración (Protegidas por JWT y Rol)
router.post('/categorias', autenticar, autorizarRoles('ADMINISTRADOR'), controller.crearCategoria);
router.post('/productos', autenticar, autorizarRoles('ADMINISTRADOR'), controller.crearProducto);
router.post('/productos/:id/variantes', autenticar, autorizarRoles('ADMINISTRADOR', 'OPERADOR'), controller.crearVariante);
router.patch('/productos/:id/desactivar', autenticar, autorizarRoles('ADMINISTRADOR'), controller.desactivarProducto);

export default router;