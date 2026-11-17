# AeroTech — cliente Flutter

Cliente en español con landing, globo 3D local, autenticación, catálogos administrativos, asientos numerados persistentes y pagos **Stripe TEST**. La API está en Render y la base en Supabase: para utilizarla solo debe iniciar Flutter.

## Iniciar

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://adape4-reservas-vuelos-api.onrender.com
```

Ejecute los comandos desde `aplicacion_flutter`. Para compartir, utilice el ZIP sin dependencias y vuelva a ejecutar `flutter pub get`. No se incluyen claves ni sesiones.

`API_BASE_URL` se establece al compilar. Sin el parámetro se conserva `http://10.0.2.2:5000`, reservado para un backend local desde el emulador Android. No es la dirección de Render.

## Flujo disponible

- USER: registro/login, filtros por aeropuertos, mapa nacional o globo internacional, cabina completa por clases.
- Selección por doble clic o Enter; cada etiqueta pertenece a un asiento real del vuelo. El servidor impide la doble venta.
- Pedido con retención temporal, Checkout externo TEST y confirmación exclusivamente del servidor. Regresar de Stripe no acredita pago.
- Reservas con etiquetas, clases e importes históricos; cancelación parcial por asientos y reembolso proporcional TEST; XML vertical académico.
- ADMIN: aeropuertos con coordenadas/zona IANA, aviones con distribución por clases, rutas, vuelos, tarifas y promoción de usuarios.
- Las ediciones usan versión; los vuelos comprometidos por retenciones, compras o devoluciones pendientes no pueden modificarse/desactivarse.
- Horarios civiles de cada aeropuerto, salida en día local posterior a hoy y llegada UTC posterior a salida, incluso cruzando días/zonas.

## Pruebas

```powershell
flutter test --no-pub
flutter analyze --no-pub
```

Guía, contrato, arquitectura y evidencias: `../docs/ape4/`. Las capturas con sufijo `local-aislado` corresponden al entorno de pruebas, no a la base remota.

**Nunca use tarjetas reales:** la pasarela y los reembolsos son de prueba. El IVA del 15 % y el XML no constituyen facturación fiscal.
