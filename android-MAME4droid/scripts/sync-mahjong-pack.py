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
ROOT = PACK.parents[4]  # .../android-MAME4droid
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


def load_groups() -> dict[str, str]:
    """rom -> parent from assets/mahjong_list/groups.txt."""
    path = ROOT / "app" / "src" / "main" / "assets" / "mahjong_list" / "groups.txt"
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for ln in path.read_text(encoding="utf-8").splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        parts = ln.split()
        if len(parts) >= 2:
            out[parts[0]] = parts[1]
    return out


def ensure_master_lamps_pcall_close(text: str) -> str:
    """Close the deferred-load pcall wrapper; Mods source ends with a single end)."""
    if "local ok, err = pcall(function()" not in text:
        return text
    if "if not ok then" in text:
        return text
    text = text.rstrip()
    idx = text.rfind("\nend)")
    if idx == -1:
        raise SystemExit("master_lamps: cannot find closing end)")
    return text[:idx] + (
        "\n    end)\n"
        "    if not ok then\n"
        "        -- swallow so a Lua error cannot blank the classic frontend\n"
        "    end\n"
        "end)\n"
    )


def artwork_targets() -> list[str]:
    """
    Whitelist plus clones that have (or can inherit) artwork.
    Clones listed in groups.txt are required so MAME finds artwork/<rom>/;
    parent-only folders are not enough for clone short names.
    """
    wl = load_whitelist()
    groups = load_groups()
    wanted: set[str] = set(wl)
    for rom, parent in groups.items():
        if (ART_SRC / rom).is_dir():
            wanted.add(rom)
        elif parent in wanted or (ART_SRC / parent).is_dir():
            wanted.add(rom)
    # stable order: whitelist first, then extras
    extra = sorted(wanted - set(wl))
    return list(wl) + extra



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

    wl = artwork_targets()
    art_dir = PACK / "artwork"
    art = {p.name for p in art_dir.iterdir() if p.is_dir()} if art_dir.is_dir() else set()
    missing_art = sorted(set(wl) - art)
    extra_art = sorted(art - set(wl))
    print("artwork targets", len(wl), "(whitelist+clones) pack dirs", len(art))
    if missing_art:
        print("STALE: artwork missing from pack", missing_art)
        stale = True
    if extra_art:
        print("note: pack artwork not in targets", extra_art)

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
    missing_lst = sorted(n for n in load_whitelist() if n.lower() not in lst)
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

    # Defer output_proxy load until a real game runs (classic ___empty frontend
    # blacks out if the proxy is constructed at autoboot parse time).
    top_load = (
        "-- MAME 0.289+：避免 machine.output:set_value 弃用警告刷屏卡顿\n"
        'local fei_output = loadfile("fei_mj_lamps/output_proxy.lua")\n'
        "if fei_output then\n"
        "    _G.fei_output = fei_output()\n"
        "end\n"
        "\n"
        "emu.register_frame_done(function()\n"
        "    if not manager or not manager.machine then return end\n"
        "    local machine = manager.machine\n"
        "    local rom_name = machine.system.name\n"
        '    if not rom_name or rom_name == "___empty" then return end\n'
    )
    top_safe = (
        "-- MAME 0.289+：避免 machine.output:set_value 弃用警告刷屏卡顿\n"
        "-- 勿在脚本顶层 loadfile：经典前端 (___empty) 阶段加载会黑屏只剩 OSC。\n"
        "local function ensure_fei_output()\n"
        "    if _G.fei_output then\n"
        "        return\n"
        "    end\n"
        '    local loader = loadfile("fei_mj_lamps/output_proxy.lua")\n'
        "    if loader then\n"
        "        local ok, factory = pcall(loader)\n"
        "        if ok and factory then\n"
        "            _G.fei_output = factory\n"
        "        end\n"
        "    end\n"
        "end\n"
        "\n"
        "emu.register_frame_done(function()\n"
        "    local ok, err = pcall(function()\n"
        "    if not manager or not manager.machine then return end\n"
        "    local machine = manager.machine\n"
        "    local sys = machine.system\n"
        "    if not sys or not sys.name then return end\n"
        "    local rom_name = sys.name\n"
        '    if rom_name == "___empty" then return end\n'
        "\n"
        "    ensure_fei_output()\n"
    )
    if top_load in merged:
        merged = merged.replace(top_load, top_safe, 1)
        print("deferred output_proxy load for classic frontend safety")
    elif "local ok, err = pcall(function()" in merged:
        print("note: output_proxy defer pattern already present")
    else:
        print("note: output_proxy defer pattern not applied (unexpected format)")

    merged = ensure_master_lamps_pcall_close(merged)
    (PACK / "master_lamps.lua").write_text(merged, encoding="utf-8", newline="\n")
    print("wrote merged master_lamps.lua")

    wl = artwork_targets()
    dst_art = PACK / "artwork"
    dst_art.mkdir(parents=True, exist_ok=True)
    existing = {p.name for p in dst_art.iterdir() if p.is_dir()}
    wanted = set(wl)
    for name in sorted(existing - wanted):
        shutil.rmtree(dst_art / name)
        print("removed stale artwork", name)

    groups = load_groups()
    missing = []
    for name in wl:
        src = ART_SRC / name
        dst = dst_art / name
        if not src.is_dir():
            parent = groups.get(name)
            if parent and (ART_SRC / parent).is_dir():
                src = ART_SRC / parent
                print("artwork inherit", name, "<-", parent)
            else:
                missing.append(name)
                continue
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(
            src,
            dst,
            ignore=shutil.ignore_patterns("*.bak*", "*.bak_diag"),
        )
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
