import SwiftUI

/// Colours for drawing the plan on screen (dark) or on paper (light).
struct EstiloPlano {
    var fondo: Color
    var piso: Color
    var muro: Color
    var mueble: Color
    var texto: Color
    var puerta: Color
    var ventana: Color

    static let pantalla = EstiloPlano(
        fondo: Tema.fondo, piso: Tema.acento.opacity(0.10), muro: Tema.texto, mueble: Tema.apagado,
        texto: Tema.acento, puerta: Tema.verde, ventana: Tema.azul
    )
    static let papel = EstiloPlano(
        fondo: .white, piso: Color(hex: 0xF3EFE7), muro: Color(hex: 0x1B1F24), mueble: Color(hex: 0x8A8F96),
        texto: Color(hex: 0xB0620A), puerta: Color(hex: 0x1E8A55), ventana: Color(hex: 0x1F6FC2)
    )
}

/// Top-down floor plan with wall dimensions, drawn to fit its frame.
struct PlanoDibujo: View {
    let plano: PlanoPlanta
    var unidad: Unidad = .metros
    var estilo: EstiloPlano = .pantalla
    var cotas = true
    var muebles = true

    var body: some View {
        Canvas { ctx, size in
            guard let l = plano.limites else { return }
            let anchoVista = Double(size.width), altoVista = Double(size.height)
            let margen: Double = cotas ? 44 : 16
            let ancho = max(l.ancho, 0.1), alto = max(l.alto, 0.1)
            let escala: Double = max(1, min((anchoVista - margen * 2) / ancho, (altoVista - margen * 2) / alto))
            let dx: Double = (anchoVista - ancho * escala) / 2
            let dy: Double = (altoVista - alto * escala) / 2
            func p(_ q: Punto2D) -> CGPoint { CGPoint(x: dx + (q.x - l.minX) * escala, y: dy + (q.y - l.minY) * escala) }
            func trazo(_ puntos: [Punto2D], cerrado: Bool) -> Path {
                var path = Path()
                guard let primero = puntos.first else { return path }
                path.move(to: p(primero))
                for q in puntos.dropFirst() { path.addLine(to: p(q)) }
                if cerrado { path.closeSubpath() }
                return path
            }

            for piso in plano.pisos {
                ctx.fill(trazo(piso, cerrado: true), with: .color(estilo.piso))
            }

            if muebles {
                for m in plano.muebles {
                    let forma = trazo(m.esquinas, cerrado: true)
                    ctx.fill(forma, with: .color(estilo.mueble.opacity(0.18)))
                    ctx.stroke(forma, with: .color(estilo.mueble), lineWidth: 1)
                    if escala * min(m.ancho, m.fondo) > 28.0 {
                        ctx.draw(Text(m.nombre).font(.system(size: 9, weight: .medium)).foregroundColor(estilo.mueble), at: p(m.centro))
                    }
                }
            }

            let grosor = CGFloat(max(3, min(8, escala * 0.12)))
            for muro in plano.muros {
                ctx.stroke(trazo([muro.a, muro.b], cerrado: false), with: .color(estilo.muro), style: StrokeStyle(lineWidth: grosor, lineCap: .square))
            }

            for a in plano.aberturas {
                let linea = trazo([a.a, a.b], cerrado: false)
                ctx.stroke(linea, with: .color(estilo.fondo), style: StrokeStyle(lineWidth: grosor + 1, lineCap: .butt))
                switch a.tipo {
                case .puerta:
                    ctx.stroke(linea, with: .color(estilo.puerta), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    // Door leaf swinging 90°.
                    let inicio = p(a.a), fin = p(a.b)
                    let radio = CGFloat(hypot(Double(fin.x - inicio.x), Double(fin.y - inicio.y)))
                    let angulo = atan2(Double(fin.y - inicio.y), Double(fin.x - inicio.x))
                    var arco = Path()
                    arco.move(to: inicio)
                    arco.addArc(center: inicio, radius: radio, startAngle: .radians(angulo), endAngle: .radians(angulo - .pi / 2), clockwise: true)
                    arco.closeSubpath()
                    ctx.stroke(arco, with: .color(estilo.puerta.opacity(0.7)), lineWidth: 1)
                case .ventana:
                    ctx.stroke(linea, with: .color(estilo.ventana), style: StrokeStyle(lineWidth: grosor * 0.6))
                    ctx.stroke(linea, with: .color(estilo.fondo), style: StrokeStyle(lineWidth: max(1, grosor * 0.2)))
                case .vano:
                    ctx.stroke(linea, with: .color(estilo.mueble), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }

            if cotas {
                let centroide = Punto2D((l.minX + l.maxX) / 2, (l.minY + l.maxY) / 2)
                for muro in plano.muros where muro.longitud > 0.2 {
                    let medio = Punto2D.medio(muro.a, muro.b)
                    let dir = (muro.b - muro.a) * (1 / muro.longitud)
                    var normal = Punto2D(-dir.y, dir.x)
                    let haciaFuera = medio - centroide
                    if normal.x * haciaFuera.x + normal.y * haciaFuera.y < 0 { normal = normal * -1 }
                    let posicion = p(medio)
                    let lugar = CGPoint(x: Double(posicion.x) + normal.x * 16, y: Double(posicion.y) + normal.y * 16)
                    var angulo = atan2(dir.y, dir.x)
                    if angulo > .pi / 2 { angulo -= .pi } else if angulo < -.pi / 2 { angulo += .pi }
                    var c = ctx
                    c.translateBy(x: lugar.x, y: lugar.y)
                    c.rotate(by: .radians(angulo))
                    c.draw(Text(Formato.longitud(muro.longitud, unidad)).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundColor(estilo.texto), at: .zero)
                }

                // Scale bar: 1 m.
                let barra = Path { path in
                    path.move(to: CGPoint(x: 12, y: altoVista - 14))
                    path.addLine(to: CGPoint(x: 12 + escala, y: altoVista - 14))
                }
                ctx.stroke(barra, with: .color(estilo.muro), lineWidth: 2)
                ctx.draw(Text(unidad == .pies ? "1 m (3' 3\")" : "1 m").font(.system(size: 9)).foregroundColor(estilo.muro), at: CGPoint(x: 12 + escala / 2, y: altoVista - 24))
            }
        }
        .background(estilo.fondo)
    }
}

/// Plan with pinch to zoom and drag to pan.
struct PlanoInteractivo: View {
    let plano: PlanoPlanta
    var unidad: Unidad
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var desplazamiento: CGSize = .zero
    @State private var desplazamientoBase: CGSize = .zero
    @State private var conMuebles = true

    var body: some View {
        PlanoDibujo(plano: plano, unidad: unidad, muebles: conMuebles)
            .scaleEffect(zoom)
            .offset(desplazamiento)
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture()
                        .onChanged { zoom = min(8, max(0.5, zoomBase * $0.magnification)) }
                        .onEnded { _ in zoomBase = zoom },
                    DragGesture()
                        .onChanged { desplazamiento = CGSize(width: desplazamientoBase.width + $0.translation.width, height: desplazamientoBase.height + $0.translation.height) }
                        .onEnded { _ in desplazamientoBase = desplazamiento }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    zoom = 1; zoomBase = 1; desplazamiento = .zero; desplazamientoBase = .zero
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                Toggle(isOn: $conMuebles) { Image(systemName: "sofa") }
                    .toggleStyle(.button)
                    .padding(10)
            }
    }
}
