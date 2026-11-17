# Manual de usuario de AeroTech

AeroTech permite buscar vuelos, elegir asientos reales y gestionar reservas con Stripe en entorno de prueba. Las pantallas de acceso, vuelos, ruta, cabina, pago, reservas y XML se contrastaron con la interfaz integrada; las capturas ADMIN se obtuvieron en el entorno local aislado. Consulte el acta para distinguir lo ejecutado en Render de lo probado localmente.

> **Solo TEST:** no utilice tarjetas reales. El IVA del 15 % y el comprobante XML son académicos, no fiscales. No comparta su contraseña ni capturas con datos de sesión.

## 1. Preparación y acceso

1. Abra el cliente AeroTech del entorno indicado por el responsable de la práctica.
2. Si no tiene cuenta, complete el formulario de registro y envíelo una sola vez. El registro no incorpora confirmación adicional por correo ni un segundo factor propio.
3. Inicie sesión con su cuenta. El servidor determina si su rol es USER o ADMIN; no basta modificar la interfaz para obtener permisos.
4. Mantenga abierta la aplicación mientras se realiza el pago externo. La sesión JWT se conserva en memoria; al cerrar o recargar completamente el cliente puede ser necesario iniciar sesión otra vez.

Si el registro indica cuenta existente, use su cuenta de prueba previa; no cree identidades repetidas para eludir el error. Credenciales incorrectas no deben dar acceso a los servicios privados.

## 2. Buscar y seleccionar un vuelo

1. Seleccione aeropuerto de origen, aeropuerto de destino y fecha de salida. Origen y destino deben ser distintos.
2. Ejecute la búsqueda y revise los vuelos disponibles. La fecha corresponde al día local del aeropuerto de origen.
3. Consulte la ruta y su mapa. Las posiciones representan las coordenadas de los aeropuertos, no una ruta aérea operativa certificada.
4. Abra la cabina del vuelo elegido y revise horario, avión, clases y tarifa.
5. Seleccione únicamente asientos libres. Una etiqueta como **1A** identifica un asiento concreto de ese vuelo; no representa solo una cantidad.
6. Revise el subtotal, IVA académico y total antes de continuar. El servidor calcula el importe definitivo.

La cabina debe mantener visibles todas las filas, incluso cuando existan asientos ocupados. Si otro usuario retiene o compra el mismo asiento antes de confirmar su pedido, actualice la cabina y elija otro; la selección inicial no garantiza disponibilidad.

## 3. Pagar con Stripe TEST

1. Envíe su selección para crear el pedido. Evite iniciar otro pedido si la primera solicitud tarda: consulte primero el estado recuperable.
2. Abra el Checkout alojado por Stripe en la pestaña o navegador externo habilitado por el cliente. No cierre AeroTech.
3. Compruebe que se trata del entorno de prueba. Use solo los datos ficticios de la [documentación oficial de Stripe](https://docs.stripe.com/testing).
4. Complete el flujo. Si Stripe solicita autenticación 3D Secure de prueba, siga ese desafío: no es una confirmación por correo de AeroTech.
5. Regrese a AeroTech y pulse **Actualizar pago** en el pedido.
6. Espere el estado confirmado por el servidor y compruebe que aparece una sola reserva con los asientos elegidos.

Una página de retorno exitosa no prueba por sí sola que el pago esté confirmado. El servidor debe consultar o recibir el estado auténtico de Stripe. Si figura pendiente o en revisión, actualice el mismo pedido; no repita compras para forzar el estado.

### Rechazo, abandono o demora

| Situación | Qué hacer | Qué no asumir |
|---|---|---|
| Tarjeta TEST rechazada | Revise el mensaje; corrija con un caso de prueba autorizado o abandone el pedido | Que existe una reserva pagada |
| No desea continuar | Use la acción de abandono del pedido y espere confirmación | Que cerrar Checkout libera de inmediato el asiento |
| Pago completado pero app pendiente | Use Actualizar pago; conserve el mismo pedido | Que necesita pagar otra vez |
| Proveedor temporalmente indisponible | Espere y reintente la consulta/recuperación del mismo pedido | Que el asiento está libre o el pago no ocurrió |
| Sesión de Checkout expirada | Consulte el pedido y, una vez liberado, inicie una nueva selección | Que el reloj de su PC determina el estado del proveedor |

## 4. Consultar reservas y comprobante

1. Abra la sección de reservas de su cuenta.
2. Seleccione una reserva y revise vuelo, clases, asientos, cantidades e importes originales.
3. Consulte el historial de cancelaciones y el estado de cada asiento.
4. Use la acción de comprobante XML de esa reserva. El documento es académico y debe reflejar importes y estado actual sin incluir secretos.

Solo puede consultar sus propias reservas y comprobantes. No modifique direcciones o identificadores para intentar acceder a información ajena.

## 5. Cancelar parte de una reserva

La política de la práctica devuelve el **100 % proporcional del importe original de los asientos cancelados**, sin penalización, antes de la salida y solo mediante Stripe TEST.

1. Abra la reserva y verifique que el vuelo aún no ha salido.
2. Pulse **Cancelar asientos** y, en el diálogo, seleccione los asientos activos que desea cancelar: mínimo uno y máximo los activos disponibles para cancelación. Las etiquetas de la tarjeta de reserva son informativas.
3. Compruebe el importe indicado y confirme una vez.
4. Actualice la reserva hasta conocer el resultado del reembolso.
5. Compruebe que los asientos no elegidos siguen activos y que el historial contiene la operación.

No puede cancelar cero asientos, seleccionar más que los activos, repetir un asiento cancelado, cancelar una reserva ajena ni cancelar después de la salida. El subtotal y el IVA se toman de la compra original; una edición posterior de tarifa no cambia la devolución.

**Reembolso pendiente:** no significa devolución completada. El asiento permanece bloqueado mientras el proveedor no confirme. Si existe una acción de reintento, úsela sobre la misma cancelación; no cree otra para cobrar dos veces. La cancelación del último asiento no borra el historial.

## 6. Administración

### 6.1. Preparar catálogos

1. Ingrese con una cuenta ADMIN autorizada.
2. Registre aeropuertos con IATA, ciudad/país, coordenadas y zona horaria IANA. Valide que correspondan a ubicaciones reales.
3. Registre el avión y su matrícula.
4. Configure cada clase mediante código, nombre, fila inicial, número de filas y columnas. No repita etiquetas ni solape filas; la capacidad total se deriva de esa distribución.
5. Cree rutas entre dos aeropuertos activos distintos.

No se gestiona una aerolínea por cada cuenta: esta versión corresponde únicamente a AeroTech.

### 6.2. Programar vuelos

1. Seleccione ruta y avión.
2. Introduzca salida en la hora local del origen y llegada en la hora local del destino. Para vuelos que llegan al día siguiente, use la fecha correspondiente; el sistema compara instantes UTC.
3. Asigne una tarifa base en USD a cada clase de la cabina.
4. Guarde y verifique que no exista solapamiento de horario con otro vuelo del mismo avión.
5. Consulte el resultado desde una cuenta USER para comprobar cabina y búsqueda.

No edite una capacidad disponible a mano. El número de asientos libres se calcula según cabina y compromisos reales.

### 6.3. Editar, eliminar y versiones

Las operaciones de edición y eliminación usan una versión del recurso. Si otro administrador cambió el dato y aparece conflicto de versión, recargue antes de volver a guardar; no sobrescriba a ciegas.

El sistema bloquea cambios que invalidarían asientos retenidos, reservas activas o reembolsos pendientes. Cuando ya no hay compromisos, la operación sigue sujeta a referencias y reglas de validación; no borra físicamente el historial.

### 6.4. Roles de usuarios

La promoción de un usuario a ADMIN corresponde a la operación administrativa existente y autorizada. Nunca se obtiene ADMIN mediante autorregistro ni modificando el JWT. La API existente lista usuarios mediante `GET /api/admin/usuarios` y promueve mediante `POST /api/admin/usuarios/{id}/promover`, ambas con autorización ADMIN. **PENDIENTE de contraste de interfaz:** ubicación y etiqueta exacta del control de gestión de roles del cliente integrado.

## 7. Mensajes y recuperación

| Respuesta | Interpretación | Acción |
|---|---|---|
| 400 | Datos inválidos o selección fuera de límites | Corregir los campos indicados |
| 401 | Sesión ausente o no válida | Iniciar sesión de nuevo |
| 403 | Rol insuficiente o acceso no autorizado | Usar únicamente operaciones de su rol |
| 404 | Recurso no encontrado | Actualizar la lista y revisar la selección |
| 409 | Asiento, versión u operación en conflicto | Recargar y recuperar la operación existente |
| 410 en compra antigua | Flujo de cantidades retirado | Usar selección de asientos y Checkout del nuevo sistema |
| 503 o error de proveedor | Servicio no configurado/disponible | Conservar el pedido y comunicar el incidente sin compartir secretos |

Un error no autoriza a omitir el pago, liberar inventario manualmente o crear una reserva gratuita.

## 8. Evidencias para el estudiante

Para cada flujo registre pantalla, fecha, entorno y resultado real según [PRUEBAS_Y_EVIDENCIAS.md](PRUEBAS_Y_EVIDENCIAS.md). Las capturas deben mostrar el estado y contexto necesarios, no contraseñas ni tokens. La existencia de este manual no demuestra que los pasos hayan pasado las pruebas.

**Control final pendiente:** contrastar etiquetas y navegación con el cliente integrado; confirmar registro/login/roles, apertura de Checkout externo, botón Actualizar pago, acción XML y cancelación parcial antes de convertir este manual a Word.

## Inicio del cliente entregado

Desde la carpeta `aplicacion_flutter`:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://adape4-reservas-vuelos-api.onrender.com
```

No hace falta iniciar Flask, Docker ni PostgreSQL para usar el entorno remoto. Docker se utilizó únicamente para pruebas aisladas del desarrollo. El plan gratuito de Render puede tardar en responder cuando el servicio despierta; no debe interpretarse una demora como pago fallido definitivo.
