import QuickLook
import SwiftUI

/// A saved project: 3D model, plan, data sheet and exports.
struct DetalleView: View {
    enum Pestana: String, CaseIterable, Identifiable {
        case modelo = "3D"
        case plano = "Plano"
        case foto = "Foto"
        case datos = "Datos"

        var id: String { rawValue }
    }

    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var cerrar
    @AppStorage("unidad") private var unidad: Unidad = .metros
    @State private var proyecto: Proyecto
    @State private var pestana: Pestana
    @State private var plano: PlanoPlanta?
    @State private var archivos: [URL] = []
    @State private var vistaAR: URL?
    @State private var renombrando = false
    @State private var nuevoNombre = ""
    @State private var confirmarBorrado = false

    init(proyecto: Proyecto) {
        _proyecto = State(initialValue: proyecto)
        _pestana = State(initialValue: proyecto.tipo == .medidas ? .foto : .modelo)
    }

    private var pestanas: [Pestana] {
        switch proyecto.tipo {
        case .cuarto: return [.modelo, .plano, .datos]
        case .malla: return almacen.existe(.foto, de: proyecto) ? [.modelo, .foto, .datos] : [.modelo, .datos]
        case .medidas: return [.foto, .datos]
        }
    }

    private var modelo: URL? {
        if proyecto.tipo == .malla, almacen.existe(.mallaOBJ, de: proyecto) { return almacen.url(.mallaOBJ, de: proyecto) }
        if almacen.existe(.modeloUSDZ, de: proyecto) { return almacen.url(.modeloUSDZ, de: proyecto) }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if pestanas.count > 1 {
                Picker("Vista", selection: $pestana) {
                    ForEach(pestanas) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            contenido.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle(proyecto.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !archivos.isEmpty {
                    Menu {
                        ForEach(archivos, id: \.self) { url in
                            ShareLink(item: url) { Label(url.lastPathComponent, systemImage: Self.icono(url)) }
                        }
                        Divider()
                        ShareLink(items: archivos) { Label("Compartir todo", systemImage: "square.and.arrow.up.on.square") }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                Menu {
                    if almacen.existe(.modeloUSDZ, de: proyecto) {
                        Button { vistaAR = almacen.url(.modeloUSDZ, de: proyecto) } label: { Label("Ver en AR", systemImage: "arkit") }
                    }
                    Button {
                        nuevoNombre = proyecto.nombre
                        renombrando = true
                    } label: { Label("Renombrar", systemImage: "pencil") }
                    Button(role: .destructive) { confirmarBorrado = true } label: { Label("Eliminar", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .quickLookPreview($vistaAR)
        .alert("Renombrar", isPresented: $renombrando) {
            TextField("Nombre", text: $nuevoNombre)
            Button("Guardar") {
                let limpio = nuevoNombre.trimmingCharacters(in: .whitespaces)
                guard !limpio.isEmpty else { return }
                proyecto.nombre = limpio
                guardarProyecto()
                Task { await prepararArchivos() }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Eliminar \(proyecto.nombre)?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                almacen.eliminar(proyecto)
                cerrar()
            }
        } message: {
            Text("Se borrarán el modelo y todos sus archivos.")
        }
        .task { await prepararArchivos() }
        .onChange(of: unidad) { Task { await prepararArchivos() } }
    }

    @ViewBuilder private var contenido: some View {
        switch pestana {
        case .modelo:
            if let modelo {
                Visor3D(url: modelo)
                    .overlay(alignment: .bottom) {
                        Pastilla(texto: "Arrastra para girar · pellizca para acercar")
                            .padding(.bottom, 12)
                            .allowsHitTesting(false)
                    }
            } else {
                Vacio(texto: "Este proyecto no tiene modelo 3D.")
            }
        case .plano:
            if let plano, !plano.vacio {
                PlanoInteractivo(plano: plano, unidad: unidad)
            } else {
                Vacio(texto: "No hay plano para este escaneo.")
            }
        case .foto:
            if let imagen = UIImage(contentsOfFile: almacen.url(.foto, de: proyecto).path) {
                Image(uiImage: imagen).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Vacio(texto: "Sin foto.")
            }
        case .datos:
            HojaDatos(proyecto: $proyecto, plano: plano, unidad: unidad, alCambiar: guardarProyecto)
        }
    }

    private func guardarProyecto() {
        try? almacen.guardar(proyecto)
    }

    /// Prepares named copies of every file so the share sheet shows nice names.
    @MainActor
    private func prepararArchivos() async {
        if proyecto.tipo == .cuarto { plano = almacen.plano(de: proyecto) }
        let carpeta = Exportacion.carpetaTemporal(proyecto)
        let base = Formato.nombreArchivo(proyecto.nombre)
        var urls: [URL] = []

        if let plano, !plano.vacio {
            let pdf = carpeta.appendingPathComponent("\(base)-plano.pdf")
            if (try? Exportacion.pdf(plano, proyecto: proyecto, unidad: unidad, en: pdf)) != nil { urls.append(pdf) }
            if let png = Exportacion.imagen(plano, tamano: CGSize(width: 1200, height: 1200), estilo: .papel, unidad: unidad)?.pngData() {
                let url = carpeta.appendingPathComponent("\(base)-plano.png")
                if (try? png.write(to: url)) != nil { urls.append(url) }
            }
            if let csv = Exportacion.texto(CSV.plano(plano), como: "\(base)-medidas.csv", en: carpeta) { urls.append(csv) }
        }
        let copias: [(ArchivoProyecto, String)] = [
            (.modeloUSDZ, "\(base).usdz"), (.mallaOBJ, "\(base).obj"), (.plano, "\(base)-plano.json"), (.foto, "\(base).jpg"),
        ]
        for (archivo, nombre) in copias where almacen.existe(archivo, de: proyecto) {
            if let copia = Exportacion.copia(almacen.url(archivo, de: proyecto), como: nombre, en: carpeta) { urls.append(copia) }
        }
        if proyecto.tipo == .medidas, !proyecto.medidas.isEmpty,
           let csv = Exportacion.texto(CSV.medidas(proyecto.medidas), como: "\(base)-medidas.csv", en: carpeta) {
            urls.append(csv)
        }
        archivos = urls
    }

    private static func icono(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "png", "jpg": return "photo"
        case "csv": return "tablecells"
        case "json": return "curlybraces"
        default: return "cube"
        }
    }
}

private struct Vacio: View {
    let texto: String

    var body: some View {
        Text(texto).foregroundStyle(Tema.apagado).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Numbers of the project: summary, walls, openings, furniture, measurements and notes.
private struct HojaDatos: View {
    @Binding var proyecto: Proyecto
    let plano: PlanoPlanta?
    let unidad: Unidad
    let alCambiar: () -> Void
    @Environment(Almacen.self) private var almacen

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let plano, !plano.vacio { datosPlano(plano) }
                if proyecto.tipo == .malla { datosMalla }
                if proyecto.tipo == .medidas { datosMedidas }
                Tarjeta {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notas").font(.headline)
                        TextField("Escribe notas del proyecto…", text: $proyecto.notas, axis: .vertical)
                            .lineLimit(3...10)
                            .onSubmit(alCambiar)
                    }
                }
                Tarjeta {
                    FilaDato(titulo: "Creado", valor: Formato.fecha(proyecto.fecha), icono: "calendar")
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: proyecto.notas) { alCambiar() }
    }

    @ViewBuilder private func datosPlano(_ plano: PlanoPlanta) -> some View {
        Tarjeta {
            VStack(spacing: 10) {
                FilaDato(titulo: "Área de piso", valor: Formato.area(plano.area, unidad), icono: "square.dashed")
                FilaDato(titulo: "Perímetro", valor: Formato.longitud(plano.perimetro, unidad), icono: "point.topleft.down.to.point.bottomright.curvepath")
                FilaDato(titulo: "Altura promedio", valor: Formato.longitud(plano.alturaPromedio, unidad), icono: "arrow.up.and.down")
                FilaDato(titulo: "Volumen", valor: Formato.volumen(plano.volumen, unidad), icono: "cube")
                FilaDato(titulo: "Muros sin huecos", valor: Formato.area(plano.areaMurosNeta, unidad), icono: "paintbrush")
            }
        }
        if !plano.muros.isEmpty {
            Tarjeta {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Muros (\(plano.muros.count))").font(.headline)
                    ForEach(Array(plano.muros.enumerated()), id: \.element.id) { i, muro in
                        FilaDato(titulo: "Muro \(i + 1)", valor: "\(Formato.longitud(muro.longitud, unidad)) × \(Formato.longitud(muro.altura, unidad))")
                    }
                }
            }
        }
        if !plano.aberturas.isEmpty {
            Tarjeta {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Puertas y ventanas").font(.headline)
                    ForEach(TipoAbertura.allCases, id: \.self) { tipo in
                        ForEach(Array(plano.aberturas.filter { $0.tipo == tipo }.enumerated()), id: \.element.id) { i, a in
                            FilaDato(
                                titulo: "\(tipo.nombre) \(i + 1)",
                                valor: "\(Formato.longitud(a.ancho, unidad)) × \(Formato.longitud(a.altura, unidad))" + (a.elevacion > 0.05 ? " ↑\(Formato.longitud(a.elevacion, unidad))" : "")
                            )
                        }
                    }
                }
            }
        }
        if !plano.muebles.isEmpty {
            Tarjeta {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Muebles (\(plano.muebles.count))").font(.headline)
                    ForEach(plano.muebles) { m in
                        FilaDato(titulo: m.nombre, valor: "\(Formato.longitud(m.ancho, unidad)) × \(Formato.longitud(m.fondo, unidad)) × \(Formato.longitud(m.alto, unidad))")
                    }
                }
            }
        }
    }

    private var datosMalla: some View {
        Tarjeta {
            VStack(spacing: 10) {
                FilaDato(titulo: "Vértices", valor: proyecto.vertices.formatted(), icono: "circle.grid.3x3")
                FilaDato(titulo: "Triángulos", valor: proyecto.triangulos.formatted(), icono: "triangle")
                if let tamano = try? almacen.url(.mallaOBJ, de: proyecto).resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    FilaDato(titulo: "Archivo OBJ", valor: ByteCountFormatter.string(fromByteCount: Int64(tamano), countStyle: .file), icono: "doc")
                }
            }
        }
    }

    private var datosMedidas: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                Text("Medidas (\(proyecto.medidas.count))").font(.headline)
                ForEach($proyecto.medidas) { $medida in
                    HStack {
                        TextField("Nombre", text: $medida.nombre)
                            .foregroundStyle(Tema.apagado)
                            .onSubmit(alCambiar)
                        Spacer()
                        Text(Formato.longitud(medida.metros, unidad)).font(.body.monospacedDigit().weight(.semibold))
                        Button {
                            proyecto.medidas.removeAll { $0.id == medida.id }
                            alCambiar()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Tema.peligro)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.subheadline)
                }
                if proyecto.medidas.count > 1 {
                    Divider()
                    FilaDato(titulo: "Suma", valor: Formato.longitud(proyecto.medidas.reduce(0) { $0 + $1.metros }, unidad))
                }
            }
        }
    }
}
