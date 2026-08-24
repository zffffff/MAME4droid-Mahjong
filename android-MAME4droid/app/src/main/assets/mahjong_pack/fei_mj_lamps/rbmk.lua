-- rbmk（实战麻将王）：GMS 平台。默认 Controls=Joystick 时麻将矩阵失效。
-- 启动后强制 DSW2 Controls → Mahjong（user_value=0）。闪灯探针可后续再校。

local force_controls = loadfile("fei_mj_lamps/force_controls.lua")
local force = force_controls and force_controls() or nil
local controls_forced = false
local wall_hunt = loadfile("fei_mj_lamps/rbmk_wall.lua")
local hunt = wall_hunt and wall_hunt() or nil

return function(machine, screen, blink_state)
    if force and not controls_forced then
        controls_forced = true
        force(machine, { port = ":DSW2", mahjong_value = 0, mask = 0x80 })
    end

    if hunt then
        hunt(machine)
    end

    local out = fei_output(machine)
    -- 占位：暂无像素闪灯；保留接口避免 master 报错
    out:set_value("lamp_hint_bibei", 0)
    out:set_value("lamp_hint_haidi", 0)
    out:set_value("lamp_hint_duihua", 0)
end
