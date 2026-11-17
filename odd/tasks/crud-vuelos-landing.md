# CRUD de vuelos y landing AeroTech
Objetivo: completar edición/eliminación segura de vuelos, landing y desplegar validaciones. Rama: codex/crud-vuelos-landing en clon publicado; frontend vigente en ADAPE4.
Entrega: exception-ok, un commit final conforme instrucción previa del usuario; sin PR. Estimación: 1000–1600 líneas autorales; pruebas Flutter/pytest y transacciones SQL aisladas.

## Specs
- S1: "despliega también los cambios del backend en Render para que tenga las mismas validaciones del front y quede todo funcionando." Mantener las reglas recientes de fecha futura Ecuador, llegada posterior, límites numéricos y roles.
- S2: "COMPLETES EL CRUD DE LOS VUELOS, ES DECIR CANCELAR EL VIAJE Y MODIFICARLO". ADMIN edita y elimina desde panel; creación/listado existentes continúan.
- S3: "AHI TAMBIEN ENTRA LO DE CONCURRECNIA EN LA EDICION DEL VUELO Y LO DE LA ELIMINACION TAMBIEN". Evitar pérdida de actualizaciones y carreras con reservas; conflictos claros y refresco sin reenviar datos obsoletos.
- S4: "NO VOYA PODER BORRAR UN VUELO SI YA TIENE ASIENTOS RESERVADOS". Bloqueo atómico si existe reserva activa. Supuesto conservador: eliminación lógica del vuelo sin reservas activas para conservar historial de reservas canceladas; nunca borrar usuarios/reservas.
- S5: "UNA LANNDIGN PAGE QUE SE MUESTR ANTES DEL LOGIN, PARA ESO SI USA NOMAS LOS MODELOS 3D QUE TENMOS TANTO EN EL LOGIN RESERVA DE LOS VUELOS, ETC". Landing adaptable en español, modelos locales existentes sin nuevas dependencias ni recursos externos, acceso a login/registro.
- S6: "AYUDAME CON TOTODS ESTOS CAMBIOS CON SUBAGENTES EN PARALELO". Escritores con superficies disjuntas: backend/SQL, admin Flutter, landing; padre integra, verifica y despliega.

## Tasks
- T1 — S1-S4,S6 — delegado backend/SQL — completado — Risk: items1,2,3,4,5; conservar inventario y reservas; commit pendiente.
- T2 — S2-S4,S6 — delegado admin Flutter — completado — Risk: items3,4; commit pendiente.
- T3 — S5,S6 — delegado landing — completado — Risk: none; commit pendiente.
- T4 — S1-S6 — inline integración y despliegue — en curso — pruebas y verificador independiente, migración, Render, ZIP/evidencia; Risk: items1,2,3,4,5.

## Log
- L1: "Bro despliega también los cambios del backend en Render para que tenga las mismas validaciones del front y quede todo funcionando. pERO ANTES NECESITO QUE COMPLETES EL CRUD DE LOS VUELOS, ES DECIR CANCELAR EL VIAJE Y MODIFICARLO, AHI TAMBIEN ENTRA LO DE CONCURRECNIA EN LA EDICION DEL VUELO Y LO DE LA ELIMINACION TAMBIEN, DE HECHO NO VOYA PODER BORRAR UN VUELO SI YA TIENE ASIENTOS RESERVADOS, ADEMAS , VOY A NECESITAR UNA LANNDIGN PAGE QUE SE MUESTR ANTES DEL LOGIN, PARA ESO SI USA NOMAS LOS MODELOS 3D QUE TENMOS TANTO EN EL LOGIN RESERVA DE LOS VUELOS, ETC, AYUDAME CON TOTODS ESTOS CAMBIOS CON SUBAGENTES EN PARALELO"
- Base publicada11856a9. Backendlocal contiene validaciones recientes aún no publicadas; usarlo como base de trabajo. Clonehermano adape4-render-fix tiene cambioajeno odd/tasks/corregir-cors-render.md, preservar. RootADAPE4 tienefrontend/otrosdirectoriosuntracked, no gitaddglobal.
- Contrato acordado internamente: vuelos version(int1+) y activo(booltrue), PUT /api/vuelos/<id> requiere fullcampos+version; DELETE requiere JSONversion. RPC transaction lockvuelo, compararversion, bloquear delete con reservas.estado=activa. Version sube en cualquier update incluido stock, reserva/cancelación. Lista pública omite inactivos; booking no permite inactivos. PUT permite0disponibles (vuelo agotado) sin rebajar reservas compradas. Reutilizar validaciones y loaderexistentes. Sin revalorar reservas históricas.

- T3 evidencia: RED observado, landing7testsPASS/análisis4archivoslimpio. ReusaGloboVuelos sinassets/deps; retira3D al navegar y modoestático si movimiento reducido.

- T1 RED10, focal24PASS, fullbackend90PASS66.85s; runnerexterno TEMP/ape4-crud-tests-fb1128b357e1410ea7255ecbe87ff1ca/Scripts/python.exe. T2 RED7/GREEN27 +análisis6limpio. ParentfullFlutter103PASS. Verificadorindependiente y SQLreal pendientes; RDDglobalOFF respetado.

- Verificadorindependiente backend/API/admin/SQLsafePASS24pytest+19Flutter; detectóP2globooculto trasloginpushReplacement. EscritorcorrigióvisibilidadModalRoute.isCurrentOf, regresiónRED->GREEN8, recheckverificador7PASS. Buildfinalenprogreso.
- GotchaeditorSupabase: fill() solo sustituye textarea virtual visible deMonaco y podía dejar prefijodelscriptprevio. PruebaSQL fallórolebegin sin ejecutarfixture. Correcciónoperativa: ControlOrMeta+A,Backspace antesdefill cada consulta; comprobarresultados/metadata.

- T4 SQLreal: migración005 aplicada; probeCRUD_SQL_AISLADO_OK trasBEGIN/ROLLBACK. Carrera2sesiones8s editar/editar: Aprecio12/version2, B VUELO_MODIFICADO. Reserva/eliminación: reserva gana, B VUELO_CON_RESERVAS. Verificaciónversionesactivascorrectastrue/reservaactiva1, permisosanonfalse/usuariofalse/backendtrue. Limpiezaexactafictures: usuarios0/vuelos0. Ningúndatoajeno modificado.
- Landingfinal: movimiento reducido conservaGLBreal estático; animaroptionaldefaulttrue preservalogin. Screenshotdocs/evidencias/landing-ape4.jpg, unmodel-viewervisible. Buildfinal106.9sexit0; fullFlutterfinal104PASS; analyzeglobalclean. ParentspotcheckclonepytestCRUD24PASS27.11s. Backendclonecopiadoúltimasvalidaciones, guardandoarchivoajeno.
