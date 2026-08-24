-- 通用牌面绘制（各机共用）。有 PNG 则贴图，否则色块+短名。
-- 牌图目录：fei_mj_lamps/art/tiles/   命名见同目录 NAMING.txt / 仓库 牌图需求.md

local ART_DIR = "fei_mj_lamps/art/tiles"
local BTN_DIRS = { "artwork/rbmk", "fei_mj_lamps/art/buttons" }

-- 与横屏透视/暂停相近：142×115 / 1600×900。竖屏再按 1000×1640 换成 142×130。
local MARK = { x0 = 0.730, y0 = 0.092, x1 = 0.819, y1 = 0.220 }

local function current_mark()
    local land = true
    pcall(function()
        local r = manager.machine.render
        local v = r.ui_target and r.ui_target.current_view
        if not v and r.targets then
            for i = 1, 4 do
                local t = r.targets[i]
                if t and not t.hidden and t.current_view then
                    v = t.current_view
                    break
                end
            end
        end
        if v then
            land = tostring(v.name or ""):find("Landscape", 1, true) ~= nil
        end
    end)
    if land then
        MARK.x0, MARK.y0, MARK.x1, MARK.y1 = 0.730, 0.092, 0.819, 0.220
    else
        MARK.x0, MARK.y0, MARK.x1, MARK.y1 = 0.728, 0.092, 0.870, 0.171
    end
    return MARK
end

local PNG_NAMES = {
    "man1", "man2", "man3", "man4", "man5", "man6", "man7", "man8", "man9",
    "pin1", "pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "pin8", "pin9",
    "sou1", "sou2", "sou3", "sou4", "sou5", "sou6", "sou7", "sou8", "sou9",
    "man5-aka", "pin5-aka", "sou5-aka", "blank", "back",
}

local SUIT_FILL = {
    man = 0xFFE8C8C0,
    pin = 0xFFC8D8F0,
    sou = 0xFFC8E4C8,
    unk = 0xFFD0D0D0,
}
local SUIT_EDGE = {
    man = 0xFFA05040,
    pin = 0xFF4060A0,
    sou = 0xFF407040,
    unk = 0xFF606060,
}

local png_files = 0
local png_have = {}
local bitmaps = {}
local textures = {}
local btn_bitmaps = {}
local btn_tex = {}
local art_tried = false

local function art_key(raw)
    if not raw or raw == 0 then
        return "blank"
    end
    local v = raw & 0xFF
    local aka = false
    if v >= 0x80 then
        aka = true
        v = v - 0x80
    end
    local hi = v >> 4
    local lo = v & 0x0F
    if lo < 1 or lo > 9 then
        return "unknown"
    end
    local suit = ({ [0] = "man", [1] = "pin", [2] = "sou" })[hi]
    if not suit then
        return "unknown"
    end
    if aka and lo == 5 then
        return string.format("%s5-aka", suit)
    end
    return string.format("%s%d", suit, lo)
end

local function short_label(tile)
    if not tile or tile.empty or not tile.name or tile.name == "＿" then
        return ""
    end
    local n = tile.name
    if n:sub(1, 3) == "赤" then
        return "赤" .. n:sub(4, 6)
    end
    return n
end

local function refresh_png_index()
    png_have = {}
    png_files = 0
    for _, key in ipairs(PNG_NAMES) do
        local f = io.open(ART_DIR .. "/" .. key .. ".png", "rb")
        if f then
            f:close()
            png_have[key] = true
            png_files = png_files + 1
        end
    end
end

local function load_textures(machine)
    if art_tried then
        return
    end
    art_tried = true
    refresh_png_index()
    local render = machine and machine.render
    if not render or not render.texture_alloc then
        return
    end
    if not (emu.bitmap_argb32 and emu.bitmap_argb32.load) then
        return
    end
    local ntex = 0
    for _, key in ipairs(PNG_NAMES) do
        local f = io.open(ART_DIR .. "/" .. key .. ".png", "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data and #data > 16 then
                local ok, bmp = pcall(emu.bitmap_argb32.load, data)
                if ok and bmp then
                    local ok2, tex = pcall(function()
                        return render:texture_alloc(bmp)
                    end)
                    if ok2 and tex then
                        bitmaps[key] = bmp
                        textures[key] = tex
                        ntex = ntex + 1
                    end
                end
            end
        end
    end
    png_files = math.max(png_files, ntex)
    for _, key in ipairs({ "mark_up", "mark_down" }) do
        for _, dir in ipairs(BTN_DIRS) do
            local f = io.open(dir .. "/" .. key .. ".png", "rb")
            if f then
                local data = f:read("*a")
                f:close()
                if data and #data > 16 then
                    local ok, bmp = pcall(emu.bitmap_argb32.load, data)
                    if ok and bmp then
                        local ok2, tex = pcall(function()
                            return render:texture_alloc(bmp)
                        end)
                        if ok2 and tex then
                            btn_bitmaps[key] = bmp
                            btn_tex[key] = tex
                            break
                        end
                    end
                end
            end
        end
    end
end

local function suit_of(raw)
    if not raw or raw == 0 then
        return "unk"
    end
    local v = raw & 0xFF
    if v >= 0x80 then
        v = v - 0x80
    end
    return ({ [0] = "man", [1] = "pin", [2] = "sou" })[v >> 4] or "unk"
end

local function draw_tile(ui, x, y, w, h, tile, hi)
    local empty = (not tile) or tile.empty or not tile.raw or tile.raw == 0
    local key = empty and "blank" or art_key(tile and tile.raw)
    local tex = textures[key]
    local aka = tile and tile.raw and (tile.raw & 0xFF) >= 0x80
    if hi then
        ui:draw_box(x - 0.0015, y - 0.002, x + w + 0.0015, y + h + 0.002, 0xFFFFFF40, 0x60FFFF00)
    elseif aka then
        ui:draw_box(x - 0.001, y - 0.0015, x + w + 0.0015, y + h + 0.0015, 0xFFC09020, 0x00000000)
    end
    if tex then
        local drawn = false
        pcall(function()
            ui:draw_quad(tex, x, y, x + w, y + h, 0xffffffff)
            drawn = true
        end)
        if drawn then
            return
        end
    end
    local fill = empty and 0xFF303038 or SUIT_FILL[suit_of(tile and tile.raw)]
    local edge = hi and 0xFFFFFF40 or (empty and 0xFF505058 or SUIT_EDGE[suit_of(tile and tile.raw)])
    if aka then
        edge = hi and 0xFFFFFF40 or 0xFFC09020
    end
    ui:draw_box(x, y, x + w, y + h, edge, fill)
    if not empty then
        local label = short_label(tile)
        if label ~= "" then
            ui:draw_text(x + 0.002, y + h * 0.28, label, 0xFF202020)
        end
    end
end

local function draw_row(ui, x, y, w, h, gap, list, maxn, hi_first)
    if not list then
        return
    end
    local n = math.min(maxn or 23, #list)
    for i = 1, n do
        draw_tile(ui, x + (i - 1) * (w + gap), y, w, h, list[i], hi_first and i == 1)
    end
end

local function draw_panel(ui, st)
    local lh = 0.032
    pcall(function()
        lh = manager.ui.line_height
    end)
    current_mark()
    ui:draw_box(0.015, 0.09, 0.985, 0.72, 0x00000000, 0xC0101420)
    local ntex = 0
    for _ in pairs(textures) do
        ntex = ntex + 1
    end
    local art_note
    if ntex > 0 then
        art_note = string.format("  牌图 %d/32", ntex)
    elseif png_files > 0 then
        art_note = string.format("  有文件 %d/32，贴图失败", png_files)
    else
        art_note = "  （尚无牌图，色块占位）"
    end
    ui:draw_text(0.03, 0.10, (st.title or "透视") .. art_note, 0xffffff40)
    ui:draw_text(0.03, 0.10 + lh, st.line1 or "", 0xffffffff)
    local mark_png = btn_tex.mark_up
    local drew_mark = false
    if mark_png then
        pcall(function()
            ui:draw_quad(mark_png, MARK.x0, MARK.y0, MARK.x1, MARK.y1, 0xffffffff)
            drew_mark = true
        end)
    end
    if not drew_mark then
        ui:draw_box(MARK.x0, MARK.y0, MARK.x1, MARK.y1, 0x00000000, 0xE0184068)
        ui:draw_text(MARK.x0 + 0.01, MARK.y0 + 0.014, "标记牌山", 0xffffffff)
    end

    local tw, th, gap = 0.036, 0.070, 0.004
    local x0 = 0.03
    ui:draw_text(0.03, 0.17, st.cpu_label or "电脑手", 0xffffd0a0)
    draw_row(ui, x0, 0.205, tw, th, gap, st.cpu, 14, false)

    local a_hi = st.next_side == "A"
    local b_hi = st.next_side == "B"
    ui:draw_text(0.03, 0.29, (a_hi and "●" or " ") .. (st.name_a or "A"), 0xffffffff)
    draw_row(ui, x0, 0.325, tw, th, gap, st.seq_a, 23, a_hi)
    ui:draw_text(0.03, 0.41, (b_hi and "●" or " ") .. (st.name_b or "B"), 0xffb0b0b0)
    draw_row(ui, x0, 0.445, tw, th, gap, st.seq_b, 23, b_hi)

    ui:draw_text(0.03, 0.54, "黄框=下一摸    金边=赤五", 0xff808080)
    ui:draw_text(0.03, 0.58, "注意：听牌将成时电脑可能换山，下摸会突然对不上，属游戏机制不是读错。", 0xffffa060)
end

local function draw_toggle(_ui, _open)
    -- 透视开关是皮肤 PNG（吃碰杠听胡一侧），不再画 Lua 色块
end

local function hit_toggle(_nx, _ny)
    return false
end

return {
    art_key = art_key,
    art_dir = ART_DIR,
    toggle = MARK,
    ensure_art = load_textures,
    refresh = function()
        if art_tried then
            refresh_png_index()
            return
        end
        load_textures(manager and manager.machine)
    end,
    png_count = function()
        return png_files
    end,
    hit_toggle = hit_toggle,
    mark_btn = MARK,
    mark_rect = current_mark,
    hit_mark = function(nx, ny)
        local m = current_mark()
        return nx and ny
            and nx >= m.x0 and nx <= m.x1
            and ny >= m.y0 and ny <= m.y1
    end,
    draw_tile = draw_tile,
    draw_row = draw_row,
    draw_panel = draw_panel,
    draw_toggle = draw_toggle,
}
