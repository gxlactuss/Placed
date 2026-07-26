import Foundation
import PDFKit
import UIKit
import Vision

/// Pulls plain text out of a resume the student picked, entirely on-device.
///
/// Nothing here touches the network. That's the point: the free Gemini tier
/// trains on submitted content and permits human review, and a resume is about
/// the densest PII a student owns. Doing OCR locally means only the projects
/// section — already stripped of contact details by `ResumeParser` — ever
/// leaves the phone. It's also free, where sending the page as an image would
/// cost one of the five Gemini requests a minute allows.
enum ResumeTextExtractor {

    enum ExtractionError: LocalizedError {
        case unreadableFile
        case unsupportedType
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .unreadableFile: "That file couldn't be opened."
            case .unsupportedType: "Upload a PDF, PNG or JPEG."
            case .noTextFound: "No text could be read from that file."
            }
        }
    }

    /// Reads `url` (PDF or image) and returns its text.
    ///
    /// Runs off the main actor — Vision on a multi-page PDF is slow enough to
    /// drop frames if it ran inline.
    static func extractText(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            // Files handed over by `fileImporter` live outside our sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let text: String
            switch url.pathExtension.lowercased() {
            case "pdf":
                text = try extractFromPDF(url)
            case "png", "jpg", "jpeg", "heic", "heif", "tiff":
                guard let image = UIImage(contentsOfFile: url.path),
                      let cgImage = image.cgImage else { throw ExtractionError.unreadableFile }
                text = try recognizeText(in: cgImage)
            default:
                throw ExtractionError.unsupportedType
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ExtractionError.noTextFound }
            return trimmed
        }.value
    }

    // MARK: - PDF

    /// Prefers the PDF's own text layer and only falls back to OCR when there
    /// isn't one.
    ///
    /// Almost every resume is exported from Word, Docs or LaTeX and carries a
    /// real text layer, which is *lossless* — OCR of the same page would only
    /// introduce misreads. Scanned or image-only resumes have no such layer, and
    /// those are the ones Vision earns its keep on.
    private static func extractFromPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadableFile }

        var embedded = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let string = page.string {
                embedded += string + "\n"
            }
        }
        // A handful of stray glyphs means the "text layer" is really just page
        // furniture, so treat that as absent and OCR the pages instead.
        if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
            return embedded
        }

        var ocr = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let cgImage = render(page) {
                ocr += (try? recognizeText(in: cgImage)).map { $0 + "\n" } ?? ""
            }
        }
        return ocr
    }

    /// Rasterises a page for Vision. 2× because OCR accuracy on 10–11pt resume
    /// body text falls off badly at native PDF resolution.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Flip: PDF space is y-up, UIKit's context is y-down.
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }

    // MARK: - Vision

    private static func recognizeText(in cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return "" }

        // Vision returns observations in detection order, not reading order, so
        // a two-column resume comes back interleaved. Sorting top-to-bottom then
        // left-to-right restores something a language model can follow.
        // Vision's origin is bottom-left, hence the descending y.
        let sorted = observations.sorted { lhs, rhs in
            let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
            // Same line within a small tolerance — order by x instead.
            if abs(dy) < 0.01 { return lhs.boundingBox.minX < rhs.boundingBox.minX }
            return dy > 0
        }

        return sorted
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
