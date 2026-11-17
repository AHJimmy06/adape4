# Administración segura de usuarios

Desde **Operaciones → Usuarios**, un ADMIN puede crear cuentas y cambiar el rol de otra persona. El autorregistro público sigue creando exclusivamente cuentas USER.

## Uso

1. Seleccione **Crear usuario** y complete nombre, correo y contraseña de 10 a 256 caracteres. USER es el rol predeterminado.
2. Si elige ADMIN, confirme expresamente que autoriza sus permisos sobre usuarios, catálogos y vuelos.
3. Para modificar una cuenta existente, seleccione **Promover a ADMIN** o **Retirar ADMIN** y escriba el correo exacto mostrado.

Crear una cuenta no inicia sesión con ella ni sustituye la sesión del operador. Retirar ADMIN conserva la cuenta, reservas y sesión del destinatario, pero sus próximas solicitudes administrativas se rechazan. No es posible retirar el propio ADMIN; debe permanecer al menos un administrador. Los errores se muestran dentro del formulario sin simular un guardado exitoso.

## Contrato HTTP

Todas estas operaciones requieren `Authorization: Bearer <token>` y un ADMIN vigente en la base de datos.

| Método y ruta | Entrada | Resultado |
|---|---|---|
| `GET /api/admin/usuarios` | Sin cuerpo | 200, lista de usuarios públicos |
| `POST /api/admin/usuarios` | `nombre`, `correo`, `contrasena`, `rol` opcional (`USER` por defecto) | 201, `{usuario, mensaje}`; sin token nuevo |
| `PUT /api/admin/usuarios/{id}/rol` | `rol`: `USER` o `ADMIN` | 200, `{usuario}` |
| `POST /api/admin/usuarios/{id}/promover` | Sin cuerpo requerido | 200, `{usuario}` con ADMIN; conserva compatibilidad |

Cada usuario público contiene únicamente `id`, `nombre`, `correo`, `rol`. Contraseñas y hashes no se devuelven. Sin sesión: 401; sin ADMIN vigente: 403; datos inválidos o auto-retiro: 400; usuario inexistente: 404; correo repetido: 409. La promoción antigua conserva el rechazo de auto-promoción con 400.

## Instalación de base de datos

En una instalación existente, aplique **solo** `database/migrations/009_administracion_usuarios.sql` antes de desplegar la API que lo requiere. No ejecute de nuevo el esquema integral ni reinicie datos. La migración es aditiva, repetible y no modifica cuentas ni roles existentes. Las instalaciones nuevas ya la incluyen al final de `database/schema.sql`.

La RPC `administrar_usuario(uuid,text,jsonb)` usa un bloqueo transaccional común para todas las creaciones y cambios de rol, incluida la promoción antigua. Relee el rol del actor **después de esperar el bloqueo**, impidiendo que dos administradores se retiren mutuamente usando permisos ya obsoletos. Solo `service_role` puede ejecutarla; la clave de servicio permanece en Flask, nunca en Flutter.

## Verificación local

Ejecute `python -m pytest backend/tests/test_admin_usuarios.py backend/tests/test_admin_usuarios_sql.py backend/tests/test_roles.py` con `AEROTECH_TEST_DSN` apuntando explícitamente a PostgreSQL desechable en loopback. Sin esa variable las pruebas SQL se omiten; eso no demuestra concurrencia. La prueba de carrera usa conexiones PostgreSQL reales y comprueba que una espera el bloqueo antes de perder autorización.

Desde `aplicacion_flutter`, ejecute `flutter test test/widgets/sistema_admin/usuarios/usuarios_test.dart test/pages/sistema_admin_page_test.dart test/services/api_service_test.dart`. Las pruebas HTTP aisladas no sustituyen las pruebas SQL reales; ninguna prueba local implica que la migración ya esté aplicada en un servidor publicado.

## Límite de rollback

Esta entrega no cambia formatos de cuentas ni borra datos. Si fuera necesario volver a frontend/API anteriores, se deben volver ambos componentes a la revisión previa compatible. La función adicional009 puede quedar instalada sin uso; no es necesario eliminarla ni volver a ejecutar008. No se deben revertir decisiones reales de rol o cuentas creadas por usuarios como si fueran datos temporales.
