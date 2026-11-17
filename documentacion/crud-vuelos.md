# Administrar vuelos sin perder cambios

El administrador crea, modifica y elimina vuelos. Eliminar significa retirarlo del catalogo, no borrar historial. Un vuelo con reservas activas no se puede eliminar.

## Uso

1. Abrir Administracion y cargar la lista actual de vuelos.
2. Editar el vuelo y guardar con su `version` original.
3. Si otra persona edito, reservo o cancelo mientras tanto, actualizar la lista antes de intentar nuevamente.

## Contrato API

| Operacion | Entrada | Resultado |
|---|---|---|
| `GET /api/vuelos` | Filtros existentes opcionales | Solo vuelos activos, con `version` |
| `POST /api/vuelos` | Campos de vuelo existentes | Crea version1/activo; ADMIN |
| `PUT /api/vuelos/<id>` | Todos los campos de vuelo y `version` integer1+ | Vuelo actualizado; ADMIN |
| `DELETE /api/vuelos/<id>` | JSON `{"version": 3}` | Retiro logico; ADMIN |

Editar permite cero asientos disponibles para no impedir cambios sobre un vuelo agotado. Crear requiere al menos uno. El inventario enviado es el saldo disponible del editor, no la capacidad total; la version impide restaurar accidentalmente asientos vendidos mientras se editaba. Los importes historicos de reservas no se recalculan.

| Error | Significado |
|---|---|
| 409 `vuelo_modificado` | La version ya cambio: recargar y revisar antes de reenviar |
| 409 `vuelo_con_reservas` | Existe al menos una reserva activa: eliminacion bloqueada |
| 404 `vuelo_no_encontrado` | Vuelo inexistente, inactivo o identificador invalido |
| 400 `version_invalida` | Falta la version o no es entero positivo dentro del rango integer |

## Concurrencia y permisos

La migracion005 agrega `activo` y `version`. Un trigger incrementa version en cualquier UPDATE del vuelo, incluso reserva/cancelacion. Las RPC de edicion y eliminacion bloquean la fila, verifican la version y cambian datos en una sola transaccion. La eliminacion consulta reservas activas despues de tomar ese bloqueo; una reserva simultanea no puede quedar asociada a un vuelo retirado. No se bloquean reservas en orden inverso.

Solo `service_role` ejecuta RPC; Flask verifica ADMIN antes de invocarlas. Anon/authenticated no acceden directamente a tablas ni funciones. El cliente no recibe claves de servicio.

Las fechas de creacion/edicion deben ser posteriores al dia actual de Ecuador (UTC-5), y la llegada posterior a salida en la misma fecha. No se cambian vuelos antiguos existentes al instalar la migracion.

## Verificacion reproducible

- `python -m pytest backend/tests -q` valida contratos, autorizacion, conflictos y carreras con repositorio aislado.
- `database/tests/probar_crud_vuelos.sql` prueba funciones PostgreSQL reales dentro de BEGIN/ROLLBACK, con UUID generados y sin conservar filas.
- `database/tests/probar_crud_vuelos_concurrente.sql` describe dos sesiones para comprobar bloqueo real entre editores y entre reserva/eliminacion. Requiere preparacion y limpieza exclusivas de sus UUID de prueba; no ejecutar todos los bloques juntos.

Aplicar `database/migrations/005_crud_vuelos_concurrencia.sql` antes de desplegar el backend nuevo. La migracion es transaccional e idempotente y no elimina reservas ni vuelos existentes.
