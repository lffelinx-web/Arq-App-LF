import SwiftUI
import UIKit

/// Dark, drafting-table palette with an amber accent.
enum Tema {
    static let fondo = Color(hex: 0x12161C)
    static let superficie = Color(hex: 0x1A2029)
    static let superficie2 = Color(hex: 0x232B36)
    static let borde = Color(hex: 0x2F3A48)
    static let texto = Color(hex: 0xE8EDF3)
    static let apagado = Color(hex: 0x8792A2)
    static let acento = Color(hex: 0xF4A63C)
    static let azul = Color(hex: 0x5AB4FF)
    static let verde = Color(hex: 0x4CC38A)
    static let peligro = Color(hex: 0xE5534B)

    static let uiAcento = UIColor(hex: 0xF4A63C)

    static func color(_ tipo: TipoProyecto) -> Color {
        switch tipo {
        case .cuarto: return acento
        case .malla: return azul
        case .medidas: return verde
        case .objeto: return Color(hex: 0xB38CF0)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

/// Rounded card used across the app.
struct Tarjeta<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido

    var body: some View {
        contenido
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Tema.borde, lineWidth: 1))
    }
}

/// A label/value row for the data sheets.
struct FilaDato: View {
    let titulo: String
    let valor: String
    var icono: String?

    var body: some View {
        HStack {
            if let icono {
                Image(systemName: icono).foregroundStyle(Tema.acento).frame(width: 22)
            }
            Text(titulo).foregroundStyle(Tema.apagado)
            Spacer()
            Text(valor).font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(Tema.texto)
        }
        .font(.subheadline)
    }
}

/// Round translucent button for the capture screens.
struct BotonCaptura: View {
    let icono: String
    var titulo: String?
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(spacing: 4) {
                Image(systemName: icono).font(.title3.weight(.semibold))
                if let titulo { Text(titulo).font(.caption2.weight(.semibold)) }
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// Small pill shown over the camera.
struct Pastilla: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
