import SwiftUI
import WebKit

/// 以 WKWebView 显示信件内容，高度随内容自动调整；信件本身的 JavaScript 一律停用
struct MailBodyView: UIViewRepresentable {
    let html: String
    let isPlainText: Bool
    @Binding var height: CGFloat
    var onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.dataDetectorTypes = [.link, .phoneNumber, .address, .calendarEvent]

        let controller = WKUserContentController()
        // 在独立的 content world 执行，信件内容无法干扰或呼叫它
        controller.addUserScript(WKUserScript(source: Self.sizeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        controller.add(WeakMessageHandler(context.coordinator), contentWorld: .defaultClient, name: "size")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let document = Self.document(html: html, plain: isPlainText)
        guard context.coordinator.loaded != document else { return }
        context.coordinator.loaded = document
        webView.loadHTMLString(document, baseURL: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MailBodyView
        var loaded: String?

        init(_ parent: MailBodyView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? Double, value > 0 else { return }
            let height = ceil(value)
            if abs(parent.height - height) > 1 {
                parent.height = height
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if url.scheme == "about" || url.scheme == "data" { return .allow }
            if action.navigationType == .linkActivated || action.targetFrame == nil {
                parent.onLink(url)
                return .cancel
            }
            // 允许 iframe 等子资源，但拦截主框架跳转
            return action.targetFrame?.isMainFrame == true ? .cancel : .allow
        }
    }

    /// WKUserContentController 会强引用 handler，用弱引用避免循环
    private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }

    private static let sizeScript = """
    (function() {
      var body = document.body, root = document.documentElement;
      function report() {
        var vw = window.innerWidth;
        if (!body.dataset.fitted && vw > 0) {
          var w = Math.max(body.scrollWidth, root.scrollWidth);
          if (w > vw + 2) { body.style.zoom = (vw / w).toFixed(4); }
          body.dataset.fitted = '1';
        }
        var h = Math.max(body.getBoundingClientRect().height * (parseFloat(body.style.zoom) || 1), body.scrollHeight * (parseFloat(body.style.zoom) || 1));
        window.webkit.messageHandlers.size.postMessage(h + 16);
      }
      new ResizeObserver(report).observe(body);
      Array.prototype.forEach.call(document.images, function(img) { img.addEventListener('load', report); });
      window.addEventListener('load', report);
      report();
    })();
    """

    static func document(html: String, plain: Bool) -> String {
        let scheme = plain ? "light dark" : "light"
        let content = plain
            ? "<div class=\"plain\">\(html.htmlEscaped.replacingOccurrences(of: "\n", with: "<br>"))</div>"
            : html
        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\(scheme)">
        <style>
          html, body { margin: 0; padding: 0; }
          body { padding: 4px 0 8px; font: -apple-system-body; font-family: -apple-system, sans-serif; -webkit-text-size-adjust: 100%; overflow-wrap: anywhere; word-break: break-word; }
          img { max-width: 100% !important; height: auto !important; }
          pre { white-space: pre-wrap; }
          blockquote { margin: 0 0 0 6px; padding-left: 10px; border-left: 2px solid #d1d5db; color: #6b7280; }
          .plain { line-height: 1.5; }
          .plain a, a { color: #0a84ff; }
          @media (prefers-color-scheme: dark) { .plain { color: #f2f2f7; } }
        </style>
        </head><body>\(content)</body></html>
        """
    }
}
