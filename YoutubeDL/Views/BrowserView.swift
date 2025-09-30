import SwiftUI
import WebKit

struct BrowserView: View {
    @State private var address = ""
    @State private var url = URL(string: "https://instagram.com")

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("https://…", text: $address)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                Button("Go") {
                    guard !address.isEmpty else { return }
                    let string = address.hasPrefix("https://") ? address : "https://\(address)"
                    guard let newURL = URL(string: string) else { return }
                    url = newURL
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            WebViewRepresentable(url: url, handler: nil)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct WebSheet: Identifiable {
    let url: URL
    var id: URL { url }
}

struct WebViewSheet: View {
    let url: URL
    var onFoundURL: (URL) -> Void

    var body: some View {
        WebViewRepresentable(url: url) { found in
            onFoundURL(found)
        }
        .ignoresSafeArea()
    }
}

private let jsHandlerName = "yt_dl_handler"

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL?
    let handler: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: jsHandlerName)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url, uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let handler: ((URL) -> Void)?

        init(handler: ((URL) -> Void)?) {
            self.handler = handler
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let string = message.body as? String, let url = URL(string: string) {
                handler?(url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard handler != nil else { return }
            Task { @MainActor in
                let javascript = """
                (function() {
                  var v = document.querySelector('video');
                  if (!v) return null;
                  return v.currentSrc || v.src || null;
                })();
                """
                for _ in 0..<20 {
                    if let result = try? await webView.evaluateJavaScript(javascript),
                       let string = result as? String,
                       let url = URL(string: string) {
                        handler?(url)
                        break
                    }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
        }
    }
}
