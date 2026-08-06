import Logging
import ServiceLifecycle
import Wire

// Teardown, as a service the app owns.
//
// This used to come from `WireHummingbird.teardownService`. The M6d port drops wire-hummingbird
// altogether: operations are WireMVC routes now, so routing and introspection both come from
// `WireMVCServerTransport`, and teardown was the only thing left. It could not come along regardless —
// wire-hummingbird pins swift-syntax to the 603 line, which the 6.4 line this package now sits on cannot
// satisfy.
//
// Nothing is lost in the move. `Teardownable` is a swift-wire protocol and every graph conforms, so this
// is framework-free: ServiceLifecycle, Wire, and a logger.

/// A service that runs `graph.teardown()` at shutdown.
///
/// **Prepend** it to the services handed to `Application(services:)`. ServiceLifecycle shuts services
/// down in reverse registration order, so the first-registered teardown service shuts down *last* —
/// resources drain only after every other service, the HTTP server included, has stopped.
package struct GraphTeardownService: Service {
    let graph: any Teardownable & Sendable
    let logger: Logger

    package init(graph: some Teardownable & Sendable, logger: Logger) {
        self.graph = graph
        self.logger = logger
    }

    package func run() async throws {
        // Suspend until this service is asked to shut down, gracefully or by cancellation; either way,
        // run teardown afterwards. Teardown errors are logged rather than failing shutdown — a resource
        // that cannot close cleanly should not stop the rest from trying.
        try? await gracefulShutdown()
        for error in await graph.teardown() {
            logger.error("Wire graph teardown action failed", metadata: ["error": "\(error)"])
        }
    }
}
