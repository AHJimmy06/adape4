# AeroTech — cliente Flutter

Frontend en español con landing, modelos 3D locales, autenticación y reservas. La API se ejecuta en Render y PostgreSQL en Supabase; para usar la aplicación no hace falta iniciar el backend local.

## Iniciar el frontend

Desde esta carpeta, con Flutter instalado:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://adape4-reservas-vuelos-api.onrender.com
```

`API_BASE_URL` configura la API al compilar. Sin ese parámetro, el código conserva `http://10.0.2.2:5000` para desarrollo Android con backend local. No contiene credenciales de Supabase ni claves administrativas. La sesión JWT permanece únicamente en memoria.

## Funciones

- Landing adaptable antes del login; el globo reutiliza los recursos 3D del proyecto. Con movimiento reducido se muestra el mismo modelo sin rotación automática.
- Registro y login con controles en tiempo real y errores dentro del formulario.
- Consulta de vuelos, reservas para varios pasajeros según disponibilidad, cancelación y comprobante XML.
- La selección numerada de la cabina es una preferencia visual; se persiste la cantidad, no una asignación real de asientos.
- ADMIN: crear, modificar y eliminar vuelos, además de promover usuarios registrados.
- La edición y eliminación envían la versión consultada. Si una reserva u otro administrador cambia el vuelo, se muestra un conflicto y se actualizan los datos antes de continuar.
- No se puede eliminar un vuelo con reservas activas. La eliminación es lógica para conservar el historial de reservas canceladas.

## Validaciones de vuelos

Origen/destino usan `Ciudad, País`. Fecha posterior a hoy en Ecuador mediante calendario; llegada posterior a salida en la misma fecha. Precio con máximo dos decimales, sin letras; asientos enteros. Un vuelo agotado admite edición con cero asientos restantes. El backend vuelve a validar todas las reglas y los permisos.

## Pruebas

```powershell
flutter test --no-pub
flutter analyze --no-pub
```

Detalles del contrato y concurrencia en `../docs/crud-vuelos.md` (en la entrega publicada, `../documentacion/crud-vuelos.md`).
