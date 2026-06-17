//
//  LocalSVGIconView.swift
//  Carda
//

import Foundation
import SwiftUI

struct LocalSVGIconView: View {
    let fileName: String

    var body: some View {
        if let svg = LocalSVGIconCache.shared.icon(named: fileName) {
            Canvas { context, size in
                context.scaleBy(
                    x: size.width / svg.viewBox.width,
                    y: size.height / svg.viewBox.height
                )
                context.translateBy(x: -svg.viewBox.minX, y: -svg.viewBox.minY)

                for element in svg.elements {
                    if let fill = element.fill {
                        context.fill(element.path, with: .color(fill))
                    }
                    if let stroke = element.stroke {
                        context.stroke(
                            element.path,
                            with: .color(stroke),
                            style: StrokeStyle(
                                lineWidth: element.strokeWidth,
                                lineCap: element.lineCap,
                                lineJoin: element.lineJoin
                            )
                        )
                    }
                }
            }
        } else {
            Color.clear
        }
    }
}

private final class LocalSVGIconCache {
    static let shared = LocalSVGIconCache()

    private var icons: [String: ParsedSVGIcon] = [:]

    func icon(named fileName: String) -> ParsedSVGIcon? {
        if let icon = icons[fileName] {
            return icon
        }

        guard
            let url = Bundle.main.url(forResource: fileName, withExtension: "svg", subdirectory: "My icon")
                ?? Bundle.main.url(forResource: fileName, withExtension: "svg"),
            let source = try? String(contentsOf: url, encoding: .utf8),
            let icon = ParsedSVGIcon(source: source)
        else {
            return nil
        }

        icons[fileName] = icon
        return icon
    }
}

private struct ParsedSVGIcon {
    let viewBox: CGRect
    let elements: [SVGElement]

    init?(source: String) {
        guard let viewBox = Self.parseViewBox(source) else { return nil }
        self.viewBox = viewBox
        self.elements = Self.parseElements(source)
    }

    nonisolated private static func parseViewBox(_ source: String) -> CGRect? {
        guard let value = attribute("viewBox", in: source) else { return nil }
        let values = value
            .split { $0 == " " || $0 == "," }
            .compactMap { Double($0) }
        guard values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    nonisolated private static func parseElements(_ source: String) -> [SVGElement] {
        let pathElements = tags(named: "path", in: source).compactMap(SVGElement.path)
        let rectElements = tags(named: "rect", in: source).compactMap(SVGElement.rect)
        return pathElements + rectElements
    }

    nonisolated fileprivate static func tags(named name: String, in source: String) -> [String] {
        let pattern = "<\(name)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range, in: source) else { return nil }
            return String(source[range])
        }
    }

    nonisolated fileprivate static func attribute(_ name: String, in text: String) -> String? {
        let pattern = "\\b\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[valueRange])
    }
}

private struct SVGElement {
    let path: Path
    let fill: Color?
    let stroke: Color?
    let strokeWidth: CGFloat
    let lineCap: CGLineCap
    let lineJoin: CGLineJoin

    nonisolated static func path(from tag: String) -> SVGElement? {
        guard let d = ParsedSVGIcon.attribute("d", in: tag) else { return nil }
        var parser = SVGPathParser(d)
        guard let path = parser.parse() else { return nil }

        return SVGElement(
            path: path,
            fill: paintColor(named: ParsedSVGIcon.attribute("fill", in: tag), opacity: fillOpacity(in: tag)),
            stroke: paintColor(named: ParsedSVGIcon.attribute("stroke", in: tag), opacity: strokeOpacity(in: tag)),
            strokeWidth: CGFloat(Double(ParsedSVGIcon.attribute("stroke-width", in: tag) ?? "1") ?? 1),
            lineCap: lineCap(named: ParsedSVGIcon.attribute("stroke-linecap", in: tag)),
            lineJoin: lineJoin(named: ParsedSVGIcon.attribute("stroke-linejoin", in: tag))
        )
    }

    nonisolated static func rect(from tag: String) -> SVGElement? {
        guard
            let x = Double(ParsedSVGIcon.attribute("x", in: tag) ?? "0"),
            let y = Double(ParsedSVGIcon.attribute("y", in: tag) ?? "0"),
            let width = Double(ParsedSVGIcon.attribute("width", in: tag) ?? ""),
            let height = Double(ParsedSVGIcon.attribute("height", in: tag) ?? "")
        else {
            return nil
        }

        let rx = Double(ParsedSVGIcon.attribute("rx", in: tag) ?? "0") ?? 0
        let rect = CGRect(x: x, y: y, width: width, height: height)
        var path = Path(
            roundedRect: rect,
            cornerSize: CGSize(width: rx, height: rx),
            style: .continuous
        )

        if let transform = rotationTransform(in: tag) {
            path = path.applying(transform)
        }

        return SVGElement(
            path: path,
            fill: paintColor(named: ParsedSVGIcon.attribute("fill", in: tag), opacity: fillOpacity(in: tag)),
            stroke: paintColor(named: ParsedSVGIcon.attribute("stroke", in: tag), opacity: strokeOpacity(in: tag)),
            strokeWidth: CGFloat(Double(ParsedSVGIcon.attribute("stroke-width", in: tag) ?? "1") ?? 1),
            lineCap: lineCap(named: ParsedSVGIcon.attribute("stroke-linecap", in: tag)),
            lineJoin: lineJoin(named: ParsedSVGIcon.attribute("stroke-linejoin", in: tag))
        )
    }

    nonisolated private static func paintColor(named name: String?, opacity: Double) -> Color? {
        guard let name, name != "none" else { return nil }
        switch name {
        case "black":
            return Color.black.opacity(opacity)
        case "#141414":
            return Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255).opacity(opacity)
        default:
            return Color.black.opacity(opacity)
        }
    }

    nonisolated private static func fillOpacity(in tag: String) -> Double {
        Double(ParsedSVGIcon.attribute("fill-opacity", in: tag) ?? "1") ?? 1
    }

    nonisolated private static func strokeOpacity(in tag: String) -> Double {
        Double(ParsedSVGIcon.attribute("stroke-opacity", in: tag) ?? "1") ?? 1
    }

    nonisolated private static func lineCap(named name: String?) -> CGLineCap {
        switch name {
        case "round":
            .round
        case "square":
            .square
        default:
            .butt
        }
    }

    nonisolated private static func lineJoin(named name: String?) -> CGLineJoin {
        switch name {
        case "round":
            .round
        case "bevel":
            .bevel
        default:
            .miter
        }
    }

    nonisolated private static func rotationTransform(in tag: String) -> CGAffineTransform? {
        guard let transform = ParsedSVGIcon.attribute("transform", in: tag) else { return nil }
        let pattern = #"rotate\(([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: transform, range: NSRange(transform.startIndex..<transform.endIndex, in: transform)),
            match.numberOfRanges == 4,
            let degreesRange = Range(match.range(at: 1), in: transform),
            let xRange = Range(match.range(at: 2), in: transform),
            let yRange = Range(match.range(at: 3), in: transform),
            let degrees = Double(transform[degreesRange]),
            let x = Double(transform[xRange]),
            let y = Double(transform[yRange])
        else {
            return nil
        }

        return CGAffineTransform(translationX: x, y: y)
            .rotated(by: CGFloat(degrees * .pi / 180))
            .translatedBy(x: -x, y: -y)
    }
}

private struct SVGPathParser {
    private let tokens: [Token]
    private var index = 0
    private var currentPoint = CGPoint.zero
    private var subpathStart = CGPoint.zero

    init(_ d: String) {
        self.tokens = Self.tokenize(d)
    }

    mutating func parse() -> Path? {
        var path = Path()
        var command: Character?

        while index < tokens.count {
            if case let .command(nextCommand) = tokens[index] {
                command = nextCommand
                index += 1
            }

            guard let command else { return nil }

            switch command {
            case "M", "m":
                guard let point = readPoint(relative: command == "m") else { return nil }
                path.move(to: point)
                currentPoint = point
                subpathStart = point
                while hasNumber {
                    guard let linePoint = readPoint(relative: command == "m") else { return nil }
                    path.addLine(to: linePoint)
                    currentPoint = linePoint
                }
            case "L", "l":
                while hasNumber {
                    guard let point = readPoint(relative: command == "l") else { return nil }
                    path.addLine(to: point)
                    currentPoint = point
                }
            case "H", "h":
                while hasNumber {
                    guard let x = readNumber() else { return nil }
                    let point = CGPoint(x: command == "h" ? currentPoint.x + x : x, y: currentPoint.y)
                    path.addLine(to: point)
                    currentPoint = point
                }
            case "V", "v":
                while hasNumber {
                    guard let y = readNumber() else { return nil }
                    let point = CGPoint(x: currentPoint.x, y: command == "v" ? currentPoint.y + y : y)
                    path.addLine(to: point)
                    currentPoint = point
                }
            case "C", "c":
                while hasNumber {
                    guard
                        let control1 = readPoint(relative: command == "c"),
                        let control2 = readPoint(relative: command == "c"),
                        let point = readPoint(relative: command == "c")
                    else {
                        return nil
                    }
                    path.addCurve(to: point, control1: control1, control2: control2)
                    currentPoint = point
                }
            case "Z", "z":
                path.closeSubpath()
                currentPoint = subpathStart
            default:
                return nil
            }
        }

        return path
    }

    private var hasNumber: Bool {
        guard index < tokens.count else { return false }
        if case .number = tokens[index] {
            return true
        }
        return false
    }

    private mutating func readPoint(relative: Bool) -> CGPoint? {
        guard let x = readNumber(), let y = readNumber() else { return nil }
        if relative {
            return CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
        }
        return CGPoint(x: x, y: y)
    }

    private mutating func readNumber() -> CGFloat? {
        guard index < tokens.count else { return nil }
        guard case let .number(value) = tokens[index] else { return nil }
        index += 1
        return CGFloat(value)
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var i = d.startIndex

        while i < d.endIndex {
            let character = d[i]

            if character.isWhitespace || character == "," {
                i = d.index(after: i)
            } else if character.isLetter {
                tokens.append(.command(character))
                i = d.index(after: i)
            } else {
                let start = i
                i = d.index(after: i)
                while i < d.endIndex, isNumberCharacter(d[i], previous: d[d.index(before: i)]) {
                    i = d.index(after: i)
                }
                if let value = Double(d[start..<i]) {
                    tokens.append(.number(value))
                }
            }
        }

        return tokens
    }

    private static func isNumberCharacter(_ character: Character, previous: Character) -> Bool {
        if character.isNumber || character == "." {
            return true
        }
        if character == "-" || character == "+" {
            return previous == "e" || previous == "E"
        }
        return character == "e" || character == "E"
    }

    private enum Token {
        case command(Character)
        case number(Double)
    }
}
