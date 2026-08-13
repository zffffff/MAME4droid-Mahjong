-- fei_mj_lamps/mcnpshnt.lua
-- 校园狩猎麻将 (mcnpshnt) 专属闪灯与横版 UI 模式切换
-- mcnpshnt_ui_mode: 0=打牌 1=狩猎A-D 2=秘技手帐A-G 3=选人A-D 4=配牌选择A-C 5=Last Chance A-J（无 Lua 时默认 0）
-- mcnpshnt_char_a~d: 选人时未击败对手=1（触摸可用+闪灯），已击败=0
-- mcnpshnt_letter_vis: 横版松开态 0=touch_up（无 Lua） 1~6=touch_up_l+ui_mode（有 Lua）
--
-- 选人探针：screen:pixel 直读 VRAM 坐标；画面上移 16px，有效内容约从 vy=16 起
-- P1 在 vy=244（超出 screen.height=240），须不钳位直读
local DEBUG_UI_PROBE = false

return function(machine, screen, blink_state)
    local out = fei_output(machine)
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

    local CHAR_P0 = { 0, 16 }           -- 66,148,255
    local CHAR_ANCHOR = { 52, 120 }     -- 198,74,0
    local CHAR_P1 = { 326, 244 }        -- 0,99,0 CREDIT 绿（仅选人屏）

    -- 配牌选择：x=140 竖条三色（截图 Y +16 → VRAM；第四色因角色而异，不用）
    local WS_PROBE = {
        { 140, 16, 115, 115, 115 },
        { 140, 22, 255, 255, 255 },
        { 140, 26, 148, 0, 0 },
    }

    -- Last Chance：截图 (95,90)(97,90)(99,90) → VRAM y+16
    local LC_PROBE = {
        { 95, 106, 0, 66, 156 },
        { 97, 106, 173, 165, 156 },
        { 99, 106, 148, 0, 0 },
    }

    -- 已击败对手标记色 148,74,34（VRAM 直读；用户坐标 Y +16）
    local CHAR_DISABLED = {
        a = { 230, 36 },
        b = { 470, 56 },
        c = { 240, 216 },
        d = { 450, 176 },
    }

    local function rgb(c)
        if not c then return nil, nil, nil end
        return (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
    end

    local function pixel_rgb(vx, vy, do_clamp)
        if do_clamp then
            vx, vy = clamp_v(vx, vy)
        end
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

    local function is_red(x, y)
        local r, g, b = rgb(screen:pixel(x, y))
        if not r then return false end
        return r > 200 and g < 50 and b < 50
    end

    if is_red(226, 388) then out:set_value("lamp_pon", blink_state) else out:set_value("lamp_pon", 0) end
    if is_red(188, 388) then out:set_value("lamp_chi", blink_state) else out:set_value("lamp_chi", 0) end
    if is_red(226, 376) then out:set_value("lamp_ron", blink_state) else out:set_value("lamp_ron", 0) end
    if is_red(188, 376) then out:set_value("lamp_kan", blink_state) else out:set_value("lamp_kan", 0) end

    local function is_char_select_screen()
        return match_v(CHAR_P0[1], CHAR_P0[2], 66, 148, 255)
            and match_v(CHAR_ANCHOR[1], CHAR_ANCHOR[2], 198, 74, 0)
    end

    local function is_character_select()
        return is_char_select_screen()
            and match_v(CHAR_P1[1], CHAR_P1[2], 0, 99, 0, false)
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

    local function is_char_enabled(key)
        local p = CHAR_DISABLED[key]
        return not match_v(p[1], p[2], 148, 74, 34)
    end

    local is_char = is_character_select()
    local is_lc = not is_char and is_last_chance()
    local is_ws = not is_char and not is_lc and is_tile_select()
    local is_hunt = not is_char and not is_lc and not is_ws and is_hunt_ad()
    local is_notebook = not is_char and not is_lc and not is_ws and is_notebook_ag()

    local ui_mode = 0
    if is_char then
        ui_mode = 3
    elseif is_lc then
        ui_mode = 5
    elseif is_ws then
        ui_mode = 4
    elseif is_notebook then
        ui_mode = 2
    elseif is_hunt then
        ui_mode = 1
    end
    out:set_value("mcnpshnt_ui_mode", ui_mode)
    out:set_value("mcnpshnt_letter_vis", ui_mode + 1)

    local flash_hunt = is_hunt and blink_state or 0
    local flash_notebook = is_notebook and blink_state or 0
    local flash_ws = is_ws and blink_state or 0
    local flash_lc = is_lc and blink_state or 0
    local flash_start = is_char and blink_state or 0

    for _, key in ipairs({ "a", "b", "c", "d" }) do
        out:set_value("lamp_hint_hunt_" .. key, flash_hunt)
        local enabled = is_char and is_char_enabled(key)
        local flash_char = enabled and blink_state or 0
        out:set_value("lamp_hint_character_" .. key, flash_char)
        out:set_value("mcnpshnt_char_" .. key, enabled and 1 or 0)
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
        local function line(vx, vy, clamp)
            local r, g, b = pixel_rgb(vx, vy, clamp)
            return string.format("v(%d,%d) %d,%d,%d", vx, vy, r or -1, g or -1, b or -1)
        end
        machine:popmessage(string.format(
            "mode=%d lc=%d\n%s\n%s\n%s",
            ui_mode, is_lc and 1 or 0,
            line(95, 106, true),
            line(97, 106, true),
            line(99, 106, true)))
    end
end
