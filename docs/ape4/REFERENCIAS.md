# Referencias de la práctica APE 4

## 1. Fuente académica principal

Universidad Técnica de Ambato. (2026). *APE 4. Desarrollo de servicios web mediante Arquitectura Orientada a Servicios (SOA)*. Guía de Aplicaciones Distribuidas, carrera de Software, sexto nivel, ciclo julio-diciembre 2026. Archivo del proyecto: `MATERIA/APE4_AD.pdf`, 4 páginas.

La página 1 contiene los apartados I-XI; las páginas 2-3 presentan la bibliografía; la página 4 corresponde a validación institucional. No se han reproducido firmas ni completado fechas de validación.

## 2. Bibliografía incluida en la guía institucional

Referencias transcritas de las páginas 2-3, sin atribuirles comprobaciones realizadas en la aplicación. La consulta de los enlaces puede requerir acceso institucional; no se afirma que se haya accedido a los libros completos.

1. Sánchez Hernández, José Juan. (2022). *Aprender Docker, un enfoque práctico* (1.ª ed.). Marcombo. 429 pp. [Biblioteca virtual UTA](https://0x1025muk-y-https-elibro-net.itmsp.museknowledge.com/es/ereader/uta/281855?page=1).
2. Argente, Estefanía; Espinosa, Agustín; Galdámez, Pablo; y Muñoz, Daniel. (2013). *Concurrencia y sistemas distribuidos* (1.ª ed.). Editorial de la Universidad Politécnica de Valencia. 337 pp. [Biblioteca virtual UTA](https://0x102qb8s-y-https-elibro-net.itmsp.museknowledge.com/es/ereader/uta/57365).
3. Cardador, Antonio. (2024). *Desarrollo de aplicaciones web distribuidas* (1.ª ed.). IC Editorial. 221 pp. [Biblioteca virtual UTA](https://0x102qb8s-y-https-elibro-net.itmsp.museknowledge.com/es/ereader/uta/253142).
4. Alvarruiz, Fernando, y Román, José E. (2018). *Ejercicios de programación paralela con OpenMP y MPI* (1.ª ed.). Editorial Universidad Politécnica de Valencia. 191 pp. [Biblioteca virtual UTA](https://0x102qb8s-y-https-elibro-net.itmsp.museknowledge.com/es/ereader/uta/57462). El registro comienza en la página 2 y continúa en la página 3.
5. Serrano Valero, Ramón. (2022). *Diseño de arquitecturas .NET orientadas a microservicios* (1.ª ed.). Marcombo. 452 pp. [Biblioteca virtual UTA](https://0x102qb8s-y-https-elibro-net.itmsp.museknowledge.com/es/ereader/uta/281854).

## 3. Documentación técnica oficial consultada

Consulta documental: 17 de noviembre de 2026. Las siguientes fuentes sustentan conceptos y procedimientos del proveedor, no certifican que AeroTech los haya ejecutado correctamente.

| Fuente | Contenido utilizado | Enlace |
|---|---|---|
| Flutter | Consumo HTTP y procesamiento de respuestas desde el cliente | [Fetch data from the internet](https://docs.flutter.dev/cookbook/networking/fetch-data) |
| Pallets / Flask | Framework de servicios web Python | [Flask Documentation](https://flask.palletsprojects.com/en/stable/) |
| Supabase | API REST de datos y arquitectura con servidor intermedio | [Data REST API](https://supabase.com/docs/guides/api) |
| Stripe | Creación de la sesión de pago alojada | [Create a Checkout Session](https://docs.stripe.com/api/checkout/sessions/create) |
| Stripe | Confirmación servidor y límite de la página de retorno | [Fulfill orders](https://docs.stripe.com/checkout/fulfillment) |
| Stripe | Recepción de eventos y validación de firmas | [Webhooks](https://docs.stripe.com/webhooks) |
| Stripe | Reembolsos parciales y estados pendientes | [Refund and cancel payments](https://docs.stripe.com/refunds) |
| Stripe | Datos ficticios de prueba, rechazos y autenticación 3D Secure | [Testing](https://docs.stripe.com/testing) |

## 4. Fuentes internas y alcance de las afirmaciones

- `CONTRATO_SISTEMA.md`: especificación de integración del dominio `/api/sistema`.
- `ARQUITECTURA.md`: diseño, límites de confianza y estados esperados.
- `PRUEBAS_Y_EVIDENCIAS.md`: protocolo y resultados que deben registrarse realmente.
- `MANUAL_USUARIO.md`: secuencias de uso sujetas a contraste con la interfaz integrada.

El IVA del 15 %, el reembolso proporcional del 100 % antes de salida y la retención de inventario son decisiones académicas del sistema, no asesoramiento tributario ni condiciones comerciales generales de Stripe o de una aerolínea real. No se atribuye un origen de datos de aeropuertos como OurAirports hasta verificar que la implementación lo utiliza y documentar su licencia.
