# Arq LF

App para iPhone con LiDAR (Swift + SwiftUI) para arquitectura e interiores: escanea cuartos, saca planos con medidas, captura modelos 3D y mide en realidad aumentada.

## Funciones

- **Escanear cuarto (RoomPlan):** detecta muros, puertas, ventanas, vanos y muebles con medidas reales.
  - Modelo 3D (USDZ) con visor orbital y opción de **Ver en AR**.
  - Plano de planta 2D con cotas de cada muro, puertas, ventanas, muebles y barra de escala. Se puede acercar y mover.
  - Datos: área de piso, perímetro, altura promedio, volumen, área de muros sin huecos (útil para pintura) y medidas de cada elemento.
  - Exporta el plano en **PDF** (tamaño carta), **PNG** y **DXF**, además de **CSV**, **USDZ** y **JSON**.
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

## Fase 2

- **Malla con color real:** durante el escaneo 3D se guardan hasta 160 fotos (cada vez que el iPhone se mueve o gira lo suficiente). Al guardar, cada vértice toma el color de la foto que lo vio más de cerca y de frente, usando la profundidad del LiDAR para no pintar lo que estaba tapado. Se exporta como **PLY** (con color, para MeshLab, Blender y CloudCompare), **OBJ** con color por vértice y **USDZ**.
- **Varios cuartos:** después de terminar un cuarto, *Otro* escanea el siguiente con las mismas coordenadas y al guardar RoomPlan los une en un solo modelo y un solo plano.
- **DXF:** el plano se exporta para AutoCAD y otros programas CAD, en metros, con capas MUROS, PUERTAS, VENTANAS, VANOS, MUEBLES, PISO y COTAS.

## Fase 3: textura fotográfica

- Fotos de hasta 2560 px tomadas solo con el iPhone casi quieto (sin desenfoque de movimiento), en alta resolución cuando el iPhone lo permite.
- **3.1:** exposición y balance de blancos fijos durante el escaneo (se puede desactivar en Ajustes), ganancia RGB por foto para igualar tonos, elección de foto por zonas con un modelo de Potts (parches grandes, menos costuras) que además prefiere las fotos más nítidas, y limpieza de la malla (soldar piezas, quitar fragmentos sueltos y rellenar huecos pequeños).
- Exporta OBJ + MTL + fotos en .zip y USDZ con textura.
- **3.2:** atlas de textura (hasta 3 imágenes de 4096 px en lugar de una foto por parche), fundido de costuras (cada parche se corrige suavemente hacia el color promedio en sus uniones), segunda pasada para orillas vistas de lado, color propagado de los vecinos en las zonas que ninguna foto vio y relleno de rendijas largas y delgadas.
- **3.3:** cada triángulo exige que sus 3 esquinas sean visibles en la foto y evita las fotos donde cae sobre un borde de profundidad (sin "embarrar" el fondo en las orillas), triángulos orientados según sus normales y dibujados por una sola cara (las láminas delgadas ya no muestran la textura en espejo por detrás), contorno de la malla sin dientes y suavizado, y guía de cobertura en vivo (verde = con foto, naranja = falta foto).
- **3.4:** se quitan las láminas sueltas y delgadas que deja ARKit (las "tiras de papel" flotantes) con una apertura morfológica sobre los triángulos, y el visor usa un fondo gris neutro para que las zonas sin escanear no se vean como agujeros negros.
- **3.5:** consistencia entre fotos (si 3 o más fotos ven una zona, se descartan las que ven un color muy distinto a la mediana: patas delgadas, personas que pasan), densidad de textura uniforme (todas las zonas reciben los mismos píxeles por metro, hasta 4 atlas de 4096 px) y filtro de láminas sueltas a 3 anillos.

## Fase 4: Fotos a 3D

- Se eligen de 10 a 300 fotos de la galería (mejor entre 20 y 200) y el iPhone arma un modelo USDZ texturizado con Object Capture de Apple (`PhotogrammetrySession`), sin Mac ni internet.
- Opción para recortar solo el objeto (quita el fondo) o conservar todo (rincones, fachadas).
- La escala es aproximada porque las fotos de la galería no traen la profundidad del LiDAR.

## IA en el escaneo 3D

- **Paredes, piso y techo planos:** ARKit clasifica cada cara de la malla con su modelo en el iPhone (pared, piso, techo, mesa, asiento, ventana, puerta). Cada región plana grande de pared, piso o techo se ajusta a un plano (vertical u horizontal) y sus vértices cercanos (hasta 8 cm) se proyectan sobre él; en las uniones los vértices quedan sobre ambos planos, así esquinas y bordes salen rectos.
- **Sin personas:** la segmentación de personas de Apple (Vision) marca a la gente en cada foto y esas zonas nunca se usan para la textura, los colores ni la igualación de exposición.
- **Sin rendijas:** después de enderezar los planos, las orillas abiertas que quedan a menos de 2.5 cm de otra orilla (piezas de ARKit que no se tocaban) se cosen como un cierre y se rellenan los huecos chicos que quedan; los triángulos que el enderezado volteó o aplastó regresan a su posición original.
- **Sin manchas sin foto:** las zonas que ninguna foto vio bien y que cuelgan de la orilla del escaneo (tus pies y piernas al escanear, cosas vistas solo de lado) y las piezas sueltas sin foto se quitan antes de texturizar; los huecos sin foto rodeados de textura se conservan y toman el color de sus vecinos.

## Espacios grandes (iglesias, naves, bodegas)

- **Escaneo por secciones:** cada escaneo 3D guarda el mapa de ubicación de ARKit. Desde el proyecto, *⋯ → Agregar sección* abre la cámara; regresa a una zona ya escaneada y apunta despacio hasta que diga "Ubicado". Lo anterior se ve en gris y la sección nueva queda en las mismas coordenadas.
- Cada sección tiene sus propias fotos (hasta 160) y su propio atlas de textura, así la textura queda nítida aunque el espacio sea enorme. Lo que la sección nueva vuelve a escanear de las anteriores se quita para no duplicar superficies.
- El visor muestra todas las secciones juntas, y *Ver en AR* y la exportación incluyen el modelo completo (**USDZ** y **PLY**) además de cada sección por separado.
- **Atlas adaptable:** hasta 4 imágenes de 4096 px para zonas de hasta 60 m², 6 hasta 150 m² y 8 para zonas más grandes.
- El LiDAR alcanza unos 5 m: bóvedas y cúpulas altas quedan fuera del escaneo.
