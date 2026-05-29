import Foundation
import PDFKit
#if canImport(Vision)
import Vision
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct PDFConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .pdf
    private let root: URL

    public init(root: URL, sourceId: String) {
        self.root = root
        self.sourceId = sourceId
    }

    public func enumerate() throws -> [SourceItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [SourceItem] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "pdf" {
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: modifiedAt))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        guard let document = PDFDocument(url: item.uri) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var pages: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(ocr(page: page))
            } else {
                pages.append(text)
            }
        }

        let body = pages.joined(separator: "\n\n")
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? item.uri.deletingPathExtension().lastPathComponent

        return ExtractedDocument(
            id: item.id,
            title: title,
            text: body,
            contentHash: ContentHash.of(body),
            meta: ["pages": String(document.pageCount)]
        )
    }

    private func ocr(page: PDFPage) -> String {
        #if canImport(Vision) && canImport(AppKit)
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(
            of: CGSize(width: bounds.width * 2, height: bounds.height * 2),
            for: .mediaBox
        )
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        #else
        return ""
        #endif
    }
}
