# Acta de ejecución observada — AeroTech APE4

Fecha: 17 de noviembre de 2026. Todas las operaciones financieras corresponden a **Stripe TEST**, no a dinero real.

## Entornos y alcance

| Entorno | Uso observado |
|---|---|
| Flutter Web local | Cliente real contra API Render; pantallas de registro, login, vuelos, mapa y cabina |
| Render | Servicio `adape4-reservas-vuelos-api`; primera revisión `8c4aa6a`, corrección de versión API en rama de entrega |
| Supabase APE4 | Migración 008 aplicada una vez; usuarios y administrador conservados |
| PostgreSQL 17 aislado | Pruebas funcionales, carreras reales y capturas ADMIN; no es la base remota |
| Stripe SDK + servidor HTTP local | Fallos de transporte después de escritura, idempotencia y HMAC; no equivale a pago integrado |

## Resultados automatizados observados

| Comando | Resultado final |
|---|---|
| `python -m pytest backend/tests -q --tb=short` con `AEROTECH_TEST_DSN` de PostgreSQL local | **119 aprobadas**, 84,35 s; incluye SQL real y SDK HTTP simulado |
| `flutter test --no-pub --reporter compact` | **140 aprobadas** |
| `flutter analyze --no-pub` | **Sin incidencias** |
| `python -m pytest backend/tests/test_stripe_sdk_simulacion.py -q` | 5 aprobadas por escritor; comprobación del padre anterior: 4 aprobadas antes de agregar regresión de versión |
| Carga de esquema nuevo, sonda SQL transaccional y `compileall` | Salida 0 |
| Sondas independientes SQL/HTTP | Sin bloqueos reproducidos; un ganador para el mismo asiento, propiedad, reembolsos exactos, recuperación de incertidumbre y rechazo de sesión ajena |

La primera suite Flutter detectó una expectativa antigua de texto: 139 aprobadas y una fallida. Se actualizó la expectativa a «Vuelo con reservas»; la repetición completa aprobó las 140. Esto no se oculta como si la primera ejecución hubiera sido correcta.

## Reinicio autorizado de la aplicación

| Medición Supabase | Antes de 008 | Después de 008 |
|---|---:|---:|
| Usuarios existentes | 2 | 2 |
| Administradores | 1 | 1 |
| Tokens existentes | 17 | 17 |
| Vuelos/reservas del dominio antiguo | 5 / 6 | Eliminados por autorización |
| Aeropuertos / aviones / vuelos nuevos | No existían | 8 / 1 / 3 |
| Asientos numerados | No existían | 108: 36 por vuelo |

La guardia de repetición se comprobó en PostgreSQL aislado; **no** se repitió el borrado remoto para fabricar una captura. Después se registró una cuenta USER sintética para el recorrido integrado; no se alteró el rol de la cuenta real del usuario.

![Conteos reales posteriores a la migración](capturas/P04-migracion-supabase.png)

## Comprobaciones HTTP de Render

- `GET /api/sistema/vuelos`: HTTP 200, tres vuelos.
- `GET /api/sistema/pedidos` sin JWT: HTTP 401, código `autenticacion_requerida`.
- Registro e inicio de sesión desde Flutter contra Render: cuenta sintética USER accede a vuelos y cabina.

## Incidencia real detectada al integrar Stripe

El primer intento Checkout obtuvo HTTP 400 del proveedor: la API `2026-10-28.endive`, predeterminada en SDK 17, retiró `payment_method_types`. La retención permaneció segura y no se emitió una reserva ni se inventó un pago.

Corrección: fijar explícitamente `2026-05-27.dahlia`, igual que el webhook, manteniendo tarjeta, importes, metadatos, cuerpo y clave idempotente. La regresión observó primero el encabezado incorrecto (RED) y después el correcto (GREEN). Una sonda independiente confirmó el encabezado y la preservación de cuerpo/clave/sesión.

**Resultado financiero integrado posterior a la corrección:** pendiente de completar con el proveedor real TEST. No declarar éxito a partir de la simulación ni del retorno del navegador.

## Capturas reales disponibles

Las capturas ADMIN con sufijo `local-aislado` se tomaron en una base reconstruible con una cuenta ficticia; no demuestran por sí solas administración en Supabase. Las demás pantallas de la aplicación se conectaron a Render.

- A01: diagrama de diseño, no captura de ejecución.
- P00: landing.
- P01: formulario de registro real.
- P02: formulario de acceso real.
- P03: catálogos ADMIN, entorno local aislado.
- P04: listado y mapa nacional, más conteos de migración.
- P05: selección de 1A y 3A de clases distintas.
- P15: despliegue Render de la primera revisión.

Los archivos financieros y XML se agregarán solo después de observar sus resultados reales.
