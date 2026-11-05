# Cómo se trabaja en Corredor para iPhone

La app tiene que hacer **todo lo que hace el panel web** (corredor.com.ar), nativo, sin mandar a la web:
Nahuel lo pidió «100 % fiel en features, que no le falte nada». El handoff dice que configuración,
consorcios, editor e informes «quedan en la web»: eso **no** vale, también van nativos.

## Reglas

- **Fiel al handoff.** `docs/handoff/design_handoff_corredor_iphone/CorredorIOS.dc.html` tiene el
  markup de cada pantalla (`<sc-if value="{{ s.<pantalla> }}">`), los datos de ejemplo en `renderVals()`
  y los encabezados en `HH`. Copiá estructura, medidas, colores, radios, copy y estados. Lo que el
  handoff no dibuja se arma **con piezas que ya existen** (filas, tarjetas, hojas, chips), nunca con
  diseño nuevo. Los íconos de Material Symbols van como su equivalente de SF Symbols.
- **Sin renglones viudos** en textos largos: `Formato.sinViudas(_:)`.
- **Copy:** voseo, montos `USD 172.000` / `ARS 540.000`, fechas «jueves 12 de noviembre». Nunca
  «Próximamente».
- **Deshacer en vez de confirmar** (cobrar, mover, aprobar, pausar, borrar): `estado.avisar("…", deshacer: { … })`.
  Hápticos: `.sensoryFeedback(.success, …)` al cobrar y al terminar MIRA; `Haptico.impacto()` al mover.
- **Sin conexión:** toda alta o cambio que la persona hace en la calle va por
  `estado.cola.enviar(metodo, ruta, cuerpo, etiqueta:)`; si no hay señal queda en cola y se ve.
- **Nunca vacío:** cada lista tiene su vacío con una acción clara (`EstadoVacio`), su esqueleto al
  cargar (`EsqueletoFilas`), su error con reintento (`EstadoError`) y sin permiso para el lector.
- **Accesibilidad:** Dynamic Type hasta AX5 (las filas pasan a vertical con `ViewThatFits` o
  `dynamicTypeSize`), etiqueta en cada botón de ícono, 44 pt mínimo, nada sólo por color.
- **En vivo:** la app escucha `GET /v1/eventos` (SSE, `App/Vivo.swift`) con la app adelante; cada cambio
  sube `estado.version`. Toda pantalla que muestra datos carga con `.task(id: estado.version)`, no con
  `.task {}` (salvo formularios y editores, para no pisar lo que se está escribiendo). Si la tabla no
  avisa, sumala al trigger `app.avisar_cambio` en una migración de la API (ver 00167).
- **Nada de `async let`** en cargas de pantalla: cerró la app en Release en Tu Local Web. Awaits uno
  detrás del otro o `TaskGroup`.
- **Nunca se compila en la Mac** (ni xcodebuild ni simulador). Se compila en GitHub: hacé push de tu
  rama y mirá `gh run list -R grupovimo/corredor-ios --branch <rama>` / `gh run view <id> --log-failed`.
  El repo es de la cuenta `grupovimo`: `export GH_TOKEN=$(gh auth token -u grupovimo)` y push con
  `git -c credential.helper= -c credential.helper='!f(){ echo username=x-access-token; echo "password=$GH_TOKEN"; }; f' push`.

## Dónde va cada cosa

- `Corredor/Pantallas/<Área>/`: las pantallas de tu área. **Sólo tocás tu carpeta** y tus archivos de
  modelos (`Corredor/Pantallas/<Área>/Modelos.swift`). Si necesitás algo común (una pieza del tema,
  un destino nuevo en `Nucleo/Destinos.swift`), sumalo en un commit chico aparte y decilo en tu reporte.
- `Nucleo/Destinos.swift`: los destinos (`AFichaPropiedad`, `AChat`…). Cada área registra los suyos en
  su `.destinos<Área>()`; para abrir la ficha de otra área: `estado.abrir(AFichaContacto(id:))` o un
  `NavigationLink(value:)`.
- `App/Estado.swift`: sesión, rol (`estado.esDuenio`, `estado.escribe`), `api`, `cola`, `avisar`,
  `ir(Ruta)`, `version` (subila después de un cambio para que las listas se refresquen).
- `Tema/`: tokens (`C.*`, `Estilo.*`, `M.*`, `.tarjeta()`, `.sombraE2()`), piezas y estados.

## La API

`~/Trabajo/vimo/.wt/corredor/api` (rama `corredor` de crm-inmobiliaria). Las rutas están en cada
`internal/dominio/<x>/*.go` (`mux.HandleFunc("GET /v1/…")`). El panel web
(`~/Trabajo/vimo/.wt/corredor/web/src/routes/panel/(app)/`) muestra qué usa cada pantalla y cómo: es la
referencia de qué features tiene que tener la app. No toques la API: si falta un endpoint, anotalo en
tu reporte.
