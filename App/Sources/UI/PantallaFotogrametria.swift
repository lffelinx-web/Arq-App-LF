import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// "Fotos a 3D": pick photos from the library and turn them into a textured
/// model with Object Capture, all on the iPhone.
struct PantallaFotogrametria: View {
    var alGuardar: (Proyecto) -> Void
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var cerrar
    @StateObject private var motor = Fotogrametria()
    @State private var seleccion: [PhotosPickerItem] = []
    @State private var soloObjeto = true
    @State private var nombre = ""
    @State private var copiando = false
    @State private var copiadas = 0
    @State private var carpetaFotos: URL?
    @State private var proyecto: Proyecto?
    @State private var error: String?

    static let minimoFotos = 10
    static let maximoFotos = 300

    private var ocupado: Bool {
        if copiando { return true }
        if case .procesando = motor.estado { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if ocupado {
                    progreso
                } else {
                    formulario
                }
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Fotos a 3D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ocupado ? "Cancelar" : "Cerrar") {
                        if ocupado { cancelar() } else { cerrar() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(ocupado)
        .onAppear { nombre = almacen.nombreSugerido(.objeto) }
        .onChange(of: motor.estado) { terminar(motor.estado) }
        .alert("No se pudo crear el modelo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var formulario: some View {
        Form {
            if !Fotogrametria.disponible {
                Section {
                    Label("Este dispositivo no admite fotogrametría (se necesita un iPhone con LiDAR y iOS 17 o posterior).", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Tema.peligro)
                }
            }
            Section {
                PhotosPicker(selection: $seleccion, maxSelectionCount: Self.maximoFotos, matching: .images) {
                    Label(seleccion.isEmpty ? "Elegir fotos" : "\(seleccion.count) fotos elegidas", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                }
                TextField("Nombre", text: $nombre)
                Toggle("Recortar solo el objeto", isOn: $soloObjeto)
            } footer: {
                Text("Entre 20 y 200 fotos da el mejor resultado. \"Recortar solo el objeto\" quita el fondo; desactívalo para rincones o fachadas.")
            }
            Section("Cómo tomar las fotos") {
                consejo("arrow.triangle.2.circlepath", "Rodea el objeto completo, en 2 o 3 alturas distintas.")
                consejo("square.on.square", "Cada foto debe compartir unos dos tercios con la anterior.")
                consejo("sun.max", "Luz pareja y sin flash; evita sombras duras.")
                consejo("hand.raised", "Fotos nítidas: detente un instante en cada toma.")
                consejo("sparkles", "Lo brillante, transparente o negro liso sale mal.")
            }
            Section {
                Button {
                    Task { await comenzar() }
                } label: {
                    Label("Crear modelo 3D", systemImage: "cube.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(seleccion.count < Self.minimoFotos || !Fotogrametria.disponible)
            } footer: {
                Text(seleccion.count < Self.minimoFotos ? "Elige al menos \(Self.minimoFotos) fotos." : "El proceso tarda varios minutos y calienta el iPhone. Mantén la app abierta.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var progreso: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.system(size: 54))
                .foregroundStyle(Tema.acento)
                .symbolEffect(.pulse)
            if copiando {
                Text("Preparando fotos \(copiadas) de \(seleccion.count)…").font(.headline)
                ProgressView(value: Double(copiadas), total: Double(max(seleccion.count, 1)))
            } else if case .procesando(let fraccion) = motor.estado {
                Text(motor.etapa).font(.headline).multilineTextAlignment(.center)
                ProgressView(value: fraccion)
                Text("\(Int(fraccion * 100)) %").font(.title2.monospacedDigit().bold())
                if motor.omitidas > 0 {
                    Text("\(motor.omitidas) fotos no se pudieron usar").font(.footnote).foregroundStyle(Tema.apagado)
                }
            }
            Text("No cierres la app ni bloquees el iPhone.")
                .font(.footnote)
                .foregroundStyle(Tema.apagado)
            Spacer()
        }
        .padding(32)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func consejo(_ icono: String, _ texto: String) -> some View {
        Label(texto, systemImage: icono).font(.subheadline)
    }

    /// Copies the picked photos into a temporary folder (Object Capture reads a
    /// folder of images) and starts the reconstruction.
    @MainActor
    private func comenzar() async {
        copiando = true
        copiadas = 0
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("Fotogrametria-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            for (i, item) in seleccion.enumerated() {
                if let datos = try await item.loadTransferable(type: Data.self) {
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    try datos.write(to: carpeta.appendingPathComponent(String(format: "foto_%04d.%@", i, ext)))
                }
                copiadas = i + 1
            }
            carpetaFotos = carpeta
            var nuevo = Proyecto(nombre: nombre.isEmpty ? almacen.nombreSugerido(.objeto) : nombre, tipo: .objeto)
            nuevo.fotos = seleccion.count
            let destino = try almacen.preparar(nuevo)
            proyecto = nuevo
            copiando = false
            motor.procesar(carpeta: carpeta, salida: destino.appendingPathComponent(ArchivoProyecto.modeloUSDZ.rawValue), soloObjeto: soloObjeto)
        } catch {
            copiando = false
            limpiar()
            self.error = error.localizedDescription
        }
    }

    private func terminar(_ estado: Fotogrametria.Estado) {
        switch estado {
        case .terminado:
            guard var proyecto else { return }
            // The first photo becomes the cover and thumbnail.
            if let carpetaFotos,
               let primera = try? FileManager.default.contentsOfDirectory(at: carpetaFotos, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
               let imagen = UIImage(contentsOfFile: primera.path) {
                try? imagen.reducida(a: 1600).jpegData(compressionQuality: 0.85)?.write(to: almacen.url(.foto, de: proyecto))
                try? imagen.reducida(a: 400).jpegData(compressionQuality: 0.8)?.write(to: almacen.url(.miniatura, de: proyecto))
            }
            proyecto.fecha = Date()
            try? almacen.guardar(proyecto)
            limpiarTemporales()
            alGuardar(proyecto)
        case .error(let mensaje):
            limpiar()
            error = mensaje
        default:
            break
        }
    }

    private func cancelar() {
        motor.cancelar()
        copiando = false
        limpiar()
    }

    /// Drops the temporary photos and the unfinished project folder.
    private func limpiar() {
        limpiarTemporales()
        if let proyecto { try? FileManager.default.removeItem(at: almacen.carpeta(proyecto)) }
        proyecto = nil
    }

    private func limpiarTemporales() {
        if let carpetaFotos { try? FileManager.default.removeItem(at: carpetaFotos) }
        carpetaFotos = nil
    }
}
