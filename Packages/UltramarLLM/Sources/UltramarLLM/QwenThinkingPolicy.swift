import Foundation

enum QwenThinkingPolicy {
    private static let noThinkSuffix = "/no_think"
    private static let thinkSuffix = "/think"

    private static let thinkOpen = "\u{3C}think\u{3E}"
    private static let thinkClose = "\u{3C}/think\u{3E}"
    private static let redactedThinkOpen = "\u{3C}|redacted_thinking|\u{3E}"

    private static var openThinkingMarkers: [String] {
        [thinkOpen, redactedThinkOpen]
    }

    private static var closeThinkingMarkers: [String] {
        [thinkClose]
    }

    /// Appends the latest Qwen mode switch so each turn is explicit.
    static func userMessageForInference(_ message: String, reasoningMode: QwenReasoningMode) -> String {
        let suffix = reasoningMode.switchToken
        if message.hasSuffix(noThinkSuffix) || message.hasSuffix(thinkSuffix) {
            return message
        }
        return "\(message) \(suffix)"
    }

    /// Streaming filter: tracks raw, visible answer, and thinking content separately.
    struct GenerationFilter {
        private(set) var rawBuffer = ""
        private(set) var visibleText = ""
        private(set) var thinkingText = ""
        private let userPrompt: String?
        private var emittedSanitizedCount = 0

        init(userPrompt: String? = nil) {
            self.userPrompt = userPrompt
        }

        mutating func append(_ piece: String) -> String {
            rawBuffer += piece
            thinkingText = QwenThinkingPolicy.extractThinkingContent(from: rawBuffer)
            visibleText = QwenThinkingPolicy.visibleAnswer(from: rawBuffer)
            if QwenThinkingPolicy.isLikelyUserPromptEchoInProgress(
                visible: visibleText,
                userPrompt: userPrompt
            ) {
                return ""
            }
            let sanitized = QwenThinkingPolicy.sanitizeFinalAnswer(visibleText, userPrompt: userPrompt)
            guard sanitized.count > emittedSanitizedCount else {
                return ""
            }
            let start = sanitized.index(sanitized.startIndex, offsetBy: emittedSanitizedCount)
            let delta = String(sanitized[start...])
            emittedSanitizedCount = sanitized.count
            return delta
        }
    }

    /// Content inside think blocks (complete + in-progress trailing block for live display).
    static func extractThinkingContent(from raw: String) -> String {
        var parts: [String] = []
        var searchRange = raw.startIndex ..< raw.endIndex

        while searchRange.lowerBound < searchRange.upperBound {
            guard let match = nextThinkingBlock(in: raw, from: searchRange) else { break }
            parts.append(match.content)
            searchRange = match.endIndex ..< raw.endIndex
        }

        if let partial = trailingOpenThinkingBlock(in: raw) {
            parts.append(partial)
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Strip thinking blocks from model output before UI (answer only).
    static func sanitizeOutput(_ raw: String) -> String {
        var text = removeCompleteThinkingBlocks(from: raw)
        text = removeLeadingTruncatedThinkingBlock(from: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct FinalizedGeneration: Sendable, Equatable {
        let answer: String
        let thinking: String
    }

    static let generationFailedMessage =
        "No pude generar una respuesta. Prueba de nuevo o usa `ultramar chat --thinking` solo para depurar."

    /// Split raw model output into hidden thinking vs user-visible answer; recover answer when generation ends mid-think.
    static func finalizeGeneration(
        raw: String,
        visibleText: String,
        thinkingText: String,
        userPrompt: String? = nil
    ) -> FinalizedGeneration {
        var answer = sanitizeFinalAnswer(
            visibleText.trimmingCharacters(in: .whitespacesAndNewlines),
            userPrompt: userPrompt
        )
        let thinking = thinkingText.trimmingCharacters(in: .whitespacesAndNewlines)

        if answer.isEmpty {
            let forced = sanitizeFinalAnswer(
                visibleAnswer(from: raw + thinkClose)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                userPrompt: userPrompt
            )
            if !forced.isEmpty {
                answer = forced
            }
        }
        if answer.isEmpty, !thinking.isEmpty {
            if let recovered = fallbackAnswerFromThinking(thinking, userPrompt: userPrompt) {
                answer = recovered
            }
        }
        if !isSubstantiveTravelAnswer(answer), !thinking.isEmpty {
            if let planned = extractPlannedReplyFromThinking(thinking, userPrompt: userPrompt) {
                answer = planned
            }
        }
        if answer.isEmpty, let greeting = greetingFallbackAnswer(for: userPrompt) {
            answer = greeting
        }
        if answer.isEmpty, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answer = generationFailedMessage
        }
        return FinalizedGeneration(answer: answer, thinking: thinking)
    }

    /// When the model emits planning bullets instead of a reply, recover a short welcome for greetings.
    static func greetingFallbackAnswer(for userPrompt: String?) -> String? {
        guard let userPrompt, isGreeting(userPrompt) else { return nil }
        if isLikelySpanish(userPrompt) {
            return """
            Hola, soy Ultramar AI, tu asistente de viaje offline. \
            ¿A dónde vas o qué necesitas planificar?
            """
        }
        return """
        Hello! I'm Ultramar AI, your offline travel assistant. \
        Where are you headed, or what do you need help planning?
        """
    }

    static func isGreeting(_ message: String) -> Bool {
        let normalized = normalizeForEchoComparison(message)
        guard !normalized.isEmpty, normalized.count <= 40 else { return false }
        let greetings = [
            "hola", "hello", "hi", "hey", "buenas", "buenos dias", "buenas tardes",
            "buenas noches", "que tal", "saludos", "good morning", "good afternoon",
        ]
        return greetings.contains { normalized == $0 || normalized.hasPrefix("\($0) ") }
    }

    static func isLikelySpanish(_ message: String) -> Bool {
        let normalized = normalizeForEchoComparison(message)
        let spanishMarkers = [
            "hola", "buenas", "buenos", "que tal", "saludos", "gracias", "donde", "viaje",
        ]
        return spanishMarkers.contains { normalized.contains($0) }
    }

    /// Multiple planning lines echoing system constraints — not user-facing travel advice.
    static func isMostlyInstructionEcho(_ text: String) -> Bool {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        let echoLines = lines.filter { isInstructionEcho($0) || isMetaPlanningLine($0) }
        return Double(echoLines.count) / Double(lines.count) >= 0.5
    }

    static func isMetaPlanningLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let trimmed = lower.trimmingCharacters(in: CharacterSet(charactersIn: "•*- "))
        let metaPrefixes = [
            "determine the response strategy",
            "response strategy:",
            "language:",
            "tone:",
            "content:",
            "constraints:",
            "drafting content",
            "final check",
            "final polish",
            "review constraints",
            "approach:",
            "plan:",
            "structure:",
            "greeting:",
            "reply:",
            "draft:",
            "for greetings",
            "for greeting,",
            "for travel questions",
            "for non-greeting",
            "if the user only greeted",
            "if the user just said",
            "for health questions",
            "step 1:",
            "step 2:",
            "step 3:",
        ]
        if metaPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        if trimmed.contains("since the user just said") || trimmed.contains("since the user said") {
            return true
        }
        if trimmed.contains("the user is asking") || trimmed.contains("the user asked") {
            return true
        }
        return false
    }

    /// Greeting-only reply to a real travel question (model ignores question and just welcomes).
    static func isGreetingBoilerplateForNonGreeting(answer: String, userPrompt: String?) -> Bool {
        guard let userPrompt, !isGreeting(userPrompt) else { return false }
        return isGreetingOnlyResponse(answer)
    }

    /// Opens with a greeting / self-intro and carries no actionable travel advice
    /// (asks a follow-up question or is too short). Self-description like
    /// "offline travel assistant" alone does not count as advice.
    static func isGreetingOnlyResponse(_ answer: String) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 320 else { return false }
        let lower = normalizeForEchoComparison(trimmed)
        guard !lower.isEmpty else { return false }
        let greetingStarters = [
            "hola", "hello", "hi", "hey", "buenas", "buenos dias", "buenas tardes",
            "buenas noches", "bienvenido", "bienvenida", "bienvenidos", "bienvenidas",
            "welcome", "saludos", "greetings", "soy ultramar", "i am ultramar",
            "im ultramar",
        ]
        let startsWithGreeting = greetingStarters.contains { greet in
            lower == greet || lower.hasPrefix("\(greet) ") || lower.hasPrefix("\(greet),")
        }
        guard startsWithGreeting else { return false }
        if trimmed.count <= 120 { return true }
        let hasBullets = trimmed.contains("•")
            || trimmed.range(of: #"(?m)^[\-\*]\s"#, options: .regularExpression) != nil
            || trimmed.range(of: #"(?m)^\s*\d+\.\s"#, options: .regularExpression) != nil
        if hasBullets { return false }
        let tail = String(trimmed.suffix(60))
        let endsWithQuestion = tail.contains("?") || tail.contains("？")
        if endsWithQuestion { return true }
        return false
    }

    /// Truncated single-line fragment: incomplete sentence, bare label, or mid-word cutoff.
    static func isLikelyFragment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let lastLine = lines.last else { return false }
        let bareLabelChars = CharacterSet(charactersIn: ":•*-– ")
        let stripped = lastLine.trimmingCharacters(in: bareLabelChars)
        if lines.count == 1 {
            if stripped.count < 12 { return true }
            if lastLine.hasSuffix(":") { return true }
            if !endsWithTerminalPunctuation(lastLine), trimmed.count < 60 { return true }
        }
        if lines.count >= 2 {
            let allLook = lines.allSatisfy { line in
                line.hasSuffix(":") || line.trimmingCharacters(in: bareLabelChars).count < 3
            }
            if allLook { return true }
        }
        return false
    }

    private static func endsWithTerminalPunctuation(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        let terminals: Set<Character> = [".", "!", "?", "”", "\"", ")", "]"]
        return terminals.contains(last)
    }

    /// Reject answers that echo system-prompt instructions instead of user-facing travel advice.
    static func sanitizeFinalAnswer(_ answer: String, userPrompt: String? = nil) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard !isInstructionEcho(trimmed), !isMostlyInstructionEcho(trimmed) else { return "" }
        if let userPrompt, echoesUserPrompt(answer: trimmed, userPrompt: userPrompt) {
            return ""
        }
        if isGreetingBoilerplateForNonGreeting(answer: trimmed, userPrompt: userPrompt) {
            return ""
        }
        if isLikelyFragment(trimmed) {
            return ""
        }
        return trimmed
    }

    /// While streaming, hold back text that is still spelling out the user's question.
    static func isLikelyUserPromptEchoInProgress(visible: String, userPrompt: String?) -> Bool {
        guard let userPrompt else { return false }
        let trimmedVisible = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVisible.isEmpty else { return false }
        if echoesUserPrompt(answer: trimmedVisible, userPrompt: userPrompt) {
            return true
        }
        let v = normalizeForEchoComparison(trimmedVisible)
        let u = normalizeForEchoComparison(userPrompt)
        guard v.count >= 8, !u.isEmpty else { return false }
        if u.hasPrefix(v) || v.hasPrefix(u) {
            return true
        }
        return false
    }

    /// Reject answers that repeat the user's question instead of answering it.
    static func echoesUserPrompt(answer: String, userPrompt: String) -> Bool {
        let a = normalizeForEchoComparison(answer)
        let u = normalizeForEchoComparison(userPrompt)
        guard !a.isEmpty, !u.isEmpty else { return false }
        if a == u { return true }
        if a.count >= 12, u.contains(a), a.count >= Int(Double(u.count) * 0.85) { return true }
        if u.count >= 12, a.contains(u) { return true }
        return false
    }

    private static func normalizeForEchoComparison(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short or meta lines from unstructured "Thinking Process" output — not user-facing travel advice.
    static func isSubstantiveTravelAnswer(_ answer: String) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 140 else { return false }
        guard !isInstructionEcho(trimmed), !isMostlyInstructionEcho(trimmed) else { return false }
        if trimmed.range(of: #"^\d+\.\s+\*\*"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    /// When Qwen spends tokens on markdown planning, recover bullet tips drafted after a Reply marker.
    static func extractPlannedReplyFromThinking(_ thinking: String, userPrompt: String?) -> String? {
        let lower = thinking.lowercased()
        let markers = ["*reply:*", "**reply:**", "reply:", "drafting content"]
        guard let marker = markers.compactMap({ lower.range(of: $0) }).first else { return nil }

        let start = thinking.index(
            thinking.startIndex,
            offsetBy: lower.distance(from: lower.startIndex, to: marker.upperBound)
        )
        let tail = String(thinking[start...])
        var tips: [String] = []
        for lineSub in tail.split(whereSeparator: \.isNewline) {
            let line = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if tips.count >= 3 { break }
                continue
            }
            let lowerLine = line.lowercased()
            if lowerLine.contains("final check") || lowerLine.contains("refining for") {
                break
            }
            var cleaned = line
            if let match = cleaned.range(of: #"^\*+\s*"#, options: .regularExpression) {
                cleaned.removeSubrange(match)
            }
            if let match = cleaned.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                cleaned.removeSubrange(match)
            }
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            guard cleaned.count >= 18 else { continue }
            guard !isLowQualityRecoveryLine(cleaned) else { continue }
            let sanitized = sanitizeFinalAnswer(cleaned, userPrompt: userPrompt)
            guard !sanitized.isEmpty else { continue }
            tips.append(sanitized)
            if tips.count >= 7 { break }
        }
        guard tips.count >= 3 else { return nil }
        return tips.map { "• \($0)" }.joined(separator: "\n")
    }

    private static func isLowQualityRecoveryLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 18 { return true }
        let lower = trimmed.lowercased()
        let metaFragments = [
            "review constraints",
            "analyze the request",
            "thinking process",
            "drafting internal",
            "formatting:",
            "identify key information",
            "user query:",
            "final check",
            "must ensure",
            "for greetings",
            "for travel questions",
            "greeting:",
            "reply:",
            "approach:",
            "plan:",
        ]
        if metaFragments.contains(where: { lower.contains($0) }) {
            return true
        }
        if trimmed.range(of: #"^\d+\.\s+\*\*[A-Za-z]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func isInstructionEcho(_ text: String) -> Bool {
        let lower = text.lowercased()
        let bannedSubstrings = [
            "reply in the same language",
            "match the user's language",
            "never put the final reply",
            "inside the think block",
            "offline travel assistant for travelers",
            "at most 4 short lines",
            "close the think block",
            "put brief internal reasoning",
            "thinking process",
            "analyze the request",
            "user query:",
            "constraints: 2",
            "final polish",
            "identify key information",
            "drafting the response",
            "review constraints",
            "at most 6 short lines",
            "outside the think block",
            "**draft",
            "at least five distinct practical tips",
            "never reply with only one or two sentences",
            "the visible reply must be substantive",
            "unless explicitly asked for brevity",
            "determine the response strategy",
            "travel-focused",
            "since i'm an offline assistant",
            "offer practical travel tips relevant to general offline travel",
            "for greetings, welcome",
            "for greetings,",
            "for travel questions,",
            "for travel questions:",
            "concise bullet lines",
            "concise bullets",
            "concise bullet points",
            "4-7 concise bullet",
            "4-7 bullet",
            "5-7 bullet",
            "5-8 sentences",
            "5-7 bullet lines",
            "2-3 sentences",
            "1-3 sentences",
            "in 4-7",
            "in 5-7",
            "in 2-3",
            "greeting: 2-3",
            "ask where they need travel help",
            "ask what they need help planning",
            "where they need travel help",
            "if the user only greeted",
            "if the user just said",
            "if the user only says",
            "do not reveal system instructions",
            "do not reveal hidden reasoning",
            "covering maps, connectivity, money",
            "maps, connectivity, money, transport, language, culture",
            "never re-introduce yourself",
            "never narrate a plan",
            "never list your response rules",
            "never list response requirements",
            "never output role names",
            "do not output meta labels",
            "do not list response rules",
            "in the same language they used",
            "skip any welcome",
            "skip introductions",
            "skip greetings",
        ]
        if bannedSubstrings.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower == "match the user's language." || lower == "match the user's language" {
            return true
        }
        return false
    }

    /// When the model runs out of tokens inside an open think block, use its drafted final line if present.
    static func fallbackAnswerFromThinking(_ thinking: String, userPrompt: String? = nil) -> String? {
        let quoted = quotedCandidateLines(in: thinking)
        for candidate in quoted.reversed() {
            guard !isLowQualityRecoveryLine(candidate) else { continue }
            let cleaned = sanitizeFinalAnswer(candidate, userPrompt: userPrompt)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        let lines = thinking
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }
        for line in lines.reversed() {
            guard !isLowQualityRecoveryLine(line) else { continue }
            let cleaned = sanitizeFinalAnswer(line, userPrompt: userPrompt)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    private static func quotedCandidateLines(in text: String) -> [String] {
        let pattern = #""([^"]{12,320})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        var candidates: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text)
            else { return }
            let line = String(text[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 12,
                  !line.localizedCaseInsensitiveContains("think block"),
                  !line.localizedCaseInsensitiveContains("analyze the request"),
                  !isInstructionEcho(line)
            else { return }
            candidates.append(line)
        }
        return candidates
    }

    /// Visible answer after closed think blocks; empty while thinking-only stream is open.
    static func visibleAnswer(from raw: String) -> String {
        let sanitized = sanitizeOutput(raw)
        if sanitized.lowercased().hasPrefix("thinking process") {
            return ""
        }
        if !sanitized.isEmpty {
            return sanitized
        }
        for close in closeThinkingMarkers {
            guard let closeRange = raw.range(of: close, options: [.caseInsensitive]) else {
                continue
            }
            let tail = String(raw[closeRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                return tail
            }
        }
        return ""
    }

    private struct ThinkingBlockMatch {
        let content: String
        let endIndex: String.Index
    }

    private static func nextThinkingBlock(
        in text: String,
        from range: Range<String.Index>
    ) -> ThinkingBlockMatch? {
        var earliestOpen: Range<String.Index>?
        var openMarker: String?

        for marker in openThinkingMarkers {
            if let found = text.range(
                of: marker,
                options: [.caseInsensitive],
                range: range
            ) {
                if earliestOpen == nil || found.lowerBound < earliestOpen!.lowerBound {
                    earliestOpen = found
                    openMarker = marker
                }
            }
        }

        guard let openRange = earliestOpen, openMarker != nil else {
            return nil
        }

        let innerStart = openRange.upperBound
        for close in closeThinkingMarkers {
            guard let closeRange = text.range(
                of: close,
                options: [.caseInsensitive],
                range: innerStart ..< text.endIndex
            ) else {
                continue
            }
            let content = String(text[innerStart ..< closeRange.lowerBound])
            return ThinkingBlockMatch(content: content, endIndex: closeRange.upperBound)
        }

        return nil
    }

    private static func trailingOpenThinkingBlock(in text: String) -> String? {
        var lastOpen: Range<String.Index>?
        for marker in openThinkingMarkers {
            if let found = text.range(of: marker, options: [.caseInsensitive], range: text.startIndex ..< text.endIndex) {
                if lastOpen == nil || found.lowerBound > lastOpen!.lowerBound {
                    lastOpen = found
                }
            }
        }
        guard let openRange = lastOpen else { return nil }
        let tail = String(text[openRange.upperBound...])
        let hasClose = closeThinkingMarkers.contains { close in
            tail.range(of: close, options: [.caseInsensitive]) != nil
        }
        guard !hasClose else { return nil }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeCompleteThinkingBlocks(from text: String) -> String {
        var result = text
        var didRemove = true
        while didRemove {
            didRemove = false
            for open in openThinkingMarkers {
                guard let openRange = result.range(of: open, options: [.caseInsensitive]) else {
                    continue
                }
                for close in closeThinkingMarkers {
                    guard let closeRange = result.range(
                        of: close,
                        options: [.caseInsensitive],
                        range: openRange.upperBound ..< result.endIndex
                    ) else {
                        continue
                    }
                    result.removeSubrange(openRange.lowerBound ..< closeRange.upperBound)
                    didRemove = true
                    break
                }
            }
        }
        return result
    }

    private static func removeLeadingTruncatedThinkingBlock(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for open in openThinkingMarkers {
            guard trimmed.range(of: open, options: [.caseInsensitive])?.lowerBound == trimmed.startIndex else {
                continue
            }
            let hasClose = closeThinkingMarkers.contains { close in
                trimmed.range(of: close, options: [.caseInsensitive]) != nil
            }
            if !hasClose {
                return ""
            }
        }
        return trimmed
    }
}
