-- fei_mj_lamps/output_proxy.lua
-- MAME 0.289+：machine.output / device:output():set 无法创建自定义灯号。
-- layout 用 id=；此处对 current_view.items[id] 写状态。
--
-- 注意：MAME 0.289 上 item.input_tag 对 XML 里的 inputtag 常为 nil，不能靠它分支。
-- 原 <animate name> 驱动 bounds 的灯号（ui_mode / letter_vis / char_*）必须挂
-- animation_state_callback；仅 set_state 会被 input 绑定吞掉 → 选择面点不到。

local caches = setmetatable({}, { __mode = "k" })

local function current_view(machine)
    local render = machine.render
    if not render or not render.targets then return nil end
    local t = render.targets[1]
    if not t then return nil end
    return t.current_view
end

-- 原 animate 绑定：多档 bounds/显隐（选择面 hitbox）
local function needs_animation_bind(name)
    return string.find(name, "_ui_mode", 1, true)
        or string.find(name, "_letter_vis", 1, true)
        or string.find(name, "_char_", 1, true)
end

local function fei_output(machine)
    local cache = caches[machine]
    if not cache then
        cache = {
            values = {},
            wired = {},
            last_view = nil,
        }
        caches[machine] = cache
    end

    local function iter_ids(view, name)
        local ids = {}
        if view.items[name] then
            ids[#ids + 1] = name
        end
        local i = 1
        while true do
            local id = name .. "__" .. i
            if not view.items[id] then break end
            ids[#ids + 1] = id
            i = i + 1
        end
        return ids
    end

    return {
        set_value = function(_, name, value)
            cache.values[name] = value
            local view = current_view(machine)
            if not view or not view.items then return end

            if view ~= cache.last_view then
                cache.wired = {}
                cache.last_view = view
            end

            for _, id in ipairs(iter_ids(view, name)) do
                local item = view.items[id]
                if item then
                    if needs_animation_bind(name) then
                        if not cache.wired[id] then
                            cache.wired[id] = true
                            local key = name
                            item:set_animation_state_callback(function()
                                return cache.values[key] or 0
                            end)
                        end
                        -- letter_vis 等无 input 绑定时 set_state 仍有效，一并写上
                        pcall(function() item:set_state(value) end)
                    else
                        -- lamp_* 等：无绑定时 set_state；有 inputtag 的加倍键等靠 element callback
                        if string.sub(name, 1, 5) == "lamp_" and not cache.wired[id] then
                            cache.wired[id] = true
                            local key = name
                            item:set_element_state_callback(function()
                                return cache.values[key] or 0
                            end)
                        end
                        pcall(function() item:set_state(value) end)
                    end
                end
            end
        end,
    }
end

return fei_output
