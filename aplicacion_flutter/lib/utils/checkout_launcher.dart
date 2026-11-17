import 'package:url_launcher/url_launcher.dart';

typedef CheckoutLauncher = Future<bool> Function(Uri uri);
bool esCheckoutSeguro(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'checkout.stripe.com' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443);
Future<bool> abrirCheckout(Uri uri) async {
  if (!esCheckoutSeguro(uri)) {
    throw const FormatException(
      'El enlace de pago no es un Checkout de Stripe válido.',
    );
  }
  return launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
}
