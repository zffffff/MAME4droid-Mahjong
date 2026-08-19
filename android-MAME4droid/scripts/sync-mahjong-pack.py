# -*- coding: utf-8 -*-
"""Sync mahjong_pack from MAME_Mahjong_Mods + mame_current artwork."""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
from datetime import date
from pathlib import Path

MODS = Path(r"D:\Dev\MAMEmjKey\MAME_Mahjong_Mods")
PACK = Path(
    r"D:\Dev\MAME4droid-Mahjong\android-MAME4droid\app\src\main\assets\mahjong_pack"
)
ART_SRC = Path(r"I:\GAMEs\EMU\ARCAD\MAME\mame_current\artwork")
RELEASE = Path(r"D:\Dev\MAMEmjKey\release")

ORIENT_BLOCK = r'''
local last_orient = nil
local orient_check_counter = 0

-- Android writes .device_orientation ("portrait"/"landscape") into the install dir.
-- Switch artwork view to matching Portrait_* / Landscape_* when the phone rotates.
local function apply_device_orientation_view(machine)
    orient_check_counter = orient_check_counter + 1
    if orient_check_counter % 15 ~= 1 then
        return
    end

    local f = io.open(".device_orientation", "r")
    if not f then
        return
    end
    local orient = (f:read("*l") or ""):gsub("%s+", "")
    f:close()
    if orient == "" or orient == last_orient then
        return
    end

    if not machine.render or not machine.render.targets then
        return
    end
    local target = machine.render.targets[1]
    if not target or not target.view_names then
        return
    end

    local want_land = (orient == "landscape")
    local best_i, best_score = nil, -1
    local i = 1
    while true do
        local name = target.view_names[i]
        if not name then
            break
        end
        local score = -1
        local lower = string.lower(name)
        if want_land then
            if name == "Landscape_Touch_Screen" then
                score = 100
            elseif string.find(lower, "landscape_touch", 1, true) then
                score = 80
            elseif string.find(lower, "landscape", 1, true) then
                score = 60
            end
        else
            if name == "Portrait_Touch_Dual_1024x2030" then
                score = 100
            elseif name == "Portrait_Touch_Dual" then
                score = 90
            elseif name == "Portrait_2_Rows" then
                score = 80
            elseif string.find(lower, "portrait", 1, true) then
                score = 60
            end
        end
        if score > best_score then
            best_score = score
            best_i = i
        end
        i = i + 1
    end

    if best_i and best_score >= 0 then
        local ok, err = pcall(function()
            target.view_index = best_i
        end)
        if ok then
            last_orient = orient
        end
    else
        last_orient = orient
    end
end
'''.lstrip("\n")


def pack_version() -> str:
    p = PACK / "VERSION.txt"
    if not p.is_file():
        return ""
    return p.read_text(encoding="utf-8").strip()


def next_version() -> str:
    today = date.today().strftime("%Y%m%d")
    cur = pack_version()
    if cur.startswith(today + "."):
        try:
            n = int(cur.split(".", 1)[1])
            return f"{today}.{n + 1}"
        except ValueError:
            pass
    return today + ".1"


def latest_release_stamp() -> str:
    if not RELEASE.is_dir():
        return ""
    best = ""
    for p in RELEASE.iterdir():
        m = re.search(r"(20\d{6})", p.name)
        if m and m.group(1) > best:
            best = m.group(1)
    return best


def file_hashes(root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not root.is_dir():
        return out
    for p in root.rglob("*"):
        if p.is_file():
            out[p.relative_to(root).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def load_whitelist() -> list[str]:
    return [
        ln.strip()
        for ln in (MODS / "白名单.txt").read_text(encoding="utf-8").splitlines()
        if ln.strip()
    ]


def lst_keys(name: str) -> set[str]:
    keys: set[str] = set()
    p = PACK / name
    if not p.is_file():
        return keys
    for ln in p.read_text(encoding="utf-8-sig").splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        key = ln.split("\t", 1)[0].split()[0].strip().lower()
        if key:
            keys.add(key)
    return keys


def check() -> int:
    """Read-only. Exit 0 if pack matches Mods; 1 if stale; 2 if Mods missing."""
    if not MODS.is_dir():
        print("Mods not found:", MODS)
        return 2

    stale = False
    ver = pack_version()
    rel = latest_release_stamp()
    print("pack VERSION", ver or "(missing)")
    print("latest Mods release stamp", rel or "(none)")
    if rel and ver and not ver.startswith(rel):
        pack_day = ver.split(".", 1)[0]
        if pack_day < rel:
            print("STALE: pack date", pack_day, "< release", rel)
            stale = True

    wl = load_whitelist()
    art_dir = PACK / "artwork"
    art = {p.name for p in art_dir.iterdir() if p.is_dir()} if art_dir.is_dir() else set()
    missing_art = sorted(set(wl) - art)
    extra_art = sorted(art - set(wl))
    print("whitelist", len(wl), "pack artwork dirs", len(art))
    if missing_art:
        print("STALE: artwork missing from pack", missing_art)
        stale = True
    if extra_art:
        print("note: pack artwork not in whitelist", extra_art)

    mods_lamps = file_hashes(MODS / "fei_mj_lamps")
    pack_lamps = file_hashes(PACK / "fei_mj_lamps")
    only_mods = sorted(set(mods_lamps) - set(pack_lamps))
    only_pack = sorted(set(pack_lamps) - set(mods_lamps))
    changed = sorted(k for k in set(mods_lamps) & set(pack_lamps) if mods_lamps[k] != pack_lamps[k])
    if only_mods:
        print("STALE: lua only in Mods", only_mods)
        stale = True
    if only_pack:
        print("note: lua only in pack", only_pack)
    if changed:
        print("STALE: lua changed", changed)
        stale = True

    master = PACK / "master_lamps.lua"
    text = master.read_text(encoding="utf-8") if master.is_file() else ""
    if "apply_device_orientation_view" not in text:
        print("STALE: pack master_lamps missing orientation bridge")
        stale = True

    lst = lst_keys("mame.lst")
    missing_lst = sorted(n for n in wl if n.lower() not in lst)
    if missing_lst:
        print("WARN: whitelist not in mame.lst (sync script does not copy lst)", missing_lst)

    if stale:
        print("RESULT stale — run this script without --check before the next APK")
        return 1
    print("RESULT ok — pack matches Mods lamps + whitelist")
    return 0


def main() -> None:
    dst_lamps = PACK / "fei_mj_lamps"
    if dst_lamps.exists():
        shutil.rmtree(dst_lamps)
    shutil.copytree(MODS / "fei_mj_lamps", dst_lamps)
    print("synced fei_mj_lamps", len(list(dst_lamps.rglob("*"))))

    mods_master = (MODS / "master_lamps.lua").read_text(encoding="utf-8")
    needle = "local module_loaded = false\n"
    if needle not in mods_master:
        raise SystemExit("unexpected master_lamps format: module_loaded")
    merged = mods_master.replace(needle, needle + "\n" + ORIENT_BLOCK + "\n", 1)

    hook_old = (
        '    if not rom_name or rom_name == "___empty" then return end\n'
        '    local screen = machine.screens[":screen"]'
    )
    hook_new = (
        '    if not rom_name or rom_name == "___empty" then return end\n'
        "\n"
        "    apply_device_orientation_view(machine)\n"
        "\n"
        '    local screen = machine.screens[":screen"]'
    )
    if hook_old not in merged:
        raise SystemExit("unexpected master_lamps format: hook")
    merged = merged.replace(hook_old, hook_new, 1)
    (PACK / "master_lamps.lua").write_text(merged, encoding="utf-8", newline="\n")
    print("wrote merged master_lamps.lua")

    wl = [
        ln.strip()
        for ln in (MODS / "白名单.txt").read_text(encoding="utf-8").splitlines()
        if ln.strip()
    ]
    dst_art = PACK / "artwork"
    dst_art.mkdir(parents=True, exist_ok=True)
    existing = {p.name for p in dst_art.iterdir() if p.is_dir()}
    wanted = set(wl)
    for name in sorted(existing - wanted):
        shutil.rmtree(dst_art / name)
        print("removed stale artwork", name)

    missing = []
    for name in wl:
        src = ART_SRC / name
        dst = dst_art / name
        if not src.is_dir():
            missing.append(name)
            continue
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    print("artwork synced", len(wl) - len(missing), "missing", missing)

    version = next_version()
    (PACK / "VERSION.txt").write_text(version + "\n", encoding="utf-8")
    print("VERSION", version)

    text = (PACK / "master_lamps.lua").read_text(encoding="utf-8")
    assert (dst_lamps / "output_proxy.lua").is_file()
    assert "apply_device_orientation_view" in text
    assert "output_proxy" in text
    print("OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sync or check mahjong_pack against Mods")
    parser.add_argument(
        "--check",
        action="store_true",
        help="read-only: exit 1 if pack is behind Mods (do not copy)",
    )
    args = parser.parse_args()
    if args.check:
        sys.exit(check())
    main()
