import SwiftUI

// MARK: - Cuarto (RoomPlan)

struct PantallaCuarto: View {
    var alGuardar: (Proyecto) -> Void

    var body: some View {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        CapturaCuarto(alGuardar: alGuardar)
        #else
        NoDisponible(mensaje: "El escaneo de cuartos necesita un dispositivo con LiDAR.")
        #endif
    }
}

#if canImport(RoomPlan) && !targetEnvironment(simulator)
private struct CapturaCuarto: View {
    var alGuardar: (Proyecto) -> Void
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var cerrar
    @StateObject private var escaner = CuartoRoomPlan()
    @State private var pidiendoNombre = false
    @State private var nombre = ""
    @State private var guardando = false
    @State private var error: String?

    var body: some View {
        ZStack {
            VistaUIKit(vista: escaner.vista).ignoresSafeArea()
            VStack {
                BarraCaptura(titulo: "Escanear cuarto") {
                    escaner.cancelar()
                    cerrar()
                }
                Pastilla(texto: indicacion)
                if !escaner.cuartos.isEmpty {
                    Pastilla(texto: escaner.cuartos.count == 1 ? "1 cuarto escaneado" : "\(escaner.cuartos.count) cuartos escaneados")
                }
                Spacer()
                controles.padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            if guardando { Guardando() }
        }
        .onAppear { escaner.iniciar() }
        .alert("Guardar escaneo", isPresented: $pidiendoNombre) {
            TextField("Nombre", text: $nombre)
            Button("Guardar") { guardar() }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var indicacion: String {
        switch escaner.estado {
        case .listo: return "Preparando…"
        case .escaneando:
            return escaner.cuartos.isEmpty
                ? "Recorre el cuarto apuntando a paredes, puertas, ventanas y muebles."
                : "Pasa al siguiente cuarto por la puerta y escanéalo igual."
        case .procesando: return "Procesando el cuarto…"
        case .terminado: return "Guarda el plano o toca Otro para agregar el siguiente cuarto; se unirán en un solo plano."
        case .error(let mensaje): return mensaje
        }
    }

    @ViewBuilder private var controles: some View {
        switch escaner.estado {
        case .escaneando:
            Button { escaner.detener() } label: {
                Label("Terminar cuarto", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(Tema.acento, in: Capsule())
                    .foregroundStyle(Tema.fondo)
            }
        case .procesando, .listo:
            ProgressView().tint(.white).padding()
        case .terminado, .error:
            HStack(spacing: 16) {
                BotonCaptura(icono: "arrow.counterclockwise", titulo: "Reiniciar") { escaner.iniciar() }
                if !escaner.cuartos.isEmpty {
                    BotonCaptura(icono: "plus.square.on.square", titulo: "Otro") { escaner.otroCuarto() }
                    Button {
                        nombre = almacen.nombreSugerido(.cuarto)
                        pidiendoNombre = true
                    } label: {
                        Label("Guardar", systemImage: "square.and.arrow.down.fill")
                            .font(.headline)
                            .padding(.horizontal, 28).padding(.vertical, 16)
                            .background(Tema.acento, in: Capsule())
                            .foregroundStyle(Tema.fondo)
                    }
                }
            }
        }
    }

    private func guardar() {
        let cuartos = escaner.cuartos
        guard !cuartos.isEmpty else { return }
        guardando = true
        Task { @MainActor in
            do {
                var proyecto = Proyecto(nombre: nombre.isEmpty ? almacen.nombreSugerido(.cuarto) : nombre, tipo: .cuarto)
                proyecto.cuartos = cuartos.count
                let carpeta = try almacen.preparar(proyecto)
                let plano = try await CuartoRoomPlan.guardar(cuartos, en: carpeta)
                try almacen.guardar(plano, de: proyecto)
                if let imagen = Exportacion.imagen(plano, tamano: CGSize(width: 400, height: 400)) {
                    try? imagen.jpegData(compressionQuality: 0.85)?.write(to: almacen.url(.miniatura, de: proyecto))
                }
                proyecto.fecha = Date()
                try almacen.guardar(proyecto)
                guardando = false
                alGuardar(proyecto)
            } catch {
                guardando = false
                self.error = error.localizedDescription
            }
        }
    }
}
#endif

// MARK: - Malla LiDAR

struct PantallaMalla: View {
    var alGuardar: (Proyecto) -> Void
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var cerrar
    @StateObject private var escaner = MallaLiDAR()
    @State private var pidiendoNombre = false
    @State private var nombre = ""
    @State private var guardando = false
    @State private var error: String?

    var body: some View {
        ZStack {
            VistaUIKit(vista: escaner.vista).ignoresSafeArea()
            VStack(spacing: 10) {
                BarraCaptura(titulo: "Escaneo 3D") {
                    escaner.pausar()
                    cerrar()
                }
                Pastilla(texto: escaner.escaneando ? escaner.aviso : "Escaneo en pausa")
                Pastilla(texto: "\(escaner.triangulos.formatted()) triángulos · \(escaner.fotos) fotos para color")
                Spacer()
                HStack(spacing: 18) {
                    BotonCaptura(icono: "arrow.counterclockwise", titulo: "Reiniciar") { escaner.iniciar() }
                    Button {
                        escaner.escaneando ? escaner.pausar() : escaner.reanudar()
                    } label: {
                        Image(systemName: escaner.escaneando ? "pause.fill" : "play.fill")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Tema.fondo)
                            .frame(width: 78, height: 78)
                            .background(Tema.azul, in: Circle())
                    }
                    BotonCaptura(icono: "checkmark", titulo: "Guardar") {
                        escaner.pausar()
                        nombre = almacen.nombreSugerido(.malla)
                        pidiendoNombre = true
                    }
                    .disabled(escaner.triangulos == 0)
                    .opacity(escaner.triangulos == 0 ? 0.5 : 1)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            if guardando { Guardando() }
        }
        .onAppear { escaner.iniciar() }
        .alert("Guardar escaneo", isPresented: $pidiendoNombre) {
            TextField("Nombre", text: $nombre)
            Button("Guardar") { guardar() }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func guardar() {
        guardando = true
        let piezas = escaner.piezas()
        let fotogramas = escaner.fotosTomadas()
        let captura = escaner.vista.snapshot()
        let proyectoBase = Proyecto(nombre: nombre.isEmpty ? almacen.nombreSugerido(.malla) : nombre, tipo: .malla)
        Task { @MainActor in
            do {
                let carpeta = try almacen.preparar(proyectoBase)
                let nombreArchivo = proyectoBase.nombre
                let totales = try await Task.detached(priority: .userInitiated) {
                    try MallaLiDAR.guardar(piezas, fotogramas: fotogramas, captura: captura, en: carpeta, nombre: nombreArchivo)
                }.value
                var proyecto = proyectoBase
                proyecto.vertices = totales.vertices
                proyecto.triangulos = totales.triangulos
                proyecto.fotos = fotogramas.count
                try almacen.guardar(proyecto)
                guardando = false
                alGuardar(proyecto)
            } catch {
                guardando = false
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Medición

struct PantallaMedicion: View {
    var alGuardar: (Proyecto) -> Void
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var cerrar
    @AppStorage("unidad") private var unidad: Unidad = .metros
    @StateObject private var medicion = Medicion()
    @State private var pidiendoNombre = false
    @State private var nombre = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            VistaUIKit(vista: medicion.vista).ignoresSafeArea()
            Mira(activa: medicion.apuntando)
            VStack(spacing: 10) {
                BarraCaptura(titulo: "Medir") {
                    medicion.pausar()
                    cerrar()
                }
                if let distancia = medicion.distanciaActual {
                    Text(Formato.longitud(distancia, unidad))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                } else if let error = medicion.error {
                    Pastilla(texto: error)
                } else {
                    Pastilla(texto: medicion.apuntando ? "Toca + para marcar el primer punto" : "Apunta a una superficie")
                }
                Spacer()
                if !medicion.medidas.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(medicion.medidas.reversed()) { medida in
                                Pastilla(texto: "\(medida.nombre): \(Formato.longitud(medida.metros, unidad))")
                            }
                        }
                    }
                }
                HStack(spacing: 18) {
                    BotonCaptura(icono: "arrow.uturn.backward", titulo: "Deshacer") { medicion.deshacer() }
                    Button { medicion.agregarPunto() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Tema.fondo)
                            .frame(width: 78, height: 78)
                            .background(medicion.apuntando ? Tema.verde : Color.gray, in: Circle())
                    }
                    .disabled(!medicion.apuntando)
                    BotonCaptura(icono: "checkmark", titulo: "Guardar") {
                        nombre = almacen.nombreSugerido(.medidas)
                        pidiendoNombre = true
                    }
                    .disabled(medicion.medidas.isEmpty)
                    .opacity(medicion.medidas.isEmpty ? 0.5 : 1)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            medicion.unidad = unidad
            medicion.iniciar()
        }
        .alert("Guardar medidas", isPresented: $pidiendoNombre) {
            TextField("Nombre", text: $nombre)
            Button("Guardar") { guardar() }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func guardar() {
        let captura = medicion.vista.snapshot()
        medicion.pausar()
        var proyecto = Proyecto(nombre: nombre.isEmpty ? almacen.nombreSugerido(.medidas) : nombre, tipo: .medidas)
        proyecto.medidas = medicion.medidas
        do {
            _ = try almacen.preparar(proyecto)
            try? captura.reducida(a: 1600).jpegData(compressionQuality: 0.85)?.write(to: almacen.url(.foto, de: proyecto))
            try? captura.reducida(a: 400).jpegData(compressionQuality: 0.8)?.write(to: almacen.url(.miniatura, de: proyecto))
            try almacen.guardar(proyecto)
            alGuardar(proyecto)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Shared pieces

private struct BarraCaptura: View {
    let titulo: String
    let cerrar: () -> Void

    var body: some View {
        HStack {
            Button(action: cerrar) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            Text(titulo).font(.headline).foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 8)
    }
}

/// Crosshair in the middle of the screen for the measuring tape.
private struct Mira: View {
    let activa: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(activa ? 0.9 : 0.4), lineWidth: 2).frame(width: 36, height: 36)
            Circle().fill(activa ? Tema.verde : .white.opacity(0.4)).frame(width: 6, height: 6)
        }
        .allowsHitTesting(false)
    }
}

private struct Guardando: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("Guardando…").font(.headline).foregroundStyle(.white)
            }
        }
    }
}

private struct NoDisponible: View {
    let mensaje: String
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor.fill").font(.largeTitle).foregroundStyle(Tema.apagado)
            Text(mensaje).multilineTextAlignment(.center)
            Button("Cerrar") { cerrar() }.buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.fondo)
    }
}
