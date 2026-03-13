import AppKit

struct ExportService {
    struct Snapshot {
        let systemPrompt: String?
        let temperature: Double
        let timestamp: Date
        let panels: [PanelSnapshot]
    }

    struct PanelSnapshot {
        let provider: String
        let model: String
        let messages: [ChatMessage]
        let inputTokens: Int?
        let outputTokens: Int?
        let duration: TimeInterval?
    }

    // MARK: - Markdown

    static func toMarkdown(_ snap: Snapshot) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var md = "# Prompt Workbench Comparison\n"
        md += "**Date:** \(df.string(from: snap.timestamp))  \n"
        md += "**Temperature:** \(snap.temperature)\n\n"

        if let sys = snap.systemPrompt, !sys.isEmpty {
            md += "## System Prompt\n> \(sys.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
        }

        for panel in snap.panels {
            md += "---\n\n"
            md += "## \(panel.provider) — \(panel.model)\n"
            var meta: [String] = []
            if let d = panel.duration { meta.append(String(format: "%.1fs", d)) }
            if let i = panel.inputTokens { meta.append("\(i) in") }
            if let o = panel.outputTokens { meta.append("\(o) out") }
            if !meta.isEmpty { md += "*\(meta.joined(separator: " · "))*\n\n" }

            for msg in panel.messages {
                switch msg.role {
                case "user":
                    md += "**You:**\n\(msg.content)\n\n"
                case "assistant":
                    md += "\(msg.content)\n\n"
                default:
                    break
                }
            }
        }

        return md
    }

    // MARK: - JSON

    static func toJSON(_ snap: Snapshot) -> String {
        let df = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "timestamp": df.string(from: snap.timestamp),
            "temperature": snap.temperature,
        ]
        if let sys = snap.systemPrompt { dict["system_prompt"] = sys }

        dict["providers"] = snap.panels.map { p -> [String: Any] in
            var d: [String: Any] = [
                "provider": p.provider,
                "model": p.model,
                "messages": p.messages.map { ["role": $0.role, "content": $0.content] },
            ]
            if let i = p.inputTokens { d["input_tokens"] = i }
            if let o = p.outputTokens { d["output_tokens"] = o }
            if let dur = p.duration { d["duration_seconds"] = dur }
            return d
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Clipboard

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - File Save

    static func saveToFile(_ content: String, defaultName: String, fileType: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = fileType == "json"
            ? [.json]
            : [.plainText]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
