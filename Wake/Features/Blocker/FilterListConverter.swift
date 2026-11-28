import Foundation

/// Turns Adblock Plus–style filter lists (EasyList, EasyPrivacy) into WebKit
/// content-blocker rules (`WKContentRuleList` JSON).
///
/// Supported: network rules (`||host^`, `|https://`, `*`, `^`, `$third-party`,
/// `$domain=`, resource types), exceptions (`@@`, including `$document` to allow a
/// whole site), and element hiding scoped to sites (`example.com##.ad`).
///
/// Skipped on purpose, each a WebKit limitation or a cost:
/// - Generic element hiding (`##.ad` for every site): tens of thousands of
///   selectors in one style sheet applied to every page cost more memory and style
///   time than the ads they hide. Network blocking stops most of those ads anyway.
/// - Regular-expression rules (`/…/`), and options WebKit has no equivalent for
///   (`$csp`, `$redirect`, `$removeparam`, `$rewrite`, `$popup` …).
/// - Extended CSS (`#?#`, `:has()`, `:-abp-…`) and element-hiding exceptions (`#@#`).
/// - Rules for subdocuments only: WebKit's "document" type would also match the
///   page itself.
/// - Anything past WebKit's 150,000-rule limit for one list.
enum FilterListConverter {
    struct Output {
        var rules: [[String: Any]] = []
        var skipped = 0

        var json: String {
            let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
            return String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    static let maxRules = 150_000

    static func convert(_ lists: [String], allowedSites: [String] = []) -> Output {
        var blocks: [[String: Any]] = []
        var exceptions: [[String: Any]] = []
        var hiding: [String: [String]] = [:]  // joined domains → selectors
        var skipped = 0

        for list in lists {
            for raw in list.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[") else { continue }
                if line.contains("##") {
                    if let (domains, selector) = cosmetic(line) {
                        hiding[domains.joined(separator: ","), default: []].append(selector)
                    } else {
                        skipped += 1
                    }
                    continue
                }
                if line.contains("#@#") || line.contains("#?#") || line.contains("#$#") || line.contains("#%#") {
                    skipped += 1
                    continue
                }
                guard let rule = network(line) else {
                    skipped += 1
                    continue
                }
                if line.hasPrefix("@@") { exceptions.append(rule) } else { blocks.append(rule) }
            }
        }

        var rules = blocks
        for (domains, selectors) in hiding.sorted(by: { $0.key < $1.key }) {
            // Many selectors per site in one rule keeps the count down.
            for chunk in stride(from: 0, to: selectors.count, by: 200) {
                let part = selectors[chunk..<min(chunk + 200, selectors.count)]
                rules.append([
                    "trigger": ["url-filter": ".*", "if-domain": domains.split(separator: ",").map { "*" + $0 }],
                    "action": ["type": "css-display-none", "selector": part.joined(separator: ", ")],
                ])
            }
        }
        // Exceptions go last: ignore-previous-rules only undoes rules before it.
        rules += exceptions
        for site in allowedSites {
            rules.append(["trigger": ["url-filter": ".*", "if-domain": ["*" + site]], "action": ["type": "ignore-previous-rules"]])
        }
        if rules.count > maxRules {
            skipped += rules.count - maxRules
            // Keep the exceptions (the end) and as many blocks as fit.
            let tail = exceptions.count + allowedSites.count
            rules = Array(rules.prefix(maxRules - tail)) + Array(rules.suffix(tail))
        }
        return Output(rules: rules, skipped: skipped)
    }

    // MARK: Network rules

    private static let resourceTypes: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
        "media": "media", "xmlhttprequest": "raw", "websocket": "raw", "other": "raw", "ping": "raw",
    ]

    /// Options that change what a rule means in ways WebKit can't express.
    private static let unsupported: Set<String> = [
        "csp", "redirect", "redirect-rule", "removeparam", "rewrite", "popup", "replace", "header",
        "permissions", "generichide", "genericblock", "elemhide", "specifichide", "badfilter", "important",
        "urltransform", "method", "to", "denyallow", "subdocument", "sitekey", "webrtc", "object",
    ]

    static func network(_ line: String) -> [String: Any]? {
        var text = Substring(line)
        let isException = text.hasPrefix("@@")
        if isException { text = text.dropFirst(2) }

        var options: [String] = []
        if let dollar = text.lastIndex(of: "$"), !text[text.index(after: dollar)...].contains("/") {
            options = text[text.index(after: dollar)...].split(separator: ",").map { String($0).lowercased() }
            text = text[..<dollar]
        }
        let pattern = String(text)
        // Regular expressions, and patterns too short to be safe.
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1 { return nil }

        var trigger: [String: Any] = [:]
        var types: [String] = []
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        var wholeDocument = false

        for option in options {
            let negated = option.hasPrefix("~")
            let name = negated ? String(option.dropFirst()) : option
            switch name {
            case "third-party", "3p": trigger["load-type"] = [negated ? "first-party" : "third-party"]
            case "first-party", "1p": trigger["load-type"] = [negated ? "third-party" : "first-party"]
            case "match-case": trigger["url-filter-is-case-sensitive"] = true
            case "document", "doc":
                guard isException else { return nil }
                wholeDocument = true
            case _ where name.hasPrefix("domain="):
                for domain in name.dropFirst("domain=".count).split(separator: "|") {
                    if domain.hasPrefix("~") { unlessDomains.append("*" + domain.dropFirst()) } else { ifDomains.append("*" + domain) }
                }
            default:
                if let type = resourceTypes[name] {
                    if negated { return nil }  // "all but images" has no WebKit form
                    if !types.contains(type) { types.append(type) }
                } else if unsupported.contains(name) || !name.isEmpty {
                    return nil
                }
            }
        }
        // WebKit allows one of if-domain / unless-domain per trigger.
        if !ifDomains.isEmpty, !unlessDomains.isEmpty { return nil }
        if !ifDomains.isEmpty { trigger["if-domain"] = ifDomains }
        if !unlessDomains.isEmpty { trigger["unless-domain"] = unlessDomains }

        if wholeDocument {
            // @@||example.com^$document: everything on that site is allowed.
            guard pattern.hasPrefix("||"), let host = hostOnly(pattern.dropFirst(2)) else { return nil }
            return ["trigger": ["url-filter": ".*", "if-domain": ["*" + host]], "action": ["type": "ignore-previous-rules"]]
        }

        guard let filter = regex(pattern), filter.count >= 4 || pattern.hasPrefix("||") else { return nil }
        trigger["url-filter"] = filter
        if !types.isEmpty { trigger["resource-type"] = types }
        return ["trigger": trigger, "action": ["type": isException ? "ignore-previous-rules" : "block"]]
    }

    /// The ABP pattern as the regular-expression subset WebKit accepts.
    static func regex(_ pattern: String) -> String? {
        var pattern = Substring(pattern)
        var result = ""
        if pattern.hasPrefix("||") {
            result = "^[^:]+://+([^:/]+\\.)?"
            pattern = pattern.dropFirst(2)
        } else if pattern.hasPrefix("|") {
            result = "^"
            pattern = pattern.dropFirst()
        }
        var anchoredEnd = false
        if pattern.hasSuffix("|") {
            anchoredEnd = true
            pattern = pattern.dropLast()
        }
        // A trailing separator matches the end of the address too, which WebKit's
        // subset (no "|" alternation) can't say; dropping it is the looser match.
        while pattern.hasSuffix("^") || pattern.hasSuffix("*") { pattern = pattern.dropLast() }
        guard !pattern.isEmpty || result.hasPrefix("^[^") else { return nil }
        for character in pattern {
            guard character.isASCII, let scalar = character.unicodeScalars.first, scalar.value > 32, scalar.value < 127 else { return nil }
            switch character {
            case "*": result += ".*"
            case "^": result += "[/:?=&]"
            case ".", "+", "?", "(", ")", "[", "]", "{", "}", "\\", "$", "|": result += "\\" + String(character)
            default: result.append(character)
            }
        }
        if anchoredEnd { result += "$" }
        return result
    }

    private static func hostOnly(_ text: Substring) -> String? {
        var host = text
        while host.hasSuffix("^") || host.hasSuffix("/") { host = host.dropLast() }
        guard !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return host.lowercased()
    }

    // MARK: Element hiding

    /// "a.com,b.org##.ad" → (["a.com", "b.org"], ".ad"). Generic rules (no sites) and
    /// extended CSS come back nil.
    static func cosmetic(_ line: String) -> ([String], String)? {
        guard let range = line.range(of: "##") else { return nil }
        let domains = line[..<range.lowerBound].split(separator: ",").map { String($0).lowercased() }
        let selector = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !domains.isEmpty, !selector.isEmpty,
              domains.allSatisfy({ !$0.hasPrefix("~") && !$0.contains("*") && !$0.contains("/") }) else { return nil }
        let extended = [":has(", ":-abp-", ":xpath(", ":contains(", ":upward(", ":remove(", ":style(", ":matches-", ":min-text-length", ":watch-attr", "[-ext-"]
        guard !extended.contains(where: selector.contains), selector.allSatisfy(\.isASCII) else { return nil }
        return (domains, selector)
    }
}
