return function(machine, screen, blink_state)
    local out = fei_output(machine)
    -- 引入精确颜色匹配工具函数，杜绝任何单点容差带来的误报
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end

    -- 1. 海底环节：使用最新升级的双点绝对精准指纹锁
    if check_exact(60, 20, 66, 173, 0) and check_exact(60, 23, 41, 66, 66) then 
        out:set_value("lamp_hint_haidi", blink_state) 
    else 
        out:set_value("lamp_hint_haidi", 0) 
    end

    -- 2. 对花环节：使用精准 RGB 颜色指纹锁，彻底解决红色误报 Bug
    if check_exact(60, 40, 247, 255, 0) then
        out:set_value("lamp_hint_duihua", blink_state)
    else
        out:set_value("lamp_hint_duihua", 0)
    end

    -- 3. 比倍环节：恢复早期代码逻辑，包含 双倍、大、小 联动
    -- （注：如果以后发现比倍环节也有误报，咱们可以用同样的方法把它也改成精确锁）
    local c3 = screen:pixel(5, 220)
    if ((c3 >> 16) & 0xFF) > 210 then
        out:set_value("lamp_hint_bibei", blink_state)
        out:set_value("lamp_double", blink_state)
        out:set_value("lamp_big", blink_state)
        out:set_value("lamp_small", blink_state)
    else
        out:set_value("lamp_hint_bibei", 0)
        out:set_value("lamp_double", 0)
        out:set_value("lamp_big", 0)
        out:set_value("lamp_small", 0)
    end
end