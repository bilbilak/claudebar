#!/usr/bin/env python3
"""regenerate-translations.py — emit per-platform translation files from i18n/strings.yaml.

ClaudeBar keeps a single canonical translation source at ``i18n/strings.yaml``.
This script reads that file and writes platform-specific translation artifacts
(gettext ``.po``/``.pot``, Qt ``.ts``, Apple ``.xcstrings``, .NET ``.resx``,
WiX ``.wxl``) into the appropriate locations under ``apps/``.

Usage
-----
    python3 scripts/regenerate-translations.py <platform>
    python3 scripts/regenerate-translations.py --all
    python3 scripts/regenerate-translations.py --help

Platforms
---------
    gnome     -> apps/linux/gnome/po/                         (gettext)
    kde       -> apps/linux/kde/po/                           (gettext)
    cinnamon  -> apps/linux/cinnamon/po/                      (gettext)
    xfce      -> apps/linux/xfce/po/                          (gettext)
    mate      -> apps/linux/mate/po/                          (gettext)
    budgie    -> apps/linux/budgie/po/                        (gettext)
    helper    -> apps/linux/common/claudebar-helper/po/       (gettext, domain claudebar-helper)
    lxqt      -> apps/linux/lxqt/translations/                (Qt .ts XML)
    macos     -> apps/macos/Resources/Localizable.xcstrings   (Xcode String Catalog)
    windows   -> apps/windows/Resources/Strings.<culture>.resx (.NET resx)
    wix       -> apps/windows/installer/loc/<culture>.wxl     (WiX localization)

Requirements
------------
    Python 3.8+, PyYAML.

The script is idempotent: re-running with the same input produces byte-identical
output. Placeholders (%d, %s, %%, \\n) are preserved verbatim.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from xml.sax.saxutils import escape as xml_escape

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write(
        "error: PyYAML is required. Install it with: python3 -m pip install pyyaml\n"
    )
    sys.exit(2)




# Target language codes (excluding the English source).
TARGET_LANGS: Tuple[str, ...] = (
    "fr", "nl", "de", "es", "pt", "sv", "cs", "pl", "ru",
    "uk", "ar", "fa", "zh", "ja", "ko", "tr", "it", "hi",
)

# Mapping from our internal lang code -> Windows/.NET ResX culture name.
RESX_CULTURE: Dict[str, str] = {
    "fr": "fr", "nl": "nl", "de": "de", "es": "es", "pt": "pt", "sv": "sv",
    "cs": "cs", "pl": "pl", "ru": "ru", "uk": "uk", "ar": "ar", "fa": "fa",
    "zh": "zh-Hans", "ja": "ja", "ko": "ko", "tr": "tr", "it": "it", "hi": "hi",
}

# Mapping from our internal lang code -> WiX culture string.
WIX_CULTURE: Dict[str, str] = {
    "fr": "fr-FR", "nl": "nl-NL", "de": "de-DE", "es": "es-ES", "pt": "pt-PT",
    "sv": "sv-SE", "cs": "cs-CZ", "pl": "pl-PL", "ru": "ru-RU", "uk": "uk-UA",
    "ar": "ar-SA", "fa": "fa-IR", "zh": "zh-CN", "ja": "ja-JP", "ko": "ko-KR",
    "tr": "tr-TR", "it": "it-IT", "hi": "hi-IN",
}

# gettext Plural-Forms header values per language.
PLURAL_FORMS: Dict[str, str] = {
    "en": "nplurals=2; plural=(n != 1);",
    "fr": "nplurals=2; plural=(n > 1);",
    "nl": "nplurals=2; plural=(n != 1);",
    "de": "nplurals=2; plural=(n != 1);",
    "es": "nplurals=2; plural=(n != 1);",
    "pt": "nplurals=2; plural=(n != 1);",
    "sv": "nplurals=2; plural=(n != 1);",
    "cs": "nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;",
    "pl": "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "ru": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "uk": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "ar": "nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);",
    "fa": "nplurals=2; plural=(n > 1);",
    "zh": "nplurals=1; plural=0;",
    "ja": "nplurals=1; plural=0;",
    "ko": "nplurals=1; plural=0;",
    "tr": "nplurals=2; plural=(n > 1);",
    "it": "nplurals=2; plural=(n != 1);",
    "hi": "nplurals=2; plural=(n != 1);",
}

REPO_ROOT = Path(__file__).resolve().parent.parent
YAML_PATH = REPO_ROOT / "i18n" / "strings.yaml"

# Platform -> (output_dir, format_kind, extra_metadata)
# format_kind is the dispatch key used in main().
PLATFORMS: Dict[str, Dict[str, str]] = {
    "gnome":    {"dir": "apps/linux/gnome/po",                       "kind": "gettext", "domain": "claudebar"},
    "kde":      {"dir": "apps/linux/kde/po",                         "kind": "gettext", "domain": "claudebar"},
    "cinnamon": {"dir": "apps/linux/cinnamon/po",                    "kind": "gettext", "domain": "claudebar"},
    "xfce":     {"dir": "apps/linux/xfce/po",                        "kind": "gettext", "domain": "claudebar"},
    "mate":     {"dir": "apps/linux/mate/po",                        "kind": "gettext", "domain": "claudebar"},
    "budgie":   {"dir": "apps/linux/budgie/po",                      "kind": "gettext", "domain": "claudebar"},
    "helper":   {"dir": "apps/linux/common/claudebar-helper/po",     "kind": "gettext", "domain": "claudebar-helper"},
    "lxqt":     {"dir": "apps/linux/lxqt/translations",              "kind": "qt_ts"},
    "macos":    {"dir": "apps/macos/Resources",                      "kind": "xcstrings"},
    "windows":  {"dir": "apps/windows/Resources",                    "kind": "resx"},
    "wix":      {"dir": "apps/windows/installer/loc",                "kind": "wxl"},
}




def load_yaml() -> Dict[str, Dict[str, str]]:
    """Load i18n/strings.yaml and return the ``strings`` mapping."""
    if not YAML_PATH.is_file():
        sys.stderr.write(f"error: cannot find {YAML_PATH}\n")
        sys.exit(2)
    with YAML_PATH.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    strings = data.get("strings")
    if not isinstance(strings, dict):
        sys.stderr.write("error: 'strings' key missing or malformed in YAML.\n")
        sys.exit(2)
    return strings


def has_any_translation(strings: Dict[str, Dict[str, str]]) -> bool:
    """Return True if at least one entry has a non-empty French translation.

    Used as the heuristic for 'has the translation agent populated this file yet?'
    """
    for entry in strings.values():
        if not isinstance(entry, dict):
            continue
        fr = entry.get("fr")
        if isinstance(fr, str) and fr.strip():
            return True
    return False


def pascal_case(key: str) -> str:
    """Convert ``menu_refresh_now`` -> ``MenuRefreshNow``."""
    return "".join(part.capitalize() for part in key.split("_") if part)


def write_if_changed(path: Path, content: str) -> bool:
    """Write ``content`` to ``path`` only if it differs from the current contents.

    Returns True if the file was written (created or updated), False if unchanged.
    Ensures parent directories exist. Uses UTF-8 with LF line endings.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    new_bytes = content.encode("utf-8")
    if path.exists():
        try:
            if path.read_bytes() == new_bytes:
                return False
        except OSError:
            pass
    with path.open("wb") as fh:
        fh.write(new_bytes)
    return True




def _po_escape(value: str) -> str:
    """Escape a string for a gettext msgid/msgstr literal."""
    return (
        value.replace("\\", "\\\\")
             .replace("\"", "\\\"")
             .replace("\n", "\\n")
             .replace("\t", "\\t")
    )


def _po_header(domain: str, lang: Optional[str], pot_creation_date: str) -> str:
    """Render the standard PO header block.

    ``lang`` of None denotes the .pot template.
    """
    project_id = f"{domain} 1.0"
    lang_field = "" if lang is None else lang
    plural = PLURAL_FORMS.get(lang or "en", "nplurals=2; plural=(n != 1);")
    lines = [
        "msgid \"\"",
        "msgstr \"\"",
        f"\"Project-Id-Version: {project_id}\\n\"",
        f"\"POT-Creation-Date: {pot_creation_date}\\n\"",
        "\"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\\n\"",
        "\"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\n\"",
        "\"Language-Team: LANGUAGE <LL@li.org>\\n\"",
        f"\"Language: {lang_field}\\n\"",
        "\"MIME-Version: 1.0\\n\"",
        "\"Content-Type: text/plain; charset=UTF-8\\n\"",
        "\"Content-Transfer-Encoding: 8bit\\n\"",
        f"\"Plural-Forms: {plural}\\n\"",
        "",
    ]
    if lang is None:
        # Stamp the template comment block at the very top.
        return (
            "# Translation template for ClaudeBar.\n"
            "# Copyright (C) ClaudeBar contributors.\n"
            "# This file is distributed under the same license as the ClaudeBar package.\n"
            "#\n"
            "#, fuzzy\n"
            + "\n".join(lines)
        )
    return (
        f"# {lang} translation for ClaudeBar.\n"
        "# Copyright (C) ClaudeBar contributors.\n"
        "# This file is distributed under the same license as the ClaudeBar package.\n"
        "#\n"
        + "\n".join(lines)
    )


def _convert_placeholders_to_qt(value: str) -> str:
    """Convert printf-style %d/%s placeholders to Qt-style %1/%2/...

    Used for the KDE plasmoid output only: QML i18n() calls pass %1/%2
    positional placeholders to KI18n, but the master YAML uses %d/%s for
    cross-platform sharing. Translating positionally (in source order)
    keeps msgid lookups byte-aligned with what i18n() actually passes.
    %% stays %%.
    """
    out: List[str] = []
    i = 0
    n = 0
    while i < len(value):
        c = value[i]
        if c == "%" and i + 1 < len(value):
            nxt = value[i + 1]
            if nxt == "%":
                out.append("%%")
                i += 2
                continue
            if nxt in ("d", "s"):
                n += 1
                out.append(f"%{n}")
                i += 2
                continue
        out.append(c)
        i += 1
    return "".join(out)


def _po_entries(
    strings: Dict[str, Dict[str, str]],
    lang: Optional[str],
    placeholder_transform=None,
) -> str:
    """Render the per-string entries of a .po / .pot file.

    Deduplicates by English msgid: when multiple YAML keys map to the same
    English value (e.g. brand_name / window_preferences_title /
    tooltip_default / installer_app_step all = "ClaudeBar"), we emit a
    single .po entry whose comment block lists every contributing key, and
    use the first key's translation for the chosen language.

    ``placeholder_transform``: optional callable applied to both the msgid
    and the translation before they're escaped. KDE uses this to convert
    %d/%s -> %1/%2.
    """
    chunks: List[str] = []
    # English-msgid -> list of (key, note, translation) tuples
    by_msgid: Dict[str, List[Tuple[str, Optional[str], str]]] = {}
    order: List[str] = []
    for key, entry in strings.items():
        if not isinstance(entry, dict):
            continue
        en_val = entry.get("en", "")
        if not isinstance(en_val, str):
            en_val = str(en_val)
        note = entry.get("note") if isinstance(entry.get("note"), str) else None
        if lang is None:
            translated = ""
        else:
            raw = entry.get(lang, "")
            translated = raw if isinstance(raw, str) and raw.strip() else ""
        if en_val not in by_msgid:
            by_msgid[en_val] = []
            order.append(en_val)
        by_msgid[en_val].append((key, note, translated))

    for en_val in order:
        records = by_msgid[en_val]
        # Pick the first non-empty translation across the duplicate keys; in
        # practice they're identical (translations follow the English source),
        # but the fallback keeps things robust.
        chosen_translation = ""
        for _key, _note, t in records:
            if t:
                chosen_translation = t
                break

        msgid_value = en_val
        msgstr_value = chosen_translation
        if placeholder_transform is not None:
            msgid_value = placeholder_transform(msgid_value)
            if msgstr_value:
                msgstr_value = placeholder_transform(msgstr_value)

        block: List[str] = []
        keys = [r[0] for r in records]
        block.append(f"#. key: {', '.join(keys)}")
        # Collect distinct notes across the merged records.
        seen_notes: List[str] = []
        for _k, n, _t in records:
            if n and n not in seen_notes:
                seen_notes.append(n)
        for n in seen_notes:
            for line in n.splitlines():
                block.append(f"#. {line}")
        block.append(f"msgid \"{_po_escape(msgid_value)}\"")
        block.append(f"msgstr \"{_po_escape(msgstr_value)}\"")
        chunks.append("\n".join(block))
    return "\n\n".join(chunks) + "\n"


def emit_gettext(
    strings: Dict[str, Dict[str, str]],
    out_dir: Path,
    domain: str,
    placeholder_transform=None,
) -> List[Path]:
    """Emit ``<domain>.pot`` plus one ``<lang>.po`` per target language.

    ``placeholder_transform``: optional callable applied to both msgid and
    msgstr text. Used by KDE to rewrite %d/%s into Qt-style %1/%2 so that
    runtime i18n() lookups in QML match the .po msgids byte-for-byte.
    """
    written: List[Path] = []
    # Use a fixed POT-Creation-Date so output is deterministic across runs.
    # We pick today's date in UTC at midnight — re-running on the same day is a no-op.
    pot_date = datetime.now(timezone.utc).strftime("%Y-%m-%d 00:00+0000")

    pot_path = out_dir / f"{domain}.pot"
    pot_content = (
        _po_header(domain, None, pot_date)
        + "\n"
        + _po_entries(strings, None, placeholder_transform)
    )
    if write_if_changed(pot_path, pot_content):
        written.append(pot_path)

    for lang in TARGET_LANGS:
        po_path = out_dir / f"{lang}.po"
        content = (
            _po_header(domain, lang, pot_date)
            + "\n"
            + _po_entries(strings, lang, placeholder_transform)
        )
        if write_if_changed(po_path, content):
            written.append(po_path)
    return written




def emit_qt_ts(strings: Dict[str, Dict[str, str]], out_dir: Path) -> List[Path]:
    """Emit one ``claudebar_<lang>.ts`` file per target language."""
    written: List[Path] = []
    for lang in TARGET_LANGS:
        lines: List[str] = []
        lines.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
        lines.append("<!DOCTYPE TS>")
        lines.append(f"<TS version=\"2.1\" language=\"{lang}\" sourcelanguage=\"en\">")
        lines.append("<context>")
        lines.append("    <name>ClaudeBar</name>")
        for key, entry in strings.items():
            if not isinstance(entry, dict):
                continue
            en_val = entry.get("en", "")
            if not isinstance(en_val, str):
                en_val = str(en_val)
            raw = entry.get(lang, "")
            translated = raw if isinstance(raw, str) and raw.strip() else ""
            note = entry.get("note") if isinstance(entry.get("note"), str) else None

            lines.append("    <message>")
            lines.append(f"        <!-- key: {xml_escape(key)} -->")
            if note:
                lines.append(f"        <extracomment>{xml_escape(note)}</extracomment>")
            lines.append(f"        <source>{xml_escape(en_val)}</source>")
            if translated:
                lines.append(f"        <translation>{xml_escape(translated)}</translation>")
            else:
                lines.append("        <translation type=\"unfinished\"></translation>")
            lines.append("    </message>")
        lines.append("</context>")
        lines.append("</TS>")
        lines.append("")
        content = "\n".join(lines)
        path = out_dir / f"claudebar_{lang}.ts"
        if write_if_changed(path, content):
            written.append(path)
    return written




def emit_xcstrings(strings: Dict[str, Dict[str, str]], out_dir: Path) -> List[Path]:
    """Emit a single ``Localizable.xcstrings`` file containing all languages."""
    catalog: Dict[str, object] = {
        "sourceLanguage": "en",
        "strings": {},
        "version": "1.0",
    }
    string_table: Dict[str, Dict[str, object]] = {}
    for key, entry in strings.items():
        if not isinstance(entry, dict):
            continue
        en_val = entry.get("en", "")
        if not isinstance(en_val, str):
            en_val = str(en_val)
        note = entry.get("note") if isinstance(entry.get("note"), str) else None

        localizations: Dict[str, object] = {
            "en": {
                "stringUnit": {
                    "state": "translated",
                    "value": en_val,
                }
            }
        }
        for lang in TARGET_LANGS:
            raw = entry.get(lang, "")
            translated = raw if isinstance(raw, str) and raw.strip() else ""
            if translated:
                localizations[lang] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": translated,
                    }
                }
            else:
                # No translation yet — emit a 'new' stringUnit pointing at the source.
                localizations[lang] = {
                    "stringUnit": {
                        "state": "new",
                        "value": en_val,
                    }
                }

        record: Dict[str, object] = {
            "extractionState": "manual",
            "localizations": localizations,
        }
        if note:
            record["comment"] = note
        # Use the English value as the catalog key (Xcode convention).
        string_table[en_val] = record

    catalog["strings"] = string_table
    path = out_dir / "Localizable.xcstrings"
    # Apple's Xcode writes xcstrings as pretty JSON, sorted keys, 2-space indent.
    content = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if write_if_changed(path, content):
        return [path]
    return []




RESX_HEADER = """<?xml version="1.0" encoding="utf-8"?>
<root>
  <xsd:schema id="root" xmlns="" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:msdata="urn:schemas-microsoft-com:xml-msdata">
    <xsd:import namespace="http://www.w3.org/XML/1998/namespace" />
    <xsd:element name="root" msdata:IsDataSet="true">
      <xsd:complexType>
        <xsd:choice maxOccurs="unbounded">
          <xsd:element name="metadata">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" />
              </xsd:sequence>
              <xsd:attribute name="name" use="required" type="xsd:string" />
              <xsd:attribute name="type" type="xsd:string" />
              <xsd:attribute name="mimetype" type="xsd:string" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="assembly">
            <xsd:complexType>
              <xsd:attribute name="alias" type="xsd:string" />
              <xsd:attribute name="name" type="xsd:string" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="data">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
                <xsd:element name="comment" type="xsd:string" minOccurs="0" msdata:Ordinal="2" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" msdata:Ordinal="1" />
              <xsd:attribute name="type" type="xsd:string" msdata:Ordinal="3" />
              <xsd:attribute name="mimetype" type="xsd:string" msdata:Ordinal="4" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="resheader">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" />
            </xsd:complexType>
          </xsd:element>
        </xsd:choice>
      </xsd:complexType>
    </xsd:element>
  </xsd:schema>
  <resheader name="resmimetype">
    <value>text/microsoft-resx</value>
  </resheader>
  <resheader name="version">
    <value>2.0</value>
  </resheader>
  <resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
  <resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
"""

RESX_FOOTER = "</root>\n"


def _resx_body(strings: Dict[str, Dict[str, str]], lang: Optional[str]) -> str:
    """Build the ``<data>`` entries for a .resx file.

    ``lang`` of None means the default (English) resx.
    """
    parts: List[str] = []
    for key, entry in strings.items():
        if not isinstance(entry, dict):
            continue
        en_val = entry.get("en", "")
        if not isinstance(en_val, str):
            en_val = str(en_val)
        if lang is None:
            value = en_val
        else:
            raw = entry.get(lang, "")
            value = raw if isinstance(raw, str) and raw.strip() else en_val
        note = entry.get("note") if isinstance(entry.get("note"), str) else None
        name = pascal_case(key)
        parts.append(f"  <data name=\"{xml_escape(name)}\" xml:space=\"preserve\">")
        parts.append(f"    <value>{xml_escape(value)}</value>")
        if note:
            parts.append(f"    <comment>{xml_escape(note)}</comment>")
        parts.append("  </data>")
    return "\n".join(parts) + "\n"


def emit_resx(strings: Dict[str, Dict[str, str]], out_dir: Path) -> List[Path]:
    """Emit ``Strings.resx`` (English default) plus one ``Strings.<culture>.resx`` per language."""
    written: List[Path] = []
    default_path = out_dir / "Strings.resx"
    default_content = RESX_HEADER + _resx_body(strings, None) + RESX_FOOTER
    if write_if_changed(default_path, default_content):
        written.append(default_path)
    for lang in TARGET_LANGS:
        culture = RESX_CULTURE[lang]
        path = out_dir / f"Strings.{culture}.resx"
        content = RESX_HEADER + _resx_body(strings, lang) + RESX_FOOTER
        if write_if_changed(path, content):
            written.append(path)
    return written




def _wxl_content(strings: Dict[str, Dict[str, str]], culture: str, lang: Optional[str]) -> str:
    """Build a single .wxl file body.

    ``lang`` of None means the English source file (``en-us.wxl``).
    """
    lines: List[str] = []
    lines.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
    lines.append(
        f"<WixLocalization Culture=\"{culture}\" "
        "xmlns=\"http://wixtoolset.org/schemas/v4/wxl\">"
    )
    for key, entry in strings.items():
        if not isinstance(entry, dict):
            continue
        en_val = entry.get("en", "")
        if not isinstance(en_val, str):
            en_val = str(en_val)
        if lang is None:
            value = en_val
        else:
            raw = entry.get(lang, "")
            value = raw if isinstance(raw, str) and raw.strip() else en_val
        name = pascal_case(key)
        # WiX uses XML attributes, so escape value for an attribute context.
        attr_value = xml_escape(value, {"\"": "&quot;"})
        lines.append(f"  <String Id=\"{xml_escape(name)}\" Value=\"{attr_value}\" />")
    lines.append("</WixLocalization>")
    lines.append("")
    return "\n".join(lines)


def emit_wxl(strings: Dict[str, Dict[str, str]], out_dir: Path) -> List[Path]:
    """Emit ``en-us.wxl`` plus one ``<culture>.wxl`` per target language."""
    written: List[Path] = []
    en_path = out_dir / "en-us.wxl"
    if write_if_changed(en_path, _wxl_content(strings, "en-US", None)):
        written.append(en_path)
    for lang in TARGET_LANGS:
        culture = WIX_CULTURE[lang]
        path = out_dir / f"{culture}.wxl"
        if write_if_changed(path, _wxl_content(strings, culture, lang)):
            written.append(path)
    return written




def generate(platform: str, strings: Dict[str, Dict[str, str]]) -> List[Path]:
    """Run the appropriate emitter for ``platform`` and return paths that changed."""
    meta = PLATFORMS[platform]
    out_dir = REPO_ROOT / meta["dir"]
    out_dir.mkdir(parents=True, exist_ok=True)
    kind = meta["kind"]
    if kind == "gettext":
        # KDE's QML calls i18n() with Qt-style %1/%2 positional placeholders.
        # The shared YAML uses printf-style %d/%s. Convert at emit time so
        # the .po msgids match what i18n() actually looks up at runtime.
        transform = _convert_placeholders_to_qt if platform == "kde" else None
        return emit_gettext(strings, out_dir, meta["domain"], transform)
    if kind == "qt_ts":
        return emit_qt_ts(strings, out_dir)
    if kind == "xcstrings":
        return emit_xcstrings(strings, out_dir)
    if kind == "resx":
        return emit_resx(strings, out_dir)
    if kind == "wxl":
        return emit_wxl(strings, out_dir)
    raise RuntimeError(f"unknown platform kind: {kind}")




def build_parser() -> argparse.ArgumentParser:
    epilog = "Supported platforms:\n" + "\n".join(
        f"  {name:<9} -> {meta['dir']}" for name, meta in PLATFORMS.items()
    )
    parser = argparse.ArgumentParser(
        prog="regenerate-translations.py",
        description="Regenerate per-platform translation files from i18n/strings.yaml.",
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "platform",
        nargs="?",
        choices=sorted(PLATFORMS.keys()),
        help="Platform to regenerate.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Regenerate every supported platform.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Generate even if strings.yaml has no translations yet (uses English fallbacks).",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.all and not args.platform:
        parser.print_help(sys.stderr)
        return 2

    strings = load_yaml()
    translations_present = has_any_translation(strings)
    if not translations_present and not args.force:
        sys.stderr.write(
            "warning: i18n/strings.yaml does not yet contain any non-English translations.\n"
            "        Run the translation agent first, or pass --force to emit English fallbacks.\n"
        )
        return 1

    platforms = sorted(PLATFORMS.keys()) if args.all else [args.platform]

    total_written: List[Path] = []
    for plat in platforms:
        try:
            changed = generate(plat, strings)
        except Exception as exc:  # pragma: no cover - defensive
            sys.stderr.write(f"error: failed to generate {plat}: {exc}\n")
            return 1
        total_written.extend(changed)
        if changed:
            print(f"[{plat}] wrote {len(changed)} file(s):")
            for path in changed:
                try:
                    rel = path.relative_to(REPO_ROOT)
                except ValueError:
                    rel = path
                print(f"    {rel}")
        else:
            print(f"[{plat}] up-to-date (no files changed)")

    print()
    print(f"Summary: {len(total_written)} file(s) written across {len(platforms)} platform(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
