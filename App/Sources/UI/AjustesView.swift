import SwiftUI

struct AjustesView: View {
    @AppStorage("unidad") private var unidad: Unidad = .metros
    @Environment(\.dismiss) private var cerrar

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Unidades") {
                    Picker("Medir en", selection: $unidad) {
                        ForEach(Unidad.allCases) { Text($0.nombre).tag($0) }
                    }
                }
                Section("Dispositivo") {
                    estado("Escaneo de cuartos (RoomPlan)", Capacidades.roomPlan)
                    estado("Malla LiDAR", Capacidades.mallaLiDAR)
                    estado("Realidad aumentada", Capacidades.realidadAumentada)
                }
                Section {
                    Text("Los proyectos se guardan en la app Archivos → En mi iPhone → Arq LF → Proyectos.")
                        .font(.footnote)
                        .foregroundStyle(Tema.apagado)
                }
                Section {
                    LabeledContent("Versión", value: version)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
        }
    }

    private func estado(_ titulo: String, _ disponible: Bool) -> some View {
        LabeledContent(titulo) {
            Image(systemName: disponible ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(disponible ? Tema.verde : Tema.apagado)
        }
    }
}
