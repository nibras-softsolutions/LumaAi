import Foundation

public enum ServerSentEvent: Equatable {
    case token(String)
    case image(ImageAttachment)
    case error(String)
    case done
    case unknown(event: String, data: String)
}

public final class SSEParser {
    private var buffer = ""
    private var currentEvent = "token"
    private var currentData = ""

    public init() {}

    public func feed(_ text: String) -> [ServerSentEvent] {
        buffer += text
        var events: [ServerSentEvent] = []
        let endsWithNewline = buffer.hasSuffix("\n")
        let lines = buffer.components(separatedBy: "\n")
        let countToProcess = endsWithNewline ? lines.count : max(0, lines.count - 1)

        for i in 0..<countToProcess {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("event:") {
                if !currentData.isEmpty {
                    let ev = parse(event: currentEvent, dataString: currentData)
                    events.append(ev)
                    currentData = ""
                }
                currentEvent = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("data:") {
                let dataContent = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let ev = parse(event: currentEvent, dataString: dataContent)
                events.append(ev)
                currentEvent = "token"
                currentData = ""
            } else if line.isEmpty {
                if !currentData.isEmpty || currentEvent == "done" {
                    let ev = parse(event: currentEvent, dataString: currentData)
                    events.append(ev)
                    currentEvent = "token"
                    currentData = ""
                }
            }
        }
        buffer = endsWithNewline ? "" : (lines.last ?? "")
        return events
    }

    public func parse(event: String, dataString: String) -> ServerSentEvent {
        let trimmedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedData = dataString.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmedEvent {
        case "token":
            if let data = trimmedData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return .token(text)
            }
            return .token(trimmedData)

        case "image":
            if let data = trimmedData.data(using: .utf8),
               let attachment = try? JSONDecoder().decode(ImageAttachment.self, from: data) {
                return .image(attachment)
            }
            return .unknown(event: trimmedEvent, data: trimmedData)

        case "error":
            if let data = trimmedData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                return .error(message)
            }
            return .error(trimmedData)

        case "done":
            return .done

        default:
            return .unknown(event: trimmedEvent, data: trimmedData)
        }
    }
}
