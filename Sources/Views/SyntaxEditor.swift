import SwiftUI
import AppKit

enum SyntaxLanguage {
    case javascript
    case json
}

// MARK: - NSTextView subclass with syntax highlighting

final class SyntaxTextView: NSTextView {
    var language: SyntaxLanguage = .javascript
    private var isHighlighting = false

    override func didChangeText() {
        super.didChangeText()
        guard !isHighlighting else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applyHighlighting()
        }
    }

    func applyHighlighting() {
        guard !isHighlighting, let storage = textStorage else { return }
        let str = storage.string
        guard !str.isEmpty else { return }

        isHighlighting = true
        defer { isHighlighting = false }

        let saved = selectedRange()
        let full = NSRange(location: 0, length: (str as NSString).length)

        storage.beginEditing()
        storage.setAttributes([
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        ], range: full)

        switch language {
        case .javascript: highlightJS(storage: storage, str: str)
        case .json:       highlightJSON(storage: storage, str: str)
        }

        storage.endEditing()
        setSelectedRange(saved)
    }

    // MARK: JS highlighting

    private func highlightJS(storage: NSTextStorage, str: String) {
        // Multi-line comments
        paint(#"/\*[\s\S]*?\*/"#, color: .comment, in: storage, str: str)
        // Single-line comments
        paint(#"//[^\n]*"#, color: .comment, in: storage, str: str)
        // Template literals
        paint(#"`(?:[^`\\]|\\.)*`"#, color: .string, in: storage, str: str)
        // Double-quoted strings
        paint(#""(?:[^"\\]|\\.)*""#, color: .string, in: storage, str: str)
        // Single-quoted strings
        paint(#"'(?:[^'\\]|\\.)*'"#, color: .string, in: storage, str: str)
        // Keywords
        let kw = "function|return|var|let|const|if|else|for|while|do|break|continue"
            + "|new|delete|typeof|instanceof|in|of|true|false|null|undefined"
            + "|this|class|extends|import|export|default|try|catch|finally|throw|switch|case"
        paint("\\b(\(kw))\\b", color: .keyword, in: storage, str: str)
        // Numbers
        paint(#"\b\d+(\.\d+)?\b"#, color: .number, in: storage, str: str)
    }

    // MARK: JSON highlighting

    private func highlightJSON(storage: NSTextStorage, str: String) {
        // All strings first (values)
        paint(#""(?:[^"\\]|\\.)*""#, color: .string, in: storage, str: str)
        // JSON keys (strings followed by colon) — override string color
        paint(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, color: .jsonKey, in: storage, str: str)
        // Numbers
        paint(#"-?\b\d+(\.\d+)?\b"#, color: .number, in: storage, str: str)
        // Booleans and null
        paint(#"\b(true|false|null)\b"#, color: .keyword, in: storage, str: str)
    }

    // MARK: Helper

    private func paint(_ pattern: String, color: NSColor, in storage: NSTextStorage, str: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else { return }
        let nsStr = str as NSString
        let range = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: range) {
            storage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

// MARK: - Semantic color palette

private extension NSColor {
    static let comment = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.65, blue: 0.40, alpha: 1)
            : NSColor(red: 0.18, green: 0.48, blue: 0.18, alpha: 1)
    }
    static let string = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.95, green: 0.55, blue: 0.35, alpha: 1)
            : NSColor(red: 0.72, green: 0.18, blue: 0.05, alpha: 1)
    }
    static let keyword = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.78, green: 0.52, blue: 0.96, alpha: 1)
            : NSColor(red: 0.50, green: 0.10, blue: 0.78, alpha: 1)
    }
    static let number = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.75, blue: 1.00, alpha: 1)
            : NSColor(red: 0.10, green: 0.40, blue: 0.75, alpha: 1)
    }
    static let jsonKey = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.90, blue: 0.85, alpha: 1)
            : NSColor(red: 0.05, green: 0.50, blue: 0.55, alpha: 1)
    }
}

// MARK: - Fullscreen sheet

struct FullscreenEditorView: View {
    @Binding var text: String
    let language: SyntaxLanguage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 12) {
                Image(systemName: language == .json ? "curlybraces" : "chevron.left.forwardslash.chevron.right")
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            SyntaxEditor(text: $text, language: language)
        }
        .frame(minWidth: 760, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Expandable wrapper (SyntaxEditor + expand button)

struct ExpandableCodeEditor: View {
    @Binding var text: String
    var language: SyntaxLanguage = .javascript
    var title: String = "编辑代码"
    var minHeight: CGFloat = 160

    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SyntaxEditor(text: $text, language: language)
                .frame(minHeight: minHeight)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            Button {
                isExpanded = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .padding(5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("全屏编辑")
        }
        .sheet(isPresented: $isExpanded) {
            FullscreenEditorView(text: $text, language: language, title: title)
        }
    }
}

// MARK: - SwiftUI wrapper

struct SyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    var language: SyntaxLanguage = .javascript

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SyntaxTextView()
        textView.language = language
        textView.delegate = context.coordinator

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.string = text
        textView.applyHighlighting()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SyntaxTextView else { return }
        guard textView.string != text else { return }
        let saved = textView.selectedRange()
        textView.string = text
        textView.applyHighlighting()
        let len = (text as NSString).length
        if saved.location <= len {
            textView.setSelectedRange(NSRange(location: min(saved.location, len), length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxEditor
        init(_ parent: SyntaxEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
