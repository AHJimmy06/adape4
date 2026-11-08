# APE 4 — Sistema de reservas de vuelos

Aplicación de ejemplo para la APE 4 de Aplicaciones Distribuidas. Implementa una arquitectura SOA con una aplicación Flutter, una API REST en Flask y Supabase/PostgreSQL.

## Componentes

- `backend/`: API REST, autenticación JWT y acceso del servidor a Supabase.
- `database/schema.sql`: tablas, políticas y funciones SQL para reservas/cancelaciones atómicas.
- `database/migrations/001_iva_reservas.sql`: actualización idempotente para bases existentes; preserva el total histórico y lo registra como subtotal sin IVA retroactivo.
- `render.yaml`: Blueprint para crear un servicio Flask independiente en Render.
- `database/semilla.sql`: vuelos ficticios para probar la aplicación.
- `aplicacion_flutter/`: cliente móvil Flutter organizado en `models/`, `services/` y `pages/`, siguiendo los ejemplos de la Unidad 4.
- `documentacion/arquitectura.mmd`: diagrama SOA en Mermaid.
- `odd/tasks/ape4-reservas-vuelos.md`: alcance, tareas y bitácora de desarrollo.

## Requisitos

- Python 3.11 o superior.
- Flutter SDK estable y Dart.
- Proyecto gratuito de Supabase con acceso al SQL Editor.
- No hace falta Docker para ejecutar esta versión local.

## Preparar Supabase

1. Abre el SQL Editor de tu proyecto Supabase.
2. Para una base nueva, ejecuta `database/schema.sql`. Si ya tienes la tabla `reservas`, ejecuta primero `database/migrations/001_iva_reservas.sql`.
3. Ejecuta `database/semilla.sql` para crear vuelos ficticios.
4. Copia la URL del proyecto y su clave `service_role`. **La clave de servicio solo va en Flask; nunca en Flutter, `render.yaml` ni Git.**

Cada nueva reserva conserva el precio del vuelo como `subtotal`, calcula `iva = redondear(subtotal × 0.15, 2)` y guarda `total = subtotal + iva`. La migración preserva los totales históricos sin aplicarles un impuesto retroactivo. El XML generado es un comprobante académico de reserva, no una factura fiscal.

## Ejecutar la API Flask

Desde la raíz del proyecto, en PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r backend/requirements.txt
Copy-Item backend/.env.example backend/.env
```

Edita `backend/.env` con `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` y un `JWT_SECRET` aleatorio de al menos 32 bytes. Luego, todavía desde la raíz:

```powershell
python -m backend.app
```

La API queda disponible en `http://localhost:5000`.

## Ejecutar Flutter

En otra terminal:

```powershell
cd aplicacion_flutter
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

`10.0.2.2` permite que el emulador Android llegue al equipo anfitrión. En Chrome usa `http://localhost:5000`; en un teléfono físico usa la dirección IP local de la computadora. El tráfico HTTP está habilitado solo en la variante debug para desarrollo local. Para builds release configura la URL HTTPS de la API publicada en Render.

## Funciones REST

| Método | Ruta | Acceso | Uso |
|---|---|---|---|
| POST | `/api/usuarios/registro` | Público | Registrar usuario |
| POST | `/api/auth/login` | Público | Iniciar sesión y recibir JWT |
| GET | `/api/vuelos?origen=&destino=&fecha=` | Público | Consultar/filtrar vuelos |
| POST | `/api/reservas` | JWT | Reservar asientos disponibles |
| GET | `/api/reservas` | JWT | Listar las reservas propias |
| GET | `/api/reservas/<id>` | JWT | Consultar una reserva propia |
| GET | `/api/reservas/<id>/comprobante.xml` | JWT | Obtener el comprobante XML de una reserva propia |
| DELETE | `/api/reservas/<id>` | JWT | Cancelar una reserva propia |

Las rutas privadas reciben `Authorization: Bearer <token>`. La identidad se toma del JWT; el cliente no puede reservar o consultar en nombre de otro usuario. Los errores se devuelven en JSON. Las reservas y sus comprobantes muestran subtotal, IVA (15 %) y total.

## Desplegar el backend en Render

El archivo `render.yaml` crea un servicio web Python separado para esta aplicación; no reutilices el servicio `AD-2026` ni otro servicio ajeno.

1. En Render, crea un Blueprint y vincula el repositorio `AHJimmy06/adape4` que contiene este archivo.
2. Antes del primer despliegue, aplica la migración de Supabase indicada arriba. Render no modifica la base de datos; las reservas antiguas conservan el importe original y quedan con IVA cero.
3. Cuando Render lo solicite, configura `SUPABASE_URL` y `SUPABASE_SERVICE_KEY` como variables secretas del servicio. El Blueprint genera `JWT_SECRET` y define `JWT_EXPIRES_MINUTES`.
4. Confirma que el servicio termine el despliegue y prueba `https://<servicio>.onrender.com/api/vuelos`.
5. Compila el cliente Flutter release con `--dart-define=API_BASE_URL=https://<servicio>.onrender.com`.

La configuración usa `gunicorn` con `backend.wsgi:app`, enlazado a `0.0.0.0:$PORT`; el endpoint `/api/vuelos` es el health check. No se incluyen secretos en el Blueprint ni en el repositorio. Consulta [Blueprints de Render](https://render.com/docs/blueprint-spec) y [variables y secretos](https://render.com/docs/configure-environment-variables).

## Pruebas

API:

```powershell
python -m pip install -r backend/requirements.txt
python -m pytest backend/tests -q
```

Aplicación Flutter:

```powershell
cd aplicacion_flutter
flutter analyze
flutter test
```

Las pruebas de Flask usan un repositorio falso y no requieren claves Supabase. La migración se entrega para su ejecución por el titular en el SQL Editor; no se modifica una base remota durante las pruebas locales.

## Seguridad y límites

- Contraseñas se guardan con hash scrypt; no se almacenan en texto plano.
- Los JWT se firman en Flask y tienen expiración; las rutas privadas verifican su registro activo.
- El cliente guarda el token solo en memoria: al cerrar la app se debe iniciar sesión nuevamente.
- Supabase aplica RLS y solo concede acceso a tablas/funciones a `service_role`; el backend es quien valida la autorización de usuario.
- Las funciones SQL bloquean la actualización de inventario dentro de una transacción para impedir sobreventa y restauran asientos al cancelar.
- El Blueprint permite crear el servicio Render desde el repositorio del proyecto; las credenciales se ingresan en Render y nunca se almacenan en el cliente móvil.
