-- pixel_probe.lua
-- 飞剧场专属：雷达扫描探针 (自动寻找指定颜色的最近坐标)

return function(machine, screen)
    -- ==========================================================
    -- 🎯 雷达设置：你要找的目标颜色和扫描范围
    -- ==========================================================
    local target_r = 189
    local target_g = 57
    local target_b = 0

    -- 限制扫描范围，防止每帧扫全屏导致模拟器死机
    -- 因为你之前的预估坐标是 (110, 23) 和 (350, 25)
    -- 所以宽扫到 500，高扫到 100 绰绰有余了
    local max_scan_x = 500  
    local max_scan_y = 100  

    local nearest_x = -1
    local nearest_y = -1
    local min_distance = 9999999 -- 初始距离设为无限大

    -- 遍历指定区域的所有像素
    for y = 0, max_scan_y do
        for x = 0, max_scan_x do
            local c = screen:pixel(x, y)
            if c then
                local r = (c >> 16) & 0xFF
                local g = (c >> 8) & 0xFF
                local b = c & 0xFF

                -- 如果发现目标颜色
                if r == target_r and g == target_g and b == target_b then
                    -- 计算到 (0,0) 的距离平方
                    local dist = (x * x) + (y * y)
                    
                    -- 如果距离比之前记录的更近，则更新坐标
                    if dist < min_distance then
                        min_distance = dist
                        nearest_x = x
                        nearest_y = y
                    end
                end
            end
        end
    end

    -- 拼装 OSD 显示内容
    local msg = ""
    if nearest_x ~= -1 then
        msg = string.format(
            "=== 📡 色彩雷达 扫描成功 (按 P 暂停) ===\n\n" ..
            "目标颜色 RGB(%d, %d, %d)\n\n" ..
            "✅ 找到离 (0,0) 最近的真实坐标：\n" ..
            "   [ X: %d,  Y: %d ]",
            target_r, target_g, target_b,
            nearest_x, nearest_y
        )
    else
        msg = string.format(
            "=== 📡 色彩雷达 扫描中... ===\n\n" ..
            "目标颜色 RGB(%d, %d, %d)\n\n" ..
            "❌ 在 (0~%d, 0~%d) 范围内\n未发现该颜色！\n\n" ..
            "可能原因：\n1. 颜色在当前帧没亮起\n2. 偏移超过了扫描范围",
            target_r, target_g, target_b, max_scan_x, max_scan_y
        )
    end

    machine:popmessage(msg)
end