# ADR 0011: Readium CSS evaluated and deferred

Status: accepted; adoption deferred.

Readium CSS v2.0.5 (published 2026-05-13, BSD 3-Clause, copyright 2017
Readium) was evaluated as a replacement for the renderer's original reader CSS.
Its distribution contains `ReadiumCSS-before.css` (about 15 KB), which must
precede author styles, `ReadiumCSS-after.css` (about 20 KB), which follows
them, `ReadiumCSS-default.css` for documents without author styles, a font
patch, and separate right-to-left, horizontal CJK and vertical CJK variants.
User settings are CSS custom properties that the reading system sets on the
root element. Version 2.0.0 (2026-02-25) was a breaking rewrite with a
migration guide.

Adoption is technically compatible with the location contract: the stylesheets
can be served as session-origin resources, custom properties can be set through
the root element's `style` attribute without scripts, and inserting a stylesheet
link at the start of the head does not change body CFIs. It is deferred because
it requires vendoring about 40 KB of CSS per variant with its license, choosing
variants from language and progression metadata, mapping `ReaderSettings` to
Readium properties, and verifying typography and pagination on the target
WebViews. That verification needs real Flutter devices, which this package
does not yet have; claiming Readium CSS compatibility without it would be
misleading. Revisit when a Flutter reader exists; pin a release, vendor it under
`packages/readpub/lib/src/render/assets` with its license and attribution, and extend the
rendering and location tests before switching.
