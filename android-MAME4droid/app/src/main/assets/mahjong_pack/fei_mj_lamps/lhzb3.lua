return function(machine, screen, blink_state)
    local ch = screen:pixel(40, 30)
    if ((ch >> 16) & 0xFF) > 220 and ((ch >> 8) & 0xFF) > 200 and (ch & 0xFF) < 40 then machine.output:set_value("lamp_hint_haidi", blink_state) else machine.output:set_value("lamp_hint_haidi", 0) end
    local cd = screen:pixel(200, 30)
    if ((cd >> 16) & 0xFF) > 140 and ((cd >> 8) & 0xFF) > 180 and (cd & 0xFF) < 80 then machine.output:set_value("lamp_hint_duihua", blink_state) else machine.output:set_value("lamp_hint_duihua", 0) end
    local cb = screen:pixel(171, 228)
    if ((cb >> 16) & 0xFF) > 220 and ((cb >> 8) & 0xFF) < 40 and (cb & 0xFF) > 220 then machine.output:set_value("lamp_hint_bibei", blink_state) else machine.output:set_value("lamp_hint_bibei", 0) end
end