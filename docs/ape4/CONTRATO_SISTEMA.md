# Contrato del sistema integral AeroTech
Versión de implementación: /api/sistema. JSON en español. USD, centavos enteros para pagos; fecha/horaISO8601UTC y zonasIANA de aeropuertos. RolesexistentesADMIN/USER, JWTBeareractual. Rutas/objetosajenos no modificables.

## Convenciones
- Errores: {"error":{"codigo":"...","mensaje":"..."}}, conservarHTTPy ApiService.ExcepcionApi.codigoError.
- Listas: {"aeropuertos":[]}, {"aviones":[]}, {"rutas":[]}, {"vuelos":[]}, {"pedidos":[]}, {"reservas":[]} segúnrecurso. Objetounitario: {"aeropuerto":{}},etc. POSTcrea201, actualiza200, conflictos409, validación400, anónimo401, rol403, inexistente404.
- Catalog CRUD: GETpublico salvoavionespuedeADMIN, POST/PUT/DELETEADMIN; PUT/DELETEversionpositivaobligatoria. Eliminaciónlógica y rechazo si referencias operativas impideneditar. No eliminaciónfísica de historial.
- IDsUUID. No confiar enusuario_id/precios/roles/importes delcliente. clave_operacionUUIDbody permite reintento idempotente delmismo usuario/payload; mismaclave/distintopayload409.
- Campos extra en objetos permitidos; no cambiar nombres listados. TimestampsUTC conZ/offset. precios_centavos enterosno floats.

## Catálogos y vuelos
### Aeropuertos
GET/POST /api/sistema/aeropuertos; PUT/DELETE /api/sistema/aeropuertos/{id}.
Objeto: id,version,activo,iata,nombre,ciudad,pais,codigo_pais,latitud,longitud,zona_horaria. IATA3mayúsculasúnico,lat−90..90/lon−180..180,zon aIANAvalidada,codigo_paisISO2. POSTnocamposid/version/activo requeridos; PUTcompletocamposnegocio+version.

### Aviones
GET/POST /api/sistema/aviones; PUT/DELETE /api/sistema/aviones/{id}.
Objeto: id,version,activo,matricula,modelo,capacidad_total,clases.
clases: [{codigo:'ECO',nombre:'Económica',fila_inicio:4,filas:20,columnas:[['A','B','C'],['D','E','F']],capacidad:120}]. Capacidadderivada,notrustcliente. Códigoclaseno duplicado, filas/etiquetasno solapadas, columnasA..Z sinrepetir, mínimo1asiento,max1000técnico. EjemploEjecutivaJ12asientosfilas1..3,columnas[['A','C'],['D','F']]. Noeditarcabinaaviónconvueloocupado/retenciónvigente.

### Rutas
GET/POST /api/sistema/rutas; PUT/DELETE /api/sistema/rutas/{id}.
POST/PUT: origen_id,destino_id,versionenPUT. Distintosaeropuertosactivos. Objeto: id,version,activo,origen_id,destino_id,origen:{aeropuerto},destino:{aeropuerto},nombre (UIO → GYE).

### Vuelos
GET/POST /api/sistema/vuelos; PUT/DELETE /api/sistema/vuelos/{id}.
POST/PUT: codigo,ruta_id,avion_id,salida_local:'2026-12-20T09:00',llegada_local:'2026-12-20T10:00',tarifas:[{clase_codigo:'ECO',precio_centavos:8900}],versionenPUT. Horariosinterpretadosenzonas de cadaaeropuerto, llegadainstantedespuéssalida, salidaenfuturo; permitellegadasdíasiguient e. Evitarsolapamientodelmismoavión. Tarifasbase>=50centavosUSD/2decimales y todasclases cubiertas; IVA15%académico separado.
Objetolectura: id,codigo,version,activo,ruta:{...},avion:{id,matricula,modelo,clases},salida_en,llegada_en,salida_local,llegada_local,fecha,hora_salida,hora_llegada,origen,destino,precio_desde_centavos,asientos_disponibles,tiene_reservas,tarifas:[{clase_codigo,precio_centavos,disponibles}]. Camposlegadosvisualesorigen/destino sonCiudad,País; coordenadasde ruta aeropuertotienenprioridad.
FiltrosGET: origen_id,destino_id,fecha (fechasalida enorigen); ADMINpuedegestionarconconsulta admin=true y autorizaciónservidor.
GET /api/sistema/vuelos/{id}/asientos (JWT): {vuelo:{...},asientos:[{id,codigo,fila,columna,clase_codigo,clase_nombre,precio_centavos,estado:'libre|retenido|ocupado',es_mio:false}],clases:[...]}.
Cabinacompletaestable, no desaparecerfilas porquehayocupados. Editar/eliminar bloqueado conreservasactivas, retenciones válidas o reembolsopendiente; stockderivadosolo, nevereditmanual.

## Pedidos, pago y reservas
POST /api/sistema/pedidos (JWT): {vuelo_id,asientos:['1A','1C'],clave_operacion:uuid}. Retieneasientosexclusivos ycreaStripeCheckoutTEST deformaservidora. Respuesta201 {pedido:{...},checkout_url:'https://checkout.stripe.com/...'}; mismoclave/payloadretornamismopedido/sesión, no nuevacompra.
Pedido: id,vuelo_id,estado,asientos:[{codigo,clase_codigo,subtotal_centavos,iva_centavos,total_centavos}],subtotal_centavos,iva_centavos,total_centavos,moneda:'usd',vence_en,checkout_url,reserva_id(opcional),mensaje(opcional).
Estadospedido: preparando_pago,pendiente_pago,pagado,expirado,cancelado,revision_pago. No pagado por simple redirección. Checkout tarjetaúnicamente, expiraciónStripe>=30min, montos/monedametadataapp=aerotech ypedidoverificados.
GET /api/sistema/pedidos/{id} (propietario): {pedido:{...}}; puedereconciliarStripeestado realconmismagarantíafirmada/SDKservidor. GET /api/sistema/pedidos {pedidos:[]} propiospendienteshistorialrecuperables.
POST /api/sistema/pedidos/{id}/abandonar {clave_operacion}: expirarCheckoutantesliberarasientos, rechazar si pagado; siStripecaído mantenerretención yestado recuperable,nunca sobreventa.
POST /api/stripe/webhook: RAWbody+Stripe-Signature obligatorio, secretconfiguradoinclusoTEST; eventosdeduplicados,pagadosvalidaramount_total,currency,livemodefalse,session/payment_intent ymetadatospropios. Ignorarobjetosdeotrosproyectos. EventosStripeconrefundsconfirmados actualizanestados sinrepetirdevoluciones.
GET /api/stripe/retorno?estado=...: páginainformativa sinconfirmarpagos ni usartokens, instruyevolverapp. Checkoutseabreenexterno/conservaaplicación; botónActualizarpagoconsultaGETownedpedido.
GET /api/sistema/reservas (JWT): {reservas:[...]}; GET /api/sistema/reservas/{id}: {reserva:{...}}. Reservaobjeto: id,vuelo_id,vuelo:{snapshotruta/avión/horarios},estado,legada(bool),cantidad,cantidad_activa,cantidad_cancelada,subtotal_centavos,iva_centavos,total_centavos,reembolsado_centavos,asientos:[{codigo,clase_codigo,estado:'activo|reembolso_pendiente|cancelado',subtotal_centavos,iva_centavos,total_centavos}],cancelaciones:[...],creado_en.
GET /api/sistema/reservas/{id}/comprobante.xml (JWTpropietario): XMLindentadoconasientos/clases/importes/estado, académico nofiscal; nunca HTMLStripeconteniendosecretos.
POST /api/sistema/reservas/{id}/cancelaciones: {asientos:['1A'],clave_operacion:uuid}. Legacyalternativa {cantidad:1,clave_operacion:uuid}; numseleccionados1..activos, antesdesalida, no duplicados ni propiedad ajena.
Respuesta {cancelacion:{id,estado,asientos,cantidad,importe_centavos},reserva:{...}}. Políticadeprueba: reembolsoproporcional100%sinpenalización, asignaciónIVAcentavosdurable paraquelossubtotales no excedancargo. Cancelacionesfallidassemantienenrecuperables; reservas/asientos retienenseguridad hastaconfirmarreembolso, no liberarporuntimetout. POST /api/sistema/reservas/{id}/cancelaciones/{cancelacion_id}/reintentar {clave_operacion} reusaoperación/cargomismo, nunca doblecargo/reembolso.
- Retencionescaducadas: reconciliarStripeantesdeliberar sihaycheckout, noopin arpagodesde relojlocal; siStripepagadofinalizar, siStripeexpiredliberar, siStripecaídoretener yreintentar. Pagoexcepcionaltardío sinasientosdisponibles=>reembolso/incidenterecuperable,no emitirreserva inválida.
- Legacy: conservarreservasimportes/propiedad/timestamps; no inventarasientosniStripepagos. Cancelaciónparcialrestauracantidadconsistentemente. No permitir antiguoPOSTcantidades emitirreservasgratispara elnuevosistema; retirarlo410conmensajeclienteactualizado siesnecesario. Catálogovueloslegadossinavión/rutanoofrecencompras hasta conversiónADMINsinreservas.

## Configuración e integración
Backendenv: STRIPE_SECRET_KEY (sk_test_/rk_test_ only), STRIPE_WEBHOOK_SECRET, PUBLIC_API_URL=https://adape4-reservas-vuelos-api.onrender.com. Neverprintkeys. Missingcredentials=>503pagos_no_configurados,no falsoéxito. Secrets onlyenvRender/localignored.
ParentsharedFlutter: SistemaApi(ApiService), get(path)->Future<Map>, lista(path,key)->Future<List<Map>>, post/put/delete(path,{body})->Future<Map>, withroutesrelative /api/sistema; XMLmethod optional. ApisolicitarSistema preservesJWT/errorparser. Parentnewmodule lib/services/sistema_api.dart; common returnmapsSpanishJSON. Frontendconstructorpages requiredApiService apiService; no duplicateJWTstorage.
UIADMINnew SistemaAdminPage; UIusernew SistemaVuelosPage and SistemaReservasPage. ParentconnectsLogin toSistemaVuelosPage onceimplementationworks; keepAeroTechstyle/GLB/resources.

## Autorización de reinicio (corrección del usuario)
El usuario autorizó borrar la BDD para evitar conflictos. Se reinicia únicamente el dominio de reservas/vuelos anteriores de APE4, conservando usuarios, roles y acceso actuales. Las ramas de migración/cancelación legacy dejan de ser necesarias tras ese reinicio. Los endpoints de compra antiguos devuelven410; las compras nuevas usan siempre asientos+StripeTEST. El reinicio se ejecuta una sola vez, transaccional y protegido contra repetición accidental; no afecta otros proyectos ni objetos de Stripe.
