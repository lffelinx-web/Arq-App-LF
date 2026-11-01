import Foundation
import Observation

/// Keeps every project in its own folder under Documents/Proyectos, so the
/// files are also visible in the Files app.
@Observable
final class Almacen {
    private(set) var proyectos: [Proyecto] = []
    let raiz: URL

    init(raiz: URL? = nil) {
        let documentos = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.raiz = raiz ?? documentos.appendingPathComponent("Proyectos", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.raiz, withIntermediateDirectories: true)
        cargar()
    }

    func carpeta(_ proyecto: Proyecto) -> URL {
        raiz.appendingPathComponent(proyecto.id.uuidString, isDirectory: true)
    }

    func url(_ archivo: ArchivoProyecto, de proyecto: Proyecto) -> URL {
        carpeta(proyecto).appendingPathComponent(archivo.rawValue)
    }

    func existe(_ archivo: ArchivoProyecto, de proyecto: Proyecto) -> Bool {
        FileManager.default.fileExists(atPath: url(archivo, de: proyecto).path)
    }

    func cargar() {
        let fm = FileManager.default
        let carpetas = (try? fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        proyectos = carpetas.compactMap { carpeta in
            guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent("proyecto.json")) else { return nil }
            return try? decoder.decode(Proyecto.self, from: datos)
        }
        .sorted { $0.fecha > $1.fecha }
    }

    /// Creates the folder for a new project and returns it so captures can write their files there.
    func preparar(_ proyecto: Proyecto) throws -> URL {
        let c = carpeta(proyecto)
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }

    func guardar(_ proyecto: Proyecto) throws {
        _ = try preparar(proyecto)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(proyecto).write(to: carpeta(proyecto).appendingPathComponent("proyecto.json"), options: .atomic)
        if let i = proyectos.firstIndex(where: { $0.id == proyecto.id }) {
            proyectos[i] = proyecto
        } else {
            proyectos.insert(proyecto, at: 0)
        }
    }

    func eliminar(_ proyecto: Proyecto) {
        try? FileManager.default.removeItem(at: carpeta(proyecto))
        proyectos.removeAll { $0.id == proyecto.id }
    }

    func plano(de proyecto: Proyecto) -> PlanoPlanta? {
        guard let datos = try? Data(contentsOf: url(.plano, de: proyecto)) else { return nil }
        return try? JSONDecoder().decode(PlanoPlanta.self, from: datos)
    }

    func guardar(_ plano: PlanoPlanta, de proyecto: Proyecto) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plano).write(to: url(.plano, de: proyecto), options: .atomic)
    }

    /// Suggested name for a new project ("Cuarto 3").
    func nombreSugerido(_ tipo: TipoProyecto) -> String {
        let n = proyectos.filter { $0.tipo == tipo }.count + 1
        return "\(tipo.nombre) \(n)"
    }
}
