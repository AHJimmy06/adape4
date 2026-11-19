# Gestionar accesos a asientos después de comprar
Objetivo: asignar, cambiar y retirar acceso por asiento pagado sin transferir la propiedad financiera.
Rama: codex/presentacion-usuarios; entrega: una unidad coherente sin PR; previsión 380 líneas (heurística); checks: análisis Flutter, compilación Python, inspección SQL y verificación independiente; sin nuevos tests ni suites.

## Specs
S1. «digamos que ya hie la reserva y despues ya mi amigo se registror u quiero darle el acceso si puedo despues conceder el asiento a otro ususairo?? o retirarlo?? implementa tmbien eso porfa».
Aceptación: comprador puede asignar/reasignar/revocar cada asiento activo de su reserva pagada a una cuenta registrada. El beneficiario ve solo sus asientos vigentes y pierde lectura al revocar. La propiedad, cancelaciones, importes, factura y snapshot original no cambian.

## Tasks
- T1 | S1 | delegado backend | completado; Python compila y SQL aislado PASS | migración aditiva de permisos vigentes + API propietaria/proyección compartida; razón: dos unidades independientes con superficies disjuntas lanzadas en paralelo | commit pendiente.
- T2 | S1 | delegado frontend | completado; Flutter analyze y revisión PASS | gestión por asiento y sección compartida de solo lectura; razón: misma tanda paralela con contrato fijado | commit pendiente.
- T3 | S1 | inline integración + verificador independiente | comprobación local completa; activación pendiente de consentimiento | riesgos1/2/4/5; comprobar artefactos, aplicar migración/desplegar y actualizar ZIP solo con evidencia | commit pendiente.

## Log
L1. Usuario: «digamos que ya hie la reserva y despues ya mi amigo se registror u quiero darle el acceso si puedo despues conceder el asiento a otro ususairo?? o retirarlo?? implementa tmbien eso porfa».
L2. Descubrimiento: snapshot014 identifica beneficiario para correo, pero API actual lista solo reservas del comprador. No ampliar reserva/XML existente. Añadir permisos actuales aparte, con revocación explícita y versión por asiento. Reutilizar orden de locks91420261117antes8084008 y validación de usuario activo.
L3. Contrato de integración: GET /api/sistema/reservas/<id>/accesos devuelve {reserva_id,asientos:[{codigo,clase_codigo,version,editable,usuario:null|{nombre,correo}}]}. POST misma ruta recibe {asiento,correo:string|null,version:int} y devuelve misma vista actualizada. GET /api/sistema/asientos-compartidos devuelve {asientos:[{id,codigo,clase_codigo,categoria,maletas_adicionales,vuelo:{codigo,salida_local,llegada_local,ruta:{origen:{iata,nombre,ciudad,pais,zona_horaria},destino:{...}}}}]}. Usar cuenta por correo sin directorio de usuarios. Conflictos409 se muestran y recargan, nunca sobrescribir silenciosamente. Lista compartida sin pedido, comprador, otros pasajeros, total de reserva ni XML/pago/cancelación. Sin nuevos correos automáticos; no reabrir pagos. Los asientos cancelados/reembolso en curso/no futuros no se reasignan.
L4. Respetar cambios locales previos del paso de pasajeros: compra_sistema_dialog.dart y pasajeros_asientos.dart NO pertenecen a esta feature ni deben sobrescribirse. Sin modificaciones a documentación pública por instrucción anterior.

L5. T1/T2 entregados en superficies disjuntas: Python compila, Flutter analyze PASS, sin nuevos tests/suites. Migración016 compila y aplica con esquema+010..015 en DB local aislada aerotech_accesos_20261118; negocio en revisión independiente. Assess nativo no evaluable por inventario de archivos previos sin seguimiento; RDD global OFF, sin iniciar revisión nativa. Se mantienen riesgos1/2/4/5.

L6. Verificador independiente S1 sin bloqueantes: transacción local aislada y ROLLBACK verificó trigger pago, asignar/reasignar/revocar, pérdida acceso anterior, denegación a tercero y cuenta inactiva, conflicto de versión, tombstone y prohibición durante reembolso; snapshot/importes intactos. No nuevos tests/suites. Faltan HTTP en vivo, carreras multisesión y navegador. Publicación bloqueada justo antes de migración porque amplía lectura de itinerarios a beneficiarios; confirmar aplicar en Supabase y desplegar Render con sesiones abiertas. No se otorgó acceso real ni se tocó producción.
L7. La unidad es coherente con API+permiso+UI inseparables (~524 líneas de fuente), por encima de la heurística380/400 pero en un solo commit según preferencia de entrega; sin PR ni documentación pública.
