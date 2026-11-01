import SwiftUI
import UIKit

/// Builds the shareable files (PDF, PNG, CSV and named copies of the models).
enum Exportacion {
    /// Letter size in points.
    static let hoja = CGSize(width: 612, height: 792)

    @MainActor
    static func imagen(_ plano: PlanoPlanta, tamano: CGSize, estilo: EstiloPlano = .pantalla, unidad: Unidad = .metros) -> UIImage? {
        let renderer = ImageRenderer(content: PlanoDibujo(plano: plano, unidad: unidad, estilo: estilo, cotas: tamano.width > 500)
            .frame(width: tamano.width, height: tamano.height))
        renderer.scale = 2
        return renderer.uiImage
    }

    @MainActor
    static func pdf(_ plano: PlanoPlanta, proyecto: Proyecto, unidad: Unidad, en url: URL) throws {
        let renderer = ImageRenderer(content: HojaPlano(plano: plano, proyecto: proyecto, unidad: unidad).frame(width: hoja.width, height: hoja.height))
        var caja = CGRect(origin: .zero, size: hoja)
        guard let contexto = CGContext(url as CFURL, mediaBox: &caja, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        renderer.render { _, dibujar in
            contexto.beginPDFPage(nil)
            dibujar(contexto)
            contexto.endPDFPage()
            contexto.closePDF()
        }
    }

    /// Temporary folder where the share sheet copies live.
    static func carpetaTemporal(_ proyecto: Proyecto) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Exportar-\(proyecto.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies `origen` as `nombre` so the shared file has a meaningful name.
    static func copia(_ origen: URL, como nombre: String, en carpeta: URL) -> URL? {
        let destino = carpeta.appendingPathComponent(nombre)
        try? FileManager.default.removeItem(at: destino)
        do {
            try FileManager.default.copyItem(at: origen, to: destino)
            return destino
        } catch {
            return nil
        }
    }

    static func texto(_ contenido: String, como nombre: String, en carpeta: URL) -> URL? {
        let destino = carpeta.appendingPathComponent(nombre)
        do {
            try Data(contenido.utf8).write(to: destino, options: .atomic)
            return destino
        } catch {
            return nil
        }
    }
}

/// One printable page: title, plan and a summary table.
private struct HojaPlano: View {
    let plano: PlanoPlanta
    let proyecto: Proyecto
    let unidad: Unidad

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(proyecto.nombre).font(.system(size: 22, weight: .bold))
                    Text("Plano de planta · \(Formato.fecha(proyecto.fecha))").font(.system(size: 10)).foregroundColor(.gray)
                }
                Spacer()
                Text("Arq LF").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: 0xB0620A))
            }
            PlanoDibujo(plano: plano, unidad: unidad, estilo: .papel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5))
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    dato("Área de piso", Formato.area(plano.area, unidad))
                    dato("Perímetro", Formato.longitud(plano.perimetro, unidad))
                    dato("Altura promedio", Formato.longitud(plano.alturaPromedio, unidad))
                    dato("Volumen", Formato.volumen(plano.volumen, unidad))
                }
                VStack(alignment: .leading, spacing: 4) {
                    dato("Muros", "\(plano.muros.count)")
                    dato("Muros sin huecos", Formato.area(plano.areaMurosNeta, unidad))
                    dato("Puertas", "\(plano.cuenta(.puerta))")
                    dato("Ventanas", "\(plano.cuenta(.ventana))")
                }
            }
            if !proyecto.notas.isEmpty {
                Text(proyecto.notas).font(.system(size: 9)).foregroundColor(.gray)
            }
        }
        .padding(36)
        .foregroundColor(.black)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func dato(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo).foregroundColor(.gray)
            Spacer(minLength: 16)
            Text(valor).fontWeight(.semibold)
        }
        .font(.system(size: 10))
        .frame(width: 220)
    }
}
