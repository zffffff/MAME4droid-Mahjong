-- fei_mj_lamps/smoke_input.lua
-- L2 冒烟：强制 Controls=Mahjong（若有）、导出 KEY 字段、合成按几下、写日志后退出。
-- 由 tools/mame_smoke.bat / dump_rom_inputs.py 启动；-seconds_to_run 兜底。

local function open_log()
    local rom = "unknown"
    pcall(function()
        rom = manager.machine.system.name or rom
    end)
    local path = string.format("smoke_logs/%s.log", rom)
    local f = io.open(path, "w")
    if not f then
        path = string.format("smoke_%s.log", rom)
        f = io.open(path, "w")
    end
    return f, path, rom
end

local logf, log_path, rom_name = open_log()

local function log(fmt, ...)
    local line = string.format(fmt, ...)
    if logf then
        logf:write(line)
        logf:write("\n")
        logf:flush()
    end
    print("[smoke] " .. line)
end

if not logf then
    print("[smoke] FATAL: cannot open log file")
else
    log("=== smoke start rom=%s path=%s ===", rom_name, log_path)
end

local machine = manager.machine
local ioport = machine.ioport
local pressed = {}

local function find_controls_field()
    if not ioport or not ioport.ports then
        return nil, "no ioport"
    end
    for tag, port in pairs(ioport.ports) do
        if port.fields and port.fields["Controls"] then
            return port.fields["Controls"], tag
        end
    end
    for tag, port in pairs(ioport.ports) do
        if port.fields then
            for name, field in pairs(port.fields) do
                if field and field.type_class == "dipswitch" and type(name) == "string"
                    and name:lower():find("control", 1, true) then
                    return field, tag .. "/" .. name
                end
            end
        end
    end
    return nil, "Controls dip not found"
end

local function force_mahjong_controls()
    local field, where = find_controls_field()
    if not field then
        log("Controls: SKIP (%s)", tostring(where))
        return false
    end
    local before = field.user_value
    if before ~= 0 then
        field.user_value = 0
    end
    log("Controls: where=%s before=%s after=%s (target Mahjong=0)", tostring(where), tostring(before), tostring(field.user_value))
    return true
end

local function dump_key_ports()
    log("--- ioport fields (KEY*/IN1/IN2/…) ---")
    if not ioport or not ioport.ports then
        log("(no ports)")
        return
    end
    local tags = {}
    for tag, _ in pairs(ioport.ports) do
        local t = tag:gsub("^:", "")
        if t:match("^KEY") or t == "IN1" or t == "IN2" or t == "PLAYER" or t == "TEST" or t == "COINS" then
            tags[#tags + 1] = tag
        end
    end
    table.sort(tags)
    for _, tag in ipairs(tags) do
        local port = ioport.ports[tag]
        log("[%s] live=0x%X", tag, port:read() or 0)
        if port.fields then
            local names = {}
            for name, _ in pairs(port.fields) do
                names[#names + 1] = name
            end
            table.sort(names)
            for _, name in ipairs(names) do
                local f = port.fields[name]
                log("  %-28s mask=0x%X def=0x%X class=%s", name, f.mask or 0, f.defvalue or 0, tostring(f.type_class or "?"))
            end
        end
    end
end

local function find_field_exact_or_substr(substr)
    if not ioport or not ioport.ports then
        return nil
    end
    local needle = substr:lower()
    local fallback, fallback_name = nil, nil
    local tags = {}
    for tag, _ in pairs(ioport.ports) do
        tags[#tags + 1] = tag
    end
    table.sort(tags, function(a, b)
        local ka = a:find("KEY") and 0 or 1
        local kb = b:find("KEY") and 0 or 1
        if ka ~= kb then
            return ka < kb
        end
        return a < b
    end)
    for _, tag in ipairs(tags) do
        local port = ioport.ports[tag]
        if port.fields then
            for name, field in pairs(port.fields) do
                if type(name) == "string" and field.type_class ~= "dipswitch" then
                    local lower = name:lower()
                    if lower == needle or lower:find(needle, 1, true) then
                        if tag:find("KEY") then
                            return field, name .. " @" .. tag
                        end
                        if not fallback then
                            fallback, fallback_name = field, name .. " @" .. tag
                        end
                    end
                end
            end
        end
    end
    return fallback, fallback_name
end

local function pulse_on(field, name)
    if not field then
        log("press SKIP: %s", tostring(name))
        return
    end
    local ok, err = pcall(function() field:set_value(1) end)
    log("press ON: %s ok=%s err=%s", name, tostring(ok), tostring(err))
end

local function pulse_off(field, name)
    if not field then
        return
    end
    pcall(function()
        if field.clear_value then
            field:clear_value()
        else
            field:set_value(0)
        end
    end)
    log("press OFF: %s", name)
end

local function log_ports(prefix)
    for _, tag in ipairs({ ":KEY0", ":KEY1", ":KEY4", ":IN1" }) do
        local port = ioport.ports[tag]
        if port then
            log("%s %s read=0x%X", prefix, tag, port:read() or 0)
        end
    end
end

local frame = 0
emu.register_frame_done(function()
    if not manager or not manager.machine then
        return
    end
    frame = frame + 1

    if frame == 1 then
        pcall(function()
            log("description: %s", machine.system.description or "?")
        end)
        force_mahjong_controls()
        dump_key_ports()
        log_ports("baseline")
    end

    -- 按住期间每帧重设，避免被冲掉
    if frame >= 90 and frame < 120 then
        for _, item in ipairs(pressed) do
            pcall(function() item[1]:set_value(1) end)
        end
    end

    if frame == 90 then
        local targets = {
            { "Mahjong A", { "麻将 a", "麻将a", "mahjong a" } },
            { "Start", { "开始", "start" } },
            { "Bet", { "押分", "押注", "bet" } },
            { "Key-In", { "开分", "key-in", "key in" } },
        }
        pressed = {}
        local seen = {}
        for _, t in ipairs(targets) do
            local label, needles = t[1], t[2]
            if not seen[label] then
                local f, n = nil, nil
                for _, needle in ipairs(needles) do
                    f, n = find_field_exact_or_substr(needle)
                    if f then
                        break
                    end
                end
                if f then
                    seen[label] = true
                    pressed[#pressed + 1] = { f, n }
                    pulse_on(f, n)
                else
                    log("press MISS: %s", label)
                end
            end
        end
        if #pressed == 0 then
            log("WARN: no fields pressed — check UI language names")
        end
    end

    if frame == 100 then
        log_ports("held")
    end

    if frame == 120 then
        for _, item in ipairs(pressed) do
            pulse_off(item[1], item[2])
        end
    end

    if frame == 130 then
        log_ports("released")
    end

    if frame == 150 then
        log("=== smoke done OK ===")
        if logf then
            logf:close()
            logf = nil
        end
        machine:exit()
    end
end)
