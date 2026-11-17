# Presentación y administración de usuarios — AeroTech
Objetivo: mejorar formularios/modales activos y permitir crear usuarios y retirar ADMIN de forma segura. Baseline desplegado d292a70; workspace ADAPE4 autoritativo, clon adape4-render-fix para publicar. Rama prevista codex/presentacion-usuarios.
Entrega: exception-ok, un commit final; sin PR/merge automático. Estimación1200–2200líneas, Flutter/pytest/SQL aislado y revisión visual. No tocar Stripe/inventario ni borrar datos existentes.

## Specs
- S1: "hay que mejorar la presentacion de las cosas. esstas son cosas de fornt". Prioridad al Pedido de la imagen: estado legible, importes jerarquizados, asientos claros, fecha humana con zona explícita y acciones separadas. Paleta AeroTech, superficies claras y consistencia responsive.
- S2: "el tema de usuarios tambien necesita poder quitar el ser administrador a un usuario". Acción ADMIN→USER autorizada exclusivamente por un ADMIN vigente, con confirmación, rechazo de auto-retiro y protección de último ADMIN/concurrencia en servidor. Decisión técnica conservadora para no perder acceso.
- S3: "permititr crear usuarios desde ahi". Formulario administrativo nombre/correo/contraseña/rol, rol USER por defecto, validación actual compartida; creación no reemplaza JWT ni sesión del operador. No exponer hashes ni contraseñas en respuestas.
- S4: "Por favor realiza merjores visuales tanto a modales informativos como a los formulario.". Mejorar compra/pedido, XML, cancelación, operaciones de catálogo y usuarios; jerarquía/espaciado/iconos/estados y acciones coherentes. Mantener controles en tiempo real, foco, desplazamiento y errores accesibles.
- S5: Preservar flujos ya verificados de asientos/pagos/reembolsos, cantidades/importes enteros, claves idempotentes, seguridad Checkout y máquina de estados. Cambio visual no altera transacciones. La ampliación de usuarios requiere API y SQL seguros; no basta deshabilitar botones en Flutter.

## Tasks
- T1 — S1,S4,S5 — delegado visual — completado — razón: paralelo independiente con T2, superficie theme/compra/formularios/reservas, sin lógica de negocio; commit pendiente; Risk:none previsto si solo presentación.
- T2 — S2,S3,S4,S5 — delegado usuarios completo — completado — razón: paralelo independiente con T1, superficie backend/SQL + ADMIN/APIusuario y sus pruebas/docs; commit pendiente; Risk:items2,4,5.
- T3 — S1-S5 — inline integración/entrega + verificador independiente — en curso — revisión conjunta, regresiones, captura, API desplegada y ZIP; commit pendiente.

## Log
- L1 usuario literal: "hay que mejorar la presentacion de las cosas. esstas son cosas de fornt, ademas el tema de usuarios tambien necesita poder quitar el ser administrador a un usuario y permititr crear usuarios desde ahi. Por favor realiza merjores visuales tanto a modales informativos como a los formulario."
- Imagen referencia: codex-clipboard-85ad6671-dfeb-4c50-9296-f8e011829619.png; Pedido StripeTEST presenta estado crudo pendiente_pago, fecha ISO y acciones amontonadas.
- Mapa read-only confirmado: visual posee compra_sistema_dialog.dart, formulario_operacion.dart, sistema_reservas_page.dart y theme; usuarios posee sistema_admin_page.dart y api_service.dart. Comparten únicamente constantes estables AerotechTheme ya existentes. APIpública registro siempreUSER sigue intacta; promoción existente continúa compatible.
- Base publicada d292a70;123testsbackend/141Flutter. RDD global OFF. Preservar modificación ajena del clon odd/tasks/corregir-cors-render.md y todo dato/rol real. No reset/migración008 otra vez.

- T1 entregado:10tests propios GREEN, análisis acotado limpio,320x640/texto1.3/teclado. Estado humano y vencimiento EcuadorUTC−5; transacciones intactas. T2backend009estable42testsHTTP/SQL, race de2conexiones/advisorylock observada; UIusuarios aún en curso. Verificador independiente revisa backend aislado; no datos remotos alterados.

- T2 completado y verificador independiente PASS después de única corrección legacy404 (texto exacto baseline, PUT nuevo intacto). Pruebas propias42HTTP/SQL y35Flutteracotadas; suite conjunta padre133backendPASS/93.90s y153FlutterPASS/15s, análisislimpio. Seguridad/concurrencia verificada por sondaspropias independientes:actor revocado mientrasespera lock403, carreras[200,403], duplicados[201,409],RPCanon/authenticateddenegados,009repetiblesindatoscambios.
- QA visual realwidgets conAPI simulada, sin tocar datosremotos: alta deJuanUSER yretiroCarlosADMINfuncionan. Pedido con4asientos35800+5370=41170 igualreferencia. Detectado scrollheredadocabina→pedido; T1corrigióValueKeyporfase yheadercompacto/CTAprioritaria:REDoffset290→GREEN1280x720CTAvisible,12pruebasacotadas. Capturas docs/mejoras-interfaz/capturas; marco360/texto1.3 no esdispositivofísico. AjusteviewportnativonoalterómedidasDOM; overridefuerestauradoyusamosmarcoFlutteraisladoidentificado.
- Supabase009aplicada SOLOaditiva:3usuarios/2ADMINantes ydespués, firmaintegridadid/nombre/correo/hash/rolidéntica;EXECUTEanonfalse/authenticatedfalse/service_roletrue. No se ejecutó RPC demutación sobrecuentasreales. 008noejecutada.

- L2 usuario literal: "usa un subagente en paralelo para preguntar cuanto falta>". Agente de estado estimó10–20min para consolidación/deploy/ZIP, sin prometer tiempos de Render. Código/pruebas ya hechos. Evaluación nativa final HIGH item2; RDD sigue desactivado global, no Status/consent/review iniciado. Verificación independiente roles/concurrencia y recheck legacy404 PASS. Restan commit/push/deploy y ZIP. Rollback pareado API/frontend mantiene función009 aditiva sin borrar datos.
