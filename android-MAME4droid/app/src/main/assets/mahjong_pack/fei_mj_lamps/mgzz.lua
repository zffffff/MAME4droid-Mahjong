-- fei_mj_lamps/mgzz.lua
-- 满贯至尊 (mgzz) 专属闪灯逻辑，从 sdmg2.lua fork，后续在此独立调校像素坐标

return function(machine, screen, blink_state)
    local out = fei_output(machine)
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end

    -- 1. 海底侦测：瞄准 "CHANCE" 中 H 字母的纵梁 (267, 35)
    local ch = screen:pixel(267, 35)
    local r1 = (ch >> 16) & 0xFF
    local g1 = (ch >> 8) & 0xFF
    local b1 = ch & 0xFF

    if r1 > 200 and g1 > 130 and g1 < 170 and b1 < 40 then
        out:set_value("lamp_hint_haidi", blink_state)
    else
        out:set_value("lamp_hint_haidi", 0)
    end

    -- 2. 比倍侦测：hint 图在 M/N 闪烁（大=k、小=m），与 lhzb2/mgcs 相同 lamp_hint_bibei 机制
    local cb = screen:pixel(25, 17)
    local r2 = (cb >> 16) & 0xFF
    local g2 = (cb >> 8) & 0xFF
    local b2 = cb & 0xFF
    local in_bibei = r2 > 200 and g2 > 100 and b2 < 50

    -- letter_mn: 0=显示字母M/N，1=隐藏
    -- bibei_mn:  0=隐藏比倍大/小（默认），1=显示（与 lay 中 state0=屏外 对齐，避免未进比倍时盖住字母键）
    if in_bibei then
        out:set_value("lamp_hint_bibei", blink_state)
        out:set_value("mgzz_letter_mn", 1)
        out:set_value("mgzz_bibei_mn", 1)
    else
        out:set_value("lamp_hint_bibei", 0)
        out:set_value("mgzz_letter_mn", 0)
        out:set_value("mgzz_bibei_mn", 0)
    end
end
