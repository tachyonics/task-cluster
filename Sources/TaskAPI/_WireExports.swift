// Wire-aware opt-in marker. It carries no bindings — only the OpenAPI document and the types
// swift-openapi-generator makes from it — but its presence is what tells a consuming target's
// WireOpenAPIGen to *read* the document here. Without it the module is skipped and
// `@OpenAPIController(spec: "TaskAPI")` resolves to nothing.
