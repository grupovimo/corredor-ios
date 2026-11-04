# Corredor para iPhone

App nativa (SwiftUI, iOS 17+) de [Corredor](https://corredor.com.ar). El proyecto de Xcode sale de
`project.yml` con `xcodegen generate`; no se compila en la Mac: lo compila y lo prueba GitHub Actions
(`ios.yml`) y lo sube a TestFlight `testflight.yml` (`gh workflow run testflight`).

- Diseño: `docs/handoff/design_handoff_corredor_iphone` (56 pantallas, claro y oscuro).
- API: `api.corredor.com.ar` (repo crm-inmobiliaria, rama `corredor`). Sesión por `Bearer`.
- Cada área vive en `Corredor/Pantallas/<Área>/` y registra sus destinos (`Nucleo/Destinos.swift`).
