#!/usr/bin/env swift

import AppKit
import Foundation
import Vision

struct TextObservation: Codable {
    let text: String
    let confidence: Float
    let x: Double
    let yFromTop: Double
    let width: Double
    let height: Double
    let pixelX: Double
    let pixelYFromTop: Double
    let pixelWidth: Double
    let pixelHeight: Double
}

struct ImageTextGeometry: Codable {
    let schemaVersion: Int
    let path: String
    let pixelWidth: Int
    let pixelHeight: Int
    let observations: [TextObservation]
}

guard (2...3).contains(CommandLine.arguments.count) else {
    FileHandle.standardError.write(Data("usage: extract_text_geometry.swift IMAGE [OUTPUT.json]\n".utf8))
    exit(64)
}

let inputPath = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
guard
    let image = NSImage(contentsOfFile: inputPath),
    let representation = image.representations.first,
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("unable to decode image: \(inputPath)\n".utf8))
    exit(65)
}

let pixelWidth = representation.pixelsWide
let pixelHeight = representation.pixelsHigh
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.recognitionLanguages = inputPath.contains("chinese-")
    ? ["zh-Hans", "en-US"]
    : ["en-US", "zh-Hans"]

do {
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
    let observations = (request.results ?? []).compactMap { observation -> TextObservation? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let box = observation.boundingBox
        let top = 1 - box.maxY
        return TextObservation(
            text: candidate.string,
            confidence: candidate.confidence,
            x: box.minX,
            yFromTop: top,
            width: box.width,
            height: box.height,
            pixelX: box.minX * Double(pixelWidth),
            pixelYFromTop: top * Double(pixelHeight),
            pixelWidth: box.width * Double(pixelWidth),
            pixelHeight: box.height * Double(pixelHeight)
        )
    }.sorted {
        if abs($0.yFromTop - $1.yFromTop) > 0.005 { return $0.yFromTop < $1.yFromTop }
        return $0.x < $1.x
    }

    let result = ImageTextGeometry(
        schemaVersion: 1,
        path: inputPath,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        observations: observations
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var encoded = try encoder.encode(result)
    encoded.append(Data("\n".utf8))
    if CommandLine.arguments.count == 3 {
        try encoded.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    } else {
        FileHandle.standardOutput.write(encoded)
    }
} catch {
    FileHandle.standardError.write(Data("Vision failed: \(error)\n".utf8))
    exit(66)
}
