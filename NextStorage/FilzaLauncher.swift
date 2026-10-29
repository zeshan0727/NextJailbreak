import Foundation
import SwiftUI
import UIKit

/// Opens the exact scanned path in a Filza edition that registers filza://.
/// Filza variants without URL scheme support cannot be deep linked.
@MainActor
final class FilzaLauncher: ObservableObject {
    @Published var showLinkFailure = false
    @Published var fallbackPath = ""

    func open(_ path: String) {
        let absolutePath = path.hasPrefix("/") ? path : "/" + path
        // Preserve directory separators while encoding spaces, #, ?, %, and Unicode.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#%")
        guard let escapedPath = absolutePath.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "filza://view" + escapedPath) else {
            handleFailure(for: absolutePath)
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] accepted in
            guard !accepted else { return }
            Task { @MainActor [weak self] in
                self?.handleFailure(for: absolutePath)
            }
        }
    }

    private func handleFailure(for path: String) {
        UIPasteboard.general.string = path
        fallbackPath = path
        showLinkFailure = true
    }
}

struct FilzaAction: View {
    @EnvironmentObject private var filza: FilzaLauncher
    let path: String
    var label: String = "Open in Filza"

    var body: some View {
        Button {
            filza.open(path)
        } label: {
            Label(label, systemImage: "arrow.up.forward.app")
        }
    }
}
