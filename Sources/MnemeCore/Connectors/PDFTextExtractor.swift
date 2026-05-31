import Foundation
import PDFKit
#if canImport(Vision)
import Vision
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct PDFTextExtraction: Sendable, Equatable {
    public let title: String?
    public let text: String
    public let pageCount: Int
}

public enum PDFTextExtractor {
    public static func extract(url: URL) throws -> PDFTextExtraction {
        guard let document = PDFDocument(url: url) else {
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

        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        return PDFTextExtraction(
            title: title,
            text: pages.joined(separator: "\n\n"),
            pageCount: document.pageCount
        )
    }

    private static func ocr(page: PDFPage) -> String {
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
