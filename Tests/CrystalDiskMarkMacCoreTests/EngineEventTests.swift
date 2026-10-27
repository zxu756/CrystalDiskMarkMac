import Testing
import Foundation
@testable import CrystalDiskMarkMacCore

struct EngineEventTests {
    @Test func decodesPhase() throws {
        let event = try EngineEventDecoder.decode(#"{"event":"phase","phase":"create","message":"Creating"}"#)
        #expect(event == .phase(phase: "create", message: "Creating"))
    }

    @Test func decodesRun() throws {
        let event = try EngineEventDecoder.decode(#"{"event":"run","test":"seq","label":"SEQ1M Q8T1","operation":"read","run":0,"warmup":true,"intervalAfterMs":5000}"#)
        #expect(event == .run(
            testID: "seq",
            label: "SEQ1M Q8T1",
            operation: .read,
            run: 0,
            warmup: true,
            intervalAfterMs: 5000
        ))
    }

    @Test func decodesProgress() throws {
        let event = try EngineEventDecoder.decode(#"{"event":"progress","test":"seq","operation":"read","elapsedMs":250,"bytes":1048576}"#)
        #expect(event == .progress(testID: "seq", operation: .read, elapsedMs: 250, bytes: 1_048_576))
    }

    @Test func decodesInterval() throws {
        let event = try EngineEventDecoder.decode(#"{"event":"interval","secondsRemaining":3}"#)
        #expect(event == .interval(secondsRemaining: 3))
    }

    @Test func decodesResult() throws {
        let event = try EngineEventDecoder.decode(#"{"event":"result","test":"seq","operation":"write","run":2,"warmup":false,"mbps":123.5,"iops":456.25,"latencyUs":42.5,"cancelled":false}"#)
        #expect(event == .result(
            testID: "seq",
            operation: .write,
            run: 2,
            warmup: false,
            mbps: 123.5,
            iops: 456.25,
            latencyUs: 42.5,
            cancelled: false
        ))
    }

    @Test func decodesDoneAndError() throws {
        #expect(try EngineEventDecoder.decode(#"{"event":"done","ok":true}"#) == .done(ok: true))
        #expect(try EngineEventDecoder.decode(#"{"event":"error","code":"cancelled","message":"Cancelled"}"#) == .error(code: "cancelled", message: "Cancelled"))
    }

    @Test func rejectsMalformedEvents() {
        #expect(throws: EngineEventError.self) {
            try EngineEventDecoder.decode("not-json")
        }
        #expect(throws: EngineEventError.self) {
            try EngineEventDecoder.decode(#"{"event":"unknown"}"#)
        }
        #expect(throws: EngineEventError.self) {
            try EngineEventDecoder.decode(#"{"event":"result","test":"x"}"#)
        }
    }

    @Test func lineBufferHandlesPartialLines() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"])
        #expect(buffer.append(Data(":2}\n".utf8)) == ["{\"b\":2}"])
    }
}
