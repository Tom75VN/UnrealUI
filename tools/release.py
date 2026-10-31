"""Validate and prepare UnrealUI changelog-driven releases.

  python -B tools/release.py check
  python -B tools/release.py notes [VERSION]
  python -B tools/release.py prepare [--minor|--major]

`prepare` turns [Unreleased] into the next dated version and updates every
player-facing version field. Commit the result, create the matching `v*` tag,
and push it; GitHub Actions publishes that version's changelog entry.
"""

import argparse
import datetime
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "CHANGELOG.md"
TOC = ROOT / "unrealUI.toc"
INIT = ROOT / "core" / "init.lua"
README = ROOT / "README.md"
UNRELEASED = "Unreleased"
CATEGORIES = ("Added", "Changed", "Fixed", "Removed", "Security")
MAX_ITEM_LENGTH = 160

VERSION_HEADING = re.compile(r"^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})$")


class Entry:
    def __init__(self, version, date, line):
        self.version = version
        self.date = date
        self.line = line
        self.body = []

    def key(self):
        return tuple(int(part) for part in self.version.split("."))

    def text(self):
        return "\n".join(self.body).strip()


def _validate_body(body, label, line, allow_empty):
    errors = []
    category = None
    categories = set()
    item_count = 0
    for offset, value in enumerate(body, 1):
        number = line + offset
        if not value.strip():
            continue
        if value.startswith("### "):
            category = value[4:]
            if category not in CATEGORIES:
                errors.append("line %d: unknown category %r" % (number, category))
            elif category in categories:
                errors.append("line %d: duplicate category %r" % (number, category))
            categories.add(category)
        elif value.startswith("- "):
            if category is None:
                errors.append("line %d: changelog item needs a category" % number)
            if not value[2:].strip():
                errors.append("line %d: empty changelog item" % number)
            if len(value) > MAX_ITEM_LENGTH:
                errors.append("line %d: changelog item exceeds %d characters" %
                              (number, MAX_ITEM_LENGTH))
            item_count += 1
        else:
            errors.append("line %d: use one-line '- ' player-facing items only" % number)
    if not allow_empty and item_count == 0:
        errors.append("line %d: %s lists no changes" % (line, label))
    return item_count, errors


def parse(text):
    unreleased = None
    unreleased_line = None
    entries = []
    errors = []
    current = None

    for number, line in enumerate(text.splitlines(), 1):
        if not line.startswith("## "):
            if current is not None:
                current.append(line)
            continue

        match = VERSION_HEADING.match(line)
        if line == "## [%s]" % UNRELEASED:
            if unreleased is not None or entries:
                errors.append("line %d: [Unreleased] must appear once before every version" % number)
            unreleased = []
            unreleased_line = number
            current = unreleased
        elif match:
            entry = Entry(match.group(1), match.group(2), number)
            entries.append(entry)
            current = entry.body
        else:
            errors.append("line %d: expected '## [a.b.c] - YYYY-MM-DD'" % number)
            current = None

    if unreleased is None:
        errors.append("missing ## [Unreleased]")
        unreleased = []
        unreleased_line = 1
    _, body_errors = _validate_body(unreleased, UNRELEASED, unreleased_line, True)
    errors.extend(body_errors)

    if not entries:
        errors.append("no released version entries")
    for entry in entries:
        try:
            datetime.date.fromisoformat(entry.date)
        except ValueError:
            errors.append("line %d: invalid date %s" % (entry.line, entry.date))
        _, body_errors = _validate_body(entry.body, entry.version, entry.line, False)
        errors.extend(body_errors)

    for newer, older in zip(entries, entries[1:]):
        if newer.key() <= older.key():
            errors.append("line %d: %s must be newer than %s below it" %
                          (newer.line, newer.version, older.version))
        if newer.date < older.date:
            errors.append("line %d: %s is dated before %s" %
                          (newer.line, newer.version, older.version))
    return unreleased, entries, errors


def _match(path, pattern, label):
    text = path.read_bytes().decode("utf-8")
    match = re.search(pattern, text, re.M)
    if not match:
        raise SystemExit("cannot read %s from %s" % (label, path.relative_to(ROOT)))
    return match.group(1)


def project_versions():
    return {
        "unrealUI.toc": _match(TOC, r"^## Version: (\S+)\r?$", "version"),
        "core/init.lua": _match(INIT, r'^U\.version\s*=\s*"([^"]+)"\r?$', "version"),
        "README.md": _match(README, r"^Current release: \*\*(\d+\.\d+\.\d+)\*\*\r?$", "version"),
    }


def load(release=None):
    text = CHANGELOG.read_bytes().decode("utf-8")
    unreleased, entries, errors = parse(text)
    versions = project_versions()
    current = next(iter(versions.values()))
    for path, version in versions.items():
        if version != current:
            errors.append("%s is %s but the addon version is %s" % (path, version, current))
    if entries and entries[0].version != current:
        errors.append("latest changelog version is %s but the addon version is %s" %
                      (entries[0].version, current))
    if release:
        if release != current:
            errors.append("release %s does not match addon version %s" % (release, current))
        items, _ = _validate_body(unreleased, UNRELEASED, 1, True)
        if items:
            errors.append("[Unreleased] still contains changes; run release.py prepare first")
    return text, current, unreleased, entries, errors


def bumped(version, part):
    major, minor, patch = (int(value) for value in version.split("."))
    if part == "major":
        return "%d.0.0" % (major + 1)
    if part == "minor":
        return "%d.%d.0" % (major, minor + 1)
    return "%d.%d.%d" % (major, minor, patch + 1)


def prepared(text, version, unreleased, part, today):
    items, _ = _validate_body(unreleased, UNRELEASED, 1, True)
    if not items:
        raise SystemExit("[Unreleased] lists no changes: nothing to release")
    new_version = bumped(version, part)
    lines = text.splitlines()
    start = lines.index("## [%s]" % UNRELEASED)
    end = start + 1
    while end < len(lines) and not lines[end].startswith("## "):
        end += 1
    body = "\n".join(unreleased).strip()
    heading = "## [%s] - %s" % (new_version, today)
    output = lines[:start + 1] + ["", heading, "", body, ""] + lines[end:]
    return "\n".join(output).rstrip("\n") + "\n", new_version


def _replace_once(path, pattern, value):
    source = path.read_bytes().decode("utf-8")
    source, count = re.subn(pattern, value, source, count=1, flags=re.M)
    if count != 1:
        raise SystemExit("cannot update %s" % path.relative_to(ROOT))
    path.write_bytes(source.encode("utf-8"))


def prepare(part):
    text, version, unreleased, _, errors = load()
    if errors:
        raise SystemExit("CHANGELOG.md:\n  " + "\n  ".join(errors))
    text, new_version = prepared(text, version, unreleased, part,
                                 datetime.date.today().isoformat())
    CHANGELOG.write_bytes(text.encode("utf-8"))
    _replace_once(TOC, r"^## Version: \S+(?=\r?$)", "## Version: " + new_version)
    _replace_once(INIT, r'^U\.version\s*=\s*"[^"]+"(?=\r?$)',
                  'U.version   = "%s"' % new_version)
    _replace_once(README, r"^Current release: \*\*\d+\.\d+\.\d+\*\*(?=\r?$)",
                  "Current release: **%s**" % new_version)
    print("%s -> %s. Review and commit, then create and push tag v%s."
          % (version, new_version, new_version))


def notes(entries, version):
    for entry in entries:
        if entry.version == version:
            return entry.text() + "\n"
    raise SystemExit("no changelog entry for %s" % version)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check")
    check.add_argument("--release")
    show = commands.add_parser("notes")
    show.add_argument("version", nargs="?")
    prep = commands.add_parser("prepare")
    part = prep.add_mutually_exclusive_group()
    part.add_argument("--minor", dest="part", action="store_const", const="minor")
    part.add_argument("--major", dest="part", action="store_const", const="major")
    args = parser.parse_args()

    if args.command == "prepare":
        prepare(args.part or "patch")
        return
    _, current, _, entries, errors = load(args.release if args.command == "check" else None)
    if errors:
        raise SystemExit("CHANGELOG.md:\n  " + "\n  ".join(errors))
    if args.command == "check":
        print("CHANGELOG.md: OK (%s)" % current)
    else:
        print(notes(entries, args.version or current), end="")


if __name__ == "__main__":
    main()
