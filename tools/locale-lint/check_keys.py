#!/usr/bin/env python3
"""Keep Locales/*.lua honest against the strings the addon actually asks for.

Every user-facing string routes through the NE.L seam (see bootstrap.lua), and the keys ARE the
English text. That makes drift invisible at runtime: AceLocale's silent default returns the key,
so a string that never reached enUS.lua looks perfectly fine in English and is simply untranslatable
in every other locale. This script is the check that drift can't hide from.

    python tools/locale-lint/check_keys.py            # report
    python tools/locale-lint/check_keys.py --stubs    # + emit missing entries, ready to paste

Exit status is 1 when enUS is missing a key the source uses, so CI can gate on it.
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOCALES = os.path.join(ROOT, "Locales")
DEFAULT_LOCALE = "enUS"

# Bulk game data, not UI chrome: encounter/boss names the client localizes itself, and enUS aura
# names used as identifiers for API lookups. Translating these by hand would be wrong.
SKIP_FILES = {
    "Data.lua", "DataWotLK.lua", "DataTBC.lua",
    "CdmSpellAuras.lua", "CdmAuraCatalog.lua", "SoundAlertData.lua",
    # Boss ability names and descriptions, sourced from the 1.15/TBC/WotLK spell data. Same
    # category as the Data files: encounter content, translated by whoever sourced it, not chrome.
    "AbilitiesEra.lua", "AbilitiesTBC.lua", "AbilitiesWotLK.lua",
}
# ReferenceAddons is other people's source, kept for reading and gitignored — never ours to
# translate. It also uses the same `L["..."]` idiom, so without this its keys land in the MISSING
# list and `gen_enus.py` (which shares this walk) appends every one of them to enUS.lua.
SKIP_DIRS = {"ReferenceAddons", "Libs", "Locales", "tools", ".git", "Textures", "Sounds", "screenshots"}

# A key is `L["..."]` / `NE.L["..."]`, where the subscript may be several adjacent literals joined
# by `..` and wrapped across lines -- long option descriptions are written that way.
CALL = re.compile(r"(?<![\w.])(?:NE\.)?L\[")
STR = re.compile(r'"((?:[^"\\]|\\.)*)"' + "|'((?:[^'\\\\]|\\\\.)*)'")


def lua_files(base):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            if fn.endswith(".lua") and fn not in SKIP_FILES:
                yield os.path.join(dirpath, fn)


def keys_in_source(text):
    """Yield (key, is_dynamic). Dynamic subscripts (a variable) can't be checked, so we flag them."""
    for m in CALL.finditer(text):
        i, parts, expect_str = m.end(), [], True
        while i < len(text):
            if text[i] in " \t\r\n":
                i += 1
                continue
            if expect_str:
                sm = STR.match(text, i)
                if not sm:
                    yield None, True  # not a literal subscript
                    break
                parts.append(sm.group(1) if sm.group(1) is not None else sm.group(2))
                i, expect_str = sm.end(), False
                continue
            if text.startswith("..", i):
                i, expect_str = i + 2, True
                continue
            if text[i] == "]":
                yield "".join(parts), False
            break


def used_keys():
    used, dynamic = {}, []
    for path in lua_files(ROOT):
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        for key, is_dynamic in keys_in_source(text):
            if is_dynamic:
                dynamic.append(rel)
            else:
                used.setdefault(key, set()).add(rel)
    return used, dynamic


# Calls that put a string in front of the player. A literal reaching one of these without going
# through L is a string no locale can ever translate, which is exactly the drift this catches.
SINKS = (
    "SetText", "SetFormattedText", "AddLine", "AddDoubleLine", "AddSection", "AddText",
    "AddHeading", "AddDescription", "AddMessage", "SetTooltip", "SetTitle", "SetLabel",
)
SINK_CALL = re.compile(r"[:.](" + "|".join(SINKS) + r")\(\s*\"((?:[^\"\\]|\\.)*)\"")
# Table fields the option/control kits render directly.
SINK_FIELD = re.compile(r"\b(label|desc|tooltipText|title|text)\s*=\s*\"((?:[^\"\\]|\\.)*)\"")

# Literals that are not prose: art paths, frame/template names, format scaffolding, punctuation.
NOT_PROSE = re.compile(
    r"^\s*$|^[%s\W\d]*$|^Interface[\\/]|^[A-Za-z_]+[\\/]|Template$|^[A-Z][A-Za-z]*Frame\d*$"
)


# A log prefix like "|cffffcc55DragonUI_NewEra|r [bags]: " is branding, not prose. Strip the colour
# tag and the bracketed tag that follows; what's left has to read as a sentence to count.
COLOR_TAG = re.compile(r"\|c[0-9a-fA-F]{8}.*?\|r|\|[cr]|\[[a-z]+\]|^[\s:>-]+|[\s:>-]+$")


def looks_translatable(text):
    if NOT_PROSE.match(text) or len(text) < 2:
        return False
    stripped = COLOR_TAG.sub("", text).strip()
    # One real word is enough -- single-word labels ("Kalimdor", "Revert") need translating just as
    # much as sentences do. What this rejects is a literal left with no word at all once its colour
    # tag is stripped, which is what a bare log prefix reduces to.
    if not re.search(r"[A-Za-z]{3,}", stripped):
        return False
    return " " in stripped or stripped[0].isupper()


def strip_comments(text):
    """Blank out Lua comments, preserving offsets so reported line numbers stay true.

    Without this the scanner reports commented-out example code as unlocalised strings -- and a
    "fix" applied to a comment is a silent no-op that still looks like progress.
    """
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("--[[", i):
            end = text.find("]]", i)
            end = n if end < 0 else end + 2
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
        elif text.startswith("--", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            out.append(" " * (end - i))
            i = end
        elif text[i] in "\"'":
            q, j = text[i], i + 1
            while j < n and text[j] != q:
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:min(j + 1, n)])
            i = min(j + 1, n)
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


# Literals that stay English on purpose. Keyed by repo-relative file, valued by the reason, so the
# scanner's clean state means "nothing left to do" rather than "six findings everyone ignores".
ALLOWED = {
    "bootstrap.lua":
        "fires before the Locales files load, and says the addon is not coming up",
    "core/_HelloDemo.lua":
        "Sprint-0 developer proof panel; its text reports art-registration state, not player copy",
    "modules/auctionhouse/TabBridge.lua":
        "Auctionator is a third-party addon's name",
    "modules/guild/Window.lua":
        "error passthrough from GuildControlPopupFrame; the payload is a client error string",
    "modules/merchant/Diagnostics.lua":
        "/nemerchant is a developer state dump -- widget names, atlas ids and texcoords, read back "
        "to diagnose a reskin. Not player copy; translating it would make a bug report harder to "
        "read, not easier",
    "modules/detailsskin/DetailsSkin.lua":
        "skin-table metadata handed to Details! for ITS skin list (author/desc, carrying the MIT "
        "attribution), not our chrome; every player-facing string for this module is in its "
        "Register.lua and goes through L",
}


def unlocalised(path, text, honour_allowlist=True):
    """Literals reaching a UI sink without an L[...] wrapper, as (line, sink, text)."""
    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    if honour_allowlist and rel in ALLOWED:
        return []
    text = strip_comments(text)
    out = []
    for pat in (SINK_CALL, SINK_FIELD):
        for m in pat.finditer(text):
            literal = m.group(2)
            if not looks_translatable(literal):
                continue
            out.append((text.count("\n", 0, m.start()) + 1, m.group(1), literal))
    return sorted(out)


# string.format specifiers, and WoW's own inline markup. A translation that drops or reorders a
# specifier does not render oddly -- it throws from string.format, at the moment the tooltip or
# popup is built. Escape/newline counts matter for the same reason.
FORMAT_SPEC = re.compile(r"%[-+ #0-9.]*[diouxXeEfgGqcs%]")
MARKUP = re.compile(r"\|c[0-9a-fA-F]{8}|\|r|\|n|\\n")


def signature(text):
    """The parts of a string a translation must reproduce exactly, in order."""
    return (tuple(FORMAT_SPEC.findall(text)), tuple(sorted(MARKUP.findall(text))))


def locale_values(locale):
    """{key: translated value} for entries carrying a real translation (not `= true`)."""
    path = os.path.join(LOCALES, locale + ".lua")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    out = {}
    for m in re.finditer(r"(?<![\w.])L\[", text):
        i, parts, expect_str = m.end(), [], True
        while i < len(text):
            if text[i] in " \t\r\n":
                i += 1
                continue
            if expect_str:
                sm = STR.match(text, i)
                if not sm:
                    break
                parts.append(sm.group(1) if sm.group(1) is not None else sm.group(2))
                i, expect_str = sm.end(), False
                continue
            if text.startswith("..", i):
                i, expect_str = i + 2, True
                continue
            if text[i] == "]":
                rest = text[i + 1:].lstrip()
                if rest.startswith("="):
                    val, j, vparts = rest[1:].lstrip(), 0, []
                    while True:
                        sm = STR.match(val, j)
                        if not sm:
                            break
                        vparts.append(sm.group(1) if sm.group(1) is not None else sm.group(2))
                        j = sm.end()
                        nxt = val[j:].lstrip()
                        if not nxt.startswith(".."):
                            break
                        j = len(val) - len(nxt) + 2
                    if vparts:
                        out["".join(parts)] = "".join(vparts)
            break
    return out


def verify_locales():
    """Report translations whose placeholders don't match the English key. Returns a failure count."""
    bad = 0
    for locale in sorted(f[:-4] for f in os.listdir(LOCALES) if f.endswith(".lua")):
        if locale == DEFAULT_LOCALE:
            continue
        problems = []
        for key, value in sorted(locale_values(locale).items()):
            want, got = signature(key), signature(value)
            if want != got:
                problems.append((key, value, want, got))
        if problems:
            print("%s: %d placeholder mismatch(es)" % (locale, len(problems)))
            for key, value, want, got in problems:
                print("  key   %s" % key[:100])
                print("  value %s" % value[:100])
                print("  want  %s   got %s" % (want, got))
            bad += len(problems)
    return bad


def locale_keys(locale):
    """Keys a locale file defines, split by whether it carries a real translation or `= true`."""
    path = os.path.join(LOCALES, locale + ".lua")
    if not os.path.exists(path):
        return None, None
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    translated, passthrough = set(), set()
    # `L["key"] = "value"` or `L["key"] = true`, keys wrapped over lines like the source seam.
    for m in re.finditer(r"(?<![\w.])L\[", text):
        i, parts, expect_str = m.end(), [], True
        while i < len(text):
            if text[i] in " \t\r\n":
                i += 1
                continue
            if expect_str:
                sm = STR.match(text, i)
                if not sm:
                    break
                parts.append(sm.group(1) if sm.group(1) is not None else sm.group(2))
                i, expect_str = sm.end(), False
                continue
            if text.startswith("..", i):
                i, expect_str = i + 2, True
                continue
            if text[i] == "]":
                rest = text[i + 1:i + 400].lstrip()
                if rest.startswith("="):
                    key = "".join(parts)
                    (passthrough if rest[1:].lstrip().startswith("true") else translated).add(key)
            break
    return translated, passthrough


def main():
    # Keys carry en dashes and ellipses; a cp1252 console would die on them mid-report.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--stubs", action="store_true", help="emit paste-ready entries for gaps")
    ap.add_argument("--raw", action="store_true",
                    help="list literals reaching a UI sink without going through L")
    ap.add_argument("--verify", action="store_true",
                    help="check every translation reproduces the English placeholders")
    args = ap.parse_args()

    if args.verify:
        bad = verify_locales()
        print("%d placeholder mismatch(es)" % bad)
        return 1 if bad else 0

    if args.raw:
        total = 0
        for rel, why in sorted(ALLOWED.items()):
            print("allowed  %-40s %s" % (rel, why))
        print("")
        for path in lua_files(ROOT):
            with open(path, encoding="utf-8") as fh:
                found = unlocalised(path, fh.read())
            if not found:
                continue
            print("%s (%d)" % (os.path.relpath(path, ROOT).replace("\\", "/"), len(found)))
            for line, sink, literal in found:
                print("  %5d  %-16s %s" % (line, sink, literal[:96]))
            total += len(found)
        print("\n%d literal(s) not routed through L" % total)
        return 1 if total else 0

    used, dynamic = used_keys()
    base_translated, base_passthrough = locale_keys(DEFAULT_LOCALE)
    if base_translated is None:
        sys.exit("Locales/%s.lua not found" % DEFAULT_LOCALE)
    base = base_translated | base_passthrough

    missing = sorted(set(used) - base)
    unused = sorted(base - set(used))

    print("source keys: %d   %s: %d" % (len(used), DEFAULT_LOCALE, len(base)))
    if dynamic:
        seen = sorted(set(dynamic))
        print("dynamic subscripts (not checkable): %d in %s" % (len(dynamic), ", ".join(seen)))

    if missing:
        print("\nMISSING from %s (%d):" % (DEFAULT_LOCALE, len(missing)))
        for key in missing:
            print("  %-60s %s" % (repr(key)[:60], ", ".join(sorted(used[key]))))
    if unused:
        print("\nnot referenced by any source file (%d):" % len(unused))
        for key in unused:
            print("  %s" % repr(key))

    print("\ncoverage")
    for locale in sorted(f[:-4] for f in os.listdir(LOCALES) if f.endswith(".lua")):
        if locale == DEFAULT_LOCALE:
            continue
        translated, passthrough = locale_keys(locale)
        pct = 100.0 * len(translated) / len(base) if base else 0.0
        gap = len(base) - len(translated)
        print("  %-6s %5.1f%%  translated %4d  english %4d  absent %4d"
              % (locale, pct, len(translated), len(passthrough), gap - len(passthrough)))

    if args.stubs and missing:
        print("\n-- paste into Locales/%s.lua" % DEFAULT_LOCALE)
        for key in missing:
            print('L[%s] = true' % ('"%s"' % key.replace('"', '\\"')))

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
