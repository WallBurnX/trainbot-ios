import Foundation
import ImageIO
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count >= 2 else {
    fail("Usage: swift scripts/ocr_ddx.swift IMAGE [IMAGE ...]")
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        FileHandle.standardError.write(Data(("Cannot read \(path)\n").utf8))
        continue
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ru-RU", "en-US"]
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.006

    do {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
    } catch {
        FileHandle.standardError.write(Data(("OCR failed for \(path): \(error)\n").utf8))
        continue
    }

    let width = Double(image.width)
    let height = Double(image.height)
    let observations = (request.results ?? []).sorted {
        let rowDifference = abs($0.boundingBox.midY - $1.boundingBox.midY)
        if rowDifference > 0.01 {
            return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }

    var rows: [[String: Any]] = []
    for observation in observations {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let box = observation.boundingBox
        rows.append([
            "text": candidate.string,
            "confidence": candidate.confidence,
            "x": box.minX * width,
            "y": (1.0 - box.maxY) * height,
            "width": box.width * width,
            "height": box.height * height,
        ])
    }

    let result: [String: Any] = [
        "file": path,
        "image_width": image.width,
        "image_height": image.height,
        "observations": rows,
    ]
    let data = try! JSONSerialization.data(withJSONObject: result, options: [])
    print(String(data: data, encoding: .utf8)!)
}
