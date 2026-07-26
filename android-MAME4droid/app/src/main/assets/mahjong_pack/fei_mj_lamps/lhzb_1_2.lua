return function(machine, screen, blink_state)
    local target_y = 77
    
    -- 基础判定函数：保持一定的颜色容差用于处理那些位置相对固定的操作键
    local function is_yellow_active(x, y)
        local color = screen:pixel(x, y)
        local r = (color >> 16) & 0xFF
        local g = (color >> 8) & 0xFF
        local b = color & 0xFF
        return r > 200 and g > 140 and g < 180 and b < 20
    end
    
    -- 1. 基础操作按键侦测 (吃、碰、杠、听、胡)
    if is_yellow_active(190, target_y) then machine.output:set_value("lamp_chi", blink_state) else machine.output:set_value("lamp_chi", 0) end
    if is_yellow_active(220, target_y) then machine.output:set_value("lamp_pon", blink_state) else machine.output:set_value("lamp_pon", 0) end
    if is_yellow_active(250, target_y) then machine.output:set_value("lamp_kan", blink_state) else machine.output:set_value("lamp_kan", 0) end
    if is_yellow_active(280, target_y) then machine.output:set_value("lamp_reach", blink_state) else machine.output:set_value("lamp_reach", 0) end
    if is_yellow_active(310, target_y) then machine.output:set_value("lamp_ron", blink_state) else machine.output:set_value("lamp_ron", 0) end

    -- 工具函数：执行 100% 确切颜色匹配，用于杜绝环节干扰
    local function check_exact(x, y, r_target, g_target, b_target)
        local c = screen:pixel(x, y)
        if not c then return false end
        local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
        return r == r_target and g == g_target and b == b_target
    end

    -- 2. 海底环节：双点指纹验证 (已于第 52 步优化)
    if check_exact(30, 20, 8, 74, 198) and check_exact(33, 20, 222, 148, 16) then 
        machine.output:set_value("lamp_hint_haidi", blink_state) 
    else 
        machine.output:set_value("lamp_hint_haidi", 0) 
    end

    -- 3. 对花环节：双点指纹验证 (根据最新探针数据优化)
    -- 探针1: (200, 15) 纯橙色; 探针2: (200, 17) 深褐橙色
    if check_exact(200, 15, 255, 165, 0) and check_exact(200, 17, 173, 74, 0) then
        machine.output:set_value("lamp_hint_duihua", blink_state)
    else
        machine.output:set_value("lamp_hint_duihua", 0)
    end
    
    -- 4. 比倍环节：暂时保持单点，如后续有干扰可继续使用探针测绘
    local c_bibei = screen:pixel(58, 5)
    if ((c_bibei >> 16) & 0xFF) > 170 and ((c_bibei >> 8) & 0xFF) > 80 then 
        machine.output:set_value("lamp_hint_bibei", blink_state) 
    else 
        machine.output:set_value("lamp_hint_bibei", 0) 
    end
end