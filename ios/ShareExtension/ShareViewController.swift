import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// RunThru Share Extension — receives shared content and writes it to the
/// App Group container for the main app to pick up on foreground resume.
///
/// Supported types: plain text, HTML, URLs, PDFs, and EPUBs.
/// Communication with the main app is via a shared JSON file in the
/// App Group container (`group.com.mgmacri.runthru`).
class ShareViewController: SLComposeServiceViewController {

    private let appGroupIdentifier = "group.com.mgmacri.runthru"

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    handleFile(provider: provider, type: "pdfFile", ext: "pdf",
                               typeIdentifier: UTType.pdf.identifier)
                    return
                } else if provider.hasItemConformingToTypeIdentifier("org.idpf.epub-container") {
                    handleFile(provider: provider, type: "epubFile", ext: "epub",
                               typeIdentifier: "org.idpf.epub-container")
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    handleURL(provider: provider)
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                    handleText(provider: provider, type: "htmlText",
                               typeIdentifier: UTType.html.identifier)
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    handleText(provider: provider, type: "text",
                               typeIdentifier: UTType.plainText.identifier)
                    return
                }
            }
        }

        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    // MARK: - Content Handlers

    private func handleText(provider: NSItemProvider, type: String, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            var text: String?
            if let str = item as? String {
                text = str
            } else if let data = item as? Data {
                text = String(data: data, encoding: .utf8)
            }

            if let text = text {
                self.writeSharedContent([
                    "type": type,
                    "data": text,
                    "mimeType": type == "htmlText" ? "text/html" : "text/plain",
                    "receivedAt": ISO8601DateFormatter().string(from: Date())
                ])
            }

            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func handleURL(provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            if let url = item as? URL {
                self.writeSharedContent([
                    "type": "url",
                    "data": url.absoluteString,
                    "receivedAt": ISO8601DateFormatter().string(from: Date())
                ])
            }

            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func handleFile(provider: NSItemProvider, type: String, ext: String, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            guard let self = self,
                  let url = item as? URL else {
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                return
            }

            // Copy file to App Group container for the main app to access.
            guard let containerURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: self.appGroupIdentifier) else {
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                return
            }

            let fileName = url.lastPathComponent.isEmpty
                ? "shared_\(Int(Date().timeIntervalSince1970)).\(ext)"
                : url.lastPathComponent
            let destURL = containerURL.appendingPathComponent(fileName)

            do {
                // Remove existing file if present.
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: url, to: destURL)

                self.writeSharedContent([
                    "type": type,
                    "data": destURL.path,
                    "title": fileName,
                    "mimeType": type == "pdfFile" ? "application/pdf" : "application/epub+zip",
                    "receivedAt": ISO8601DateFormatter().string(from: Date())
                ])
            } catch {
                NSLog("RunThru ShareExtension: Failed to copy file: \(error)")
            }

            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    // MARK: - App Group Communication

    /// Writes shared content as a JSON file to the App Group container.
    /// The main RunThru app reads this file on foreground resume.
    private func writeSharedContent(_ content: [String: Any]) {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            NSLog("RunThru ShareExtension: Cannot access App Group container")
            return
        }

        let fileURL = containerURL.appendingPathComponent("shared_content.json")

        do {
            let data = try JSONSerialization.data(withJSONObject: content, options: .prettyPrinted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("RunThru ShareExtension: Failed to write shared content: \(error)")
        }
    }
}
