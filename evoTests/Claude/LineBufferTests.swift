//
//  LineBufferTests.swift
//  evoTests
//
//  TDD seam for ClaudeSession: stdout bytes from the `claude` subprocess can
//  arrive split across reads — including mid-codepoint for multi-byte UTF-8
//  characters — so line assembly needs to buffer at the byte level and only
//  decode complete lines.
//

@testable import Evo
import Foundation
import Testing

struct LineBufferTests {
    @Test func emitsCompleteLinesAcrossChunks() {
        var out: [String] = []
        var buf = LineBuffer()
        buf.append(Data("{\"a\":1}\n{\"b\"".utf8), emit: { out.append($0) })
        buf.append(Data(":2}\n".utf8), emit: { out.append($0) })
        #expect(out == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test func decodesMultiByteCharacterSplitAcrossChunks() {
        // "café 🎉\n" — split the trailing emoji's UTF-8 encoding mid-codepoint.
        let line = "café 🎉"
        let fullBytes = Array(Data((line + "\n").utf8))
        let splitPoint = fullBytes.count - 2 // lands inside the 4-byte emoji encoding
        let firstChunk = Data(fullBytes[0 ..< splitPoint])
        let secondChunk = Data(fullBytes[splitPoint...])

        var out: [String] = []
        var buf = LineBuffer()
        buf.append(firstChunk, emit: { out.append($0) })
        buf.append(secondChunk, emit: { out.append($0) })
        #expect(out == [line])
    }

    @Test func flushEmitsTrailingPartialLine() {
        var out: [String] = []
        var buf = LineBuffer()
        buf.append(Data("{\"a\":1}\n{\"b\":2}".utf8), emit: { out.append($0) })
        #expect(out == ["{\"a\":1}"])
        buf.flush(emit: { out.append($0) })
        #expect(out == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test func flushIsNoOpWhenNoPendingBytes() {
        var out: [String] = []
        var buf = LineBuffer()
        buf.append(Data("{\"a\":1}\n".utf8), emit: { out.append($0) })
        buf.flush(emit: { out.append($0) })
        #expect(out == ["{\"a\":1}"])
    }

    @Test func stripsTrailingCarriageReturn() {
        var out: [String] = []
        var buf = LineBuffer()
        buf.append(Data("{\"a\":1}\r\n".utf8), emit: { out.append($0) })
        #expect(out == ["{\"a\":1}"])
    }
}
