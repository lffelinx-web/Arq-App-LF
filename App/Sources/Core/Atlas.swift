import Foundation
import simd

/// RGBA image in memory, row 0 at the top.
struct ImagenRGBA: Equatable {
    var ancho: Int
    var alto: Int
    var pixeles: [UInt8]

    init(ancho: Int, alto: Int) {
        self.ancho = ancho
        self.alto = alto
        pixeles = [UInt8](repeating: 0, count: ancho * alto * 4)
    }

    init(ancho: Int, alto: Int, pixeles: [UInt8]) {
        self.ancho = ancho
        self.alto = alto
        self.pixeles = pixeles
    }

    /// Bilinear sample at pixel coordinates, clamped to the edges.
    func muestra(_ x: Float, _ y: Float) -> SIMD3<Float> {
        let cx = min(max(x, 0), Float(ancho - 1)), cy = min(max(y, 0), Float(alto - 1))
        let x0 = Int(cx), y0 = Int(cy)
        let x1 = min(x0 + 1, ancho - 1), y1 = min(y0 + 1, alto - 1)
        let fx = cx - Float(x0), fy = cy - Float(y0)
        func p(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let i = (y * ancho + x) * 4
            return SIMD3(Float(pixeles[i]), Float(pixeles[i + 1]), Float(pixeles[i + 2]))
        }
        let arriba = p(x0, y0) * (1 - fx) + p(x1, y0) * fx
        let abajo = p(x0, y1) * (1 - fx) + p(x1, y1) * fx
        return arriba * (1 - fy) + abajo * fy
    }

    func color(_ x: Int, _ y: Int) -> SIMD3<Float> {
        let i = (y * ancho + x) * 4
        return SIMD3(Float(pixeles[i]), Float(pixeles[i + 1]), Float(pixeles[i + 2]))
    }

    func ocupado(_ x: Int, _ y: Int) -> Bool { pixeles[(y * ancho + x) * 4 + 3] > 0 }

    mutating func poner(_ x: Int, _ y: Int, _ c: SIMD3<Float>) {
        let i = (y * ancho + x) * 4
        pixeles[i] = UInt8(clamping: Int(c.x.rounded()))
        pixeles[i + 1] = UInt8(clamping: Int(c.y.rounded()))
        pixeles[i + 2] = UInt8(clamping: Int(c.z.rounded()))
        pixeles[i + 3] = 255
    }

    /// Grows the painted areas a few pixels into the empty ones, so texture
    /// filtering at a patch's edge never picks up the empty background.
    mutating func dilatar(pasadas: Int) {
        let w = ancho, h = alto
        for _ in 0..<pasadas {
            let antes = pixeles
            var cambios = 0
            antes.withUnsafeBufferPointer { a in
                pixeles.withUnsafeMutableBufferPointer { p in
                    for y in 0..<h {
                        for x in 0..<w {
                            let i = (y * w + x) * 4
                            guard a[i + 3] == 0 else { continue }
                            var r = 0, g = 0, b = 0, n = 0
                            if x > 0, a[i - 1] > 0 { r += Int(a[i - 4]); g += Int(a[i - 3]); b += Int(a[i - 2]); n += 1 }
                            if x < w - 1, a[i + 7] > 0 { r += Int(a[i + 4]); g += Int(a[i + 5]); b += Int(a[i + 6]); n += 1 }
                            let arriba = i - w * 4, abajo = i + w * 4
                            if y > 0, a[arriba + 3] > 0 { r += Int(a[arriba]); g += Int(a[arriba + 1]); b += Int(a[arriba + 2]); n += 1 }
                            if y < h - 1, a[abajo + 3] > 0 { r += Int(a[abajo]); g += Int(a[abajo + 1]); b += Int(a[abajo + 2]); n += 1 }
                            guard n > 0 else { continue }
                            p[i] = UInt8(r / n); p[i + 1] = UInt8(g / n); p[i + 2] = UInt8(b / n); p[i + 3] = 255
                            cambios += 1
                        }
                    }
                }
            }
            if cambios == 0 { break }
        }
    }
}

/// Packs the photo patches into a few large texture images (an atlas) and
/// blends the seams between patches.
///
/// Each patch is a connected group of triangles textured from the same photo.
/// Along the seams, every patch is shifted toward the average colour the
/// neighbouring photos see there, and that shift fades smoothly into the patch
/// ("seam leveling", as in Waechter et al., "Let there be color!"). Triangles
/// no photo saw are painted with the mesh's vertex colours instead of grey.
enum Atlas {
    /// One triangle to draw into the atlas.
    struct Tarea: Equatable {
        var atlas: Int32
        /// Photo to copy from, or -1 to paint the vertex colours.
        var foto: Int32
        /// Corners in atlas pixels.
        var destino: [SIMD2<Float>]
        /// Corners in the full-size photo's pixels (unused for vertex colours).
        var origen: [SIMD2<Float>]
        /// Per corner: colour offset added to the photo, or the vertex colour.
        var colores: [SIMD3<Float>]
    }

    struct Plan {
        var lado: Int
        var numeroAtlas: Int
        /// Mesh with UVs pointing into the atlas; groups are atlas indices.
        var malla: MallaTexturizada
        /// Sorted by atlas, then photo.
        var tareas: [Tarea]
        /// Photo gains, applied when copying.
        var ganancias: [SIMD3<Float>]
    }

    /// Triangles that share an edge and the same photo.
    static func parches(_ malla: PiezaMalla, etiquetas: [Int32]) -> [[Int]] {
        let vecinos = Texturizar.vecindad(malla)
        var visitado = [Bool](repeating: false, count: malla.triangulos)
        var resultado: [[Int]] = []
        for t in 0..<malla.triangulos where etiquetas[t] >= 0 && !visitado[t] {
            var parche: [Int] = []
            var pila = [t]
            visitado[t] = true
            while let actual = pila.popLast() {
                parche.append(actual)
                for v in vecinos[actual] where !visitado[Int(v)] && etiquetas[Int(v)] == etiquetas[t] {
                    visitado[Int(v)] = true
                    pila.append(Int(v))
                }
            }
            resultado.append(parche)
        }
        return resultado
    }

    /// Shelf packing: rectangles sorted by height, placed left to right in rows.
    /// Returns (atlas, x, y) for each rectangle, or nil if it needs more than `maximoAtlas`.
    static func empaquetar(_ tamanos: [SIMD2<Int>], lado: Int, maximoAtlas: Int) -> [(atlas: Int, x: Int, y: Int)]? {
        let orden = tamanos.indices.sorted { tamanos[$0].y > tamanos[$1].y }
        var resultado = [(atlas: Int, x: Int, y: Int)](repeating: (0, 0, 0), count: tamanos.count)
        var atlas = 0, x = 0, y = 0, altoFila = 0
        for i in orden {
            let t = tamanos[i]
            guard t.x <= lado, t.y <= lado else { return nil }
            if x + t.x > lado {
                y += altoFila
                x = 0
                altoFila = 0
            }
            if y + t.y > lado {
                atlas += 1
                x = 0
                y = 0
                altoFila = 0
            }
            guard atlas < maximoAtlas else { return nil }
            resultado[i] = (atlas, x, y)
            x += t.x
            altoFila = max(altoFila, t.y)
        }
        return resultado
    }

    /// Lays out the atlas and computes the seam corrections.
    /// - Parameters:
    ///   - uvFoto: six values per triangle, its corners' UVs on its photo (0...1).
    ///   - fotogramas: the scan photos (their small copy and gain give the seam colours).
    ///   - tamanos: pixel size of each photo's full-resolution file.
    static func planificar(
        _ malla: PiezaMalla, etiquetas: [Int32], uvFoto: [Float], fotogramas: [Fotograma],
        tamanos: [SIMD2<Int>], lado: Int = 4096, maximoAtlas: Int = 3
    ) -> Plan {
        let margen = 2
        let celda = 8
        let lista = parches(malla, etiquetas: etiquetas)

        // Patch rectangles in photo pixels.
        var rectangulos: [(minimo: SIMD2<Float>, maximo: SIMD2<Float>)] = []
        for parche in lista {
            let foto = Int(etiquetas[parche[0]])
            let tam = SIMD2<Float>(Float(tamanos[foto].x), Float(tamanos[foto].y))
            var minimo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), maximo = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
            for t in parche {
                for k in 0..<3 {
                    let p = SIMD2(uvFoto[t * 6 + k * 2], uvFoto[t * 6 + k * 2 + 1]) * tam
                    minimo = simd_min(minimo, p)
                    maximo = simd_max(maximo, p)
                }
            }
            rectangulos.append((minimo, maximo))
        }
        let sinFoto = (0..<malla.triangulos).filter { etiquetas[$0] < 0 }

        // Scale so everything fits; shrink further if packing still overflows.
        let areaTotal = rectangulos.reduce(Float(0)) { s, r in s + (r.maximo.x - r.minimo.x + 1) * (r.maximo.y - r.minimo.y + 1) }
        let areaCeldas = Float(sinFoto.count * (celda + margen * 2) * (celda + margen * 2))
        let capacidad = Float(maximoAtlas * lado * lado) * 0.8 - areaCeldas
        let mayor = rectangulos.reduce(Float(1)) { max($0, $1.maximo.x - $1.minimo.x, $1.maximo.y - $1.minimo.y) }
        var escala = min(1, (max(capacidad, 1) / max(areaTotal, 1)).squareRoot(), Float(lado - 2 * margen - 2) / mayor)
        var ubicaciones: [(atlas: Int, x: Int, y: Int)] = []
        var tamanosPaquete: [SIMD2<Int>] = []
        for _ in 0..<30 {
            tamanosPaquete = rectangulos.map { r in
                SIMD2(Int(((r.maximo.x - r.minimo.x) * escala).rounded(.up)) + 1 + 2 * margen,
                      Int(((r.maximo.y - r.minimo.y) * escala).rounded(.up)) + 1 + 2 * margen)
            } + Array(repeating: SIMD2(celda + 2 * margen, celda + 2 * margen), count: sinFoto.count)
            if let u = empaquetar(tamanosPaquete, lado: lado, maximoAtlas: maximoAtlas) {
                ubicaciones = u
                break
            }
            escala *= 0.85
        }
        if ubicaciones.isEmpty {
            // Too many untextured triangles to pack: they share one cell.
            ubicaciones = Array(repeating: (atlas: 0, x: 0, y: 0), count: tamanosPaquete.count)
        }

        let desplazamientos = nivelarCosturas(malla, etiquetas: etiquetas, uvFoto: uvFoto, fotogramas: fotogramas)

        var tareas: [Tarea] = []
        tareas.reserveCapacity(malla.triangulos)
        for (n, parche) in lista.enumerated() {
            let foto = etiquetas[parche[0]]
            let tam = SIMD2<Float>(Float(tamanos[Int(foto)].x), Float(tamanos[Int(foto)].y))
            let u = ubicaciones[n]
            let base = SIMD2<Float>(Float(u.x + margen), Float(u.y + margen))
            for t in parche {
                var destino: [SIMD2<Float>] = [], origen: [SIMD2<Float>] = [], colores: [SIMD3<Float>] = []
                for k in 0..<3 {
                    let p = SIMD2(uvFoto[t * 6 + k * 2], uvFoto[t * 6 + k * 2 + 1]) * tam
                    origen.append(p)
                    destino.append(base + (p - rectangulos[n].minimo) * escala + 0.5)
                    let v = malla.indices[t * 3 + k]
                    colores.append(desplazamientos[clave(v, foto)] ?? .zero)
                }
                tareas.append(Tarea(atlas: Int32(u.atlas), foto: foto, destino: destino, origen: origen, colores: colores))
            }
        }
        for (n, t) in sinFoto.enumerated() {
            let u = ubicaciones[min(lista.count + n, ubicaciones.count - 1)]
            let base = SIMD2<Float>(Float(u.x + margen), Float(u.y + margen))
            let destino = [base + SIMD2(0.5, 0.5), base + SIMD2(Float(celda) - 0.5, 0.5), base + SIMD2(0.5, Float(celda) - 0.5)]
            let colores = (0..<3).map { k -> SIMD3<Float> in
                let i = Int(malla.indices[t * 3 + k])
                guard malla.conColor else { return SIMD3(repeating: 170) }
                let c = malla.colores[i]
                return SIMD3(Float(c.0), Float(c.1), Float(c.2))
            }
            tareas.append(Tarea(atlas: Int32(u.atlas), foto: -1, destino: destino, origen: [], colores: colores))
        }

        // Triangles in the same order as the tasks, grouped by atlas.
        var ordenTareas = Array(tareas.indices)
        let trianguloDeTarea = lista.flatMap { $0 } + sinFoto
        ordenTareas.sort { (tareas[$0].atlas, tareas[$0].foto) < (tareas[$1].atlas, tareas[$1].foto) }
        var malla3 = MallaTexturizada()
        var tareasOrdenadas: [Tarea] = []
        tareasOrdenadas.reserveCapacity(tareas.count)
        let conNormales = malla.normales.count == malla.vertices.count
        for i in ordenTareas {
            let tarea = tareas[i]
            let t = trianguloDeTarea[i]
            if malla3.grupos.last?.foto != tarea.atlas {
                malla3.grupos.append(.init(foto: tarea.atlas, inicio: Int32(malla3.numeroTriangulos), triangulos: 0))
            }
            malla3.grupos[malla3.grupos.count - 1].triangulos += 1
            let indices = (0..<3).map { Int(malla.indices[t * 3 + $0]) }
            let a = punto(malla.vertices[indices[0]]), b = punto(malla.vertices[indices[1]]), c = punto(malla.vertices[indices[2]])
            let cara = simd_cross(b - a, c - a)
            let normalCara = simd_length(cara) > 1e-9 ? simd_normalize(cara) : SIMD3<Float>(0, 1, 0)
            for (k, i) in indices.enumerated() {
                let v = malla.vertices[i]
                malla3.posiciones += [v.0, v.1, v.2]
                let n = conNormales ? punto(malla.normales[i]) : normalCara
                malla3.normales += [n.x, n.y, n.z]
                malla3.uvs += [tarea.destino[k].x / Float(lado), tarea.destino[k].y / Float(lado)]
            }
            tareasOrdenadas.append(tarea)
        }
        let numero = (tareas.map { Int($0.atlas) }.max() ?? -1) + 1
        return Plan(lado: lado, numeroAtlas: numero, malla: malla3, tareas: tareasOrdenadas, ganancias: fotogramas.map(\.ganancia))
    }

    /// Paints atlas number `indice`. `cargar` returns a full-size photo; photos are
    /// requested in order, so the caller only needs to keep the last one.
    static func hornear(_ plan: Plan, atlas indice: Int, cargar: (Int32) -> ImagenRGBA?) -> ImagenRGBA {
        var imagen = ImagenRGBA(ancho: plan.lado, alto: plan.lado)
        var fotoActual: Int32 = -2
        var foto: ImagenRGBA?
        for tarea in plan.tareas where tarea.atlas == Int32(indice) {
            if tarea.foto >= 0, tarea.foto != fotoActual {
                fotoActual = tarea.foto
                foto = cargar(tarea.foto)
            }
            rasterizar(tarea, en: &imagen, foto: tarea.foto >= 0 ? foto : nil, ganancia: tarea.foto >= 0 ? plan.ganancias[Int(tarea.foto)] : SIMD3(repeating: 1))
        }
        imagen.dilatar(pasadas: 4)
        return imagen
    }

    private static func rasterizar(_ t: Tarea, en imagen: inout ImagenRGBA, foto: ImagenRGBA?, ganancia: SIMD3<Float>) {
        let p0 = t.destino[0], p1 = t.destino[1], p2 = t.destino[2]
        func borde(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ p: SIMD2<Float>) -> Float {
            (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        let area = borde(p0, p1, p2)
        let minimo = simd_min(p0, simd_min(p1, p2)), maximo = simd_max(p0, simd_max(p1, p2))
        let x0 = max(0, Int(minimo.x.rounded(.down)) - 1), y0 = max(0, Int(minimo.y.rounded(.down)) - 1)
        let x1 = min(imagen.ancho - 1, Int(maximo.x.rounded(.up)) + 1), y1 = min(imagen.alto - 1, Int(maximo.y.rounded(.up)) + 1)
        guard x0 <= x1, y0 <= y1 else { return }

        func pintar(_ w0: Float, _ w1: Float, _ w2: Float, _ x: Int, _ y: Int) {
            let mezcla = t.colores[0] * w0 + t.colores[1] * w1 + t.colores[2] * w2
            if let foto, t.origen.count == 3 {
                let o = t.origen[0] * w0 + t.origen[1] * w1 + t.origen[2] * w2
                imagen.poner(x, y, foto.muestra(o.x - 0.5, o.y - 0.5) * ganancia + mezcla)
            } else if t.foto < 0 {
                imagen.poner(x, y, mezcla)
            }
        }

        guard abs(area) > 1e-6 else {
            pintar(1, 0, 0, min(max(Int(p0.x), 0), imagen.ancho - 1), min(max(Int(p0.y), 0), imagen.alto - 1))
            return
        }
        // A small tolerance paints the pixels the edges cross, so there are no cracks.
        let tolerancia = 1.0 / max(abs(area).squareRoot(), 1)
        for y in y0...y1 {
            for x in x0...x1 {
                let p = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                let w0 = borde(p1, p2, p) / area
                let w1 = borde(p2, p0, p) / area
                let w2 = 1 - w0 - w1
                guard w0 >= -tolerancia, w1 >= -tolerancia, w2 >= -tolerancia else { continue }
                let c0 = max(w0, 0), c1 = max(w1, 0), c2 = max(w2, 0)
                let s = c0 + c1 + c2
                pintar(c0 / s, c1 / s, c2 / s, x, y)
            }
        }
    }

    // MARK: - Seam leveling

    static func clave(_ vertice: UInt32, _ foto: Int32) -> UInt64 { UInt64(vertice) << 32 | UInt64(UInt32(bitPattern: foto)) }

    /// Colour offset for each (vertex, photo) pair. On seams it moves every
    /// photo to the average the photos there see; inside a patch it fades out
    /// smoothly (a Laplace equation solved with Gauss-Seidel).
    static func nivelarCosturas(_ malla: PiezaMalla, etiquetas: [Int32], uvFoto: [Float], fotogramas: [Fotograma], iteraciones: Int = 80) -> [UInt64: SIMD3<Float>] {
        // Every (vertex, photo) pair gets an index, its colour in that photo and
        // its neighbours within that photo's triangles.
        var indice: [UInt64: Int32] = [:]
        var claves: [UInt64] = []
        var colores: [SIMD3<Float>] = []
        var vecinos: [[Int32]] = []
        var fotosDelVertice: [UInt32: [Int32]] = [:]
        for t in 0..<malla.triangulos where etiquetas[t] >= 0 {
            let foto = etiquetas[t]
            let f = fotogramas[Int(foto)]
            var trio: [Int32] = []
            for k in 0..<3 {
                let v = malla.indices[t * 3 + k]
                let c = clave(v, foto)
                if let existente = indice[c] {
                    trio.append(existente)
                } else {
                    let nuevo = Int32(claves.count)
                    indice[c] = nuevo
                    claves.append(c)
                    let u = uvFoto[t * 6 + k * 2] * Float(f.ancho), w = uvFoto[t * 6 + k * 2 + 1] * Float(f.alto)
                    colores.append(f.color(u: min(max(u, 0), Float(f.ancho - 2)), v: min(max(w, 0), Float(f.alto - 2))))
                    vecinos.append([])
                    fotosDelVertice[v, default: []].append(foto)
                    trio.append(nuevo)
                }
            }
            for a in trio { for b in trio where a != b && !vecinos[Int(a)].contains(b) { vecinos[Int(a)].append(b) } }
        }

        var desplazamiento = [SIMD3<Float>](repeating: .zero, count: claves.count)
        var fijo = [Bool](repeating: false, count: claves.count)
        var hayCosturas = false
        for (v, fotos) in fotosDelVertice where fotos.count > 1 {
            let lista = fotos.compactMap { indice[clave(v, $0)] }
            let media = lista.reduce(SIMD3<Float>.zero) { $0 + colores[Int($1)] } / Float(lista.count)
            for i in lista {
                desplazamiento[Int(i)] = simd_clamp(media - colores[Int(i)], SIMD3(repeating: -60), SIMD3(repeating: 60))
                fijo[Int(i)] = true
            }
            hayCosturas = true
        }
        guard hayCosturas else { return [:] }

        let libres = (0..<claves.count).filter { !fijo[$0] && !vecinos[$0].isEmpty }
        for _ in 0..<iteraciones {
            for i in libres {
                var suma = SIMD3<Float>.zero
                for n in vecinos[i] { suma += desplazamiento[Int(n)] }
                desplazamiento[i] = suma / Float(vecinos[i].count)
            }
        }
        var resultado: [UInt64: SIMD3<Float>] = [:]
        resultado.reserveCapacity(claves.count)
        for (i, c) in claves.enumerated() where desplazamiento[i] != .zero { resultado[c] = desplazamiento[i] }
        return resultado
    }

    private static func punto(_ t: (Float, Float, Float)) -> SIMD3<Float> { SIMD3(t.0, t.1, t.2) }
}
