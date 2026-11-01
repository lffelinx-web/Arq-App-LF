import Foundation
import simd

/// Mesh ready to draw with photo textures: every triangle has its own three
/// corners (position, normal and UV) and triangles are grouped by photo.
struct MallaTexturizada: Equatable {
    struct Grupo: Equatable {
        /// Index of the photo in the scan, or -1 for triangles no photo saw.
        var foto: Int32
        /// First triangle of the group and how many it has.
        var inicio: Int32
        var triangulos: Int32
    }

    var posiciones: [Float] = []   // x, y, z per corner
    var normales: [Float] = []     // nx, ny, nz per corner
    var uvs: [Float] = []          // u, v per corner, (0, 0) at the photo's top-left
    var grupos: [Grupo] = []
    /// Every triangle's winding agrees with its normal, so it can be drawn one-sided
    /// (seen from behind, thin surfaces disappear instead of showing a mirrored texture).
    var orientada = false

    var esquinas: Int { posiciones.count / 3 }
    var numeroTriangulos: Int { esquinas / 3 }
    var fotosUsadas: [Int32] { grupos.map(\.foto).filter { $0 >= 0 } }
}

/// Projects the scan photos onto the mesh: each triangle takes the photo that
/// saw it closest, most head-on and unobstructed, and neighbouring triangles
/// are nudged toward the same photo so there are fewer seams.
enum Texturizar {
    /// Joins the ARKit pieces into one mesh.
    static func unir(_ piezas: [PiezaMalla]) -> PiezaMalla {
        var total = PiezaMalla(vertices: [], normales: [], indices: [])
        let conNormales = piezas.allSatisfy { $0.normales.count == $0.vertices.count }
        let conColor = piezas.allSatisfy(\.conColor)
        let conClases = piezas.allSatisfy(\.conClases)
        for pieza in piezas {
            let base = UInt32(total.vertices.count)
            total.vertices += pieza.vertices
            if conNormales { total.normales += pieza.normales }
            if conColor { total.colores += pieza.colores }
            if conClases { total.clases += pieza.clases }
            total.indices += pieza.indices.map { $0 + base }
        }
        return total
    }

    /// Score of photo `f` for the triangle `a b c` (higher is better), with the
    /// triangle's UVs on that photo, or nil if the photo can't texture it.
    static func puntaje(
        _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, normal: SIMD3<Float>,
        foto f: Fotograma, inversa: simd_float4x4, posicion: SIMD3<Float>, frontalMinimo: Float = 0.2, estricto: Bool = true
    ) -> (puntaje: Float, uv: [Float])? {
        guard let pa = f.proyectar(a, con: inversa),
              let pb = f.proyectar(b, con: inversa),
              let pc = f.proyectar(c, con: inversa) else { return nil }
        let centro = (a + b + c) / 3
        guard let pm = f.proyectar(centro, con: inversa), pm.distancia < 7 else { return nil }
        let hacia = simd_normalize(posicion - centro)
        let frontal = simd_dot(normal, hacia)
        guard frontal > frontalMinimo else { return nil }
        guard f.visible(u: pm.u, v: pm.v, distancia: pm.distancia) else { return nil }
        // Never paint a person onto the room.
        for p in [pa, pb, pc, pm] where f.esPersona(u: p.u, v: p.v) { return nil }
        var penalizacion: Float = 1
        if estricto {
            // Every corner must be in plain sight, or the photo paints part of
            // whatever was in front of it onto the triangle.
            for p in [pa, pb, pc] where !f.visible(u: p.u, v: p.v, distancia: p.distancia) { return nil }
            // On object outlines the photo mixes object and background: prefer another photo.
            let salto = [pa, pb, pc, pm].map { f.saltoProfundidad(u: $0.u, v: $0.v) }.max() ?? 0
            if salto > 0.12 + 0.04 * pm.distancia { penalizacion = 0.25 }
        }
        let bordeX = min(pm.u, Float(f.ancho) - pm.u) / Float(f.ancho)
        let bordeY = min(pm.v, Float(f.alto) - pm.v) / Float(f.alto)
        let enCentro = min(1, 4 * min(bordeX, bordeY) + 0.2)
        let puntaje = frontal * frontal * enCentro * penalizacion / max(pm.distancia, 0.3)
        let w = Float(f.ancho), h = Float(f.alto)
        return (puntaje, [pa.u / w, pa.v / h, pb.u / w, pb.v / h, pc.u / w, pc.v / h])
    }

    /// Photo chosen for every triangle (-1 when none fits). Each triangle keeps its
    /// best few photos; then, pass after pass, it switches to the photo its
    /// neighbours use when that photo is good enough (a Potts model solved by ICM).
    /// That gives large patches with few seams instead of a per-triangle mosaic.
    static func etiquetas(_ malla: PiezaMalla, fotogramas: [Fotograma], suavizado: Float = 0.28, pasadas: Int = 10) -> [Int32] {
        let triangulos = malla.triangulos
        guard triangulos > 0, !fotogramas.isEmpty else { return [Int32](repeating: -1, count: triangulos) }
        let inversas = fotogramas.map(\.mundoACamara)
        let posiciones = fotogramas.map(\.posicion)
        let nitidezMaxima = max(fotogramas.map(\.nitidez).max() ?? 1, 1e-6)
        let factorNitidez = fotogramas.map { ($0.nitidez / nitidezMaxima).squareRoot() * 0.7 + 0.3 }

        var candidatos = [[(foto: Int32, puntaje: Float)]](repeating: [], count: triangulos)
        for t in 0..<triangulos {
            let i = Int(malla.indices[t * 3]), j = Int(malla.indices[t * 3 + 1]), k = Int(malla.indices[t * 3 + 2])
            let a = punto(malla.vertices[i]), b = punto(malla.vertices[j]), c = punto(malla.vertices[k])
            let n = normal(malla, i, j, k, a, b, c)
            var lista: [(foto: Int32, puntaje: Float)] = []
            var colores: [SIMD3<Float>] = []
            for f in fotogramas.indices {
                guard let r = puntaje(a, b, c, normal: n, foto: fotogramas[f], inversa: inversas[f], posicion: posiciones[f]) else { continue }
                lista.append((Int32(f), r.puntaje * factorNitidez[f]))
                colores.append(colorCentro(r.uv, fotogramas[f]))
            }
            lista = consistentes(lista, colores: colores)
            if lista.isEmpty {
                // Edges and corners seen only at a grazing angle: a slanted photo beats none.
                for f in fotogramas.indices {
                    guard let r = puntaje(a, b, c, normal: n, foto: fotogramas[f], inversa: inversas[f], posicion: posiciones[f], frontalMinimo: 0.03, estricto: false) else { continue }
                    lista.append((Int32(f), r.puntaje * factorNitidez[f] * 0.5))
                }
            }
            lista.sort { $0.puntaje > $1.puntaje }
            candidatos[t] = Array(lista.prefix(6))
        }

        var etiqueta = candidatos.map { $0.first?.foto ?? -1 }
        guard pasadas > 0 else { return etiqueta }
        let vecinos = vecindad(malla)
        for _ in 0..<pasadas {
            var cambios = 0
            for t in 0..<triangulos where candidatos[t].count > 1 {
                let mejor = candidatos[t][0].puntaje
                var elegido = etiqueta[t]
                var menorCosto = Float.infinity
                for candidato in candidatos[t] {
                    var costo = 1 - candidato.puntaje / mejor
                    for v in vecinos[t] where etiqueta[Int(v)] != candidato.foto { costo += suavizado }
                    if costo < menorCosto - 1e-6 {
                        menorCosto = costo
                        elegido = candidato.foto
                    }
                }
                if elegido != etiqueta[t] {
                    etiqueta[t] = elegido
                    cambios += 1
                }
            }
            if cambios == 0 { break }
        }
        return etiqueta
    }

    /// Colour a photo sees at the middle of a triangle (from its UVs).
    private static func colorCentro(_ uv: [Float], _ f: Fotograma) -> SIMD3<Float> {
        let u = (uv[0] + uv[2] + uv[4]) / 3 * Float(f.ancho)
        let v = (uv[1] + uv[3] + uv[5]) / 3 * Float(f.alto)
        return f.color(u: min(max(u, 0), Float(f.ancho - 2)), v: min(max(v, 0), Float(f.alto - 2)))
    }

    /// Photo consistency: when three or more photos see a triangle, drop the ones
    /// whose colour there is far from the median. That removes things the mesh
    /// doesn't have (thin chair legs, a passer-by) that a single photo would
    /// otherwise paint onto the surface behind them.
    static func consistentes(_ lista: [(foto: Int32, puntaje: Float)], colores: [SIMD3<Float>], tolerancia: Float = 45) -> [(foto: Int32, puntaje: Float)] {
        guard lista.count >= 3, colores.count == lista.count else { return lista }
        func mediana(_ valores: [Float]) -> Float {
            let o = valores.sorted()
            return o.count % 2 == 1 ? o[o.count / 2] : (o[o.count / 2 - 1] + o[o.count / 2]) / 2
        }
        let centro = SIMD3(mediana(colores.map(\.x)), mediana(colores.map(\.y)), mediana(colores.map(\.z)))
        let filtrada = zip(lista, colores).filter { simd_distance($0.1, centro) <= tolerancia }.map(\.0)
        return filtrada.isEmpty ? lista : filtrada
    }

    /// UVs of every triangle's corners on its chosen photo (six values per
    /// triangle, zeros for triangles without a photo).
    static func uvs(_ malla: PiezaMalla, etiquetas: [Int32], fotogramas: [Fotograma]) -> [Float] {
        let inversas = fotogramas.map(\.mundoACamara)
        var resultado = [Float](repeating: 0, count: malla.triangulos * 6)
        for t in 0..<malla.triangulos where etiquetas[t] >= 0 {
            let f = fotogramas[Int(etiquetas[t])]
            let w = Float(f.ancho), h = Float(f.alto)
            for k in 0..<3 {
                let v = malla.vertices[Int(malla.indices[t * 3 + k])]
                let c = inversas[Int(etiquetas[t])] * SIMD4<Float>(v.0, v.1, v.2, 1)
                let d = max(-c.z, 0.01)
                resultado[t * 6 + k * 2] = (f.fx * c.x / d + f.cx) / w
                resultado[t * 6 + k * 2 + 1] = (-f.fy * c.y / d + f.cy) / h
            }
        }
        return resultado
    }

    /// Builds the textured mesh, grouping triangles by photo.
    static func construir(_ malla: PiezaMalla, fotogramas: [Fotograma]) -> MallaTexturizada {
        let etiqueta = etiquetas(malla, fotogramas: fotogramas)
        var porFoto: [Int32: [Int]] = [:]
        for (t, e) in etiqueta.enumerated() { porFoto[e, default: []].append(t) }

        var resultado = MallaTexturizada()
        resultado.posiciones.reserveCapacity(malla.triangulos * 9)
        resultado.normales.reserveCapacity(malla.triangulos * 9)
        resultado.uvs.reserveCapacity(malla.triangulos * 6)
        let inversas = fotogramas.map(\.mundoACamara)
        let posiciones = fotogramas.map(\.posicion)

        for foto in porFoto.keys.sorted() {
            let lista = porFoto[foto] ?? []
            resultado.grupos.append(.init(foto: foto, inicio: Int32(resultado.numeroTriangulos), triangulos: Int32(lista.count)))
            for t in lista {
                let i = Int(malla.indices[t * 3]), j = Int(malla.indices[t * 3 + 1]), k = Int(malla.indices[t * 3 + 2])
                let a = punto(malla.vertices[i]), b = punto(malla.vertices[j]), c = punto(malla.vertices[k])
                let n = normal(malla, i, j, k, a, b, c)
                for (indice, p) in [(i, a), (j, b), (k, c)] {
                    resultado.posiciones += [p.x, p.y, p.z]
                    let nv = malla.normales.count == malla.vertices.count ? punto(malla.normales[indice]) : n
                    resultado.normales += [nv.x, nv.y, nv.z]
                }
                // Labels only point to photos that can texture the triangle, so the
                // fallback is just a safety net.
                if foto >= 0, let r = puntaje(a, b, c, normal: n, foto: fotogramas[Int(foto)], inversa: inversas[Int(foto)], posicion: posiciones[Int(foto)]) {
                    resultado.uvs += r.uv
                } else {
                    resultado.uvs += [0, 0, 0, 0, 0, 0]
                }
            }
        }
        return resultado
    }

    // MARK: - Files

    /// Compact binary used by the app's viewer.
    static func datos(_ m: MallaTexturizada) -> Data {
        var d = Data("ALFT".utf8)
        agregar(&d, UInt32(m.orientada ? 2 : 1))
        agregar(&d, UInt32(m.esquinas))
        agregar(&d, UInt32(m.grupos.count))
        for v in m.posiciones { agregar(&d, v.bitPattern) }
        for v in m.normales { agregar(&d, v.bitPattern) }
        for v in m.uvs { agregar(&d, v.bitPattern) }
        for g in m.grupos {
            agregar(&d, UInt32(bitPattern: g.foto))
            agregar(&d, UInt32(bitPattern: g.inicio))
            agregar(&d, UInt32(bitPattern: g.triangulos))
        }
        return d
    }

    enum ErrorTextura: Error { case formato }

    static func leer(_ datos: Data) throws -> MallaTexturizada {
        guard datos.count >= 16, datos.prefix(4) == Data("ALFT".utf8) else { throw ErrorTextura.formato }
        return try datos.withUnsafeBytes { (crudo: UnsafeRawBufferPointer) -> MallaTexturizada in
            func u32(_ i: Int) -> UInt32 {
                UInt32(crudo[i]) | UInt32(crudo[i + 1]) << 8 | UInt32(crudo[i + 2]) << 16 | UInt32(crudo[i + 3]) << 24
            }
            let version = u32(4)
            guard version == 1 || version == 2 else { throw ErrorTextura.formato }
            let esquinas = Int(u32(8)), grupos = Int(u32(12))
            let necesario = 16 + esquinas * 8 * 4 + grupos * 12
            guard crudo.count >= necesario else { throw ErrorTextura.formato }
            var m = MallaTexturizada()
            m.orientada = version == 2
            var cursor = 16
            func flotantes(_ n: Int) -> [Float] {
                var r = [Float]()
                r.reserveCapacity(n)
                for _ in 0..<n { r.append(Float(bitPattern: u32(cursor))); cursor += 4 }
                return r
            }
            m.posiciones = flotantes(esquinas * 3)
            m.normales = flotantes(esquinas * 3)
            m.uvs = flotantes(esquinas * 2)
            for _ in 0..<grupos {
                m.grupos.append(.init(foto: Int32(bitPattern: u32(cursor)), inicio: Int32(bitPattern: u32(cursor + 4)), triangulos: Int32(bitPattern: u32(cursor + 8))))
                cursor += 12
            }
            return m
        }
    }

    /// Writes `modelo.obj` + `modelo.mtl` into `carpeta`. The photos must be next
    /// to them as `foto_N.jpg`, which is what `nombreFoto` returns.
    static func escribirOBJ(_ m: MallaTexturizada, en carpeta: URL) throws {
        var mtl = "# Arq LF\n"
        for g in m.grupos {
            if g.foto >= 0 {
                mtl += "newmtl \(nombreMaterial(g.foto))\nKa 1 1 1\nKd 1 1 1\nillum 1\nmap_Kd \(nombreFoto(g.foto))\n\n"
            } else {
                mtl += "newmtl \(nombreMaterial(g.foto))\nKa 1 1 1\nKd 0.67 0.67 0.67\nillum 1\n\n"
            }
        }
        try Data(mtl.utf8).write(to: carpeta.appendingPathComponent("modelo.mtl"), options: .atomic)

        let url = carpeta.appendingPathComponent("modelo.obj")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let archivo = try FileHandle(forWritingTo: url)
        defer { try? archivo.close() }
        try archivo.write(contentsOf: Data("# Escaneo LiDAR texturizado con Arq LF\n# Unidades: metros\nmtllib modelo.mtl\no Escaneo\n".utf8))

        let bloque = 20_000
        var inicio = 0
        while inicio < m.esquinas {
            let fin = min(m.esquinas, inicio + bloque)
            var s = ""
            for e in inicio..<fin {
                s += "v \(OBJ.numero(m.posiciones[e * 3])) \(OBJ.numero(m.posiciones[e * 3 + 1])) \(OBJ.numero(m.posiciones[e * 3 + 2]))\n"
            }
            for e in inicio..<fin {
                // OBJ's V grows upward.
                s += "vt \(OBJ.numero(m.uvs[e * 2])) \(OBJ.numero(1 - m.uvs[e * 2 + 1]))\n"
            }
            for e in inicio..<fin {
                s += "vn \(OBJ.numero(m.normales[e * 3])) \(OBJ.numero(m.normales[e * 3 + 1])) \(OBJ.numero(m.normales[e * 3 + 2]))\n"
            }
            try archivo.write(contentsOf: Data(s.utf8))
            inicio = fin
        }

        for g in m.grupos {
            var s = "usemtl \(nombreMaterial(g.foto))\n"
            for t in Int(g.inicio)..<Int(g.inicio + g.triangulos) {
                let a = t * 3 + 1, b = a + 1, c = a + 2
                s += "f \(a)/\(a)/\(a) \(b)/\(b)/\(b) \(c)/\(c)/\(c)\n"
            }
            try archivo.write(contentsOf: Data(s.utf8))
        }
    }

    static func nombreFoto(_ foto: Int32) -> String { "foto_\(foto).jpg" }
    static func nombreMaterial(_ foto: Int32) -> String { foto >= 0 ? "foto_\(foto)" : "sin_textura" }

    // MARK: - Helpers

    private static func punto(_ t: (Float, Float, Float)) -> SIMD3<Float> { SIMD3(t.0, t.1, t.2) }

    /// Averaged vertex normal, or the face normal when the mesh has none.
    private static func normal(_ m: PiezaMalla, _ i: Int, _ j: Int, _ k: Int, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        if m.normales.count == m.vertices.count {
            let suma = punto(m.normales[i]) + punto(m.normales[j]) + punto(m.normales[k])
            let largo = simd_length(suma)
            if largo > 1e-6 { return suma / largo }
        }
        let cara = simd_cross(b - a, c - a)
        let largo = simd_length(cara)
        return largo > 1e-9 ? cara / largo : SIMD3(0, 1, 0)
    }

    /// Triangles that share an edge with each triangle.
    static func vecindad(_ m: PiezaMalla) -> [[Int32]] {
        var porArista: [UInt64: [Int32]] = [:]
        porArista.reserveCapacity(m.triangulos * 2)
        for t in 0..<m.triangulos {
            let v = [m.indices[t * 3], m.indices[t * 3 + 1], m.indices[t * 3 + 2]]
            for (x, y) in [(v[0], v[1]), (v[1], v[2]), (v[2], v[0])] {
                let clave = UInt64(min(x, y)) << 32 | UInt64(max(x, y))
                porArista[clave, default: []].append(Int32(t))
            }
        }
        var vecinos = [[Int32]](repeating: [], count: m.triangulos)
        for lista in porArista.values where lista.count > 1 {
            for t in lista { for o in lista where o != t { vecinos[Int(t)].append(o) } }
        }
        return vecinos
    }

    private static func agregar(_ d: inout Data, _ v: UInt32) {
        d.append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)])
    }
}
