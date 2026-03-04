//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#endif

private struct MarkdownTableWebViewPreviewHost: View {
    @State private var contentHeight: CGFloat = 120
    @State private var contentWidth: CGFloat = 320

    private let previewTable = MarkdownTable(
        headers: ["Area", "Status", "Notes"],
        alignments: [.leading, .center, .leading],
        rows: [
            ["macOS", "✅", "Open With + drag/drop support"],
            ["iOS", "✅", "Files picker + detail/source toggle"],
            ["iPadOS", "✅", "Split view navigation + toolbar"]
        ]
    )

    var body: some View {
        MarkdownTableWebView(
            html: MarkdownTableHTMLBuilder.document(for: previewTable),
            contentHeight: $contentHeight,
            contentWidth: $contentWidth
        )
        .frame(width: min(contentWidth, 500), height: max(contentHeight, 44))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .padding(20)
    }
}

#Preview("Table WebView") {
    MarkdownTableWebViewPreviewHost()
}

#if os(iOS)
struct MarkdownTableWebView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    @Binding var contentWidth: CGFloat

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var contentHeight: Binding<CGFloat>
        var contentWidth: Binding<CGFloat>
        var lastHTML: String?

        init(contentHeight: Binding<CGFloat>, contentWidth: Binding<CGFloat>) {
            self.contentHeight = contentHeight
            self.contentWidth = contentWidth
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            requestSizeUpdate(from: webView)
        }

        func requestSizeUpdate(from webView: WKWebView) {
            webView.evaluateJavaScript("""
            (function() {
              const table = document.querySelector('table');
              const h = (table && table.getBoundingClientRect) ? Math.ceil(table.getBoundingClientRect().height) : (document.documentElement.scrollHeight || document.body.scrollHeight || 44);
              const w = (table && table.scrollWidth) ? table.scrollWidth : (document.documentElement.scrollWidth || document.body.scrollWidth || 120);
              return { height: h, width: w };
            })()
            """) { [weak self] result, _ in
                guard let self else { return }
                if let dictionary = result as? [String: Any] {
                    self.applyTableSize(from: dictionary)
                } else if let value = result as? CGFloat {
                    DispatchQueue.main.async {
                        self.contentHeight.wrappedValue = max(44, value)
                    }
                } else if let number = result as? NSNumber {
                    DispatchQueue.main.async {
                        self.contentHeight.wrappedValue = max(44, CGFloat(truncating: number))
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "size" else { return }
            if let dictionary = message.body as? [String: Any] {
                applyTableSize(from: dictionary)
            } else if let value = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.contentHeight.wrappedValue = max(44, value)
                }
            } else if let number = message.body as? NSNumber {
                DispatchQueue.main.async {
                    self.contentHeight.wrappedValue = max(44, CGFloat(truncating: number))
                }
            }
        }

        private func applyTableSize(from dictionary: [String: Any]) {
            let heightValue = (dictionary["height"] as? NSNumber)?.doubleValue ?? 44
            let widthValue = (dictionary["width"] as? NSNumber)?.doubleValue ?? 120
            DispatchQueue.main.async {
                self.contentHeight.wrappedValue = max(44, CGFloat(heightValue))
                self.contentWidth.wrappedValue = max(120, CGFloat(widthValue))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight, contentWidth: $contentWidth) }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "size")
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.contentWidth = $contentWidth
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            context.coordinator.requestSizeUpdate(from: webView)
        }
    }
}
#elseif os(macOS)
struct MarkdownTableWebView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    @Binding var contentWidth: CGFloat

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var contentHeight: Binding<CGFloat>
        var contentWidth: Binding<CGFloat>
        var lastHTML: String?

        init(contentHeight: Binding<CGFloat>, contentWidth: Binding<CGFloat>) {
            self.contentHeight = contentHeight
            self.contentWidth = contentWidth
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            requestSizeUpdate(from: webView)
        }

        func requestSizeUpdate(from webView: WKWebView) {
            webView.evaluateJavaScript("""
            (function() {
              const table = document.querySelector('table');
              const h = (table && table.getBoundingClientRect) ? Math.ceil(table.getBoundingClientRect().height) : (document.documentElement.scrollHeight || document.body.scrollHeight || 44);
              const w = (table && table.scrollWidth) ? table.scrollWidth : (document.documentElement.scrollWidth || document.body.scrollWidth || 120);
              return { height: h, width: w };
            })()
            """) { [weak self] result, _ in
                guard let self else { return }
                if let dictionary = result as? [String: Any] {
                    self.applyTableSize(from: dictionary)
                } else if let value = result as? CGFloat {
                    DispatchQueue.main.async {
                        self.contentHeight.wrappedValue = max(44, value)
                    }
                } else if let number = result as? NSNumber {
                    DispatchQueue.main.async {
                        self.contentHeight.wrappedValue = max(44, CGFloat(truncating: number))
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "size" else { return }
            if let dictionary = message.body as? [String: Any] {
                applyTableSize(from: dictionary)
            } else if let value = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.contentHeight.wrappedValue = max(44, value)
                }
            } else if let number = message.body as? NSNumber {
                DispatchQueue.main.async {
                    self.contentHeight.wrappedValue = max(44, CGFloat(truncating: number))
                }
            }
        }

        private func applyTableSize(from dictionary: [String: Any]) {
            let heightValue = (dictionary["height"] as? NSNumber)?.doubleValue ?? 44
            let widthValue = (dictionary["width"] as? NSNumber)?.doubleValue ?? 120
            DispatchQueue.main.async {
                self.contentHeight.wrappedValue = max(44, CGFloat(heightValue))
                self.contentWidth.wrappedValue = max(120, CGFloat(widthValue))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight, contentWidth: $contentWidth) }

    func makeNSView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "size")
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.contentWidth = $contentWidth
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            context.coordinator.requestSizeUpdate(from: webView)
        }
    }
}
#endif
