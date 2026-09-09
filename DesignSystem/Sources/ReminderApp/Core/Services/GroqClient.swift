import Foundation

/// The one network seam in the app: a hand-rolled client for Groq's
/// OpenAI-compatible chat-completions endpoint.
///
/// There is no SDK dependency here on purpose. The app makes exactly one kind
/// of request — "here is a transcript, stream me back a JSON object" — and a
/// whole package graph to express that would be more code to read, not less.
/// `URLSession` already does streaming HTTP; everything this type adds is the
/// twenty lines of SSE framing that sit on top of it.
///
/// The client is deliberately dumb about *content*. It knows nothing about
/// captures, reports or questions: it takes a system prompt and a user prompt
/// and yields text fragments. All the meaning lives in `CaptureAnalysis`, so
/// the prompt can be rewritten without touching a line of transport code.
public struct GroqClient: Sendable {
    /// Groq's OpenAI-compatible endpoint. Kept as a literal rather than a
    /// configurable base URL because a second host would mean a second auth
    /// scheme, and that is a bigger change than swapping a string.
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    /// A 120B model is overkill for classification and roughly right for the
    /// rewrite, which is the expensive half of the job: the report has to keep
    /// every fact from a rambling transcript while reading like prose. Smaller
    /// models drop qualifiers and numbers, which is the one failure mode this
    /// feature cannot survive.
    ///
    /// This is a reasoning model, which matters for the SSE loop below: its
    /// chain of thought arrives in a separate `delta.reasoning` field, so the
    /// `delta.content` this client yields is still nothing but the JSON object.
    ///
    /// Model ids on Groq are decommissioned without warning — the previous one
    /// here, `llama-3.3-70b-versatile`, started 404ing as `model_not_found`
    /// while the API key stayed perfectly valid. If every call suddenly fails,
    /// check `GET /openai/v1/models` before suspecting the key.
    private static let model = "openai/gpt-oss-120b"

    /// Nil when no key has been configured. Kept optional rather than defaulted
    /// to `""` so `hasKey` is a real question with a real answer, and the
    /// screens can show a "set up your key" path instead of a failed request.
    public let apiKey: String?

    public init(apiKey: String?) {
        self.apiKey = apiKey
    }

    /// The client the app actually uses, built from the key baked into the
    /// bundle's Info.plist by `Secrets.xcconfig`.
    ///
    /// The placeholder cases matter: an unexpanded `$(GROQ_API_KEY)` is what
    /// you get when the developer cloned the repo and never made their own
    /// `Secrets.xcconfig`, and it must read as *absent*, not as a key that will
    /// fail with a confusing 401 at the worst possible moment.
    public static var configured: GroqClient {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GROQ_API_KEY") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholders: Set<String> = ["", "$(GROQ_API_KEY)", "YOUR_KEY_HERE"]
        return GroqClient(apiKey: placeholders.contains(trimmed) ? nil : trimmed)
    }

    /// Whether a real request can be made at all. Callers check this before
    /// showing any AI affordance, so a key-less build degrades to the local
    /// `TriageEngine` silently rather than throwing in the user's face.
    public var hasKey: Bool { apiKey != nil }

    /// Streams the assistant's reply back as it is generated.
    ///
    /// The stream yields raw text deltas in order — no framing, no JSON, just
    /// whatever characters the model has emitted since the last yield. The
    /// caller is expected to accumulate them; `StreamingAnalysisParser` is the
    /// thing that makes sense of a half-written JSON object.
    ///
    /// Streaming rather than awaiting the whole response is the entire point of
    /// this method: the report is the longest thing the model writes, and
    /// watching it appear is the difference between a screen that feels alive
    /// and four seconds of a spinner.
    public func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey else { throw GroqError.missingKey }

                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    // Long transcripts plus a long report: the default 60s is
                    // tight, and a timeout mid-report is worse than a slow one.
                    request.timeoutInterval = 120

                    let body: [String: Any] = [
                        "model": Self.model,
                        "stream": true,
                        // Low but not zero. The rewrite needs enough freedom to
                        // turn speech into readable prose; anything higher and
                        // the model starts inventing detail that was never said,
                        // which is the one thing a faithful report must not do.
                        "temperature": 0.3,
                        // Constrained decoding, so the incremental parser is
                        // reading a document that is guaranteed to be JSON
                        // rather than a chatty preamble followed by a fence.
                        "response_format": ["type": "json_object"],
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": user]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        // The body of an error response is a stream too, so it
                        // has to be drained by hand to produce a message worth
                        // showing — Groq puts the useful part ("invalid api
                        // key", "rate limit") in there.
                        var detail = ""
                        for try await line in bytes.lines {
                            detail += line
                            if detail.count > 2000 { break }
                        }
                        throw GroqError.http(http.statusCode, detail)
                    }

                    for try await line in bytes.lines {
                        // Server-sent events: blank lines and comment lines are
                        // keep-alive padding and carry no payload.
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }

                        // Deliberately hand-picked out of the JSON rather than
                        // decoded into a struct: the chunk shape carries a dozen
                        // fields the app never reads, and a schema change in any
                        // of them should not be able to break the stream.
                        guard
                            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let choices = object["choices"] as? [[String: Any]],
                            let delta = choices.first?["delta"] as? [String: Any],
                            let content = delta["content"] as? String,
                            !content.isEmpty
                        else { continue }

                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling the consuming task must actually stop the request —
            // otherwise leaving the screen keeps a 120B generation running.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole reply, once. For the calls where nobody is watching the text
    /// arrive — the retitle pass writes a heading and a handful of short
    /// fields, and animating those in character by character would be motion
    /// on the page for something the reader did not ask to watch.
    ///
    /// Built on `stream` rather than beside it so there is still exactly one
    /// request shape in this file: the transport, the error handling and the
    /// JSON mode are the ones above, and this only declines to publish the
    /// intermediate states.
    public func complete(system: String, user: String) async throws -> String {
        var text = ""
        for try await delta in stream(system: system, user: user) {
            text += delta
        }
        return text
    }
}

/// Failures worth telling the user about, in their own words.
///
/// Each case exists because it needs a *different* recovery: no key is a setup
/// problem, an HTTP failure is usually transient, and a decoding failure means
/// falling back to the local heuristics rather than retrying.
public enum GroqError: LocalizedError, Sendable {
    /// No `GROQ_API_KEY` reached the bundle — almost always a missing
    /// `Secrets.xcconfig`.
    case missingKey
    /// The endpoint answered with a non-2xx status; the string is whatever of
    /// the error body could be read.
    case http(Int, String)
    /// The response arrived but was not the JSON object the prompt asked for.
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            "No Groq API key. Copy Secrets.example.xcconfig to Secrets.xcconfig and add a key from console.groq.com."
        case let .http(status, detail):
            detail.isEmpty
                ? "Groq returned HTTP \(status)."
                : "Groq returned HTTP \(status): \(detail)"
        case let .decoding(detail):
            "Couldn't read Groq's reply: \(detail)"
        }
    }
}
