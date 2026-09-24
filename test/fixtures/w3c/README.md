# Vendored W3C EPUB 3 tests

Packaged from https://github.com/w3c/epub-tests at commit `4cc654f941fbe297a07877e09280ec3c473f3ec6` by
`tool/vendor_w3c_tests.py`; see NOTICE.md and LICENSE.md. These files are
excluded from the published package. `test/w3c_suite_test.dart` asserts the
requirement of each test that this library can observe, using
`tool/conformance_checks.dart`. manifest.json records provenance.

| Test | Level | Requirement |
|---|---|---|
| lay-pp-spine-overrides_image-spine-reflow | - | Reflowable document, with a spine item overriding the global setting to use pre-paginated layout, the pre-paginated page is image in spine with fallback. |
| nav-non-text_img | should | The navigation document contains a normal link, and a link with an image content with alt text. |
| nav-non-text_img_title | should | The navigation document contains a normal link, and a link with an image content with title and alt text. |
| ocf-font_obfuscation | should | An obfuscated (TrueType) font should be displayed after de-obfuscation. |
| ocf-font_obfuscation_bis | should | An obfuscated (TrueType) font should not be displayed after de-obfuscation, because the obfuscation used a different publication id. |
| ocf-metainf-manifest | - | An ancillary manifest file, containing an extra spine item, is present in the META-INF directory; this extra item must be ignored by the reading system. |
| ocf-package_multiple | - | The EPUB contains three valid package files and three corresponding sets of content documents, all referenced by the container.xml file. The reading system must use the first package. |
| ocf-url_link-leaking-relative | - | Use a relative link with several double-dot path segments from the content to a photograph. The folder hierarchy containing the photograph starts at the root level; the relative image reference exceeds depth of hierarchy. |
| ocf-url_link-path-absolute | - | Use a path-absolute link, i.e., beginning with a leading slash, from the content to a photograph. The folder hierarchy containing the photograph starts at the root level. |
| ocf-url_link-relative | - | A simple relative link from the content to a photograph. The folder hierarchy containing the photograph starts at the root level. |
| ocf-zip-comp | - | MUST treat any OCF ZIP container that uses compression techniques other than Deflate as in error. |
| ocf-zip-mult | - | MUST treat any OCF ZIP container that splits the content into segments as in error. |
| pkg-creator-order | - | Several creators are listed in the package document. The reading system must not display them out of order (but it may display only the first). |
| pkg-dir-auto_root-rtl | - | The 'dc:title' element contains text whose proper rendering requires bidi control. The element's 'dir' attribute is set to 'auto' and the 'dir' attribute is set to 'rtl' on the package element; the title should display incorrectly. |
| pkg-dir-auto_root-unset | - | The 'dc:title' element contains text whose proper rendering requires bidi control. The element's 'dir' attribute is set to 'auto'; the title should display incorrectly. |
| pkg-dir_creator-rtl | - | The 'dc:creator' element's 'dir' attribute is set to 'rtl'; the creator's name should display right-to-left. |
| pkg-dir_rtl-root-ltr | - | The 'dc:title' element contains text whose proper rendering requires bidi control. The element's 'dir' attribute is set to 'rtl' and the 'dir' attribute is set to 'ltr' on the 'package' element; the title should display correctly. |
| pkg-dir_rtl-root-unset | - | The 'dc:title' element contains text whose proper rendering requires bidi control. The element's 'dir' attribute is set to 'rtl'; the title should display correctly. |
| pkg-dir_unset-root-rtl | - | The 'dc:title' element contains text whose proper rendering requires bidi control. The root's 'dir' attribute is set to 'rtl'; the title should display correctly. |
| pkg-dir_unset-root-unset | - | The 'dc:title' element contains text whose proper rendering requires bidi control. The element's 'dir' attribute is not set; the title should display incorrectly. |
| pkg-linked-records | should | Reading System must process and display the title and creator metadata from the package document. An ONIX 3.0 format linked metadata record exists, but contains neither title nor creator metadata. |
| pkg-manifest-unlisted-resource | should | The XHTML content references an image that does not appear in the manifest. The image should not be shown. |
| pkg-meta-whitespace | - | The package document's title and creator contain leading and trailing spaces along with excess internal whitespace. The reading system must render only a single space in all cases. |
| pkg-spine-duplicate-item-rendering | - | The spine contains several references to the same content document. The reading system must not skip the duplicates when rendering the reading order. |
| pkg-title-order | - | Several titles are listed in the package document. The reading system must use the first title (and whether to use other titles is not defined). |
| pkg-version-backward | - | “Reading Systems MUST attempt to process an EPUB Publication whose Package Document version attribute is less than "3.0"”. This is an EPUB with package version attribute set to "0", to see if a reading system will open it. |
| pub-file-urls | must | The XHTML content document contains iframes referring to resources on the user's local file system through a file URL. The reading system should refrain from loading these resources. |
| pub-foreign_image | - | An HTML content file contains a PSD image, with a manifest fallback to a PNG image. This tests fallbacks for resources that are not in the spine. |
| pub-foreign_json-spine | - | This EPUB uses a JSON content file in the spine, with a manifest fallback to an HTML document. If the reading system does not support JSON, it should display the HTML. |
| pub-foreign_xml-spine | - | This EPUB uses an ordinary XML content file with mimetype application/xml in the spine, with a manifest fallback to an HTML document. If the reading system does not support XML, it should display the HTML. |
| pub-foreign_xml-suffix-spine | - | This EPUB uses an custom XML content file with mimetype application/dtc+xml in the spine, with a manifest fallback to an HTML document. If the reading system does not support XML, it should display the HTML. |
| pub-xml-external-id | - | The XHTML content document contains a reference to an external entity. The reading system must not resolve it. Reading systems may raise an error on the ingenstion workflow. |
| pub-xml-names | - | An XHTML element has an invalid name with two successive colons. The reading system must produce an error. |
| pub-xml-non-validating_comment | - | This is a test of XML processing. The nav doc should not appear in the spine because the itemref is commented out. |
| pub-xml-non-validating_unclosed | - | An XHTML element does not have a closing tag. The reading system must produce an error. |
