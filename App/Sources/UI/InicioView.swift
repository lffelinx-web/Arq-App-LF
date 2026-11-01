import SwiftUI

/// Home: the three capture modes on top and the saved projects below.
struct InicioView: View {
    @Environment(Almacen.self) private var almacen
    @State private var captura: TipoProyecto?
    @State private var ruta: [Proyecto] = []
    @State private var filtro: TipoProyecto?
    @State private var ajustes = false
    @State private var aviso: String?

    private var visibles: [Proyecto] {
        guard let filtro else { return almacen.proyectos }
        return almacen.proyectos.filter { $0.tipo == filtro }
    }

    var body: some View {
        NavigationStack(path: $ruta) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Escaneo arquitectura")
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    modos
                    proyectos
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Escaneo arquitectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The big title lives in the content so it can shrink to fit.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ajustes = true } label: { Image(systemName: "gearshape") }
                }
            }
            .navigationDestination(for: Proyecto.self) { DetalleView(proyecto: $0) }
        }
        .fullScreenCover(item: $captura) { tipo in
            ConPermisoCamara {
                switch tipo {
                case .cuarto: PantallaCuarto(alGuardar: abrir)
                case .malla: PantallaMalla(alGuardar: abrir)
                case .medidas: PantallaMedicion(alGuardar: abrir)
                }
            }
            .environment(almacen)
        }
        .sheet(isPresented: $ajustes) { AjustesView() }
        .alert("No disponible", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aviso ?? "")
        }
    }

    private var modos: some View {
        VStack(spacing: 12) {
            BotonModo(
                titulo: "Escanear cuarto",
                detalle: "Plano con muros, puertas, ventanas y muebles. Exporta USDZ, PDF y JSON.",
                icono: "square.split.bottomrightquarter",
                color: Tema.acento
            ) { abrirCaptura(.cuarto) }
            HStack(spacing: 12) {
                BotonModo(titulo: "Escaneo 3D", detalle: "Malla LiDAR de cualquier espacio u objeto.", icono: "cube.transparent", color: Tema.azul, compacto: true) {
                    abrirCaptura(.malla)
                }
                BotonModo(titulo: "Medir", detalle: "Distancias punto a punto en AR.", icono: "ruler", color: Tema.verde, compacto: true) {
                    abrirCaptura(.medidas)
                }
            }
        }
    }

    private var proyectos: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Proyectos").font(.title3.bold())
                Spacer()
                Menu {
                    Picker("Filtro", selection: $filtro) {
                        Text("Todos").tag(TipoProyecto?.none)
                        ForEach(TipoProyecto.allCases, id: \.self) { Text($0.nombre).tag(TipoProyecto?.some($0)) }
                    }
                } label: {
                    Label(filtro?.nombre ?? "Todos", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                }
            }
            if visibles.isEmpty {
                Tarjeta {
                    VStack(spacing: 8) {
                        Image(systemName: "viewfinder").font(.largeTitle).foregroundStyle(Tema.apagado)
                        Text("Aún no hay escaneos").font(.headline)
                        Text("Elige un modo arriba para empezar.").font(.subheadline).foregroundStyle(Tema.apagado)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(visibles) { proyecto in
                        NavigationLink(value: proyecto) { CeldaProyecto(proyecto: proyecto) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { almacen.eliminar(proyecto) } label: { Label("Eliminar", systemImage: "trash") }
                            }
                    }
                }
            }
        }
    }

    private func abrirCaptura(_ tipo: TipoProyecto) {
        switch tipo {
        case .cuarto where !Capacidades.roomPlan:
            aviso = "El escaneo de cuartos necesita un iPhone o iPad con LiDAR."
        case .malla where !Capacidades.mallaLiDAR:
            aviso = "El escaneo 3D necesita un iPhone o iPad con LiDAR."
        case .medidas where !Capacidades.realidadAumentada:
            aviso = "Este dispositivo no tiene realidad aumentada."
        default:
            captura = tipo
        }
    }

    private func abrir(_ proyecto: Proyecto) {
        captura = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ruta = [proyecto] }
    }
}

extension TipoProyecto: Identifiable {
    var id: String { rawValue }
}

private struct BotonModo: View {
    let titulo: String
    let detalle: String
    let icono: String
    let color: Color
    var compacto = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icono)
                    .font(.system(size: compacto ? 22 : 28, weight: .semibold))
                    .foregroundStyle(Tema.fondo)
                    .frame(width: compacto ? 44 : 54, height: compacto ? 44 : 54)
                    .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(titulo).font(compacto ? .headline : .title3.bold()).foregroundStyle(Tema.texto)
                Text(detalle).font(.caption).foregroundStyle(Tema.apagado).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: compacto ? 150 : 0, alignment: .topLeading)
            .background(
                LinearGradient(colors: [color.opacity(0.18), Tema.superficie], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CeldaProyecto: View {
    @Environment(Almacen.self) private var almacen
    let proyecto: Proyecto

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Tema.superficie2
                if let imagen = UIImage(contentsOfFile: almacen.url(.miniatura, de: proyecto).path) {
                    Image(uiImage: imagen).resizable().scaledToFill()
                } else {
                    Image(systemName: proyecto.tipo.icono).font(.largeTitle).foregroundStyle(Tema.color(proyecto.tipo))
                }
            }
            .frame(height: 120)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(proyecto.nombre).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: proyecto.tipo.icono)
                    Text(proyecto.tipo.nombre)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Tema.color(proyecto.tipo))
                Text(Formato.fecha(proyecto.fecha)).font(.caption2).foregroundStyle(Tema.apagado)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.borde, lineWidth: 1))
    }
}
