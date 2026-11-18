"""Stripe TEST adapter. No fake payments and no unsigned webhook fallback."""
import os
from datetime import datetime
from backend.models import ErrorAPI


# Match the configured webhook snapshot and the synchronous card-only contract.
STRIPE_API_VERSION = '2026-05-27.dahlia'


class StripeTest:
    def __init__(self, client=None):
        self.client = client

    def ready(self):
        key = os.getenv('STRIPE_SECRET_KEY', '')
        secret = os.getenv('STRIPE_WEBHOOK_SECRET', '')
        base = os.getenv('PUBLIC_API_URL', '').rstrip('/')
        if not key.startswith(('sk_test_', 'rk_test_')) or not secret.startswith('whsec_') or not base.startswith('https://'):
            raise ErrorAPI('pagos_no_configurados', 'Stripe TEST no está configurado. Los asientos no se han cobrado.', 503)
        if self.client is None:
            import stripe
            self.client = stripe.StripeClient(key, stripe_version=STRIPE_API_VERSION, max_network_retries=2,
                                             http_client=stripe.RequestsClient(timeout=15))
        return base

    @staticmethod
    def plain(value):
        return value.to_dict() if hasattr(value, 'to_dict') else dict(value)

    @staticmethod
    def publishable_key():
        key = os.getenv('STRIPE_PUBLISHABLE_KEY', '')
        if not key.startswith('pk_test_'):
            raise ErrorAPI('pagos_no_configurados', 'Falta configurar la clave pública de Stripe TEST para el formulario de pago.', 503)
        return key

    def call(self, method, *args, **kwargs):
        self.ready()
        try:
            return self.plain(method(*args, **kwargs))
        except Exception as error:
            raise ErrorAPI('proveedor_no_disponible', 'No se pudo confirmar la operación con Stripe; vuelve a consultar o reintenta. Se conserva la retención.', 503) from error

    def checkout(self, order):
        base = self.ready()
        metadata = dict(app='aerotech', pedido_id=order['id'], usuario_id=order['usuario_id'])
        params = dict(mode='payment', payment_method_types=['card'], client_reference_id=order['id'],
                      metadata=metadata, payment_intent_data={'metadata': metadata},
                      success_url=base + '/api/stripe/retorno?estado=retorno',
                      cancel_url=base + '/api/stripe/retorno?estado=cancelado',
                      expires_at=int(datetime.fromisoformat(order['creado_en'].replace('Z', '+00:00')).timestamp() + 24 * 3600),
                      line_items=[dict(quantity=1, price_data=dict(currency='usd', unit_amount=order['total_centavos'],
                          product_data={'name': 'AeroTech — ' + ', '.join(s['codigo'] for s in order['asientos'])}))])
        # The persisted request marker keeps recovery of pre-upgrade orders
        # byte-for-byte compatible with their original provider idempotency key.
        ui = (order.get('solicitud') or {}).get('checkout_ui')
        if ui in ('embedded', 'embedded_card_v2', 'embedded_card_v3'):
            params.pop('success_url')
            params.pop('cancel_url')
            params.update(ui_mode='embedded_page', redirect_on_completion='never')
        if ui in ('embedded_card_v2', 'embedded_card_v3'):
            # Versioned options must not alter an existing idempotent payload.
            # These flags are supported by the pinned Stripe v17 API types.
            params.update(wallet_options={'link': {'display': 'never'}},
                          billing_address_collection='auto',
                          phone_number_collection={'enabled': False},
                          saved_payment_method_options={'payment_method_save': 'disabled'})
        if ui == 'embedded_card_v2':
            # Recover existing keys first, including successful responses not yet linked.
            params['name_collection'] = {'individual': {'enabled': False}, 'business': {'enabled': False}}
        # Provider maximum lifetime permits deterministic crash recovery. The
        # 35-minute business hold expires by verified Stripe.expire, never clock-only.
        key = 'aerotech-checkout-' + order['id']
        try:
            return self.call(self.client.v1.checkout.sessions.create, params,
                             options={'idempotency_key': key})
        except ErrorAPI as error:
            cause = error.__cause__
            rejected_names = ('If specifying name_collection, you must have either '
                              '`name_collection[individual][enabled] = true` or '
                              '`name_collection[business][enabled] = true`.')
            if (ui != 'embedded_card_v2' or getattr(cause, 'http_status', None) != 400
                    or getattr(cause, 'user_message', None) != rejected_names):
                raise
            # Only this confirmed validation rejection proves no Checkout was created.
            # A fixed repair key also recovers safely after a lost repair response.
            params.pop('name_collection')
            return self.call(self.client.v1.checkout.sessions.create, params,
                             options={'idempotency_key': key + '-name-fix-v3'})

    def retrieve(self, session_id):
        self.ready()
        return self.call(self.client.v1.checkout.sessions.retrieve, session_id)

    def expire(self, session_id):
        self.ready()
        return self.call(self.client.v1.checkout.sessions.expire, session_id,
                         options={'idempotency_key': 'aerotech-expire-' + session_id})

    def refund(self, cancellation):
        self.ready()
        params = dict(payment_intent=cancellation['payment_intent'], amount=cancellation['importe_centavos'],
                      metadata=dict(app='aerotech', cancelacion_id=cancellation['id'], pedido_id=cancellation['pedido_id']))
        return self.call(self.client.v1.refunds.create, params,
                         options={'idempotency_key': 'aerotech-refund-' + cancellation['id'] + '-' + str(cancellation.get('intento', 1))})

    def retrieve_refund(self, refund_id):
        self.ready()
        return self.call(self.client.v1.refunds.retrieve, refund_id)

    def event(self, payload, signature):
        self.ready()
        if not signature:
            raise ErrorAPI('firma_requerida', 'Se requiere Stripe-Signature.', 400)
        import stripe
        try:
            return self.plain(stripe.Webhook.construct_event(payload, signature, os.environ['STRIPE_WEBHOOK_SECRET']))
        except (ValueError, stripe.SignatureVerificationError) as error:
            raise ErrorAPI('firma_invalida', 'Firma de Stripe inválida.', 400) from error
