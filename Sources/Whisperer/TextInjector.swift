import Foundation
import Cocoa
import Carbon

class TextInjector {
    private let injectionQueue = DispatchQueue(label: "com.voibe.textInjector")
    // Previous text to avoid reinserting the same content
    private var previousText = ""
    // For logging
    private let logEnabled = true
    private let minLogCharacters = 20
    
    func injectText(_ text: String) {
        injectionQueue.async { [weak self] in
            self?.injectTextOnQueue(text)
        }
    }
    
    private func injectTextOnQueue(_ text: String) {
        let result = TextInjector.computeDelta(previousText: previousText, incomingText: text)
        let newText = result.delta
        previousText = result.newPreviousText
        
        // Do nothing if there's no new text
        guard !newText.isEmpty else {
            return
        }
        
        if newText.count >= minLogCharacters {
            log("Injecting text (\(textSummary(newText)))")
        }
        
        // Inject the text using CGEvent.keyboardSetUnicodeString
        injectUnicodeString(newText)
    }
    
    private func injectUnicodeString(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            log("Failed to create event source")
            return
        }
        
        // For longer texts, split and inject in chunks to avoid overwhelming the system
        let maxChunkSize = 5 // Maximum characters per event
        var remainingText = text
        
        while !remainingText.isEmpty {
            // Take the next chunk of text
            let endIndex = remainingText.index(remainingText.startIndex, offsetBy: min(maxChunkSize, remainingText.count))
            let chunk = String(remainingText[remainingText.startIndex..<endIndex])
            
            // Remove the chunk from the remaining text
            remainingText = String(remainingText[endIndex...])
            
            // Create key down event (we'll use keycode 0 since we're setting unicode string)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            
            // Convert the string to Unicode characters
            if let unicodeChars = chunk.unicodeScalars.map({ UniChar($0.value) }) as [UniChar]? {
                // Use the instance method to set Unicode string
                keyDown?.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: unicodeChars)
                
                // Post the event
                keyDown?.post(tap: .cghidEventTap)
                
                // Create and post key up event
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                keyUp?.post(tap: .cghidEventTap)
            }
            
            // Add a small delay between chunks
            if !remainingText.isEmpty {
                usleep(8333) // 8.333ms delay between chunks (120 chunks per second)
            }
        }
    }
    
    func reset() {
        injectionQueue.async { [weak self] in
            self?.previousText = ""
        }
    }

    static func computeDelta(previousText: String, incomingText: String) -> (delta: String, newPreviousText: String) {
        // Only inject new text (the part that hasn't been injected yet)
        if incomingText.hasPrefix(previousText) && !previousText.isEmpty {
            let delta = String(incomingText.dropFirst(previousText.count))
            return (delta, incomingText)
        }
        
        if incomingText.count < previousText.count || !incomingText.contains(previousText) {
            return (incomingText, incomingText)
        }
        
        return (incomingText, incomingText)
    }
    
    private func log(_ message: String) {
        if logEnabled {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let time = formatter.string(from: Date())
            print("[TextInjector] [\(time)] \(message)")
        }
    }

    private func textSummary(_ text: String) -> String {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return "words: \(wordCount), chars: \(text.count)"
    }
} 
