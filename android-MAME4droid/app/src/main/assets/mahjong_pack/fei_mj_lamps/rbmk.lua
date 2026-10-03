-- rbmk（实战麻将王）：灯控-only（公开仓不含增强 wall）。
local force_controls = loadfile("fei_mj_lamps/force_controls.lua")
local force = force_controls and force_controls() or nil
local controls_forced = false

return function(machine, screen, blink_state)
    if force and not controls_forced then
        controls_forced = true
        force(machine, { port = ":DSW2", mahjong_value = 0, mask = 0x80 })
    end
    local out = fei_output(machine)
    out:set_value("lamp_hint_bibei", 0)
    out:set_value("lamp_hint_haidi", 0)
    out:set_value("lamp_hint_duihua", 0)
end
