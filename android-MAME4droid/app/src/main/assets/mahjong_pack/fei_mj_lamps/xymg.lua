return function(machine, screen, blink_state)
    local out = fei_output(machine)
    -- 引入精确颜色匹配工具函数 (备用：如果旧逻辑误报，可随时用探针测出确切数值后改用此函数)
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end

    -- ==========================================
    -- 【幸运满贯 (xymg) 及其衍生版】
    -- ==========================================
    
    -- 1. 海底检测 (基于特定浅蓝 坐标 52, 12，RGB 107, 181, 255)
    local c_haidi_xymg = screen:pixel(52, 12)
    local r1 = (c_haidi_xymg >> 16) & 0xFF
    local g1 = (c_haidi_xymg >> 8) & 0xFF
    local b1 = c_haidi_xymg & 0xFF
    
    if r1 > 80 and r1 < 130 and g1 > 150 and g1 < 210 and b1 > 220 then
        out:set_value("lamp_hint_haidi", blink_state)
    else
        out:set_value("lamp_hint_haidi", 0)
    end

    -- 2. 比倍检测 (基于特定鹅黄 坐标 5, 30，RGB 255, 247, 132)
    local c_bibei_xymg = screen:pixel(5, 30)
    local r2 = (c_bibei_xymg >> 16) & 0xFF
    local g2 = (c_bibei_xymg >> 8) & 0xFF
    local b2 = c_bibei_xymg & 0xFF
    
    if r2 > 220 and g2 > 210 and b2 > 100 and b2 < 160 then
        out:set_value("lamp_hint_bibei", blink_state)
    else
        out:set_value("lamp_hint_bibei", 0)
    end

end