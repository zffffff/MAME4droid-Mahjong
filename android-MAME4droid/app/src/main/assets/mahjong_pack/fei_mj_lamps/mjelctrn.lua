return function(machine, screen, blink_state)
    local w, h = screen.width, screen.height
    
    local function is_red(vx, vy)
        local color = screen:pixel(w - vx - 1, h - vy - 1)
        return ((color >> 16) & 0xFF) > 200 and ((color >> 8) & 0xFF) < 50 and (color & 0xFF) < 50
    end
    if is_red(286, 92) then machine.output:set_value("lamp_pon", blink_state) else machine.output:set_value("lamp_pon", 0) end
    if is_red(324, 92) then machine.output:set_value("lamp_chi", blink_state) else machine.output:set_value("lamp_chi", 0) end
    if is_red(286, 104) then machine.output:set_value("lamp_ron", blink_state) else machine.output:set_value("lamp_ron", 0) end
    if is_red(324, 104) then machine.output:set_value("lamp_kan", blink_state) else machine.output:set_value("lamp_kan", 0) end

    local function check_select_screen()
        local c1 = screen:pixel(w - 16 - 1, h - 10 - 1)
        local r1, g1, b1 = (c1 >> 16) & 0xFF, (c1 >> 8) & 0xFF, c1 & 0xFF
        local is_char_select = (r1 > 200 and r1 < 255 and g1 > 80 and g1 < 130 and b1 > 80 and b1 < 130)

        local c2 = screen:pixel(w - 0 - 1, h - 0 - 1)
        local r2, g2, b2 = (c2 >> 16) & 0xFF, (c2 >> 8) & 0xFF, c2 & 0xFF
        local is_bonus_game = (r2 > 160 and r2 < 200 and g2 > 170 and g2 < 220 and b2 > 150 and b2 < 190)

        return is_char_select or is_bonus_game
    end

    local is_sel = check_select_screen()
    machine.output:set_value("lamp_hint_select_a", is_sel and blink_state or 0)
    machine.output:set_value("lamp_hint_select_b", is_sel and blink_state or 0)
    machine.output:set_value("lamp_hint_select_c", is_sel and blink_state or 0)
    machine.output:set_value("lamp_hint_select_d", is_sel and blink_state or 0)
end