// Wire-aware opt-in marker. Its presence tells the consuming target's
// WireBuildPlugin that this library participates in cross-module
// composition; the plugin re-parses these sources and merges the
// `@Singleton`/`@Provides` bindings declared here into the consumer's
// graph. Presence-only — the file needs no contents.
