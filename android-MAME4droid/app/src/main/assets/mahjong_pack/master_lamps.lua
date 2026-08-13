-- master_lamps.lua
-- 街机麻将终极外挂大脑 (主控路由 飞剧场专属版)

local frame_counter = 0
local game_module = nil
local module_loaded = false

local last_orient = nil
local orient_check_counter = 0

-- Android writes .device_orientation ("portrait"/"landscape") into the install dir.
-- Switch artwork view to matching Portrait_* / Landscape_* when the phone rotates.
local function apply_device_orientation_view(machine)
    orient_check_counter = orient_check_counter + 1
    if orient_check_counter % 15 ~= 1 then
        return
    end

    local f = io.open(".device_orientation", "r")
    if not f then
        return
    end
    local orient = (f:read("*l") or ""):gsub("%s+", "")
    f:close()
    if orient == "" or orient == last_orient then
        return
    end

    if not machine.render or not machine.render.targets then
        return
    end
    local target = machine.render.targets[1]
    if not target or not target.view_names then
        return
    end

    local want_land = (orient == "landscape")
    local best_i, best_score = nil, -1
    local i = 1
    while true do
        local name = target.view_names[i]
        if not name then
            break
        end
        local score = -1
        local lower = string.lower(name)
        if want_land then
            if name == "Landscape_Touch_Screen" then
                score = 100
            elseif string.find(lower, "landscape_touch", 1, true) then
                score = 80
            elseif string.find(lower, "landscape", 1, true) then
                score = 60
            end
        else
            if name == "Portrait_Touch_Dual_1024x2030" then
                score = 100
            elseif name == "Portrait_Touch_Dual" then
                score = 90
            elseif name == "Portrait_2_Rows" then
                score = 80
            elseif string.find(lower, "portrait", 1, true) then
                score = 60
            end
        end
        if score > best_score then
            best_score = score
            best_i = i
        end
        i = i + 1
    end

    if best_i and best_score >= 0 then
        local ok, err = pcall(function()
            target.view_index = best_i
        end)
        if ok then
            last_orient = orient
        end
    else
        last_orient = orient
    end
end


-- MAME 0.289+：避免 machine.output:set_value 弃用警告刷屏卡顿
local fei_output = loadfile("fei_mj_lamps/output_proxy.lua")
if fei_output then
    _G.fei_output = fei_output()
end

emu.register_frame_done(function()
    if not manager or not manager.machine then return end
    local machine = manager.machine
    local rom_name = machine.system.name
    if not rom_name or rom_name == "___empty" then return end

    apply_device_orientation_view(machine)

    local screen = machine.screens[":screen"]
    local is_jantouki = (rom_name == "jantouki")
    if not screen and not is_jantouki then return end
    if is_jantouki and not machine.screens[":bottom"] then return end

    frame_counter = (frame_counter + 1) % 60
    local blink_state = (frame_counter < 30) and 1 or 0

    if not machine.output then return end

    -- 只在第一帧运行环境准备好时，加载对应的模块，杜绝性能浪费
    if not module_loaded then
        local is_mjelctrn_family = (rom_name == "mjelctrn" or rom_name == "mjembase" or rom_name == "mjelct3bi" or rom_name == "mjelct3bia" or rom_name == "mjelct3bib" or rom_name == "mjelct3" or rom_name == "mjelct3a" or rom_name == "mjelct3b" or rom_name == "mjelctrb" or rom_name == "qyjdzjp")
        local is_lhzb_1_2 = (rom_name == "lhzb" or string.sub(rom_name, 1, 5) == "lhzb2" or string.sub(rom_name, 1, 6) == "lhzb1")
        local is_lhzb3 = (string.find(rom_name, "lhzb3") or rom_name == "lthyp" or string.find(rom_name, "lhdmg"))
        local is_lhzb4 = (string.sub(rom_name, 1, 5) == "lhzb4")
        local is_ougonhai = (string.sub(rom_name, 1, 8) == "ougonhai")
        
        -- 以下为拆分后的杂项游戏家族
        local is_qlgs = (rom_name == "qlgs")
        local is_xymg = (string.sub(rom_name, 1, 4) == "xymg")
        local is_sdmg2 = (string.sub(rom_name, 1, 5) == "sdmg2")
        local is_lhb = ((string.sub(rom_name, 1, 3) == "lhb" and not string.match(rom_name, "^lhb[23]")) or rom_name == "dbc" or rom_name == "ryukobou" or string.sub(rom_name, 1, 4) == "lhb2" or rom_name == "lhb3" or rom_name == "nkishusp")
        
        -- 新增：天开眼 家族
        local is_tenkai = (string.sub(rom_name, 1, 6) == "tenkai")

        -- 满贯财神 1 代 (mgcs/mgcsa/mgcsb)，排除 mgcs2 联机版与 mgcs3
        local is_mgcs = (string.sub(rom_name, 1, 4) == "mgcs" and not string.find(rom_name, "mgcs2") and not string.find(rom_name, "mgcs3"))

        -- 满贯至尊 (mgzz/mgzz100cn)
        local is_mgzz = (string.sub(rom_name, 1, 4) == "mgzz")

        -- 校园狩猎麻将 (mcnpshnt)
        local is_mcnpshnt = (rom_name == "mcnpshnt")

        -- 雀斗记 (jantouki) W 筐体双屏
        local is_jantouki = (rom_name == "jantouki")

        if is_mjelctrn_family then
            game_module = loadfile("fei_mj_lamps/mjelctrn.lua")()
        elseif is_lhzb_1_2 then
            game_module = loadfile("fei_mj_lamps/lhzb_1_2.lua")()
        elseif is_lhzb3 then
            game_module = loadfile("fei_mj_lamps/lhzb3.lua")()
        elseif is_lhzb4 then
            game_module = loadfile("fei_mj_lamps/lhzb4.lua")()
        elseif is_ougonhai then
            game_module = loadfile("fei_mj_lamps/ougonhai.lua")()
        elseif is_qlgs then
            game_module = loadfile("fei_mj_lamps/qlgs.lua")()
        elseif is_xymg then
            game_module = loadfile("fei_mj_lamps/xymg.lua")()
        elseif is_sdmg2 then
            game_module = loadfile("fei_mj_lamps/sdmg2.lua")()
        elseif is_lhb then
            game_module = loadfile("fei_mj_lamps/lhb.lua")()
        elseif is_tenkai then
            game_module = loadfile("fei_mj_lamps/tenkai.lua")()
        elseif is_mgcs then
            game_module = loadfile("fei_mj_lamps/mgcs.lua")()
        elseif is_mgzz then
            game_module = loadfile("fei_mj_lamps/mgzz.lua")()
        elseif is_mcnpshnt then
            game_module = loadfile("fei_mj_lamps/mcnpshnt.lua")()
        elseif is_jantouki then
            game_module = loadfile("fei_mj_lamps/jantouki.lua")()
        end

        module_loaded = true
    end

    -- 将参数传给被调用的具体游戏插件执行
    if game_module then
        if rom_name == "jantouki" then
            local bottom = machine.screens[":bottom"]
            local top = machine.screens[":top"]
            if bottom then
                game_module(machine, bottom, top, blink_state)
            end
        else
            game_module(machine, screen, blink_state)
        end
    end

    -- ==========================================================
    -- 🛠️ 开发者工具：像素探针开关 (发布前请在下方代码前加 -- 注释掉)
    -- ==========================================================
    -- local debug_probe = loadfile("fei_mj_lamps/pixel_probe.lua")
    -- if debug_probe then debug_probe()(machine, screen) end

end)