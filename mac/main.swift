// GlassPermission — pop-up "Liquid Glass" pour les demandes d'autorisation de Claude Code.
//
// Lancé par le hook `PermissionRequest` de Claude Code :
//   - lit la demande (JSON) sur stdin
//   - affiche une pop-up flottante en verre en haut de l'écran
//   - renvoie la décision (allow / deny) sur stdout, ou rien du tout
//     pour laisser Claude Code poser la question dans le terminal.
//
// Compilation : swiftc -O main.swift -o GlassPermission

import AppKit
import Combine
import SwiftUI

// MARK: - Lecture de la demande

struct PermissionRequest {
    let toolName: String
    let toolLabel: String
    let symbol: String
    let summary: String?   // phrase courte (ex. description d'une commande Bash)
    let detail: String     // contenu technique (commande, chemin, URL…)
    let project: String

    init(json: [String: Any]) {
        let tool = json["tool_name"] as? String ?? "Outil"
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let cwd = json["cwd"] as? String ?? FileManager.default.currentDirectoryPath
        toolName = tool
        project = URL(fileURLWithPath: cwd).lastPathComponent

        func str(_ key: String) -> String? {
            guard let v = input[key] as? String, !v.isEmpty else { return nil }
            return v
        }

        switch tool {
        case "Bash":
            toolLabel = "Exécuter une commande"
            symbol = "terminal.fill"
            summary = str("description")
            detail = str("command") ?? Self.pretty(input)
        case "Edit", "MultiEdit":
            toolLabel = "Modifier un fichier"
            symbol = "pencil"
            summary = nil
            detail = str("file_path") ?? Self.pretty(input)
        case "Write":
            toolLabel = "Créer un fichier"
            symbol = "doc.badge.plus"
            summary = nil
            detail = str("file_path") ?? Self.pretty(input)
        case "NotebookEdit":
            toolLabel = "Modifier un notebook"
            symbol = "book.pages"
            summary = nil
            detail = str("notebook_path") ?? Self.pretty(input)
        case "WebFetch":
            toolLabel = "Ouvrir une page web"
            symbol = "globe"
            summary = str("prompt")
            detail = str("url") ?? Self.pretty(input)
        case "WebSearch":
            toolLabel = "Rechercher sur le web"
            symbol = "magnifyingglass"
            summary = nil
            detail = str("query") ?? Self.pretty(input)
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                toolLabel = parts.count >= 3 ? "\(parts[1]) · \(parts[2...].joined(separator: "_"))" : tool
                symbol = "puzzlepiece.extension.fill"
            } else {
                toolLabel = tool
                symbol = "wrench.and.screwdriver.fill"
            }
            summary = nil
            detail = Self.pretty(input)
        }
    }

    static func pretty(_ obj: [String: Any]) -> String {
        guard !obj.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "—" }
        return s
    }
}

// MARK: - Réponse au hook

enum Decision {
    case allow, deny, terminal

    func emit() -> Never {
        switch self {
        case .allow:
            Self.write(["behavior": "allow"])
        case .deny:
            Self.write(["behavior": "deny",
                        "message": "L'utilisateur a refusé cette action depuis la pop-up."])
        case .terminal:
            break // aucune sortie → Claude Code affiche sa demande habituelle
        }
        exit(0)
    }

    private static func write(_ decision: [String: Any]) {
        let out: [String: Any] = ["hookSpecificOutput": [
            "hookEventName": "PermissionRequest",
            "decision": decision,
        ]]
        if let data = try? JSONSerialization.data(withJSONObject: out),
           let s = String(data: data, encoding: .utf8) {
            print(s)
            fflush(stdout)
        }
    }
}

// MARK: - Style "Liquid Glass" (macOS 26) avec repli sur les matériaux classiques

private let corner: CGFloat = 28

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
    }
}

struct GlassButton: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
    }
}

// Orange "Claude"
private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

// MARK: - Vue

struct PermissionView: View {
    // Pas de @State : ses macros ne sont livrées qu'avec Xcode, pas avec les
    // outils en ligne de commande. L'état vit dans `Controller`, qui redessine la vue.
    let request: PermissionRequest
    let timeout: Int
    let remaining: Int
    let appeared: Bool
    let onDecision: (Decision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let summary = request.summary {
                Text(summary)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailBox
            buttons
        }
        .padding(18)
        .frame(width: 460)
        .modifier(GlassCard())
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .scaleEffect(appeared ? 1 : 0.9, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -16)
        .padding(30) // marge pour l'ombre
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: request.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(LinearGradient(colors: [claudeOrange.opacity(0.95), claudeOrange.opacity(0.7)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.6))

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude demande une autorisation")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(request.toolLabel)  ·  \(request.project)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Anneau de compte à rebours
            ZStack {
                Circle().stroke(.primary.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(timeout, 1)))
                    .stroke(claudeOrange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Text("\(remaining)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 26, height: 26)
        }
    }

    private var detailBox: some View {
        Text(request.detail)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(8)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { decide(.terminal) } label: {
                Label("Terminal", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Laisser Claude Code poser la question dans le terminal")

            Spacer()

            Button { decide(.deny) } label: {
                Text("Refuser").frame(minWidth: 72)
            }
            .modifier(GlassButton(prominent: false))
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            Button { decide(.allow) } label: {
                Text("Autoriser").fontWeight(.semibold).frame(minWidth: 84)
            }
            .modifier(GlassButton(prominent: true))
            .tint(claudeOrange)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func decide(_ d: Decision) { onDecision(d) }
}

// MARK: - Style "toast" de jeu vidéo (en bas à droite, glisse vers le haut)

private let toastAccent = Color(red: 0.58, green: 0.76, blue: 0.24)
private let toastBgTop = Color(red: 0.17, green: 0.21, blue: 0.26)
private let toastBgBottom = Color(red: 0.09, green: 0.11, blue: 0.14)

struct ToastView: View {
    let request: PermissionRequest
    let timeout: Int
    let remaining: Int
    let appeared: Bool
    let onDecision: (Decision) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: request.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(claudeOrange)
                    .frame(width: 58, height: 58)
                    .background(Color.black.opacity(0.55))
                    .overlay(Rectangle().strokeBorder(toastAccent, lineWidth: 2))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(toastAccent)
                    Text("demande une autorisation")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.6))
                    Text(request.toolLabel.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(toastAccent)
                        .lineLimit(1)
                    Text(request.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.75))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(12)

            HStack(spacing: 8) {
                Text(request.project)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.45))
                    .lineLimit(1)
                Spacer()
                toastButton("Refuser", key: "⌫", primary: false) { onDecision(.deny) }
                toastButton("Autoriser", key: "↩", primary: true) { onDecision(.allow) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            // Barre de temps restant
            Rectangle()
                .fill(toastAccent)
                .frame(height: 2)
                .scaleEffect(x: CGFloat(remaining) / CGFloat(max(timeout, 1)), anchor: .leading)
                .animation(.linear(duration: 1), value: remaining)
        }
        .frame(width: 380)
        .background(LinearGradient(colors: [toastBgTop, toastBgBottom], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .offset(y: appeared ? 0 : 240) // caché sous le bord de la fenêtre, puis glisse vers le haut
        .padding(EdgeInsets(top: 30, leading: 30, bottom: 16, trailing: 16))
    }

    private func toastButton(_ title: String, key: String, primary: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).fontWeight(.semibold)
                Text(key).opacity(0.6)
            }
            .font(.system(size: 11))
            .foregroundStyle(primary ? Color.black : Color(white: 0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(primary ? toastAccent : Color.white.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - État, compte à rebours et animations

enum PopupStyle: String {
    case toast, glass
}

@MainActor
final class Controller {
    let request: PermissionRequest
    let timeout: Int
    let style: PopupStyle
    private var remaining: Int
    private var appeared = false
    private var done = false
    private var timer: Timer?
    var host: NSHostingView<AnyView>!

    init(request: PermissionRequest, timeout: Int, style: PopupStyle) {
        self.request = request
        self.timeout = timeout
        self.style = style
        self.remaining = timeout
    }

    func makeView() -> AnyView {
        let onDecision: (Decision) -> Void = { [weak self] d in self?.decide(d) }
        switch style {
        case .toast:
            return AnyView(ToastView(request: request, timeout: timeout, remaining: remaining,
                                     appeared: appeared, onDecision: onDecision))
        case .glass:
            return AnyView(PermissionView(request: request, timeout: timeout, remaining: remaining,
                                          appeared: appeared, onDecision: onDecision))
        }
    }

    private func render(_ animation: Animation?) {
        withAnimation(animation) { host.rootView = makeView() }
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.appeared = true
            self.render(self.style == .toast ? .easeOut(duration: 0.4)
                                             : .spring(response: 0.45, dampingFraction: 0.72))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Raccourcis clavier : Entrée = autoriser, Effacer / Suppr / Échap = refuser
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let decision: Decision?
            switch event.keyCode {
            case 36, 76: decision = .allow        // Entrée, Entrée du pavé numérique
            case 51, 117, 53: decision = .deny    // Effacer (⌫), Suppr (⌦), Échap
            default: decision = nil
            }
            guard let decision else { return event }
            MainActor.assumeIsolated { self?.decide(decision) }
            return nil
        }
    }

    private func tick() {
        guard !done else { return }
        remaining -= 1
        render(.linear(duration: 1))
        if remaining <= 0 { decide(.terminal) }
    }

    func decide(_ d: Decision) {
        guard !done else { return }
        done = true
        timer?.invalidate()
        appeared = false
        let out = style == .toast ? 0.3 : 0.18
        render(.easeIn(duration: out))
        DispatchQueue.main.asyncAfter(deadline: .now() + out + 0.02) { d.emit() }
    }
}

// MARK: - Fenêtre flottante transparente

final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Point d'entrée

@main
struct GlassPermissionApp {
    @MainActor static func main() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let request = PermissionRequest(json: json)
        let env = ProcessInfo.processInfo.environment
        let seconds = Int(env["GLASS_TIMEOUT"] ?? "") ?? 90
        // Style : "toast" (par défaut) ou "glass". Choix via GLASS_STYLE ou le fichier ~/.claude/glass-permission/style
        let styleFile = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/glass-permission/style")
        let styleName = env["GLASS_STYLE"]
            ?? (try? String(contentsOfFile: styleFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let style = PopupStyle(rawValue: styleName.lowercased()) ?? .toast

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // pas d'icône dans le Dock

        let controller = Controller(request: request, timeout: seconds, style: style)
        let host = NSHostingView(rootView: controller.makeView())
        controller.host = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let panel = GlassPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .fullSizeContentView],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // l'ombre est dessinée par SwiftUI
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.contentView = host

        // Sur l'écran où se trouve la souris :
        //   toast → en bas à droite (au-dessus du Dock), glass → en haut au centre
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            switch style {
            case .toast:
                panel.isMovableByWindowBackground = false
                panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width, y: frame.minY))
            case .glass:
                panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height + 18))
            }
        }

        NSSound(named: style == .toast ? "Pop" : "Glass")?.play()
        panel.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        controller.start()
        app.run()
    }
}
