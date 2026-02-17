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
        let lines = block.components(separatedBy: "\n")
        var declaredEventType: String? = nil
        var dataLines: [String] = []

        for line in lines {
            if line.hasPrefix("event:") {
                var eventType = String(line.dropFirst("event:".count))
                if eventType.hasPrefix(" ") {
                    eventType.removeFirst()
                }
                declaredEventType = eventType.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if line.hasPrefix("data:") {
                var payloadLine = String(line.dropFirst("data:".count))
                if payloadLine.hasPrefix(" ") {
                    payloadLine.removeFirst()
                }
                dataLines.append(payloadLine)
            }
        }

        guard !dataLines.isEmpty else {
            return []
        }

        let payload = dataLines.joined(separator: "\n")
        if let event = parsePayload(payload, declaredEventType: declaredEventType) {
            return [event]
        }
        return []
    }

    private func parsePayload(_ payload: String, declaredEventType: String?) -> SSEEvent? {
        if payload.isEmpty || payload == "[DONE]" {
            return payload == "[DONE]" ? .done(nil) : nil
        }

        guard let jsonData = payload.data(using: .utf8) else {
            return nil
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let eventType = (json["type"] as? String) ?? declaredEventType
                guard let eventType = eventType else {
                    return nil
                }

                switch eventType {
                case "transcript.text.delta", "response.output_text.delta":
                    if let delta = json["delta"] as? String {
                        return .delta(delta)
                    }
                case "transcript.text.done", "response.output_text.done":
                    if let text = json["text"] as? String {
                        return .done(text)
                    }
                    if let text = json["delta"] as? String {
                        return .done(text)
                    }
                    return .done(nil)
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
