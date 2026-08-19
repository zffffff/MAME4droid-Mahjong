-- fei_mj_lamps/force_controls.lua
-- 将指定 DIP「Controls」强制为 Mahjong（通常 user_value=0）。
-- 用法：
--   local force = loadfile("fei_mj_lamps/force_controls.lua")()
--   force(machine, { port = ":DSW2", mahjong_value = 0 })

return function(machine, opts)
    opts = opts or {}
    local port_tag = opts.port or ":DSW1"
    local mahjong_value = opts.mahjong_value or 0
    local mask = opts.mask -- optional: match dip field.mask

    pcall(function()
        local ports = machine.ioport and machine.ioport.ports
        if not ports then
            return
        end
        local port = ports[port_tag]
        if not port or not port.fields then
            return
        end
        local field = port.fields["Controls"]
        if not field then
            for name, f in pairs(port.fields) do
                if f and f.type_class == "dipswitch" then
                    if mask and f.mask == mask then
                        field = f
                        break
                    end
                    if type(name) == "string" and name:lower():find("control", 1, true) then
                        field = f
                        break
                    end
                end
            end
        end
        if field and field.user_value ~= mahjong_value then
            field.user_value = mahjong_value
        end
    end)
end
