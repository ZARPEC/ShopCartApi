# ShopCart - Plataforma Web de Ventas (Fase 1: Base de Datos y Backend)

---

## Decisiones Técnicas y de Arquitectura (Sección 06 del Enunciado)

### Cero ORM y Stored Procedures Tipados
Para cumplir con los estándares, todo el acceso a datos se delegó a Stored Procedures (`SP_Modulo_Proceso`), Vistas (`VW_Modulo_Proceso`) y Funciones Tipo Tabla (`FU_Modulo_Proceso`). Los procedimientos utilizan parámetros tipados (`sql.Int`, `sql.VarChar`, etc.), erradicando la concatenación de cadenas y el riesgo de inyección SQL.

### Separación entre `.env` y la tabla `ConfiguracionSistema`
* **Archivo `.env` (Infraestructura y Secretos):** Almacena credenciales que la aplicación necesita antes de conectarse a la base de datos (cadena de conexión a SQL Server, puertos y secretos criptográficos de firma JWT).
* **Tabla `dbo.ConfiguracionSistema` (Parámetros Operativos en Caliente):** Parámetros de negocio que deben poder ajustarse desde el motor de base de datos sin recompilar ni reiniciar el servidor:
  * `CHECKOUT_TIEMPO_RESERVA_MIN = 15` (Minutos de reserva temporal en checkout).
  * `CARRITO_ABANDONADO_MINUTOS = 60` (Umbral de inactividad para reportar carritos abandonados).
  * `IMPUESTO_IVA_PORCENTAJE = 12.00` (IVA incluido en precios en Quetzales).
  * `ENVIO_COSTO_ESTANDAR_GTQ = 25.00` y `ENVIO_GRATIS_MONTO_MINIMO_GTQ = 500.00`.
  * `AUTH_MAX_INTENTOS_FALLIDOS = 5` y `AUTH_TIEMPO_BLOQUEO_MINUTOS = 15`.

### Control de Concurrencia y Prevención de Sobreventa
Para cumplir con el criterio de **RF-06** (*"Si dos clientes compran la última unidad al mismo tiempo, solo uno lo logra; nunca hay sobreventa"*):
* La reserva del inventario ocurre exclusivamente al iniciar el checkout, nunca al agregar al carrito, previniendo el secuestro de existencias por carritos inactivos.
* Las consultas de verificación emplean bloqueo a nivel de fila (`UPDLOCK, ROWLOCK`) dentro de transacciones aisladas, impidiendo condiciones de carrera.
* La columna calculada persistida `ExistenciaDisponible AS (ExistenciaFisica - ExistenciaReservada) PERSISTED` y la restricción `CK_VarianteProducto_SinSobreventa (ExistenciaFisica >= ExistenciaReservada)` garantizan físicamente en el motor que no exista sobreventa.

###  Idempotencia en Pagos (RF-06)
Cada confirmación de pago exige una `claveIdempotencia` única en el encabezado o cuerpo:
* Si el cliente presiona dos veces el botón de pagar por impaciencia o falla la conexión de red, SQL Server detecta la clave existente en `dbo.Pedido` y retorna el pedido original sin duplicar cobros, líneas ni salidas de inventario (`"EsRespuestaIdempotente": 1`).
* Al confirmarse la compra, el carrito asociado pasa a estado `CONVERTIDO` (3), impidiendo que se generen pedidos adicionales sobre la misma bolsa.

### Inmutabilidad de Kardex y Bitácora de Auditoría
Cumpliendo con RF-03 y RF-09, las tablas `dbo.MovimientoKardex` y `dbo.BitacoraAuditoria` cuentan con triggers `INSTEAD OF UPDATE, DELETE` que arrojan excepciones personalizadas (errores 50009 y 50010) ante cualquier intento de alteración o borrado físico. Las correcciones de inventario exigen registrar un nuevo movimiento de ajuste con motivo documentado.

### Rotación de Refresh Tokens y Detección de Reuso (RFC 6819)
Cada sesión genera una `FamiliaToken` (UUID). Al solicitar un nuevo `accessToken` en `/api/auth/refresh`, el token actual se revoca y se emite un nuevo reemplazo. Si un atacante intenta reutilizar un token revocado, el sistema detecta la brecha e invalida automáticamente toda la familia de tokens activa, forzando un nuevo inicio de sesión.
