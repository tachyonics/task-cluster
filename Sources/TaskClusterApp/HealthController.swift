import Wire
import WireMVC

// The liveness probe, which used to be the one hand-written route on the Hummingbird router:
//
//     router.get("/health") { _, _ in HTTPResponse.Status.ok }
//
// There is no router to hang it off any more, and nowhere for a hand-registered route to go — the
// generated entry point registers what the graph collated and nothing else. So it becomes what every other
// route in this app already is: a collated `@Controller`, arriving at the builder in the same pass as the
// OpenAPI operations. It also stops being a special case in a second way — the global middleware and error
// tiers fold into it exactly as they do into an operation, where before it sat outside `apply` entirely.
//
// Deliberately not in the OpenAPI document: `/health` is an operational endpoint for the deployment, not
// part of the API the document describes. Being able to say that — an annotation-driven route beside a
// document-driven one, under one router — is what M6d bought.

@Singleton
@Controller("/health")
package struct HealthController {
    @Inject package init() {}

    /// 200 with an empty body. `@ResponseStatus` rather than `@JSONResponse` because there is nothing to
    /// encode; a probe reads the status line.
    @Get
    @ResponseStatus(.ok)
    package func health() {}
}
