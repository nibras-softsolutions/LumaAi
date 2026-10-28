import SwiftUI

public struct MarkdownView: View {
    let content: String

    public init(_ content: String) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parseBlocks(), id: \.id) { block in
                switch block.type {
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .text(let text):
                    if let attributed = try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .font(LumaTypography.body)
                            .foregroundColor(.lumaPrimaryText)
                            .lineSpacing(3)
                    } else {
                        Text(text)
                            .font(LumaTypography.body)
                            .foregroundColor(.lumaPrimaryText)
                    }
                }
            }
        }
    }

    private struct ContentBlock: Identifiable {
        let id = UUID()
        enum BlockType {
            case text(String)
            case code(language: String, code: String)
        }
        let type: BlockType
    }

    private func parseBlocks() -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let pattern = "```([a-zA-Z0-9_-]*)\\n?([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.init(type: .text(content))]
        }

        let nsString = content as NSString
        var lastIndex = 0

        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let fullRange = match.range
            if fullRange.location > lastIndex {
                let textChunk = nsString.substring(with: NSRange(location: lastIndex, length: fullRange.location - lastIndex))
                if !textChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.init(type: .text(textChunk)))
                }
            }

            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let lang = langRange.location != NSNotFound ? nsString.substring(with: langRange) : ""
            let code = codeRange.location != NSNotFound ? nsString.substring(with: codeRange) : ""

            blocks.append(.init(type: .code(language: lang.isEmpty ? "code" : lang, code: code.trimmingCharacters(in: .newlines))))
            lastIndex = fullRange.location + fullRange.length
        }

        if lastIndex < nsString.length {
            let trailing = nsString.substring(with: NSRange(location: lastIndex, length: nsString.length - lastIndex))
            if !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.init(type: .text(trailing)))
            }
        }

        return blocks.isEmpty ? [.init(type: .text(content))] : blocks
    }
}

public struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Text(language.uppercased())
                    .font(LumaTypography.captionMedium)
                    .foregroundColor(.lumaSecondaryText)

                Spacer()

                Button(action: {
                    UIPasteboard.general.string = code
                    HapticFeedback.light()
                    withAnimation {
                        copied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            copied = false
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(LumaTypography.captionMedium)
                    .foregroundColor(copied ? .lumaSuccess : .lumaSecondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.lumaSurfaceElevated)

            Divider()

            // Code content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(LumaTypography.code)
                    .foregroundColor(.lumaPrimaryText)
                    .padding(14)
                    .textSelection(.enabled)
            }
            .background(Color.lumaCanvas)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.lumaBorder, lineWidth: 1)
        )
    }
}
