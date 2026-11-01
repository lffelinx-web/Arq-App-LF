# Arq LF

App para iPhone con LiDAR (Swift + SwiftUI) para arquitectura e interiores: escanea cuartos, saca planos con medidas, captura modelos 3D y mide en realidad aumentada.

## Funciones

- **Escanear cuarto (RoomPlan):** detecta muros, puertas, ventanas, vanos y muebles con medidas reales.
  - Modelo 3D (USDZ) con visor orbital y opción de **Ver en AR**.
  - Plano de planta 2D con cotas de cada muro, puertas, ventanas, muebles y barra de escala. Se puede acercar y mover.
  - Datos: área de piso, perímetro, altura promedio, volumen, área de muros sin huecos (útil para pintura) y medidas de cada elemento.
  - Exporta el plano en **PDF** (tamaño carta) y **PNG**, además de **CSV**, **USDZ** y **JSON**.
- **Escaneo 3D (malla LiDAR):** reconstruye cualquier espacio u objeto como malla de triángulos. Exporta **OBJ** (SketchUp, Blender, Revit, Rhino…) y **USDZ**.
- **Medir:** cinta métrica en AR punto a punto con la mira al centro, apoyada en la profundidad del LiDAR. Guarda las medidas con foto y las exporta a CSV.
- Unidades en metros, centímetros o pies y pulgadas.
- Los proyectos se guardan en *Archivos → En mi iPhone → Arq LF → Proyectos*.

## Estructura

- `App/Sources/Core`: modelos y lógica pura (geometría, plano, OBJ, CSV, almacenamiento), cubiertos por las pruebas de `Tests/`.
- `App/Sources/Captura`: RoomPlan, malla LiDAR (ARKit) y medición.
- `App/Sources/UI`: pantallas SwiftUI.

## Compilación

Igual que en los otros proyectos: XcodeGen y GitHub Actions sobre macOS, sin necesidad de una Mac propia.

- **Cualquier rama:** ejecuta las pruebas unitarias en el simulador y genera un IPA sin firmar, que se descarga como artefacto desde la pestaña *Actions*.
- **`main`:** además firma la app con fastlane `match` (certificado guardado en la rama `certificados`) y la sube a TestFlight.

### Para activar TestFlight

1. En [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) registra el identificador **`com.lfaz.arq`**.
2. En [App Store Connect](https://appstoreconnect.apple.com/apps) crea la app con ese identificador.
3. En *Settings → Secrets and variables → Actions* del repositorio añade los mismos secrets que en los otros proyectos: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` y `APPLE_TEAM_ID`.

Mientras falten los secrets, la subida a TestFlight se omite y el resto de la compilación sigue funcionando.
