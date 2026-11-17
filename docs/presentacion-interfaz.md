# Interfaz de pedidos y operaciones

Los diálogos activos de AeroTech usan superficies claras, encabezados con contexto y acciones separadas. La actualización es visual: no modifica pagos, inventario, validaciones ni datos enviados al servidor.

## Qué revisar

| Área | Presentación |
|---|---|
| Pedido | Estado legible, asientos individuales, subtotal e IVA y total destacado. |
| Vencimiento | Fecha humana en hora de Ecuador continental, con etiqueta `Ecuador (UTC−5)`. |
| Operaciones | Secciones de ubicación, cabina, horarios y tarifas; campos y validación existentes. |
| Comprobante | XML seleccionable, enmarcado y con desplazamiento vertical. |
| Cancelación | Asientos activos, importe estimado y acción destructiva diferenciada. |

Las acciones se apilan en espacios estrechos y el contenido conserva desplazamiento con teclado o texto ampliado. Los errores aparecen en paneles accesibles; el color nunca sustituye al mensaje.

## Fechas y confirmación

- Los vencimientos con `Z` u offset se convierten explícitamente a UTC−5, sin depender de la zona del dispositivo. No se agregaron dependencias de zonas horarias.
- Los horarios civiles de vuelos conservan la zona IANA del aeropuerto. No se deduce una conversión usando la zona del equipo.
- Una fecha no válida se presenta como «Fecha por confirmar»; una fecha sin zona no se etiqueta falsamente como Ecuador.
- Volver de Stripe no confirma una reserva. La actualización y liberación de asientos siguen dependiendo del servidor.

## Verificación

Pruebas de widgets cubren estado legible, importes, vencimientos equivalentes con `Z`/offset y cambio de día, 320×640 con texto 1,3 y formulario con teclado. Las pruebas previas conservan cobertura de selección de asientos, conflictos, payloads, idempotencia y centavos. La revisión visual en navegador corresponde a la integración final.
