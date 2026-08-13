return function(machine, screen, blink_state)
    local out = fei_output(machine)
    local function check_color(x, y, r_min, r_max, g_min, g_max, b_min, b_max)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r >= r_min and r <= r_max and g >= g_min and g <= g_max and b >= b_min and b <= b_max
    end

    if check_color(12, 55, 20, 60, 230, 255, 0, 30) and check_color(500, 55, 20, 60, 230, 255, 0, 30) then
        out:set_value("lamp_hint_bibei", blink_state)
    else
        out:set_value("lamp_hint_bibei", 0)
    end

    if check_color(25, 45, 130, 180, 0, 30, 90, 140) and check_color(480, 116, 40, 90, 140, 190, 0, 30) then
        out:set_value("lamp_hint_haidi", blink_state)
    else
        out:set_value("lamp_hint_haidi", 0)
    end

    if check_color(50, 15, 180, 230, 120, 160, 0, 30) and check_color(480, 116, 40, 90, 140, 190, 0, 30) then
        out:set_value("lamp_hint_duihua", blink_state)
    else
        out:set_value("lamp_hint_duihua", 0)
    end
end