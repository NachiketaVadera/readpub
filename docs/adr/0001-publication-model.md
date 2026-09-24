# ADR 0001: Separate publication values from byte access

Status: accepted; value model implementation deferred.

Readium Kotlin, Swift and TypeScript each expose metadata, reading order, links
and collections separately from resource storage. Adopt those concepts as Dart
immutable values with defensive collections and later JSON serialization. Keep
EPUB XML objects private to the parser. Do not introduce Publication or Link
placeholders now: foundations use Uri and Resource without upward dependencies.
This avoids coupling ZIP APIs to either EPUB or the working package name.
