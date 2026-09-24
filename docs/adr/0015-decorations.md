# ADR 0015: Decorations drawn as an overlay

Status: accepted and implemented.

The Flutter reader draws highlights and underlines, collectively decorations,
for locators. Applications own the decorations and their storage; the
controller draws them. `ReaderController.applyDecorations(group, list)`
replaces a named group, such as highlights or search results, and
`onDecorationActivated` reports taps on them. Each decoration is a
`Locator`, as produced by `selectionLocator` or `locatorForTextRange`, an id
and a style. Locators are resolved with `ReadingServices.resolve`, so a
decoration saved for an earlier edition of a book is drawn where its text is
found. One that resolves only to a point, by fragment or progression, is not
drawn, because drawing unrelated text would be worse than drawing nothing.

Three rendering approaches were considered:

- Wrapping text in `mark` elements changes the element and text-node
  structure that CFIs count, so every location computed in the page would
  disagree with `DocumentText`.
- The CSS Custom Highlight API leaves the DOM alone and paints behind text,
  but needs iOS 17.2 or later, allows only a few properties in
  `::highlight()`, and has no hit testing.
- Absolutely positioned marks over the text work in every supported WebView
  and allow any style, at the cost of following layout and scrolling
  ourselves. Readium uses this approach.

The reader uses the overlay. `readerDecorationScript` appends one
`readpub-decorations` element to the root element, after the body, and draws
into its shadow tree. The content's structure, and therefore every CFI, is
unchanged; author styles do not reach the marks; and the element ignores
pointer events and selection. Marks cover the client rects of text nodes only,
not the boxes of contained elements, so a highlight across paragraphs does not
fill the margin between them. Each decoration is translucent as a whole with
opaque marks, so overlapping marks do not darken. On light pages the overlay
multiplies with the page, keeping text crisp as a marker does; on dark pages
it is composited normally.

Scrolled chapters scroll the document, and the overlay is positioned in
document coordinates so it moves natively. Paged chapters scroll the body
horizontally, so the overlay is fixed to the viewport and translated on
scroll events, which browsers dispatch before painting the scrolled frame.
Marks are redrawn after resizes, resource loads, font loads and size changes
observed by a `ResizeObserver`. A tap on a mark is reported with the tap
point and the decoration's visible bounds and suppresses the ordinary tap, so
it never turns a page; links inside decorated text still work.

Integration tests on the iOS simulator and an Android emulator measure the
drawn marks against the text they decorate, in paged and scrolled flows,
after page turns, relayout, theme and chapter changes. Writing them exposed a
WebKit behavior: a script may scroll past the end of the document until the
native scroll view corrects it, so pages briefly reported positions that were
never displayed. `readerLocationScript` now clamps its scrolling.

Annotation storage, notes attached to decorations and custom styles beyond
highlights and underlines are left to applications or later work.
