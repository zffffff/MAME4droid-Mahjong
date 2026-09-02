-- mjelctrn（电子基盘）透视 Phase 2/3：牌图面板 + 皮肤钮 + 内存 hunt
-- 知识库：仓库根目录 电子基盘透视知识.md（含 MAME 默认键避让表）
--
-- ★ 热键一律用「右 Ctrl」：左 Ctrl = 本机杠牌（KEY0），会抢键/污染操作
-- F9 / 右Ctrl+9 / 皮肤 btn_peek  开/关牌图透视（画 ui_container，勿用 :screen）
-- 皮肤 btn_pause  暂停/继续（不绑麻将键；MAME 暂停默认是 F5）
-- 右Ctrl+5/2/…  Phase 1 hunt（见 电子基盘透视知识.md）
--   右Ctrl+5/2/4 记录时自动 emu.pause()；按 F5 继续（电脑不等玩家）
-- 右Ctrl+2 另写 [draw-slot]：用手数 multiset 推断刚摸，对照 @7502/@712D（摸牌验证）
-- 右Ctrl+6  dump 当前 bank 下 A24D/A215/AA5E 等（追摸牌生成/过滤；冷启动 bank 无效）
-- 右Ctrl+7  控摸：切换目标牌（万/筒/索/字循环）
-- 右Ctrl+8  控摸：开/关（开=整池填目标；摸入手数+1后自动关并恢复备份）
--         听牌被拒时：跳过「归还池+重抽」(A274 call AA5E / A277 jr)，改 jr A279 接受
-- 右Ctrl+0  一键三元：武装 @7CB0 并装弹白/发/中×3（官方表），弹出换牌 UI
-- 右Ctrl+-  / 皮肤 btn_bleed  下一局配牌出血：写 @7CC1=0（押注界面开局兑现）
-- 皮肤 btn_accept  听牌可胡：A260 读拦截；关/复位清零 @7424
-- F8      三元换牌监视开/关（注意：MAME 默认 F8=减跳帧，可能需在 UI 里改绑）
-- F9 牌池：34 种常显（0 张半透明）；点牌图 = 控摸下一张；角标=真实剩余
--         （注意：MAME 默认 F9=加跳帧；本仓沿用 F9 透视，冲突时改 UI 键）

local LOG_PATH = "smoke_logs/mjelctrn_wall.log"

local MJELCTRN_FAMILY = {
    mjelctrn = true,
    mjembase = true,
    mjelct3 = true,
    mjelct3a = true,
    mjelct3b = true,
    mjelct3bi = true,
    mjelct3bia = true,
    mjelct3bib = true,
    mjelctrb = true,
    qyjdzjp = true,
}

local RANGES = {
    { tag = ":maincpu", space = "program", start = 0x6000, size = 0x1000, name = "z80_work" },
    { tag = ":maincpu", space = "program", start = 0x7000, size = 0x1000, name = "z80_nvram" },
    { tag = ":maincpu", space = "program", start = 0x8000, size = 0x8000, name = "z80_bank_win" },
}

-- ROT180 Cocktail：HUD 画 ui_container 窗口行，不画 :screen
local HAND_ADDR = 0x7120
local HAND_SORTED = 13 -- 画面手牌 13 张；@7120 第 14 字节是台面缓冲不是排序手
local HAND_STAGING_OFF = 13 -- @7120+13 = 0x712D
local CPU_HAND_ADDR = 0x7240
-- 吃碰杠时 @7240 常被清空；镜像里往往仍有剩余手（按长度优先）
local CPU_HAND_FALLBACKS = { 0x7240, 0x77C0, 0x7610, 0x7630, 0x7100 }
-- 勿用 @72C0：那是玩家手镜像；@7240 空时回退到它会把「电脑手」显示成玩家手
local TABLE_TILE_ADDR = 0x7502 -- 台面最近牌（含电脑刚打、玩家刚摸），勿标「刚摸」
local WALL_POOL_ADDR = 0x7000 -- A875 牌池：非零=剩余 BCD，00=已取走
local WALL_POOL_LEN = 0xE0 -- 至约 @70DF（含字牌区）
-- 听牌可胡：每帧写 @7424=$50 会卡 B001 入口；仅 A260 读拦截
-- 控摸：仅填牌池 @7000，勿改 bank 窗 ROM
local draw_code = {
    reject_addr = 0xA274,
    reject_len = 5,
    reject_orig = { 0xCD, 0x5E, 0xAA, 0x18, 0xD1 },
    reject_bypass = { 0x18, 0x03, 0x00, 0x00, 0x00 },
}
local CPU_HAND_MAX = 13
local CPU_DISCARD_ADDR = 0x7200 -- 电脑河牌 append 序列（实机 2026-08-27 确认）
local PLAYER_DISCARD_ADDR = 0x7280 -- 玩家河牌 append 序列（实机 2026-08-27 确认）
local DISCARD_HIST_MAX = 40

local SHOW_DEBUG_HUD = false
local peek_open = false
local peek_click = false
local sangen_click = false
local accept_click = false
local peek_state = nil
local pool_click_bcd = nil
local cpu_hand_cache = { raw = {}, src = nil } -- @7240 清空时的软缓存
local last_player_draw = nil -- BCD or nil
local last_cpu_draw = nil
local draw_track_prev = nil
local cpu_hand_src_addr = nil
local hooked_views = {}
local pause_poll_hooked = false
-- 指针边沿用全局 down；只绑一个 view，避免 ui_target+targets 各吃一次点击
local ptr_any_down = false
local ptr_bound_view = nil
local last_peek_toggle_tick = 0
local last_peek_draw_frame = -1
local ptr_lock_until = 0
local ptr_lock_frames = 0
local hook_tick = 0
local last_session_sec = nil
local boot_grace = 300 -- 开机/复位空转；DIP 重启后约 5s 内不挂钩/不读重活
local tiles_ui = nil
-- 供 mjelctrn.lua 灯控跳过 screen:pixel（复位后读屏易卡死）
_G.__fei_mjelctrn_boot_grace = boot_grace
-- 列表再开会 loadfile：禁止接管旧 view；pointer 进程内只绑一次（见 hook）
do
    local reloaded = _G.__fei_mjelctrn_wall_ever_loaded == true
    _G.__fei_mjelctrn_wall_ever_loaded = true
    if reloaded then
        boot_grace = 300
        _G.__fei_mjelctrn_boot_grace = boot_grace
        ptr_bound_view = nil
    end
end
pcall(function()
    local loader = loadfile("fei_mj_lamps/ui_tiles.lua")
    tiles_ui = loader and loader() or nil
end)
local snap_baseline = nil
local snap_prev = nil
local snap_exchange = nil
local step_idx = 0
local logged_map = false
local HUNT_AUTO_PAUSE = true

local function pause_for_hunt()
    if not HUNT_AUTO_PAUSE then
        return false
    end
    local ok, paused = pcall(function()
        if manager.machine and not manager.machine.paused then
            emu.pause()
            return true
        end
        return false
    end)
    return ok and paused
end

local NVRAM_BASE = 0x7000
local NVRAM_HOT0 = 0x7100 - NVRAM_BASE -- buf off 0x100
local NVRAM_HOT1 = 0x7800 - NVRAM_BASE -- buf off 0x800
local BANK_DUMP_MAX_LINES = 96
local HUNT_FOCUS0 = 0x7300
local HUNT_FOCUS_LEN = 64
local HUNT_CLUSTER0 = 0x730E
local HUNT_CLUSTER_LEN = 6
local HUNT_CLUSTER_ROUTES = { 0x730E, 0x732E, 0x734E, 0x736E }
local hunt_unknown_stats = {}

-- 三元换牌：F8 监视；Ctrl+0 一键武装（D9F1 门控 + D9EB 表白/发/中）
local SANGEN_FLAG_ADDR = 0x7423 -- 画面中曾见 00→50，换完→00；与摸牌过滤用的 @7424 同族
local SANGEN_FLAG2_ADDR = 0x7428
local SANGEN_MIRROR_ADDR = 0x72CA -- #1→#2 写入 37 37 37
-- 其余三元地址进表，避免主 chunk local 超过 Lua 200 上限（超限则整文件 load 失败）
local SANGEN = {
    enable = 0x7CB0,
    timer = 0x7CB4,
    skip = 0x7CB6,
    queue = 0x7CB7,
    gate = 0x72A1, -- bit4=1 则 D9F1 跳过
    table = { 0x35, 0x36, 0x37 }, -- ROM $D9EB：白、发、中
}
-- 配牌出血：押注界面 @7CC1=0 → 开局 45E8 走 4605→4628 写 @7CC0=01（动画+计时）
-- 已在窗口内（@7CC0≠0）再写只续会话，不重播开场。合表免占额外 local function。
local bleed = {
    pending = 0x7CC1,
    session = 0x7CC0,
    click = false,
    press_frames = 0,
}
-- 皮肤钮 layout 像素回退（item.bounds 失败时）；横 1600×900 / 竖 1000×1640
local SKIN_HIT = {
    peek = { lx0 = 1400, ly0 = 10, lx1 = 1542, ly1 = 125, px0 = 3, py0 = 1110, px1 = 145, py1 = 1240 },
    pause = { lx0 = 1400, ly0 = 130, lx1 = 1542, ly1 = 245, px0 = 855, py0 = 1110, px1 = 997, py1 = 1240 },
    sangen = { lx0 = 58, ly0 = 10, lx1 = 200, ly1 = 125, px0 = 287, py0 = 980, px1 = 429, py1 = 1110 },
    accept = { lx0 = 58, ly0 = 130, lx1 = 200, ly1 = 245, px0 = 429, py0 = 980, px1 = 571, py1 = 1110 },
    bleed = { lx0 = 58, ly0 = 250, lx1 = 200, ly1 = 365, px0 = 571, py0 = 980, px1 = 713, py1 = 1110 },
}
local sangen_watch = {
    on = false,
    prev_flag = nil,
    prev_flag2 = nil,
    prev_m3 = nil, -- 3 bytes at @72CA
    cool = 0,
    saw_ui50 = false, -- 已报过进 $50，避免 AFFD 反复写 $50 刷屏
    saw_commit = false, -- 已报过字牌×3 换入
}

-- hunt diff 时可忽略（镜像/河/手/台面/影子/常见噪声）
local KNOWN_HUNT_RANGES = {
    { 0x7100, 0x715F },
    { 0x7200, 0x72DF },
    { 0x7500, 0x751F },
    { 0x7610, 0x764F },
    { 0x77B0, 0x77DF },
}
local WALL_SCAN_LENS = { 70, 84, 90, 108, 136 }

-- 热键 seq 全部进表：Lua 主函数最多 200 个 local，散装 seq* 会撑爆导致 loadfile 失败
local keys = {
    input = nil,
    bound_machine = nil,
    need_rebind = true, -- DIP/F3 后旧 seq 失效；seq_pressed 会 ACCESS VIOLATION
    last_code_dump_draw = nil,
    prev = { false, false, false, false, false, false, false, false, false, false, false, false, false },
    seq5 = nil,
    seq1 = nil,
    seq2 = nil,
    seq3 = nil,
    seq4 = nil,
    seq6 = nil,
    seq7 = nil,
    seq8 = nil,
    seq9 = nil,
    seq0 = nil,
    seq_minus = nil, -- 右Ctrl+- 配牌出血
    seq_f9 = nil,
    seq_f8 = nil,
}

local FORCE_TILES = {}
do
    for i = 1, 9 do
        FORCE_TILES[#FORCE_TILES + 1] = i
    end
    for i = 0x11, 0x19 do
        FORCE_TILES[#FORCE_TILES + 1] = i
    end
    for i = 0x21, 0x29 do
        FORCE_TILES[#FORCE_TILES + 1] = i
    end
    for _, v in ipairs({ 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37 }) do
        FORCE_TILES[#FORCE_TILES + 1] = v
    end
end
local force_draw = {
    armed = false,
    tile_i = 5, -- 默认 五万
    backup = nil,
    sticky_backup = nil, -- 首次开控摸时的真牌池；换种/bank 闪断不得覆盖
    armed_pl_n = nil,
    tick = 0,
}
local listen_accept = {
    on = false,
    tap = nil,
    cpu = nil,
    addr = 0x7424,
    aux = 0x7427,
    accept = 0x50,
    pc_lo = 0xA260,
    pc_hi = 0xA266,
}

local HONOR_NAMES = {
    [0x31] = "东",
    [0x32] = "南",
    [0x33] = "西",
    [0x34] = "北",
    [0x35] = "白",
    [0x36] = "发",
    [0x37] = "中",
}

local BCD_TILE = {}
for i = 1, 9 do
    BCD_TILE[i] = true
    BCD_TILE[0x10 + i] = true
    BCD_TILE[0x20 + i] = true
end
for i = 0x31, 0x37 do
    BCD_TILE[i] = true
end

local function now()
    return os.date("%H:%M:%S")
end

local function is_family(name)
    return name and MJELCTRN_FAMILY[name] == true
end

local function write_log(text, mode)
    local f = io.open(LOG_PATH, mode or "a")
    if not f then
        f = io.open("mjelctrn_wall.log", mode or "a")
    end
    if not f then
        print("[mjelctrn_wall] cannot open log")
        return
    end
    f:write(text)
    if text:sub(-1) ~= "\n" then
        f:write("\n")
    end
    f:close()
end

local function write_bin(path, data)
    local f = io.open(path, "wb")
    if f then
        f:write(data)
        f:close()
    end
end

local mem = {}
function mem.read_u8(machine, addr)
    local cpu = machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space then
        return nil
    end
    local ok, v = pcall(function()
        return space:read_u8(addr)
    end)
    if ok then
        return v & 0xFF
    end
    return nil
end

function mem.write_u8(machine, addr, val)
    local cpu = machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space or not space.write_u8 then
        return false
    end
    local ok = pcall(function()
        space:write_u8(addr, val & 0xFF)
    end)
    return ok and true or false
end

function mem.bytes_eq(machine, addr, expect)
    for i = 1, #expect do
        local v = mem.read_u8(machine, addr + i - 1)
        if v ~= expect[i] then
            return false
        end
    end
    return true
end

function listen_accept.clear_ram(machine)
    if not machine then
        return
    end
    mem.write_u8(machine, listen_accept.addr, 0)
    mem.write_u8(machine, listen_accept.aux, 0)
end

function listen_accept.pc_ok(cpu)
    if not cpu or not cpu.state then
        return false
    end
    local pc = nil
    pcall(function()
        local r = cpu.state["PC"]
        if r then
            pc = r.value
        end
    end)
    return pc and pc >= listen_accept.pc_lo and pc <= listen_accept.pc_hi
end

function listen_accept.tap_rm()
    if listen_accept.tap then
        pcall(function()
            listen_accept.tap:remove()
        end)
        listen_accept.tap = nil
    end
    listen_accept.cpu = nil
end

function listen_accept.tap_install(machine)
    listen_accept.tap_rm()
    local cpu = machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space or not space.install_read_tap then
        return false
    end
    listen_accept.cpu = cpu
    local ok, tap = pcall(function()
        return space:install_read_tap(
            listen_accept.addr,
            listen_accept.addr,
            "fei_listen7424",
            function(_offset, _data, _mask)
                if listen_accept.on and listen_accept.pc_ok(listen_accept.cpu) then
                    return listen_accept.accept
                end
            end
        )
    end)
    if ok and tap then
        listen_accept.tap = tap
        return true
    end
    listen_accept.cpu = nil
    return false
end

function force_draw.target_bcd()
    return FORCE_TILES[force_draw.tile_i] or 0x05
end

function force_draw.backup_pool(machine)
    local t = {}
    for i = 0, WALL_POOL_LEN - 1 do
        t[i + 1] = mem.read_u8(machine, WALL_POOL_ADDR + i) or 0
    end
    return t
end

function force_draw.restore_pool(machine, backup)
    if not backup then
        return
    end
    for i = 0, WALL_POOL_LEN - 1 do
        mem.write_u8(machine, WALL_POOL_ADDR + i, backup[i + 1] or 0)
    end
end

function force_draw.fill_pool(machine, bcd)
    for i = 0, WALL_POOL_LEN - 1 do
        mem.write_u8(machine, WALL_POOL_ADDR + i, bcd)
    end
end

function force_draw.clear_armed()
    force_draw.armed = false
    force_draw.backup = nil
    force_draw.armed_pl_n = nil
    force_draw.tick = 0
end

function force_draw.clear_session()
    force_draw.clear_armed()
    force_draw.sticky_backup = nil
end

function listen_accept.toggle(machine)
    if listen_accept.on then
        listen_accept.on = false
        listen_accept.tap_rm()
        listen_accept.clear_ram(machine)
        machine:popmessage("听牌可胡关 · 已清 @7424")
        write_log(
            string.format(
                "=== [listen-accept] OFF %s verify7424=%02X ===\n",
                now(),
                mem.read_u8(machine, listen_accept.addr) or 0
            ),
            "a"
        )
        return
    end
    listen_accept.on = true
    listen_accept.clear_ram(machine)
    local tap_ok = listen_accept.tap_install(machine)
    write_log(
        string.format(
            "=== [listen-accept] ON tapA260+%s 7424=%02X %s ===\n",
            tap_ok and "Y" or "N",
            mem.read_u8(machine, listen_accept.addr) or 0,
            now()
        ),
        "a"
    )
    if not tap_ok then
        listen_accept.on = false
        machine:popmessage("听牌可胡失败：无法装读拦截")
        return
    end
    machine:popmessage("听牌可胡开\n按下=下一摸放行")
end

-- 控摸写 A274 前必须确认 bank（仅 code-dump 参考）
local function draw_code_bank_ok(machine)
    -- 玩家摸写台面：A24D ld ($7502),a = 32 02 75
    if not mem.bytes_eq(machine, 0xA24D, { 0x32, 0x02, 0x75 }) then
        return false
    end
    if mem.bytes_eq(machine, draw_code.reject_addr, draw_code.reject_orig) then
        return true
    end
    if mem.bytes_eq(machine, draw_code.reject_addr, draw_code.reject_bypass) then
        return true
    end
    return false
end

local function dump_code_bytes(machine, addr, len)
    local t = {}
    for i = 0, len - 1 do
        local v = mem.read_u8(machine, addr + i)
        t[#t + 1] = v and string.format("%02X", v) or "??"
    end
    return table.concat(t, " ")
end

-- Z80: ld ($7502),a = 32 02 75
local function find_ld_7502_a(machine, start_addr, span)
    local hits = {}
    for off = 0, span - 3 do
        local b0 = mem.read_u8(machine, start_addr + off)
        local b1 = mem.read_u8(machine, start_addr + off + 1)
        local b2 = mem.read_u8(machine, start_addr + off + 2)
        if b0 == 0x32 and b1 == 0x02 and b2 == 0x75 then
            hits[#hits + 1] = start_addr + off
            if #hits >= 12 then
                break
            end
        end
    end
    return hits
end

local function dump_draw_code_context(machine, reason)
    reason = reason or "manual"
    local windows = {
        { "player_draw_A24D", 0xA230, 80 },
        { "cpu_draw_A215", 0xA1F0, 80 },
        { "pool_return_AA5E", 0xAA5E, 96 },
        { "filter_B001", 0xB001, 80 },
        { "filter_B3A6", 0xB3A6, 96 },
        { "filter_400A", 0x400A, 64 },
        { "gen_A86B", 0xA86B, 48 },
        { "player_discard_8C6E", 0x8C50, 48 },
        { "cpu_discard_9168", 0x9140, 48 },
    }
    local lines = {
        string.format("=== [code-dump] %s %s rom=%s ===\n", reason, now(), machine.system.name),
        "  note: Axxx/Bxxx 在 bank 窗；须在对局里 dump（冷启动反汇编无效）\n",
        "  过滤链: B001 → ($7424==$50?) → B3A6(Z?) → 400A(NC?) → 否则 AA5E归还+重抽\n",
        "  expect A24D: 32 02 75 | A274 原版 CD 5E AA 18 D1 | 控摸旁路 18 03 00 00 00\n",
    }
    for _, w in ipairs(windows) do
        lines[#lines + 1] = string.format(
            "  %s @%04X+%d:\n    %s\n",
            w[1],
            w[2],
            w[3],
            dump_code_bytes(machine, w[2], w[3])
        )
    end
    do
        local hex = {}
        for i = 0, draw_code.reject_len - 1 do
            hex[#hex + 1] = string.format("%02X", mem.read_u8(machine, draw_code.reject_addr + i) or 0)
        end
        local h = table.concat(hex, " ")
        local note = " (非预期)"
        if h == "CD 5E AA 18 D1" then
            note = " (原版：归还+重抽)"
        elseif h == "18 03 00 00 00" then
            note = " (控摸旁路：jr A279)"
        end
        lines[#lines + 1] = "  A274.. bytes: " .. h .. note .. "\n"
    end
    local hits = find_ld_7502_a(machine, 0x8000, 0x8000)
    if #hits == 0 then
        lines[#lines + 1] = "  find ld($7502),a in 8000-FFFF: (none — bank 可能不对)\n"
    else
        local parts = {}
        for _, a in ipairs(hits) do
            parts[#parts + 1] = string.format("%04X", a)
        end
        lines[#lines + 1] = "  find ld($7502),a @ " .. table.concat(parts, " ") .. "\n"
    end
    write_log(table.concat(lines), "a")
    return #hits
end

local function tile_valid(v)
    if not v or v == 0 or v == 0xFF or v == 0xEE or v == 0xFD then
        return false
    end
    return BCD_TILE[v] == true
end

local function tile_name(v)
    if v >= 0x01 and v <= 0x09 then
        return string.format("%d万", v)
    end
    if v >= 0x11 and v <= 0x19 then
        return string.format("%d筒", v - 0x10)
    end
    if v >= 0x21 and v <= 0x29 then
        return string.format("%d条", v - 0x20)
    end
    if HONOR_NAMES[v] then
        return HONOR_NAMES[v]
    end
    return string.format("[%02X]", v)
end

local function read_player_hand(machine)
    local sorted_raw, staging_raw, all_raw = {}, nil, {}
    for i = 0, HAND_SORTED do
        local v = mem.read_u8(machine, HAND_ADDR + i)
        if not tile_valid(v) then
            break
        end
        all_raw[#all_raw + 1] = v
        if i < HAND_SORTED then
            sorted_raw[#sorted_raw + 1] = v
        else
            staging_raw = v
        end
    end
    return sorted_raw, staging_raw, all_raw
end

local function read_cpu_hand_at(machine, addr)
    local raws = {}
    for i = 0, CPU_HAND_MAX - 1 do
        local v = mem.read_u8(machine, addr + i)
        if not tile_valid(v) then
            break
        end
        raws[#raws + 1] = v
    end
    return raws
end

local function read_cpu_hand(machine)
    local best, best_addr = {}, nil
    for _, addr in ipairs(CPU_HAND_FALLBACKS) do
        local raws = read_cpu_hand_at(machine, addr)
        if #raws > #best then
            best, best_addr = raws, addr
        end
    end
    if #best > 0 then
        cpu_hand_cache = { raw = best, src = best_addr }
        cpu_hand_src_addr = best_addr
        return best, best_addr, false
    end
    if cpu_hand_cache.raw and #cpu_hand_cache.raw > 0 then
        cpu_hand_src_addr = cpu_hand_cache.src
        return cpu_hand_cache.raw, cpu_hand_cache.src, true
    end
    cpu_hand_src_addr = nil
    return {}, nil, false
end

local function multiset_of(raw_list)
    local m = {}
    for _, v in ipairs(raw_list or {}) do
        if tile_valid(v) then
            m[v] = (m[v] or 0) + 1
        end
    end
    return m
end

local function multiset_gains(old_m, new_m)
    local g = {}
    for v, n in pairs(new_m) do
        local d = n - (old_m[v] or 0)
        for _ = 1, d do
            g[#g + 1] = v
        end
    end
    return g
end

local function player_hand_list(live)
    -- 追踪/显示手数：只用 @7120..712C，不含 @712D（常被台面污染，会把电脑打误判成你摸）
    local list = {}
    for _, v in ipairs(live.sorted_raw or {}) do
        list[#list + 1] = v
    end
    return list
end

-- 帧间推断刚摸（每帧跑）。原则：
-- 玩家摸：仅当「你手数+1 且你河未变长」；绝不用裸 @7502 变化
-- 电脑摸：电脑河变长时看 @7240 增益；摸切则河末=摸；读不到手则不更新（避免把弃牌当摸）
local function update_draw_track(machine, live)
    local pl_list = player_hand_list(live)
    local pl = multiset_of(pl_list)
    local cpu7240 = read_cpu_hand_at(machine, CPU_HAND_ADDR)
    -- 追踪优先实读；@7240 空时用镜像（仍不要用「清空前缓存」，避免假增益）
    local cpu_raw = cpu7240
    if #cpu_raw == 0 then
        for _, addr in ipairs(CPU_HAND_FALLBACKS) do
            if addr ~= CPU_HAND_ADDR then
                local raws = read_cpu_hand_at(machine, addr)
                if #raws > #cpu_raw then
                    cpu_raw = raws
                end
            end
        end
    end
    local cpu = multiset_of(cpu_raw)
    local table_v = live.table_tile and live.table_tile.raw or nil
    local pl_rn = #(live.player_discard_raw or {})
    local cpu_rn = #(live.cpu_discard_raw or {})
    local n_pl = #pl_list
    local n_cpu = #cpu_raw

    if not draw_track_prev then
        draw_track_prev = {
            pl = pl,
            cpu = cpu,
            table = table_v,
            pl_rn = pl_rn,
            cpu_rn = cpu_rn,
            n_pl = n_pl,
            n_cpu = n_cpu,
        }
        return
    end

    local prev = draw_track_prev
    local pl_gains = multiset_gains(prev.pl, pl)
    local cpu_gains = multiset_gains(prev.cpu, cpu)
    local pl_river_grew = pl_rn > (prev.pl_rn or 0)
    local cpu_river_grew = cpu_rn > (prev.cpu_rn or 0)

    -- 玩家摸：手数增加且本帧你没打牌进河
    if n_pl > (prev.n_pl or 0) and not pl_river_grew and #pl_gains > 0 then
        local pick = nil
        for _, v in ipairs(pl_gains) do
            if table_v and v == table_v then
                pick = v
                break
            end
        end
        last_player_draw = pick or pl_gains[1]
        if last_player_draw ~= keys.last_code_dump_draw then
            keys.last_code_dump_draw = last_player_draw
            pcall(function()
                dump_draw_code_context(
                    machine,
                    string.format("auto_player_draw_%02X", last_player_draw)
                )
            end)
        end
    end

    -- 电脑摸：以电脑河变长为一巡结束信号
    if cpu_river_grew then
        local river_end = live.cpu_discard_raw[cpu_rn]
        if #cpu_gains > 0 then
            -- 摸≠打：增益=摸入；若增益里有与河末不同的优先那张
            local pick = nil
            for _, v in ipairs(cpu_gains) do
                if v ~= river_end then
                    pick = v
                    break
                end
            end
            last_cpu_draw = pick or cpu_gains[1]
        elseif n_cpu > 0 and (prev.n_cpu or 0) > 0 then
            -- 摸切：手 multiset 净零，摸=打=河末
            if tile_valid(river_end) then
                last_cpu_draw = river_end
            end
        end
        -- 若手完全读不到：不更新，避免 last_cpu_draw=弃牌
    elseif n_cpu > (prev.n_cpu or 0) and not cpu_river_grew and #cpu_gains > 0 then
        -- 尚可见「摸入未打」的一帧
        local pick = nil
        for _, v in ipairs(cpu_gains) do
            if table_v and v == table_v then
                pick = v
                break
            end
        end
        last_cpu_draw = pick or cpu_gains[1]
    end

    draw_track_prev = {
        pl = pl,
        cpu = cpu,
        table = table_v,
        pl_rn = pl_rn,
        cpu_rn = cpu_rn,
        n_pl = n_pl,
        n_cpu = n_cpu,
    }
end

local function read_discard_hist(machine, addr)
    local raw, names = {}, {}
    for i = 0, DISCARD_HIST_MAX - 1 do
        local v = mem.read_u8(machine, addr + i)
        if not tile_valid(v) then
            break
        end
        raw[#raw + 1] = v
        names[#names + 1] = tile_name(v)
    end
    return raw, names
end

local function bcd_tile_obj(v)
    return {
        raw = v,
        name = tile_name(v),
        enc = "bcd",
        empty = false,
    }
end

local function build_cpu_hand_tiles(cpu_raw)
    local tiles = {}
    for _, v in ipairs(cpu_raw) do
        tiles[#tiles + 1] = bcd_tile_obj(v)
    end
    return tiles
end

-- @7000 牌池：固定 34 种按钮格；角标=真实剩余（控摸中读 sticky/backup，不被整池填充污染）
local function wall_pool_counts(machine)
    local counts = {}
    local src = nil
    if force_draw.armed then
        src = force_draw.sticky_backup or force_draw.backup
    end
    if src then
        for _, v in ipairs(src) do
            if tile_valid(v) then
                counts[v] = (counts[v] or 0) + 1
            end
        end
    else
        for i = 0, WALL_POOL_LEN - 1 do
            local v = mem.read_u8(machine, WALL_POOL_ADDR + i)
            if tile_valid(v) then
                counts[v] = (counts[v] or 0) + 1
            end
        end
    end
    return counts
end

local function read_wall_pool(machine)
    local counts = wall_pool_counts(machine)
    local target = force_draw.armed and force_draw.target_bcd() or nil
    local tiles = {}
    local total = 0
    for _, v in ipairs(FORCE_TILES) do
        local n = counts[v] or 0
        total = total + n
        tiles[#tiles + 1] = {
            raw = v,
            name = tile_name(v),
            enc = "bcd",
            empty = false,
            count = n,
            dim = n == 0,
            force_hi = target ~= nil and v == target,
        }
    end
    return tiles, total
end

local function build_peek_state(machine, live)
    live = live or read_live_peek(machine)
    local cpu_hand = build_cpu_hand_tiles(live.cpu_raw)
    local pool_tiles, pool_n = read_wall_pool(machine)
    local line1_parts = {
        string.format("牌池剩 %d", pool_n),
    }
    if #cpu_hand > 0 then
        line1_parts[#line1_parts + 1] = string.format("电脑 %d", #cpu_hand)
        if live.cpu_from_cache then
            line1_parts[#line1_parts + 1] = "副露中"
        end
    end
    if live.table_tile then
        line1_parts[#line1_parts + 1] = "台面 " .. live.table_tile.name
    end
    do
        local tb = force_draw.target_bcd()
        if force_draw.armed then
            line1_parts[#line1_parts + 1] = "控摸→" .. tile_name(tb)
        else
            line1_parts[#line1_parts + 1] = "点牌控摸"
        end
    end
    local cpu_label = string.format("电脑手 (%d)", #cpu_hand)
    if #cpu_hand == 0 then
        cpu_label = "电脑手（副露中/暂无）"
    elseif live.cpu_from_cache then
        cpu_label = cpu_label .. " · 副露中"
    end
    return {
        title = "电子基盘 透视",
        line1 = table.concat(line1_parts, "  ·  "),
        queue_label = cpu_label,
        queue = cpu_hand,
        queue_hi_first = false,
        queue_dim_after = 99,
        pool_label = string.format("牌池 · 剩 %d 张 · 点选控摸", pool_n),
        pool = pool_tiles,
        pool_rows = 2,
        note1 = "点牌图 = 下一摸强制该种 · 再点同种取消",
        note2 = "听牌可控摸 · 右Ctrl+8 关并恢复牌池 · F9 关透视",
    }
end

local function read_live_peek(machine)
    local sorted_raw, staging_raw = read_player_hand(machine)
    local hand = {}
    for _, v in ipairs(sorted_raw) do
        hand[#hand + 1] = tile_name(v)
    end
    local table_v = mem.read_u8(machine, TABLE_TILE_ADDR)
    local table_tile
    if tile_valid(table_v) then
        table_tile = { name = tile_name(table_v), raw = table_v }
    end
    local cpu_raw, cpu_src, cpu_from_cache = read_cpu_hand(machine)
    local cpu_discard_raw, cpu_discard_names = read_discard_hist(machine, CPU_DISCARD_ADDR)
    local player_discard_raw, player_discard_names = read_discard_hist(machine, PLAYER_DISCARD_ADDR)
    return {
        hand = hand,
        sorted_raw = sorted_raw,
        staging_raw = staging_raw,
        table_tile = table_tile,
        cpu_raw = cpu_raw,
        cpu_src = cpu_src,
        cpu_from_cache = cpu_from_cache,
        cpu_discard_raw = cpu_discard_raw,
        cpu_discard_names = cpu_discard_names,
        player_discard_raw = player_discard_raw,
        player_discard_names = player_discard_names,
    }
end

local function player_hand_len(machine)
    local n = 0
    for i = 0, HAND_SORTED do
        local v = mem.read_u8(machine, HAND_ADDR + i)
        if not tile_valid(v) then
            break
        end
        n = n + 1
    end
    return n
end

function force_draw.backup_looks_forced(backup)
    if not backup or #backup < 8 then
        return false
    end
    local first = nil
    local n = 0
    for _, v in ipairs(backup) do
        if tile_valid(v) then
            n = n + 1
            if not first then
                first = v
            elseif v ~= first then
                return false
            end
        end
    end
    return n >= 8 and first ~= nil
end

function force_draw.arm(machine)
    local bcd = force_draw.target_bcd()
    if not force_draw.sticky_backup then
        local snap = force_draw.backup_pool(machine)
        if force_draw.backup_looks_forced(snap) then
            machine:popmessage(
                "牌池已是控摸态且无真备份\n无法还原多样性 · 请结束本局再开控摸"
            )
        end
        force_draw.sticky_backup = snap
    end
    force_draw.backup = force_draw.sticky_backup
    force_draw.armed = true
    force_draw.tick = 0
    local live = read_live_peek(machine)
    force_draw.armed_pl_n = player_hand_len(machine)
    if force_draw.armed_pl_n < 1 then
        force_draw.armed_pl_n = #(live.sorted_raw or {})
    end
    force_draw.fill_pool(machine, bcd)
    write_log(
        string.format(
            "=== [force-draw] ARM %s (%02X) pool-only %s ===\n",
            tile_name(bcd),
            bcd,
            now()
        ),
        "a"
    )
    machine:popmessage(
        string.format(
            "控摸开 → 下一摸强制 %s\n摸完/右Ctrl+8/再点同种 关",
            tile_name(bcd)
        )
    )
end

function force_draw.disarm(machine, reason)
    reason = reason or "manual"
    local bak = force_draw.sticky_backup or force_draw.backup
    if not force_draw.armed and not bak then
        return false
    end
    if bak then
        pcall(function()
            force_draw.restore_pool(machine, bak)
        end)
    end
    local forced_bak = force_draw.backup_looks_forced(bak)
    force_draw.clear_armed()
    write_log(
        string.format("=== [force-draw] DISARM (%s) %s ===\n", reason, now()),
        "a"
    )
    if not bak then
        machine:popmessage("控摸关 · 无牌池备份可恢复")
    elseif forced_bak then
        machine:popmessage("控摸关 · 备份已是污染池\n本局牌池多样性无法还原")
    else
        machine:popmessage("控摸关 · 牌池已恢复")
    end
    return true
end

function force_draw.run_tick(machine)
    if not force_draw.armed then
        return
    end
    force_draw.tick = (force_draw.tick or 0) + 1
    if (force_draw.tick % 8) == 1 then
        force_draw.fill_pool(machine, force_draw.target_bcd())
    end
    local n = player_hand_len(machine)
    local base = force_draw.armed_pl_n or n
    if n > base then
        local bcd = force_draw.target_bcd()
        local name = tile_name(bcd)
        force_draw.disarm(machine, string.format("player_hand_%d_to_%d", base, n))
        machine:popmessage(
            string.format("控摸：已摸入（手 %d→%d）\n目标曾为 %s", base, n, name)
        )
    end
end

function force_draw.index_of(bcd)
    bcd = bcd and (bcd & 0xFF)
    for i, v in ipairs(FORCE_TILES) do
        if v == bcd then
            return i
        end
    end
    return nil
end

function force_draw.select(machine, bcd)
    local idx = force_draw.index_of(bcd)
    if not idx then
        return
    end
    bcd = FORCE_TILES[idx]
    if force_draw.armed and force_draw.target_bcd() == bcd then
        force_draw.disarm(machine, "click_same")
        return
    end
    force_draw.tile_i = idx
    if force_draw.armed then
        force_draw.fill_pool(machine, bcd)
        write_log(
            string.format("=== [force-draw] RETARGET %s (%02X) %s ===\n", tile_name(bcd), bcd, now()),
            "a"
        )
        machine:popmessage(
            string.format("控摸改 → %s\n摸完自动关 | 再点同种取消", tile_name(bcd))
        )
        return
    end
    force_draw.arm(machine)
end

local function hand_bytes_hex(machine)
    local t = {}
    for i = 0, HAND_SORTED do
        local v = mem.read_u8(machine, HAND_ADDR + i)
        t[#t + 1] = v and string.format("%02X", v) or "??"
    end
    return table.concat(t, " ")
end

local function focus7300_hex(machine)
    local t = {}
    for i = 0, HUNT_FOCUS_LEN - 1 do
        local v = mem.read_u8(machine, HUNT_FOCUS0 + i)
        t[#t + 1] = v and string.format("%02X", v) or "??"
    end
    return table.concat(t, " ")
end

local function cluster6_hex(machine)
    local t = {}
    for i = 0, HUNT_CLUSTER_LEN - 1 do
        local v = mem.read_u8(machine, HUNT_CLUSTER0 + i)
        t[#t + 1] = v and string.format("%02X", v) or "??"
    end
    return table.concat(t, " ")
end

local function cluster_routes_hex(machine)
    local parts = {}
    for _, addr in ipairs(HUNT_CLUSTER_ROUTES) do
        local a = mem.read_u8(machine, addr)
        local b = mem.read_u8(machine, addr + 1)
        parts[#parts + 1] = string.format(
            "@%04X=%s %s",
            addr,
            a and string.format("%02X", a) or "??",
            b and string.format("%02X", b) or "??"
        )
    end
    return table.concat(parts, " | ")
end

local function hex3(machine, addr)
    local a = mem.read_u8(machine, addr) or 0
    local b = mem.read_u8(machine, addr + 1) or 0
    local c = mem.read_u8(machine, addr + 2) or 0
    return string.format("%02X %02X %02X", a, b, c), a, b, c
end

-- 一键弹出官方三元换牌 UI（不选手动换入种；队列按 $D9EB 白/发/中随机×3）
local function sangen_arm_ui(machine)
    local tab = SANGEN.table
    local tile = tab[math.random(1, #tab)]
    local q = SANGEN.queue
    -- 清队列 8 字节（对齐 D998 入口），再装同种×3
    for i = 0, 7 do
        mem.write_u8(machine, q + i, 0)
    end
    mem.write_u8(machine, q, tile)
    mem.write_u8(machine, q + 1, tile)
    mem.write_u8(machine, q + 2, tile)
    mem.write_u8(machine, SANGEN.enable, 1)
    mem.write_u8(machine, SANGEN.skip, 0)
    mem.write_u8(machine, SANGEN.timer, 1)
    local gate = mem.read_u8(machine, SANGEN.gate) or 0
    mem.write_u8(machine, SANGEN.gate, gate & 0xEF) -- 清 @72A1 bit4
    local name = tile_name(tile)
    write_log(
        string.format(
            "[sangen-arm] %s queue=%s×3 @7CB0=1 @7CB4=1 @7CB6=0 @72A1&=EF\n",
            now(),
            name
        ),
        "a"
    )
    machine:popmessage(
        string.format(
            "三元换牌已武装 → 换入 %s×3\n选 3 张换出 | 勿连续触发叠同种\n(热键=右Ctrl+0)",
            name
        )
    )
    return true
end

function bleed.arm(machine)
    if not machine then
        return false
    end
    local prev = mem.read_u8(machine, bleed.pending) or 0
    local sess = mem.read_u8(machine, bleed.session) or 0
    mem.write_u8(machine, bleed.pending, 0)
    bleed.press_frames = 12
    write_log(
        string.format("[bleed-arm] %s @7CC1 %02X→00 @7CC0=%02X\n", now(), prev, sess),
        "a"
    )
    if sess ~= 0 then
        machine:popmessage(
            "已在出血窗口内：下一局续当前计时\n（不会重播开场动画）\n(皮肤钮 / 右Ctrl+-)"
        )
    else
        machine:popmessage(
            "下一局配牌出血已武装\n押注界面开局 → 动画+计时+BGM\n(皮肤钮 / 右Ctrl+-)"
        )
    end
    return true
end

local function dump_sangen_watch(machine, reason)
    local f = mem.read_u8(machine, SANGEN_FLAG_ADDR) or 0
    local f2 = mem.read_u8(machine, SANGEN_FLAG2_ADDR) or 0
    local f24 = mem.read_u8(machine, 0x7424) or 0
    local c0 = mem.read_u8(machine, HUNT_CLUSTER0) or 0
    local mhex, m0, m1, m2 = hex3(machine, SANGEN_MIRROR_ADDR)
    local lines = {
        string.format("=== [sangen-watch] %s %s ===\n", reason or "?", now()),
        string.format(
            "  @7423=%02X @7428=%02X @7424=%02X (摸牌过滤旁路字) @730E[0]=%02X\n",
            f,
            f2,
            f24,
            c0
        ),
        string.format("  @72CA.. = %s", mhex),
    }
    if tile_valid(m0) and m0 == m1 and m1 == m2 then
        lines[#lines + 1] = string.format("  (= %s×3)\n", tile_name(m0))
    else
        lines[#lines + 1] = "\n"
    end
    lines[#lines + 1] = "  手hex@7120: " .. hand_bytes_hex(machine) .. "\n"
    lines[#lines + 1] = "  cluster6@730E: " .. cluster6_hex(machine) .. "\n"
    local pool37 = 0
    for i = 0, WALL_POOL_LEN - 1 do
        if mem.read_u8(machine, WALL_POOL_ADDR + i) == 0x37 then
            pool37 = pool37 + 1
        end
    end
    lines[#lines + 1] = string.format("  池内红中计数 @7000: %d\n", pool37)
    write_log(table.concat(lines), "a")
end

local function sangen_watch_reset_prev()
    sangen_watch.prev_flag = nil
    sangen_watch.prev_flag2 = nil
    sangen_watch.prev_m3 = nil
    sangen_watch.cool = 0
    sangen_watch.saw_ui50 = false
    sangen_watch.saw_commit = false
end

-- 高信号 + 闩锁：AFFD 会反复写 $50，换完后仍可能刷
local function sangen_watch_tick(machine)
    if not sangen_watch.on then
        return
    end
    if sangen_watch.cool > 0 then
        sangen_watch.cool = sangen_watch.cool - 1
    end
    local f = mem.read_u8(machine, SANGEN_FLAG_ADDR) or 0
    local f2 = mem.read_u8(machine, SANGEN_FLAG2_ADDR) or 0
    local _, m0, m1, m2 = hex3(machine, SANGEN_MIRROR_ADDR)
    local mkey = string.format("%02X%02X%02X", m0 or 0, m1 or 0, m2 or 0)
    if sangen_watch.prev_flag == nil then
        sangen_watch.prev_flag = f
        sangen_watch.prev_flag2 = f2
        sangen_watch.prev_m3 = mkey
        return
    end
    local reasons = {}
    local prev_f = sangen_watch.prev_flag
    -- 仅 非50→50 报一次进 UI；50→00 报一次离开
    if f ~= prev_f then
        if f == 0x50 and prev_f ~= 0x50 and not sangen_watch.saw_ui50 then
            reasons[#reasons + 1] = string.format("@7423 %02X→50 (UI)", prev_f)
            sangen_watch.saw_ui50 = true
        elseif prev_f == 0x50 and f == 0x00 then
            reasons[#reasons + 1] = "@7423 50→00 (离UI)"
            sangen_watch.saw_ui50 = false
        end
    end
    if mkey ~= sangen_watch.prev_m3 and not sangen_watch.saw_commit then
        if tile_valid(m0) and m0 == m1 and m1 == m2 and m0 >= 0x31 and m0 <= 0x37 then
            reasons[#reasons + 1] = string.format("@72CA→%s×3", tile_name(m0))
            sangen_watch.saw_commit = true
        end
    end
    sangen_watch.prev_flag = f
    sangen_watch.prev_flag2 = f2
    sangen_watch.prev_m3 = mkey
    if #reasons == 0 or sangen_watch.cool > 0 then
        return
    end
    local why = table.concat(reasons, " | ")
    dump_sangen_watch(machine, why)
    sangen_watch.cool = 120
    pause_for_hunt()
    machine:popmessage("三元监视命中\n" .. why .. "\n已追加 log | F5 继续")
end

local function slice_bytes(data, base, addr, len)
    local off = addr - base + 1
    if off < 1 or off + len - 1 > #data then
        return nil
    end
    return data:sub(off, off + len - 1)
end

local function bytes_hex(data)
    local t = {}
    for i = 1, #data do
        t[#t + 1] = string.format("%02X", data:byte(i))
    end
    return table.concat(t, " ")
end

local function format_cluster730e_diff(a, b, base, label)
    local tag = label or "cluster@730E"
    local lines = {}
    local blk_a = slice_bytes(a, base, HUNT_CLUSTER0, HUNT_CLUSTER_LEN)
    local blk_b = slice_bytes(b, base, HUNT_CLUSTER0, HUNT_CLUSTER_LEN)
    if blk_a and blk_b and blk_a ~= blk_b then
        lines[#lines + 1] = string.format("[%s] 6-byte block @0x%04X changed\n  A %s\n  B %s\n", tag, HUNT_CLUSTER0, bytes_hex(blk_a), bytes_hex(blk_b))
    end
    local route_changes = {}
    for _, addr in ipairs(HUNT_CLUSTER_ROUTES) do
        local ra = slice_bytes(a, base, addr, 2)
        local rb = slice_bytes(b, base, addr, 2)
        if ra and rb and ra ~= rb then
            route_changes[#route_changes + 1] = string.format("  @%04X: %s -> %s\n", addr, bytes_hex(ra), bytes_hex(rb))
        end
    end
    if #route_changes > 0 then
        lines[#lines + 1] = string.format("[%s routes] %d pair(s) changed\n%s", tag, #route_changes, table.concat(route_changes))
    end
    if #lines == 0 then
        return ""
    end
    return table.concat(lines)
end

local function reset_hunt_unknown_stats()
    hunt_unknown_stats = {}
end

local function record_hunt_unknown_stats(runs)
    for _, r in ipairs(runs) do
        local e = hunt_unknown_stats[r.addr]
        if not e then
            e = { addr = r.addr, count = 0, max_len = 0 }
            hunt_unknown_stats[r.addr] = e
        end
        e.count = e.count + 1
        if r.len > e.max_len then
            e.max_len = r.len
        end
    end
end

local function format_hunt_unknown_tally(maxn)
    local list = {}
    for _, e in pairs(hunt_unknown_stats) do
        list[#list + 1] = e
    end
    if #list == 0 then
        return "[UNKNOWN tally] (empty)\n"
    end
    table.sort(list, function(x, y)
        if x.count ~= y.count then
            return x.count > y.count
        end
        return x.addr < y.addr
    end)
    local n = maxn or 12
    local t = { string.format("[UNKNOWN tally] %d addr(s), top %d:\n", #list, math.min(#list, n)) }
    for i = 1, math.min(#list, n) do
        local e = list[i]
        t[#t + 1] = string.format("  0x%06X  x%d  max_len=%d\n", e.addr, e.count, e.max_len)
    end
    return table.concat(t)
end

local function hand_multiset_line(live)
    local freq = {}
    local function add(v)
        if tile_valid(v) then
            local n = tile_name(v)
            freq[n] = (freq[n] or 0) + 1
        end
    end
    for _, v in ipairs(live.sorted_raw) do
        add(v)
    end
    if live.staging_raw then
        add(live.staging_raw)
    end
    local keys = {}
    for k in pairs(freq) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        if freq[k] > 1 then
            parts[#parts + 1] = string.format("%s×%d", k, freq[k])
        else
            parts[#parts + 1] = k
        end
    end
    if #parts == 0 then
        return nil
    end
    return "  手multiset(7120+712D): " .. table.concat(parts, " ")
end

local function table_contamination_lines(live)
    if not live.table_tile then
        return {}
    end
    local tv = live.table_tile.raw
    local hits = {}
    for i, v in ipairs(live.sorted_raw) do
        if v == tv then
            hits[#hits + 1] = string.format("7120+%d", i - 1)
        end
    end
    if #hits == 0 then
        return {}
    end
    local n = #live.sorted_raw + (live.staging_raw and 1 or 0)
    local note = string.format(
        "  疑似台面重复: @7502=%s (%02X) 亦在排序区 %s",
        live.table_tile.name,
        tv,
        table.concat(hits, ",")
    )
    if n <= 13 then
        note = note .. "（13张未摸时多为电脑台面污染，勿算入手牌）"
    else
        note = note .. "（摸后可能与刚摸合并，以 @7502 为准）"
    end
    return { note }
end

local function hunt_addr_known(addr)
    for _, r in ipairs(KNOWN_HUNT_RANGES) do
        if addr >= r[1] and addr <= r[2] then
            return true
        end
    end
    return false
end

local function format_live_log(live, machine)
    local t = {
        string.format(
            "  手%d@7120: %s",
            #live.sorted_raw,
            (#live.hand > 0) and table.concat(live.hand, " ") or "-"
        ),
    }
    if machine then
        t[#t + 1] = "  手hex@7120: " .. hand_bytes_hex(machine)
        t[#t + 1] = "  focus@7300: " .. focus7300_hex(machine)
        t[#t + 1] = "  cluster6@730E: " .. cluster6_hex(machine)
        t[#t + 1] = "  cluster2: " .. cluster_routes_hex(machine)
    end
    local ms = hand_multiset_line(live)
    if ms then
        t[#t + 1] = ms
    end
    for _, line in ipairs(table_contamination_lines(live)) do
        t[#t + 1] = line
    end
    if live.staging_raw then
        t[#t + 1] = string.format("  缓冲@712D: %s (%02X)", tile_name(live.staging_raw), live.staging_raw)
    end
    if live.table_tile then
        t[#t + 1] = string.format("  台面@7502: %s (%02X)", live.table_tile.name, live.table_tile.raw)
    else
        t[#t + 1] = "  台面@7502: -"
    end
    if #live.cpu_raw > 0 then
        local q = {}
        for _, v in ipairs(live.cpu_raw) do
            q[#q + 1] = string.format("%s/%02X", tile_name(v), v)
        end
        t[#t + 1] = "  电脑@7240: " .. table.concat(q, " ")
    else
        t[#t + 1] = "  电脑@7240: -"
    end
    if live.cpu_discard_names and #live.cpu_discard_names > 0 then
        local hex = {}
        for _, v in ipairs(live.cpu_discard_raw) do
            hex[#hex + 1] = string.format("%02X", v)
        end
        t[#t + 1] = string.format(
            "  电脑河@7200(%d): %s",
            #live.cpu_discard_names,
            table.concat(live.cpu_discard_names, " ")
        )
        t[#t + 1] = "  电脑河hex: " .. table.concat(hex, " ")
    else
        t[#t + 1] = "  电脑河@7200: -"
    end
    if live.player_discard_names and #live.player_discard_names > 0 then
        local hex = {}
        for _, v in ipairs(live.player_discard_raw) do
            hex[#hex + 1] = string.format("%02X", v)
        end
        t[#t + 1] = string.format(
            "  玩家河@7280(%d): %s",
            #live.player_discard_names,
            table.concat(live.player_discard_names, " ")
        )
        t[#t + 1] = "  玩家河hex: " .. table.concat(hex, " ")
    else
        t[#t + 1] = "  玩家河@7280: -"
    end
    return table.concat(t, "\n") .. "\n"
end

local function dump_space(space, start, size)
    local buf = {}
    buf[#buf + 1] = {}
    local chunk = buf[#buf]
    for i = 0, size - 1 do
        local ok, v = pcall(function()
            return space:read_u8(start + i)
        end)
        chunk[#chunk + 1] = string.char((ok and v or 0) & 0xFF)
        if #chunk >= 4096 then
            buf[#buf + 1] = {}
            chunk = buf[#buf]
        end
    end
    for i = 1, #buf do
        buf[i] = table.concat(buf[i])
    end
    return table.concat(buf)
end

local function hex_preview(s, n)
    n = math.min(n or 32, #s)
    local t = {}
    for i = 1, n do
        t[#t + 1] = string.format("%02X", s:byte(i))
    end
    return table.concat(t, " ")
end

local function hex_dump(s, base, off, len)
    off = off or 0
    len = math.min(len or #s, #s - off)
    local t = {}
    local i = 0
    while i < len do
        local line = { string.format("  %06X ", base + off + i) }
        for j = 0, 15 do
            if i + j < len then
                line[#line + 1] = string.format(" %02X", s:byte(off + i + j + 1))
            else
                line[#line + 1] = "   "
            end
        end
        t[#t + 1] = table.concat(line)
        i = i + 16
    end
    return table.concat(t, "\n") .. "\n"
end

local function wall_hits_bcd_n(s, n)
    local hits = {}
    if #s < n then
        return hits
    end
    local freq = {}
    local bad = 0
    local function addv(v, d)
        if not BCD_TILE[v] then
            bad = bad + d
            return
        end
        freq[v] = (freq[v] or 0) + d
    end
    local function ok()
        if bad ~= 0 then
            return false
        end
        local sum = 0
        for _, c in pairs(freq) do
            if c > 4 then
                return false
            end
            sum = sum + c
        end
        return sum == n
    end
    for i = 1, n do
        addv(s:byte(i), 1)
    end
    if ok() then
        hits[#hits + 1] = 0
    end
    for i = 2, #s - n + 1 do
        addv(s:byte(i - 1), -1)
        addv(s:byte(i + n - 1), 1)
        if ok() then
            hits[#hits + 1] = i - 1
        end
    end
    return hits
end

local function hist34_hits(s)
    local n = #s
    local hits = {}
    if n < 34 then
        return hits
    end
    local sum, bad = 0, 0
    local function addv(v, d)
        if v > 4 then
            bad = bad + d
        else
            sum = sum + v * d
        end
    end
    for i = 1, 34 do
        addv(s:byte(i), 1)
    end
    local function ok()
        return bad == 0 and sum >= 84 and sum <= 136
    end
    if ok() then
        hits[#hits + 1] = { off = 0, sum = sum }
    end
    for i = 2, n - 33 do
        addv(s:byte(i - 1), -1)
        addv(s:byte(i + 33), 1)
        if ok() then
            hits[#hits + 1] = { off = i - 1, sum = sum }
        end
    end
    return hits
end

local function scan_buf(s, label, base_addr)
    local hits = {}
    local n = #s
    if n < 34 then
        return hits
    end
    local function add(kind, off, len, note)
        hits[#hits + 1] = {
            kind = kind,
            addr = base_addr + off,
            off = off,
            len = len,
            note = note,
            preview = hex_preview(s:sub(off + 1, off + math.min(len, 24)), 24),
        }
    end
    for _, n in ipairs(WALL_SCAN_LENS) do
        if #s >= n then
            local kind = string.format("wall%d BCD", n)
            for _, off in ipairs(wall_hits_bcd_n(s, n)) do
                add(kind, off, n, label)
            end
        end
    end
    local h34 = hist34_hits(s)
    local shown = 0
    for _, h in ipairs(h34) do
        shown = shown + 1
        if shown <= 8 then
            add(string.format("hist34 sum=%d", h.sum), h.off, 34, label)
        end
    end
    if #h34 > 8 then
        add(string.format("hist34 ... +%d more", #h34 - 8), h34[9].off, 34, label)
    end
    return hits
end

local function scan_region(s, name, base_addr)
    return scan_buf(s, name .. "/u8", base_addr)
end

local function format_hits(hits)
    local walls, other = {}, {}
    for _, h in ipairs(hits) do
        if h.kind:find("wall", 1, true) and h.kind:find("BCD", 1, true) then
            walls[#walls + 1] = h
        else
            other[#other + 1] = h
        end
    end
    if #walls == 0 and #other == 0 then
        return "  (no wall/hist signature)\n"
    end
    local t = { string.format("  wall=%d hist/other=%d\n", #walls, #other) }
    local function dump(list, maxn)
        for i = 1, math.min(#list, maxn) do
            local h = list[i]
            t[#t + 1] = string.format(
                "  - %s @ 0x%06X len=%d %s\n    %s\n",
                h.kind, h.addr, h.len, h.note or "", h.preview
            )
        end
        if #list > maxn then
            t[#t + 1] = string.format("  ... %d more\n", #list - maxn)
        end
    end
    dump(walls, 16)
    dump(other, 8)
    return table.concat(t)
end

local function collect_diff_runs(a, b, base_addr)
    local n = math.min(#a, #b)
    local runs = {}
    local i = 1
    while i <= n do
        if a:byte(i) ~= b:byte(i) then
            local j = i
            while j <= n and a:byte(j) ~= b:byte(j) do
                j = j + 1
            end
            runs[#runs + 1] = {
                addr = base_addr + (i - 1),
                len = j - i,
                before = hex_preview(a:sub(i, i + math.min(j - i, 32) - 1), 32),
                after = hex_preview(b:sub(i, i + math.min(j - i, 32) - 1), 32),
            }
            i = j
        else
            i = i + 1
        end
    end
    return runs
end

local function format_diff_runs(name, runs, maxn)
    local t = { string.format("[%s] %d changed run(s)\n", name, #runs) }
    table.sort(runs, function(x, y)
        if x.len ~= y.len then
            return x.len > y.len
        end
        return x.addr < y.addr
    end)
    for k = 1, math.min(#runs, maxn or 24) do
        local r = runs[k]
        t[#t + 1] = string.format(
            "  run @ 0x%06X len=%d\n    A %s\n    B %s\n",
            r.addr, r.len, r.before, r.after
        )
    end
    if #runs > (maxn or 24) then
        t[#t + 1] = string.format("  ... %d more\n", #runs - (maxn or 24))
    end
    return table.concat(t)
end

local function diff_bufs(a, b, name, base_addr)
    return format_diff_runs(name, collect_diff_runs(a, b, base_addr), 24)
end

local function collect_unknown_runs(a, b, base_addr)
    local all = collect_diff_runs(a, b, base_addr)
    local runs = {}
    for _, r in ipairs(all) do
        if not hunt_addr_known(r.addr) then
            runs[#runs + 1] = r
        end
    end
    return runs
end

local function diff_bufs_unknown(a, b, name, base_addr)
    return format_diff_runs(name, collect_unknown_runs(a, b, base_addr), 32)
end

local function snapshot_all(machine)
    local snap = { regions = {}, hits = {}, rom = machine.system.name }
    local cpu = machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space then
        return snap
    end
    for _, spec in ipairs(RANGES) do
        local s = dump_space(space, spec.start, spec.size)
        snap.regions[#snap.regions + 1] = {
            name = spec.name,
            start = spec.start,
            size = spec.size,
            data = s,
        }
        for _, h in ipairs(scan_region(s, spec.name, spec.start)) do
            snap.hits[#snap.hits + 1] = h
        end
    end
    return snap
end

local function region(snap, name)
    for _, r in ipairs(snap.regions) do
        if r.name == name then
            return r
        end
    end
end

local function peek_snap_u8(snap, addr)
    for _, name in ipairs({ "z80_work", "z80_nvram", "z80_bank_win" }) do
        local r = region(snap, name)
        if r and addr >= r.start and addr < r.start + #r.data then
            return r.data:byte(addr - r.start + 1), name
        end
    end
    return nil, nil
end

local function hand_multiset_from_snap(snap)
    local counts = {}
    local list = {}
    for i = 0, HAND_SORTED - 1 do
        local v = peek_snap_u8(snap, HAND_ADDR + i)
        if v and tile_valid(v) then
            counts[v] = (counts[v] or 0) + 1
            list[#list + 1] = v
        end
    end
    local st = peek_snap_u8(snap, HAND_ADDR + HAND_STAGING_OFF)
    if st and tile_valid(st) then
        counts[st] = (counts[st] or 0) + 1
        list[#list + 1] = st
    end
    return counts, list
end

local function discard_tail_from_snap(snap, base)
    local last = nil
    for i = 0, DISCARD_HIST_MAX - 1 do
        local v = peek_snap_u8(snap, base + i)
        if not v or not tile_valid(v) then
            break
        end
        last = v
    end
    return last
end

local function fmt_tile_opt(v)
    if v and tile_valid(v) then
        return string.format("%s(%02X)", tile_name(v), v)
    end
    if v then
        return string.format("[%02X]", v)
    end
    return "-"
end

-- 干净摸牌：推断刚摸 + 对照 @7502/@712D + 未知区 first-appear（限流）
local DRAW_SLOT_FA_MAX = 16
local function format_draw_slot_report(snap_old, snap_new)
    local t = { "  [draw-slot] 玩家摸牌交付对照\n" }
    if not snap_old or not snap_new then
        t[#t + 1] = "  (无上一拍 — 先 Ctrl+5)\n"
        return table.concat(t), "无基准"
    end
    local ca, lista = hand_multiset_from_snap(snap_old)
    local cb, listb = hand_multiset_from_snap(snap_new)
    local n_a, n_b = #lista, #listb
    t[#t + 1] = string.format("  手数(排序+@712D): %d → %d\n", n_a, n_b)

    local gained, lost = {}, {}
    local keys = {}
    for v, _ in pairs(ca) do
        keys[v] = true
    end
    for v, _ in pairs(cb) do
        keys[v] = true
    end
    for v, _ in pairs(keys) do
        local d = (cb[v] or 0) - (ca[v] or 0)
        if d > 0 then
            for _ = 1, d do
                gained[#gained + 1] = v
            end
        elseif d < 0 then
            for _ = 1, -d do
                lost[#lost + 1] = v
            end
        end
    end
    if #gained > 0 then
        local gnames = {}
        for _, v in ipairs(gained) do
            gnames[#gnames + 1] = tile_name(v)
        end
        t[#t + 1] = string.format("  手 multiset +%d: %s\n", #gained, table.concat(gnames, " "))
    else
        t[#t + 1] = "  手 multiset +: (无)\n"
    end
    if #lost > 0 then
        local lnames = {}
        for _, v in ipairs(lost) do
            lnames[#lnames + 1] = tile_name(v)
        end
        t[#t + 1] = string.format("  手 multiset -%d: %s\n", #lost, table.concat(lnames, " "))
    end

    local drawn_v = nil
    if #gained == 1 and #lost == 0 then
        drawn_v = gained[1]
    elseif #gained == 1 and #lost >= 1 then
        drawn_v = gained[1]
        t[#t + 1] = "  (手数有减有增 — 可能换牌/吃碰，仍以 +1 张为候选刚摸)\n"
    end

    local t7502_a = peek_snap_u8(snap_old, TABLE_TILE_ADDR)
    local t7502_b = peek_snap_u8(snap_new, TABLE_TILE_ADDR)
    local t712d_a = peek_snap_u8(snap_old, HAND_ADDR + HAND_STAGING_OFF)
    local t712d_b = peek_snap_u8(snap_new, HAND_ADDR + HAND_STAGING_OFF)
    local cpu_tail_a = discard_tail_from_snap(snap_old, CPU_DISCARD_ADDR)
    local cpu_tail_b = discard_tail_from_snap(snap_new, CPU_DISCARD_ADDR)
    local pl_tail_a = discard_tail_from_snap(snap_old, PLAYER_DISCARD_ADDR)
    local pl_tail_b = discard_tail_from_snap(snap_new, PLAYER_DISCARD_ADDR)

    t[#t + 1] = string.format(
        "  @7502: %s → %s%s\n",
        fmt_tile_opt(t7502_a),
        fmt_tile_opt(t7502_b),
        (t7502_a ~= t7502_b) and "  ←变" or ""
    )
    t[#t + 1] = string.format(
        "  @712D: %s → %s%s\n",
        fmt_tile_opt(t712d_a),
        fmt_tile_opt(t712d_b),
        (t712d_a ~= t712d_b) and "  ←变" or ""
    )
    t[#t + 1] = string.format(
        "  电脑河末: %s → %s%s | 玩家河末: %s → %s%s\n",
        fmt_tile_opt(cpu_tail_a),
        fmt_tile_opt(cpu_tail_b),
        (cpu_tail_a ~= cpu_tail_b) and "  ←变" or "",
        fmt_tile_opt(pl_tail_a),
        fmt_tile_opt(pl_tail_b),
        (pl_tail_a ~= pl_tail_b) and "  ←变" or ""
    )

    local match_7502 = drawn_v and t7502_b == drawn_v
    local match_712d = drawn_v and t712d_b == drawn_v
    local river_only = (cpu_tail_a ~= cpu_tail_b or pl_tail_a ~= pl_tail_b) and #gained == 0
    local verdict
    if drawn_v and n_b == n_a + 1 and #lost == 0 then
        local parts = { string.format("玩家摸 %s", tile_name(drawn_v)) }
        if match_7502 then
            parts[#parts + 1] = "@7502"
        end
        if match_712d then
            parts[#parts + 1] = "@712D"
        end
        if not match_7502 and not match_712d then
            parts[#parts + 1] = "交付槽未对上@7502/@712D"
        end
        verdict = table.concat(parts, "→") .. " | 手+1"
    elseif river_only and t7502_a ~= t7502_b then
        verdict = "仅@7502/河变、手未+1（疑台面/打牌）"
    elseif #gained == 0 and t7502_a ~= t7502_b then
        verdict = "仅@7502变、手未变（疑台面/打牌）"
    elseif drawn_v then
        verdict = string.format(
            "候选刚摸 %s | @7502%s @712D%s",
            tile_name(drawn_v),
            match_7502 and "=合" or "≠",
            match_712d and "=合" or "≠"
        )
    else
        verdict = "未推断出单张刚摸（检查是否摸/打混拍）"
    end
    t[#t + 1] = "  结论: " .. verdict .. "\n"

    if drawn_v and tile_valid(drawn_v) then
        t[#t + 1] = string.format(
            "  刚摸对照: %s (%02X)\n",
            tile_name(drawn_v),
            drawn_v
        )
        local first_appear, consumed = {}, {}
        for _, name in ipairs({ "z80_work", "z80_nvram" }) do
            local ra = region(snap_old, name)
            local rb = region(snap_new, name)
            if ra and rb then
                local n = math.min(#ra.data, #rb.data)
                -- 热区优先：nvram 只扫 0x7100-0x77FF
                local i0, i1 = 1, n
                if name == "z80_nvram" then
                    i0 = math.max(1, 0x7100 - ra.start + 1)
                    i1 = math.min(n, 0x77FF - ra.start + 1)
                end
                for i = i0, i1 do
                    local oa, ob = ra.data:byte(i), rb.data:byte(i)
                    local addr = ra.start + i - 1
                    if oa == drawn_v and ob ~= drawn_v then
                        consumed[#consumed + 1] = { addr = addr, before = oa, after = ob, region = name }
                    elseif oa ~= drawn_v and ob == drawn_v then
                        first_appear[#first_appear + 1] = {
                            addr = addr,
                            before = oa,
                            after = ob,
                            region = name,
                            from_empty = (oa == 0 or not tile_valid(oa)),
                            known = hunt_addr_known(addr),
                        }
                    end
                end
            end
        end
        table.sort(first_appear, function(a, b)
            if a.known ~= b.known then
                return a.known and not b.known
            end
            if a.from_empty ~= b.from_empty then
                return a.from_empty
            end
            return a.addr < b.addr
        end)
        t[#t + 1] = string.format("  first-appear %s @ %d addr(s) (已知槽优先):\n", tile_name(drawn_v), #first_appear)
        for i = 1, math.min(#first_appear, DRAW_SLOT_FA_MAX) do
            local h = first_appear[i]
            t[#t + 1] = string.format(
                "    %s @0x%06X  %02X→%02X%s%s\n",
                h.region,
                h.addr,
                h.before,
                h.after,
                h.from_empty and " (空→)" or "",
                h.known and " [known]" or ""
            )
        end
        if #first_appear == 0 then
            t[#t + 1] = "    (none)\n"
        end
        t[#t + 1] = string.format("  consumed %s @ %d addr(s):\n", tile_name(drawn_v), #consumed)
        for i = 1, math.min(#consumed, 8) do
            local h = consumed[i]
            t[#t + 1] = string.format(
                "    %s @0x%06X  %02X→%02X\n",
                h.region,
                h.addr,
                h.before,
                h.after
            )
        end
        if #consumed == 0 then
            t[#t + 1] = "    (none)\n"
        end
    end
    return table.concat(t), verdict
end

local function dump_region_nz(data, base, label, max_lines)
    local t = { label .. "\n" }
    local lines = 0
    for off = 0, #data - 1, 16 do
        local nz = false
        for j = 1, math.min(16, #data - off) do
            if data:byte(off + j) ~= 0 then
                nz = true
                break
            end
        end
        if nz then
            t[#t + 1] = hex_dump(data, base, off, 16)
            lines = lines + 1
            if max_lines and lines >= max_lines then
                t[#t + 1] = string.format("  ... truncated after %d non-zero lines\n", max_lines)
                break
            end
        end
    end
    if lines == 0 then
        t[#t + 1] = "  (all zero)\n"
    end
    return table.concat(t)
end

local function dump_hot(snap)
    local t = { string.format("rom=%s\n", snap.rom or "?") }
    local nv = region(snap, "z80_nvram")
    if nv then
        t[#t + 1] = dump_region_nz(
            nv.data:sub(NVRAM_HOT0 + 1, NVRAM_HOT1),
            0x7100,
            "[z80_nvram 0x7000-0x7FFF focus 0x7100-0x77FF]",
            nil
        )
    end
    local bank = region(snap, "z80_bank_win")
    if bank then
        t[#t + 1] = dump_region_nz(
            bank.data,
            bank.start,
            "[z80_bank_win 0x8000-0xFFFF non-zero]",
            BANK_DUMP_MAX_LINES
        )
    end
    return table.concat(t)
end

local function log_map(machine)
    if logged_map then
        return
    end
    logged_map = true
    local lines = {
        string.format("=== mjelctrn wall hunt map %s rom=%s ===\n", now(), machine.system.name),
    }
    for tag, dev in pairs(machine.devices) do
        if type(tag) == "string" and tag:find("cpu", 1, true) then
            lines[#lines + 1] = string.format("device %s short=%s\n", tag, tostring(dev.shortname))
        end
    end
    write_log(table.concat(lines), "a")
end

local function invalidate_keys()
    keys.need_rebind = true
    keys.bound_machine = nil
    keys.input = nil
    keys.seq5, keys.seq1, keys.seq2, keys.seq3, keys.seq4 = nil, nil, nil, nil, nil
    keys.seq6, keys.seq7, keys.seq8, keys.seq9 = nil, nil, nil, nil
    keys.seq0, keys.seq_f9, keys.seq_f8 = nil, nil, nil
    keys.seq_minus = nil
    for i = 1, #keys.prev do
        keys.prev[i] = false
    end
end

local function bind_keys(machine)
    if not keys.need_rebind and keys.bound_machine == machine and keys.input and keys.seq5 then
        return true
    end
    if not machine or not machine.input then
        invalidate_keys()
        return false
    end
    -- 一律右 Ctrl：左 Ctrl=杠牌。可选键失败不得拖垮核心绑定。
    local ok = pcall(function()
        local inp = machine.input
        local R = "KEYCODE_RCONTROL"
        keys.seq5 = inp:seq_from_tokens(R .. " KEYCODE_5")
        keys.seq1 = inp:seq_from_tokens(R .. " KEYCODE_1")
        keys.seq2 = inp:seq_from_tokens(R .. " KEYCODE_2")
        keys.seq3 = inp:seq_from_tokens(R .. " KEYCODE_3")
        keys.seq4 = inp:seq_from_tokens(R .. " KEYCODE_4")
        keys.seq6 = inp:seq_from_tokens(R .. " KEYCODE_6")
        keys.seq7 = inp:seq_from_tokens(R .. " KEYCODE_7")
        keys.seq8 = inp:seq_from_tokens(R .. " KEYCODE_8")
        keys.seq9 = inp:seq_from_tokens(R .. " KEYCODE_9")
        keys.seq_f9 = inp:seq_from_tokens("KEYCODE_F9")
        keys.seq_f8 = inp:seq_from_tokens("KEYCODE_F8")
        keys.input = inp
    end)
    if not ok or not keys.seq5 then
        invalidate_keys()
        return false
    end
    keys.seq0 = nil
    keys.seq_minus = nil
    pcall(function()
        keys.seq0 = keys.input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_0")
    end)
    pcall(function()
        keys.seq_minus = keys.input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_MINUS")
    end)
    keys.bound_machine = machine
    keys.need_rebind = false
    for i = 1, #keys.prev do
        keys.prev[i] = false
    end
    return true
end

-- 软复位后旧 input_seq 会变成野指针；裸 seq_pressed → 无响应 / 退出时 ACCESS VIOLATION
local function edge(idx, seq)
    if not keys.input or not seq then
        return false
    end
    local ok, down = pcall(function()
        return keys.input:seq_pressed(seq)
    end)
    if not ok then
        invalidate_keys()
        return false
    end
    down = down and true or false
    local fire = down and not keys.prev[idx]
    keys.prev[idx] = down
    return fire
end

local function refresh_pause_visual()
    local m = manager.machine
    if not m or not m.render then
        return
    end
    local st = (m.paused and 1) or 0
    local function apply(view)
        if not view or not view.items then
            return
        end
        local item = view.items["btn_pause"]
        if item and item.set_state then
            pcall(function()
                item:set_state(st)
            end)
        end
    end
    pcall(function()
        if m.render.ui_target then
            apply(m.render.ui_target.current_view)
        end
        for i = 1, 4 do
            local t = m.render.targets[i]
            if t and t.current_view then
                apply(t.current_view)
            end
        end
    end)
end

local function osd_now()
    local t, hz = 0, 0
    pcall(function()
        t = emu.osd_ticks()
        hz = emu.osd_ticks_per_second()
    end)
    return t, hz
end

local function ptr_busy()
    local t, hz = osd_now()
    if t > 0 and hz and hz > 0 then
        return ptr_lock_until > 0 and t < ptr_lock_until
    end
    return ptr_lock_frames > 0
end

local function ptr_mark_busy(sec)
    sec = sec or 0.22
    local t, hz = osd_now()
    if t > 0 and hz and hz > 0 then
        ptr_lock_until = t + hz * sec
    end
    ptr_lock_frames = math.max(14, math.floor(60 * sec))
end

local function ptr_tick()
    if ptr_lock_frames > 0 then
        ptr_lock_frames = ptr_lock_frames - 1
    end
    local t, hz = osd_now()
    if t > 0 and hz and hz > 0 and ptr_lock_until > 0 and t >= ptr_lock_until then
        ptr_lock_until = 0
        ptr_lock_frames = 0
    end
end

local function toggle_pause()
    if ptr_busy() then
        return
    end
    ptr_mark_busy()
    pcall(function()
        if manager.machine.paused then
            emu.unpause()
        else
            emu.pause()
        end
    end)
    refresh_pause_visual()
end

local function rt_bounds(x0, y0, x1, y1)
    local b = emu.render_bounds()
    if b.set_xy then
        b:set_xy(x0, y0, x1, y1)
        return b
    end
    b.x0, b.y0, b.x1, b.y1 = x0, y0, x1, y1
    return b
end

local function view_is_landscape(view)
    local name = ""
    pcall(function()
        name = tostring(view.name or "")
    end)
    return name:find("Landscape", 1, true) ~= nil
end

local function ptr_norm(view, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil
    end
    if x <= 2 and y <= 2 then
        return x, y
    end
    local vx0, vy0, vw, vh = 0, 0, 0, 0
    pcall(function()
        local b = view.bounds
        if b then
            vx0, vy0 = b.x0, b.y0
            vw, vh = b.x1 - b.x0, b.y1 - b.y0
        end
    end)
    if vw > 2 and vh > 2 then
        return (x - vx0) / vw, (y - vy0) / vh
    end
    if view_is_landscape(view) then
        return x / 1600, y / 900
    end
    return x / 1000, y / 1640
end

local function item_bounds(item)
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
    if b and b.x0 and b.y0 then
        return b.x0, b.y0, b.x1, b.y1
    end
    return nil
end

local function hit_rect(x, y, x0, y0, x1, y1)
    if not x or not y or not x0 then
        return false
    end
    if x0 > x1 then
        x0, x1 = x1, x0
    end
    if y0 > y1 then
        y0, y1 = y1, y0
    end
    local mx, my = (x1 - x0) * 0.10, (y1 - y0) * 0.10
    return x >= (x0 - mx) and x <= (x1 + mx) and y >= (y0 - my) and y <= (y1 + my)
end

local function hit_item_xy(view, id, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local item = view and view.items and view.items[id]
    local x0, y0, x1, y1 = item_bounds(item)
    if not x0 then
        return false
    end
    if hit_rect(x, y, x0, y0, x1, y1) then
        return true
    end
    local nx, ny = ptr_norm(view, x, y)
    local bx0, by0 = ptr_norm(view, x0, y0)
    local bx1, by1 = ptr_norm(view, x1, y1)
    return hit_rect(nx, ny, bx0, by0, bx1, by1)
end

local function hit_skin_xy(view, id, key, x, y)
    local ok, hit = pcall(hit_item_xy, view, id, x, y)
    if ok and hit then
        return true
    end
    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local r = SKIN_HIT[key]
    if not r then
        return false
    end
    local land = view_is_landscape(view)
    local x0, y0, x1, y1
    if land then
        x0, y0, x1, y1 = r.lx0, r.ly0, r.lx1, r.ly1
    else
        x0, y0, x1, y1 = r.px0, r.py0, r.px1, r.py1
    end
    if x <= 2 and y <= 2 then
        local vw, vh = land and 1600 or 1000, land and 900 or 1640
        return hit_rect(x, y, x0 / vw, y0 / vh, x1 / vw, y1 / vh)
    end
    return hit_rect(x, y, x0, y0, x1, y1)
end

local function hit_pause_xy(view, x, y)
    return hit_skin_xy(view, "btn_pause", "pause", x, y)
end

local function hit_peek_xy(view, x, y)
    return hit_skin_xy(view, "btn_peek", "peek", x, y)
end

local function hit_accept_xy(view, x, y)
    return hit_skin_xy(view, "btn_accept", "accept", x, y)
end

local function hit_sangen_xy(view, x, y)
    return hit_skin_xy(view, "btn_sangen", "sangen", x, y)
end

local function hit_bleed_xy(view, x, y)
    return hit_skin_xy(view, "btn_bleed", "bleed", x, y)
end

local function hit_pool_tile_xy(view, x, y)
    if not peek_open or not tiles_ui or not tiles_ui.hit_mjelctrn_pool then
        return nil
    end
    if not peek_state or not peek_state.pool then
        return nil
    end
    -- 透视画在 ui_container：用 layout/全窗 0–1，勿用 view_to_screen（会减游戏画面 inset≈2 格）
    local ux, uy
    if tiles_ui.view_to_ui01 then
        ux, uy = tiles_ui.view_to_ui01(view, x, y)
    elseif tiles_ui.view_to_screen then
        ux, uy = tiles_ui.view_to_screen(view, x, y)
    end
    if not ux then
        return nil
    end
    return tiles_ui.hit_mjelctrn_pool(ux, uy, peek_state.pool)
end

local function hook_peek_pointer(machine)
    -- 每个 view userdata 只 set_*_callback 一次（横↔竖会换 current_view，必须都能挂）
    -- 列表再开若复用同一 view：登记仍在 → 跳过，避免「按任意键」假死
    local bound = _G.__fei_mjelctrn_bound_views
    if not bound then
        bound = {}
        _G.__fei_mjelctrn_bound_views = bound
    end
    -- 二次进机：推迟挂新 view，避开开机图/按任意键
    if _G.__fei_mjelctrn_reentry then
        local sec = nil
        pcall(function()
            sec = machine.time.seconds
        end)
        if type(sec) ~= "number" or sec < 20 then
            return
        end
    end
    local render = machine.render
    if not render or not render.targets then
        return
    end
    local function pack_btn(name)
        return function()
            local p = _G.__fei_mjelctrn_wall
            local fn = p and p[name]
            if fn then
                return fn()
            end
            return 0
        end
    end
    local bound_n = 0
    local function try_bind(view)
        if not view or bound[view] then
            return false
        end
        local has_btn = false
        pcall(function()
            has_btn = view.items and view.items["btn_peek"] ~= nil
        end)
        if not has_btn then
            return false
        end
        local ok = pcall(function()
            local function bind_state(id, fn)
                local item = view.items[id]
                if not item then
                    return
                end
                if item.set_element_state_callback then
                    item:set_element_state_callback(fn)
                end
                if item.set_animation_state_callback then
                    item:set_animation_state_callback(fn)
                end
            end
            bind_state("btn_peek", pack_btn("btn_peek"))
            bind_state("btn_pause", pack_btn("btn_pause"))
            bind_state("btn_sangen", pack_btn("btn_sangen"))
            bind_state("btn_accept", pack_btn("btn_accept"))
            bind_state("btn_bleed", pack_btn("btn_bleed"))
            if view.set_pointer_updated_callback then
                view:set_pointer_updated_callback(function(_, _pid, _, x, y, _, pressed)
                    local p = _G.__fei_mjelctrn_wall
                    if p and p.on_pointer then
                        p.on_pointer(view, x, y, pressed)
                    end
                end)
            end
        end)
        if not ok then
            write_log(string.format("[pointer] bind FAIL %s\n", now()), "a")
            return false
        end
        bound[view] = true
        hooked_views[view] = true
        bound_n = bound_n + 1
        ptr_bound_view = view
        return true
    end
    for i = 1, 4 do
        local t = render.targets[i]
        if t and not t.hidden and t.current_view then
            try_bind(t.current_view)
        end
    end
    if render.ui_target and render.ui_target.current_view then
        try_bind(render.ui_target.current_view)
    end
    if bound_n > 0 then
        _G.__fei_mjelctrn_pointer_ever_bound = true
        _G.__fei_mjelctrn_pointer_hooked = true
        _G.__fei_mjelctrn_ptr_bound_view = ptr_bound_view
        write_log(string.format("[pointer] bound +%d view(s) %s\n", bound_n, now()), "a")
    end
end

local function toggle_peek(machine)
    local t, hz = osd_now()
    if t > 0 and hz and hz > 0 and last_peek_toggle_tick > 0 then
        if (t - last_peek_toggle_tick) < (hz * 0.35) then
            return
        end
    end
    if t > 0 then
        last_peek_toggle_tick = t
    end
    peek_open = not peek_open
    if tiles_ui then
        tiles_ui.ensure_art(machine)
    end
    -- 关闭时清面板缓存签名，避免下次脏合成叠色
    if (not peek_open) and tiles_ui and tiles_ui.invalidate_panel_cache then
        pcall(tiles_ui.invalidate_panel_cache)
    end
    machine:popmessage(peek_open and "电子基盘透视开（F9 关）" or "电子基盘透视关")
end

local function apply_peek_click(machine)
    if peek_click then
        peek_click = false
        toggle_peek(machine)
    end
end

local function apply_sangen_click(machine)
    if not sangen_click then
        return
    end
    sangen_click = false
    sangen_arm_ui(machine)
end

local function apply_accept_click(machine)
    if not accept_click then
        return
    end
    accept_click = false
    listen_accept.toggle(machine)
end

local function apply_pool_click(machine)
    if not pool_click_bcd then
        return
    end
    local bcd = pool_click_bcd
    pool_click_bcd = nil
    force_draw.select(machine, bcd)
end

local function draw_peek_panel(machine)
    if not peek_open then
        return
    end
    local frame_n = nil
    pcall(function()
        local scr = machine.screens[":screen"]
        if scr and scr.frame_number then
            frame_n = scr:frame_number()
        end
    end)
    if frame_n ~= nil and frame_n == last_peek_draw_frame then
        return
    end
    if frame_n ~= nil then
        last_peek_draw_frame = frame_n
    end
    local ui = machine.render and machine.render.ui_container
    if not ui then
        return
    end
    local live = read_live_peek(machine)
    peek_state = build_peek_state(machine, live)
    if tiles_ui then
        tiles_ui.ensure_art(machine)
        local ok = pcall(function()
            tiles_ui.draw_mjelctrn_panel(ui, peek_state)
        end)
        if ok then
            return
        end
    end
    draw_text_hud(machine)
end

local function draw_text_hud(machine)
    if not SHOW_DEBUG_HUD then
        return
    end
    local ui = machine.render and machine.render.ui_container
    if not ui or not ui.draw_text then
        return
    end
    local live = read_live_peek(machine)
    local hand_line = (#live.hand > 0) and table.concat(live.hand, " ") or "(空)"
    local raw_line = "-"
    if #live.sorted_raw > 0 then
        local t = {}
        for _, v in ipairs(live.sorted_raw) do
            t[#t + 1] = string.format("%02X", v)
        end
        raw_line = table.concat(t, " ")
    end
    local table_line = live.table_tile
        and string.format("台面: %s", live.table_tile.name)
        or "台面: -"
    local cpu_line = "-"
    if #live.cpu_raw > 0 then
        local t = {}
        for _, v in ipairs(live.cpu_raw) do
            t[#t + 1] = tile_name(v)
        end
        cpu_line = table.concat(t, " ")
    end
    local lines = {
        string.format("[Debug] %s  手%d", machine.system.name, #live.hand),
        hand_line,
        "码: " .. raw_line,
        table_line,
        "电脑: " .. cpu_line,
        string.format(
            "基准:%s STEP:%d | Ctrl+5/2 | F9关",
            snap_prev and (snap_prev.tag or "有") or "无",
            step_idx
        ),
    }
    local row0 = 11
    for i, line in ipairs(lines) do
        local col = 0xffffffff
        local bg = 0xc0101020
        if i == 1 then
            col = 0xffffff50
        elseif i == 2 then
            col = 0xffc8ffc8
        elseif i >= 4 then
            col = 0xffb0b0b0
        end
        pcall(function()
            ui:draw_text("left", row0 + i - 1, line, col, bg)
        end)
    end
end

local function report_scan(snap, title, mode)
    local body = {
        string.format("=== %s %s rom=%s ===\n", title, now(), snap.rom or "?"),
        format_hits(snap.hits),
        dump_hot(snap),
    }
    write_log(table.concat(body), mode)
    local walls, first = 0, nil
    for _, h in ipairs(snap.hits) do
        if h.kind:find("wall", 1, true) and h.kind:find("BCD", 1, true) then
            walls = walls + 1
            first = first or h
        end
    end
    if first then
        return string.format("mjelctrn: %d wall hit(s), first %s @ 0x%06X", walls, first.kind, first.addr)
    end
    return "mjelctrn: no wall BCD signature (hot+bank dump in log)"
end

local function diff_nvram_hot(snap_old, snap_new, label)
    local ra = region(snap_old, "z80_nvram")
    local rb = region(snap_new, "z80_nvram")
    if not ra or not rb or #ra.data < NVRAM_HOT1 or #rb.data < NVRAM_HOT1 then
        return
    end
    local a = ra.data:sub(NVRAM_HOT0 + 1, NVRAM_HOT1)
    local b = rb.data:sub(NVRAM_HOT0 + 1, NVRAM_HOT1)
    local tag = label or "z80_nvram_hot"
    write_log(diff_bufs(a, b, tag, 0x7100), "a")
    local unknown_runs = collect_unknown_runs(a, b, 0x7100)
    write_log(format_diff_runs(tag .. " UNKNOWN", unknown_runs, 32), "a")
    record_hunt_unknown_stats(unknown_runs)
    write_log(format_hunt_unknown_tally(12), "a")
    local cluster_diff = format_cluster730e_diff(a, b, 0x7100, "hot cluster@730E")
    if cluster_diff ~= "" then
        write_log(cluster_diff, "a")
    end
end

local function set_baseline(machine, tag, pop_suffix)
    log_map(machine)
    local live = read_live_peek(machine)
    local snap = snapshot_all(machine)
    snap.tag = tag or "baseline"
    step_idx = 0
    reset_hunt_unknown_stats()
    snap_baseline = snap
    snap_prev = snap
    write_log(string.format("=== BASELINE %s %s ===\n", snap.tag, now()), "a")
    write_log(format_live_log(live, machine), "a")
    local nv = region(snap, "z80_nvram")
    if nv then
        write_bin("smoke_logs/mjelctrn_nvram_baseline.bin", nv.data)
    end
    local msg = report_scan(snap, "BASELINE " .. snap.tag, "a")
    local pause_note = pause_for_hunt() and "\n已暂停 | F5 继续" or ""
    machine:popmessage(
        msg
            .. "\n基准已设 | 13张未摸最佳"
            .. "\n摸一张(先别打) → Ctrl+2 看 [draw-slot]"
            .. (pop_suffix or "")
            .. pause_note
    )
end

local function record_step(machine)
    step_idx = step_idx + 1
    local live = read_live_peek(machine)
    local draw_verdict = nil
    write_log(string.format("=== STEP #%d %s ===\n", step_idx, now()), "a")
    write_log(format_live_log(live, machine), "a")
    local snap_new = snapshot_all(machine)
    snap_new.tag = string.format("step_%d", step_idx)
    local nv = region(snap_new, "z80_nvram")
    if nv then
        write_bin(string.format("smoke_logs/mjelctrn_nvram_step_%02d.bin", step_idx), nv.data)
    end
    if snap_prev then
        write_log(
            string.format(
                "=== DIFF %s -> step_%d %s ===\n",
                snap_prev.tag or "?",
                step_idx,
                now()
            ),
            "a"
        )
        diff_nvram_hot(snap_prev, snap_new, string.format("hot %s->step_%d", snap_prev.tag or "?", step_idx))
        local slot_body, verdict = format_draw_slot_report(snap_prev, snap_new)
        write_log(slot_body, "a")
        draw_verdict = verdict
    else
        write_log("(no prev snap — 建议先 Ctrl+5 设基准)\n", "a")
    end
    snap_prev = snap_new
    local msg = report_scan(snap_new, string.format("STEP #%d", step_idx), "a")
    local pause_note = pause_for_hunt() and "\n已暂停 | F5 继续" or ""
    local slot_note = draw_verdict and ("\n" .. draw_verdict) or ""
    machine:popmessage(
        string.format("STEP #%d 已记录 | F5 继续\n%s%s%s", step_idx, msg, slot_note, pause_note)
    )
end

local function on_soft_reset(machine)
    -- DIP/F3 软复位：
    -- 1) 禁止写 A274；有 sticky/backup 只恢复 @7000 牌池。
    -- 2) 不要重绑 layout pointer。
    -- 3) 必须作废热键 seq（同 machine 指针时 bind 会跳过 → 旧 seq_pressed 野指针卡死/崩）。
    -- 4) 复位 notifier 内禁止 write_log。
    local bak = force_draw.sticky_backup or force_draw.backup
    if machine and bak then
        pcall(function()
            force_draw.restore_pool(machine, bak)
        end)
    end
    force_draw.clear_session()
    peek_open = false
    peek_state = nil
    ptr_any_down = false
    peek_click = false
    sangen_click = false
    accept_click = false
    bleed.click = false
    bleed.press_frames = 0
    listen_accept.on = false
    listen_accept.tap_rm()
    listen_accept.clear_ram(machine)
    pool_click_bcd = nil
    ptr_lock_until = 0
    ptr_lock_frames = 0
    last_peek_toggle_tick = 0
    last_peek_draw_frame = -1
    draw_track_prev = nil
    invalidate_keys()
    sangen_watch_reset_prev()
    boot_grace = 300
    _G.__fei_mjelctrn_boot_grace = boot_grace
    last_session_sec = nil
    if tiles_ui and tiles_ui.invalidate_panel_cache then
        pcall(tiles_ui.invalidate_panel_cache)
    end
end

local function on_machine_stop()
    -- 列表退回：pack 置空，避免复用 view 上的旧回调踩死；pointer 登记表保留防重绑
    _G.__fei_mjelctrn_wall = {
        is_family = function()
            return false
        end,
        on_paused_tick = function() end,
        btn_peek = function()
            return 0
        end,
        btn_pause = function()
            return 0
        end,
        btn_sangen = function()
            return 0
        end,
        btn_accept = function()
            return 0
        end,
        btn_bleed = function()
            return 0
        end,
        on_pointer = function() end,
    }
    _G.__fei_mjelctrn_reentry = true
    ptr_bound_view = nil
    hooked_views = {}
    ptr_any_down = false
    peek_open = false
    peek_click = false
    sangen_click = false
    accept_click = false
    bleed.click = false
    bleed.press_frames = 0
    pool_click_bcd = nil
    invalidate_keys()
    boot_grace = 300
    _G.__fei_mjelctrn_boot_grace = boot_grace
    last_session_sec = nil
end
_G.__fei_mjelctrn_on_machine_stop = on_machine_stop

local function ensure_stop_notifier()
    -- 飞剧场 pack 的 master 未必有停机 inert；wall 自己挂一份
    if _G.__fei_mjelctrn_stop_hooked then
        _G.__fei_mjelctrn_on_machine_stop = on_machine_stop
        return
    end
    if not emu.add_machine_stop_notifier then
        return
    end
    _G.__fei_mjelctrn_stop_hooked = true
    pcall(function()
        _G.__fei_mjelctrn_stop_sub = emu.add_machine_stop_notifier(function()
            local fn = _G.__fei_mjelctrn_on_machine_stop
            if fn then
                pcall(fn)
            end
        end)
    end)
end

local function check_soft_reset(machine)
    -- 备用：时间回绕 / 复位后时间接近 0（notifier 才是主路径）
    local sec = nil
    pcall(function()
        sec = machine.time.seconds
    end)
    if type(sec) ~= "number" then
        return
    end
    if last_session_sec ~= nil then
        if sec + 2.0 < last_session_sec then
            on_soft_reset(machine)
        elseif last_session_sec > 2.0 and sec < 1.0 then
            -- DIP「重新启动」常见：时间被清零，但未必是「回绕小于 last-2」
            on_soft_reset(machine)
        end
    end
    last_session_sec = sec
end

local function ensure_reset_notifier()
    if _G.__fei_mjelctrn_reset_hooked then
        _G.__fei_mjelctrn_on_reset = on_soft_reset
        return
    end
    if not emu.add_machine_reset_notifier then
        return
    end
    _G.__fei_mjelctrn_reset_hooked = true
    _G.__fei_mjelctrn_on_reset = on_soft_reset
    pcall(function()
        -- 必须挂在 _G，避免订阅被 GC
        _G.__fei_mjelctrn_reset_sub = emu.add_machine_reset_notifier(function()
            local fn = _G.__fei_mjelctrn_on_reset
            if fn then
                pcall(fn, manager and manager.machine)
            end
        end)
    end)
end

local function ensure_pause_poll()
    -- 进程内只 register 一次；重进游戏只更新 session，避免 periodic 叠层卡死
    -- layout 回调也读这个 pack：热重载不重绑 C 回调，只换这里的闭包
    _G.__fei_mjelctrn_wall = {
        is_family = is_family,
        on_paused_tick = function(m)
            if m.paused then
                apply_peek_click(m)
                apply_pool_click(m)
            end
            ptr_tick()
        end,
        btn_peek = function()
            return peek_open and 1 or 0
        end,
        btn_pause = function()
            return (manager.machine.paused and 1) or 0
        end,
        btn_sangen = function()
            return 0
        end,
        btn_accept = function()
            return listen_accept.on and 1 or 0
        end,
        btn_bleed = function()
            return (bleed.press_frames > 0) and 1 or 0
        end,
        on_pointer = function(view, x, y, pressed)
            local down = type(pressed) == "number" and (pressed & 1) ~= 0
            local was = ptr_any_down
            ptr_any_down = down
            if not down or was then
                return
            end
            if ptr_busy() then
                return
            end
            if hit_pause_xy(view, x, y) then
                toggle_pause()
                return
            end
            if hit_peek_xy(view, x, y) then
                peek_click = true
                ptr_mark_busy(0.45)
                return
            end
            if hit_sangen_xy(view, x, y) then
                sangen_click = true
                ptr_mark_busy(0.35)
                return
            end
            if hit_accept_xy(view, x, y) then
                accept_click = true
                ptr_mark_busy(0.35)
                return
            end
            if hit_bleed_xy(view, x, y) then
                bleed.click = true
                ptr_mark_busy(0.35)
                return
            end
            local bcd = hit_pool_tile_xy(view, x, y)
            if bcd then
                pool_click_bcd = bcd
                ptr_mark_busy()
            end
        end,
    }
    if _G.__fei_mjelctrn_wall_periodic then
        return
    end
    _G.__fei_mjelctrn_wall_periodic = true
    pcall(function()
        emu.register_periodic(function()
            local pack = _G.__fei_mjelctrn_wall
            local m = manager and manager.machine
            if not pack or not m or not m.system or not pack.is_family(m.system.name) then
                return
            end
            pcall(pack.on_paused_tick, m)
        end)
    end)
end

return function(machine)
    if not machine or not is_family(machine.system.name) then
        return
    end
    check_soft_reset(machine)
    ensure_reset_notifier()
    ensure_stop_notifier()
    ensure_pause_poll()
    if boot_grace > 0 then
        boot_grace = boot_grace - 1
        _G.__fei_mjelctrn_boot_grace = boot_grace
        -- 宽限期内可重建按键对象，禁止 seq_pressed / 写内存 / 挂钩
        if keys.need_rebind then
            pcall(bind_keys, machine)
        end
        return
    end
    _G.__fei_mjelctrn_boot_grace = 0
    -- 热键绑失败也要继续跑皮肤钮/透视；勿 return 掐断 pointer
    pcall(bind_keys, machine)
    ptr_tick()
    apply_peek_click(machine)
    apply_sangen_click(machine)
    apply_accept_click(machine)
    if bleed.click then
        bleed.click = false
        bleed.arm(machine)
    end
    apply_pool_click(machine)
    if bleed.press_frames > 0 then
        bleed.press_frames = bleed.press_frames - 1
    end
    pcall(function()
        force_draw.run_tick(machine)
    end)
    pcall(function()
        sangen_watch_tick(machine)
    end)
    if peek_open or SHOW_DEBUG_HUD then
        pcall(function()
            local live = read_live_peek(machine)
            update_draw_track(machine, live)
        end)
        draw_peek_panel(machine)
        draw_text_hud(machine)
    end

    -- 横↔竖会换 current_view：持续扫描尚未登记的 view；已登记的绝不重绑
    hook_tick = hook_tick + 1
    if hook_tick >= 8 then
        hook_tick = 0
        hook_peek_pointer(machine)
    end
    if _G.__fei_mjelctrn_pointer_ever_bound then
        ptr_bound_view = true
    end

    if not keys.input then
        return
    end

    -- 热键全部包在 pcall：任何 seq_pressed 失败只作废绑定，不拖死 MAME
    local ok_keys, err_keys = pcall(function()
        if keys.seq9 and edge(5, keys.seq9) then
            toggle_peek(machine)
        elseif keys.seq_f9 and edge(6, keys.seq_f9) then
            toggle_peek(machine)
        elseif keys.seq_f8 and edge(11, keys.seq_f8) then
            sangen_watch.on = not sangen_watch.on
            sangen_watch_reset_prev()
            if sangen_watch.on then
                dump_sangen_watch(machine, "arm")
                machine:popmessage(
                    "三元监视开 (F8 关)\n仅：@7423↔$50 或 @72CA=字牌×3\n命中暂停+追加 log | F5 继续"
                )
            else
                machine:popmessage("三元监视关")
            end
        elseif keys.seq0 and edge(12, keys.seq0) then
            sangen_arm_ui(machine)
        elseif keys.seq_minus and edge(13, keys.seq_minus) then
            bleed.arm(machine)
        end

        if keys.seq7 and edge(9, keys.seq7) then
            force_draw.tile_i = (force_draw.tile_i % #FORCE_TILES) + 1
            local bcd = force_draw.target_bcd()
            machine:popmessage(
                string.format(
                    "控摸目标 → %s (%02X)\n右Ctrl+8 开/关 | 勿选听牌自摸",
                    tile_name(bcd),
                    bcd
                )
            )
        elseif keys.seq8 and edge(10, keys.seq8) then
            if force_draw.armed or force_draw.sticky_backup then
                force_draw.disarm(machine, "manual_ctrl8")
            else
                force_draw.arm(machine)
            end
        elseif edge(7, keys.seq5) then
            set_baseline(machine, "manual", "")
        elseif edge(1, keys.seq1) then
            snap_exchange = snapshot_all(machine)
            snap_exchange.tag = "at_exchange_prompt"
            step_idx = 0
            snap_baseline = snap_exchange
            snap_prev = snap_exchange
            local nv = region(snap_exchange, "z80_nvram")
            if nv then
                write_bin("smoke_logs/mjelctrn_nvram_baseline.bin", nv.data)
            end
            local msg = report_scan(snap_exchange, "SNAP exchange prompt", "w")
            machine:popmessage(msg .. "\n开局换牌提示 | 换完稳定后 Ctrl+5 或 Ctrl+4")
        elseif edge(4, keys.seq4) then
            if snap_exchange then
                local snap_after = snapshot_all(machine)
                snap_after.tag = "after_exchange"
                write_log(string.format("=== DIFF exchange->after %s ===\n", now()), "a")
                diff_nvram_hot(snap_exchange, snap_after, "hot exchange->after")
                snap_exchange = nil
            end
            set_baseline(machine, "after_exchange", "（开局换牌后）")
        elseif edge(2, keys.seq2) then
            record_step(machine)
        elseif keys.seq6 and edge(8, keys.seq6) then
            local n = dump_draw_code_context(machine, "manual_ctrl6")
            machine:popmessage(
                string.format("code-dump 已写 log\nld($7502),a ×%d（应为含 A24D）", n)
            )
            pause_for_hunt()
        elseif edge(3, keys.seq3) then
            local snap = snapshot_all(machine)
            local msg = report_scan(snap, "SCAN only", "a")
            machine:popmessage(msg)
        end
    end)
    if not ok_keys then
        invalidate_keys()
    end
end
