-- 通用牌面绘制（各机共用）。有 PNG 则贴图，否则色块+短名。
-- 牌图目录：fei_mj_lamps/art/tiles/   命名见同目录 NAMING.txt / 仓库 牌图需求.md

local ART_DIR = "fei_mj_lamps/art/tiles"
local BTN_DIRS = { "artwork/rbmk", "fei_mj_lamps/art/buttons" }

-- 电脑手最多 13 张。牌山每行只显示 13 张：本行开局前 13 张满亮，被摸走后滑进来的牌保持半透明。
-- 比例按 layout 里游戏画面的显示矩形算。标记钮在标题栏右上角，约 11:10。
local ROW_N = 13
local TILE_ASPECT = 3 / 4
local MARK_ASPECT = 11 / 10
local GAP_FRAC = 0.08
local MARK = { x0 = 0.730, y0 = 0.012, x1 = 0.819, y1 = 0.112 }
-- 玩家手牌约在 0.875；框可压住 A–N 字母，勿压到底部手牌。
local GY1_MAX = 0.82
local DIM_ARGB = 0x80ffffff

local ntex_cached = 0
local art_note_cached = "  （尚无牌图，色块占位）"
local layout_cache = { key = "", land = true }
local view_cache = { age = 99, view = nil, land = true, machine = nil }

local LAY_LAND = { vx = 1600, vy = 900, sx = 200, sy = 0, sw = 1200, sh = 900 }
local LAY_PORT = { vx = 1000, vy = 1640, sx = 0, sy = 0, sw = 1000, sh = 970 }
local PEEK_LAND = { x0 = 1400 / 1600, y0 = 10 / 900, x1 = 1542 / 1600, y1 = 125 / 900 }
local PEEK_PORT = { x0 = 3 / 1000, y0 = 1110 / 1640, x1 = 145 / 1000, y1 = 1240 / 1640 }

local function current_view()
    local m = nil
    pcall(function()
        m = manager.machine
    end)
    if m ~= view_cache.machine then
        view_cache.machine = m
        view_cache.age = 99
        view_cache.view = nil
    end
    view_cache.age = view_cache.age + 1
    if view_cache.view and view_cache.age < 12 then
        return view_cache.view
    end
    local v
    pcall(function()
        local r = m and m.render
        if r.targets then
            for i = 1, 4 do
                local t = r.targets[i]
                if t and not t.hidden and t.current_view then
                    local name = tostring(t.current_view.name or "")
                    if name:find("Landscape", 1, true) or name:find("Portrait", 1, true) then
                        v = t.current_view
                        return
                    end
                end
            end
        end
        if r.ui_target and r.ui_target.current_view then
            v = r.ui_target.current_view
        end
    end)
    view_cache.age = 0
    view_cache.view = v
    return v
end

local function is_landscape()
    local v = current_view()
    if v then
        local name = ""
        pcall(function()
            name = tostring(v.name or "")
        end)
        if name:find("Landscape", 1, true) then
            view_cache.land = true
            return true
        end
        if name:find("Portrait", 1, true) then
            view_cache.land = false
            return false
        end
    end
    return view_cache.land
end

local function view_is_land(view)
    local name = ""
    pcall(function()
        name = tostring(view and view.name or "")
    end)
    if name:find("Portrait", 1, true) then
        return false
    end
    if name:find("Landscape", 1, true) then
        return true
    end
    return is_landscape()
end

local function lay_screen(land)
    if land == nil then
        land = is_landscape()
    end
    return land and LAY_LAND or LAY_PORT
end

local game_ui_cache = { machine = nil, ui = nil, on_game = false }

local function game_container(machine)
    if machine and game_ui_cache.machine == machine and game_ui_cache.ui then
        return game_ui_cache.ui, game_ui_cache.on_game
    end
    game_ui_cache.machine = machine
    game_ui_cache.ui = nil
    game_ui_cache.on_game = false
    local c
    pcall(function()
        local s = machine and machine.screens and machine.screens[":screen"]
        c = s and s.container
    end)
    if c then
        game_ui_cache.ui, game_ui_cache.on_game = c, true
        return c, true
    end
    local ui = machine and machine.render and machine.render.ui_container
    game_ui_cache.ui, game_ui_cache.on_game = ui, false
    return ui, false
end

local function item_xy(item)
    if not item then
        return nil
    end
    local b
    pcall(function()
        b = item.bounds
        if type(b) == "function" then
            b = item:bounds()
        end
    end)
    if b and b.x0 then
        return b.x0, b.y0, b.x1, b.y1
    end
    return nil
end

-- 用透视键实际窗口位置，把 View 0–1 换成渲染目标 0–1
local function view_to_target_map(view)
    if not view then
        return nil
    end
    if view.items then
        local x0, y0, x1, y1 = item_xy(view.items["btn_peek"])
        if x0 and math.abs(x1 - x0) >= 0.002 and x0 <= 2 and y0 <= 2 then
            local p = view_is_land(view) and PEEK_LAND or PEEK_PORT
            local sx = (x1 - x0) / (p.x1 - p.x0)
            local sy = (y1 - y0) / (p.y1 - p.y0)
            if sx >= 0.05 and sy >= 0.05 and sx <= 8 and sy <= 8 then
                return {
                    ox = x0 - p.x0 * sx,
                    oy = y0 - p.y0 * sy,
                    sx = sx,
                    sy = sy,
                }
            end
        end
    end
    local vb
    pcall(function()
        vb = view.bounds
    end)
    if vb and vb.x0 and (vb.x1 - vb.x0) > 0.08 and (vb.x1 - vb.x0) < 0.95 then
        return {
            ox = vb.x0,
            oy = vb.y0,
            sx = vb.x1 - vb.x0,
            sy = vb.y1 - vb.y0,
        }
    end
    return nil
end

local function view_to_screen(view, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil
    end
    local land = view_is_land(view)
    local L = lay_screen(land)
    local nx, ny = x, y
    local map = view_to_target_map(view)
    if map and x <= 2 and y <= 2 then
        nx = (x - map.ox) / map.sx
        ny = (y - map.oy) / map.sy
    elseif x > 2 or y > 2 then
        nx, ny = x / L.vx, y / L.vy
    end
    local sx0, sy0 = L.sx / L.vx, L.sy / L.vy
    local sw, sh = L.sw / L.vx, L.sh / L.vy
    local sx = (nx - sx0) / sw
    local sy = (ny - sy0) / sh
    if sx < -0.02 or sx > 1.02 or sy < -0.02 or sy > 1.02 then
        return nil, nil
    end
    return sx, sy
end

-- ui_container / layout 全窗 0–1（mjelctrn HUD 画在此空间，勿再减游戏画面 inset）
local function view_to_ui01(view, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil
    end
    local land = view_is_land(view)
    local L = lay_screen(land)
    local nx, ny = x, y
    local map = view_to_target_map(view)
    if map and x <= 2 and y <= 2 then
        nx = (x - map.ox) / map.sx
        ny = (y - map.oy) / map.sy
    elseif x > 2 or y > 2 then
        nx, ny = x / L.vx, y / L.vy
    end
    return nx, ny
end

local function screen_to_view_rect(x0, y0, x1, y1, land)
    local L = lay_screen(land)
    local sx0, sy0 = L.sx / L.vx, L.sy / L.vy
    local sw, sh = L.sw / L.vx, L.sh / L.vy
    return {
        x0 = sx0 + x0 * sw,
        y0 = sy0 + y0 * sh,
        x1 = sx0 + x1 * sw,
        y1 = sy0 + y1 * sh,
    }
end

-- 窗口里看到的宽/高 = aspect 时，屏幕 0–1 里 x 跨度 / y 跨度
local function vis_xy_ratio(wh, land)
    local L = lay_screen(land)
    return wh * (L.sh / L.sw)
end

local function tile_from_width(avail_w, land, nfit)
    nfit = nfit or ROW_N
    local tw = avail_w / (nfit + (nfit - 1) * GAP_FRAC)
    local gap = math.max(0.002, tw * GAP_FRAC)
    local th = tw / vis_xy_ratio(TILE_ASPECT, land)
    return tw, th, gap
end

local function panel_geom()
    local land = is_landscape()
    local key = land and "L" or "P"
    if layout_cache.key == key then
        return layout_cache
    end
    local gx0, gy0, gx1 = 0.012, 0.012, 0.988
    local title_h = 0.100
    local avail_w = gx1 - gx0
    local tw, th, gap = tile_from_width(avail_w, land, ROW_N)
    -- 横屏：行标签与牌之间留出字高，避免「电脑手/玩家」压住牌面
    local lab = land and 0.058 or 0.038
    local row_pad = land and 0.014 or 0.010
    local lab_to_tile = land and 1.0 or 0.70
    local mark_h = title_h - 0.008
    local mark_w = mark_h * vis_xy_ratio(MARK_ASPECT, land)
    MARK.x1 = gx1 - 0.006
    MARK.y0 = gy0 + 0.005
    MARK.x0 = MARK.x1 - mark_w
    MARK.y1 = MARK.y0 + mark_h
    local cpu_lab_y = gy0 + title_h
    local cpu_y = cpu_lab_y + lab * lab_to_tile
    local a_lab_y = cpu_y + th + row_pad
    local a_y = a_lab_y + lab * lab_to_tile
    local b_lab_y = a_y + th + row_pad
    local b_y = b_lab_y + lab * lab_to_tile
    local tiles_end = b_y + th
    local note_h = land and 0.050 or 0.042
    local tile_note_gap = land and 0.048 or 0.030
    local note_bottom = land and 0.028 or 0.022
    local notes_block = tile_note_gap + note_h * 2 + note_bottom
    local gy1 = tiles_end + notes_block
    if gy1 < GY1_MAX then
        gy1 = math.min(GY1_MAX, gy1 + (land and 0.03 or 0.06))
    end
    if gy1 > GY1_MAX then
        gy1 = GY1_MAX
    end
    local note_y = tiles_end + tile_note_gap
    local note2_y = note_y + note_h
    local g = {
        key = key,
        land = land,
        gx0 = gx0,
        gy0 = gy0,
        gx1 = gx1,
        gy1 = gy1,
        tw = tw,
        th = th,
        gap = gap,
        x0 = gx0,
        title_y = gy0 + 0.010,
        line1_y = gy0 + 0.052,
        cpu_lab_y = cpu_lab_y,
        cpu_y = cpu_y,
        a_lab_y = a_lab_y,
        a_y = a_y,
        b_lab_y = b_lab_y,
        b_y = b_y,
        note_y = note_y,
        note2_y = note2_y,
        foot_y = gy1 - 0.02,
    }
    layout_cache = g
    return g
end

local function screen_to_window_xy(sx, sy)
    local view = current_view()
    if not view then
        return nil, nil
    end
    local land = view_is_land(view)
    local vr = screen_to_view_rect(sx, sy, sx + 0.001, sy + 0.001, land)
    local map = view_to_target_map(view)
    if not map then
        return nil, nil
    end
    return map.ox + vr.x0 * map.sx, map.oy + vr.y0 * map.sy
end

local function current_mark()
    panel_geom()
    return MARK
end

-- lay 的 set_bounds_callback 必须返回窗口 0–1，不能直接塞 View 比例（竖屏会跑到黑边并把画面挤偏）
local function mark_target_rect(view)
    local m = current_mark()
    local land = view_is_land(view)
    local vr = screen_to_view_rect(m.x0, m.y0, m.x1, m.y1, land)
    local map = view_to_target_map(view)
    if not map then
        return nil
    end
    return {
        x0 = map.ox + vr.x0 * map.sx,
        y0 = map.oy + vr.y0 * map.sy,
        x1 = map.ox + vr.x1 * map.sx,
        y1 = map.oy + vr.y1 * map.sy,
    }
end

local PNG_NAMES = {
    "man1", "man2", "man3", "man4", "man5", "man6", "man7", "man8", "man9",
    "pin1", "pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "pin8", "pin9",
    "sou1", "sou2", "sou3", "sou4", "sou5", "sou6", "sou7", "sou8", "sou9",
    "man5-aka", "pin5-aka", "sou5-aka", "blank", "back",
    "honor-e", "honor-s", "honor-w", "honor-n", "honor-c", "honor-f", "honor-p",
}
local PNG_TOTAL = 39

local SUIT_FILL = {
    man = 0xFFE8C8C0,
    pin = 0xFFC8D8F0,
    sou = 0xFFC8E4C8,
    honor = 0xFFE8E0F0,
    unk = 0xFFD0D0D0,
}
local SUIT_EDGE = {
    man = 0xFFA05040,
    pin = 0xFF4060A0,
    sou = 0xFF407040,
    honor = 0xFF605090,
    unk = 0xFF606060,
}

local png_files = 0
local png_have = {}
local bitmaps = {}
local textures = {}
local btn_bitmaps = {}
local btn_tex = {}
local art_tried = false
local panel_cache = { sig = "", key = "", w = 0, h = 0, bmp = nil, tex = nil, enabled = true }
local COLOR_DIM = nil
local COLOR_FULL = nil

local function panel_pixel_size(g)
    local L = lay_screen(g.land)
    return math.max(64, math.floor((g.gx1 - g.gx0) * L.sw)), math.max(64, math.floor((g.gy1 - g.gy0) * L.sh))
end

local function panel_sig(st, g)
    local parts = {
        g.key,
        st.name_a or "",
        st.name_b or "",
        st.next_side or "",
        tostring(st.dim_a or 0),
        tostring(st.dim_b or 0),
    }
    local function row_sig(list)
        if not list then
            return "-"
        end
        local t = {}
        for i = 1, math.min(ROW_N, #list) do
            t[#t + 1] = string.format("%02X", list[i].raw or 0)
        end
        return table.concat(t, ",")
    end
    parts[#parts + 1] = row_sig(st.cpu)
    parts[#parts + 1] = row_sig(st.seq_a)
    parts[#parts + 1] = row_sig(st.seq_b)
    return table.concat(parts, "|")
end

local function ensure_panel_colors()
    if COLOR_FULL then
        return true
    end
    if not emu.render_color then
        return false
    end
    local ok
    ok, COLOR_FULL = pcall(emu.render_color, 1, 1, 1, 1)
    if not ok then
        return false
    end
    ok, COLOR_DIM = pcall(emu.render_color, 0.5, 1, 1, 1)
    return ok
end

local function free_panel_texture()
    local render = manager and manager.machine and manager.machine.render
    if render and panel_cache.tex and render.texture_free then
        pcall(function()
            render:texture_free(panel_cache.tex)
        end)
    end
    panel_cache.tex = nil
    panel_cache.bmp = nil
end

local function screen_rect_to_panel_px(g, pw, ph, x, y, w, h)
    local px = math.floor((x - g.gx0) / (g.gx1 - g.gx0) * pw)
    local py = math.floor((y - g.gy0) / (g.gy1 - g.gy0) * ph)
    local tw = math.max(1, math.floor(w / (g.gx1 - g.gx0) * pw))
    local th = math.max(1, math.floor(h / (g.gy1 - g.gy0) * ph))
    return px, py, tw, th
end

local function blit_tile_bmp(panel, g, pw, ph, x, y, w, h, tile, hi, dim)
    if (not tile) or tile.empty or not tile.raw or tile.raw == 0 then
        return
    end
    local px, py, tw, th = screen_rect_to_panel_px(g, pw, ph, x, y, w, h)
    if px + tw > pw or py + th > ph then
        return
    end
    local key = art_key_for(tile)
    local src = bitmaps[key]
    local aka = tile.enc ~= "bcd" and (tile.raw & 0xFF) >= 0x80
    if src then
        local ok = pcall(function()
            local slot = emu.bitmap_argb32(panel, px, py, px + tw - 1, py + th - 1)
            src:resample(slot, dim and COLOR_DIM or COLOR_FULL)
        end)
        if ok then
            if hi then
                pcall(function()
                    panel:plot_box(px - 1, py - 1, tw + 2, th + 2, 0x60FFFF00)
                end)
            elseif aka and not dim then
                pcall(function()
                    panel:plot_box(px - 1, py - 1, tw + 2, th + 2, 0xFFC09020)
                end)
            end
            return
        end
    end
    local fill = SUIT_FILL[suit_of_tile(tile)]
    if dim then
        fill = with_alpha(fill, 0x80)
    end
    pcall(function()
        panel:plot_box(px, py, tw, th, fill)
    end)
end

local function blit_row_bmp(panel, g, pw, ph, x, y, w, h, gap, list, maxn, hi_first, dim_after)
    if not list then
        return
    end
    local n = math.min(maxn or ROW_N, #list)
    if dim_after == nil then
        dim_after = 99
    end
    for i = 1, n do
        blit_tile_bmp(panel, g, pw, ph, x + (i - 1) * (w + gap), y, w, h, list[i], hi_first and i == 1, i > dim_after)
    end
end

local function ensure_panel_bitmap(render, g)
    local pw, ph = panel_pixel_size(g)
    if panel_cache.bmp and panel_cache.key == g.key and panel_cache.w == pw and panel_cache.h == ph then
        return panel_cache.bmp, pw, ph
    end
    free_panel_texture()
    local bmp
    local ok = pcall(function()
        bmp = emu.bitmap_argb32(pw, ph)
    end)
    if not ok or not bmp then
        return nil
    end
    local tex
    ok = pcall(function()
        tex = render:texture_alloc(bmp)
    end)
    if not ok or not tex then
        return nil
    end
    panel_cache.bmp = bmp
    panel_cache.tex = tex
    panel_cache.key = g.key
    panel_cache.w = pw
    panel_cache.h = ph
    panel_cache.sig = ""
    return bmp, pw, ph
end

local function rebuild_panel_cache(machine, st, g)
    if not ensure_panel_colors() then
        return false
    end
    local render = machine and machine.render
    if not render or not render.texture_alloc then
        return false
    end
    load_textures(machine)
    local panel, pw, ph = ensure_panel_bitmap(render, g)
    if not panel then
        return false
    end
    pcall(function()
        panel:fill(0xC0101420)
    end)
    blit_row_bmp(panel, g, pw, ph, g.x0, g.cpu_y, g.tw, g.th, g.gap, st.cpu, ROW_N, false)
    local a_hi = st.next_side == "A"
    local b_hi = st.next_side == "B"
    blit_row_bmp(panel, g, pw, ph, g.x0, g.a_y, g.tw, g.th, g.gap, st.seq_a, ROW_N, a_hi, st.dim_a)
    blit_row_bmp(panel, g, pw, ph, g.x0, g.b_y, g.tw, g.th, g.gap, st.seq_b, ROW_N, b_hi, st.dim_b)
    return true
end

local function draw_panel_labels(ui, st, g)
    ui:draw_text(g.x0, g.title_y, (st.title or "透视") .. art_note_cached, 0xffffff40)
    ui:draw_text(g.x0, g.line1_y, st.line1 or "", 0xffffffff)
    ui:draw_text(g.x0, g.cpu_lab_y, st.cpu_label or "电脑手", 0xffffd0a0)
    local a_hi = st.next_side == "A"
    local b_hi = st.next_side == "B"
    ui:draw_text(g.x0, g.a_lab_y, (a_hi and "●" or " ") .. (st.name_a or "A"), 0xffffffff)
    ui:draw_text(g.x0, g.b_lab_y, (b_hi and "●" or " ") .. (st.name_b or "B"), 0xffb0b0b0)
    if st.note1 and st.note1 ~= "" then
        local uic, nx, ny, ny2
        if g.land then
            pcall(function()
                uic = manager.machine.render.ui_container
            end)
            if g.note_wx then
                nx, ny, ny2 = g.note_wx, g.note_wy, g.note2_wy
            else
                nx, ny = screen_to_window_xy(g.x0, g.note_y)
                _, ny2 = screen_to_window_xy(g.x0, g.note2_y)
                if nx then
                    g.note_wx, g.note_wy, g.note2_wy = nx, ny, ny2
                end
            end
        end
        if g.land and uic and ny then
            uic:draw_text(nx, ny, st.note1, 0xffffe090)
            if st.note2 and ny2 then
                uic:draw_text(nx, ny2, st.note2, 0xffffc070)
            end
        else
            ui:draw_text(g.x0, g.note_y, st.note1, 0xffffe090)
            if st.note2 then
                ui:draw_text(g.x0, g.note2_y, st.note2, 0xffffc070)
            end
        end
    end
end

local function art_key_bcd(v)
    if not v or v == 0 then
        return "blank"
    end
    v = v & 0xFF
    if v >= 0x01 and v <= 0x09 then
        return string.format("man%d", v)
    end
    if v >= 0x11 and v <= 0x19 then
        return string.format("pin%d", v - 0x10)
    end
    if v >= 0x21 and v <= 0x29 then
        return string.format("sou%d", v - 0x20)
    end
    return ({
        [0x31] = "honor-e",
        [0x32] = "honor-s",
        [0x33] = "honor-w",
        [0x34] = "honor-n",
        [0x35] = "honor-p",
        [0x36] = "honor-f",
        [0x37] = "honor-c",
    })[v] or "unknown"
end

local function art_key_for(tile)
    if tile and tile.enc == "bcd" then
        return art_key_bcd(tile.raw)
    end
    return art_key(tile and tile.raw)
end

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
        n = "赤" .. n:sub(4, 6)
    elseif #n > 2 then
        -- keep full CJK name (e.g. 3万)
    end
    if tile.count ~= nil then
        return tostring(tile.count)
    end
    if #n <= 2 then
        return n
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
    ntex_cached = ntex
    if ntex > 0 then
        art_note_cached = string.format("  牌图 %d/%d", ntex, PNG_TOTAL)
    elseif png_files > 0 then
        art_note_cached = string.format("  有文件 %d/%d，贴图失败", png_files, PNG_TOTAL)
    else
        art_note_cached = "  （尚无牌图，色块占位）"
    end
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

local function suit_of_tile(tile)
    if tile and tile.enc == "bcd" then
        local v = tile.raw & 0xFF
        if v >= 0x01 and v <= 0x09 then
            return "man"
        end
        if v >= 0x11 and v <= 0x19 then
            return "pin"
        end
        if v >= 0x21 and v <= 0x29 then
            return "sou"
        end
        if v >= 0x31 and v <= 0x37 then
            return "honor"
        end
        return "unk"
    end
    return suit_of(tile and tile.raw)
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

local function with_alpha(col, a)
    return ((a & 0xFF) << 24) | (col & 0x00FFFFFF)
end

local function draw_tile(ui, x, y, w, h, tile, hi, dim)
    if (not tile) or tile.empty or not tile.raw or tile.raw == 0 then
        return
    end
    if tile.dim then
        dim = true
    end
    local key = art_key_for(tile)
    local tex = textures[key]
    local aka = tile.enc ~= "bcd" and (tile.raw & 0xFF) >= 0x80
    local tint = dim and DIM_ARGB or 0xffffffff
    if hi or tile.force_hi then
        ui:draw_box(x - 0.0015, y - 0.002, x + w + 0.0015, y + h + 0.002, 0xFFFFFF40, 0x60FFFF00)
        hi = true
    elseif aka and not dim then
        ui:draw_box(x - 0.001, y - 0.0015, x + w + 0.0015, y + h + 0.0015, 0xFFC09020, 0x00000000)
    end
    if tex then
        ui:draw_quad(tex, x, y, x + w, y + h, tint)
        if tile.count ~= nil then
            ui:draw_text(
                x + w * 0.55,
                y + h * 0.02,
                tostring(tile.count),
                dim and 0x80202080 or 0xff1a1060
            )
        end
        return
    end
    local fill = SUIT_FILL[suit_of_tile(tile)]
    local edge = hi and 0xFFFFFF40 or SUIT_EDGE[suit_of_tile(tile)]
    if aka then
        edge = hi and 0xFFFFFF40 or 0xFFC09020
    end
    if dim then
        fill = with_alpha(fill, 0x80)
        edge = with_alpha(edge, 0x80)
    end
    ui:draw_box(x, y, x + w, y + h, edge, fill)
    local label = short_label(tile)
    if label ~= "" then
        ui:draw_text(x + 0.002, y + h * 0.28, label, dim and 0x80202020 or 0xFF202020)
    end
end

local function draw_row(ui, x, y, w, h, gap, list, maxn, hi_first, dim_after, hi_idx)
    if not list then
        return
    end
    local n = math.min(maxn or ROW_N, #list)
    if dim_after == nil then
        dim_after = 99
    end
    for i = 1, n do
        local t = list[i]
        local hi = (hi_first and i == 1) or (hi_idx and i == hi_idx) or (t and t.force_hi)
        local dim = (i > dim_after) or (t and (t.dim or t.count == 0))
        draw_tile(ui, x + (i - 1) * (w + gap), y, w, h, t, hi, dim)
    end
end

local function draw_panel_cached(ui, st, g)
    if not panel_cache.tex then
        return false
    end
    local drew = false
    pcall(function()
        ui:draw_quad(panel_cache.tex, g.gx0, g.gy0, g.gx1, g.gy1, 0xffffffff)
        drew = true
    end)
    if drew then
        draw_panel_labels(ui, st, g)
        return true
    end
    return false
end

local function draw_panel_legacy(ui, st)
    local g = panel_geom()
    ui:draw_box(g.gx0, g.gy0, g.gx1, g.gy1, 0x00000000, 0xC0101420)
    ui:draw_text(g.x0, g.cpu_lab_y, st.cpu_label or "电脑手", 0xffffd0a0)
    draw_row(ui, g.x0, g.cpu_y, g.tw, g.th, g.gap, st.cpu, ROW_N, false)
    local a_hi = st.next_side == "A"
    local b_hi = st.next_side == "B"
    draw_row(ui, g.x0, g.a_y, g.tw, g.th, g.gap, st.seq_a, ROW_N, a_hi, st.dim_a)
    draw_row(ui, g.x0, g.b_y, g.tw, g.th, g.gap, st.seq_b, ROW_N, b_hi, st.dim_b)
    draw_panel_labels(ui, st, g)
end

local function draw_panel(ui, st)
    if not st then
        return
    end
    local g = panel_geom()
    if panel_cache.enabled and emu.bitmap_argb32 and manager and manager.machine then
        local sig = panel_sig(st, g)
        if sig ~= panel_cache.sig then
            local ok = pcall(rebuild_panel_cache, manager.machine, st, g)
            if ok and panel_cache.tex then
                panel_cache.sig = sig
            else
                panel_cache.enabled = false
                panel_cache.sig = ""
            end
        end
        if panel_cache.enabled and draw_panel_cached(ui, st, g) then
            return
        end
        if panel_cache.tex then
            panel_cache.enabled = false
            panel_cache.sig = ""
        end
    end
    draw_panel_legacy(ui, st)
end

local function draw_toggle(_ui, _open)
end

local mjelctrn_layout = { key = "" }
local mjelctrn_pool_hits = {} -- 每帧绘制时缓存，与 ui_container 坐标一致

local function mjelctrn_geom()
    local land = is_landscape()
    -- mL5/mP5：HUD 限制在 layout 游戏画面内，勿盖两侧/底栏按钮
    local key = land and "mL5" or "mP5"
    if mjelctrn_layout.key == key then
        return mjelctrn_layout
    end
    local L = lay_screen(land)
    local pad = land and 0.008 or 0.010
    -- ui_container 与 layout 同 0–1：用 screen 矩形，避开左右 bezel
    local gx0 = (L.sx / L.vx) + pad
    local gx1 = ((L.sx + L.sw) / L.vx) - pad
    local gy0 = (L.sy / L.vy) + pad
    local title_h = land and 0.080 or 0.070
    local avail_w = gx1 - gx0
    local row_n = 13
    local tw, th, gap = tile_from_width(avail_w, land, row_n)
    -- 牌池用略小牌，多排显示 34 种
    local ptw, pth, pgap = tile_from_width(avail_w, land, 17)
    local lab = land and 0.034 or 0.028
    local row_pad = land and 0.008 or 0.006
    local cpu_lab_y = gy0 + title_h
    local cpu_y = cpu_lab_y + lab
    local pool_lab_y = cpu_y + th + row_pad
    local pool_y0 = pool_lab_y + lab
    local pool_rows = 2
    local tiles_end = pool_y0 + pool_rows * (pth + row_pad)
    local note_h = land and 0.036 or 0.030
    local note_gap = land and 0.012 or 0.010
    local gy1 = math.min(GY1_MAX, tiles_end + note_gap + note_h * 2 + 0.016)
    -- 竖屏勿盖到底部按钮带（screen 下沿约 970/1640）
    if not land then
        local screen_bot = (L.sy + L.sh) / L.vy - pad
        gy1 = math.min(gy1, screen_bot)
    end
    mjelctrn_layout = {
        key = key,
        land = land,
        gx0 = gx0,
        gy0 = gy0,
        gx1 = gx1,
        gy1 = gy1,
        tw = tw,
        th = th,
        gap = gap,
        ptw = ptw,
        pth = pth,
        pgap = pgap,
        x0 = gx0,
        title_y = gy0 + 0.008,
        line1_y = gy0 + 0.042,
        cpu_lab_y = cpu_lab_y,
        cpu_y = cpu_y,
        pool_lab_y = pool_lab_y,
        pool_y0 = pool_y0,
        pool_row_pad = row_pad,
        pool_rows = pool_rows,
        pool_row_n = 17,
        note_y = tiles_end + note_gap,
        note2_y = tiles_end + note_gap + note_h,
        row_n = row_n,
    }
    return mjelctrn_layout
end

local function mjelctrn_panel_sig(st, g)
    local parts = { g.key, st.line1 or "", st.note1 or "", st.note2 or "" }
    local function row_sig(list, n)
        if not list then
            return "-"
        end
        local t = {}
        for i = 1, math.min(n or 34, #list) do
            local x = list[i]
            t[#t + 1] = string.format(
                "%02X:%d%s",
                (x and x.raw) or 0,
                (x and x.count) or 0,
                (x and x.force_hi) and "*" or ""
            )
        end
        return table.concat(t, ",")
    end
    parts[#parts + 1] = row_sig(st.queue, 13)
    parts[#parts + 1] = row_sig(st.pool, 34)
    return table.concat(parts, "|")
end

local function rebuild_mjelctrn_panel_cache(machine, st, g)
    if not ensure_panel_colors() then
        return false
    end
    local render = machine and machine.render
    if not render or not render.texture_alloc then
        return false
    end
    load_textures(machine)
    local panel, pw, ph = ensure_panel_bitmap(render, g)
    if not panel then
        return false
    end
    pcall(function()
        panel:fill(0xC0101420)
    end)
    blit_row_bmp(panel, g, pw, ph, g.x0, g.cpu_y, g.tw, g.th, g.gap, st.queue, g.row_n or 13, false)
    local pool = st.pool or {}
    local rows = st.pool_rows or g.pool_rows or 2
    local per = g.pool_row_n or 17
    for r = 0, rows - 1 do
        local slice = {}
        local i0 = r * per
        for i = 1, per do
            local t = pool[i0 + i]
            if t then
                slice[#slice + 1] = t
            end
        end
        if #slice > 0 then
            local y = g.pool_y0 + r * (g.pth + g.pool_row_pad)
            for i = 1, #slice do
                local t = slice[i]
                local hi = t and t.force_hi
                local dim = t and (t.dim or t.count == 0)
                blit_tile_bmp(
                    panel, g, pw, ph,
                    g.x0 + (i - 1) * (g.ptw + g.pgap), y, g.ptw, g.pth,
                    t, hi, dim
                )
            end
        end
    end
    return true
end

local function draw_mjelctrn_labels(ui, st, g)
    ui:draw_text(g.x0, g.title_y, (st.title or "电子基盘 透视") .. art_note_cached, 0xffffff40)
    if st.line1 and st.line1 ~= "" then
        ui:draw_text(g.x0, g.line1_y, st.line1, 0xffffffff)
    end
    ui:draw_text(g.x0, g.cpu_lab_y, st.queue_label or "电脑手", 0xffffd0a0)
    ui:draw_text(g.x0, g.pool_lab_y, st.pool_label or "牌池", 0xffa0ffe0)
    if st.note1 and st.note1 ~= "" then
        ui:draw_text(g.x0, g.note_y, st.note1, 0xffffe090)
    end
    if st.note2 and st.note2 ~= "" then
        ui:draw_text(g.x0, g.note2_y, st.note2, 0xffffc070)
    end
end

local function draw_mjelctrn_counts(ui, st, g)
    local pool = st.pool or {}
    local rows = st.pool_rows or g.pool_rows or 2
    local per = g.pool_row_n or 17
    for r = 0, rows - 1 do
        for i = 1, per do
            local t = pool[r * per + i]
            if t and t.count ~= nil then
                local x0 = g.x0 + (i - 1) * (g.ptw + g.pgap)
                local y = g.pool_y0 + r * (g.pth + g.pool_row_pad)
                ui:draw_text(
                    x0 + g.ptw * 0.55,
                    y + g.pth * 0.55,
                    tostring(t.count),
                    (t.count == 0) and 0x80ffffff or 0xffffff40
                )
            end
        end
    end
end

local function draw_mjelctrn_panel(ui, st)
    if not st or not ui then
        return
    end
    local g = mjelctrn_geom()
    -- 更新点击热区（与是否走贴图缓存无关）
    mjelctrn_pool_hits = {}
    local pool = st.pool or {}
    local rows = st.pool_rows or g.pool_rows
    local per = g.pool_row_n
    for r = 0, rows - 1 do
        for i = 1, per do
            local t = pool[r * per + i]
            if t then
                local x0 = g.x0 + (i - 1) * (g.ptw + g.pgap)
                local y = g.pool_y0 + r * (g.pth + g.pool_row_pad)
                mjelctrn_pool_hits[#mjelctrn_pool_hits + 1] = {
                    x0 = x0,
                    y0 = y,
                    x1 = x0 + g.ptw,
                    y1 = y + g.pth,
                    raw = t.raw and (t.raw & 0xFF) or 0,
                }
            end
        end
    end

    if panel_cache.enabled and emu.bitmap_argb32 and manager and manager.machine then
        local sig = "mj|" .. mjelctrn_panel_sig(st, g)
        if sig ~= panel_cache.sig then
            local ok = pcall(rebuild_mjelctrn_panel_cache, manager.machine, st, g)
            if ok and panel_cache.tex then
                panel_cache.sig = sig
            else
                panel_cache.enabled = false
                panel_cache.sig = ""
            end
        end
        if panel_cache.enabled and panel_cache.tex then
            local drew = false
            pcall(function()
                ui:draw_quad(panel_cache.tex, g.gx0, g.gy0, g.gx1, g.gy1, 0xffffffff)
                drew = true
            end)
            if drew then
                draw_mjelctrn_labels(ui, st, g)
                draw_mjelctrn_counts(ui, st, g)
                return
            end
        end
    end

    -- 回退：逐牌 draw（慢）
    ui:draw_box(g.gx0, g.gy0, g.gx1, g.gy1, 0x00000000, 0xC0101420)
    draw_mjelctrn_labels(ui, st, g)
    draw_row(
        ui, g.x0, g.cpu_y, g.tw, g.th, g.gap,
        st.queue, g.row_n, st.queue_hi_first, st.queue_dim_after
    )
    for r = 0, rows - 1 do
        local slice = {}
        local i0 = r * per
        for i = 1, per do
            local t = pool[i0 + i]
            if t then
                slice[#slice + 1] = t
            end
        end
        if #slice > 0 then
            local y = g.pool_y0 + r * (g.pth + g.pool_row_pad)
            draw_row(ui, g.x0, y, g.ptw, g.pth, g.pgap, slice, per, false, 99)
        end
    end
end

-- ui_container 0–1 → 牌池格 BCD（与绘制同空间；勿用 view_to_screen）
local function hit_mjelctrn_pool(nx, ny, pool)
    if not nx or not ny then
        return nil
    end
    if #mjelctrn_pool_hits > 0 then
        for _, h in ipairs(mjelctrn_pool_hits) do
            if nx >= h.x0 and nx <= h.x1 and ny >= h.y0 and ny <= h.y1 and h.raw ~= 0 then
                return h.raw
            end
        end
        return nil
    end
    if not pool or #pool == 0 then
        return nil
    end
    local g = mjelctrn_geom()
    local rows = 2
    local per = g.pool_row_n
    local tw, th, gap = g.ptw, g.pth, g.pgap
    for r = 0, rows - 1 do
        local y0 = g.pool_y0 + r * (th + g.pool_row_pad)
        local y1 = y0 + th
        if ny >= y0 and ny <= y1 then
            for i = 1, per do
                local t = pool[r * per + i]
                if t and t.raw and t.raw ~= 0 then
                    local x0 = g.x0 + (i - 1) * (tw + gap)
                    local x1 = x0 + tw
                    if nx >= x0 and nx <= x1 then
                        return t.raw & 0xFF
                    end
                end
            end
        end
    end
    return nil
end

local function hit_toggle(_nx, _ny)
    return false
end

return {
    art_key = art_key,
    art_key_bcd = art_key_bcd,
    art_key_for = art_key_for,
    art_dir = ART_DIR,
    toggle = MARK,
    ensure_art = load_textures,
    invalidate_panel_cache = function()
        free_panel_texture()
        panel_cache.sig = ""
        panel_cache.enabled = true
    end,
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
    hit_mjelctrn_pool = hit_mjelctrn_pool,
    mark_btn = MARK,
    mark_rect = mark_target_rect,
    mark_target_rect = mark_target_rect,
    game_container = game_container,
    view_to_screen = view_to_screen,
    view_to_ui01 = view_to_ui01,
    hit_mark = function(nx, ny)
        local m = current_mark()
        return nx and ny
            and nx >= m.x0 and nx <= m.x1
            and ny >= m.y0 and ny <= m.y1
    end,
    draw_tile = draw_tile,
    draw_row = draw_row,
    draw_panel = draw_panel,
    draw_mjelctrn_panel = draw_mjelctrn_panel,
    draw_toggle = draw_toggle,
    row_n = ROW_N,
    is_landscape = is_landscape,
}
