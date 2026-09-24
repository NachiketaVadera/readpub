"""Vendor selected W3C EPUB 3 tests as reproducible EPUB fixtures.

Usage: python3 tool/vendor_w3c_tests.py PATH/TO/epub-tests

PATH/TO/epub-tests is a checkout of https://github.com/w3c/epub-tests at the
commit recorded in SOURCE_COMMIT. Each selected test directory is packaged
without modifying its files: mimetype first and stored, other files deflated,
with fixed timestamps so rebuilding produces identical bytes. Two container
tests cannot be expressed as a directory and are packaged as the suite intends:
ocf-zip-comp with Bzip2-compressed members, and ocf-zip-mult as the final
segment of a split archive (built with Info-ZIP `zip -s`, which must be
installed). Output goes to test/fixtures/w3c with a provenance manifest, the
suite's license statement and the W3C license notice.
"""
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

SOURCE_COMMIT = "4cc654f941fbe297a07877e09280ec3c473f3ec6"
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test/fixtures/w3c"

# Tests whose requirements the conformance checks observe, plus tests that
# require an error. See tool/conformance_checks.dart.
SELECTED = [
    "lay-pp-spine-overrides_image-spine-reflow",
    "nav-non-text_img",
    "nav-non-text_img_title",
    "ocf-font_obfuscation",
    "ocf-font_obfuscation_bis",
    "ocf-metainf-manifest",
    "ocf-package_multiple",
    "ocf-url_link-leaking-relative",
    "ocf-url_link-path-absolute",
    "ocf-url_link-relative",
    "ocf-zip-comp",
    "ocf-zip-mult",
    "pkg-creator-order",
    "pkg-dir-auto_root-rtl",
    "pkg-dir-auto_root-unset",
    "pkg-dir_creator-rtl",
    "pkg-dir_rtl-root-ltr",
    "pkg-dir_rtl-root-unset",
    "pkg-dir_unset-root-rtl",
    "pkg-dir_unset-root-unset",
    "pkg-linked-records",
    "pkg-manifest-unlisted-resource",
    "pkg-meta-whitespace",
    "pkg-spine-duplicate-item-rendering",
    "pkg-title-order",
    "pkg-version-backward",
    "pub-file-urls",
    "pub-foreign_image",
    "pub-foreign_json-spine",
    "pub-foreign_xml-spine",
    "pub-foreign_xml-suffix-spine",
    "pub-xml-external-id",
    "pub-xml-names",
    "pub-xml-non-validating_comment",
    "pub-xml-non-validating_unclosed",
]
DATE = (2026, 9, 16, 0, 0, 0)


NOTICE = """# W3C EPUB 3 test suite notice

The EPUB files in this directory are packaged from tests in the W3C EPUB 3 test
suite, https://github.com/w3c/epub-tests, at commit {commit}, which is licensed
under the W3C Software and Document License - 2023 version. The suite's own
license statement is reproduced in LICENSE.md.

This software or document includes material copied from or derived from the W3C
EPUB 3 test suite (https://github.com/w3c/epub-tests). Copyright © 2021-2026
World Wide Web Consortium. https://www.w3.org/copyright/software-license-2023/

Changes: the files of each test directory were packaged into an EPUB archive
without modification. ocf-zip-comp uses Bzip2-compressed members and
ocf-zip-mult is the final segment of a split archive, as those tests describe.
Package documents keep their original rights statements.

## Software and Document license - 2023 version

This work is being provided by the copyright holders under the following
license.

### License

By obtaining and/or copying this work, you (the licensee) agree that you have
read, understood, and will comply with the following terms and conditions.

Permission to copy, modify, and distribute this work, with or without
modification, for any purpose and without fee or royalty is hereby granted,
provided that you include the following on ALL copies of the work or portions
thereof, including modifications:

1. The full text of this NOTICE in a location viewable to users of the
   redistributed or derivative work.
2. Any pre-existing intellectual property disclaimers, notices, or terms and
   conditions. If none exist, the W3C software and document short notice
   should be included.
3. Notice of any changes or modifications, through a copyright statement on
   the new code or document such as "This software or document includes
   material copied from or derived from [title and URI of the W3C document].
   Copyright © [$year-of-document] World Wide Web Consortium.
   https://www.w3.org/copyright/software-license-2023/"

### Disclaimers

THIS WORK IS PROVIDED "AS IS," AND COPYRIGHT HOLDERS MAKE NO REPRESENTATIONS OR
WARRANTIES, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO, WARRANTIES OF
MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF THE
SOFTWARE OR DOCUMENT WILL NOT INFRINGE ANY THIRD PARTY PATENTS, COPYRIGHTS,
TRADEMARKS OR OTHER RIGHTS.

COPYRIGHT HOLDERS WILL NOT BE LIABLE FOR ANY DIRECT, INDIRECT, SPECIAL OR
CONSEQUENTIAL DAMAGES ARISING OUT OF ANY USE OF THE SOFTWARE OR DOCUMENT.

The name and trademarks of copyright holders may NOT be used in advertising or
publicity pertaining to the work without specific, written prior permission.
Title to copyright in this work will at all times remain with copyright
holders.

Source: https://www.w3.org/copyright/software-license-2023/
"""


def files(directory):
    return sorted(
        path for path in directory.rglob("*")
        if path.is_file() and path.name != ".DS_Store" and path.name != "mimetype"
    )


def package(directory, target, method=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(target, "w") as archive:
        def add(path, name, compression):
            info = zipfile.ZipInfo(name, date_time=DATE)
            info.compress_type = compression
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())

        add(directory / "mimetype", "mimetype", zipfile.ZIP_STORED)
        for path in files(directory):
            add(path, path.relative_to(directory).as_posix(), method)


def split_final_segment(directory, target):
    with tempfile.TemporaryDirectory() as scratch:
        # Copy with fixed timestamps so the split archive does not depend on
        # checkout times.
        copy = Path(scratch) / "content"
        shutil.copytree(directory, copy)
        stamp = datetime(*DATE, tzinfo=timezone.utc).timestamp()
        for path in copy.rglob("*"):
            os.utime(path, (stamp, stamp))
        split = Path(scratch) / "split.zip"
        names = ["mimetype"] + [p.relative_to(copy).as_posix() for p in files(copy)]
        subprocess.run(
            ["zip", "-qX", "-s", "64k", str(split), *names],
            cwd=copy,
            check=True,
            env={**os.environ, "TZ": "UTC"},
        )
        shutil.copyfile(split, target)


def metadata(directory):
    opf = next(directory.rglob("*.opf"))
    text = opf.read_text(encoding="utf-8")
    description = re.search(r"<dc:description[^>]*>(.*?)</dc:description>", text, re.S)
    level = re.search(r'belongs-to-collection"?\s*>\s*([a-z]+)', text)
    return {
        "description": " ".join(description.group(1).split()) if description else None,
        "level": level.group(1) if level else None,
        "references": re.findall(r'isReferencedBy"?\s*>\s*([^<\s]+)', text),
    }


def main():
    checkout = Path(sys.argv[1]).resolve()
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=checkout, capture_output=True, text=True, check=True
    ).stdout.strip()
    if commit != SOURCE_COMMIT:
        sys.exit(f"Expected epub-tests commit {SOURCE_COMMIT}, found {commit}.")
    license_statement = subprocess.run(
        ["git", "show", "HEAD:LICENSE.md"], cwd=checkout, capture_output=True, text=True, check=True
    ).stdout
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    tests = []
    for test in SELECTED:
        directory = checkout / "tests" / test
        target = OUT / f"{test}.epub"
        if test == "ocf-zip-comp":
            package(directory, target, zipfile.ZIP_BZIP2)
            packaging = "Members other than mimetype compressed with Bzip2."
        elif test == "ocf-zip-mult":
            split_final_segment(directory, target)
            packaging = "Final segment of a split archive (Info-ZIP zip -s 64k)."
        else:
            package(directory, target)
            packaging = "Unmodified files; mimetype stored, others deflated."
        tests.append({"id": test, "file": target.name, "packaging": packaging, **metadata(directory)})
    manifest = {
        "source": "https://github.com/w3c/epub-tests",
        "commit": commit,
        "license": "W3C Software and Document License - 2023 version; see LICENSE.md and NOTICE.md",
        "tests": tests,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    (OUT / "LICENSE.md").write_text(license_statement)
    (OUT / "NOTICE.md").write_text(NOTICE.format(commit=commit))
    rows = "\n".join(
        f"| {test['id']} | {test['level'] or '-'} | {test['description']} |" for test in tests
    )
    (OUT / "README.md").write_text(
        "# Vendored W3C EPUB 3 tests\n\n"
        f"Packaged from https://github.com/w3c/epub-tests at commit `{commit}` by\n"
        "`tool/vendor_w3c_tests.py`; see NOTICE.md and LICENSE.md. These files are\n"
        "excluded from the published package. `test/w3c_suite_test.dart` asserts the\n"
        "requirement of each test that this library can observe, using\n"
        "`tool/conformance_checks.dart`. manifest.json records provenance.\n\n"
        "| Test | Level | Requirement |\n|---|---|---|\n" + rows + "\n"
    )
    print(f"Vendored {len(tests)} W3C tests from {commit} into {OUT}")


main()
