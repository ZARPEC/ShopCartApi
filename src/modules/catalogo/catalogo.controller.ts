import { Request, Response, NextFunction } from 'express';
import { CatalogoService } from './catalogo.service.js';
import {
  CrearCategoriaSchema,
  CrearProductoSchema,
  CrearVarianteSchema,
  ListarProductosQuerySchema,
} from './catalogo.schema.js';

export class CatalogoController {
  private service = new CatalogoService();

  listarCategorias = async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const categorias = await this.service.listarCategorias();
      res.status(200).json({ ok: true, categorias });
    } catch (error) {
      next(error);
    }
  };

  crearCategoria = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = CrearCategoriaSchema.parse(req.body);
      const categoria = await this.service.crearCategoria(data);
      res.status(201).json({ ok: true, mensaje: 'Categoría creada exitosamente.', categoria });
    } catch (error) {
      next(error);
    }
  };

  listarProductos = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const filtros = ListarProductosQuerySchema.parse(req.query);
      const resultado = await this.service.listarProductos(filtros);
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  obtenerProductoPorSlug = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const slug = String(req.params.slug);
      const producto = await this.service.obtenerProductoPorSlug(slug);
      res.status(200).json({ ok: true, producto });
    } catch (error) {
      next(error);
    }
  };

  crearProducto = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = CrearProductoSchema.parse(req.body);
      const producto = await this.service.crearProducto(data);
      res.status(201).json({ ok: true, mensaje: 'Producto creado exitosamente.', producto });
    } catch (error) {
      next(error);
    }
  };

  crearVariante = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idProducto = Number(req.params.id);
      const data = CrearVarianteSchema.parse(req.body);
      const idUsuario = req.usuario?.idUsuario ?? 1;
      const variante = await this.service.crearVariante(idProducto, data, idUsuario);
      res.status(201).json({ ok: true, mensaje: 'Variante creada exitosamente.', variante });
    } catch (error) {
      next(error);
    }
  };

  desactivarProducto = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idProducto = Number(req.params.id);
      const resultado = await this.service.desactivarProducto(idProducto);
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };
}