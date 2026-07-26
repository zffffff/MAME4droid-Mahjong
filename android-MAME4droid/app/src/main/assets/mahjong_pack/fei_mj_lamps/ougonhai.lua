return function(machine, screen, blink_state)
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end

    local is_n = false

    if check_exact(140, 156, 0, 90, 222) and 
       check_exact(140, 158, 140, 222, 247) and 
       check_exact(140, 159, 198, 247, 247) then 
        is_n = true 
    end

    if not is_n and 
       check_exact(56, 29, 231, 198, 66) and 
       check_exact(56, 30, 0, 90, 222) then
        is_n = true
    end

    if not is_n and 
       check_exact(101, 22, 181, 140, 33) and 
       check_exact(101, 24, 214, 181, 66) then
        is_n = true
    end

    machine.output:set_value("lamp_hint_n", is_n and blink_state or 0)
end