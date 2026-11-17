"""HTTP services and payment saga for the frozen /api/sistema contract."""
from datetime import datetime, timezone
import xml.etree.ElementTree as ET

from flask import Response, g, jsonify, request
from backend.models import ErrorAPI
from backend.sistema_validacion import (identifier, integer, invalid, object_body,
                                         seat_codes, validate_catalog)
from backend.stripe_test import StripeTest


class Sistema:
    def __init__(self, repository, provider=None):
        self.repository = repository
        self.provider = provider or StripeTest()

    def rpc(self, action, user=None, **data):
        if not hasattr(self.repository, 'sistema_operar'):
            raise ErrorAPI('sistema_no_configurado', 'Aplica la migración del sistema integral.', 503)
        return self.repository.sistema_operar(action, user, data)

    @staticmethod
    def public_order(order):
        hidden = {'usuario_id', 'session_id', 'payment_intent', 'solicitud', 'incidencia'}
        result = {k: v for k, v in order.items() if k not in hidden}
        result.update(moneda='usd', mensaje=order.get('incidencia'))
        return result

    def owned_order(self, order_id, user):
        return self.rpc('pedido', user, id=identifier(order_id))

    def checkout(self, order):
        self.provider.ready()
        if order['estado'] == 'preparando_pago' and not order.get('session_id'):
            created = datetime.fromisoformat(order['creado_en'].replace('Z', '+00:00'))
            if (datetime.now(timezone.utc) - created).total_seconds() > 23 * 3600:
                self.rpc('incidencia', order['usuario_id'], id=order['id'])
                raise ErrorAPI('pago_en_revision', 'La recuperación excedió la ventana segura de idempotencia; requiere revisión.', 409)
            session = self.provider.checkout(order)
            self.verify_session(order, session, binding=False)
            order = self.rpc('vincular', order['usuario_id'], id=order['id'], session_id=session['id'],
                             checkout_url=session.get('url'), expires_at=session['expires_at'])
        return order

    def verify_session(self, order, session, binding=True):
        metadata = session.get('metadata') or {}
        safe = (session.get('livemode') is False and session.get('mode') == 'payment'
                and session.get('currency') == 'usd' and session.get('amount_total') == order['total_centavos']
                and metadata.get('app') == 'aerotech' and metadata.get('pedido_id') == order['id']
                and metadata.get('usuario_id') == order['usuario_id']
                and session.get('client_reference_id') == order['id']
                and (not binding or not order.get('session_id') or session.get('id') == order['session_id']))
        if not safe or not str(session.get('id', '')).startswith('cs_test_'):
            self.rpc('incidencia', order['usuario_id'], id=order['id'])
            raise ErrorAPI('pago_no_verificado', 'La sesión de pago no coincide con el pedido; se mantiene en revisión.', 409)

    def reconcile(self, order, session=None):
        if order['estado'] in ('pagado', 'expirado', 'cancelado') and session is None:
            return order
        if not order.get('session_id') and session is None:
            order = self.checkout(order)
        session = session or self.provider.retrieve(order['session_id'])
        self.verify_session(order, session)
        if not order.get('session_id'):
            order = self.rpc('vincular', order['usuario_id'], id=order['id'], session_id=session['id'],
                             checkout_url=session.get('url'), expires_at=session['expires_at'])
        # Expire the provider session after the 35-minute business hold. Always
        # retrieve FIRST: a paid session wins even with a delayed webhook.
        deadline = datetime.fromisoformat(order['vence_en'].replace('Z', '+00:00'))
        if session.get('status') == 'open' and session.get('payment_status') != 'paid' and datetime.now(timezone.utc) >= deadline:
            session = self.provider.expire(session['id'])
            self.verify_session(order, session)
        # payment_status is provider-owned; a redirect and local expiry prove nothing.
        if session.get('payment_status') == 'paid':
            payment = session.get('payment_intent')
            if not isinstance(payment, str) or not payment.startswith('pi_'):
                raise ErrorAPI('pago_no_verificado', 'Stripe no devolvió la referencia del cargo.', 409)
            order = self.rpc('resolver', order['usuario_id'], id=order['id'], status='paid', payment_intent=payment)
            compensation = self.rpc('compensacion', order['usuario_id'], id=order['id'])
            if compensation:
                self.refund(compensation)
                order = self.owned_order(order['id'], order['usuario_id'])
        elif session.get('status') == 'expired':
            order = self.rpc('resolver', order['usuario_id'], id=order['id'], status='expired')
        return order

    def refund(self, cancellation):
        if cancellation['estado'] == 'cancelado':
            return cancellation
        if cancellation.get('refund_id'):
            result = self.provider.retrieve_refund(cancellation['refund_id'])
        else:
            result = self.provider.refund(cancellation)
        meta = result.get('metadata') or {}
        if (result.get('livemode') is not False or result.get('currency') != 'usd'
                or result.get('amount') != cancellation['importe_centavos']
                or result.get('payment_intent') != cancellation['payment_intent']
                or meta.get('app') != 'aerotech' or meta.get('cancelacion_id') != cancellation['id']
                or meta.get('pedido_id') != cancellation['pedido_id']):
            raise ErrorAPI('reembolso_no_verificado', 'La devolución requiere revisión; no se liberaron asientos.', 409)
        return self.rpc('reembolso_resultado', cancellation['usuario_id'], id=cancellation['id'],
                        refund_id=result['id'], status=result.get('status'))

    def webhook(self, payload, signature):
        event = self.provider.event(payload, signature)
        if event.get('livemode') is not False:
            invalid('Solo se aceptan eventos Stripe TEST.', 'modo_no_permitido')
        obj = (event.get('data') or {}).get('object') or {}
        metadata = obj.get('metadata') or {}
        if metadata.get('app') != 'aerotech':
            return {'recibido': True, 'ignorado': True}
        if self.rpc('evento_visto', event_id=event['id']):
            return {'recibido': True, 'repetido': True}
        event_type = event.get('type', '')
        if event_type in ('checkout.session.completed', 'checkout.session.async_payment_succeeded', 'checkout.session.expired'):
            order = self.rpc('pedido_interno', id=identifier(metadata.get('pedido_id')))
            # Retrieve server-side even for signed events: binding and current
            # provider state survive out-of-order deliveries and stale payloads.
            self.reconcile(order, self.provider.retrieve(obj['id']))
        elif event_type in ('refund.created', 'refund.updated', 'refund.failed'):
            cancellation = self.rpc('cancelacion_obtener', id=identifier(metadata.get('cancelacion_id')))
            self.refund({**cancellation, 'refund_id': obj['id']})
        else:
            return {'recibido': True, 'ignorado': True}
        self.rpc('evento', event_id=event['id'], tipo=event_type)
        return {'recibido': True}


def register_system(app, repository, authenticated, administrator, stripe_provider=None):
    system = Sistema(repository, stripe_provider)
    app.extensions['sistema'] = system
    singular = {'aeropuertos': 'aeropuerto', 'aviones': 'avion', 'rutas': 'ruta', 'vuelos': 'vuelo'}

    def catalog_list(resource):
        if request.args.get('admin') == 'true':
            @administrator
            def listing():
                return jsonify(system.rpc('listar', g.usuario['id'], recurso=resource, admin=True))
            return listing()
        data = {'recurso': resource}
        for key in ('origen_id', 'destino_id'):
            if key in request.args:
                data[key] = identifier(request.args[key])
        if 'fecha' in request.args:
            from datetime import date
            try:
                data['fecha'] = date.fromisoformat(request.args['fecha']).isoformat()
            except ValueError:
                invalid('Fecha inválida.')
        return jsonify(system.rpc('listar', **data))

    def catalog_write(resource, item_id=None):
        data = object_body(request.get_json(silent=True))
        if request.method == 'DELETE':
            return jsonify(system.rpc('borrar', g.usuario['id'], recurso=resource, id=identifier(item_id),
                                      datos={'version': integer(data.get('version'))}))
        validated = validate_catalog(resource, data, update=item_id is not None)
        result = system.rpc('guardar', g.usuario['id'], recurso=resource,
                            id=identifier(item_id) if item_id else None, datos=validated)
        return jsonify({singular[resource]: result}), 200 if item_id else 201

    for resource in singular:
        def listing(resource=resource):
            return catalog_list(resource)
        def creating(resource=resource):
            return catalog_write(resource)
        def changing(item_id, resource=resource):
            return catalog_write(resource, item_id)
        app.add_url_rule('/api/sistema/' + resource, 'sistema_list_' + resource,
                         administrator(listing) if resource == 'aviones' else listing, methods=['GET'])
        app.add_url_rule('/api/sistema/' + resource, 'sistema_create_' + resource, administrator(creating), methods=['POST'])
        app.add_url_rule('/api/sistema/' + resource + '/<item_id>', 'sistema_change_' + resource,
                         administrator(changing), methods=['PUT', 'DELETE'])

    @app.get('/api/sistema/vuelos/<flight_id>/asientos')
    @authenticated
    def seats(flight_id):
        # Provider failures never turn an uncertain payment into a free seat.
        for pending in system.rpc('vencidos', g.usuario['id'], id=identifier(flight_id)):
            try:
                system.reconcile(pending)
            except ErrorAPI:
                pass
        return jsonify(system.rpc('cabina', g.usuario['id'], id=identifier(flight_id)))

    @app.post('/api/sistema/pedidos')
    @authenticated
    def create_order():
        system.provider.ready()  # missing configuration creates no hold
        data = object_body(request.get_json(silent=True))
        order = system.rpc('crear_pedido', g.usuario['id'], vuelo_id=identifier(data.get('vuelo_id')),
                           asientos=seat_codes(data.get('asientos')), clave_operacion=identifier(data.get('clave_operacion')))
        order = system.checkout(order)
        if datetime.now(timezone.utc) >= datetime.fromisoformat(order['vence_en'].replace('Z', '+00:00')):
            order = system.reconcile(order)
        return jsonify(pedido=system.public_order(order), checkout_url=order.get('checkout_url')), 201

    @app.get('/api/sistema/pedidos')
    @authenticated
    def orders():
        return jsonify(system.rpc('pedidos', g.usuario['id']))

    @app.get('/api/sistema/pedidos/<order_id>')
    @authenticated
    def order(order_id):
        result = system.reconcile(system.owned_order(order_id, g.usuario['id']))
        return jsonify(pedido=system.public_order(result))

    @app.post('/api/sistema/pedidos/<order_id>/abandonar')
    @authenticated
    def abandon(order_id):
        data = object_body(request.get_json(silent=True))
        identifier(data.get('clave_operacion'))
        result = system.owned_order(order_id, g.usuario['id'])
        result = system.reconcile(result)
        if result['estado'] == 'pagado':
            invalid('El pedido ya está pagado; cancela desde tus reservas.', 'pedido_pagado', 409)
        if result['estado'] not in ('expirado', 'cancelado'):
            session = system.provider.expire(result['session_id'])
            result = system.reconcile(result, session)
        system.rpc('abandonar', g.usuario['id'], id=identifier(order_id))
        return jsonify(pedido=system.public_order(result))

    @app.get('/api/sistema/reservas')
    @authenticated
    def reservations():
        return jsonify(system.rpc('reservas', g.usuario['id']))

    @app.get('/api/sistema/reservas/<reservation_id>')
    @authenticated
    def reservation(reservation_id):
        return jsonify(reserva=system.rpc('reserva', g.usuario['id'], id=identifier(reservation_id)))

    @app.get('/api/sistema/reservas/<reservation_id>/comprobante.xml')
    @authenticated
    def receipt(reservation_id):
        data = system.rpc('reserva', g.usuario['id'], id=identifier(reservation_id))
        root = ET.Element('comprobante', tipo='academico', fiscal='false', moneda='USD')
        for key in ('id', 'creado_en', 'estado', 'cantidad', 'cantidad_activa', 'subtotal_centavos', 'iva_centavos', 'total_centavos', 'reembolsado_centavos'):
            ET.SubElement(root, key).text = str(data[key])
        seats_node = ET.SubElement(root, 'asientos')
        for item in data['asientos']:
            node = ET.SubElement(seats_node, 'asiento')
            for key, value in item.items():
                ET.SubElement(node, key).text = str(value)
        ET.SubElement(root, 'nota').text = 'Comprobante académico; no es documento fiscal ni factura electrónica.'
        ET.indent(root)
        return Response(ET.tostring(root, encoding='utf-8', xml_declaration=True), content_type='application/xml; charset=utf-8')

    def cancellation_response(item):
        public = {key: value for key, value in item.items() if key not in ('usuario_id', 'payment_intent')}
        public['cantidad'] = len(item['asientos'])
        return jsonify(cancelacion=public, reserva=system.rpc('reserva', g.usuario['id'], id=item['reserva_id']))

    @app.post('/api/sistema/reservas/<reservation_id>/cancelaciones')
    @authenticated
    def cancel(reservation_id):
        data = object_body(request.get_json(silent=True))
        item = system.rpc('cancelar', g.usuario['id'], id=identifier(reservation_id),
                          asientos=seat_codes(data.get('asientos')), clave_operacion=identifier(data.get('clave_operacion')))
        return cancellation_response(system.refund(item))

    @app.post('/api/sistema/reservas/<reservation_id>/cancelaciones/<cancellation_id>/reintentar')
    @authenticated
    def retry_cancel(reservation_id, cancellation_id):
        retry_key = identifier(object_body(request.get_json(silent=True)).get('clave_operacion'))
        item = system.rpc('cancelacion_obtener', g.usuario['id'], id=identifier(cancellation_id))
        if item['reserva_id'] != identifier(reservation_id):
            invalid('No se encontró la cancelación.', 'no_encontrado', 404)
        if item['estado'] == 'fallido':
            # Retry only after definitive provider failure, never on timeout.
            confirmed = system.refund(item)
            if confirmed['estado'] == 'fallido':
                item = system.rpc('reembolso_reintentar', g.usuario['id'], id=item['id'], clave_operacion=retry_key)
        return cancellation_response(system.refund(item))

    @app.post('/api/stripe/webhook')
    def webhook():
        return jsonify(system.webhook(request.get_data(cache=False), request.headers.get('Stripe-Signature')))

    @app.get('/api/stripe/retorno')
    def stripe_return():
        return Response('<!doctype html><html lang="es"><meta charset="utf-8"><title>AeroTech</title>'
                        '<h1>Vuelve a AeroTech</h1><p>El retorno no confirma el pago. En la aplicación, '
                        'selecciona Actualizar pago para verificarlo con Stripe.</p></html>', content_type='text/html; charset=utf-8')
