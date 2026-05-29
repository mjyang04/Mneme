import AppKit
import Foundation

enum PDFTestSupport {
    static func makeTextPDF(_ text: String, at url: URL) throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.beginPDFPage(nil)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 18)]
        ).draw(in: CGRect(x: 50, y: 50, width: 500, height: 700))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        data.write(to: url, atomically: true)
    }
}
