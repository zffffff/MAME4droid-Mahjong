return function(machine, screen, blink_state)
    local out = fei_output(machine)
    local target_y = 77
    local function is_yellow_active(x, y)
        local color = screen:pixel(x, y)
        local r = (color >> 16) & 0xFF
        local g = (color >> 8) & 0xFF
        local b = color & 0xFF
        return r > 200 and g > 140 and g < 180 and b < 20
    end
    if is_yellow_active(190, target_y) then out:set_value("lamp_chi", blink_state) else out:set_value("lamp_chi", 0) end
    if is_yellow_active(220, target_y) then out:set_value("lamp_pon", blink_state) else out:set_value("lamp_pon", 0) end
    if is_yellow_active(250, target_y) then out:set_value("lamp_kan", blink_state) else out:set_value("lamp_kan", 0) end
    if is_yellow_active(280, target_y) then out:set_value("lamp_reach", blink_state) else out:set_value("lamp_reach", 0) end
    if is_yellow_active(310, target_y) then out:set_value("lamp_ron", blink_state) else out:set_value("lamp_ron", 0) end
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end
    if check_exact(30, 20, 8, 74, 198) and check_exact(33, 20, 222, 148, 16) then
        out:set_value("lamp_hint_haidi", blink_state)
    else
        out:set_value("lamp_hint_haidi", 0)
    end
    if check_exact(200, 15, 255, 165, 0) and check_exact(200, 17, 173, 74, 0) then
        out:set_value("lamp_hint_duihua", blink_state)
    else
        out:set_value("lamp_hint_duihua", 0)
    end
    local c_bibei = screen:pixel(58, 5)
    if ((c_bibei >> 16) & 0xFF) > 170 and ((c_bibei >> 8) & 0xFF) > 80 then
        out:set_value("lamp_hint_bibei", blink_state)
    else
        out:set_value("lamp_hint_bibei", 0)
    end
end
