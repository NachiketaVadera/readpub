# Dependencies and licenses

Reviewed 2026-09-24 against official pub.dev metadata and local package source.

File I/O and raw DEFLATE use the Dart SDK, without Flutter, platform channels, JNI, FFI or native bindings added
by this package. The initial package targets Dart VM and Flutter host runtimes;
running the package in a browser is not claimed because file, compression and
the render server use dart:io. Browser/WebView clients consume its loopback HTTP
output.

| Direct development dependency | Purpose | License |
|---|---|---|
| test | Standard Dart behavior test runner | BSD 3-Clause |
| lints | Official recommended analyzer rules | BSD 3-Clause |

The locally verified versions and all development-only transitive dependencies
are recorded in pubspec.lock. No dependency source is vendored. Development
package distributions retain their own LICENSE files.

## ZIP alternatives investigated

Current archive 4.3.0 declares path and posix. Posix depends on ffi. Therefore,
using it as a runtime dependency would violate this project's explicit no-FFI
constraint even when only core codec APIs were imported.

Archive 3.6.1 has no FFI dependency, but is an older release. Source inspection
found eager symlink-content decoding in ZipDecoder and unbounded materialization
in ZipFile.content. A robust wrapper needs substantial preflight and output
controls. We chose a narrow ZIP32 index reader plus SDK raw DEFLATE, described in
ADR 0002, rather than pinning an old decoder or copying an entire package.

## EPUB parsing dependencies

| Runtime dependency | Purpose | License |
|---|---|---|
| xml 7.0.1 | Namespace-aware XML DOM and bounded event preflight | MIT |
| crypto 3.0.7 | IDPF SHA-1 font-obfuscation key | BSD 3-Clause |
| collection 1.19.1 | Structural equality for immutable values | BSD 3-Clause |
| html 0.15.7 | Legacy HTML5 parsing for renderer preparation | MIT-style |

Runtime transitives include petitparser (MIT), meta (BSD 3-Clause),
typed_data (BSD 3-Clause), csslib and source_span (BSD 3-Clause). These packages are pure Dart; no FFI or Flutter is introduced.
Versions resolved locally are recorded in pubspec.lock. Source and license
inspection informed the choice; XML and cryptographic primitives are not
reimplemented. XML external resources are never resolved.

Sources: [xml](https://pub.dev/packages/xml),
[crypto](https://pub.dev/packages/crypto),
[collection](https://pub.dev/packages/collection),
[html](https://pub.dev/packages/html).

Sources: [archive current](https://pub.dev/packages/archive),
[archive 3.6.1](https://pub.dev/packages/archive/versions/3.6.1),
[posix](https://pub.dev/packages/posix),
[test](https://pub.dev/packages/test), [lints](https://pub.dev/packages/lints).

## Reading services

Locators, EPUB CFI, text extraction, positions and search add no dependencies.
XHTML is walked with `package:xml` events and legacy HTML with `package:html`,
as in the renderer. The search folding table is generated data committed in
`lib/src/search/folding_table.dart`; regenerating it requires Python 3 but the
package does not. `location_script_test.dart` runs `node --check` only when
Node.js is installed. The benchmark generator uses the Python standard library.
