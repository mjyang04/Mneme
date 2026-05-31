import XCTest
@testable import MnemeCore

final class AgentTranscriptConnectorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mneme-agent-log-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_connectorParsesCodexMessagesAndRedactsSecrets() throws {
        let log = root.appendingPathComponent("rollout-test.jsonl")
        let fakeOpenAIKey = "sk-" + "abcdefghijklmnopqrstuvwxyz123456"
        let jsonl = """
        {"type":"session_meta","payload":{"id":"session-1","cwd":"/Users/mj/Mneme","git_branch":"develop","cli_version":"codex-test"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Use token=abcdef1234567890 and search docs"}]}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Do not expose \(fakeOpenAIKey)."}]}}
        {"type":"event_msg","payload":{"message":"ignored"}}
        """
        try jsonl.write(to: log, atomically: true, encoding: .utf8)

        let connector = AgentTranscriptConnector(root: root, sourceId: "agent")
        let items = try connector.enumerate()
        XCTAssertEqual(items.map { $0.uri.lastPathComponent }, ["rollout-test.jsonl"])

        let document = try connector.extract(items[0])
        XCTAssertEqual(document.title, "codex · Mneme · rollout-test")
        XCTAssertEqual(document.meta["session_id"], "session-1")
        XCTAssertEqual(document.meta["git_branch"], "develop")
        XCTAssertEqual(document.meta["cwd_name"], "Mneme")
        XCTAssertEqual(document.meta["agent_log_name"], "rollout-test.jsonl")
        XCTAssertNil(document.meta["cwd"])
        XCTAssertNil(document.meta["agent_log_file"])
        XCTAssertTrue(document.text.contains("[user]"))
        XCTAssertTrue(document.text.contains("[assistant]"))
        XCTAssertTrue(document.text.contains("token=[REDACTED_SECRET]"))
        XCTAssertTrue(document.text.contains("[REDACTED_OPENAI_KEY]"))
        XCTAssertFalse(document.text.contains("abcdef1234567890"))
        XCTAssertFalse(document.text.contains(fakeOpenAIKey))
    }

    func test_connectorSkipsSubagentsByDefault() throws {
        let top = root.appendingPathComponent("top.jsonl")
        try #"{"type":"response_item","payload":{"type":"message","role":"user","content":"top"}}"#
            .write(to: top, atomically: true, encoding: .utf8)
        let subagents = root.appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try #"{"type":"response_item","payload":{"type":"message","role":"user","content":"sub"}}"#
            .write(to: subagents.appendingPathComponent("sub.jsonl"), atomically: true, encoding: .utf8)

        let connector = AgentTranscriptConnector(root: root, sourceId: "agent")
        XCTAssertEqual(try connector.enumerate().map { $0.uri.lastPathComponent }, ["top.jsonl"])

        let includingSubagents = AgentTranscriptConnector(root: root, sourceId: "agent", includeSubagents: true)
        XCTAssertEqual(
            try includingSubagents.enumerate().map { $0.uri.lastPathComponent }.sorted(),
            ["sub.jsonl", "top.jsonl"]
        )
    }
}
