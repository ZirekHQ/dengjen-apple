import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One piece of a speech request, in the order it is spoken.
public enum SpeechSegment: Equatable, Sendable {
    case text(String, Prosody)
    case pause(milliseconds: Int)
}

/// Turns the SSML of an `AVSpeechSynthesisProviderRequest` into text and pauses the engine can
/// speak. Prosody nests; `<sub alias>` speaks its alias; `<break>` becomes a pause; tags the
/// engine has no use for keep their text.
public enum SSML {
    /// The longest pause a single `<break>` produces.
    public static let maxPauseMilliseconds = 10_000

    public static func segments(from ssml: String) -> [SpeechSegment] {
        let builder = SegmentBuilder()
        let parser = XMLParser(data: Data(ssml.utf8))
        parser.delegate = builder
        if parser.parse() {
            return builder.finish()
        }
        let text = plainText(fromMalformed: ssml)
        return text.isEmpty ? [] : [.text(text, .neutral)]
    }

    /// Reads a `<break>` element's pause length.
    static func pauseMilliseconds(time: String?, strength: String?) -> Int {
        if let time = time?.trimmed.lowercased() {
            let milliseconds: Double?
            if time.hasSuffix("ms") {
                milliseconds = Double(time.dropLast(2))
            } else if time.hasSuffix("s") {
                milliseconds = Double(time.dropLast()).map { $0 * 1000 }
            } else {
                milliseconds = nil
            }
            if let milliseconds, milliseconds.isFinite {
                return Int(milliseconds.rounded().clamped(to: 0...Double(maxPauseMilliseconds)))
            }
        }
        switch strength?.trimmed.lowercased() {
        case "none": return 0
        case "x-weak": return 100
        case "weak": return 200
        case "strong": return 750
        case "x-strong": return 1200
        default: return 500
        }
    }

    /// Text that is not well-formed XML is spoken with anything tag-shaped removed.
    static func plainText(fromMalformed text: String) -> String {
        let withoutTags = text.replacingOccurrences(
            of: "<[^>]*>", with: " ", options: .regularExpression)
        let decoded = withoutTags
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        return collapseWhitespace(decoded)
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private final class SegmentBuilder: NSObject, XMLParserDelegate {
    private var segments: [SpeechSegment] = []
    private var prosodyStack: [Prosody] = [.neutral]
    private var text = ""
    /// Elements whose content is replaced or not spoken; their text is skipped while this is > 0.
    private var skipDepth = 0
    /// The open elements, so an end tag knows whether it closes a prosody or a skipped element.
    private var openElements: [String] = []

    private var prosody: Prosody { prosodyStack.last ?? .neutral }

    func finish() -> [SpeechSegment] {
        flushText()
        return segments
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = localName(elementName)
        openElements.append(name)
        if skipDepth > 0 {
            skipDepth += 1
            return
        }
        switch name {
        case "prosody":
            flushText()
            var next = prosody
            if let rate = attributes["rate"] {
                next.rate = ProsodyValue.rate(rate, inherited: next.rate)
            }
            if let pitch = attributes["pitch"] {
                next.pitch = ProsodyValue.pitch(pitch, inherited: next.pitch)
            }
            if let volume = attributes["volume"] {
                next.volume = ProsodyValue.volume(volume, inherited: next.volume)
            }
            prosodyStack.append(next)
        case "break":
            flushText()
            let milliseconds = SSML.pauseMilliseconds(
                time: attributes["time"], strength: attributes["strength"])
            appendPause(milliseconds)
        case "sub":
            text += " " + (attributes["alias"] ?? "") + " "
            skipDepth = 1
        case "p", "s":
            text += " "
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = openElements.popLast() ?? localName(elementName)
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }
        switch name {
        case "prosody":
            flushText()
            if prosodyStack.count > 1 {
                prosodyStack.removeLast()
            }
        case "p", "s":
            text += " "
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth == 0 {
            text += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if skipDepth == 0, let string = String(data: CDATABlock, encoding: .utf8) {
            text += string
        }
    }

    private func flushText() {
        let spoken = SSML.collapseWhitespace(text)
        text = ""
        guard !spoken.isEmpty else { return }
        if case .text(let previous, let previousProsody)? = segments.last, previousProsody == prosody {
            segments[segments.count - 1] = .text(previous + " " + spoken, prosody)
        } else {
            segments.append(.text(spoken, prosody))
        }
    }

    private func appendPause(_ milliseconds: Int) {
        guard milliseconds > 0 else { return }
        if case .pause(let previous)? = segments.last {
            let total = min(previous + milliseconds, SSML.maxPauseMilliseconds)
            segments[segments.count - 1] = .pause(milliseconds: total)
        } else {
            segments.append(.pause(milliseconds: milliseconds))
        }
    }

    private func localName(_ name: String) -> String {
        (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
    }
}
