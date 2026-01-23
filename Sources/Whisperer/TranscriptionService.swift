import Foundation
import AVFoundation

// Extension to allow easy conversion of integers to Data
extension FixedWidthInteger {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

// Make this an actor to eliminate data races
actor TranscriptionService {
    // Log levels
    enum LogLevel: Int {
        case none = 0
        case error = 1
        case info = 2
        case debug = 3
    }
    
    // Connection states
    enum ConnectionState {
        case idle
        case recording
        case transcribing
        case error(String)
    }
    
    // Set the desired log level
    private let logLevel: LogLevel = .info
    
    // State management
    private var connectionState = ConnectionState.idle {
        didSet {
            Task { @MainActor in
                await self.onConnectionStateChanged?(self.connectionState)
            }
            
            switch connectionState {
            case .idle:
                log(.info, message: "State: Idle")
            case .recording:
                log(.info, message: "State: Recording")
            case .transcribing:
                log(.info, message: "State: Transcribing")
            case .error(let message):
                log(.error, message: "State: Error - \(message)")
            }
        }
    }
    
    private var recordedAudioData: Data?
    private var transcriptionTask: Task<Void, Never>?
    private var sseParser = SSEStreamParser()
    private var didComplete = false
    private var didReceiveText = false
    
    // Callbacks
    private var onTranscriptionReceived: ((String) -> Void)?
    private var onConnectionStateChanged: ((ConnectionState) -> Void)?
    private var onTranscriptionComplete: (() -> Void)?
    
    // Retry configuration
    private let maxRetries = 5
    private var currentRetryCount = 0
    
    private var apiKey: String {
        // First check user defaults
        if let key = UserDefaults.standard.string(forKey: "openAIApiKey"), !key.isEmpty {
            return key
        }
        
        // Fall back to environment variable
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
    
    private var customPrompt: String {
        return UserDefaults.standard.string(forKey: "customPrompt") ?? ""
    }
    
    init() {}
    
    // Start recording
    func startRecording() {
        log(.info, message: "Starting recording")
        connectionState = .recording
        recordedAudioData = nil
    }
    
    // Called when recording is finished
    func finishRecording(withAudioData audioData: Data) {
        log(.info, message: "Recording finished, sending audio for transcription")
        
        // Ensure audio data exists and has reasonable size
        guard !audioData.isEmpty, audioData.count > 100 else {
            log(.error, message: "Audio data too small or empty")
            connectionState = .error("Audio data too small or empty")
            
            // Ensure we still complete the transcription when we have no data
            Task { @MainActor in
                await self.onTranscriptionComplete?()
            }
            
            // Return to idle state after reporting error
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                self.connectionState = .idle
            }
            
            return
        }
        
        recordedAudioData = audioData
        sendAudioForTranscription()
    }
    
    private func sendAudioForTranscription() {
        guard let audioData = recordedAudioData else {
            connectionState = .error("No audio data to transcribe")
            return
        }
        
        guard !apiKey.isEmpty else {
            connectionState = .error("OpenAI API key is not set")
            return
        }
        
        connectionState = .transcribing
        
        // Create the URL for the transcription API
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            connectionState = .error("Invalid URL for OpenAI API")
            return
        }
        
        // Create a boundary for multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create the request body
        request.httpBody = createRequestBody(boundary: boundary, audioData: audioData)
        
        // Cancel any existing task
        transcriptionTask?.cancel()
        transcriptionTask = nil
        sseParser = SSEStreamParser()
        didComplete = false
        didReceiveText = false
        
        log(.info, message: "Sending audio for transcription...")
        
        transcriptionTask = Task { [weak self] in
            await self?.streamTranscription(request: request)
        }
    }
    
    private func streamTranscription(request: URLRequest) async {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                connectionState = .error("Invalid response from server")
                return
            }
            
            if httpResponse.statusCode != 200 {
                let errorData = try await collectBytes(bytes)
                let errorMessage = parseErrorMessage(data: errorData)
                log(.error, message: "Server returned error: \(httpResponse.statusCode), \(errorMessage)")
                
                // Check if this is a server error (5xx) that should be retried
                if httpResponse.statusCode >= 500 && httpResponse.statusCode < 600 {
                    retryTranscriptionIfPossible(with: "Server error: \(httpResponse.statusCode)")
                    return
                }
                
                connectionState = .error("Server error: \(httpResponse.statusCode)")
                return
            }
            
            var chunk = Data()
            var responseData = Data()
            for try await byte in bytes {
                if Task.isCancelled {
                    connectionState = .error("Request cancelled")
                    return
                }
                
                chunk.append(byte)
                responseData.append(byte)
                if chunk.count >= 1024 {
                    handleSSEChunk(&chunk)
                }
            }
            
            if !chunk.isEmpty {
                handleSSEChunk(&chunk)
            }
            
            let trailingEvents = sseParser.flush()
            if !trailingEvents.isEmpty {
                handleSSEEvents(trailingEvents)
            }

            // Reset retry count on success
            currentRetryCount = 0
            
            if !didReceiveText, let showingText = parseTranscriptionText(data: responseData) {
                didReceiveText = true
                Task { @MainActor in
                    await self.onTranscriptionReceived?(showingText)
                }
            }
            
            log(.info, message: "Transcription complete")
            connectionState = .idle
            
            if !didComplete {
                didComplete = true
                Task { @MainActor in
                    await self.onTranscriptionComplete?()
                }
            }
        } catch {
            if Task.isCancelled {
                connectionState = .error("Request cancelled")
                return
            }
            
            log(.error, message: "Transcription request failed: \(error.localizedDescription)")
            retryTranscriptionIfPossible(with: "Request failed: \(error.localizedDescription)")
        }
    }
    
    // New function to handle retries with exponential backoff
    private func retryTranscriptionIfPossible(with errorMessage: String) {
        if currentRetryCount < maxRetries {
            currentRetryCount += 1
            
            // Calculate exponential backoff delay: 2^retry * 250ms 
            // This gives: 250ms, 500ms, 1s, 2s, 4s for retries 1-5
            let delayInSeconds = pow(2.0, Double(currentRetryCount)) * 0.25
            
            log(.info, message: "Retry \(currentRetryCount)/\(maxRetries) for transcription after \(delayInSeconds)s")
            
            // Update connection state to show retry information
            connectionState = .error("\(errorMessage). Retrying (\(currentRetryCount)/\(maxRetries))...")
            
            // Schedule retry after the calculated delay
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delayInSeconds * 1_000_000_000))
                sendAudioForTranscription()
            }
        } else {
            // Max retries reached, give up
            log(.error, message: "Maximum retries (\(maxRetries)) reached for transcription")
            connectionState = .error("\(errorMessage). Max retries reached.")
            
            // Ensure we complete the transcription process even on error
            Task { @MainActor in
                await self.onTranscriptionComplete?()
            }
            
            // Reset retry count and return to idle
            currentRetryCount = 0
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                self.connectionState = .idle
            }
        }
    }
    
    private func createRequestBody(boundary: String, audioData: Data) -> Data {
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-transcribe\r\n".data(using: .utf8)!)
        
        // Add prompt parameter if available
        if !customPrompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(customPrompt)\r\n".data(using: .utf8)!)
        }
        
        // Add language parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        
        // Add stream parameter for SSE
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"stream\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        
        // Create WAV file with PCM audio data
        let wavData = createWavFileFromPCMData(audioData)
        
        // Add audio file - converted to WAV
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close the body
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    // Function to create a WAV file from the PCM audio data
    private func createWavFileFromPCMData(_ pcmData: Data) -> Data {
        WavEncoder.encodePCM(pcmData)
    }
    
    private func handleSSEChunk(_ chunk: inout Data) {
        let events = sseParser.feed(chunk)
        chunk.removeAll(keepingCapacity: true)
        handleSSEEvents(events)
    }
    
    private func handleSSEEvents(_ events: [SSEEvent]) {
        for event in events {
            switch event {
            case .delta(let delta):
                log(.debug, message: "Transcription delta: \"\(delta)\"")
                didReceiveText = true
                Task { @MainActor in
                    await self.onTranscriptionReceived?(delta)
                }
            case .done(let fullText):
                if let fullText = fullText {
                    log(.info, message: "Transcription complete: \"\(fullText)\"")
                    if !didReceiveText {
                        didReceiveText = true
                        Task { @MainActor in
                            await self.onTranscriptionReceived?(fullText)
                        }
                    }
                } else {
                    log(.debug, message: "Received end-of-stream marker")
                }
                if !didComplete {
                    didComplete = true
                    Task { @MainActor in
                        await self.onTranscriptionComplete?()
                    }
                }
            }
        }
    }
    
    // Parse error message from response data
    private func parseErrorMessage(data: Data?) -> String {
        guard let errorData = data,
              let errorStr = String(data: errorData, encoding: .utf8) else {
            return "Unknown error"
        }
        
        // Try to extract a cleaner error message from JSON if possible
        do {
            if let errorJson = try JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
        } catch {
            // Just use the raw error string if we can't parse JSON
        }
        
        return errorStr
    }

    private func parseTranscriptionText(data: Data) -> String? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return text
            }
        } catch {
            return nil
        }
        
        return nil
    }

    private func collectBytes(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
    
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        sseParser = SSEStreamParser()
        didComplete = false
        didReceiveText = false
        // Ensure we switch back to idle state
        connectionState = .idle
        
        // Clear any stored audio data
        recordedAudioData = nil
        
        // Reset retry count
        currentRetryCount = 0
    }
    
    // Logging utility
    func log(_ level: LogLevel, message: String) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: now)
        
        if level.rawValue <= logLevel.rawValue {
            let prefix: String
            switch level {
            case .none: prefix = ""
            case .error: prefix = "❌ ERROR: "
            case .info: prefix = "ℹ️ INFO: "
            case .debug: prefix = "🔍 DEBUG: "
            }
            print("\(timestamp) \(prefix)\(message)")
        } else {
            print("\(timestamp) \(message)")
        }
    }
    
    /// Set all callbacks safely within the actor's isolation domain
    func setCallbacks(
        onStateChanged: @escaping (ConnectionState) -> Void,
        onReceived: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.onConnectionStateChanged = onStateChanged
        self.onTranscriptionReceived = onReceived
        self.onTranscriptionComplete = onComplete
    }
} 
