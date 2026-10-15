import Foundation
import Vision
import ImageIO

// The region is x,y,width,height as fractions of the original image, from
// its top-left corner. OCR never sees pixels outside this rectangle.
guard CommandLine.arguments.count == 3 else {
    fputs("usage: InstrumentOCR IMAGE X,Y,WIDTH,HEIGHT\n", stderr)
    exit(1)
}
let fields = CommandLine.arguments[2].split(separator: ",", omittingEmptySubsequences: false)
guard fields.count == 4,
      let x = Double(fields[0]), let y = Double(fields[1]),
      let width = Double(fields[2]), let height = Double(fields[3]),
      [x, y, width, height].allSatisfy(\.isFinite),
      x >= 0, y >= 0, width > 0, height > 0,
      x + width <= 1.000002, y + height <= 1.000002 else {
    fputs("invalid OCR region\n", stderr)
    exit(1)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("cannot open image\n", stderr)
    exit(1)
}
let px = max(0, Int(floor(x * Double(image.width))))
let py = max(0, Int(floor(y * Double(image.height))))
let right = min(image.width, Int(ceil((x + width) * Double(image.width))))
let bottom = min(image.height, Int(ceil((y + height) * Double(image.height))))
let cropRect = CGRect(x: px, y: py, width: right - px, height: bottom - py)
guard cropRect.width >= 8, cropRect.height >= 8,
      let crop = image.cropping(to: cropRect) else {
    fputs("OCR region is too small\n", stderr)
    exit(1)
}

// Small screen digits benefit from an enlarged input, but enlargement cannot
// restore detail absent from the original photograph.
let scale = min(8.0, max(1.0, 360.0 / cropRect.width, 160.0 / cropRect.height))
let scaledWidth = Int((cropRect.width * scale).rounded())
let scaledHeight = Int((cropRect.height * scale).rounded())
guard let context = CGContext(data: nil, width: scaledWidth, height: scaledHeight,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("cannot prepare OCR crop\n", stderr)
    exit(1)
}
context.interpolationQuality = .high
context.draw(crop, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
guard let prepared = context.makeImage() else { exit(1) }
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages = ["en-US"]
do {
    try VNImageRequestHandler(cgImage: prepared, options: [:]).perform([request])
} catch {
    fputs("OCR failed: \(error)\n", stderr)
    exit(1)
}

struct Piece {
    let text: String
    let confidence: Float
    let box: CGRect
}
let pieces = (request.results ?? []).compactMap { observation -> Piece? in
    guard let candidate = observation.topCandidates(1).first,
          candidate.confidence >= 0.35 else { return nil }
    return Piece(text: candidate.string, confidence: candidate.confidence,
                 box: observation.boundingBox)
}.sorted { $0.box.midY > $1.box.midY }

// Vision sometimes separates a leading minus sign from the digits. Join
// fragments on the same display line. Labels and units are tolerated, but
// two numbers in the rectangle remain ambiguous and are rejected.
var lines: [[Piece]] = []
for piece in pieces {
    if let i = lines.firstIndex(where: { abs($0[0].box.midY - piece.box.midY) < 0.055 }) {
        lines[i].append(piece)
    } else {
        lines.append([piece])
    }
}
let pattern = try! NSRegularExpression(
    pattern: "(?<![A-Za-z0-9])[+-]?[ ]*(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+)(?![0-9])"
)
var values: [(String, Float)] = []
var ambiguous = false
for line in lines {
    let ordered = line.sorted { $0.box.minX < $1.box.minX }
    var text = ordered.map(\.text).joined(separator: " ")
    text = text.replacingOccurrences(of: "−", with: "-")
                 .replacingOccurrences(of: "–", with: "-")
                 .replacingOccurrences(of: "＋", with: "+")
                 .replacingOccurrences(of: "，", with: ",")
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = pattern.matches(in: text, range: range)
    if matches.count > 1 {
        ambiguous = true
        break
    }
    guard matches.count == 1,
          let matchRange = Range(matches[0].range, in: text) else { continue }
    let numericText = String(text[matchRange])
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ",", with: ".")
    guard let number = Double(numericText), number.isFinite else { continue }
    let confidence = ordered.map(\.confidence).reduce(0, +) / Float(ordered.count)
    values.append((String(number), confidence))
}
guard !ambiguous && values.count == 1 else { exit(2) }
print("\(values[0].0)\t\(values[0].1)")
