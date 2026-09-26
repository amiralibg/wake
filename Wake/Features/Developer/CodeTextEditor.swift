import AppKit
import SwiftUI

/// An editable, monospaced NSTextView for code: JSON, HTML, storage values.
///
/// SwiftUI's `TextEditor` inherits macOS's text substitutions, so typing `"a"` turns
/// into `“a”` and `--` into `—`, which silently corrupts JSON and markup. This turns
/// every substitution, spelling and grammar check, completion and prediction off.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 12

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        // Completion and prediction popovers also eat the next click (e.g. on Save).
        textView.isAutomaticTextCompletionEnabled = false
        textView.inlinePredictionType = .no
        if #available(macOS 15.0, *) { textView.mathExpressionCompletionType = .no }
        if #available(macOS 15.1, *) { textView.writingToolsBehavior = .none }
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
