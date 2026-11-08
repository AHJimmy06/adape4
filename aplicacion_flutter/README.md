# Cliente Flutter para reservas de vuelos

Aplicación Flutter en español que se comunica exclusivamente con la API REST Flask. La sesión mantiene el JWT solo en memoria; al cerrar la aplicación será necesario iniciar sesión otra vez.

## Configurar la URL de la API

El cliente usa `http://10.0.2.2:5000` de forma predeterminada, dirección que permite al emulador Android acceder al puerto 5000 del equipo anfitrión. Para elegir otra dirección, pásala al ejecutar Flutter:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

En Chrome u otro navegador local, normalmente se usa `http://localhost:5000`. En un dispositivo físico, usa la dirección IP local del equipo donde se ejecuta Flask y asegúrate de que ambos estén en la misma red. El HTTP local está permitido solo en la variante Android debug; en release configura la URL HTTPS de la API publicada. No incluyas contraseñas ni claves en `API_BASE_URL`.

## Funciones

- Crear una cuenta e iniciar sesión.
- Buscar vuelos por origen y destino.
- Reservar un asiento y consultar las reservas de la sesión autenticada.
- Cancelar una reserva con confirmación.

## Contrato REST consumido

- `POST /api/usuarios/registro`: `{nombre, correo, contrasena}`.
- `POST /api/auth/login`: `{correo, contrasena}`; responde `{mensaje, token, usuario: {id, nombre, correo}}`.
- `GET /api/vuelos`: acepta filtros opcionales `origen`, `destino` y `fecha`; cada vuelo contiene identificador UUID como texto, `origen`, `destino`, `fecha`, `hora_salida`, `hora_llegada`, `precio` y `asientos_disponibles`.
- `POST /api/reservas`: `{vuelo_id, cantidad}`; responde `{mensaje, reserva_id, total, estado}`. La identidad del pasajero se deriva del JWT y el cliente no envía `usuario_id`.
- `GET /api/reservas`: devuelve la lista de reservas del usuario autenticado.
- `DELETE /api/reservas/<id>`: cancela la reserva indicada.

El token JWT se envía como `Authorization: Bearer <token>` en las operaciones protegidas.
