-- fei_mj_lamps/tenkai.lua
-- 天开眼 (tenkai) 专属像素雷达与灯光控制逻辑

return function(machine, screen, blink_state)
    local out = fei_output(machine)

    local function check_color(x, y, target_r, target_g, target_b)
        local color = screen:pixel(x, y)
        if not color then return false end
        local r = (color >> 16) & 0xFF
        local g = (color >> 8) & 0xFF
        local b = color & 0xFF
        return r == target_r and g == target_g and b == target_b
    end
    
    local function check_color_fuzzy(x, y, r, g, b)
        return check_color(x, y, r, g, b) or 
               check_color(x+1, y, r, g, b) or 
               check_color(x, y+1, r, g, b)
    end

    local flash_a, flash_b, flash_c, flash_d, flash_e = 0, 0, 0, 0, 0
    local flash_f, flash_g, flash_h, flash_i, flash_j = 0, 0, 0, 0, 0
    local flash_ron = 0

    -- [环节 1：选择电脑对手]
    if check_color(0, 0, 247, 132, 16) and check_color(113, 27, 189, 57, 0) then
        if check_color(353, 29, 189, 57, 0) or check_color(353, 27, 189, 57, 0) then
            flash_a = blink_state
            flash_b = blink_state
        end
    end

    -- [环节 2：胡牌 (修复配牌撞车版)]
    if check_color_fuzzy(391, 106, 0, 222, 255) and check_color_fuzzy(391, 116, 231, 189, 66) then
        if check_color_fuzzy(391, 155, 189, 107, 33) or check_color_fuzzy(391, 155, 247, 115, 123) then
            flash_ron = blink_state
        end
    end

    -- [环节 3：海底捞月选牌]
    if check_color_fuzzy(23, 107, 0, 222, 255) and check_color_fuzzy(83, 81, 247, 231, 99) then
        flash_a, flash_b, flash_c, flash_d, flash_e = 1, 1, 1, 1, 1
        flash_f, flash_g, flash_h, flash_i, flash_j = 1, 1, 1, 1, 1
    end

    -- [环节 4：Bonus 小游戏]
    -- 锚点 1 (0, 0) -> 物理校准 (3, 4)
    -- 锚点 2 (30, 30) -> 物理校准 (33, 34)
    if check_color_fuzzy(3, 4, 165, 82, 82) and check_color_fuzzy(33, 34, 222, 165, 41) then
        flash_a = blink_state
        flash_b = blink_state
        flash_c = blink_state
        flash_d = blink_state
        flash_e = blink_state
    end

    out:set_value("lamp_hint_select_a", flash_a)
    out:set_value("lamp_hint_select_b", flash_b)
    out:set_value("lamp_hint_select_c", flash_c)
    out:set_value("lamp_hint_select_d", flash_d)
    out:set_value("lamp_hint_select_e", flash_e)
    out:set_value("lamp_hint_select_f", flash_f)
    out:set_value("lamp_hint_select_g", flash_g)
    out:set_value("lamp_hint_select_h", flash_h)
    out:set_value("lamp_hint_select_i", flash_i)
    out:set_value("lamp_hint_select_j", flash_j)
    
    out:set_value("lamp_ron", flash_ron)
end