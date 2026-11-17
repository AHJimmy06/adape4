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
        # Provider maximum lifetime permits deterministic crash recovery. The
        # 35-minute business hold expires by verified Stripe.expire, never clock-only.
        return self.call(self.client.v1.checkout.sessions.create, params,
                         options={'idempotency_key': 'aerotech-checkout-' + order['id']})

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
