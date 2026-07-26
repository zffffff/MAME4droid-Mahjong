-- fei_mj_lamps/jantouki.lua
-- 雀斗记 (jantouki) W 筐体：探针读下屏 bottom VRAM（512×240）
-- jantouki_ui_mode: 0=打牌 1=狩猎 2=手帐 3=选人 4=配牌 5=Last Chance
-- jantouki_char_a~d: 选人界面=1；jantouki_letter_vis: 0=touch_up 1~6=touch_up_l+ui_mode
local DEBUG_UI_PROBE = false

return function(machine, screen, screen_top, blink_state)
    local out = machine.output
    local w, h = screen.width, screen.height
    local REF_W, REF_H = 508, 240

    local function shot_xy(sx, sy)
        local x = math.floor(sx * w / REF_W + 0.5)
        local bias = 16 * (REF_H - sy) / REF_H
        local y = math.floor((sy + bias) * h / REF_H + 0.5)
        if x < 0 then x = 0 elseif x >= w then x = w - 1 end
        if y < 0 then y = 0 elseif y >= h then y = h - 1 end
        return x, y
    end

    local function clamp_v(vx, vy)
        if vx < 0 then vx = 0 elseif vx >= w then vx = w - 1 end
        if vy < 0 then vy = 0 elseif vy >= h then vy = h - 1 end
        return vx, vy
    end

    local HUNT_P1 = { 34, 231 }
    local HUNT_P2 = { 64, 231 }
    local HUNT_P3 = { 185, 213 }

    local function shot_bottom_vy(sy)
        return (sy - 240) + 16
    end

    -- 选人：512×480 截图 y=435, x=48~51 → bottom VRAM vy=shot_bottom_vy(435)=211
    local CHAR_PROBE = {
        { 48, shot_bottom_vy(435), 0, 99, 0 },
        { 49, shot_bottom_vy(435), 239, 239, 231 },
        { 50, shot_bottom_vy(435), 115, 33, 0 },
        { 51, shot_bottom_vy(435), 198, 74, 0 },
    }

    -- 配牌：512×480 截图 (140,248~250) → bottom VRAM vy=shot_bottom_vy(sy)
    local WS_PROBE = {
        { 140, shot_bottom_vy(248), 255, 255, 255 },
        { 140, shot_bottom_vy(249), 173, 165, 156 },
        { 140, shot_bottom_vy(250), 148, 0, 0 },
    }

    -- Last Chance：下屏 VRAM 直读；jantouki 背景与 mcnpshnt 不同，LC_1 白点 @ (96,106)
    local LC_PROBE = {
        { 96, 106, 255, 255, 255 },
        { 97, 106, 173, 165, 156 },
        { 99, 106, 148, 0, 0 },
    }

    local function rgb(c)
        if not c then return nil, nil, nil end
        return (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
    end

    local function pixel_rgb(vx, vy, do_clamp)
        if do_clamp then vx, vy = clamp_v(vx, vy) end
        return rgb(screen:pixel(vx, vy))
    end

    local function match_v(vx, vy, tr, tg, tb, do_clamp)
        if do_clamp == nil then do_clamp = true end
        local r, g, b = pixel_rgb(vx, vy, do_clamp)
        if not r then return false end
        return r == tr and g == tg and b == tb
    end

    local function match_shot(sx, sy, tr, tg, tb)
        local r, g, b = rgb(screen:pixel(shot_xy(sx, sy)))
        if not r then return false end
        return r == tr and g == tg and b == tb
    end

    local function is_red(vx, vy)
        local r, g, b = pixel_rgb(vx, vy, true)
        if not r then return false end
        return r > 200 and g < 50 and b < 50
    end

    if is_red(226, 208) then out:set_value("lamp_pon", blink_state) else out:set_value("lamp_pon", 0) end
    if is_red(188, 208) then out:set_value("lamp_chi", blink_state) else out:set_value("lamp_chi", 0) end
    if is_red(226, 196) then out:set_value("lamp_ron", blink_state) else out:set_value("lamp_ron", 0) end
    if is_red(188, 196) then out:set_value("lamp_kan", blink_state) else out:set_value("lamp_kan", 0) end

    local function is_character_select()
        for _, p in ipairs(CHAR_PROBE) do
            if not match_v(p[1], p[2], p[3], p[4], p[5]) then
                return false
            end
        end
        return true
    end

    local function is_hunt_ad()
        return match_shot(HUNT_P1[1], HUNT_P1[2], 255, 206, 90)
            and match_shot(HUNT_P2[1], HUNT_P2[2], 255, 206, 90)
            and match_shot(HUNT_P3[1], HUNT_P3[2], 66, 198, 173)
    end

    local function is_notebook_ag()
        return match_shot(88, 212, 49, 49, 49)
            and match_shot(92, 212, 66, 198, 173)
    end

    local function is_tile_select()
        for _, p in ipairs(WS_PROBE) do
            if not match_v(p[1], p[2], p[3], p[4], p[5]) then
                return false
            end
        end
        return true
    end

    local function is_last_chance()
        for _, p in ipairs(LC_PROBE) do
            if not match_v(p[1], p[2], p[3], p[4], p[5]) then
                return false
            end
        end
        return true
    end

    local is_char = is_character_select()
    local is_lc = not is_char and is_last_chance()
    local is_ws = not is_char and not is_lc and is_tile_select()
    local is_hunt = not is_char and not is_lc and not is_ws and is_hunt_ad()
    local is_notebook = not is_char and not is_lc and not is_ws and is_notebook_ag()

    local ui_mode = 0
    if is_char then ui_mode = 3
    elseif is_lc then ui_mode = 5
    elseif is_ws then ui_mode = 4
    elseif is_notebook then ui_mode = 2
    elseif is_hunt then ui_mode = 1
    end

    out:set_value("jantouki_ui_mode", ui_mode)
    out:set_value("jantouki_letter_vis", ui_mode + 1)

    local flash_hunt = is_hunt and blink_state or 0
    local flash_notebook = is_notebook and blink_state or 0
    local flash_ws = is_ws and blink_state or 0
    local flash_lc = is_lc and blink_state or 0
    local flash_start = is_char and blink_state or 0

    for _, key in ipairs({ "a", "b", "c", "d" }) do
        out:set_value("lamp_hint_hunt_" .. key, flash_hunt)
    end
    for _, key in ipairs({ "a", "b", "c", "d" }) do
        out:set_value("lamp_hint_character_" .. key, flash_start)
        out:set_value("jantouki_char_" .. key, is_char and 1 or 0)
    end
    for _, key in ipairs({ "a", "b", "c" }) do
        out:set_value("lamp_hint_ws_" .. key, flash_ws)
    end
    for _, key in ipairs({ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }) do
        out:set_value("lamp_hint_lc_" .. key, flash_lc)
    end
    for _, key in ipairs({ "a", "b", "c", "d", "e", "f", "g" }) do
        out:set_value("lamp_hint_notebook_" .. key, flash_notebook)
    end
    out:set_value("lamp_start_donden", flash_start)

    if DEBUG_UI_PROBE and blink_state == 1 then
        local parts = { string.format("mode=%d char=%s", ui_mode, is_char and "Y" or "N") }
        for i, p in ipairs(CHAR_PROBE) do
            local r, g, b = pixel_rgb(p[1], p[2], true)
            local hit = match_v(p[1], p[2], p[3], p[4], p[5])
            parts[#parts + 1] = string.format(
                "C%d:%d,%d,%d%s", i, r or -1, g or -1, b or -1, hit and "+" or "-")
        end
        machine:popmessage(table.concat(parts, " "))
    end
end
