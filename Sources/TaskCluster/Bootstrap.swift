import BasicContainers
import Configuration
import HTTPAPIs
import HTTPTypes
import Logging
import NIOHTTPServer
import Wire
import WireMVC
import WireMVCRouter

// The composition root, and the whole of this target's entry point.
//
// There is no `main.swift` and no hand-written `@main`. `@WireMVCBootstrap` makes WireMVCRouteGen generate
// the entry point from this type: it runs `prepare()`, bootstraps the graph with what `prepare()` returned,
// reads this binding off the graph, asks it for the server and the route builder, registers **every**
// collated route contributor onto that builder, mounts introspection, registers the `@NotFound` fallback,
// freezes the builder into a router and serves it alongside the graph's collated services.
//
// "Every collated route contributor" is what replaced `buildApplication`. An `@Operation` on an
// `@OpenAPIController` contributes to `WireMVCKeys.routeContributors` exactly as a `@Get` does, so the four
// task operations and the health route arrive through one registration pass and share one router, one
// `@NotFound` and one set of error tiers. Nothing here names OpenAPI — which is the same property the
// Hummingbird `WireMVCServerTransport.apply` call had, now with no host framework underneath it.

/// The graph's inputs — read before any binding is constructed and handed to `Wire.bootstrap(inputs:)`.
///
/// The `ConfigReader` is the honest case for an input. It reads the environment, which is a deployment
/// fact rather than something the graph derives, and it has to exist before the first binding that reads a
/// key. It used to be an ordinary `@Provides` in `ApplicationWiring` *and* be constructed a second time in
/// `main` to read the port; as an input there is one reader, built once, in the one place that runs first.
@GraphInputs
package struct AppInputs: Sendable {
    package let config: ConfigReader
    package let serverConfig: ServerConfig
}

/// Where the server binds. Separate from `ConfigReader` because it is read on the production path only —
/// under test the harness owns the transport and binds its own port, and never calls `createServer()`.
package struct ServerConfig: Sendable {
    package let host: String
    package let port: Int
}

@Singleton
@WireMVCBootstrap
package struct AppBootstrap {
    @Inject let config: ServerConfig

    /// The pre-step: runs before the graph exists, and its return value is the graph's `inputs:`.
    ///
    /// `LoggingSystem.bootstrap` is why this has to be pre-graph rather than a binding — it traps on a
    /// second call, and the unbound default logger is captured at first access, so bootstrapping after the
    /// graph is built leaves every binding constructed so far holding a logger that ignores this handler.
    /// Being pre-graph it can inject nothing; that is the trade for running first.
    package static func prepare() async throws -> AppInputs {
        LoggingSystem.bootstrap { StreamLogHandler.standardOutput(label: $0) }

        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        return AppInputs(
            config: config,
            serverConfig: ServerConfig(
                host: config.string(forKey: "HTTP_HOST", default: "0.0.0.0"),
                port: config.int(forKey: "HTTP_PORT", default: 8080)
            )
        )
    }

    /// Returns the *concrete* server rather than `some HTTPServer`: the proposal's `Reader` and
    /// `ResponseSender` are `~Copyable`, which a bare opaque return cannot express. The generated entry
    /// point binds to whatever concrete type this returns, and wraps it in `WireMVCContextServer` itself.
    package func createServer() throws -> NIOHTTPServer {
        NIOHTTPServer(
            logger: Logger(label: "TaskCluster"),
            configuration: try .init(
                bindTarget: .hostAndPort(host: config.host, port: config.port),
                supportedHTTPVersions: [.http1_1],
                transportSecurity: .plaintext
            )
        )
    }

    /// `TrieRouteBuilder` is wire-mvc's `FinalizableHTTPServerRouteBuilder`: routes are registered onto it,
    /// then the generated entry point `finalize()`s it into the immutable router the server serves —
    /// build, freeze, serve.
    package func createRouteBuilder<Server: HTTPServer>(
        for server: borrowing Server
    ) -> some FinalizableHTTPServerRouteBuilder<Server.RequestContext, Server.Reader, Server.ResponseSender>
    where
        Server.RequestContext: ~Copyable,
        Server.Reader: ~Copyable,
        Server.ResponseSender: ~Copyable,
        Server.ResponseSender.Writer: ~Copyable
    {
        TrieRouteBuilder(for: server)
    }

    /// The graph's wiring model as JSON, at the path `WireMVCServerTransport.mountIntrospection` used to
    /// put it. Registered before `finalize()`, so it is a real route rather than a special case.
    package func mountIntrospectionAt() -> String? { "/wiring" }

    /// The fallback for unmatched requests. Registered via `registerNotFound` before `finalize()`, so the
    /// global tiers fold into it — which is the reason to write one rather than let the plugin synthesise
    /// a bare 404: a fallback is the response nobody declares, and so the easiest place to lose the header
    /// fields a global middleware contributed.
    @NotFound
    @RawRoute
    package func notFound<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        var body = UniqueArray<UInt8>(copying: Array(#"{"message":"not found"}"#.utf8))
        try await responseSender.sendAndFinish(
            HTTPResponse(status: .notFound, headerFields: [.contentType: "application/json"]),
            buffer: &body
        )
    }
}
