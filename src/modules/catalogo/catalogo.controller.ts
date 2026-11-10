import { Request, Response, NextFunction } from "express";
import { CatalogoService } from "./catalogo.service.js";
import {
  CrearCategoriaSchema,
  CrearProductoSchema,
  CrearVarianteSchema,
  ListarProductosQuerySchema,
} from "./catalogo.schema.js";
import { CatalogoRepository } from "./catalogo.repository.js";

export class CatalogoController {
  private service = new CatalogoService();

  listarCategorias = async (
    _req: Request,
    res: Response,
    next: NextFunction,
  ) => {
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
      res.status(201).json({
        ok: true,
        mensaje: "Categoría creada exitosamente.",
        categoria,
      });
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

  obtenerProductoPorSlug = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
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
      res
        .status(201)
        .json({ ok: true, mensaje: "Producto creado exitosamente.", producto });
    } catch (error) {
      next(error);
    }
  };

  crearVariante = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idProducto = Number(req.params.id);
      const data = CrearVarianteSchema.parse(req.body);
      const idUsuario = req.usuario?.idUsuario ?? 1;
      const variante = await this.service.crearVariante(
        idProducto,
        data,
        idUsuario,
      );
      res
        .status(201)
        .json({ ok: true, mensaje: "Variante creada exitosamente.", variante });
    } catch (error) {
      next(error);
    }
  };

  desactivarProducto = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const idProducto = Number(req.params.id);
      const resultado = await this.service.desactivarProducto(idProducto);
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  actualizarProducto = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const idProducto = Number(String(req.params.id));
      const repo = new CatalogoRepository();
      const prod = await repo.actualizarProducto(
        idProducto,
        req.body,
        req.usuario?.idUsuario ?? 1,
        req.ip,
      );
      res.status(200).json({ ok: true, producto: prod });
    } catch (error) {
      next(error);
    }
  };

  actualizarVariante = async (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const idVariante = Number(String(req.params.idVariante));
      const repo = new CatalogoRepository();
      const variante = await repo.actualizarVariante(
        idVariante,
        req.body,
        req.usuario?.idUsuario ?? 1,
        req.ip,
      );
      res.status(200).json({ ok: true, variante });
    } catch (error) {
      next(error);
    }
  };

  agregarImagen = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idProducto = Number(String(req.params.id));
      const repo = new CatalogoRepository();
      const imagen = await repo.agregarImagen(idProducto, req.body);
      res.status(201).json({ ok: true, imagen });
    } catch (error) {
      next(error);
    }
  };

  eliminarImagen = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idImagen = Number(String(req.params.idImagen));
      const repo = new CatalogoRepository();
      const resultado = await repo.eliminarImagen(
        idImagen,
        req.usuario?.idUsuario ?? 1,
        req.ip,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };

  reactivarProducto = async (
    req: Request,
    res: Response,
    next: NextFunction
  ) => {
    try {
      const idProducto = Number(String(req.params.id));
      const repo = new CatalogoRepository();
      const resultado = await repo.reactivarProducto(
        idProducto,
        req.usuario?.idUsuario ?? 1,
        req.ip,
      );
      res.status(200).json({ ok: true, ...resultado });
    } catch (error) {
      next(error);
    }
  };
}
