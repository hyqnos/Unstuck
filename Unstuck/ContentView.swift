import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        BrainMapView()
            .background(Color.black)          // window always dark
            .preferredColorScheme(.dark)      // glass refracts dark — not white
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Cluster.self, BrainItem.self], inMemory: true)
}
