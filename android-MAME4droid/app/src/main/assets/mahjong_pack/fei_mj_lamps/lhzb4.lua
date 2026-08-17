-- lhzb4 / lhzb4dhb：默认 Controls=Joystick 时麻将键矩阵整组失效。
-- 手机按键包启动后强制切到 Mahjong（DSW1 bit0 = 0）。
local controls_forced = false

local function ensure_mahjong_controls(machine)
    if controls_forced then
        return
    end
    controls_forced = true
    pcall(function()
        local port = machine.ioport and machine.ioport.ports and machine.ioport.ports[":DSW1"]
        if not port or not port.fields then
            return
        end
        local field = port.fields["Controls"]
        if not field then
            for _, f in pairs(port.fields) do
                if f and f.type_class == "dipswitch" and f.mask == 1 then
                    field = f
                    break
                end
            end
        end
        -- Mahjong = 0；Joystick = 1（defvalue）
        if field and field.user_value ~= 0 then
            field.user_value = 0
        end
    end)
end

return function(machine, screen, blink_state)
    ensure_mahjong_controls(machine)

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
