import Testing
import Logging
import EasyJSON
@testable import SwiftAgentKit

// Helper extension for easier testing
extension JSON {
    subscript(key: String) -> Any? {
        guard case .object(let dict) = self else { return nil }
        guard let value = dict[key] else { return nil }
        switch value {
        case .string(let s): return s
        case .integer(let i): return i
        case .double(let d): return d
        case .boolean(let b): return b
        default: return nil
        }
    }
    
    var isEmpty: Bool {
        guard case .object(let dict) = self else { return true }
        return dict.isEmpty
    }
}

@Suite("ToolCall Tests")
struct ToolCallTests {
    
    @Test("extractToolCallStringPlusRange - Empty Content")
    func testProcessToolCallsEmptyContent() throws {
        let result = ToolCall.extractToolCallStringPlusRange(content: "", availableTools: ["test_tool"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Direct Tool Call with Available Tool")
    func testProcessToolCallsDirectToolCall() throws {
        let content = "test_tool(arg1, arg2)"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["test_tool"])
        #expect(result.toolCall == "test_tool(arg1, arg2)")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Direct Tool Call with Multiple Available Tools")
    func testProcessToolCallsDirectToolCallMultipleTools() throws {
        let content = "search_tool(query)"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["test_tool", "search_tool", "other_tool"])
        #expect(result.toolCall == "search_tool(query)")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Direct Tool Call Not in Available Tools")
    func testProcessToolCallsDirectToolCallNotAvailable() throws {
        let content = "unknown_tool(arg1)"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["test_tool", "search_tool"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Wrapped Tool Call with Both Tags")
    func testProcessToolCallsWrappedToolCall() throws {
        let content = "Some text <|python_tag|>search_tool(query)<|eom_id|> more text"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == "search_tool(query)")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Wrapped Tool Call without Available Tools")
    func testProcessToolCallsWrappedToolCallNoAvailableTools() throws {
        let content = "Some text <|python_tag|>search_tool(query)<|eom_id|> more text"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: [])
        #expect(result.toolCall == "search_tool(query)")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Wrapped Tool Call with Only Opening Tag")
    func testProcessToolCallsWrappedToolCallOnlyOpeningTag() throws {
        let content = "Some text <|python_tag|>search_tool(query) more text"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == "search_tool(query)")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - No Tool Call Found")
    func testProcessToolCallsNoToolCallFound() throws {
        let content = "This is just regular text without any tool calls"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["test_tool"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Tool Call with Complex Arguments")
    func testProcessToolCallsComplexArguments() throws {
        let content = "search_tool(query=\"complex query with spaces\", limit=10, filter=\"active\")"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == "search_tool(query=\"complex query with spaces\", limit=10, filter=\"active\")")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Tool Call with Nested Parentheses")
    func testProcessToolCallsNestedParentheses() throws {
        let content = "search_tool(query=\"test\", options=(limit=10, filter=\"active\"))"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == "search_tool(query=\"test\", options=(limit=10, filter=\"active\"))")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Tool Call with Spaces")
    func testProcessToolCallsWithSpaces() throws {
        let content = "  search_tool(query)  "
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == "search_tool(query)")
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Tool Call without Parentheses")
    func testProcessToolCallsWithoutParentheses() throws {
        let content = "search_tool"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Tool Call with Only Opening Parenthesis")
    func testProcessToolCallsOnlyOpeningParenthesis() throws {
        let content = "search_tool("
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Tool Call with Only Closing Parenthesis")
    func testProcessToolCallsOnlyClosingParenthesis() throws {
        let content = "search_tool)"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Tool Call with Special Characters")
    func testProcessToolCallsSpecialCharacters() throws {
        let content = "search_tool(query=\"test@example.com\", path=\"/usr/local/bin\")"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["search_tool"])
        #expect(result.toolCall == "search_tool(query=\"test@example.com\", path=\"/usr/local/bin\")")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Simple Wrapped Tool Call")
    func testProcessToolCallsSimpleWrappedToolCall() throws {
        let content = "<|python_tag|>simple_tool()<|eom_id|>"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["simple_tool"])
        #expect(result.toolCall == "simple_tool()")
        #expect(result.range != nil)
    }
    
    @Test("parseToolCallFromString - Empty Content")
    func testProcessModelResponseEmptyContent() throws {
        let result = ToolCall.parseToolCallFromString(content: "", availableTools: ["test_tool"])
        #expect(result.message == "")
        #expect(result.toolCall == nil)
    }
    
    @Test("parseToolCallFromString - No Tool Call in Content")
    func testProcessModelResponseNoToolCall() throws {
        let content = "This is a regular message without any tool calls"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool"])
        #expect(result.message == content)
        #expect(result.toolCall == nil)
    }
    
    @Test("parseToolCallFromString - Direct Tool Call with Available Tool")
    func testProcessModelResponseDirectToolCall() throws {
        let content = "Here is the answer: test_tool(arg1, arg2)"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool"])
        #expect(result.message == "Here is the answer: ")
        #expect(result.toolCall == "test_tool(arg1, arg2)")
    }
    
    @Test("parseToolCallFromString - Direct Tool Call at Beginning")
    func testProcessModelResponseDirectToolCallAtBeginning() throws {
        let content = "test_tool(arg1, arg2) Here is the answer"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool"])
        #expect(result.message == " Here is the answer")
        #expect(result.toolCall == "test_tool(arg1, arg2)")
    }
    
    @Test("parseToolCallFromString - Direct Tool Call at End")
    func testProcessModelResponseDirectToolCallAtEnd() throws {
        let content = "Here is the answer test_tool(arg1, arg2)"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool"])
        #expect(result.message == "Here is the answer ")
        #expect(result.toolCall == "test_tool(arg1, arg2)")
    }
    
    @Test("parseToolCallFromString - Direct Tool Call with Spaces")
    func testProcessModelResponseDirectToolCallWithSpaces() throws {
        let content = "  test_tool(arg1, arg2)  "
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool"])
        #expect(result.message == "    ")
        #expect(result.toolCall == "test_tool(arg1, arg2)")
    }
    
    @Test("parseToolCallFromString - Direct Tool Call Not in Available Tools")
    func testProcessModelResponseDirectToolCallNotAvailable() throws {
        let content = "Here is the answer: unknown_tool(arg1)"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool"])
        #expect(result.message == content)
        #expect(result.toolCall == nil)
    }
    
    @Test("parseToolCallFromString - Wrapped Tool Call with Both Tags")
    func testProcessModelResponseWrappedToolCall() throws {
        let content = "Some text <|python_tag|>search_tool(query)<|eom_id|> more text"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Some text  more text")
        #expect(result.toolCall == "search_tool(query)")
    }
    
    @Test("parseToolCallFromString - Wrapped Tool Call at Beginning")
    func testProcessModelResponseWrappedToolCallAtBeginning() throws {
        let content = "<|python_tag|>search_tool(query)<|eom_id|> Here is the answer"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == " Here is the answer")
        #expect(result.toolCall == "search_tool(query)")
    }
    
    @Test("parseToolCallFromString - Wrapped Tool Call at End")
    func testProcessModelResponseWrappedToolCallAtEnd() throws {
        let content = "Here is the answer <|python_tag|>search_tool(query)<|eom_id|>"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Here is the answer ")
        #expect(result.toolCall == "search_tool(query)")
    }
    
    @Test("parseToolCallFromString - Wrapped Tool Call without Available Tools")
    func testProcessModelResponseWrappedToolCallNoAvailableTools() throws {
        let content = "Some text <|python_tag|>search_tool(query)<|eom_id|> more text"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: [])
        #expect(result.message == "Some text  more text")
        #expect(result.toolCall == "search_tool(query)")
    }
    
    @Test("parseToolCallFromString - Wrapped Tool Call with Only Opening Tag")
    func testProcessModelResponseWrappedToolCallOnlyOpeningTag() throws {
        let content = "Some text <|python_tag|>search_tool(query) more text"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Some text ")
        #expect(result.toolCall == "search_tool(query)")
    }
    
    @Test("parseToolCallFromString - Wrapped Tool Call with Only Opening Tag and No Available Tools")
    func testProcessModelResponseWrappedToolCallOnlyOpeningTagNoAvailableTools() throws {
        let content = "Some text <|python_tag|>search_tool(query) more text"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: [])
        #expect(result.message == "Some text ")
        #expect(result.toolCall == "search_tool(query) more text")
    }
    
    @Test("processModelResponse - Tool Call with Complex Arguments")
    func testProcessModelResponseComplexArguments() throws {
        let content = "Processing: search_tool(query=\"complex query with spaces\", limit=10, filter=\"active\")"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Processing: ")
        #expect(result.toolCall == "search_tool(query=\"complex query with spaces\", limit=10, filter=\"active\")")
    }
    
    @Test("parseToolCallFromString - Tool Call with Nested Parentheses")
    func testProcessModelResponseNestedParentheses() throws {
        let content = "Result: search_tool(query=\"test\", options=(limit=10, filter=\"active\"))"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Result: ")
        #expect(result.toolCall == "search_tool(query=\"test\", options=(limit=10, filter=\"active\"))")
    }
    
    @Test("parseToolCallFromString - Multiple Tool Calls (First One Wins)")
    func testProcessModelResponseMultipleToolCalls() throws {
        let content = "First: test_tool(arg1) Second: search_tool(query)"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool", "search_tool"])
        #expect(result.message == "First:  Second: search_tool(query)")
        #expect(result.toolCall == "test_tool(arg1)")
    }
    
    @Test("parseToolCallFromString - Tool Call with Special Characters")
    func testProcessModelResponseSpecialCharacters() throws {
        let content = "Path: search_tool(query=\"test@example.com\", path=\"/usr/local/bin\")"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Path: ")
        #expect(result.toolCall == "search_tool(query=\"test@example.com\", path=\"/usr/local/bin\")")
    }
    
    @Test("parseToolCallFromString - Simple Wrapped Tool Call")
    func testProcessModelResponseSimpleWrappedToolCall() throws {
        let content = "<|python_tag|>simple_tool()<|eom_id|>"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["simple_tool"])
        #expect(result.message == "")
        #expect(result.toolCall == "simple_tool()")
    }
    
    @Test("parseToolCallFromString - Tool Call with Newlines")
    func testProcessModelResponseToolCallWithNewlines() throws {
        let content = "Line 1\ntest_tool(arg1)\nLine 3"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["test_tool"])
        #expect(result.message == "Line 1\n\nLine 3")
        #expect(result.toolCall == "test_tool(arg1)")
    }
    
    @Test("parseToolCallFromString - Wrapped Tool Call with Newlines")
    func testProcessModelResponseWrappedToolCallWithNewlines() throws {
        let content = "Line 1\n<|python_tag|>search_tool(query)<|eom_id|>\nLine 3"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Line 1\n\nLine 3")
        #expect(result.toolCall == "search_tool(query)")
    }
    
    @Test("parseToolCallFromString - Empty Available Tools")
    func testProcessModelResponseEmptyAvailableTools() throws {
        let content = "test_tool(arg1)"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: [])
        #expect(result.message == content)
        #expect(result.toolCall == nil)
    }
    
    @Test("parseToolCallFromString - Tool Call with Quotes in Arguments")
    func testProcessModelResponseToolCallWithQuotes() throws {
        let content = "Query: search_tool(query=\"Hello 'World'\", name=\"test\")"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["search_tool"])
        #expect(result.message == "Query: ")
        #expect(result.toolCall == "search_tool(query=\"Hello 'World'\", name=\"test\")")
    }
    
    // MARK: - Parse Function Tests

        @Test("parse - Basic Tool Call with Unnamed Arguments")
    func testParseBasicToolCallUnnamed() throws {
        let toolCall = ToolCall.parse("search_tool(\"test\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["1"] as? String == "test")
    }
    
    @Test("parse - Basic Tool Call with Unnamed Arguments Unquoted")
    func testParseBasicToolCallUnnamedUnquoted() throws {
        let toolCall = ToolCall.parse("search_tool(test)")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["1"] as? String == "test")
    }
    
    
    @Test("parse - Multiple Unnamed Arguments")
    func testParseMultipleUnnamedArguments() throws {
        let toolCall = ToolCall.parse("calculate_sum(5, 10)")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "calculate_sum")
        #expect(toolCall?.arguments["1"] as? String == "5")
        #expect(toolCall?.arguments["2"] as? String == "10")
    }
    
    @Test("parse - Basic Tool Call with Named Arguments")
    func testParseBasicToolCallNamed() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"test\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "test")
    }
    
    @Test("parse - Multiple Named Arguments")
    func testParseMultipleNamedArguments() throws {
        let toolCall = ToolCall.parse("calculate_sum(a=5, b=10)")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "calculate_sum")
        #expect(toolCall?.arguments["a"] as? String == "5")
        #expect(toolCall?.arguments["b"] as? String == "10")
    }
    
    @Test("parse - No Arguments")
    func testParseNoArguments() throws {
        let toolCall = ToolCall.parse("get_time()")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "get_time")
        #expect(toolCall?.arguments.isEmpty == true)
    }
    
    @Test("parse - Empty Arguments")
    func testParseEmptyArguments() throws {
        let toolCall = ToolCall.parse("get_time( )")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "get_time")
        #expect(toolCall?.arguments.isEmpty == true)
    }
    
    @Test("parse - Single Quoted String")
    func testParseSingleQuotedString() throws {
        let toolCall = ToolCall.parse("search_tool(query='test query')")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "test query")
    }
    
    @Test("parse - Double Quoted String")
    func testParseDoubleQuotedString() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"test query\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "test query")
    }
    
    @Test("parse - Quoted String with Spaces")
    func testParseQuotedStringWithSpaces() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"complex query with spaces\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "complex query with spaces")
    }
    
    @Test("parse - Quoted String with Special Characters")
    func testParseQuotedStringWithSpecialCharacters() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"test@example.com\", path=\"/usr/local/bin\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "test@example.com")
        #expect(toolCall?.arguments["path"] as? String == "/usr/local/bin")
    }
    
    @Test("parse - Quoted String with Embedded Quotes")
    func testParseQuotedStringWithEmbeddedQuotes() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"Hello 'World'\", name=\"test\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "Hello 'World'")
        #expect(toolCall?.arguments["name"] as? String == "test")
    }
    
    @Test("parse - Nested Parentheses in Arguments")
    func testParseNestedParentheses() throws {
        let toolCall = ToolCall.parse("search_tool(options=(limit=10, filter=\"active\"))")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["options"] as? String == "(limit=10, filter=active)")
    }
    
    @Test("parse - Complex Nested Structure")
    func testParseComplexNestedStructure() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"test\", options=(limit=10, filter=\"active\"))")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "test")
        #expect(toolCall?.arguments["options"] as? String == "(limit=10, filter=active)")
    }
    
    @Test("parse - Whitespace Handling")
    func testParseWhitespaceHandling() throws {
        let toolCall = ToolCall.parse("  search_tool  (  query  =  \"test\"  )  ")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "test")
    }
    
    @Test("parse - Function Name with Underscores")
    func testParseFunctionNameWithUnderscores() throws {
        let toolCall = ToolCall.parse("my_custom_tool(param=\"value\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "my_custom_tool")
        #expect(toolCall?.arguments["param"] as? String == "value")
    }
    
    @Test("parse - Function Name with Numbers")
    func testParseFunctionNameWithNumbers() throws {
        let toolCall = ToolCall.parse("tool_123(param=\"value\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "tool_123")
        #expect(toolCall?.arguments["param"] as? String == "value")
    }
    
    @Test("parse - Invalid Format - No Parentheses")
    func testParseInvalidFormatNoParentheses() throws {
        let toolCall = ToolCall.parse("invalid_format")
        #expect(toolCall == nil)
    }
    
    @Test("parse - Invalid Format - Only Opening Parenthesis")
    func testParseInvalidFormatOnlyOpeningParenthesis() throws {
        let toolCall = ToolCall.parse("invalid_format(")
        #expect(toolCall == nil)
    }
    
    @Test("parse - Invalid Format - Only Closing Parenthesis")
    func testParseInvalidFormatOnlyClosingParenthesis() throws {
        let toolCall = ToolCall.parse("invalid_format)")
        #expect(toolCall == nil)
    }
    
    @Test("parse - Invalid Format - Empty Function Name")
    func testParseInvalidFormatEmptyFunctionName() throws {
        let toolCall = ToolCall.parse("(param=\"value\")")
        #expect(toolCall == nil)
    }
    
    @Test("parse - Invalid Format - Empty String")
    func testParseInvalidFormatEmptyString() throws {
        let toolCall = ToolCall.parse("")
        #expect(toolCall == nil)
    }
    
    @Test("parse - Invalid Format - Whitespace Only")
    func testParseInvalidFormatWhitespaceOnly() throws {
        let toolCall = ToolCall.parse("   ")
        #expect(toolCall == nil)
    }
    
    @Test("parse - Unclosed Quote")
    func testParseUnclosedQuote() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"unclosed quote)")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "unclosed quote")
    }
    
    @Test("parse - Mixed Quote Types")
    func testParseMixedQuoteTypes() throws {
        let toolCall = ToolCall.parse("search_tool(query='test', name=\"value\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "test")
        #expect(toolCall?.arguments["name"] as? String == "value")
    }
    
    @Test("parse - Arguments with Commas in Quoted Strings")
    func testParseArgumentsWithCommasInQuotedStrings() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"value1,value2\", filter=\"active,enabled\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "value1,value2")
        #expect(toolCall?.arguments["filter"] as? String == "active,enabled")
    }
    
    @Test("parse - Arguments with Equals in Quoted Strings")
    func testParseArgumentsWithEqualsInQuotedStrings() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"key=value\", filter=\"status=active\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "key=value")
        #expect(toolCall?.arguments["filter"] as? String == "status=active")
    }
    
    @Test("parse - Arguments with Parentheses in Quoted Strings")
    func testParseArgumentsWithParenthesesInQuotedStrings() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"(nested)\", filter=\"(active)\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "(nested)")
        #expect(toolCall?.arguments["filter"] as? String == "(active)")
    }
    
    @Test("parse - Arguments with Newlines in Quoted Strings")
    func testParseArgumentsWithNewlinesInQuotedStrings() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"line1\nline2\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "line1\nline2")
    }
    
    @Test("parse - Arguments with Tabs in Quoted Strings")
    func testParseArgumentsWithTabsInQuotedStrings() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"tab\tseparated\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "tab\tseparated")
    }
    
    @Test("parse - Arguments with Unicode Characters")
    func testParseArgumentsWithUnicodeCharacters() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"café\", name=\"José\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "café")
        #expect(toolCall?.arguments["name"] as? String == "José")
    }
    
    @Test("parse - Arguments with Emoji")
    func testParseArgumentsWithEmoji() throws {
        let toolCall = ToolCall.parse("search_tool(query=\"🚀 rocket\", name=\"🎉 party\")")
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search_tool")
        #expect(toolCall?.arguments["query"] as? String == "🚀 rocket")
        #expect(toolCall?.arguments["name"] as? String == "🎉 party")
    }
    
    // MARK: - JSON Format Tool Call Tests
    
    @Test("extractToolCallStringPlusRange - Direct JSON Format Tool Call")
    func testProcessToolCallsDirectJsonFormat() throws {
        let content = "{\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World I hear you!\"}}"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["echo"])
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World I hear you!\"}}")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Direct JSON Format Tool Call with Surrounding Text")
    func testProcessToolCallsDirectJsonFormatWithSurroundingText() throws {
        let content = "Here is the response: {\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World I hear you!\"}} and more text"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["echo"])
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World I hear you!\"}}")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - Direct JSON Format Tool Call Not in Available Tools")
    func testProcessToolCallsDirectJsonFormatNotAvailable() throws {
        let content = "{\"type\": \"function\", \"name\": \"unknown_tool\", \"parameters\": {\"message\": \"Hello World\"}}"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["echo"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Direct JSON Format Tool Call with Invalid Type")
    func testProcessToolCallsDirectJsonFormatInvalidType() throws {
        let content = "{\"type\": \"message\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World\"}}"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["echo"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("extractToolCallStringPlusRange - Direct JSON Format Tool Call with Invalid JSON")
    func testProcessToolCallsDirectJsonFormatInvalidJson() throws {
        let content = "{\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World\""
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["echo"])
        #expect(result.toolCall == nil)
        #expect(result.range == nil)
    }
    
    @Test("parseToolCallFromString - Direct JSON Format Tool Call")
    func testProcessModelResponseDirectJsonFormat() throws {
        let content = "Here is the response: {\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World I hear you!\"}} and more text"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["echo"])
        #expect(result.message == "Here is the response:  and more text")
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World I hear you!\"}}")
    }
    
    @Test("parse - Direct JSON Format Tool Call")
    func testParseDirectJsonFormat() throws {
        let jsonString = "{\"type\": \"function\", \"name\": \"echo\", \"parameters\": {\"message\": \"Hello World I hear you!\"}}"
        let toolCall = ToolCall.parse(jsonString)
        #expect(toolCall != nil)
        #expect(toolCall?.name == "echo")
        #expect(toolCall?.arguments["message"] as? String == "Hello World I hear you!")
    }
    
    @Test("parse - Direct JSON Format Tool Call with Multiple Parameters")
    func testParseDirectJsonFormatWithMultipleParameters() throws {
        let jsonString = "{\"type\": \"function\", \"name\": \"calculate\", \"parameters\": {\"operation\": \"add\", \"a\": 10, \"b\": 20}}"
        let toolCall = ToolCall.parse(jsonString)
        #expect(toolCall != nil)
        #expect(toolCall?.name == "calculate")
        #expect(toolCall?.arguments["operation"] as? String == "add")
        #expect(toolCall?.arguments["a"] as? Int == 10)
        #expect(toolCall?.arguments["b"] as? Int == 20)
    }
    
    // MARK: - JSON Format Tool Call Tests
    
    @Test("extractToolCallStringPlusRange - JSON Format Tool Call")
    func testProcessToolCallsJsonFormat() throws {
        let content = "<|python_start|>{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}<|python_end|>"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["add"])
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - JSON Format Tool Call with Surrounding Text")
    func testProcessToolCallsJsonFormatWithSurroundingText() throws {
        let content = "Here is the result: <|python_start|>{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}<|python_end|> and more text"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["add"])
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - JSON Format Tool Call with Only Opening Tag")
    func testProcessToolCallsJsonFormatOnlyOpeningTag() throws {
        let content = "Some text <|python_start|>{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}} more text"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["add"])
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}")
        #expect(result.range != nil)
    }
    
    @Test("extractToolCallStringPlusRange - JSON Format Tool Call Not in Available Tools")
    func testProcessToolCallsJsonFormatNotAvailable() throws {
        let content = "<|python_start|>{\"type\": \"function\", \"name\": \"unknown_tool\", \"parameters\": {\"a\": 44123, \"b\": 5532}}<|python_end|>"
        let result = ToolCall.extractToolCallStringPlusRange(content: content, availableTools: ["add"])
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"unknown_tool\", \"parameters\": {\"a\": 44123, \"b\": 5532}}")
        #expect(result.range != nil)
    }
    
    @Test("parseToolCallFromString - JSON Format Tool Call")
    func testProcessModelResponseJsonFormat() throws {
        let content = "Here is the result: <|python_start|>{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}<|python_end|> and more text"
        let result = ToolCall.parseToolCallFromString(content: content, availableTools: ["add"])
        #expect(result.message == "Here is the result:  and more text")
        #expect(result.toolCall == "{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}")
    }
    
    @Test("parse - JSON Format Tool Call")
    func testParseJsonFormat() throws {
        let jsonString = "{\"type\": \"function\", \"name\": \"add\", \"parameters\": {\"a\": 44123, \"b\": 5532}}"
        let toolCall = ToolCall.parse(jsonString)
        #expect(toolCall != nil)
        #expect(toolCall?.name == "add")
        #expect(toolCall?.arguments["a"] as? Int == 44123)
        #expect(toolCall?.arguments["b"] as? Int == 5532)
    }
    
    @Test("parse - JSON Format Tool Call with String Parameters")
    func testParseJsonFormatWithStringParameters() throws {
        let jsonString = "{\"type\": \"function\", \"name\": \"search\", \"parameters\": {\"query\": \"test query\", \"filter\": \"active\"}}"
        let toolCall = ToolCall.parse(jsonString)
        #expect(toolCall != nil)
        #expect(toolCall?.name == "search")
        #expect(toolCall?.arguments["query"] as? String == "test query")
        #expect(toolCall?.arguments["filter"] as? String == "active")
    }
    
    @Test("parse - JSON Format Tool Call with Mixed Parameter Types")
    func testParseJsonFormatWithMixedParameterTypes() throws {
        let jsonString = "{\"type\": \"function\", \"name\": \"calculate\", \"parameters\": {\"operation\": \"add\", \"values\": [1, 2, 3], \"enabled\": true}}"
        let toolCall = ToolCall.parse(jsonString)
        #expect(toolCall != nil)
        #expect(toolCall?.name == "calculate")
        #expect(toolCall?.arguments["operation"] as? String == "add")
        #expect(toolCall?.arguments["enabled"] as? Bool == true)
        // Note: Array parsing would need to be implemented separately
    }
} 
