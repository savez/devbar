import AppKit

/// Selettore di cartelle (solo directory).
@MainActor
enum FolderPicker {
    static func choose(multiple: Bool, prompt: String) -> [String] {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = multiple
        p.prompt = prompt
        guard p.runModal() == .OK else { return [] }
        return p.urls.map(\.path)
    }
}
