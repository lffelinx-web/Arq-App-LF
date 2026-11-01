import SwiftUI

@main
struct ArqLFApp: App {
    @State private var almacen = Almacen()

    var body: some Scene {
        WindowGroup {
            InicioView()
                .environment(almacen)
                .preferredColorScheme(.dark)
                .tint(Tema.acento)
        }
    }
}
