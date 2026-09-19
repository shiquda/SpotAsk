#!/usr/bin/env python3
"""Fail closed if a Sparkle appcast is missing signatures, notes, or public-key match."""

from __future__ import annotations

import argparse
import base64
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ED25519_SPKI_PREFIX = bytes.fromhex("302a300506032b6570032100")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def local_name(tag: str) -> str:
    return tag.split("}", 1)[-1]


def enclosure_attr(elem: ET.Element, name: str) -> str | None:
    direct = elem.attrib.get(name)
    if direct:
        return direct
    namespaced = elem.attrib.get(f"{{{SPARKLE_NS}}}{name}")
    if namespaced:
        return namespaced
    for key, value in elem.attrib.items():
        if local_name(key) == name or key.endswith(f":{name}"):
            return value
    return None


def xml_lang(elem: ET.Element) -> str | None:
    for key, value in elem.attrib.items():
        if key == "{http://www.w3.org/XML/1998/namespace}lang" or key == "xml:lang" or key.endswith(":lang") or key == "lang":
            return value
    return None


def public_key_from_plist(path: Path) -> str:
    with path.open("rb") as handle:
        plist = plistlib.load(handle)
    key = plist.get("SUPublicEDKey")
    if not isinstance(key, str) or not key.strip():
        fail(f"SUPublicEDKey is missing from {path}")
    return key.strip()


def pem_from_public_key(public_b64: str) -> bytes:
    raw = base64.b64decode(public_b64)
    if len(raw) != 32:
        fail(f"SUPublicEDKey must decode to 32 bytes, got {len(raw)}")
    der = ED25519_SPKI_PREFIX + raw
    converted = subprocess.run(
        ["openssl", "pkey", "-pubin", "-inform", "DER", "-outform", "PEM"],
        input=der,
        capture_output=True,
        check=False,
    )
    if converted.returncode != 0:
        fail(converted.stderr.decode() or "Unable to convert SUPublicEDKey to PEM")
    return converted.stdout


def verify_signature(archive: Path, signature_b64: str, public_b64: str) -> None:
    try:
        signature = base64.b64decode(signature_b64, validate=True)
    except Exception:
        fail(f"sparkle:edSignature is not valid base64 in {archive.name}")
    if len(signature) != 64:
        fail(f"sparkle:edSignature for {archive.name} must be 64 bytes, got {len(signature)}")

    pem = pem_from_public_key(public_b64)
    with tempfile.TemporaryDirectory() as tmp:
        pem_path = Path(tmp) / "pub.pem"
        sig_path = Path(tmp) / "sig.bin"
        pem_path.write_bytes(pem)
        sig_path.write_bytes(signature)
        result = subprocess.run(
            [
                "openssl",
                "pkeyutl",
                "-verify",
                "-pubin",
                "-inkey",
                str(pem_path),
                "-rawin",
                "-in",
                str(archive),
                "-sigfile",
                str(sig_path),
            ],
            capture_output=True,
            text=True,
        )
    if result.returncode != 0:
        fail(
            f"sparkle:edSignature for {archive.name} does not match SUPublicEDKey: "
            f"{(result.stderr or result.stdout).strip()}"
        )


def text_content(elem: ET.Element | None) -> str:
    if elem is None:
        return ""
    parts = [elem.text or ""]
    for child in list(elem):
        parts.append(text_content(child))
        parts.append(child.tail or "")
    return "".join(parts)


def verify_appcast(
    xml_path: Path,
    archive: Path,
    public_b64: str,
    notes_token: str | None,
    notes_zh_token: str | None = None,
    bilingual: bool = False,
) -> None:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    items = [elem for elem in root.iter() if local_name(elem.tag) == "item"]
    if not items:
        fail(f"{xml_path.name} has no Sparkle items")

    matched = False
    for item in items:
        for enclosure in item.iter():
            if local_name(enclosure.tag) != "enclosure":
                continue
            url = enclosure_attr(enclosure, "url") or ""
            if Path(url).name != archive.name and not url.endswith("/" + archive.name):
                continue
            matched = True
            signature = enclosure_attr(enclosure, "edSignature")
            if not signature:
                fail(f"{xml_path.name} enclosure for {archive.name} is missing sparkle:edSignature")
            verify_signature(archive, signature, public_b64)

        for child in item.iter():
            if local_name(child.tag) == "releaseNotesLink":
                fail(f"{xml_path.name} uses sparkle:releaseNotesLink; notes must be embedded")

        desc_elems = [
            child for child in item.iter() if local_name(child.tag) == "description"
        ]
        if len(desc_elems) > 1:
            for d in desc_elems:
                if not xml_lang(d):
                    fail(
                        f"{xml_path.name} has multiple descriptions but at least one lacks xml:lang"
                    )

        if notes_token and notes_zh_token:
            en_desc = [d for d in desc_elems if xml_lang(d) in ("en", "en-US")]
            if not en_desc:
                fail(f'{xml_path.name} is missing description with xml:lang="en"')
            if not any(notes_token in text_content(d) for d in en_desc):
                fail(
                    f"{xml_path.name} English description does not contain {notes_token!r}"
                )

            zh_desc = [
                d for d in desc_elems if xml_lang(d) in ("zh-CN", "zh-Hans", "zh")
            ]
            if not zh_desc:
                fail(f'{xml_path.name} is missing description with xml:lang="zh-CN"')
            if not any(notes_zh_token in text_content(d) for d in zh_desc):
                fail(
                    f"{xml_path.name} Chinese description does not contain {notes_zh_token!r}"
                )

            for d in en_desc + zh_desc:
                fmt = enclosure_attr(d, "format")
                if fmt != "markdown":
                    fail(f"{xml_path.name} description format must be 'markdown', got {fmt!r}")
        elif bilingual:
            en_desc = [d for d in desc_elems if xml_lang(d) in ("en", "en-US")]
            if not en_desc:
                fail(f'{xml_path.name} is missing description with xml:lang="en"')
            zh_desc = [
                d for d in desc_elems if xml_lang(d) in ("zh-CN", "zh-Hans", "zh")
            ]
            if not zh_desc:
                fail(f'{xml_path.name} is missing description with xml:lang="zh-CN"')
            if notes_token and not any(notes_token in text_content(d) for d in en_desc):
                fail(f"{xml_path.name} English description does not contain {notes_token!r}")
            if notes_zh_token and not any(notes_zh_token in text_content(d) for d in zh_desc):
                fail(f"{xml_path.name} Chinese description does not contain {notes_zh_token!r}")
        elif notes_token:
            descriptions = [text_content(child) for child in desc_elems]
            if not any(notes_token in description for description in descriptions):
                fail(f"{xml_path.name} does not embed release notes containing {notes_token!r}")
        elif notes_zh_token:
            zh_desc = [
                d for d in desc_elems if xml_lang(d) in ("zh-CN", "zh-Hans", "zh")
            ]
            if not zh_desc or not any(notes_zh_token in text_content(d) for d in zh_desc):
                fail(
                    f"{xml_path.name} does not embed Chinese release notes containing {notes_zh_token!r}"
                )

    if not matched:
        fail(f"{xml_path.name} has no enclosure for {archive.name}")

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--public-key")
    parser.add_argument("--info-plist", type=Path)
    parser.add_argument("--notes-token")
    parser.add_argument("--notes-zh-token")
    parser.add_argument("--notes-token-zh", dest="notes_zh_token")
    parser.add_argument("--bilingual", action="store_true")
    args = parser.parse_args()

    if not args.xml.is_file():
        fail(f"appcast is missing: {args.xml}")
    if not args.archive.is_file():
        fail(f"archive is missing: {args.archive}")

    public_b64 = args.public_key
    if not public_b64:
        if not args.info_plist:
            fail("Pass --public-key or --info-plist")
        public_b64 = public_key_from_plist(args.info_plist)

    verify_appcast(
        args.xml,
        args.archive,
        public_b64,
        args.notes_token,
        args.notes_zh_token,
        args.bilingual,
    )
    print(f"Verified {args.xml.name} against {args.archive.name}")


if __name__ == "__main__":
    main()
