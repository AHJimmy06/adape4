# Backend integral AeroTech: implementación y verificación

El sistema utiliza Flask como frontera HTTP, PostgreSQL como autoridad de inventario y Stripe Checkout alojado exclusivamente en TEST. No se confirma un pago desde Flutter ni desde una redirección. Las rutas y los campos públicos están definidos en `CONTRATO_SISTEMA.md`.

## Instalación y migración

1. **Base existente:** revisar y ejecutar únicamente `database/migrations/008_sistema_integral.sql` una vez. La autorización del usuario permite eliminar reservas y vuelos antiguos de esta aplicación. Se conservan `usuarios`, contraseñas, roles, administrador y tokens; no se toca `auth`, `storage` ni otro proyecto.
2. **Base vacía:** ejecutar `database/schema.sql`; ya incorpora 008. No ejecutar después 008 de nuevo.
3. La tabla `aerotech_migraciones` registra versión 8. Un segundo intento falla con `MIGRACION_008_YA_APLICADA` **antes** de borrar datos. No se implementa una reaplicación destructiva automática.
4. Configurar en el servidor `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `JWT_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` y `PUBLIC_API_URL`. No colocar secretos en Flutter, documentación, Git ni capturas.
5. Instalar `backend/requirements.txt`. Stripe está fijado a `17.0.0`; `tzdata` permite validar zonas IANA en Windows. `psycopg[binary]` es una dependencia de pruebas SQL, no un segundo acceso productivo.

El trabajador no ejecutó ninguna migración en Supabase ni operación real de Stripe. El despliegue, la configuración final del secreto webhook y la prueba real TEST pertenecen a la integración principal.

## Datos iniciales

Se crean ocho aeropuertos: UIO, GYE, CUE, LOH, MEC, JFK, LIM y BOG, con coordenadas y zonas IANA. Fuente geográfica de referencia: [OurAirports](https://ourairports.com/data/), datos de dominio público. La revisión de referencias forma parte de la documentación principal.

Se crea **un avión ficticio académico**, matrícula `AT-DEMO-01`, de 36 asientos:

| Clase | Filas | Columnas | Capacidad | Tarifa base inicial |
|---|---|---|---:|---:|
| Ejecutiva, EJEC | 1–2 | AC / DF | 8 | USD 120,00 |
| Económica, ECO | 3–9 | AB / CD | 28 | USD 59,00 |

Tres vuelos UIO→GYE, GYE→CUE y CUE→UIO se programan siete días después de aplicar la migración, sin solapamientos. La capacidad se deriva de la cabina; nunca de un contador enviado por el cliente. No se afirma que este avión o aerolínea ficticios operen comercialmente.

## Servicios e invariantes

| Responsabilidad | Implementación |
|---|---|
| Registro, login, JWT y roles actuales | `backend/app.py`, `backend/services.py` |
| Catálogos, compras, reservas, comprobante y cancelaciones HTTP | `backend/sistema_http.py` |
| Validación de cabina, UUID, zonas, importes y etiquetas | `backend/sistema_validacion.py` |
| SDK Stripe TEST, firma y transporte | `backend/stripe_test.py` |
| Adaptador privado Supabase | `RepositorioSupabase.sistema_operar` |
| Transacciones, inventario, reembolsos y estados durables | RPC `public.sistema_operar` y tablas `at_*` |

- Cada asiento tiene una fila persistente y una restricción única `(vuelo_id, codigo)`. La asignación exclusiva se representa con `pedido_id`; las filas de cabina no desaparecen al comprar o cancelar.
- Las mutaciones usan un bloqueo asesor transaccional de aerolínea y filas de vuelo/asientos en orden estable. **Tradeoff:** serialización simple y verificable, apropiada para el alcance académico de una sola aerolínea; no pretende alto volumen distribuido.
- Un trigger rechaza horarios UTC solapados del mismo avión. La salida debe ser un día local posterior a hoy; la llegada se compara como instante UTC y permite otro día u otra zona.
- Editar o desactivar un vuelo con retenciones, asientos pagados o reembolsos pendientes devuelve 409. Una cabina de avión ya asociada a vuelos activos no cambia: primero se reorganizan esos vuelos, evitando inconsistencias entre plantilla y fotografía persistida.
- Aeropuertos y rutas asociados a operaciones activas no se modifican/desactivan. La eliminación es lógica; las reservas conservan fotografía de vuelo y cabina.
- Todas las tablas nuevas tienen RLS. `anon` y `authenticated` no tienen acceso a tablas ni RPC. `service_role` solo lee directamente las tablas nuevas; escribe mediante la frontera transaccional `SECURITY DEFINER`. El servidor recarga el rol actual del usuario y comprueba propiedad por ID de usuario autenticado.
- Los endpoints antiguos de compra por cantidad y mutación de vuelos/reservas devuelven 410, después de autenticar/autorizar. No existe un bypass gratuito de Stripe. Se conservan las rutas antiguas de consulta, login, XML y CORS; el reinicio autorizado deja vacío su dominio histórico.

## Saga de compra y recuperación

1. `POST /api/sistema/pedidos` valida configuración TEST antes de retener. El RPC crea un pedido `preparando_pago`, calcula precios del servidor e IVA agregado del 15 %, asigna centavos por asiento y retiene exclusivamente las etiquetas elegidas.
2. La clave del usuario es UUID y se compara con la solicitud canónica. El mismo usuario/clave/payload recupera el mismo pedido; un payload distinto devuelve 409.
3. El servidor crea Checkout únicamente con tarjeta, USD y metadatos `app=aerotech`, `pedido_id`, `usuario_id`. La clave Stripe es determinística por pedido.
4. La retención de negocio dura **35 minutos** (30 minutos y margen de creación). La sesión del proveedor utiliza un `expires_at` inmutable de creación+24 horas, para que un reintento después de una caída no cambie parámetros ni falle por el mínimo Stripe de 30 minutos.
5. Al consultar o reconciliar una cabina con retenciones vencidas, primero se recupera Stripe. Un pago completado se finaliza; una sesión abierta después del plazo de negocio se expira explícitamente en Stripe; solo una expiración verificada libera inventario. Si Stripe no responde, los asientos siguen retenidos. No existe liberación por reloj SQL solamente.
6. Un corte después de crear Checkout y antes de guardar su ID se recupera con los mismos parámetros y clave Stripe. Después de 23 horas, la recuperación desconocida pasa a revisión antes de acercarse a la ventana de eliminación de claves del proveedor; no se inventa una sesión nueva.
7. Los webhooks requieren cuerpo crudo y `Stripe-Signature`, incluso en TEST. Se valida firma antes de ignorar metadatos ajenos. Se rechaza `livemode=true` y se verifica por SDK la sesión actual, importe, moneda, propietario, referencia y metadatos.
8. Solo una sesión verificada `payment_status=paid` crea la reserva. Eventos repetidos no duplican reservas. Si excepcionalmente llega pago de un pedido cuyo asiento ya fue liberado y reasignado, se genera compensación durable de devolución total; **nunca** se roba el asiento ni se emite reserva inválida.

No hay tarea cron que afirme expiraciones sin consultar al proveedor: la recuperación se ejecuta desde consultas del pedido/cabina y webhooks. Una incidencia fuera de la ventana segura requiere intervención, conservando el inventario.

## Cancelación parcial y dinero

La política académica TEST devuelve el 100 % proporcional de los asientos seleccionados antes de la salida. Se exige al menos un asiento activo, etiquetas sin duplicados, propiedad y clave UUID. Los importes originales no se alteran.

El IVA se redondea una sola vez sobre el agregado. Se distribuye mediante diferencias del impuesto acumulado por asiento, de modo que los ajustes sean de un centavo y las devoluciones sumadas nunca superen el cargo. Cada cancelación reserva su asignación monetaria antes de llamar a Stripe.

`cancelacion.estado`: `reembolso_pendiente`, `cancelado`, `fallido`, `revision`. Los asientos de la reserva usan `activo`, `reembolso_pendiente`, `cancelado`.

- Una devolución pendiente, fallida o de resultado desconocido **no** libera asientos.
- Un timeout después de la escritura remota reintenta la misma clave Stripe y recupera una única devolución.
- Solo tras fallo definitivo verificado se permite una nueva generación durable de intento. Un timeout o estado pendiente nunca habilita una segunda devolución.
- `succeeded` libera exactamente las etiquetas canceladas. Webhooks y reintentos repetidos no aumentan stock ni dinero.
- El XML es académico, no fiscal; incluye estado, clases, etiquetas e importes en centavos. No contiene HTML de Stripe ni secretos.

## Ejemplo público

Solicitud autenticada:

```json
{"vuelo_id":"d0000000-0000-4000-8000-000000000001","asientos":["1A"],"clave_operacion":"11111111-2222-4333-8444-555555555555"}
```

Respuesta resumida; IDs dinámicos y URL se generan realmente por el servidor/proveedor:

```json
{"pedido":{"id":"UUID","estado":"pendiente_pago","asientos":[{"codigo":"1A","clase_codigo":"EJEC","subtotal_centavos":12000,"iva_centavos":1800,"total_centavos":13800}],"subtotal_centavos":12000,"iva_centavos":1800,"total_centavos":13800,"moneda":"usd","checkout_url":"https://checkout.stripe.com/..."},"checkout_url":"https://checkout.stripe.com/..."}
```

Los conflictos de inventario, versión y referencias utilizan `error.codigo=conflicto`, HTTP 409. Errores especializados: `pago_no_verificado`, `reembolso_no_verificado`, `pedido_pagado`, `pago_en_revision`, `pagos_no_configurados`, `proveedor_no_disponible`. Un 503 nunca indica pago exitoso.

## Verificación reproducible

Pruebas unitarias y HTTP conservadas de autenticación, roles y CORS, más nuevas pruebas de PostgreSQL real y del SDK real frente a un servidor HTTP local. El servidor simulado es la dependencia Stripe; la aplicación y los RPC se ejecutan realmente. Los escenarios incluyen desconexión **después** de escribir una sesión o devolución, no solo una respuesta feliz simulada.

```powershell
python -m pytest backend/tests -q
# Para incluir PostgreSQL real, establecer explícitamente AEROTECH_TEST_DSN.
# Solo se aceptan hosts loopback; la suite crea sus propias bases aerotech_test_*.
python -m pytest backend/tests -q
```

Sin `AEROTECH_TEST_DSN`, las pruebas SQL se omiten explícitamente: eso no constituye prueba de inventario. Las bases creadas se conservan para revisión y limpieza del proceso principal, nunca se usan credenciales o URLs de nube implícitas.

Probes SQL:

```sh
psql -v ON_ERROR_STOP=1 -f database/tests/probar_sistema_integral.sql
```

El probe crea sus propios fixtures dentro de `BEGIN/ROLLBACK`; verifica IVA, idempotencia, exclusión, devolución, historial y privilegios. `probar_sistema_concurrente.sql` exige IDs explícitos de fixtures aislados; su equivalente automatizado abre dos conexiones reales y exige exactamente un ganador para el mismo asiento.

**Evidencia observada:** RED inicial de tres rutas inexistentes; GREEN de esas tres. Primera batería nueva de 32 pruebas: 32 aprobadas. Cierre completo: **118 pruebas aprobadas en 77,21 segundos (cierre posterior a normalización UTF-8)**, con PostgreSQL real y SDK Stripe real contra HTTP local; esquema inicial y probe transaccional aprobaron con salida 0. La firma HMAC real se verifica localmente con el SDK. La prueba end-to-end contra Stripe TEST real y el webhook desplegado permanece separada: necesita configuración de firma válida y un checkout efectivamente pagado, no capturas simuladas.

Postman CLI no estaba utilizable en este equipo (el ejecutable encontrado abre la aplicación gráfica); se usó el servidor HTTP local acotado y el SDK instalado para comprobar el transporte. No se publicó ninguna simulación ni se enviaron secretos a servicios externos.

## Referencias de implementación

- [Stripe Python oficial](https://github.com/stripe/stripe-python): `StripeClient.v1`, opciones de idempotencia y `Webhook.construct_event`.
- [Checkout Session create](https://docs.stripe.com/api/checkout/sessions/create): metadatos, tarjetas y expiración.
- [Stripe webhooks](https://docs.stripe.com/webhooks): firma del cuerpo original y tratamiento de eventos.
- [Stripe refunds](https://docs.stripe.com/api/refunds): estado e importes verificados antes de liberar inventario.
