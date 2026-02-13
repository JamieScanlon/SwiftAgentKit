import Foundation

/// A utility for dynamically replacing markup tokens in text prompts with values at call time.
///
/// DynamicPrompt supports token replacement using double curly braces syntax: `{{tokenName}}`
/// Tokens are replaced with values provided at runtime, making it ideal for template-based prompts.
///
/// Example:
/// ```swift
/// let template = "Hello {{name}}, welcome to {{location}}!"
/// var prompt = DynamicPrompt(template: template)
/// prompt["name"] = "Alice"
/// prompt["location"] = "SwiftAgentKit"
/// let result = prompt.replace()
/// // Result: "Hello Alice, welcome to SwiftAgentKit!"
/// ```
public struct DynamicPrompt: Sendable {
    /// The template string containing markup tokens
    public let template: String
    
    /// Pre-parsed token names found in the template
    private let tokenNames: Set<String>
    
    /// Default token values that will be used when tokens are not provided in replace calls
    private var defaultTokens: [String: String]
    
    /// Creates a new DynamicPrompt from a template string.
    ///
    /// The template can contain tokens in the format `{{tokenName}}` which will be replaced
    /// with values when `replace(tokens:)` is called.
    ///
    /// - Parameters:
    ///   - template: The template string containing markup tokens
    ///   - defaultTokens: Optional dictionary of default token values
    public init(template: String, defaultTokens: [String: String] = [:]) {
        self.template = template
        self.tokenNames = Self.parseTokenNames(from: template)
        self.defaultTokens = defaultTokens
    }
    
    /// Accesses or modifies default token values using subscript syntax.
    ///
    /// - Parameter token: The token name (without braces)
    /// - Returns: The default value for the token, or `nil` if not set
    ///
    /// Example:
    /// ```swift
    /// var prompt = DynamicPrompt(template: "Hello {{name}}!")
    /// prompt["name"] = "World"
    /// let value = prompt["name"] // Returns "World"
    /// ```
    public subscript(token: String) -> String? {
        get {
            return defaultTokens[token]
        }
        set {
            defaultTokens[token] = newValue
        }
    }
    
    /// Replaces all tokens in the template with the provided values.
    ///
    /// If no tokens are provided, uses default token values. Provided tokens override defaults.
    ///
    /// - Parameter tokens: A dictionary mapping token names (without braces) to their replacement values.
    ///                     If `nil` or empty, uses default token values. Provided tokens override defaults.
    /// - Returns: The template string with all tokens replaced. Tokens without values remain unchanged.
    ///
    /// Example:
    /// ```swift
    /// var prompt = DynamicPrompt(template: "Hello {{name}}!")
    /// prompt["name"] = "World"
    /// let result = prompt.replace() // Uses default: "Hello World!"
    /// let result2 = prompt.replace(tokens: ["name": "Alice"]) // Overrides: "Hello Alice!"
    /// ```
    public func replace(tokens: [String: String]? = nil) -> String {
        guard !tokenNames.isEmpty else {
            return template
        }
        
        // Merge default tokens with provided tokens (provided tokens take precedence)
        let mergedTokens: [String: String]
        if let providedTokens = tokens, !providedTokens.isEmpty {
            mergedTokens = defaultTokens.merging(providedTokens) { (_, new) in new }
        } else {
            mergedTokens = defaultTokens
        }
        
        var result = template
        
        // Replace each token found in the template
        for tokenName in tokenNames {
            let tokenPattern = "{{\(tokenName)}}"
            let replacement = mergedTokens[tokenName] ?? tokenPattern // Keep token if no replacement provided
            result = result.replacingOccurrences(of: tokenPattern, with: replacement)
        }
        
        return result
    }
    
    /// Returns the final resolved text prompt using default token values.
    ///
    /// This is a convenience method equivalent to calling `replace()` without parameters.
    /// It provides a clearer semantic meaning when you want to get the final static text
    /// using only the default tokens that have been set.
    ///
    /// - Returns: The template string with all tokens replaced using default token values.
    ///            Tokens without default values remain unchanged.
    ///
    /// Example:
    /// ```swift
    /// var prompt = DynamicPrompt(template: "Hello {{name}}, welcome to {{location}}!")
    /// prompt["name"] = "Alice"
    /// prompt["location"] = "SwiftAgentKit"
    /// let finalText = prompt.render() // "Hello Alice, welcome to SwiftAgentKit!"
    /// ```
    public func render() -> String {
        return replace()
    }
    
    /// Replaces all tokens in the template with the provided values, using a custom closure for transformation.
    ///
    /// If the transform closure returns `nil` for a token, the default token value (if set) will be used.
    ///
    /// - Parameter transform: A closure that takes a token name and returns its replacement value.
    ///                       If `nil` is returned, the default token value (if set) will be used.
    /// - Returns: The template string with all tokens replaced
    ///
    /// Example:
    /// ```swift
    /// var prompt = DynamicPrompt(template: "Count: {{count}}, Name: {{name}}")
    /// prompt["name"] = "Alice"
    /// let result = prompt.replace { tokenName in
    ///     if tokenName == "count" { return "42" }
    ///     return nil // Will use default for "name"
    /// }
    /// // Result: "Count: 42, Name: Alice"
    /// ```
    public func replace(transform: (String) -> String?) -> String {
        guard !tokenNames.isEmpty else {
            return template
        }
        
        var result = template
        
        for tokenName in tokenNames {
            let tokenPattern = "{{\(tokenName)}}"
            // Try transform first, then fall back to default token
            let replacement = transform(tokenName) ?? defaultTokens[tokenName] ?? tokenPattern
            result = result.replacingOccurrences(of: tokenPattern, with: replacement)
        }
        
        return result
    }
    
    /// Returns the set of token names found in the template.
    ///
    /// - Returns: A set of token names (without braces) that appear in the template
    public func getTokenNames() -> Set<String> {
        return tokenNames
    }
    
    /// Checks if the template contains any tokens.
    ///
    /// - Returns: `true` if the template contains at least one token, `false` otherwise
    public func hasTokens() -> Bool {
        return !tokenNames.isEmpty
    }
    
    /// Returns all default token values.
    ///
    /// - Returns: A dictionary of all default token values
    public func getDefaultTokens() -> [String: String] {
        return defaultTokens
    }
    
    /// Sets multiple default token values at once.
    ///
    /// - Parameter tokens: A dictionary mapping token names to their default values
    public mutating func setDefaultTokens(_ tokens: [String: String]) {
        defaultTokens = tokens
    }
    
    /// Removes a default token value.
    ///
    /// - Parameter token: The token name to remove
    public mutating func removeDefaultToken(_ token: String) {
        defaultTokens.removeValue(forKey: token)
    }
    
    /// Removes all default token values.
    public mutating func clearDefaultTokens() {
        defaultTokens.removeAll()
    }
    
    // MARK: - Private Helpers
    
    /// Parses token names from a template string.
    ///
    /// Tokens are identified by the pattern `{{tokenName}}` where `tokenName` can contain
    /// letters, numbers, underscores, and hyphens. Tokens inside triple braces `{{{tokenName}}}`
    /// are ignored.
    ///
    /// - Parameter template: The template string to parse
    /// - Returns: A set of unique token names found in the template
    private static func parseTokenNames(from template: String) -> Set<String> {
        var tokenNames = Set<String>()
        
        // Use regex to find all tokens in the format {{tokenName}}
        // Token names can contain: letters, numbers, underscores, hyphens
        // Negative lookbehind/lookahead ensures we don't match tokens inside triple braces
        let pattern = #"(?<!\{)\{\{([a-zA-Z0-9_-]+)\}\}(?!\})"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return tokenNames
        }
        
        let nsString = template as NSString
        let matches = regex.matches(in: template, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            if match.numberOfRanges > 1 {
                let tokenRange = match.range(at: 1) // First capture group
                if tokenRange.location != NSNotFound {
                    let tokenName = nsString.substring(with: tokenRange)
                    tokenNames.insert(tokenName)
                }
            }
        }
        
        return tokenNames
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Creates a DynamicPrompt from this string and replaces tokens with the provided values.
    ///
    /// - Parameter tokens: A dictionary mapping token names to their replacement values
    /// - Returns: The string with all tokens replaced
    ///
    /// Example:
    /// ```swift
    /// let result = "Hello {{name}}!".replacingTokens(["name": "World"])
    /// // Result: "Hello World!"
    /// ```
    public func replacingTokens(_ tokens: [String: String]) -> String {
        let prompt = DynamicPrompt(template: self)
        return prompt.replace(tokens: tokens)
    }
    
    /// Creates a DynamicPrompt from this string and replaces tokens using a transform closure.
    ///
    /// - Parameter transform: A closure that takes a token name and returns its replacement value
    /// - Returns: The string with all tokens replaced
    public func replacingTokens(transform: (String) -> String?) -> String {
        let prompt = DynamicPrompt(template: self)
        return prompt.replace(transform: transform)
    }
}
