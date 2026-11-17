# Corregir acceso Flutter Web a Render
Objetivo: restaurar comunicación del navegador con la API sin cambiar autenticación ni contratos.
Rama: codex/corregir-cors-render. Entrega: un commit focalizado. Pruebas: pytest backend/tests.

## Specs
- S1: "Bro revisa tu mismo la peticion y arregla ese error para poder iniciar sesion con la API de Render". Comprobar preflight, login y conservación de JWT.

## Tasks
- T1 — S1 — inline — completado — RED: 4 fallos CORS; GREEN: 7 pruebas focalizadas y suite completa 17/17.
- T2 — S1 — verificación independiente — completado (17/17 y probes de orígenes, errores y JWT) — Risk: item 2 (política CORS), item 5 (despliegue).
- T3 — S1 — inline — pendiente — publicar corrección y verificar cabeceras reales; login exitoso requiere credenciales de prueba disponibles.

## Log
- L1: "Bro revisa tu mismo la peticion y arregla ese error para poder iniciar sesion con la API de Render"
- La API responde 200 a /api/vuelos, pero OPTIONS /api/auth/login no devuelve cabeceras CORS. La copia backend en ADAPE4 está desactualizada: se preserva la versión publicada de GitHub en un clon separado.

- Política: permitir únicamente HTTP loopback y orígenes exactos configurables; no wildcard, no cookies, JWT conservado. Sin nuevas dependencias. Revisión nativa desactivada globalmente.

- Verificador independiente sin bloqueantes; prueba focalizada repetida por el padre: 7/7. Publicación de este único commit autorizada por la reparación solicitada de la API Render. T3 continúa hasta verificar producción.
