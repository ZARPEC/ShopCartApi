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
router.put('/productos/:id', autenticar, autorizarRoles('ADMINISTRADOR'), controller.actualizarProducto);
router.put('/variantes/:idVariante', autenticar, autorizarRoles('ADMINISTRADOR'), controller.actualizarVariante);
router.post('/productos/:id/imagenes', autenticar, autorizarRoles('ADMINISTRADOR'), controller.agregarImagen);
router.delete('/imagenes/:idImagen', autenticar, autorizarRoles('ADMINISTRADOR'), controller.eliminarImagen);
router.patch('/productos/:id/reactivar', autenticar, autorizarRoles('ADMINISTRADOR'), controller.reactivarProducto);
export default router;