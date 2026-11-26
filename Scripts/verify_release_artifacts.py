#!/usr/bin/env python3

import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Callable

SEMVER_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.(0|[1-9][0-9]*))?$"
)
DIGITS_RE = re.compile(r"^[0-9]+$")
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
FORBIDDEN_ARCH_RE = re.compile(r"x86_64|universal", re.IGNORECASE)
EXPECTED_RPATH = "@executable_path/../Frameworks"

CommandRunner = Callable[[list[str]], subprocess.CompletedProcess[str]]


class VerificationError(Exception):
    pass


def default_runner(
    cmd: list[str], env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=False, env=env)


def fail(msg: str) -> None:
    raise VerificationError(msg)


def load_source_info_plist(plist_path: Path) -> tuple[str, str]:
    if not plist_path.is_file():
        fail(f"Info.plist not found: {plist_path}")
    with plist_path.open("rb") as f:
        data = plistlib.load(f)
    short_ver = data.get("CFBundleShortVersionString")
    if not isinstance(short_ver, str) or not SEMVER_RE.fullmatch(short_ver):
        fail(f"Invalid CFBundleShortVersionString in {plist_path}: {short_ver!r}")
    build_ver = data.get("CFBundleVersion")
    if not isinstance(build_ver, str) or not DIGITS_RE.fullmatch(build_ver) or int(build_ver) <= 0:
        fail(f"Invalid CFBundleVersion in {plist_path}: {build_ver!r}")
    return short_ver, build_ver


def verify_tag_matches(tag: str, short_ver: str) -> str:
    if not tag.startswith("v"):
        fail(f"Tag must start with 'v': {tag!r}")
    semver = tag.removeprefix("v")
    if not SEMVER_RE.fullmatch(semver):
        fail(f"Invalid SemVer tag: {tag!r}")
    if semver != short_ver:
        fail(f"Tag {tag!r} != CFBundleShortVersionString {short_ver!r}")
    return semver


def verify_makefile(
    makefile_path: Path, short_ver: str, build_ver: str, runner: CommandRunner
) -> None:
    if not makefile_path.is_file():
        fail(f"Makefile not found: {makefile_path}")
    text = makefile_path.read_text(encoding="utf-8")
    if re.search(r"BUILD_NUMBER[^\n]*git\s+rev-list", text) or re.search(
        r"git\s+rev-list[^\n]*--count", text
    ):
        fail(f"Makefile must not derive BUILD_NUMBER from git rev-list: {makefile_path}")
    make_dir = str(makefile_path.parent) or "."
    proc = runner(["env", "-u", "VERSION", "-u", "BUILD_NUMBER", "make", "-C", make_dir, "version"])
    if proc.returncode != 0:
        fail(f"make version failed ({proc.returncode}): {proc.stderr.strip()}")
    parsed = {}
    for line in proc.stdout.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            parsed[k.strip()] = v.strip()
    for key, val in (("Version", short_ver), ("Marketing", short_ver), ("Build Number", build_ver)):
        if parsed.get(key) != val:
            fail(f"make version {key} ({parsed.get(key)!r}) != Info.plist ({val!r})")


def verify_otool_rpath(otool_output: str) -> bool:
    in_rpath = False
    for line in otool_output.splitlines():
        s = line.strip()
        if s.startswith("Load command "):
            in_rpath = False
        elif s.startswith("cmd "):
            in_rpath = s == "cmd LC_RPATH"
        elif in_rpath and s.startswith("path ") and EXPECTED_RPATH in s:
            return True
    return False


def verify_app(
    app_path: Path,
    info_plist_path: Path,
    makefile_path: Path | None,
    tag: str | None,
    runner: CommandRunner = default_runner,
) -> None:
    short_ver, build_ver = load_source_info_plist(info_plist_path)
    if makefile_path is not None:
        verify_makefile(makefile_path, short_ver, build_ver, runner)
    if tag is not None:
        verify_tag_matches(tag, short_ver)
    if not app_path.is_dir():
        fail(f"App bundle not found: {app_path}")
    app_plist_path = app_path / "Contents" / "Info.plist"
    if not app_plist_path.is_file():
        fail(f"App Info.plist not found: {app_plist_path}")
    with app_plist_path.open("rb") as f:
        app_plist = plistlib.load(f)
    if app_plist.get("CFBundleShortVersionString") != short_ver:
        fail(f"Bundle CFBundleShortVersionString != {short_ver!r}")
    if app_plist.get("CFBundleVersion") != build_ver:
        fail(f"Bundle CFBundleVersion != {build_ver!r}")
    exe = app_path / "Contents" / "MacOS" / "Lunt"
    if not exe.is_file():
        fail(f"Executable not found: {exe}")
    lipo_proc = runner(["lipo", "-archs", str(exe)])
    if lipo_proc.returncode != 0:
        fail(f"lipo failed ({lipo_proc.returncode}): {lipo_proc.stderr.strip()}")
    if lipo_proc.stdout.strip() != "arm64":
        fail(f"Expected arm64 executable, found {lipo_proc.stdout.strip()!r}")
    sparkle = app_path / "Contents" / "Frameworks" / "Sparkle.framework"
    if not sparkle.is_dir():
        fail(f"Sparkle.framework not found: {sparkle}")
    for rel in (Path("Versions") / "Current", Path("Sparkle")):
        link = sparkle / rel
        if not os.path.islink(link):
            fail(f"Sparkle path is not a symlink: {link}")
        if not link.resolve().exists():
            fail(f"Sparkle symlink target missing: {link}")
    otool_proc = runner(["otool", "-l", str(exe)])
    if otool_proc.returncode != 0:
        fail(f"otool failed ({otool_proc.returncode}): {otool_proc.stderr.strip()}")
    if not verify_otool_rpath(otool_proc.stdout):
        fail(f"Missing LC_RPATH containing {EXPECTED_RPATH} in {exe}")
    sign_proc = runner(["codesign", "--verify", "--deep", "--strict", str(app_path)])
    if sign_proc.returncode != 0:
        fail(f"codesign failed ({sign_proc.returncode}): {sign_proc.stderr.strip()}")


def verify_dmg(
    dmg_path: Path,
    tag: str,
    info_plist_path: Path,
    makefile_path: Path | None,
    runner: CommandRunner = default_runner,
) -> None:
    short_ver, _ = load_source_info_plist(info_plist_path)
    verify_tag_matches(tag, short_ver)
    if not dmg_path.is_file():
        fail(f"DMG not found: {dmg_path}")
    with tempfile.TemporaryDirectory(prefix="lunt-dmg-") as tmp_dir:
        mnt = Path(tmp_dir) / "mnt"
        mnt.mkdir(parents=True, exist_ok=True)
        attached = False
        try:
            proc = runner([
                "hdiutil", "attach", str(dmg_path),
                "-nobrowse", "-readonly", "-mountpoint", str(mnt),
            ])
            if proc.returncode != 0:
                fail(f"hdiutil attach failed ({proc.returncode}): {proc.stderr.strip()}")
            attached = True
            verify_app(mnt / "Lunt.app", info_plist_path, makefile_path, tag, runner)
        finally:
            if attached or os.path.ismount(mnt):
                runner(["hdiutil", "detach", str(mnt), "-quiet"])


def verify_appcast(
    appcast_path: Path,
    tag: str,
    info_plist_path: Path,
    dmg_path: Path | None,
    makefile_path: Path | None = None,
    runner: CommandRunner = default_runner,
) -> None:
    short_ver, build_ver = load_source_info_plist(info_plist_path)
    semver = verify_tag_matches(tag, short_ver)
    if not appcast_path.is_file():
        fail(f"Appcast not found: {appcast_path}")
    raw = appcast_path.read_text(encoding="utf-8")
    if FORBIDDEN_ARCH_RE.search(raw):
        fail(f"Forbidden architecture text ('x86_64' or 'universal') in {appcast_path}")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        fail(f"Invalid XML in {appcast_path}: {exc}")
    items = root.findall(".//item")
    enclosures = root.findall(".//enclosure")
    if len(items) != 1 or len(enclosures) != 1 or enclosures[0] not in items[0].findall(".//enclosure"):
        fail(f"Expected 1 <item> with 1 <enclosure> in {appcast_path}")
    item, enclosure = items[0], enclosures[0]
    ver_el = item.find(f"{{{SPARKLE_NS}}}version")
    ver_txt = None if ver_el is None or ver_el.text is None else ver_el.text.strip()
    if ver_txt != build_ver:
        fail(f"<sparkle:version> ({ver_txt!r}) != CFBundleVersion ({build_ver!r})")
    short_el = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
    short_txt = None if short_el is None or short_el.text is None else short_el.text.strip()
    if short_txt != semver:
        fail(f"<sparkle:shortVersionString> ({short_txt!r}) != tag semver ({semver!r})")
    expected_url = f"https://github.com/samzong/lunt/releases/download/{tag}/Lunt-{semver}-arm64.dmg"
    actual_url = enclosure.attrib.get("url", "")
    if actual_url != expected_url:
        fail(f"<enclosure url> ({actual_url!r}) != {expected_url!r}")
    if dmg_path is not None:
        verify_dmg(dmg_path, tag, info_plist_path, makefile_path, runner)


def write_plist(path: Path, short_ver: str, build_ver: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        plistlib.dump({"CFBundleShortVersionString": short_ver, "CFBundleVersion": build_ver}, f)


def create_synthetic_app(app_path: Path, short_ver: str, build_ver: str) -> None:
    contents = app_path / "Contents"
    macos = contents / "MacOS"
    sparkle = contents / "Frameworks" / "Sparkle.framework"
    ver_b = sparkle / "Versions" / "B"
    macos.mkdir(parents=True, exist_ok=True)
    ver_b.mkdir(parents=True, exist_ok=True)
    write_plist(contents / "Info.plist", short_ver, build_ver)
    (macos / "Lunt").write_bytes(b"\xcf\xfa\xed\xfe")
    (ver_b / "Sparkle").write_bytes(b"\xcf\xfa\xed\xfe")
    os.symlink("B", sparkle / "Versions" / "Current")
    os.symlink("Versions/Current/Sparkle", sparkle / "Sparkle")


def write_synthetic_appcast(path: Path, sparkle_ver: str, short_ver: str, url: str) -> None:
    path.write_text(
        f'<?xml version="1.0" encoding="utf-8"?>\n'
        f'<rss version="2.0" xmlns:sparkle="{SPARKLE_NS}">\n'
        f"  <channel><title>Lunt Updates</title><item>\n"
        f"    <sparkle:version>{sparkle_ver}</sparkle:version>\n"
        f"    <sparkle:shortVersionString>{short_ver}</sparkle:shortVersionString>\n"
        f'    <enclosure url="{url}" type="application/octet-stream" sparkle:os="macos" />\n'
        f"  </item></channel>\n</rss>\n",
        encoding="utf-8",
    )


def assert_fails(label: str, fn: Callable[[], None], fragment: str) -> None:
    try:
        fn()
    except VerificationError as exc:
        if fragment not in str(exc):
            fail(f"Self-test {label} wrong error: {exc}")
        return
    fail(f"Self-test {label} unexpectedly succeeded")


def setup_shallow_clone(tmp_root: Path) -> Path:
    repo_root = Path(__file__).resolve().parent.parent
    if not (repo_root / ".git").exists():
        fail(f"Self-test requires git repository at {repo_root}")
    shallow = tmp_root / "shallow"
    clone = default_runner(["git", "clone", "-q", "--depth", "1", f"file://{repo_root}", str(shallow)])
    if clone.returncode != 0:
        fail(f"Self-test shallow clone failed: {clone.stderr.strip()}")
    cnt = default_runner(["git", "-C", str(shallow), "rev-list", "--count", "HEAD"])
    if cnt.returncode != 0 or cnt.stdout.strip() != "1":
        fail(f"Expected shallow commit count 1, got {cnt.stdout.strip()!r}")
    shutil.copy2(repo_root / "Makefile", shallow / "Makefile")
    shutil.copy2(repo_root / "Sources" / "Lunt" / "Info.plist", shallow / "Sources" / "Lunt" / "Info.plist")
    return shallow


def run_self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="lunt-selftest-") as tmp_str:
        tmp_root = Path(tmp_str)
        shallow = setup_shallow_clone(tmp_root)
        info_plist = shallow / "Sources" / "Lunt" / "Info.plist"
        makefile = shallow / "Makefile"
        short_ver, build_ver = load_source_info_plist(info_plist)
        tag = f"v{short_ver}"
        rpath_ok = {"v": True}

        def stub_runner(cmd: list[str]) -> subprocess.CompletedProcess[str]:
            if cmd[:6] == ["env", "-u", "VERSION", "-u", "BUILD_NUMBER", "make"]:
                return default_runner(cmd)
            if cmd[0] == "lipo":
                return subprocess.CompletedProcess(cmd, 0, "arm64\n", "")
            if cmd[0] == "otool":
                p = EXPECTED_RPATH if rpath_ok["v"] else "/usr/lib/swift"
                return subprocess.CompletedProcess(cmd, 0, f"Load command 20\n cmd LC_RPATH\n cmdsize 48\n path {p} (offset 12)\n", "")
            if cmd[0] == "codesign":
                return subprocess.CompletedProcess(cmd, 0, "", "")
            fail(f"Unexpected tool in self-test: {cmd}")
            raise AssertionError

        valid_app = tmp_root / "valid" / "Lunt.app"
        create_synthetic_app(valid_app, short_ver, build_ver)
        verify_app(valid_app, info_plist, makefile, tag, stub_runner)
        verify_makefile(
            makefile,
            short_ver,
            build_ver,
            lambda c: default_runner(c, env={**os.environ, "VERSION": f"v{short_ver}", "BUILD_NUMBER": "999"}),
        )

        valid_appcast = tmp_root / "appcast.xml"
        valid_url = f"https://github.com/samzong/lunt/releases/download/{tag}/Lunt-{short_ver}-arm64.dmg"
        write_synthetic_appcast(valid_appcast, build_ver, short_ver, valid_url)
        verify_appcast(valid_appcast, tag, info_plist, None, None, stub_runner)

        f1 = tmp_root / "f1" / "Lunt.app"
        create_synthetic_app(f1, short_ver, build_ver)
        shutil.rmtree(f1 / "Contents" / "Frameworks" / "Sparkle.framework")
        assert_fails("missing Sparkle.framework", lambda: verify_app(f1, info_plist, makefile, tag, stub_runner), "Sparkle.framework not found")

        f2 = tmp_root / "f2" / "Lunt.app"
        create_synthetic_app(f2, short_ver, build_ver)
        cur = f2 / "Contents" / "Frameworks" / "Sparkle.framework" / "Versions" / "Current"
        cur.unlink()
        cur.mkdir()
        assert_fails("dereferenced Current", lambda: verify_app(f2, info_plist, makefile, tag, stub_runner), "not a symlink")

        rpath_ok["v"] = False
        assert_fails("missing LC_RPATH", lambda: verify_app(valid_app, info_plist, makefile, tag, stub_runner), "Missing LC_RPATH")
        rpath_ok["v"] = True

        f4 = tmp_root / "f4.xml"
        write_synthetic_appcast(f4, short_ver, short_ver, valid_url)
        assert_fails("sparkle:version marketing", lambda: verify_appcast(f4, tag, info_plist, None, None, stub_runner), "<sparkle:version>")

        f5 = tmp_root / "f5.xml"
        bad_url = f"https://github.com/samzong/lunt/releases/download/{tag}/Lunt-{short_ver}-x86_64.dmg"
        write_synthetic_appcast(f5, build_ver, short_ver, bad_url)
        assert_fails("enclosure x86_64", lambda: verify_appcast(f5, tag, info_plist, None, None, stub_runner), "Forbidden architecture text")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify Lunt app bundle, DMG, and Sparkle appcast metadata.")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--appcast", type=Path)
    parser.add_argument("--dmg", type=Path)
    parser.add_argument("--tag", type=str)
    parser.add_argument("--info-plist", type=Path)
    parser.add_argument("--makefile", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.self_test:
            if any(x is not None for x in (args.app, args.appcast, args.dmg)):
                fail("--self-test cannot be combined with --app, --appcast, or --dmg")
            run_self_test()
            print("OK: self-test passed (shallow clone + 5 fault injections)")
            return 0
        if args.app is None and args.appcast is None and args.dmg is None:
            fail("Specify --self-test, --app, --appcast, or --dmg")
        plist = args.info_plist if args.info_plist is not None else Path("Sources/Lunt/Info.plist")
        makefile = args.makefile if args.makefile is not None else (Path("Makefile") if Path("Makefile").is_file() else None)
        if args.app is not None:
            verify_app(args.app, plist, makefile, args.tag)
            print(f"OK: verified app bundle {args.app}")
        if args.appcast is not None:
            if not args.tag:
                fail("--tag is required with --appcast")
            verify_appcast(args.appcast, args.tag, plist, args.dmg, makefile)
            print(f"OK: verified appcast {args.appcast}")
        elif args.dmg is not None:
            if not args.tag:
                fail("--tag is required with --dmg")
            verify_dmg(args.dmg, args.tag, plist, makefile)
            print(f"OK: verified DMG {args.dmg}")
        return 0
    except VerificationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
