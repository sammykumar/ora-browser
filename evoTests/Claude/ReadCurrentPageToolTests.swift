//
//  ReadCurrentPageToolTests.swift
//  evoTests
//
//  TDD for the `read_current_page` MCP tool handler — pure, provider-driven
//  logic exercised here with a stub `ActiveTabTextProvider` (no live WebKit,
//  no MCP transport).
//

@testable import Evo
import Testing

private final class StubProvider: ActiveTabTextProvider {
    let result: Swift.Result<String, PageReadError>
    init(_ r: Swift.Result<String, PageReadError>) {
        result = r
    }

    func currentPageText() async -> Swift.Result<String, PageReadError> {
        result
    }
}

struct ReadCurrentPageToolTests {
    @Test func returnsPageText() async {
        let out = await ReadCurrentPageTool.run(provider: StubProvider(.success("Hello page")))
        #expect(out.text == "Hello page")
        #expect(out.isError == false)
    }

    @Test func reportsNoActiveTab() async {
        let out = await ReadCurrentPageTool.run(provider: StubProvider(.failure(.noActiveTab)))
        #expect(out.isError == true)
        #expect(out.text.contains("no active tab"))
    }

    @Test func reportsNilProvider() async {
        let out = await ReadCurrentPageTool.run(provider: nil)
        #expect(out.isError == true)
    }
}
