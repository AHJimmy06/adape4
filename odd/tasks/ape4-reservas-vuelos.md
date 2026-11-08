# APE 4 — Reservas de vuelos
Objetivo: construir desde cero una aplicación SOA Flutter + Flask + Supabase siguiendo los ejemplos de la Unidad 4.
Rama: feature/ape4-reservas-vuelos | Entrega: un único commit local al terminar todas las implementaciones (exception-ok por instrucción explícita; sin PR ni cadena) | Verificación: pytest, flutter analyze y flutter test.

## Specs

### S1 — API REST y persistencia
- Alcance: crear una API Flask en español para registro/inicio de sesión, consulta filtrable de vuelos, reserva y gestión/cancelación de reservas; integrar Supabase/PostgreSQL con configuración por variables de entorno.
- Aceptación: tablas `usuarios`, `vuelos`, `reservas` y `tokens`; JWT para rutas protegidas; control transaccional de asientos para evitar sobreventa; filtros de vuelos; errores JSON coherentes.
- Verificación: pruebas automatizadas para validación, autenticación, búsqueda, reserva, concurrencia/inventario y cancelación; esquema SQL ejecutable.
- Riesgo: item 2 (autenticación y protección de credenciales).

### S2 — Cliente Flutter
- Alcance: app Flutter con carpetas `models/`, `services/` y `pages/`, siguiendo los ejemplos del PDF.
- Aceptación: registro/login, consulta de vuelos, reservar, listar y cancelar reservas; interfaz en español; consume solo la API Flask; permiso INTERNET en manifest principal, HTTP permitido solo en debug y HTTPS requerido en release.
- Verificación: análisis estático y pruebas Flutter; verificación estructural de manifests Android; guía para configurar la URL de la API.
- Riesgo: item 5 (permisos y política de cleartext Android determinan conectividad; se habilita HTTP solo en debug y se exige HTTPS en release).

### S3 — Integración y entrega local
- Alcance: integrar cliente, API y esquema; documentar configuración, ejecución y despliegue previsto con Render.
- Aceptación: guía reproducible en español en Markdown y PDF, diagrama SOA en Mermaid, `.env.example` sin secretos y datos semilla demostrativos.
- Verificación: pruebas API, `flutter analyze` y `flutter test` cuando el SDK esté instalado; comprobación estructural del esquema/documentación.
- Riesgo: none.

### S4 — Alineación con el entregable APE 4 y despliegue
- Alcance autorizado (texto del usuario): “modiffica todo para que se alinee con lo del ape y si es verdad te abri render para que tu mismo crees este despliegue desde cero creo que para eso si necesitas un repo en github verda el link es [https://github.com/AHJimmy06/adape4.git](https://github.com/AHJimmy06/adape4.git)”
- Aceptación: calcular subtotal, IVA del 15 % y total en las reservas; persistir los importes para conservarlos aunque cambie el precio del vuelo; ofrecer desde Flutter el comprobante XML asociado a cada reserva; actualizar guía y esquema/migración; dejar configuración reproducible de Render.
- Decisión conservadora: las reservas históricas conservan el total existente, se copian a subtotal y quedan con IVA/porcentaje cero; no se aplica impuesto retroactivo. No ejecutar mutaciones en Supabase remoto sin autorización explícita.
- Verificación: pruebas de redondeo/importe, autenticación y pertenencia al consultar XML, XML válido y escapado, Flutter analyze/test, SQL de esquema/migración y configuración de despliegue.
- Riesgo: item 1 (cambio de importes persistidos y migración), item 3 (ampliación de respuesta REST consumida por Flutter), item 5 (configuración/despliegue externo).

## Tasks
- T1 (S1): API, modelo SQL y pruebas — delegated + integración inline — done; falta prueba contra Supabase real — mismo commit local final.
- T2 (S2): aplicación Flutter, consumo API y permisos de red Android — delegated + correcciones inline — done; sin prueba en dispositivo — mismo commit local final.
- T3 (S3): integración, guía PDF, diagrama y verificaciones — inline — done; end-to-end con Supabase pendiente de credenciales — mismo commit local final.
- T4 (S4): IVA, comprobante XML, cliente y documentación — inline — done; pruebas propias e independiente aprobadas; un solo commit local final.
- T5 (S4): configuración y despliegue Render desde el repositorio indicado — inline — Blueprint listo; despliegue remoto pendiente de confirmar la sesión/credencial autorizada y de ingresar secretos en Render; no tocar el servicio previo `AD-2026`.

## Log
- L1 — User request (verbatim): “bro los pdfs tiene el codigo del que necesito que aprendas la forma de codificar pereo el proyecto si lo debes desarrollar tu.”
- L2 — User authorization/location (verbatim): “como apunta a una carpeta de visualizaciones, bro creo el proyecto desde cero aqui.”
- L3 — Los ejemplos de la Unidad 4 están en `MATERIA/Unidad_4_AD.pdf`, páginas 49-61; la arquitectura/entregables de APE 4 aparecen en páginas 62-64. El material muestra Flutter -> Flask REST -> Supabase/PostgreSQL y despliegue en Render, sin requerir Docker.
- L4 — Engram no aceptó el nombre del workspace actual como proyecto respaldado; el espejo Engram queda pendiente. Aunque inicialmente no se encontró `.git`, después el workspace quedó con un repositorio Git local sin commits en la rama activa; se desconoce el origen de esa inicialización. No se usó GitHub ni se configuró/publicó un remoto.
- L5 — Se elige delegación paralela para T1 y T2: son dos unidades independientes con superficies de escritura disjuntas (`backend/` + `database/` frente a `aplicacion_flutter/`); la coordinación e integración final queda con el agente principal.
- L6 — La lectura del código reveló un desajuste de integración: PostgreSQL usa UUID mientras Flutter asumía enteros; además la consulta ordenaba por `fecha_salida` inexistente, no aplicaba filtros y no reflejaba errores JSON anidados. Se alinearon modelos a UUID, filtros y columna `fecha`, y el cliente extrae el mensaje de error legible.
- L7 — Pruebas RED observadas: el filtro de vuelos devolvía vuelos fuera del criterio; Flutter fallaba al convertir UUID a num; el cliente mostraba el mapa JSON completo en vez del mensaje. Tras las correcciones: pytest 7/7, flutter analyze limpio y flutter test 10/10.
- L8 — Supabase real no fue conectado porque no se compartieron credenciales. `gentle-ai review mode status` indicó OFF global; no se inició ciclo de review. Assessment de cambios devolvió `unassessable` por archivos no rastreados; riesgo item 2 permanece explícito y requiere verificación independiente antes de cierre.
- L9 — El primer intento de un writer usó su cwd implícito y creó seis archivos en `C:\Users\JIMMY\Desktop\PROYECTOSU\ADAPE4\backend\` y un intento de `database/schema.sql`, fuera del destino autorizado. El writer detuvo allí las escrituras; no se borraron porque la limpieza sería una operación destructiva fuera del alcance confirmado.
- L10 — User correction (verbatim): “Un solo commit cunado termines todas las implementacioones, oye como qu ecommit si esta carpeta ni erar repo baboso”. Se retiró el commit de seguimiento prematuro; se preservaron los archivos y no habrá más commits hasta que toda la implementación esté terminada.
- L11 — User clarification (verbatim): “si porfavor, de hecho esto ni es un repo de github”. No hay operaciones remotas, push ni publicación; cualquier commit final será local.
- L12 — Independent verifier blocked S2: el manifest principal de Android no declaraba INTERNET y la URL local HTTP podía fallar por cleartext bloqueado en Android moderno. El hallazgo fue estructural; no se ejecutó una app en dispositivo.
- L13 — Se agregó INTERNET al manifest principal y una configuración de red cleartext solo en `src/debug`; las guías ahora exigen HTTPS para release. La re-verificación independiente limitada confirmó el arreglo estructural.
- L14 — Revisión independiente revalidó el arreglo S2 en copia temporal: XML del manifest principal/debug correcto y docs coherentes. No se realizó prueba en dispositivo. `flutter build apk --debug` se interrumpió tras más de 7 minutos sin completar ni arrojar error de compilación; quedó prueba runtime/build no disponible.
- L15 — Verificación final observada: `python -m pytest backend/tests -q` = 7 passed; `python -m py_compile ...` = correcto; `flutter analyze` = sin problemas; `flutter test` = 10 passed; verificación XML de red = correcta; PDF de dos páginas renderizado y revisado visualmente. Sin conexión real a Supabase por falta de credenciales.
- L16 — La única entrega de Git autorizada por el usuario es un commit local cuando toda la implementación esté lista; se retiró la referencia del commit de seguimiento prematuro y se conservaron los archivos. No se hará push, PR ni uso de GitHub.
- L17 — User change of scope (verbatim): “modiffica todo para que se alinee con lo del ape y si es verdad te abri render para que tu mismo crees este despliegue desde cero creo que para eso si necesitas un repo en github verda el link es [https://github.com/AHJimmy06/adape4.git](https://github.com/AHJimmy06/adape4.git)”. Esta instrucción autoriza preparar el proyecto para el destino indicado y desplegar en Render, pero la sesión/credencial de GitHub a usar debe aclararse antes de cualquier operación remota.
- L18 — Decisión de preservación de datos: el 15 % se aplica a nuevas reservas; la migración conserva total histórico como subtotal y registra IVA/porcentaje cero, evitando recotizar importes ya guardados. El XML es explícitamente académico y no fiscal.
- L19 — Evidencia local tras normalización: pytest = 10 passed; `flutter analyze` = sin problemas; `flutter test` = 12 passed; esquema/migración parseados con PostgreSQL parser; `render.yaml` parseado; PDF regenerado a 3 páginas y revisado visualmente. Sin ejecución contra Supabase remoto ni despliegue Render.
- L20 — La verificación independiente reprodujo que el DEFAULT 15 % se aplicaba a filas históricas antes del backfill aunque su IVA fuera cero. La migración ahora agrega porcentaje sin DEFAULT, conserva importes históricos en el backfill y aplica DEFAULT 15 % después; recheck PostgreSQL 16.15 pasó al aplicar migración dos veces (legacy: 89.00/0.00/0.00/89.00; reserva nueva: 89.00/13.35/15.00/102.35). Parent spot check: `test_database_migration.py` = 1 passed.
