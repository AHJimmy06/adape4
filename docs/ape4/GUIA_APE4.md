# Guía APE 4: sistema distribuido AeroTech

**Universidad Técnica de Ambato**  
**Facultad:** Ingeniería en Sistemas, Electrónica e Industrial  
**Carrera:** Software | **Nivel:** Sexto | **UOC:** Unidad Profesional  
**Asignatura:** Aplicaciones Distribuidas  
**Ciclo académico de la guía:** julio 2026 - diciembre 2026

Documento base: `MATERIA/APE4_AD.pdf`, cuatro páginas. No se han completado nombres de estudiantes, fechas de ejecución, firmas ni calificaciones. Esos datos deben incorporarse únicamente cuando correspondan a la entrega real.

> **Estado de esta edición:** memoria técnica del diseño y protocolo de demostración. Las pruebas, capturas, despliegue y operaciones Stripe no se consideran aprobados por estar descritos. Los resultados observados se completan en VIII y en el registro de evidencias.

## I. Tema

APE 4. Desarrollo de servicios web mediante Arquitectura Orientada a Servicios (SOA).

**Aplicación:** AeroTech, gestión de vuelos y reservas para una sola aerolínea, con cliente Flutter, servicios Flask, persistencia Supabase y pagos Stripe exclusivamente de prueba.

## II. Objetivo

Diseñar e implementar una aplicación distribuida basada en SOA, con servicios REST e intercambio interoperable entre cliente y servidor. En AeroTech, el objetivo se concreta en registrar y autenticar usuarios, consultar vuelos, seleccionar asientos, procesar pagos TEST y gestionar reservas y cancelaciones parciales.

La demostración debe verificar contratos, control de acceso y consistencia del inventario; no basta con mostrar pantallas o solicitudes que responden HTTP 200.

## III. Modalidad

Presencial, conforme a la guía institucional.

## IV. Tiempo de duración

| Tipo | Horas indicadas en la guía |
|---|---:|
| Presenciales | 12 |
| No presenciales | 0 |

Estas cifras describen la actividad académica; no constituyen un registro de tiempo efectivamente ejecutado.

## V. Instrucciones y desarrollo técnico

### 5.1. Diseño SOA

La separación de responsabilidades organiza servicios de identidad, catálogos, consulta de vuelos, pedidos/pagos y gestión de reservas. El cliente consume contratos HTTP; no accede a las credenciales administrativas de persistencia ni confirma pagos por sí mismo. Son servicios lógicos dentro de una API Flask: no se afirma que cada uno sea un microservicio desplegado de forma independiente.

La topología es **PC con Flutter -> HTTPS -> Flask en Render -> HTTPS PostgREST/RPC -> PostgreSQL administrado por Supabase**. Flask también consume Stripe mediante su SDK servidor. El navegador muestra Checkout alojado por Stripe y Stripe notifica al webhook del backend. La arquitectura no requiere una máquina virtual creada por el estudiante ni una conexión SQL directa desde Flutter. Véase [Arquitectura](ARQUITECTURA.md).

### 5.2. Servicios, proveedores y consumidores

| Servicio | Consumidor | Proveedor | Contrato o recurso | Evidencias |
|---|---|---|---|---|
| Registro | Pantalla de registro Flutter | API de identidad Flask | `POST /api/usuarios/registro` | P01 |
| Autenticación y autorización | Flutter y cada operación protegida | API de identidad Flask | `POST /api/auth/login`; JWT, USER/ADMIN | P02, P03 |
| Aeropuertos, aviones y rutas | Consulta y administración Flutter | API `/api/sistema` | Catálogos versionados | P03, P04, P12, P13 |
| Consulta de vuelos y cabina | Cliente Flutter | API `/api/sistema` | `/vuelos`, `/vuelos/{id}/asientos` | P04, P05 |
| Reserva y pago | Flutter; navegador para Checkout | API Flask y Stripe TEST | `/pedidos`, webhook firmado | P05-P07, P10, P11 |
| Gestión de reservas | Propietario autenticado | API Flask y Stripe TEST | `/reservas`, cancelaciones y XML | P08, P09, P14 |
| Persistencia transaccional | Backend Flask | Supabase/PostgreSQL | PostgREST y funciones RPC | P05, P09-P13 |

El [contrato del sistema](CONTRATO_SISTEMA.md) define campos y códigos HTTP del nuevo dominio. Las rutas preexistentes verificadas de identidad son `POST /api/usuarios/registro`, `POST /api/auth/login` y `GET /api/auth/perfil`. La administración existente expone `GET /api/admin/usuarios` y `POST /api/admin/usuarios/{id}/promover`; esta última exige ADMIN. Los resultados de ejecución siguen pendientes.

### 5.3. Intercambio de información

- JSON representa aeropuertos, rutas, vuelos, cabinas, pedidos, reservas y errores.
- El JWT viaja en `Authorization: Bearer ...`, nunca en enlaces o capturas.
- El comprobante de una reserva propia se obtiene como XML por `GET /api/sistema/reservas/{id}/comprobante.xml`. Es académico, no fiscal.
- HTTP 400 identifica validación; 401 ausencia de autenticación; 403 rol insuficiente; 404 recurso inexistente; 409 conflicto de inventario, versión u operación. Un proveedor no disponible se comunica como error recuperable, sin simular éxito.
- HTTPS protege los intercambios remotos. La prueba P14 registra URL, tipo de contenido y respuesta sin publicar secretos.

### 5.4. Reglas que debe demostrar el sistema

| Regla | Aplicación | Verificación |
|---|---|---|
| Asiento real por vuelo | El código 1A identifica una posición concreta de una cabina y clase | P05: dos clientes no adquieren el mismo asiento |
| Capacidad derivada | Filas y columnas determinan los asientos; no se edita stock a mano | P03, P12 |
| Ruta válida | Origen y destino son aeropuertos distintos con coordenadas y zona IANA | P04 |
| Operación del avión | Un avión no tiene vuelos solapados | P13 |
| Pago verificado | Redirección no equivale a pago; el servidor valida Stripe TEST | P06, P10 |
| Dinero estable | Centavos USD; desglose original inmutable e IVA académico del 15 % | P06, P08, P09 |
| Cancelación proporcional | Entre uno y los asientos activos; antes de salida; 100 % TEST sin penalización | P08, P09 |
| Fallo seguro | Reembolso pendiente conserva bloqueo del asiento; reintentos no duplican cobros | P10, P11 |
| Identidad | Sin confirmación de correo ni 2FA añadido; JWT y roles se mantienen | P01-P03 |

La autenticación 3D Secure que eventualmente solicite Stripe es distinta de la confirmación de identidad propia de AeroTech; no se desactiva como parte de esta práctica.

### 5.5. Pruebas y documentación

El [plan de pruebas y evidencias](PRUEBAS_Y_EVIDENCIAS.md) define precondiciones, procedimiento, estado esperado, forma de comprobar persistencia y captura requerida. Una imagen complementa los resultados; no reemplaza la verificación de exclusividad, firma, idempotencia o sumas monetarias.

## VI. Equipos, materiales y recursos

| Recurso | Uso en la práctica |
|---|---|
| PC y navegador | Ejecutar Flutter y abrir Checkout TEST |
| Internet | Comunicar cliente, API y servicios externos |
| Flutter/Dart | Interfaz cliente y consumo HTTP |
| Python/Flask | Contratos REST, autorización y coordinación de pagos |
| Render | Servicio administrado previsto para la API |
| Supabase/PostgreSQL | Catálogos, inventario e historial transaccional |
| Stripe TEST | Simulación de cobros y reembolsos; sin dinero real |
| Herramientas de pruebas | Validar servicios y registrar salidas reales |
| Inteligencia artificial y TAC | Apoyo técnico sujeto a verificación humana |
| Biblioteca virtual y aula virtual UTA | Bibliografía y material de la asignatura |

Las versiones y URL efectivamente utilizadas se incorporan en el acta de ejecución. No deben copiarse claves de entorno, archivos `.env` ni datos de cuentas privadas.

## VII. Actividades por desarrollar

1. Identificar actores, servicios, contratos y límites de confianza; revisar el diagrama.
2. Configurar persistencia y servicios de prueba dentro del proyecto autorizado.
3. Preparar aeropuertos, aviones con clases, rutas y vuelos futuros.
4. Demostrar registro, autenticación, roles y consumo JSON desde Flutter.
5. Buscar un vuelo y contrastar mapa, cabina, clase y precio calculado por el servidor.
6. Competir por el mismo asiento desde dos sesiones; comprobar exclusividad persistida.
7. Realizar Checkout TEST, reconciliar el pago y emitir una sola reserva propia.
8. Cancelar parcialmente y comprobar reembolso proporcional, límites y recuperación ante fallos.
9. Obtener el XML y verificar seguridad, errores y restricciones administrativas.
10. Completar resultados observados, insertar capturas reales y revisar la trazabilidad.

La guía institucional solicita finalmente un único PDF con el formato establecido. Esta entrega proporciona Markdown solicitado para su conversión a Word; después de incorporar evidencias reales, reunir guía y anexos, revisar saltos de página/tablas/figuras en Word y exportar el PDF académico. No se afirma que esa conversión ya se haya realizado.

## VIII. Resultados obtenidos

**PENDIENTE DE EJECUCIÓN Y CONSOLIDACIÓN:** el texto anterior especifica qué se construye y cómo se comprueba; esta sección no certifica resultados todavía.

| Resultado requerido | Prueba que lo sustenta | Resultado observado |
|---|---|---|
| Arquitectura distribuida SOA identificada | Diagrama y trazabilidad de servicios | PENDIENTE: adjuntar diagrama final y contrastar despliegue real |
| Registro y autenticación operativos | P01-P03 | PENDIENTE: fecha, entorno, respuesta y captura |
| Consulta y reserva de vuelos | P04-P07 | PENDIENTE: vuelo de prueba, estados antes/después y resultado |
| Gestión y cancelación de reservas | P08-P09, P12-P14 | PENDIENTE: cantidades y centavos antes/después |
| Interoperabilidad, disponibilidad y confiabilidad | P10-P11, P14 | PENDIENTE: salidas de pruebas y límites del entorno |

**Acta de cierre:** fecha/hora UTC: PENDIENTE; revisión del código: PENDIENTE; URL comprobada: PENDIENTE; comandos ejecutados y conteos aprobados/fallidos/omitidos: PENDIENTE. No reemplazar estos campos por éxito sin evidencia.

## IX. Habilidades blandas

| Habilidad indicada en la guía | Evidencia de trabajo que se debe registrar |
|---|---|
| Liderazgo | Decisiones de alcance y coordinación de integración documentadas |
| Trabajo en equipo | División de responsabilidades y resolución de incompatibilidades entre contratos |
| Pensamiento crítico | Análisis de carreras de inventario, estados inciertos de pago y límites de las pruebas |

Estas categorías orientan la reflexión del estudiante; no se atribuyen desempeños o calificaciones no evaluados.

## X. Conclusiones

1. El diseño permite explicar SOA mediante responsabilidades y contratos HTTP, sin confundir servicios lógicos con despliegues independientes. Su correspondencia con la aplicación final debe confirmarse en el diagrama y las evidencias P01-P14.
2. La exclusividad de asientos y el cierre de pagos dependen de validación servidor y operaciones transaccionales, no de deshabilitar botones. Solo P05 y P10-P11 permitirán concluir que esa garantía se cumple en la ejecución evaluada.
3. La interoperabilidad se comprobará con solicitudes JSON y comprobantes XML consumidos por el cliente; mientras P14 permanezca pendiente no se declara validación integral.
4. Stripe TEST permite estudiar cobros y devoluciones sin dinero real. Los resultados de pruebas no demuestran habilitación comercial, facturación fiscal ni disponibilidad garantizada en producción.

## XI. Recomendaciones

- Revisar el material del aula y la bibliografía institucional antes de interpretar la arquitectura y sus restricciones.
- Acudir a tutoría cuando existan dudas de SOA, transacciones o pruebas; documentar las decisiones que modifiquen la solución.
- Mantener los secretos en configuración del servidor y excluirlos de capturas, XML, cliente y control de versiones.
- No repetir el reinicio de datos ni ejecutar operaciones en proyectos o cuentas ajenas al alcance autorizado.
- Completar cada resultado con evidencia verificable antes de convertir la guía a Word/PDF; conservar también los errores y pruebas no ejecutadas.
- No extrapolar una demostración funcional a métricas de escalabilidad o disponibilidad sin mediciones adicionales.

## Bibliografía

Véase [Referencias](REFERENCIAS.md): transcribe los cinco libros incluidos en la guía y separa las fuentes técnicas oficiales consultadas. Los libros son bibliografía proporcionada por la asignatura; su inclusión no afirma lectura completa ni acceso a la biblioteca institucional.

## Anexos para la entrega

1. [Arquitectura y flujos](ARQUITECTURA.md).
2. [Contrato de endpoints y datos](CONTRATO_SISTEMA.md).
3. [Pruebas y capturas](PRUEBAS_Y_EVIDENCIAS.md).
4. [Manual de usuario](MANUAL_USUARIO.md).
5. [Referencias](REFERENCIAS.md).
