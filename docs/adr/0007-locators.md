# ADR 0007: Locators as independent, persistable location values

Status: accepted and implemented.

Readium Kotlin, Swift and TypeScript describe a reading location with one
Locator value that combines a resource href, media type, title, several
location representations and surrounding text. No single representation
survives every change: CFIs break when markup changes, progression shifts when
text is edited, and text context fails for repeated phrases. Adopt the same
shape as immutable Dart values: `Locator`, `Locations` and `LocatorText`.

Hrefs are publication-relative encoded URIs without fragments; fragments live
in `Locations.fragments`, so a locator matches its reading-order link by href.
Constructors validate progression ranges, one-based positions, media types and
JSON-compatible extension values. `fromJson` reports invalid known fields with
`FormatException`, ignores unknown top-level fields and keeps unknown
`locations` fields in `otherLocations`. The content-document CFI is stored in
the Readium `partialCfi` extension as a point; a range is described by its start
point plus `text.highlight`, as Readium highlights are.

The JSON field names follow the Readium Locator model, but no conformance with
a Readium schema is claimed. There is no version field. Later releases may add
optional fields; existing fields change meaning only in a major release.
Applications store the publication identifier next to each locator. Positions
inside a locator are informational because they depend on the position
algorithm; restoration relies on CFI, text, fragments and progression.
