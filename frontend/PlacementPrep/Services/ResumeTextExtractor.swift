import Foundation
import PDFKit
import UIKit
import Vision

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

    static func extractText(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
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

    private static func extractFromPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadableFile }

        var embedded = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let string = page.string {
                embedded += string + "\n"
            }
        }
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

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }

    private static func recognizeText(in cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return "" }

        let sorted = observations.sorted { lhs, rhs in
            let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(dy) < 0.01 { return lhs.boundingBox.minX < rhs.boundingBox.minX }
            return dy > 0
        }

        return sorted
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
