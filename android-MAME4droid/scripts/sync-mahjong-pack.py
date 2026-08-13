# -*- coding: utf-8 -*-
"""Sync mahjong_pack from MAME_Mahjong_Mods + mame_current artwork."""
from __future__ import annotations

import shutil
from datetime import date
from pathlib import Path

MODS = Path(r"D:\Dev\MAMEmjKey\MAME_Mahjong_Mods")
PACK = Path(
    r"D:\Dev\MAME4droid-Mahjong\android-MAME4droid\app\src\main\assets\mahjong_pack"
)
ART_SRC = Path(r"I:\GAMEs\EMU\ARCAD\MAME\mame_current\artwork")
VERSION = date.today().strftime("%Y%m%d") + ".1"

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

    (PACK / "VERSION.txt").write_text(VERSION + "\n", encoding="utf-8")
    print("VERSION", VERSION)

    text = (PACK / "master_lamps.lua").read_text(encoding="utf-8")
    assert (dst_lamps / "output_proxy.lua").is_file()
    assert "apply_device_orientation_view" in text
    assert "output_proxy" in text
    print("OK")


if __name__ == "__main__":
    main()
