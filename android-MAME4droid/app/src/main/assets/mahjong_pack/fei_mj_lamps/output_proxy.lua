-- fei_mj_lamps/output_proxy.lua
-- MAME 0.289+：machine.output:set_value 已弃用，每帧调用会刷屏警告并严重卡顿。
-- 用 root device 的 output proxy（:set），并按 name 缓存。
--
-- 用法（各游戏插件内）：
--   local out = fei_output(machine)
--   out:set_value("lamp_hint_bibei", blink_state)

local caches = setmetatable({}, { __mode = "k" })

local function fei_output(machine)
    local cache = caches[machine]
    if not cache then
        cache = {}
        caches[machine] = cache
    end
    local root = machine.devices[":"]
    return {
        set_value = function(_, name, value)
            local p = cache[name]
            if not p then
                p = root:output(name)
                cache[name] = p
            end
            p:set(value)
        end
    }
end

return fei_output
