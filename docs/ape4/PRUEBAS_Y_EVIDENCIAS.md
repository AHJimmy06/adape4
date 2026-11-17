# Pruebas funcionales y evidencias de AeroTech

**Ninguna fila de este documento constituye una prueba aprobada mientras su resultado observado permanezca PENDIENTE.** Los procedimientos describen lo que debe ejecutarse en el entorno autorizado. El resultado final debe incluir tanto fallos como omisiones; un mock de Stripe no equivale a un cobro TEST integrado.

## 1. Acta de ejecución

| Campo | Valor observado |
|---|---|
| Fecha y hora UTC | PENDIENTE |
| Revisión de código y versión del cliente | PENDIENTE |
| API y entorno comprobados | PENDIENTE |
| Migración aplicada / reinicio único | PENDIENTE |
| Comandos automatizados ejecutados | PENDIENTE: comando exacto, salida resumida y código de salida |
| Conteos | PENDIENTE: aprobadas / fallidas / omitidas / no ejecutadas |
| Integración Stripe | PENDIENTE: TEST confirmado; no publicar identificadores de cuenta |
| Responsable de la ejecución | PENDIENTE: completar solo con datos reales autorizados |

### Preparación segura

Usar dos cuentas USER de prueba y una ADMIN, vuelos futuros y asientos conocidos. No mostrar contraseñas, JWT, claves, datos personales ni archivos de entorno. Los casos que alteran datos requieren el entorno APE4 autorizado o un estado aislado reconstruible; nunca se ejecutan sobre otros proyectos. Registrar saldo/cantidades iniciales, identificadores opacos de correlación y estado final.

**Reinicio:** comprobar que la guardia impide una segunda ejecución y que usuarios/roles permanecen. No repetir una eliminación para obtener una captura. Ningún procedimiento autoriza eliminar objetos de Stripe.

## 2. Matriz de pruebas

| ID / servicio | Preparación y procedimiento | Estado esperado y forma de comprobarlo | Resultado observado / captura propuesta |
|---|---|---|---|
| P01 Registro | Registrar una cuenta con datos válidos y repetir el mismo identificador; registrar el endpoint real usado | Cuenta única; error controlado al duplicar; no confirmación por correo añadida. Comparar respuesta y registro persistido sin contraseña | PENDIENTE; `capturas/P01-registro.png` |
| P02 Autenticación | Iniciar sesión válida; intentar contraseña incorrecta; solicitar recurso protegido sin token | Sesión válida solo con credenciales correctas; denegación sin token. Registrar códigos reales y ausencia de datos sensibles | PENDIENTE; `capturas/P02-autenticacion.png` |
| P03 Roles y catálogos | USER intenta crear catálogo; ADMIN crea aeropuerto, avión con dos clases y ruta; intentar matrícula/IATA o filas duplicadas; verificar promoción autorizada de rol | USER no administra; ADMIN sí; validación rechaza duplicados; capacidad coincide con filas/columnas. Consultar API y persistencia; no autorregistro ADMIN | PENDIENTE; `capturas/P03-catalogos-roles.png` |
| P04 Consulta y mapa | Crear vuelo futuro por aeropuertos; buscar origen/destino/fecha local; abrir ruta/cabina | Filtro correcto, coordenadas de aeropuertos, zonas y UTC coherentes, clases/precios visibles; ruta no es texto libre. Comparar JSON con UI y datos origen | PENDIENTE; `capturas/P04-busqueda-mapa.png` |
| P05 Concurrencia 1A | Dos usuarios consultan 1A libre del mismo vuelo y solicitan simultáneamente retenerlo con claves distintas | Una retención efectiva; el otro recibe conflicto. Inspeccionar ambos HTTP, filas persistidas y unicidad; actualizar cabina del perdedor. Tras compra, 1A ocupado sin segunda venta | PENDIENTE; `capturas/P05-asiento-exclusivo.png` |
| P06 Checkout pagado TEST | Seleccionar asientos, anotar desglose, abrir Checkout externo, pagar con datos ficticios y volver a actualizar el pedido | Modo TEST, USD y centavos coinciden; una reserva propia tras confirmación servidor; JWT de app conservado. Verificar sesión proveedor, webhook/reconciliación y persistencia; retorno solo no basta | PENDIENTE; `capturas/P06-pago-test.png` |
| P07 Rechazo y abandono | Intentar tarjeta de prueba rechazada; después abandonar un pedido no pagado; repetir abandono | No reserva pagada por rechazo. Liberación solo después de sesión expirada confirmada. Un pedido ya pagado no puede abandonarse. Consultar proveedor y cabina final | PENDIENTE; `capturas/P07-rechazo-abandono.png` |
| P08 Cancelación parcial | Comprar dos o más asientos; cancelar uno antes de salida; actualizar estado | Solo asiento elegido cancelado tras refund confirmado; restantes activos. Comparar centavos originales y devolución TEST proporcional del 100 %, IVA incluido; historial preservado | PENDIENTE; `capturas/P08-cancelacion-parcial.png` |
| P09 Límites e idempotencia | Solicitar cero asientos, más de activos, duplicados, ajenos y cancelación después de salida; repetir compra/cancelación con misma clave y contenido; misma clave con contenido distinto | Solicitudes inválidas no cambian inventario ni dinero. Repetición válida reutiliza resultado; distinto contenido recibe conflicto. Sumas y stock nunca exceden originales; comparar filas y objetos Stripe | PENDIENTE; `capturas/P09-limites-idempotencia.png` |
| P10 Webhooks | En entorno de prueba reproducir evento firmado, reenviarlo y variar orden; probar firma ausente/incorrecta y cuerpo alterado; objeto de otro proyecto | Firma inválida rechazada; evento ajeno sin mutación; replay no duplica reserva/refund; estado pagado no retrocede. Verificar logs sanitizados y conteos persistidos antes/después | PENDIENTE; `capturas/P10-webhook.png` |
| P11 Fallos de proveedor | Simular indisponibilidad al crear Checkout, consultar/expirar sesión y devolver; restablecer proveedor y reintentar | Sin falso éxito; pedido recuperable; inventario incierto permanece bloqueado. Reembolso pendiente no libera asiento; recuperación produce una operación final sin duplicar. Distinguir prueba simulada de integración real | PENDIENTE; `capturas/P11-recuperacion.png` |
| P12 Edición y eliminación | Intentar editar/eliminar vuelo o cabina con hold vigente, reserva pagada y refund pendiente; repetir después de cancelar el último asiento y confirmar devolución; enviar versión antigua | Bloqueo mientras hay compromisos; versión antigua provoca conflicto; ya sin compromisos la operación permitida conserva historial y sigue validando referencias. Confirmar cabina estable y estados persistidos | PENDIENTE; `capturas/P12-proteccion-administrativa.png` |
| P13 Programación de avión | Programar mismo avión en intervalos solapados; repetir con horarios contiguos o no solapados; llegada local del día siguiente | Rechazo del solapamiento; no solapado válido; comparación por instantes UTC no solo texto local. Registrar ambos vuelos y códigos HTTP | PENDIENTE; `capturas/P13-programacion-avion.png` |
| P14 XML y privacidad | Descargar comprobante propio y consultar uno ajeno; registrar solicitudes JSON/XML y HTTPS; revisar cliente, respuestas y capturas | XML legible con asientos/clases/importes/estado y sin secretos; acceso ajeno denegado. Content-Type real y JSON interoperable. Revisión sin credenciales visibles | PENDIENTE; `capturas/P14-comprobante-xml.png` |

Los contratos existentes verificados son `POST /api/usuarios/registro` (`nombre`, `correo`, `contrasena`), `POST /api/auth/login`, `GET /api/auth/perfil`, `GET /api/admin/usuarios` y `POST /api/admin/usuarios/{id}/promover`. Los dos últimos requieren ADMIN. Los códigos HTTP realmente recibidos se registran al ejecutar P01-P03; no se deducen del nuevo prefijo `/api/sistema`.

## 3. Ficha que se completa por cada prueba

Copiar esta ficha para P01-P14 al ejecutar, sin borrar resultados fallidos anteriores:

- **ID:** PENDIENTE: ID de la matriz.
- **Entorno, revisión y fecha UTC:** PENDIENTE.
- **Precondiciones reales:** PENDIENTE: vuelo/asientos/estado inicial, sin datos personales.
- **Acción ejecutada:** PENDIENTE: pasos o comando exacto sanitizado.
- **Respuesta observable:** PENDIENTE: HTTP, mensaje y estado visible.
- **Persistencia y proveedor:** PENDIENTE: conteos y estados antes/después; si no aplica, justificar.
- **Resultado:** PENDIENTE: aprobado, fallido, omitido o no ejecutado, con motivo.
- **Captura y salida asociada:** PENDIENTE: ruta de archivo realmente existente.
- **Limitación:** PENDIENTE: simulación, demora, permisos o falta de integración.

Una prueba de concurrencia requiere observar ambos contendientes y la base; una captura aislada de un asiento ocupado no prueba exclusividad. Un webhook fabricado sin firma del entorno no acredita validación de firma real.

## 4. Capturas para incorporar en Word

Las rutas de la matriz son **destinos propuestos**, no imágenes existentes. No se insertan enlaces de imagen hasta que los archivos sean reales. Al incorporarlos, usar rutas relativas a este documento, por ejemplo `capturas/P06-pago-test.png`, para que la carpeta sea portable al convertir a Word.

| Figura | Encuadre recomendado | Texto de pie que se completa con lo observado |
|---|---|---|
| A01 | Diagrama final con PC, Render, Supabase y Stripe TEST | Arquitectura revisada de la versión indicada en el acta |
| P01-P03 | Formulario/resultado y rol visible, sin credenciales | Servicio y resultado HTTP observado |
| P04 | Filtros, mapa y ruta entre aeropuertos | Aeropuertos y fecha de prueba |
| P05 | Dos sesiones y cabina después del conflicto | Un ganador, respuesta del perdedor y conteo persistido |
| P06-P07 | Checkout TEST y retorno a pedido en AeroTech | Estado Stripe y estado de pedido confirmados |
| P08-P09 | Reserva antes/después y desglose cancelado | Asientos activos/cancelados y devolución en centavos |
| P10-P11 | Resultado de test o log sanitizado y estado seguro | Firma/replay/fallo aplicado y resultado real |
| P12-P13 | Mensaje de protección y datos de vuelo | Restricción comprobada y respuesta observada |
| P14 | XML académico sin identificadores sensibles | Propiedad, contenido y tipo de respuesta |

Antes de publicar, revisar cada imagen con zoom legible. Ocultar secretos **antes** de capturar. No cubrir una pantalla con datos ficticios para aparentar una ejecución real. Indicar recortes o anonimización cuando alteren la comprensión de la evidencia.

## 5. Cierre y trazabilidad

| Criterio APE4_AD | Evidencias mínimas | Estado |
|---|---|---|
| Servicios, contratos, consumidor y proveedor | Arquitectura A01-A02 y contrato | PENDIENTE de contraste con integración |
| Registro y autenticación | P01-P03 | PENDIENTE |
| Consulta, reserva y gestión | P04-P09, P12-P13 | PENDIENTE |
| JSON/XML y HTTP/HTTPS | P02, P04, P14 | PENDIENTE |
| Errores, interoperabilidad y confiabilidad | P05, P07, P09-P11 | PENDIENTE |
| Capturas de pruebas realizadas | Archivos reales P01-P14 y pies | PENDIENTE |

**Resumen final por completar:** aprobadas PENDIENTE; fallidas PENDIENTE; omitidas PENDIENTE; pendientes PENDIENTE. Anotar las limitaciones concretas y trasladar los resultados a VIII de `GUIA_APE4.md`. No convertir pendientes en aprobaciones por existir código o documentación.
