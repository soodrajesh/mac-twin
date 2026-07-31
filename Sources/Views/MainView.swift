import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: DupeModel

    var body: some View {
        Group {
            if model.isScanning {
                ScanningView()
            } else if model.hasScanned {
                ResultsView()
            } else {
                StartView()
            }
        }
    }
}
