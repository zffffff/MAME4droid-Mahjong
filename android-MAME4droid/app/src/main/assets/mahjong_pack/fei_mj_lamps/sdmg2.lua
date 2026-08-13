return function(machine, screen, blink_state)
    local out = fei_output(machine)
    -- 引入精确颜色匹配工具函数 (备用：如果旧逻辑不亮，可随时用探针测出确切数值后改用此函数)
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end

    -- 1. 海底侦测：瞄准 "CHANCE" 中 H 字母的纵梁 (267, 35)
    -- 旧逻辑：目标颜色约为 de9410 (R:222, G:148, B:16)
    local ch = screen:pixel(267, 35)
    local r1 = (ch >> 16) & 0xFF
    local g1 = (ch >> 8) & 0xFF
    local b1 = ch & 0xFF
    
    if r1 > 200 and g1 > 130 and g1 < 170 and b1 < 40 then
        out:set_value("lamp_hint_haidi", blink_state)
    else
        out:set_value("lamp_hint_haidi", 0)
    end

    -- 2. 比倍侦测：联动 双倍、大、小、得分(take)
    local cb = screen:pixel(25, 17)
    local r2 = (cb >> 16) & 0xFF
    local g2 = (cb >> 8) & 0xFF
    local b2 = cb & 0xFF
    
    if r2 > 200 and g2 > 100 and b2 < 50 then
        out:set_value("lamp_hint_bibei", blink_state)
        out:set_value("lamp_double", blink_state)
        out:set_value("lamp_big", blink_state)
        out:set_value("lamp_small", blink_state)
        out:set_value("lamp_take", blink_state)
    else
        out:set_value("lamp_hint_bibei", 0)
        out:set_value("lamp_double", 0)
        out:set_value("lamp_big", 0)
        out:set_value("lamp_small", 0)
        out:set_value("lamp_take", 0)
    end
end