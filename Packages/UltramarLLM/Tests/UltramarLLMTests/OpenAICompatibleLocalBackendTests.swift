import Foundation
import Testing
@testable import UltramarLLM

@Test func openAIRequestAddsQwenReasoningSwitchToLastUserMessage() throws {
    let backend = OpenAICompatibleLocalBackend(
        baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
        session: URLSession(configuration: .ephemeral),
        profile: .qwenServer()
    )
    let request = ChatRequest(
        messages: [
            ChatMessage(role: .user, content: "Hola"),
        ],
        systemPrompt: "System",
        reasoningMode: .finalOnly,
        maxTokens: 64
    )

    let data = try backend.encodedRequestBody(for: request, stream: false)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let messages = try #require(json["messages"] as? [[String: String]])

    #expect(json["stream"] as? Bool == false)
    #expect(messages.first?["role"] == "system")
    #expect(messages.last?["content"] == "Hola /no_think")
}

@Test func openAIBackendParsesNonStreamingResponseAndHidesThinkBlock() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolMock.self]
    let backend = OpenAICompatibleLocalBackend(
        baseURL: URL(string: "http://local.test/v1")!,
        session: URLSession(configuration: configuration),
        profile: .qwenServer()
    )

    let response = try await backend.send(
        request: ChatRequest(messages: [ChatMessage(role: .user, content: "Hola")])
    )

    #expect(response.answer == "Respuesta limpia.")
    #expect(response.hiddenReasoning == "plan interno")
    #expect(response.tokens == 12)
    #expect(response.backend == .server)
}

@Test func openAIBackendParsesServerSentEvents() throws {
    let events = try OpenAICompatibleLocalBackend.parseServerSentEvents(
        """
        data: {"choices":[{"delta":{"content":"Ho"}}]}

        data: {"choices":[{"delta":{"content":"la"}}]}

        data: [DONE]

        """
    )

    #expect(events == [.token("Ho"), .token("la")])
}

private final class URLProtocolMock: URLProtocol {
    static let responseData = """
    {
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": "<think>plan interno</think>Respuesta limpia."
          }
        }
      ],
      "usage": {
        "completion_tokens": 12
      }
    }
    """.data(using: .utf8)!
    static let statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
