# ADR 0006: Browser rendering over a loopback resource origin

Status: accepted before rendering implementation; active-content removal
amended by ADR 0010 to structure-preserving placeholders.

EPUB content is XHTML, HTML, SVG and CSS. Reimplementing browser layout in Dart
would make typography, images and accessibility incomplete. Expose an ephemeral
loopback HTTP origin so an existing browser or WebView can render the original
publication resources. The core stays pure Dart and contains no Flutter or native
UI code. The renderer adapter owns only its HTTP server; the caller owns the
Publication and closes both explicitly.

Give each session an unpredictable path prefix and bind only to 127.0.0.1. Serve
manifest resources through Publication.resource so font obfuscation and future
resource transforms are applied once. Decode and validate request paths before
lookup; never fetch remote resources. XHTML and HTML responses receive reader CSS
and settings; other resources retain their original bytes and MIME types. Use a
strict Content Security Policy that disables scripts, connections, framing and
remote resources, along with no-sniff and no-referrer headers. The host must keep
JavaScript disabled and decide how outbound links are handled.

For XHTML, use bounded XML events before DOM mutation and preserve the document
namespace. For legacy text/html, use the maintained pure-Dart html parser. Bound
input bytes, element count and depth. Do not change publisher text or inline
styles. Provide scroll and paged CSS modes and simple user settings. Fixed-layout
content gets only viewport sizing and remains browser laid out.

The loopback server is a rendering bridge, not a pagination or browser engine.
Applications may display its chapter URL in a browser or WebView. Browser-specific
page measurement, location persistence and native controls remain host concerns.
