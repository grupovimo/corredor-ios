# Handoff: Corredor para iPhone (SwiftUI, iOS 17+)

## Overview
App nativa de Corredor para iPhone. La usa sobre todo el agente en la calle, con una mano y a veces sin señal; la dueña la usa para ver el día y aprobar. Responde en orden: qué hago ahora, contestar rápido (WhatsApp, Mercado Libre, web), captar con MIRA y cobrar con recibo. Lo pesado (configuración, consorcios, editor de la web, informes) queda en la web y la app lleva un link.

## About the design files
Los `.dc.html` son **referencias de diseño en HTML**, no código para copiar. La tarea es **recrearlos en SwiftUI** con componentes nativos (TabView, NavigationStack, .sheet con detents, .swipeActions, .contextMenu, .searchable, ActivityKit, WidgetKit, App Intents). Se abren en el navegador con `support.js` e `image-slot.js` en la misma carpeta.

- `Corredor-09-App-iOS.dc.html`: lienzo con prototipo clickeable (6 flujos, claro/oscuro, estados), las 56 pantallas en claro y oscuro, tokens SwiftUI, ícono, lanzamiento, capturas App Store y accesibilidad.
- `CorredorIOS.dc.html`: la app en un solo componente. Props: `pantalla` (clave del mapa), `oscuro` (bool), `estado` (normal · vacio · cargando · error · offline · permiso · persona · ilegible). Los textos y datos exactos de cada pantalla están en su `renderVals()`.

## Fidelity
**Alta fidelidad.** Colores, tipografía, radios, sombras, copy y microinteracciones son finales, a 393 × 852 pt (iPhone 16). Los montos, índices y nombres son datos de ejemplo (Luna Propiedades, jueves 12 de noviembre).

## Detalle

Archivos: `Corredor-09-App-iOS.dc.html` (lienzo: prototipo, todas las pantallas en claro y oscuro, tokens SwiftUI, ícono, lanzamiento, capturas App Store, accesibilidad) y `CorredorIOS.dc.html` (la app: un solo componente con props `pantalla`, `oscuro`, `estado`). Diseño a 393 × 852 pt (iPhone 16).

Es una app **nativa**, no la web achicada. Lo pesado (configuración, consorcios, editor de la web, informes) queda en la web; la app lleva un link.

### Navegación
- `TabView` con 5 destinos: Inicio · Propiedades · **MIRA** (centro, botón oro elevado que abre la cámara a pantalla completa) · Mensajes · Agenda.
- Contactos, Operaciones, Cobranzas, Actas, Avisos y Perfil: `NavigationStack` desde Inicio y Perfil.
- Títulos grandes (`.navigationBarTitleDisplayMode(.large)`), `.searchable` global, `.sheet` con `.presentationDetents([.medium, .large])` para acciones cortas, `.swipeActions`, `.contextMenu`, `.refreshable`.

### Mapa de pantallas
| Código | Pantalla | `pantalla=` | Vista SwiftUI sugerida |
|---|---|---|---|
| 1A–1D | Bienvenida, Sign in with Apple, elegir inmobiliaria, Face ID | entrada, apple, inmo, faceid | `EntradaView`, `ASAuthorizationAppleIDButton`, `InmobiliariaPicker`, `LocalAuthentication` |
| 2A–2C | Inicio agente, Inicio dueña, búsqueda global | inicio, inicio-duena, buscar | `HoyView`, `HoyDuenaView`, `.searchable` |
| 3A–3F | Cartera, deslizar, mapa, ficha, galería, compartir | propiedades(-swipe/-mapa), ficha, galeria, ficha-compartir | `CarteraView` + MapKit, `FichaView`, `ShareLink` |
| 4A | Alta rápida | alta | `AltaView` + `PhotosPicker`, Speech |
| 5A–5I | MIRA: cámara, leyendo, revisión, captada, sin señal, persona, ilegible, sin permiso, captadas | mira, mira-leyendo, mira-revision, mira-listo, mira-sinsenal, mira-persona, mira-ilegible, mira (estado permiso), mira-cola | AVFoundation + Gemini; cola offline |
| 6A–6D | Bandeja, WhatsApp, fuera de 24 h, Mercado Libre | mensajes, chat, chat-24h, ml | `BandejaView`, `ChatView` |
| 7A–7C | Agenda día, semana, nueva visita | agenda, agenda-semana, agenda-nueva | `AgendaView`, sheet |
| 8A–8B | Contactos, ficha | contactos, contacto | |
| 9A–9C | Tablero, menú contextual, ficha de operación | operaciones, operaciones-menu, operacion | |
| 10A–10D | Por cobrar, deslizar, registrar pago, recibo | cobranzas, cobranzas-swipe, cobro-sheet, recibo | |
| 11A–11C | Recorrida de inventario, firmas | inventario, firma, firma-lista | PencilKit para la firma |
| 12A–12B | Avisos, configuración | notificaciones, avisos-config | |
| 13A | Perfil (incluye borrar la cuenta) | perfil | |
| 14A–14H | Pantalla bloqueada con Live Activity, aviso expandido, responder desde el aviso, isla expandida, widgets e isla compacta, menú del ícono, Spotlight, Atajos | lock, lock-acciones, lock-respuesta, isla, home, home-menu, spotlight, atajos | ActivityKit, WidgetKit, `UNNotificationCategory` con `UNTextInputNotificationAction`, App Intents, `UIApplicationShortcutItem` |
| E1–E5 | Vacío, cargando, error, sin conexión, sin permiso | prop `estado` | |

### Tokens → SwiftUI
Colores en Asset Catalog con par Any/Dark (tabla completa en la sección «Tokens SwiftUI» del lienzo). En oscuro, **Accion** = oro `#f2bb57` y **SobreAccion** = `#1a1405`.
Tipografía: Geist con `Font.custom(_, size:, relativeTo:)`: 34/800 .largeTitle · 28/700 .title · 20/700 .title3 · 17/600 .headline · 17/400 .body · 15/600 .subheadline · 13 .footnote · 12/700 .caption · 10/600 .caption2.
Radios continuos: 12 controles · 18 tarjetas · 22 destacadas · 30 hojas · Capsule chips.
Sombras teñidas de verde (`#0f3530`): e1 r2 y1 7 % · e2 r11 y10 32 % · e3 r20 y22 80 %.
Grano: imagen en mosaico, `.blendMode(.multiply)` en claro / opacidad .55 en oscuro.

### Comportamiento
- **Deshacer en vez de confirmar**: cobrar, mover operación, aprobar, pausar; aviso inferior con «Deshacer» 5 s.
- **Hápticos**: `.sensoryFeedback(.success)` al cobrar y al terminar MIRA; `.impact(.medium)` al mover una operación.
- **Sin conexión**: todo lo cargado entra en una cola con estado visible («2 cambios en cola», «En cola · se lee cuando vuelva la señal») y se sube solo.
- **MIRA**: pedir «Fotografiá sólo el cartel, sin personas»; si detecta una persona no lee; la revisión marca «Revisá» en los campos dudosos; siempre queda como borrador.
- **WhatsApp 24 h**: fuera de la ventana sólo plantillas aprobadas.
- **Mercado Libre**: sin teléfonos ni mails en la respuesta.
- **Accesibilidad**: Dynamic Type hasta AX5 (las filas pasan a vertical), VoiceOver con etiquetas en todos los botones de ícono, 44 pt mínimo, nada sólo por color.

### Ícono y App Store
- Ícono 1024: `assets/corredor-rr-final.png` (claro), `corredor-rr-oro.png` sobre negro (oscuro), `corredor-rr-papel.png` en grises (teñido). Pedir vectores para exportar limpio.
- Lanzamiento: verde `#0f3530` con la rr en oro, sin texto.
- Capturas: 6,9" 1320 × 2868 y 6,5" 1242 × 2688, 5 capturas cada una (ver lienzo).

## Assets
- `assets/corredor-rr-final.png`: ícono de app (claro). `corredor-rr-oro.png`: ícono oscuro y pantalla de lanzamiento. `corredor-rr-papel.png`: base del ícono teñido.
- `assets/corredor-rr-simbolo.png`: rr suelta (marca de agua, sello). `patron-rr.png`, `forma-verde.png`: fondos de entrada, bloqueo y widgets.
- `assets/grano.svg` / `grano-claro.svg`: textura en mosaico.
- ⚠ Los PNG de logo son recortes de los tableros: pedir los vectores para el Asset Catalog.
- Logos de integraciones: `https://corredor.com.ar/logos/{whatsapp.svg,mercadolibre.svg,zonaprop.png,argenprop.png,google.svg,apple.svg}`.
- Fotos: de marca (`https://corredor.com.ar/marca/*.jpg`) y de Unsplash (licencia libre) como ejemplo; en la app vienen de la cartera.
- Íconos: Material Symbols Rounded en el diseño → en producción usar **SF Symbols** equivalentes (house, building.2, bubble.left.and.bubble.right, calendar, dollarsign.circle, viewfinder para MIRA).
- Fuente: Geist (OFL) registrada en Info.plist (`UIAppFonts`).

## Copy
Voseo («Creá», «Tocá», «Mantené apretado»). Montos `USD 172.000` / `ARS 540.000`. Fechas «jueves 12 de noviembre». Nunca «Próximamente». MIRA siempre pide «Fotografiá sólo el cartel, sin personas» y recuerda revisar antes del alta.

## Pendiente
- Vectores del logo para el ícono.
- Copy legal de la hoja de borrar cuenta (usar el de corredor.com.ar/terminos).
- Lista final de plantillas aprobadas de WhatsApp.

## Files
`Corredor-09-App-iOS.dc.html`, `CorredorIOS.dc.html`, `support.js`, `image-slot.js`, `assets/`.
