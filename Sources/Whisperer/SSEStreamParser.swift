import Foundation

enum SSEEvent: Equatable {
    case delta(String)
    case done(String?)
}

struct SSEStreamParser {
    private var buffer = ""

    mutating func feed(_ data: Data) -> [SSEEvent] {
        guard let chunk = String(data: data, encoding: .utf8) else {
            return []
        }

        buffer.append(chunk)
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        buffer = buffer.replacingOccurrences(of: "\r", with: "\n")

        var events: [SSEEvent] = []

        while let range = buffer.range(of: "\n\n") {
            let eventBlock = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            events.append(contentsOf: parseEventBlock(eventBlock))
        }

        return events
    }

    mutating func flush() -> [SSEEvent] {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            buffer = ""
            return []
        }

        buffer = ""
        return parseEventBlock(trimmed)
    }

    private func parseEventBlock(_ block: String) -> [SSEEvent] {
        var events: [SSEEvent] = []
        let lines = block.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("data:") else { continue }
            var payload = String(trimmedLine.dropFirst("data:".count))
            if payload.hasPrefix(" ") {
                payload.removeFirst()
            }
            if let event = parsePayload(payload) {
                events.append(event)
            }
        }

        return events
    }

    private func parsePayload(_ payload: String) -> SSEEvent? {
        if payload.isEmpty || payload == "[DONE]" {
            return payload == "[DONE]" ? .done(nil) : nil
        }

        guard let jsonData = payload.data(using: .utf8) else {
            return nil
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let type = json["type"] as? String {
                switch type {
                case "transcript.text.delta":
                    if let delta = json["delta"] as? String {
                        return .delta(delta)
                    }
                case "transcript.text.done":
                    return .done(json["text"] as? String)
                default:
                    return nil
                }
            }
        } catch {
            return nil
        }

        return nil
    }
}
