//
//  LineBufferTests.swift
//  evoTests
//
//  TDD seam for ClaudeSession: stdout bytes from the `claude` subprocess can
//  arrive split across reads, so line assembly needs to tolerate a chunk
//  boundary landing mid-line.
//

@testable import Evo
import Testing

struct LineBufferTests {
    @Test func emitsCompleteLinesAcrossChunks() {
        var out: [String] = []
        var buf = LineBuffer()
        buf.append("{\"a\":1}\n{\"b\"", emit: { out.append($0) })
        buf.append(":2}\n", emit: { out.append($0) })
        #expect(out == ["{\"a\":1}", "{\"b\":2}"])
    }
}
