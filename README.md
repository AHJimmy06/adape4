# AeroTech — sistema integral APE4

Sistema de reservas de una sola aerolínea: Flutter, API Flask en Render, PostgreSQL administrado en Supabase y pagos **Stripe TEST**. La guía principal es `MATERIA/APE4_AD.pdf`; los materiales anteriores se usaron como referencia de estilo.

## Usar la aplicación: solo iniciar Flutter

```powershell
cd aplicacion_flutter
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://adape4-reservas-vuelos-api.onrender.com
```

No inicie Docker ni el backend local para utilizar esta API. Las cuentas existentes y el ADMIN se conservaron; las cuentas nuevas se registran como USER. Nunca introduzca tarjetas reales.

## Funciones

- ADMIN: aeropuertos con coordenadas y zona horaria, aviones con distribución y clases, rutas, programación y tarifas de vuelos, gestión de usuarios/promoción autorizada.
- USER: búsqueda, mapa nacional o globo3D internacional, selección de asientos concretos, Checkout alojado, reservas propias, cancelaciones parciales y comprobante XML académico.
- Inventario transaccional, retenciones temporales, versiones de edición, protección de vuelos comprometidos y control de solapamiento del avión por instantes UTC.
- Confirmación de pagos y devoluciones exclusivamente del servidor/proveedor; webhooks firmados, importes en centavos e idempotencia ante fallos después de escritura.

La cabina inicial es ficticia:36 asientos,8 Ejecutiva y28 Económica. Hay8 aeropuertos y3 vuelos futuros al día de la migración. Fechas/stock cambian al utilizar el sistema.

## Documentación y evidencia

[Índice de la entrega Markdown](docs/ape4/README.md). Incluye guía I–XI, arquitectura PNG, contratos, manual, matriz, acta de ejecución y26 imágenes reales/diagrama. Las capturas `local-aislado` están identificadas y no se presentan como producción remota.

## Backend y base de datos

- `backend/`: Flask, JWT/roles, coordinación de Stripe y adaptador Supabase.
- `database/schema.sql`: instalación en base vacía.
- `database/migrations/008_sistema_integral.sql`: reinicio único autorizado del dominio antiguo. **Ya aplicado en el proyecto remoto APE4: no repetirlo.** No borra usuarios/tokens; la guardia de versión8 rechaza reaplicaciones.
- `render.yaml`: despliegue, secretos definidos exclusivamente en el entorno de Render.

No colocar claves en Flutter, Git, documentación o capturas. `STRIPE_SECRET_KEY` debe ser TEST; el webhook requiere firma incluso en pruebas. La API está fijada a `2026-05-27.dahlia`, igual que el webhook, para no depender de cambios incompatibles del SDK.

## Verificación observada

123 pruebas backend,141 Flutter, análisis sin incidencias y sondas independientes con PostgreSQL real aislado. Recorrido remoto TEST: compra20585centavos, devolución parcial6785 y restante13800; dos devoluciones exactas, historial conservado y todos los asientos nuevamente libres. El acta explica errores iniciales, correcciones y limitaciones; no se ensayaron dispositivos físicos ni dinero real.
