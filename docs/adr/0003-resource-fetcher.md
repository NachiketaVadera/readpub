# ADR 0003: Resource and Fetcher contracts

Status: accepted.

Resource is an asynchronously readable representation with href, optional media
type, length and half-open byte ranges. Fetcher provides optional lookup and
required open, and owns the underlying archive lifetime. Use typed exceptions
rather than platform-specific Result wrappers or generic error strings.

Current Readium mobile toolkits call this container access; TypeScript retains
Fetcher. Keep Fetcher here for the requested API without introducing both names
as redundant layers. Do not require Publication.Link from storage code. A future
fetcher may serve other backends; do not build HTTP or directory providers yet.
String decoding helpers and EPUB charset detection are deferred. Range validation is identical across assets and resources.
