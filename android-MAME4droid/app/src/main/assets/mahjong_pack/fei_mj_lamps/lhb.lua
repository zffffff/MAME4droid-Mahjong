return function(machine, screen, blink_state)
    local out = fei_output(machine)
    local rom_name = machine.system.name

    -- 引入精确颜色匹配工具函数 (备用：如果旧逻辑误报，可随时用探针测出确切数值后改用此函数)
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end

    -- ==========================================
    -- 【龙虎榜 1 (lhb) 及其全系克隆版 (大笨象等)】
    -- ==========================================
    if (string.sub(rom_name, 1, 3) == "lhb" and not string.match(rom_name, "^lhb[23]")) or rom_name == "dbc" or rom_name == "ryukobou" then
        
        -- 1. 选人侦测 (坐标 2, 2)
        local c_select = screen:pixel(2, 2)
        local r_s = (c_select >> 16) & 0xFF
        local g_s = (c_select >> 8) & 0xFF
        local b_s = c_select & 0xFF
        
        if r_s > 180 and g_s > 130 and g_s < 180 and b_s > 20 and b_s < 80 then
            out:set_value("lamp_hint_select", blink_state)
        else
            out:set_value("lamp_hint_select", 0)
        end

        -- 2. 海底侦测 (坐标 60, 37)
        local c_haidi = screen:pixel(60, 37)
        local r1 = (c_haidi >> 16) & 0xFF
        local g1 = (c_haidi >> 8) & 0xFF
        local b1 = c_haidi & 0xFF
        
        if r1 > 130 and g1 < 20 and b1 < 20 then
            out:set_value("lamp_hint_haidi", blink_state)
        else
            out:set_value("lamp_hint_haidi", 0)
        end

    -- ==========================================
    -- 【龙虎榜 2/3 (lhb2/lhb3) 及其全系克隆版】
    -- ==========================================
    elseif string.sub(rom_name, 1, 4) == "lhb2" or rom_name == "lhb3" or rom_name == "nkishusp" then
        
        -- 海底侦测 (基于特定橙色 坐标 5, 40)
        local c_haidi2 = screen:pixel(5, 40)
        local r2 = (c_haidi2 >> 16) & 0xFF
        local g2 = (c_haidi2 >> 8) & 0xFF
        local b2 = c_haidi2 & 0xFF
        
        -- 色彩容错，锁定偏浅橙红的色域
        if r2 > 200 and g2 > 130 and g2 < 180 and b2 > 90 and b2 < 140 then
            out:set_value("lamp_hint_haidi", blink_state)
        else
            out:set_value("lamp_hint_haidi", 0)
        end
    end
end