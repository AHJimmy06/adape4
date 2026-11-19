"""Presentación de eventos posteriores a la compra; sin operaciones financieras."""
from html import escape


def asunto_evento(datos):
    codigo = str(datos.get('vuelo', {}).get('codigo') or 'Tu viaje')
    if datos.get('evento') == 'cancelacion_confirmada':
        return f'AeroTech · Cancelación y reembolso confirmados · {codigo}'
    if datos.get('evento') == 'acceso_otorgado':
        return f'AeroTech · Te otorgaron acceso a un asiento · {codigo}'
    return None


def contenido_evento(datos, importe, aeropuerto, horario, detalle):
    evento = datos.get('evento')
    if evento not in ('cancelacion_confirmada', 'acceso_otorgado'):
        return None
    cancelacion = evento == 'cancelacion_confirmada'
    vuelo = datos['vuelo']
    filas = []
    for asiento in datos['asientos']:
        descripcion = f"Asiento {asiento['codigo']} · {asiento.get('clase_codigo') or 'Clase del vuelo'}"
        if cancelacion:
            descripcion += '\n' + detalle(asiento)
            descripcion += '\nImporte reembolsado: ' + importe(asiento, 'total_centavos')
        else:
            descripcion += f"\nEquipaje adicional: {asiento.get('maletas_adicionales', 0)} maleta(s)"
        filas.append(descripcion)
    if not filas:
        raise ValueError('evento_sin_asientos')
    titulo = 'Lamentamos que no puedas acompañarnos' if cancelacion else 'Tu próximo viaje tiene un lugar para ti'
    mensaje = ('Tu cancelación y su reembolso fueron confirmados. Sentimos que tus planes hayan cambiado; '
               'esperamos volver a acompañarte pronto.' if cancelacion else
               f"{datos['otorgante']} te otorgó acceso a {'un asiento' if len(filas) == 1 else 'estos asientos'}. "
               'Puedes consultar el viaje desde Asientos compartidos conmigo en AeroTech.')
    etiqueta = 'CANCELACIÓN Y REEMBOLSO CONFIRMADOS' if cancelacion else 'ACCESO A TU ASIENTO'
    itinerario = [
        ('Vuelo', str(vuelo.get('codigo') or 'AeroTech')),
        ('Origen', aeropuerto(vuelo, 'origen')),
        ('Destino', aeropuerto(vuelo, 'destino')),
        ('Salida', horario(vuelo, 'salida', 'origen')),
        ('Llegada', horario(vuelo, 'llegada', 'destino')),
    ]
    importes = []
    if cancelacion:
        importes = [('Subtotal reembolsado', importe(datos, 'subtotal_centavos')),
                    ('IVA reembolsado', importe(datos, 'iva_centavos')),
                    ('Total reembolsado', importe(datos, 'total_centavos'))]
    nota = ('Stripe TEST: la devolución es una simulación y no mueve dinero real. '
            'Los extras indicados corresponden únicamente a los asientos reembolsados.' if cancelacion else
            'Este acceso permite consultar tus asientos. No transfiere la compra, los pagos ni los permisos de cancelación. '
            'El comprador puede retirar o cambiar el acceso.')
    pie = 'Demostración en Mailtrap Sandbox. No es un documento fiscal y no se entrega a un buzón real.'
    texto = '\n\n'.join([titulo, f"Hola, {datos['nombre']}.", mensaje,
        '\n'.join(f'{k}: {v}' for k, v in itinerario),
        'Asientos reembolsados' if cancelacion else 'Tus asientos', *filas,
        '\n'.join(f'{k}: {v}' for k, v in importes), nota, pie])
    filas_itinerario = ''.join(
        f'<tr><td style="padding:8px;color:#526784">{escape(k)}</td>'
        f'<td style="padding:8px;color:#102d4b">{escape(v)}</td></tr>' for k, v in itinerario)
    filas_asientos = ''.join(
        '<tr><td style="padding:16px;border-bottom:1px solid #dce7ef;color:#102d4b;line-height:24px">'
        + '<br>'.join(escape(linea) for linea in fila.splitlines()) + '</td></tr>' for fila in filas)
    filas_importes = ''.join(
        f'<tr><td style="padding:10px;color:#102d4b">{escape(k)}</td>'
        f'<td align="right" style="padding:10px;color:#102d4b;font-weight:bold">{escape(v)}</td></tr>'
        for k, v in importes)
    html = f'''<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>{escape(titulo)}</title></head>
<body style="margin:0;background-color:#edf4f9;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:640px;background-color:#ffffff">
<tr><td style="padding:24px;background-color:#102d4b;color:#ffffff;font-size:24px;font-weight:bold">AeroTech</td></tr>
<tr><td style="padding:28px 24px 8px;color:#176bac;font-size:12px;font-weight:bold">{escape(etiqueta)}</td></tr>
<tr><td style="padding:8px 24px;color:#102d4b;font-size:28px;line-height:36px;font-weight:bold">{escape(titulo)}</td></tr>
<tr><td style="padding:16px 24px;color:#102d4b;line-height:24px">Hola, {escape(str(datos['nombre']))}.<br><br>{escape(mensaje)}</td></tr>
<tr><td style="padding:8px 24px"><table role="presentation" width="100%" style="background-color:#eef8fa">{filas_itinerario}</table></td></tr>
<tr><td style="padding:16px 24px"><table role="presentation" width="100%">{filas_asientos}</table></td></tr>
<tr><td style="padding:0 24px 16px"><table role="presentation" width="100%" style="background-color:#edf4f9">{filas_importes}</table></td></tr>
<tr><td style="padding:20px 24px;background-color:#f5f8fb;color:#526784;font-size:12px;line-height:20px">{escape(nota)}<br><br>{escape(pie)}</td></tr>
</table></td></tr></table></body></html>'''
    return texto, html
