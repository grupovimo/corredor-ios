# Corredor para iPhone: estado y cómo retomar

Objetivo (Nahuel, 6/11/2026): la app hace **todo lo del panel web** (`crm-inmobiliaria`, rama `corredor`, `web/`), con
la misma API (`api/`). Después se clona a Android idéntica (`grupovimo/corredor-android`) con el molde de Tengo Libre
(`tengolibre/apps/android/GUIA-CLON-IOS.md`). Nada se publica en las tiendas hasta tener Android.

## Cómo se compila
- Sólo en GitHub (`.github/workflows/ios.yml`, macos-15-intel). Nunca en la Mac ni en el simulador.
- Push a `main` con la cuenta `grupovimo`. Una compilación en verde dispara `testflight` y `testflight-ultima` (la
  suma a todos los grupos y vence las viejas).
- Si falla al compilar: artefacto `compilar-log`. Si fallan las pruebas: artefacto `probar` (`probar.log` y
  `probar.xcresult`). Cada prueba se corta a los 4 min (`-default-test-execution-time-allowance 240`).
- `PantallasTests` monta cada pantalla en claro y oscuro; `testNavegacionTotal` abre cada destino navegable y
  falla si alguno muestra el placeholder de SwiftUI (cuenta con `PantallasMostradas`, que suma `FondoApp`: toda
  pantalla apilada lleva `.pantallaApilada` o `FondoApp`).

## Hecho (6–7/11)
- **Auditoría web ↔ iOS** con 4 agentes (~370 faltas, ~310 parciales, 63 flujos enteros, ~35 bugs contra la API).
- **Tanda 1:** los bugs contra la API.
- **Tanda 2:** todo el panel (~31 mil líneas): propiedades y MIRA, mensajes, WhatsApp y Mercado Libre, agenda,
  avisos e insignias, cobranzas, contratos (alta con lectura del PDF, renovar, borradores), rendiciones,
  inventarios (recorrida, actas con firmas y links, devolución con «¿quién paga?»), consorcios entero, Más
  (equipo, licencias, integraciones, IA conectadas, web, difusión, emprendimientos, temporada, reservas,
  importar, papelera, actividad, plan), ingreso (contraseña, recuperar acceso, invitaciones), bienvenida.
- **Integración:** aviso con acción y «Deshacer» a la vez (el cobro ofrece «Mandar recibo»), errores por campo de
  la API en `ErrorApi.campos` (el alta de contrato vuelve al paso del campo), tope de subida por uso, rutas de
  todos los avisos del panel (`Ruta(texto:)`), código muerto afuera.
- **7/11, con respuesta de Nahuel:**
  - «Tomá una consulta sin dueño» abre Contactos con `?agente=libre` (también en la web, que no filtraba).
  - «Dictá la recorrida» arma los ítems: la API (`POST /v1/propiedades/{id}/grabaciones` con `armar: true`) los
    arma con la IA de MIRA (tope 40 por día) o por reglas (`api/internal/dominio/inventario/armar.go`).
- Endpoints: todo lo que usa la web lo usa la app, salvo lo propio de plataforma (abajo).

## Distinto a propósito
- Suscripción con Apple (`/v1/suscripcion/apple`), no Mercado Pago. Push por APNs, no web push.
- Lo que en la web es de escritorio tiene su equivalente táctil: atajos de teclado → menú «⋯» o botón; arrastrar
  archivos → elegir de Archivos o Fotos; arrastrar en el calendario → tocar un día libre; vistas lado a lado → una
  pantalla por vez.
- «Pausar» una publicación se llama «Despublicar».

## Sin probar en un teléfono
Nunca corrió en un aparato real fuera de TestFlight: Nahuel la revisa a mano ahí (las capturas de iOS del CI no se
comparan).

## Falta
1. Revisión de Nahuel en TestFlight.
2. El clon a Android en `grupovimo/corredor-android` (`~/Trabajo/vimo/corredor-android`), un `.kt` por `.swift`,
   con FCM en la API (`/opt/corredor/claves/fcm.json`, pg_dump antes).
