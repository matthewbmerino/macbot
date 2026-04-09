import Foundation

/// Deterministic post-generation guard against numeric fabrication.
///
/// The guard scans the model's draft response for numeric tokens (dollar
/// amounts, percentages, plain decimals, integers with thousands separators)
/// and checks each one against the conversation's tool-call history. If a
/// number appears in the draft that doesn't appear in any tool result for
/// this turn, the guard flags it as a probable fabrication.
///
/// **Why this works against small models.** The model is already producing
/// tool-grounded responses *most* of the time. The failures we keep seeing
/// (AMZN +0.00%, "essentially flat", "4 minutes behind") all share the
/// property that the bad number is not in the tool history — the model
/// rounded, smoothed, paraphrased, or made up a number to fill a gap. A
/// regex scanner catches the entire class deterministically with zero
/// model cost.
///
/// **Tolerance handling.** Numeric matching is fuzzy at the boundaries:
/// "$233.65" in tool output should match "$233.65" or "233.65" or
/// "233.65 USD" in the draft, even if the surrounding punctuation differs.
/// We normalize both sides before comparing.
enum CitationGuard {

    /// A numeric token extracted from a string. We carry the original text
    /// for diagnostics and the normalized form for comparison.
    struct NumericToken: Equatable, Hashable {
        let original: String
        let normalized: String
    }

    /// Result of running the guard against a draft response.
    struct GuardResult {
        /// True if every numeric token in the draft is grounded in tool history.
        let isGrounded: Bool
        /// Numeric tokens that appear in the draft but not in any tool result.
        /// Empty when `isGrounded` is true.
        let unsourced: [NumericToken]
    }

    /// Check whether every numeric claim in `draft` is supported by some
    /// tool result in `toolHistory`.
    ///
    /// - Parameters:
    ///   - draft: the model's proposed response (after `ThinkingStripper`).
    ///   - toolHistory: the concatenated text of all tool results from
    ///     this turn. Pass an empty string if no tools were called.
    ///   - allowedSmallIntegers: integers below this value (e.g. "1", "2",
    ///     "5") are exempt from grounding. Common small numbers appear in
    ///     prose constantly ("3 things", "1st", "step 2") and would create
    ///     false positives if every one had to be in tool history.
    ///   - allowedLiterals: a set of normalized literals that are always
    ///     considered grounded (e.g. dates, year strings the model can
    ///     legitimately know from its system prompt context).
    static func check(
        draft: String,
        toolHistory: String,
        allowedSmallIntegers: Int = 10,
        allowedLiterals: Set<String> = []
    ) -> GuardResult {
        let draftTokens = extractNumericTokens(from: draft)
        guard !draftTokens.isEmpty else {
            // Nothing numeric to verify — trivially grounded.
            return GuardResult(isGrounded: true, unsourced: [])
        }

        // Build the haystack of acceptable normalized values from tool history.
        let toolTokens = extractNumericTokens(from: toolHistory)
        var grounded = Set(toolTokens.map(\.normalized))
        grounded.formUnion(allowedLiterals)

        var unsourced: [NumericToken] = []
        for token in draftTokens {
            if grounded.contains(token.normalized) { continue }
            // Small integers are common in prose ("3 reasons", "step 2")
            // — exempt them so the guard doesn't fire on benign English.
            if let asInt = Int(token.normalized), abs(asInt) <= allowedSmallIntegers {
                continue
            }
            unsourced.append(token)
        }
        return GuardResult(isGrounded: unsourced.isEmpty, unsourced: unsourced)
    }

    /// Build the system-message nudge that gets appended to history when
    /// the guard fires. The nudge tells the model exactly which numbers
    /// don't appear in any tool result so it can either correct them or
    /// say "I don't have that information."
    static func regenerationNudge(for unsourced: [NumericToken]) -> String {
        let preview = unsourced.prefix(8).map(\.original).joined(separator: ", ")
        return """
        Your previous response contained numbers that do not appear in any \
        tool result above: \(preview). \
        Use ONLY numbers that are literally present in the tool results. \
        If a fact you want to state has no number in the tool history, do \
        not invent one — say "I don't have that information" or quote what \
        the tools actually returned.
        """
    }

    /// Extract numeric tokens from arbitrary text.
    ///
    /// Recognizes:
    /// - currency amounts: `$233.65`, `$1,234.56`, `$1.2M`
    /// - percentages: `+6.20%`, `-5.9%`, `4.71%`
    /// - decimals: `233.65`, `0.5`
    /// - integers with thousands separators: `1,234`, `12,345,678`
    /// - plain integers above the small-integer threshold: `233`, `1000`
    ///
    /// Each token is normalized by stripping currency symbols, commas, and
    /// trailing punctuation, and by canonicalizing the sign. So "$233.65"
    /// and "233.65" both normalize to "233.65".
    static func extractNumericTokens(from text: String) -> [NumericToken] {
        // Single regex that captures any of the supported numeric forms.
        // The patterns intentionally allow leading $, +, -, leading commas
        // inside thousands groupings, and an optional trailing % or letter
        // suffix (M/B/K) for compact magnitudes.
        let pattern = #"[+\-]?\$?\d{1,3}(?:,\d{3})+(?:\.\d+)?%?|[+\-]?\$?\d+\.\d+%?|[+\-]?\$?\d+%?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        var seen = Set<String>()
        var tokens: [NumericToken] = []
        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let raw = String(text[r])
            let normalized = normalizeNumeric(raw)
            guard !normalized.isEmpty else { continue }
            // Deduplicate within the same input — we only need to know
            // each unique value appears, not how many times.
            if seen.insert(normalized).inserted {
                tokens.append(NumericToken(original: raw, normalized: normalized))
            }
        }
        return tokens
    }

    /// Canonicalize a numeric token for comparison.
    ///
    /// - Strips `$`, `,`, surrounding whitespace, and trailing `%` (the
    ///   percent sign isn't part of the number — `+6.20%` and `6.2`
    ///   should be considered the same magnitude).
    /// - Drops a leading `+` (signs other than minus are cosmetic).
    /// - Trims trailing zeros after a decimal point (`233.65` and
    ///   `233.6500` are the same).
    /// - Returns the empty string for tokens that don't parse as a number.
    static func normalizeNumeric(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Strip the trailing percent sign — comparison is on magnitude.
        if s.hasSuffix("%") { s.removeLast() }
        // Strip leading `$`.
        if s.hasPrefix("$") { s.removeFirst() }
        else if s.hasPrefix("+$") { s.removeFirst(2); s = "+" + s }
        else if s.hasPrefix("-$") { s.removeFirst(2); s = "-" + s }
        // Strip leading + (cosmetic).
        if s.hasPrefix("+") { s.removeFirst() }
        // Strip thousands commas.
        s = s.replacingOccurrences(of: ",", with: "")
        // Parse to canonical form.
        guard let value = Double(s) else { return "" }
        // Round to 4 decimal places to absorb floating-point noise, then
        // emit without trailing zeros.
        let rounded = (value * 10000).rounded() / 10000
        // Use %g style: drops trailing zeros, no scientific notation for
        // numbers in our range.
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        // Strip trailing zeros from a fixed-point representation.
        var formatted = String(format: "%.4f", rounded)
        while formatted.hasSuffix("0") { formatted.removeLast() }
        if formatted.hasSuffix(".") { formatted.removeLast() }
        return formatted
    }
}
