-- mjelctrn（电子基盘）透视 Phase 2/3：牌图面板 + 皮肤钮 + 内存 hunt
-- 知识库：仓库根目录 电子基盘透视知识.md（含 MAME 默认键避让表）
--
-- ★ 热键一律用「右 Ctrl」：左 Ctrl = 本机杠牌（KEY0），会抢键/污染操作
-- F9 / 右Ctrl+9 / 皮肤 btn_peek  开/关牌图透视（画 ui_container，勿用 :screen）
-- 皮肤 btn_pause  暂停/继续（不绑麻将键；MAME 暂停默认是 F5）
-- 右Ctrl+5/2/…  Phase 1 hunt（见 电子基盘透视知识.md）
--   右Ctrl+5/2/4 记录时自动 emu.pause()；按 F5 继续（电脑不等玩家）
-- 副露地址 hunt（不必卡吃碰瞬间）：
--   开局无副露 Ctrl+5 → 画面上已能看见副露后再 Ctrl+2（弃牌打出也没关系）
--   脚本在「判定电脑副露 / 玩家副露块变多」时自动写 [meld-hunt]（不用手按）
-- 杠 hunt：控摸凑齐 → 杠（游戏键，勿用左Ctrl热键）→ Ctrl+2；再 Donden → Ctrl+2
--   （杠块会先出现在 @72D0/@7130，对调后多半进 @7250）
-- 右Ctrl+2 另写 [draw-slot]：用手数 multiset 推断刚摸，对照 @7502/@712D（摸牌验证）
-- 右Ctrl+6  dump 当前 bank 下 A24D/A215/AA5E 等（追摸牌生成/过滤；冷启动 bank 无效）
-- 右Ctrl+7  控摸：切换目标牌（万/筒/索/字循环）
-- 右Ctrl+8  控摸：开/关（开=整池填目标；**单次**：玩家摸写 @7502/A24D 即时恢复；手数兜底）
--         听牌被拒时：跳过「归还池+重抽」(A274 call AA5E / A277 jr)，改 jr A279 接受
-- 右Ctrl+0  一键三元：武装 @7CB0 并装弹白/发/中×3（官方表），弹出换牌 UI
-- 右Ctrl+-  / 皮肤 btn_bleed  下一局配牌出血：写 @7CC1=0（押注界面开局兑现）
-- F9 透视开时：面板「玩家役满」「电脑役满」下拉（写 @72C0 / @7240；含十三不搭探测）
-- 皮肤 btn_accept  听牌可胡：A260 读拦截；关/复位清零 @7424
--                 喂荣：透视点电脑手锁定（单次）→ 弃牌 PC 劫持写入 + 手/河对调一致
--                 主版 A2CE/9850/9168；mjelct3 9FE0/9605/9627（两套窗同时武装，同族 ROM 共用）
-- 可胡开时 log 会记 [listen-accept-pc]；喂荣记 [listen-accept-feed] / [listen-accept-7502]
-- F8      三元换牌监视开/关（注意：MAME 默认 F8=减跳帧，可能需在 UI 里改绑）
-- F9 牌池：34 种常显（0 张半透明）；点牌图 = 控摸下一张（单次，摸完/局间自动关）；角标=真实剩余
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
-- 透视读电脑手（只读）：@7240 主；空则 @77C0；再空试 @7610/@7630（只读，勿理牌写入）
-- 绝不用 @7100：副露时几乎总是玩家手拷贝，取它会串台
-- 绝不用 @72C0/@77B0：玩家手镜像
local CPU_HAND_FALLBACKS = { 0x7240, 0x77C0, 0x7610, 0x7630 }
local CPU_HAND_PRIO = { [0x7240] = 40, [0x77C0] = 30, [0x7610] = 20, [0x7630] = 10 }
-- 喂荣若再动手牌，只允许写这几个（当前暂停写入手牌）
local CPU_HAND_WRITABLE = { 0x7240, 0x77C0 }
local PLAYER_HAND_MIRRORS = { 0x7120 } -- 仅画面手；@72C0/@77B0 在 Donden 后会滞后，拿来判串台会把真电脑手当玩家手拒掉
-- 喂荣改手牌：副露透视未稳前关闭，避免 pack 同步污染真电脑手
local FEED_MUTATE_CPU_HAND = false
local TABLE_TILE_ADDR = 0x7502 -- 台面最近牌（含电脑刚打、玩家刚摸），勿标「刚摸」
local HAND_MIRROR_ADDR = 0x72C0 -- 判定用手镜像（cheat 役满手同址）
local WALL_POOL_ADDR = 0x7000 -- A875 牌池：非零=剩余 BCD，00=已取走
local WALL_POOL_LEN = 0xE0 -- 至约 @70DF（含字牌区）
-- 打牌影子里「刚打 BCD」槽（仅这几处可安全写成牌面；勿扫整段 @7605-764D，以免误改张数/状态）
local DISCARD_SHADOW_TILE_ADDRS = { 0x760A, 0x761D, 0x763D, 0x764D }
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
-- 副露方案（2026-09-17）：结算/Donden 都跟副露走 → 先读副露块，再反推暗手期望张数
-- 2026-09-17 实机钉死（用户局：碰中→吃一二三筒→玩家碰六筒→Donden）：
--   块格式：`mark` + 三张 BCD；mark=`82`碰 / `81`吃（旧 `44` 仍扫，三元/杠残留）
--   电脑副露 @7250 顺序追加（每口 4 字节）；玩家 @72D0 先出现，@7130 稍后/对调后可见
local meld = {
    MARK_CHI = 0x81,
    MARK_PON = 0x82,
    MARK_KAN = 0x84, -- 大明杠直接写 84；加杠则 82→84（终态相同）
    MARK_ANKAN = 0x44, -- 暗杠（2026-09-17：暗杠北 = 44 34 34 34）
    PLAYER_ADDR = 0x7130,
    PLAYER_MIRROR = 0x72D0, -- 玩家副露常先写这里
    CPU_ADDR = 0x7250,
    -- 每口 4 字节、最多 4 口；只认表头连续块（勿扫 0x40，会把 @7150 镜像算成第二口）
    SCAN_LEN = 0x10,
}

local SHOW_DEBUG_HUD = false
local peek_open = false
local peek_click = false
local sangen_click = false
local accept_click = false
local peek_state = nil
local pool_click_bcd = nil
local cpu_hand_cache = { raw = {}, src = nil } -- @7240 清空时的软缓存
-- 可信电脑手：只被可信镜像刷新，绝不因「像玩家」误清空（副露后喂荣依赖它）
local cpu_hand_trusted = { raw = {}, src = nil }
-- HUD 暂存：副露瞬间 @7120/@7280 常空读，顶栏用上次非零避免「你手0/你河0」闪断
local hud_sticky = { pl_n = 0, pl_rn = 0, cpu_rn = 0 }
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
    armed_zeros = 0,
    tick = 0,
    tap = nil,
    tap_cpu = nil,
    tap_dead = false,
    pending_msg = nil,
    pending_log = nil,
    prev_n = nil,
    prev_pl_rn = nil,
    prev_7502 = nil,
    -- ld ($7502),a @A24D 共 3 字节；写监视触发时 PC 常已到 A250，须放宽
    pc_lo = 0xA24D,
    pc_hi = 0xA25F,
}
-- 透视内「牌型」菜单（不占皮肤常驻钮）
-- 牌码对齐 jiangsheng mjelct3 cheat @72C0；四杠等需副露结构的未收
local hand_pat = {
    menu_open = false,
    menu_target = nil, -- "player" | "cpu"
    hits = {},
    click_id = nil,
    hold = nil, -- 换牌阶段短时每帧盖回镜像 { tiles=, frames= }
    hold_cpu = nil, -- 电脑役满：换牌阶段盖回 @7240/@77C0
    presets = {
        {
            id = "yakuman_tri",
            label = "字一色大三元四暗刻",
            tiles14 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x35, 0x35, 0x35, 0x36, 0x36, 0x36, 0x37, 0x37, 0x37,
            },
            tiles13 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x35, 0x35, 0x35, 0x36, 0x36, 0x36, 0x37, 0x37,
            },
            wait_hint = "听：中",
            wait_bcd = { 0x37 },
            key_bcd = { 0x35, 0x36, 0x37 },
        },
        {
            id = "daisangen",
            label = "大三元",
            tiles14 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x35, 0x35, 0x35, 0x36, 0x36, 0x36, 0x37, 0x37, 0x37,
            },
            tiles13 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x35, 0x35, 0x35, 0x36, 0x36, 0x36, 0x37, 0x37,
            },
            wait_hint = "听：中",
            wait_bcd = { 0x37 },
            key_bcd = { 0x35, 0x36, 0x37 },
        },
        {
            id = "daisuushi",
            label = "大四喜",
            tiles14 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x32, 0x33, 0x33, 0x33, 0x34, 0x34, 0x34, 0x35, 0x35,
            },
            tiles13 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x32, 0x33, 0x33, 0x33, 0x34, 0x34, 0x34, 0x35,
            },
            wait_hint = "听：白",
        },
        {
            id = "shosuushi",
            label = "小四喜",
            tiles14 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x32, 0x33, 0x33, 0x34, 0x34, 0x34, 0x35, 0x35, 0x35,
            },
            tiles13 = {
                0x31, 0x31, 0x31, 0x32, 0x32, 0x32, 0x33, 0x33, 0x34, 0x34, 0x34, 0x35, 0x35,
            },
            wait_hint = "听：白",
        },
        {
            id = "dairoisei",
            label = "大七星(电子基盘归为字一色)",
            tiles14 = {
                0x31, 0x31, 0x32, 0x32, 0x33, 0x33, 0x34, 0x34, 0x35, 0x35, 0x36, 0x36, 0x37, 0x37,
            },
            tiles13 = {
                0x31, 0x31, 0x32, 0x32, 0x33, 0x33, 0x34, 0x34, 0x35, 0x35, 0x36, 0x36, 0x37,
            },
            wait_hint = "听：中；机内计为字一色",
        },
        {
            id = "kokushi",
            label = "国士无双",
            tiles14 = {
                0x01, 0x09, 0x11, 0x19, 0x21, 0x29, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x37,
            },
            tiles13 = {
                0x01, 0x09, 0x11, 0x19, 0x21, 0x29, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
            },
            wait_hint = "听：中等国士牌",
        },
        {
            id = "chuuren",
            label = "九莲宝灯",
            tiles14 = {
                0x01, 0x01, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x09, 0x09, 0x09,
            },
            tiles13 = {
                0x01, 0x01, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x09, 0x09,
            },
            wait_hint = "听：九万",
        },
        {
            id = "ryuuiisou",
            label = "绿一色",
            tiles14 = {
                0x22, 0x22, 0x22, 0x23, 0x23, 0x24, 0x24, 0x24, 0x26, 0x26, 0x26, 0x28, 0x28, 0x28,
            },
            tiles13 = {
                0x22, 0x22, 0x22, 0x23, 0x23, 0x24, 0x24, 0x24, 0x26, 0x26, 0x26, 0x28, 0x28,
            },
            wait_hint = "听：8条",
        },
        {
            id = "koukaku",
            label = "红孔雀",
            tiles14 = {
                0x21, 0x21, 0x21, 0x25, 0x25, 0x25, 0x27, 0x27, 0x27, 0x29, 0x29, 0x29, 0x37, 0x37,
            },
            tiles13 = {
                0x21, 0x21, 0x21, 0x25, 0x25, 0x25, 0x27, 0x27, 0x27, 0x29, 0x29, 0x29, 0x37,
            },
            wait_hint = "听：中",
        },
        {
            id = "chinroutou",
            label = "清老头",
            tiles14 = {
                0x01, 0x01, 0x01, 0x09, 0x09, 0x09, 0x11, 0x11, 0x11, 0x19, 0x19, 0x19, 0x21, 0x21,
            },
            tiles13 = {
                0x01, 0x01, 0x01, 0x09, 0x09, 0x09, 0x11, 0x11, 0x11, 0x19, 0x19, 0x19, 0x21,
            },
            wait_hint = "听：1条",
            wait_bcd = { 0x21 },
            key_bcd = { 0x01, 0x09, 0x11, 0x19, 0x21 },
        },
        {
            id = "hyakuman",
            label = "百万石",
            tiles14 = {
                0x05, 0x05, 0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x09, 0x09, 0x09,
            },
            tiles13 = {
                0x05, 0x05, 0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x09, 0x09,
            },
            wait_hint = "听：九万",
        },
        {
            id = "chariot",
            label = "大车轮",
            -- 机内役名为大车轮：二～八筒七对（非万子）
            tiles14 = {
                0x12, 0x12, 0x13, 0x13, 0x14, 0x14, 0x15, 0x15, 0x16, 0x16, 0x17, 0x17, 0x18, 0x18,
            },
            tiles13 = {
                0x12, 0x12, 0x13, 0x13, 0x14, 0x14, 0x15, 0x15, 0x16, 0x16, 0x17, 0x17, 0x18,
            },
            wait_hint = "听：八筒",
        },
        {
            id = "suurenkou",
            label = "四连刻",
            -- 六七八九万四个刻 + 中对（旧 cheat 6789 形胡后机内常显「百万石」）
            tiles14 = {
                0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x09, 0x09, 0x09, 0x37, 0x37,
            },
            tiles13 = {
                0x06, 0x06, 0x06, 0x07, 0x07, 0x07, 0x08, 0x08, 0x08, 0x09, 0x09, 0x09, 0x37,
            },
            wait_hint = "听：中",
        },
        {
            id = "shinkansen",
            label = "东北新干线",
            tiles14 = {
                0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x31, 0x31, 0x31, 0x34, 0x34,
            },
            tiles13 = {
                0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x31, 0x31, 0x31, 0x34,
            },
            wait_hint = "听：北",
        },
        {
            id = "shiisan1",
            label = "十三不搭1",
            -- 147万 + 258筒 + 369条 + 东南西北北（经典探测形）
            tiles14 = {
                0x01, 0x04, 0x07, 0x12, 0x15, 0x18, 0x23, 0x26, 0x29, 0x31, 0x32, 0x33, 0x34, 0x34,
            },
            tiles13 = {
                0x01, 0x04, 0x07, 0x12, 0x15, 0x18, 0x23, 0x26, 0x29, 0x31, 0x32, 0x33, 0x34,
            },
            wait_hint = "人和/自摸（仅首张机会）；电脑=仅天和",
            wait_bcd = {},
            key_bcd = {
                0x01, 0x04, 0x07, 0x12, 0x15, 0x18, 0x23, 0x26, 0x29, 0x31, 0x32, 0x33, 0x34,
            },
            tenhou_only = true,
        },
        {
            id = "shiisan2",
            label = "十三不搭2",
            -- 日麻形：159万 + 26筒 + 37条 + 东南西北中；14 张中成对
            tiles14 = {
                0x01, 0x05, 0x09, 0x12, 0x16, 0x23, 0x27, 0x31, 0x32, 0x33, 0x34, 0x35, 0x37, 0x37,
            },
            tiles13 = {
                0x01, 0x05, 0x09, 0x12, 0x16, 0x23, 0x27, 0x31, 0x32, 0x33, 0x34, 0x35, 0x37,
            },
            wait_hint = "人和/自摸（仅首张机会）；电脑=仅天和",
            wait_bcd = {},
            key_bcd = {
                0x01, 0x05, 0x09, 0x12, 0x16, 0x23, 0x27, 0x31, 0x32, 0x33, 0x34, 0x35, 0x37,
            },
            tenhou_only = true,
        },
    },
}
-- 电脑役满「必和窗」探测：注入后记摸/打，自动标 W0 / S_discard / S_pass / W_retry
local cpu_win_probe = {
    active = false,
    session = 0,
    id = nil,
    label = nil,
    mode = nil,
    first_chance = false,
    complete14 = false,
    tenhou_only = false,
    wait = {},
    key = {},
    saw_skip = false,
    last_draw = nil,
    draw_was_wait = false,
    discard_n = 0,
    coded = false,
    last_n_cpu = nil,
}
-- 控摸提示画在画面顶部（popmessage 居中会挡手牌）
local ui_toast = { lines = nil, frames = 0 }
local listen_accept = {
    on = false,
    tap = nil,
    disc_tap = nil, -- 写 @7502：仅电脑弃牌 PC 窗喂荣（单次）
    disc_riv_tap = nil, -- 写 @7200 河 append：同上
    cpu = nil,
    mach = nil,
    addr = 0x7424,
    aux = 0x7427,
    accept = 0x50,
    -- 默认主版窗；apply_rom_profile 会按机种覆盖
    pc_lo = 0xA260,
    pc_hi = 0xA266,
    seen_pc = {},
    probe_n = 0,
    filter_n = 0,
    post_arm_logs = 0,
    feed_n = 0,
    feed_log_n = 0,
    wait_bcd = nil, -- 透视点电脑手锁定的喂荣牌（单次；打出后清）
    feed_done = false,
    pending_clear_wait = nil,
    feed_pending_was = nil, -- 本次弃牌原值（log）
    feed_fallback_rn = nil,
    feed_sticky = false, -- 已命中弃牌决定后，粘住改写直至 commit
    pending_commit = nil, -- 弃牌 finish PC 后下一帧 commit
    hold = nil, -- 弃牌提交后短时盖河 { wait, was, rn, frames }
    snap_wait_n = nil, -- 锁定时手里 wait 张数（用于打出后对齐）
    hold_tap7502 = nil,
    hold_tap7200 = nil,
    hold_tap_shadow = nil,
    prev_cpu_rn = nil,
    w7502_log_n = 0,
}

-- 听牌可胡：读 @7424 时的 PC 窗（与主版 A260..A266 同宽 7 字节）
-- mjembase: AB57 → AB54..AB5A
-- mjelct3 / mjelct3a: ADF4 → ADF1..ADF7（FILTER armed=Y 多次）
-- mjelctrb: AFF4 → AFF1..AFF7
local ACCEPT_PC_BY_ROM = {
    mjelctrn = { 0xA260, 0xA266 },
    qyjdzjp = { 0xA260, 0xA266 },
    mjelct3b = { 0xA260, 0xA266 },
    mjembase = { 0xAB54, 0xAB5A },
    mjelct3 = { 0xADF1, 0xADF7 },
    mjelct3a = { 0xADF1, 0xADF7 },
    mjelctrb = { 0xAFF1, 0xAFF7 },
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

-- 必须在 listen_accept / force_draw 等之前定义：后面的 local 对早前闭包不可见，会变成全局 nil → pcall 吞错
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

-- 副露扫描须在 local mem 之后定义，否则闭包里的 mem 会落到全局 nil
-- mark：`81`吃 / `82`碰 / `80`–`8F` 其它（杠候选）/ `44` 旧痕迹
function meld.is_mark(v)
    if not v then
        return false
    end
    if v == meld.MARK_ANKAN then
        return true
    end
    return v >= 0x80 and v <= 0x8F
end

function meld.mark_kind(v)
    if v == meld.MARK_CHI then
        return "chi"
    end
    if v == meld.MARK_PON then
        return "pon"
    end
    if v == meld.MARK_KAN then
        return "kan" -- 大明杠或加杠（终态均为 84+三张）
    end
    if v == meld.MARK_ANKAN then
        return "ankan"
    end
    if v and v >= 0x80 and v <= 0x8F then
        return string.format("m%02X", v)
    end
    return "?"
end

function meld.read_blocks(machine, base, scan_len)
    scan_len = scan_len or meld.SCAN_LEN
    local blocks = {}
    if not machine or not base then
        return blocks
    end
    -- 只从表头连续读：遇非 mark 块即停（避免扫进手牌/对调镜像造成「副露2」假阳）
    local i = 0
    while i <= scan_len - 4 do
        local mark = mem.read_u8(machine, base + i)
        if not meld.is_mark(mark) then
            break
        end
        local t1 = mem.read_u8(machine, base + i + 1)
        local t2 = mem.read_u8(machine, base + i + 2)
        local t3 = mem.read_u8(machine, base + i + 3)
        if not (tile_valid(t1) and tile_valid(t2) and tile_valid(t3)) then
            break
        end
        blocks[#blocks + 1] = {
            addr = base + i,
            mark = mark,
            kind = meld.mark_kind(mark),
            tiles = { t1, t2, t3 },
        }
        i = i + 4
    end
    return blocks
end

function meld.format_blocks(blocks)
    if not blocks or #blocks == 0 then
        return "-"
    end
    local parts = {}
    for i = 1, #blocks do
        local b = blocks[i]
        local names = {}
        for j = 1, #b.tiles do
            names[#names + 1] = tile_name(b.tiles[j])
        end
        parts[#parts + 1] = string.format(
            "@%04X%s/%02X[%s]",
            b.addr,
            b.kind or "?",
            b.mark or 0,
            table.concat(names, "")
        )
    end
    return table.concat(parts, " ")
end

-- 吃碰杠后暗手期望张数：13-3n；刚副露尚未打牌时多 1（14-3n）
function meld.expected_closed_n(meld_n, awaiting_discard)
    meld_n = meld_n or 0
    if meld_n < 0 then
        meld_n = 0
    end
    local n = 13 - 3 * meld_n
    if awaiting_discard then
        n = n + 1
    end
    if n < 1 then
        n = 1
    end
    return n
end

-- 由暗手张数反推副露口数（只升不降地校正 meld_count）
function meld.infer_n_from_closed(closed_n, awaiting_discard)
    closed_n = closed_n or 0
    if awaiting_discard then
        if closed_n >= 14 then
            return 0
        end
        if closed_n >= 11 then
            return 1
        end
        if closed_n >= 8 then
            return 2
        end
        if closed_n >= 5 then
            return 3
        end
        return 4
    end
    if closed_n >= 13 then
        return 0
    end
    if closed_n >= 10 then
        return 1
    end
    if closed_n >= 7 then
        return 2
    end
    if closed_n >= 4 then
        return 3
    end
    return 4
end

-- 副露 hunt：dump 已知窗 + 扫 hot 区所有 `44`+三张（事后拍也够用，不要求卡在打牌前）
function meld.dump_hunt(machine, why)
    if not machine then
        return
    end
    local tag = why or "?"
    write_log(string.format("=== [meld-hunt] %s %s ===\n", tag, now()), "a")
    local windows = {
        { "pl@7130", meld.PLAYER_ADDR },
        { "pl@72D0", meld.PLAYER_MIRROR },
        { "cpu@7250", meld.CPU_ADDR },
    }
    for _, w in ipairs(windows) do
        local blocks = meld.read_blocks(machine, w[2], 0x40)
        local hex = {}
        for i = 0, 0x3F do
            local v = mem.read_u8(machine, w[2] + i) or 0
            hex[#hex + 1] = string.format("%02X", v)
        end
        write_log(
            string.format(
                "  %s blocks=%d %s\n  hex: %s\n",
                w[1],
                #blocks,
                meld.format_blocks(blocks),
                table.concat(hex, " ")
            ),
            "a"
        )
    end
    -- 全 hot 扫描：`80`–`8F`/`44` + 三张
    local hits = {}
    for addr = 0x7100, 0x77FC do
        local mark = mem.read_u8(machine, addr)
        if meld.is_mark(mark) then
            local t1 = mem.read_u8(machine, addr + 1)
            local t2 = mem.read_u8(machine, addr + 2)
            local t3 = mem.read_u8(machine, addr + 3)
            if tile_valid(t1) and tile_valid(t2) and tile_valid(t3) then
                hits[#hits + 1] = string.format(
                    "@%04X%s/%02X[%s%s%s]",
                    addr,
                    meld.mark_kind(mark),
                    mark,
                    tile_name(t1),
                    tile_name(t2),
                    tile_name(t3)
                )
            end
        end
    end
    if #hits > 0 then
        write_log("  hot-meld-hits: " .. table.concat(hits, " ") .. "\n", "a")
    else
        write_log("  hot-meld-hits: (none)\n", "a")
    end
end

function listen_accept.clear_ram(machine)
    if not machine then
        return
    end
    mem.write_u8(machine, listen_accept.addr, 0)
    mem.write_u8(machine, listen_accept.aux, 0)
end

function listen_accept.apply_rom_profile(machine)
    local rom = (machine and machine.system and machine.system.name) or ""
    local w = ACCEPT_PC_BY_ROM[rom]
    if w then
        listen_accept.pc_lo = w[1]
        listen_accept.pc_hi = w[2]
    else
        listen_accept.pc_lo = 0xA260
        listen_accept.pc_hi = 0xA266
    end
end

function listen_accept.pc_value(cpu)
    if not cpu or not cpu.state then
        return nil
    end
    local pc = nil
    pcall(function()
        local r = cpu.state["PC"]
        if r then
            pc = r.value
        end
    end)
    return pc
end

function listen_accept.pc_ok(cpu)
    local pc = listen_accept.pc_value(cpu)
    return pc and pc >= listen_accept.pc_lo and pc <= listen_accept.pc_hi
end

-- 可胡开着时记 PC。控摸武装期间对 bank 窗读点逐条打 FILTER（抓换牌否决）。
function listen_accept.probe_note(cpu, hit)
    local pc = listen_accept.pc_value(cpu)
    if not pc then
        return
    end
    local armed = force_draw.armed == true
    local post = (listen_accept.post_arm_logs or 0) > 0
    if (armed or post) and pc >= 0x8000 and listen_accept.filter_n < 60 then
        listen_accept.filter_n = listen_accept.filter_n + 1
        if post and not armed then
            listen_accept.post_arm_logs = listen_accept.post_arm_logs - 1
        end
        write_log(
            string.format(
                "=== [listen-accept-pc] FILTER#%d PC=%04X %s armed=%s window=%04X..%04X ===\n",
                listen_accept.filter_n,
                pc,
                hit and "HIT" or "MISS",
                armed and "Y" or "N",
                listen_accept.pc_lo,
                listen_accept.pc_hi
            ),
            "a"
        )
    end
    if listen_accept.seen_pc[pc] then
        return
    end
    if listen_accept.probe_n >= 40 then
        return
    end
    listen_accept.seen_pc[pc] = true
    listen_accept.probe_n = listen_accept.probe_n + 1
    write_log(
        string.format(
            "=== [listen-accept-pc] #%d PC=%04X %s window=%04X..%04X ===\n",
            listen_accept.probe_n,
            pc,
            hit and "HIT" or "MISS",
            listen_accept.pc_lo,
            listen_accept.pc_hi
        ),
        "a"
    )
end

function listen_accept.probe_reset()
    listen_accept.seen_pc = {}
    listen_accept.probe_n = 0
    listen_accept.filter_n = 0
    listen_accept.post_arm_logs = 0
    listen_accept.w7502_log_n = 0
    -- 勿清 prev_cpu_rn / feed_done：开可胡或探针复位时仍要保持喂荣单次状态
end

function listen_accept.cpu_river_count(machine)
    local n = 0
    for i = 0, DISCARD_HIST_MAX - 1 do
        local v = mem.read_u8(machine, CPU_DISCARD_ADDR + i)
        if not tile_valid(v) then
            break
        end
        n = i + 1
    end
    return n
end

function listen_accept.disc_tap_rm()
    if listen_accept.disc_tap then
        pcall(function()
            listen_accept.disc_tap:remove()
        end)
        listen_accept.disc_tap = nil
    end
end

function listen_accept.disc_riv_tap_rm()
    if listen_accept.disc_riv_tap then
        pcall(function()
            listen_accept.disc_riv_tap:remove()
        end)
        listen_accept.disc_riv_tap = nil
    end
end

function listen_accept.hold_tap_rm()
    if listen_accept.hold_tap7502 then
        pcall(function()
            listen_accept.hold_tap7502:remove()
        end)
        listen_accept.hold_tap7502 = nil
    end
    if listen_accept.hold_tap7200 then
        pcall(function()
            listen_accept.hold_tap7200:remove()
        end)
        listen_accept.hold_tap7200 = nil
    end
    if listen_accept.hold_tap_shadow then
        pcall(function()
            listen_accept.hold_tap_shadow:remove()
        end)
        listen_accept.hold_tap_shadow = nil
    end
end

function listen_accept.disc_taps_rm()
    listen_accept.disc_tap_rm()
    listen_accept.disc_riv_tap_rm()
end

function listen_accept.rom_name()
    local m = listen_accept.mach or (manager and manager.machine)
    return (m and m.system and m.system.name) or ""
end

function listen_accept.is_mjelct3_family()
    local rom = listen_accept.rom_name()
    return rom == "mjelct3" or rom == "mjelct3a"
end

-- 弃牌「可见提交」：主版 9168；mjelct3 9605 / 9627；9644=序列结束（常写 00，勿当牌值改写）
function listen_accept.pc_cpu_discard_finish(cpu)
    local pc = listen_accept.pc_value(cpu)
    if not pc then
        return false
    end
    if pc >= 0x9158 and pc <= 0x9178 then
        return true -- mjelctrn 9168
    end
    if pc >= 0x95F8 and pc <= 0x9610 then
        return true -- mjelct3 9605
    end
    if pc >= 0x9618 and pc <= 0x9630 then
        return true -- mjelct3 9627
    end
    if pc >= 0x9638 and pc <= 0x9650 then
        return true -- mjelct3 9644 结束标记
    end
    return false
end

-- 喂荣新策略（post-discard swap）：
-- 让电脑正常打完（河/手先自洽），再把「河末那张」换成锁定牌，手里锁定牌与原弃牌对调。
-- 不再中途劫持弃牌写（易出现：手里发没了、河里仍是八万）。

-- 画面河/刚打牌常读影子槽，不只 @7200；逻辑河已对时仍可能画面错
function listen_accept.apply_discard_shadow(machine, wait, _was)
    if not machine or not wait then
        return
    end
    for _, addr in ipairs(DISCARD_SHADOW_TILE_ADDRS) do
        mem.write_u8(machine, addr, wait)
    end
end

function listen_accept.snapshot_cpu_river(machine)
    local t = {}
    local n = listen_accept.cpu_river_count(machine)
    for i = 0, n - 1 do
        t[i + 1] = mem.read_u8(machine, CPU_DISCARD_ADDR + i) or 0
    end
    return t
end

-- 河变长时定位「刚打出」那一格：旧→新 append 在末尾；新→旧则在开头
function listen_accept.detect_new_discard(machine, rn, prev_bytes)
    local last = mem.read_u8(machine, CPU_DISCARD_ADDR + rn - 1) or 0
    if not prev_bytes or #prev_bytes + 1 ~= rn then
        return rn, last
    end
    local prefix_ok = true
    for i = 1, #prev_bytes do
        if (mem.read_u8(machine, CPU_DISCARD_ADDR + i - 1) or 0) ~= prev_bytes[i] then
            prefix_ok = false
            break
        end
    end
    if prefix_ok then
        return rn, last
    end
    local first = mem.read_u8(machine, CPU_DISCARD_ADDR) or 0
    local suffix_ok = true
    for i = 1, #prev_bytes do
        if (mem.read_u8(machine, CPU_DISCARD_ADDR + i) or 0) ~= prev_bytes[i] then
            suffix_ok = false
            break
        end
    end
    if suffix_ok then
        return 1, first
    end
    return rn, last
end

-- 电脑已打完：先只改「刚打出」那一格并护住；真稳定后再改手
function listen_accept.commit_feed(machine, was, why, rn_slot)
    local wait = listen_accept.wait_bcd
    if not wait or not machine or listen_accept.hold or listen_accept.feed_done then
        return
    end
    local rn = listen_accept.cpu_river_count(machine)
    if rn < 1 then
        rn = listen_accept.feed_fallback_rn or 1
    end
    local slot = rn_slot or rn
    if slot < 1 then
        slot = rn
    end
    was = was or 0
    if was == 0 then
        was = mem.read_u8(machine, CPU_DISCARD_ADDR + slot - 1) or 0
    end

    -- 副露后 RAM 手常空，锁定可能只在透视缓存里：仍改河/@7502 供吃碰，手在 hold 里对齐
    local has_live = listen_accept.count_bcd_in_hand(machine, wait) > 0
    local has_cache = listen_accept.count_bcd_in_cache(wait) > 0
    if was ~= wait and not has_live and not has_cache then
        write_log(
            string.format(
                "=== [listen-accept-feed] WARN no_wait_live/cache was=%02X wait=%02X（仍改河） %s ===\n",
                was,
                wait,
                now()
            ),
            "a"
        )
    end

    local snap_w = listen_accept.snap_wait_n or 0
    if snap_w < 1 then
        snap_w = has_live and listen_accept.count_bcd_in_hand(machine, wait)
            or listen_accept.count_bcd_in_cache(wait)
        if snap_w < 1 then
            snap_w = 1
        end
    end

    mem.write_u8(machine, TABLE_TILE_ADDR, wait)
    mem.write_u8(machine, CPU_DISCARD_ADDR + slot - 1, wait)
    listen_accept.apply_discard_shadow(machine, wait, was)

    listen_accept.hold = {
        wait = wait,
        was = was,
        rn = rn,
        rn_slot = slot,
        frames = 120,
        phase = "river",
        stable = 0,
        rewrites = 0,
        swapped = false,
        snap_wait_n = snap_w,
        why = why or "commit",
    }
    listen_accept.disc_taps_rm()
    listen_accept.hold_tap_install(machine)
    listen_accept.feed_sticky = false
    write_log(
        string.format(
            "=== [listen-accept-feed] HOLD-RIVER was=%02X wait=%02X rn=%d slot=%d snapW=%d live=%s cache=%s why=%s %s ===\n",
            was,
            wait,
            rn,
            slot,
            snap_w,
            has_live and "Y" or "N",
            has_cache and "Y" or "N",
            why or "?",
            now()
        ),
        "a"
    )
end

function listen_accept.apply_hold_writes(machine)
    local h = listen_accept.hold
    if not h or not machine or not h.wait then
        return
    end
    local slot = h.rn_slot or h.rn or 1
    if slot >= 1 then
        mem.write_u8(machine, CPU_DISCARD_ADDR + slot - 1, h.wait)
    end
    listen_accept.apply_discard_shadow(machine, h.wait, h.was)
end

function listen_accept.tick_hold(machine)
    local h = listen_accept.hold
    if not h or not machine then
        return
    end
    local slot = h.rn_slot or h.rn or 1
    local addr = CPU_DISCARD_ADDR + slot - 1
    -- 先读再写：避免自己写完再读造成假 stable
    local river = mem.read_u8(machine, addr)
    if river == h.wait then
        h.stable = (h.stable or 0) + 1
        -- 逻辑河已对时仍刷新画面影子（吃碰判定看 @7502/@7200，画面看影子）
        listen_accept.apply_discard_shadow(machine, h.wait, h.was)
        if mem.read_u8(machine, TABLE_TILE_ADDR) ~= h.wait then
            mem.write_u8(machine, TABLE_TILE_ADDR, h.wait)
        end
    else
        h.stable = 0
        h.rewrites = (h.rewrites or 0) + 1
        mem.write_u8(machine, addr, h.wait)
        listen_accept.apply_discard_shadow(machine, h.wait, h.was)
        if mem.read_u8(machine, TABLE_TILE_ADDR) ~= h.wait then
            mem.write_u8(machine, TABLE_TILE_ADDR, h.wait)
        end
    end

    -- 河稳住后每帧对手（含 phase=done），直到 hold 结束，防机盖回锁定牌
    if (h.stable or 0) >= 12 then
        local need = h.was and h.was ~= 0 and h.was ~= h.wait
        if need then
            if not listen_accept.hand_feed_synced(machine, h.wait, h.was, h.snap_wait_n) then
                if listen_accept.swap_hand_after_river(machine, h.wait, h.was) then
                    h.swapped = true
                end
            else
                h.swapped = true
            end
        else
            h.swapped = true
        end
        if h.phase ~= "done"
            and (
                listen_accept.hand_feed_synced(machine, h.wait, h.was, h.snap_wait_n)
                or not need
            )
        then
            if h.phase ~= "hand_ok" then
                h.phase = "hand_ok"
                write_log(
                    string.format(
                        "=== [listen-accept-feed] HAND-SWAP was=%02X wait=%02X sync=Y slot=%d stable=%d snapW=%d %s ===\n",
                        h.was or 0,
                        h.wait,
                        slot,
                        h.stable or 0,
                        h.snap_wait_n or 0,
                        now()
                    ),
                    "a"
                )
            end
            -- 再护几帧手/河后收尾
            if (h.stable or 0) >= 24 then
                h.phase = "done"
                listen_accept.mark_feed_done(h.why or "river_stable", h.was, h.wait)
            end
        end
    end

    h.frames = (h.frames or 0) - 1
    if h.frames >= 0 then
        return
    end

    listen_accept.hold_tap_rm()
    river = mem.read_u8(machine, addr)
    -- 超时仍尽量再对手一次
    if h.phase ~= "done" then
        if h.was and h.was ~= 0 and h.was ~= h.wait then
            listen_accept.swap_hand_after_river(machine, h.wait, h.was)
            h.swapped = listen_accept.hand_feed_synced(machine, h.wait, h.was, h.snap_wait_n)
                or h.swapped
        end
        listen_accept.mark_feed_done(
            h.swapped and (h.why or "timeout_ok") or "timeout_hand",
            h.was,
            h.wait
        )
        write_log(
            string.format(
                "=== [listen-accept-feed] HAND-SWAP was=%02X wait=%02X sync=%s slot=%d stable=%d rewrites=%d (timeout) %s ===\n",
                h.was or 0,
                h.wait,
                h.swapped and "Y" or "N",
                slot,
                h.stable or 0,
                h.rewrites or 0,
                now()
            ),
            "a"
        )
    end
    if river ~= h.wait and h.swapped then
        if h.was and h.was ~= 0 and h.was ~= h.wait then
            if listen_accept.count_bcd_in_hand(machine, h.was) > 0
                and listen_accept.count_bcd_in_hand(machine, h.wait) < 1
            then
                listen_accept.remove_one_bcd(machine, h.was)
                listen_accept.add_one_bcd(machine, h.wait)
                listen_accept.pack_cpu_hand(machine)
            end
        end
        ui_toast.show("喂荣河牌被改回，已恢复手牌", 220)
        write_log(
            string.format(
                "=== [listen-accept-feed] REVERT-HAND river_back=%02X wait=%02X %s ===\n",
                river or 0,
                h.wait,
                now()
            ),
            "a"
        )
    elseif river ~= h.wait then
        ui_toast.show(
            string.format(
                "喂荣未稳住：河仍是 %s\n目标 %s",
                tile_name(river or 0),
                tile_name(h.wait)
            ),
            260
        )
        write_log(
            string.format(
                "=== [listen-accept-feed] FAIL river=%02X wait=%02X slot=%d rewrites=%d %s ===\n",
                river or 0,
                h.wait,
                slot,
                h.rewrites or 0,
                now()
            ),
            "a"
        )
    end
    listen_accept.hold = nil
end

function listen_accept.hand_count_at(machine, base)
    local n = 0
    if not machine or not base then
        return 0
    end
    for i = 0, CPU_HAND_MAX - 1 do
        if tile_valid(mem.read_u8(machine, base + i)) then
            n = n + 1
        end
    end
    return n
end

function listen_accept.read_hand_contig(machine, base)
    local raws = {}
    if not machine or not base then
        return raws
    end
    for i = 0, CPU_HAND_MAX - 1 do
        local v = mem.read_u8(machine, base + i)
        if not tile_valid(v) then
            break
        end
        raws[#raws + 1] = v
    end
    return raws
end

function listen_accept.multiset_overlap(a, b)
    local mb = {}
    for _, v in ipairs(b or {}) do
        mb[v] = (mb[v] or 0) + 1
    end
    local n = 0
    for _, v in ipairs(a or {}) do
        local c = mb[v] or 0
        if c > 0 then
            n = n + 1
            mb[v] = c - 1
        end
    end
    return n
end

-- 副露时工作区常把玩家手拷进 @7100/@77C0：同长且多重集合完全一致才判串台
function listen_accept.raw_looks_like_player(machine, raws)
    if not machine or not raws or #raws < 5 then
        return false
    end
    for _, addr in ipairs(PLAYER_HAND_MIRRORS) do
        local pl = listen_accept.read_hand_contig(machine, addr)
        if #pl >= 5 and #pl == #raws then
            local ov = listen_accept.multiset_overlap(raws, pl)
            if ov == #raws then
                return true
            end
        end
    end
    return false
end

function listen_accept.base_looks_like_player(machine, base)
    return listen_accept.raw_looks_like_player(
        machine,
        listen_accept.read_hand_contig(machine, base)
    )
end

-- 副露后 @7240 常空：取可信电脑镜像（拒玩家串台），勿只按「张数最多」
function listen_accept.live_cpu_hand_base(machine)
    local best, best_score = CPU_HAND_ADDR, -1
    if not machine then
        return best, 0
    end
    for _, base in ipairs(CPU_HAND_FALLBACKS) do
        local raws = listen_accept.read_hand_contig(machine, base)
        if #raws > 0 and not listen_accept.raw_looks_like_player(machine, raws) then
            local score = #raws * 10 + (CPU_HAND_PRIO[base] or 0)
            if score > best_score then
                best, best_score = base, score
            end
        end
    end
    if best_score < 0 then
        return CPU_HAND_ADDR, 0
    end
    return best, listen_accept.hand_count_at(machine, best)
end

function listen_accept.count_bcd_in_hand(machine, bcd)
    local n = 0
    if not machine or not bcd then
        return 0
    end
    -- 只数可信电脑镜像（拷贝取 max，勿累加；串台缓冲不计）
    for _, base in ipairs(CPU_HAND_FALLBACKS) do
        if not listen_accept.base_looks_like_player(machine, base) then
            local c = 0
            for i = 0, CPU_HAND_MAX - 1 do
                if mem.read_u8(machine, base + i) == bcd then
                    c = c + 1
                end
            end
            if c > n then
                n = c
            end
        end
    end
    return n
end

function listen_accept.count_bcd_in_cache(bcd)
    local n = 0
    if not bcd then
        return 0
    end
    local raw = (cpu_hand_trusted.raw and #cpu_hand_trusted.raw > 0)
            and cpu_hand_trusted.raw
        or cpu_hand_cache.raw
    if not raw then
        return 0
    end
    for _, v in ipairs(raw) do
        if v == bcd then
            n = n + 1
        end
    end
    return n
end

function listen_accept.hand_has_at(machine, base, bcd)
    if not machine or not base or not bcd then
        return false
    end
    for i = 0, CPU_HAND_MAX - 1 do
        if mem.read_u8(machine, base + i) == bcd then
            return true
        end
    end
    return false
end

-- 优先：含该牌且张数最多的可信镜像（拒玩家串台）
function listen_accept.find_hand_base_with(machine, bcd)
    local best, best_n = nil, -1
    if not machine or not bcd then
        return nil
    end
    for _, base in ipairs(CPU_HAND_FALLBACKS) do
        if not listen_accept.base_looks_like_player(machine, base)
            and listen_accept.hand_has_at(machine, base, bcd)
        then
            local n = listen_accept.hand_count_at(machine, base)
            if n > best_n then
                best, best_n = base, n
            end
        end
    end
    return best
end

function listen_accept.remove_one_bcd(machine, bcd)
    local base = listen_accept.find_hand_base_with(machine, bcd)
        or listen_accept.live_cpu_hand_base(machine)
    for i = 0, CPU_HAND_MAX - 1 do
        local addr = base + i
        if mem.read_u8(machine, addr) == bcd then
            mem.write_u8(machine, addr, 0)
            return true
        end
    end
    return false
end

function listen_accept.add_one_bcd(machine, bcd)
    if not tile_valid(bcd) then
        return false
    end
    local base = listen_accept.live_cpu_hand_base(machine)
    for i = 0, CPU_HAND_MAX - 1 do
        local addr = base + i
        if not tile_valid(mem.read_u8(machine, addr)) then
            mem.write_u8(machine, addr, bcd)
            return true
        end
    end
    return false
end

function listen_accept.pack_cpu_hand(machine, base)
    if not FEED_MUTATE_CPU_HAND then
        return
    end
    if not machine then
        return
    end
    base = base or listen_accept.live_cpu_hand_base(machine)
    local writable = false
    for _, a in ipairs(CPU_HAND_WRITABLE) do
        if a == base then
            writable = true
            break
        end
    end
    if not writable then
        return
    end
    local tiles = {}
    for i = 0, CPU_HAND_MAX - 1 do
        local v = mem.read_u8(machine, base + i)
        if tile_valid(v) then
            tiles[#tiles + 1] = v
        end
    end
    table.sort(tiles)
    if listen_accept.raw_looks_like_player(machine, tiles) then
        write_log(
            string.format(
                "=== [cpu-hand] skip-pack player-like @%04X n=%d %s ===\n",
                base,
                #tiles,
                now()
            ),
            "a"
        )
        return
    end
    for i = 0, CPU_HAND_MAX - 1 do
        mem.write_u8(machine, base + i, tiles[i + 1] or 0)
    end
    for _, dst in ipairs(CPU_HAND_WRITABLE) do
        if dst ~= base then
            for i = 0, CPU_HAND_MAX - 1 do
                mem.write_u8(machine, dst + i, mem.read_u8(machine, base + i))
            end
        end
    end
    cpu_hand_cache = { raw = tiles, src = base }
    cpu_hand_trusted = { raw = tiles, src = base }
    cpu_hand_src_addr = base
end

function listen_accept.patch_cpu_hand_cache(wait, was)
    local function patch_raw(raw)
        if not raw or #raw < 1 or not wait then
            return false
        end
        for i, v in ipairs(raw) do
            if v == wait then
                if was and was ~= 0 and was ~= wait and tile_valid(was) then
                    raw[i] = was
                else
                    table.remove(raw, i)
                end
                return true
            end
        end
        return false
    end
    local ok = patch_raw(cpu_hand_trusted.raw)
    if cpu_hand_cache.raw and cpu_hand_cache.raw ~= cpu_hand_trusted.raw then
        ok = patch_raw(cpu_hand_cache.raw) or ok
    end
    return ok
end

function listen_accept.add_one_to_cache(bcd)
    if not bcd or not tile_valid(bcd) then
        return false
    end
    local function add(raw)
        if not raw then
            return false
        end
        if #raw >= CPU_HAND_MAX then
            return false
        end
        raw[#raw + 1] = bcd
        return true
    end
    local ok = add(cpu_hand_trusted.raw)
    if cpu_hand_cache.raw and cpu_hand_cache.raw ~= cpu_hand_trusted.raw then
        add(cpu_hand_cache.raw)
    elseif ok and (not cpu_hand_cache.raw or #cpu_hand_cache.raw < 1) then
        cpu_hand_cache = {
            raw = cpu_hand_trusted.raw,
            src = cpu_hand_trusted.src,
        }
    end
    return ok
end

-- 副露缓存下电脑打牌：
-- 摸切 → 不动；手切 → 先补本巡摸入再扣弃牌；碰/吃后必打 → 只扣弃牌
function listen_accept.patch_cache_after_cpu_discard(disc, table_v)
    if not disc or not tile_valid(disc) then
        return false
    end
    local raw = cpu_hand_trusted.raw
    if not raw or #raw < 1 then
        return false
    end
    local pending = cpu_hand_trusted.pending_draw
    local no_draw = cpu_hand_trusted.no_draw_discard
    local in_hand = listen_accept.count_in_list(raw, disc) > 0
    -- 碰/吃后必打：优先于摸切；弃牌必须在手里才扣（勿乱删末张，曾扣到只剩 5/1）
    if no_draw then
        if not in_hand then
            cpu_hand_trusted.after_meld_miss = (cpu_hand_trusted.after_meld_miss or 0) + 1
            write_log(
                string.format(
                    "=== [peek-hand] discard after-meld-wait=%02X trust=%d miss=%d %s ===\n",
                    disc,
                    #raw,
                    cpu_hand_trusted.after_meld_miss or 0,
                    now()
                ),
                "a"
            )
            -- 连续错过：多半是假副露/已打过，清 no_draw 以免一直不更新、再被 force 扣穿
            if (cpu_hand_trusted.after_meld_miss or 0) >= 2 then
                cpu_hand_trusted.no_draw_discard = false
                cpu_hand_trusted.after_meld_miss = 0
                cpu_hand_trusted.pending_draw = nil
                write_log(
                    string.format(
                        "=== [peek-hand] no_draw clear after-miss trust=%d %s ===\n",
                        #raw,
                        now()
                    ),
                    "a"
                )
            end
            return false
        end
        listen_accept.mark_stale_before_patch()
        listen_accept.remove_n_from_cache(disc, 1)
        cpu_hand_trusted.no_draw_discard = false
        cpu_hand_trusted.pending_draw = nil
        cpu_hand_trusted.after_meld_miss = 0
        write_log(
            string.format(
                "=== [peek-hand] discard after-meld=%02X trust=%d %s ===\n",
                disc,
                cpu_hand_trusted.raw and #cpu_hand_trusted.raw or 0,
                now()
            ),
            "a"
        )
        return true
    end
    -- 摸切：弃牌不在缓存，或 pending 摸入就是这张（含「手里已有同种再摸切」）
    if (not in_hand) or (pending and pending == disc) then
        cpu_hand_trusted.pending_draw = nil
        write_log(
            string.format(
                "=== [peek-hand] discard tsumogiri=%02X in_hand=%s trust=%d %s ===\n",
                disc,
                in_hand and "Y" or "N",
                #raw,
                now()
            ),
            "a"
        )
        return true
    end
    -- 手切：必须有摸入证据，否则不扣（漏记摸入时曾越打越少 → 10 变 6）
    local draw = pending
    if (not draw or draw == disc) and table_v and tile_valid(table_v) and table_v ~= disc then
        draw = table_v
    end
    if not (draw and tile_valid(draw) and draw ~= disc) then
        cpu_hand_trusted.pending_draw = nil
        write_log(
            string.format(
                "=== [peek-hand] discard keep=%02X no-draw-ev trust=%d %s ===\n",
                disc,
                #raw,
                now()
            ),
            "a"
        )
        return true
    end
    listen_accept.mark_stale_before_patch()
    listen_accept.add_one_to_cache(draw)
    listen_accept.remove_n_from_cache(disc, 1)
    cpu_hand_trusted.pending_draw = nil
    write_log(
        string.format(
            "=== [peek-hand] discard tedashi disc=%02X draw=%02X trust=%d %s ===\n",
            disc,
            draw,
            cpu_hand_trusted.raw and #cpu_hand_trusted.raw or 0,
            now()
        ),
        "a"
    )
    return true
end

function listen_accept.remove_n_from_cache(bcd, n)
    n = n or 1
    if not bcd or n < 1 then
        return 0
    end
    local function rm(raw, left)
        if not raw then
            return 0
        end
        local i = 1
        local did = 0
        while i <= #raw and did < left do
            if raw[i] == bcd then
                table.remove(raw, i)
                did = did + 1
            else
                i = i + 1
            end
        end
        return did
    end
    local a = rm(cpu_hand_trusted.raw, n)
    if cpu_hand_cache.raw and cpu_hand_cache.raw ~= cpu_hand_trusted.raw then
        rm(cpu_hand_cache.raw, n)
    end
    return a
end

-- @7250 口数已增但「河缩/世代」没抓到 → 暗手卡在旧张数（典型：副露1 后一直 10）
function listen_accept.align_trust_to_cpu_melds(machine, ram_n, awaiting_discard, why)
    ram_n = ram_n or 0
    local raw = cpu_hand_trusted.raw
    if not raw or #raw < 1 or ram_n < 1 then
        return false
    end
    local target = meld.expected_closed_n(ram_n, awaiting_discard)
    if #raw <= target then
        cpu_hand_trusted.meld_count = ram_n
        local gen = cpu_hand_trusted.pl_discard_gen or 0
        if gen >= 1 then
            cpu_hand_trusted.meld_at_gen = gen
        end
        return false
    end
    local need = #raw - target
    local claim = cpu_hand_trusted.last_pl_discard
    local blocks = meld.read_blocks(machine, meld.CPU_ADDR)
    if blocks and #blocks > 0 then
        local b = blocks[#blocks]
        if b.tiles and b.tiles[1] then
            if b.kind == "pon" or b.kind == "kan" or b.kind == "ankan" then
                claim = b.tiles[1]
            elseif not (claim and listen_accept.count_in_list(b.tiles, claim) > 0) then
                claim = b.tiles[1]
            end
        end
    end
    listen_accept.mark_stale_before_patch()
    local removed = 0
    if claim and tile_valid(claim) then
        removed = listen_accept.remove_n_from_cache(claim, math.min(need, 2))
    end
    while removed < need and cpu_hand_trusted.raw and #cpu_hand_trusted.raw > target do
        table.remove(cpu_hand_trusted.raw)
        if cpu_hand_cache.raw and cpu_hand_cache.raw ~= cpu_hand_trusted.raw then
            if #cpu_hand_cache.raw > 0 then
                table.remove(cpu_hand_cache.raw)
            end
        end
        removed = removed + 1
    end
    if cpu_hand_cache.raw == nil or cpu_hand_cache.raw == cpu_hand_trusted.raw then
        cpu_hand_cache = {
            raw = cpu_hand_trusted.raw,
            src = cpu_hand_trusted.src,
        }
    end
    cpu_hand_trusted.meld_count = ram_n
    if awaiting_discard then
        cpu_hand_trusted.no_draw_discard = true
        cpu_hand_trusted.pending_draw = nil
    end
    -- 标记本世代已扣过，避免下一帧 cpu-meld 再 force-shrink（曾 13→11→9→8）
    local gen = cpu_hand_trusted.pl_discard_gen or 0
    if gen >= 1 then
        cpu_hand_trusted.meld_at_gen = gen
    end
    write_log(
        string.format(
            "=== [peek-hand] align-meld ram=%d rem=%d trust=%d expect=%d await=%s why=%s %s ===\n",
            ram_n,
            removed,
            cpu_hand_trusted.raw and #cpu_hand_trusted.raw or 0,
            target,
            awaiting_discard and "Y" or "N",
            why or "-",
            now()
        ),
        "a"
    )
    return removed > 0
end

function listen_accept.count_in_list(raw, bcd)
    local c = 0
    for _, v in ipairs(raw or {}) do
        if v == bcd then
            c = c + 1
        end
    end
    return c
end

-- 吃：从缓存去掉能与 claimed 组成顺子的两张
function listen_accept.remove_chi_partners_from_raw(raw, claimed)
    if not raw or not claimed then
        return false
    end
    local suit = claimed & 0xF0
    local n = claimed & 0x0F
    if suit > 0x20 or n < 1 or n > 9 then
        return false
    end
    local cands = {}
    if n >= 3 then
        cands[#cands + 1] = { suit + (n - 2), suit + (n - 1) }
    end
    if n >= 2 and n <= 8 then
        cands[#cands + 1] = { suit + (n - 1), suit + (n + 1) }
    end
    if n <= 7 then
        cands[#cands + 1] = { suit + (n + 1), suit + (n + 2) }
    end
    for _, pair in ipairs(cands) do
        local a, b = pair[1], pair[2]
        if listen_accept.count_in_list(raw, a) >= 1
            and listen_accept.count_in_list(raw, b) >= 1
        then
            local function rm1(t)
                for i, v in ipairs(raw) do
                    if v == t then
                        table.remove(raw, i)
                        return true
                    end
                end
                return false
            end
            return rm1(a) and rm1(b)
        end
    end
    return false
end

-- 电脑吃/碰玩家河牌后：暗手先少 2 张（碰后还要打牌再到 10）
-- 绝不因手里有 3 张同牌就当杠扣 3——会变成暗手少 1（10 显示成 9）
-- 去重用「玩家弃牌世代」：同一口弃牌只扣一次；河长偶然相同也不会挡住下一口吃
function listen_accept.can_meld_claim(claimed)
    local raw = cpu_hand_trusted.raw
    if not raw or not claimed or not tile_valid(claimed) then
        return false, nil
    end
    if listen_accept.count_in_list(raw, claimed) >= 2 then
        return true, "pon"
    end
    -- 试算吃：复制后再扣，不改真缓存
    local copy = {}
    for i, v in ipairs(raw) do
        copy[i] = v
    end
    if listen_accept.remove_chi_partners_from_raw(copy, claimed) then
        return true, "chi"
    end
    return false, nil
end

function listen_accept.patch_cache_after_cpu_meld(machine, claimed)
    if not claimed or not tile_valid(claimed) then
        return false
    end
    local raw = cpu_hand_trusted.raw
    -- 两口后暗手可到 7；三口到 4。按当前副露数放宽下限
    local meld_n = cpu_hand_trusted.meld_count or 0
    local min_raw = (meld_n >= 2) and 4 or 7
    local ram_n = 0
    if machine then
        ram_n = #meld.read_blocks(machine, meld.CPU_ADDR)
        if ram_n >= 2 then
            min_raw = 4
        elseif ram_n >= 1 and meld_n >= 1 then
            min_raw = 4
        end
    end
    if not raw or #raw < min_raw then
        return false
    end
    -- @7250 尚无块：多半是河缩误判，绝不能 force 扣缓存（曾 ram=0 连扣到只剩 1～2 张）
    if ram_n < 1 then
        write_log(
            string.format(
                "=== [peek-hand] cpu-meld skip no-ram claim=%02X trust=%d %s ===\n",
                claimed,
                #raw,
                now()
            ),
            "a"
        )
        return false
    end
    local gen = cpu_hand_trusted.pl_discard_gen or 0
    if gen < 1 then
        return false
    end
    -- align-meld 已按 RAM 扣过 → 只补标记，禁止再 force-shrink（曾 13→11→9→8）
    if ram_n >= 1 then
        local exp_await = meld.expected_closed_n(ram_n, true)
        local exp_done = meld.expected_closed_n(ram_n, false)
        if #raw <= exp_await then
            cpu_hand_trusted.meld_count = ram_n
            cpu_hand_trusted.meld_at_gen = gen
            if #raw > exp_done then
                cpu_hand_trusted.no_draw_discard = true
                cpu_hand_trusted.pending_draw = nil
            end
            write_log(
                string.format(
                    "=== [peek-hand] cpu-meld skip already-aligned claim=%02X trust=%d ram=%d exp=%d %s ===\n",
                    claimed,
                    #raw,
                    ram_n,
                    exp_await,
                    now()
                ),
                "a"
            )
            return false
        end
    end
    if cpu_hand_trusted.meld_at_gen == gen then
        write_log(
            string.format(
                "=== [peek-hand] cpu-meld skip same-gen=%d claim=%02X trust=%d %s ===\n",
                gen,
                claimed,
                #raw,
                now()
            ),
            "a"
        )
        if ram_n >= 1 and #raw > meld.expected_closed_n(ram_n, true) then
            return listen_accept.align_trust_to_cpu_melds(
                machine,
                ram_n,
                true,
                "same-gen-oversize"
            )
        end
        return false
    end
    local can, kind = listen_accept.can_meld_claim(claimed)
    listen_accept.mark_stale_before_patch()
    local removed = 0
    if can and kind == "pon" then
        removed = listen_accept.remove_n_from_cache(claimed, 2)
    elseif can then
        local ok = listen_accept.remove_chi_partners_from_raw(cpu_hand_trusted.raw, claimed)
        if ok and cpu_hand_cache.raw and cpu_hand_cache.raw ~= cpu_hand_trusted.raw then
            listen_accept.remove_chi_partners_from_raw(cpu_hand_cache.raw, claimed)
        elseif ok then
            cpu_hand_cache = {
                raw = cpu_hand_trusted.raw,
                src = cpu_hand_trusted.src,
            }
        end
        if ok then
            removed = 2
        end
    end
    -- 第二口常认不出吃碰组合，但台面已副露：强制暗手 -2；勿扣穿期望张数
    if removed < 2 and #raw >= min_raw then
        local expect_cap = meld.expected_closed_n(
            ram_n > 0 and ram_n or (meld_n + 1),
            true
        )
        local have = listen_accept.count_in_list(raw, claimed)
        if have >= 1 then
            removed = listen_accept.remove_n_from_cache(claimed, math.min(2, have))
        end
        while removed < 2
            and cpu_hand_trusted.raw
            and #cpu_hand_trusted.raw > expect_cap
        do
            table.remove(cpu_hand_trusted.raw)
            if cpu_hand_cache.raw and cpu_hand_cache.raw ~= cpu_hand_trusted.raw then
                if #cpu_hand_cache.raw > 0 then
                    table.remove(cpu_hand_cache.raw)
                end
            end
            removed = removed + 1
        end
        if cpu_hand_cache.raw == nil or cpu_hand_cache.raw == cpu_hand_trusted.raw then
            cpu_hand_cache = {
                raw = cpu_hand_trusted.raw,
                src = cpu_hand_trusted.src,
            }
        end
        kind = can and kind or "force"
        write_log(
            string.format(
                "=== [peek-hand] cpu-meld force-shrink claim=%02X rem=%d trust=%d cap=%d %s ===\n",
                claimed,
                removed,
                cpu_hand_trusted.raw and #cpu_hand_trusted.raw or 0,
                expect_cap,
                now()
            ),
            "a"
        )
    end
    if removed > 0 then
        cpu_hand_trusted.meld_at_gen = gen
        -- 碰/吃后必打一张，本巡无摸
        cpu_hand_trusted.no_draw_discard = true
        cpu_hand_trusted.pending_draw = nil
        -- @7250 常已先写入：以 RAM 块数为准，避免 soft-sync 后再 +1 变成「副露2」
        if ram_n > 0 then
            cpu_hand_trusted.meld_count = ram_n
        else
            cpu_hand_trusted.meld_count = (cpu_hand_trusted.meld_count or 0) + 1
        end
        write_log(
            string.format(
                "=== [peek-hand] cpu-meld %s claim=%02X rem=%d trust=%d meld_n=%d ram=%d expect=%d gen=%d why=%s %s ===\n",
                kind or "?",
                claimed,
                removed,
                cpu_hand_trusted.raw and #cpu_hand_trusted.raw or 0,
                cpu_hand_trusted.meld_count or 0,
                ram_n,
                meld.expected_closed_n(
                    cpu_hand_trusted.meld_count,
                    true
                ),
                gen,
                listen_accept._peek_meld_why or "-",
                now()
            ),
            "a"
        )
        return true
    end
    write_log(
        string.format(
            "=== [peek-hand] cpu-meld fail claim=%02X trust=%d gen=%d %s ===\n",
            claimed,
            #raw,
            gen,
            now()
        ),
        "a"
    )
    return false
end

-- 扣牌前记下「扣之前的样子」：之后实读若仍等于它，说明镜像没跟上，勿撑回去
function listen_accept.mark_stale_before_patch()
    local raw = cpu_hand_trusted.raw
    if not raw or #raw < 1 then
        return
    end
    local copy = {}
    for i, v in ipairs(raw) do
        copy[i] = v
    end
    cpu_hand_trusted.stale = copy
end

-- 新局：两家河都空 → 丢弃上一局残留缓存（否则新局 13 张会被旧短缓存挡住）
function listen_accept.reset_cpu_hand_cache(why)
    local had = cpu_hand_trusted.raw and #cpu_hand_trusted.raw or 0
    cpu_hand_trusted = { raw = {}, src = nil }
    cpu_hand_cache = { raw = {}, src = nil }
    cpu_hand_src_addr = nil
    if had > 0 then
        write_log(
            string.format(
                "=== [peek-hand] reset why=%s had=%d %s ===\n",
                why or "?",
                had,
                now()
            ),
            "a"
        )
    end
end

function listen_accept.multiset_is_subset(small, big)
    if not small or not big then
        return false
    end
    local mb = {}
    for _, v in ipairs(big) do
        mb[v] = (mb[v] or 0) + 1
    end
    for _, v in ipairs(small) do
        local c = mb[v] or 0
        if c < 1 then
            return false
        end
        mb[v] = c - 1
    end
    return true
end

function listen_accept.multiset_equal_lists(a, b)
    if not a or not b or #a ~= #b or #a < 1 then
        return false
    end
    return listen_accept.multiset_overlap(a, b) == #a
end

-- 河已是 wait：把手里一张 wait 原地换成 was（机已扣 was / 尚未扣都行）
function listen_accept.swap_hand_after_river(machine, wait, was)
    if not wait or not was or was == 0 or was == wait then
        return false
    end
    if not tile_valid(was) then
        return false
    end
    -- 副露透视优先：只改显示缓存，不写 RAM
    if not FEED_MUTATE_CPU_HAND then
        return listen_accept.patch_cpu_hand_cache(wait, was)
    end
    if not machine then
        return false
    end
    local base = listen_accept.find_hand_base_with(machine, wait)
    if base then
        for i = 0, CPU_HAND_MAX - 1 do
            local addr = base + i
            if mem.read_u8(machine, addr) == wait then
                mem.write_u8(machine, addr, was)
                listen_accept.pack_cpu_hand(machine, base)
                return true
            end
        end
    end
    return listen_accept.patch_cpu_hand_cache(wait, was)
end

function listen_accept.swap_hand_for_feed(machine, wait, was)
    return listen_accept.swap_hand_after_river(machine, wait, was)
end

-- 目标：锁定牌张数降到 snap_wait_n-1（通常从 1→0）
function listen_accept.hand_feed_synced(machine, wait, was, snap_wait_n)
    if not wait then
        return true
    end
    local want = math.max(0, (snap_wait_n or 1) - 1)
    local live_n = listen_accept.count_bcd_in_hand(machine, wait)
    local cache_n = listen_accept.count_bcd_in_cache(wait)
    -- 有 live 手时以 live 为准；全空才看缓存
    local _, live_total = listen_accept.live_cpu_hand_base(machine)
    if live_total > 0 then
        return live_n <= want
    end
    return cache_n <= want
end

function listen_accept.sort_cpu_hands(_machine)
end

function listen_accept.sync_cpu_hand_mirrors(_machine)
end

function listen_accept.hold_tap_install(machine)
    listen_accept.hold_tap_rm()
    local h = listen_accept.hold
    if not h or not machine then
        return false
    end
    local cpu = machine.devices and machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space or not space.install_write_tap then
        return false
    end
    local slot = h.rn_slot or h.rn or 1
    if slot >= 1 then
        local river_addr = CPU_DISCARD_ADDR + slot - 1
        local ok2, t2 = pcall(function()
            return space:install_write_tap(
                river_addr,
                river_addr,
                "fei_feed_hold7200",
                function(_offset, data, _mask)
                    local hh = listen_accept.hold
                    if not hh or not hh.wait then
                        return
                    end
                    if ((data or 0) & 0xFF) == hh.wait then
                        return
                    end
                    return hh.wait
                end
            )
        end)
        if ok2 and t2 then
            listen_accept.hold_tap7200 = t2
        end
    end
    -- 护画面影子槽（仅已知刚打牌面地址）
    local ok3, t3 = pcall(function()
        return space:install_write_tap(
            0x760A,
            0x764D,
            "fei_feed_hold_shadow",
            function(offset, data, _mask)
                local hh = listen_accept.hold
                if not hh or not hh.wait then
                    return
                end
                local addr = offset & 0xFFFF
                local hit = false
                for _, a in ipairs(DISCARD_SHADOW_TILE_ADDRS) do
                    if addr == a then
                        hit = true
                        break
                    end
                end
                if not hit then
                    return
                end
                local cur = (data or 0) & 0xFF
                if cur == hh.wait then
                    return
                end
                return hh.wait
            end
        )
    end)
    if ok3 and t3 then
        listen_accept.hold_tap_shadow = t3
    end
    return listen_accept.hold_tap7200 ~= nil or listen_accept.hold_tap_shadow ~= nil
end

-- 中途不再改写弃牌；仅保留 tap 空壳以免旧调用报错（真正喂荣靠河变长后 swap）
function listen_accept.feed_try_rewrite(_data)
    return nil
end

function listen_accept.disc_tap_install(machine)
    listen_accept.disc_tap_rm()
    if not listen_accept.wait_bcd or not machine then
        return false
    end
    local cpu = machine.devices and machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space or not space.install_write_tap then
        return false
    end
    listen_accept.cpu = cpu
    listen_accept.mach = machine
    local ok, tap = pcall(function()
        return space:install_write_tap(
            TABLE_TILE_ADDR,
            TABLE_TILE_ADDR,
            "fei_feed_disc7502",
            function(_offset, data, _mask)
                return listen_accept.feed_try_rewrite(data)
            end
        )
    end)
    if ok and tap then
        listen_accept.disc_tap = tap
        return true
    end
    return false
end

function listen_accept.disc_riv_tap_install(machine)
    listen_accept.disc_riv_tap_rm()
    if not listen_accept.wait_bcd or not machine then
        return false
    end
    local cpu = machine.devices and machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space or not space.install_write_tap then
        return false
    end
    listen_accept.cpu = cpu
    listen_accept.mach = machine
    local riv_end = CPU_DISCARD_ADDR + DISCARD_HIST_MAX - 1
    local ok, tap = pcall(function()
        return space:install_write_tap(
            CPU_DISCARD_ADDR,
            riv_end,
            "fei_feed_disc7200",
            function(_offset, data, _mask)
                return listen_accept.feed_try_rewrite(data)
            end
        )
    end)
    if ok and tap then
        listen_accept.disc_riv_tap = tap
        return true
    end
    return false
end

function listen_accept.disc_taps_install(machine)
    listen_accept.disc_tap_install(machine)
    listen_accept.disc_riv_tap_install(machine)
    return listen_accept.disc_tap ~= nil
end

function listen_accept.on_force_arm()
    listen_accept.filter_n = 0
    listen_accept.post_arm_logs = 0
end

function listen_accept.on_force_disarm()
    listen_accept.post_arm_logs = 30
end

function listen_accept.wait_name()
    local w = listen_accept.wait_bcd
    if not w then
        return "(未锁定)"
    end
    local nm = string.format("%02X", w)
    pcall(function()
        nm = tile_name(w)
    end)
    return nm
end

function listen_accept.clear_wait(why)
    local was = listen_accept.wait_bcd
    if not was then
        listen_accept.feed_done = false
        listen_accept.snap_wait_n = nil
        return
    end
    local nm = listen_accept.wait_name()
    listen_accept.wait_bcd = nil
    -- 单次=本锁已消费；清锁后必须允许下一锁再喂（勿让 feed_done 卡住 tick_feed）
    listen_accept.feed_done = false
    listen_accept.snap_wait_n = nil
    listen_accept.disc_taps_rm()
    -- hold 自行耗尽护河；清锁定时不拆 hold
    listen_accept.feed_pending_was = nil
    listen_accept.feed_fallback_rn = nil
    listen_accept.feed_sticky = false
    listen_accept.pending_commit = nil
    pcall(function()
        if tiles_ui and tiles_ui.invalidate_panel_cache then
            tiles_ui.invalidate_panel_cache()
        end
    end)
    write_log(
        string.format(
            "=== [listen-accept-wait] clear was=%02X %s why=%s %s ===\n",
            was,
            nm,
            why or "?",
            now()
        ),
        "a"
    )
end

function listen_accept.set_wait(bcd)
    if not bcd or bcd == 0 then
        return
    end
    if listen_accept.wait_bcd == (bcd & 0xFF) then
        local nm = listen_accept.wait_name()
        listen_accept.hold_tap_rm()
        listen_accept.hold = nil
        listen_accept.clear_wait("toggle_same")
        ui_toast.show(string.format("已取消喂荣锁定「%s」", nm), 160)
        return
    end
    listen_accept.hold_tap_rm()
    listen_accept.disc_taps_rm()
    listen_accept.hold = nil
    listen_accept.wait_bcd = bcd & 0xFF
    listen_accept.feed_done = false
    listen_accept.feed_pending_was = nil
    listen_accept.feed_fallback_rn = nil
    listen_accept.feed_sticky = false
    listen_accept.pending_commit = nil
    listen_accept.pending_clear_wait = nil
    local m = manager and manager.machine
    listen_accept.snap_wait_n = 0
    if m then
        listen_accept.mach = m
        listen_accept.snap_wait_n = listen_accept.count_bcd_in_hand(m, listen_accept.wait_bcd)
        -- 副露中 RAM 空：用透视缓存张数，否则 snapW=0 会导致不再对手
        if listen_accept.snap_wait_n < 1 then
            listen_accept.snap_wait_n = listen_accept.count_bcd_in_cache(listen_accept.wait_bcd)
        end
        if listen_accept.snap_wait_n < 1 then
            listen_accept.snap_wait_n = 1
        end
    end
    local nm = listen_accept.wait_name()
    pcall(function()
        if tiles_ui and tiles_ui.invalidate_panel_cache then
            tiles_ui.invalidate_panel_cache()
        end
    end)
    ui_toast.show(
        string.format(
            "喂荣锁定「%s」(单次)\n电脑打出后，河末换成此张",
            nm
        ),
        260
    )
    write_log(
        string.format(
            "=== [listen-accept-wait] lock=%02X %s snapW=%d rom=%s %s ===\n",
            bcd & 0xFF,
            nm,
            listen_accept.snap_wait_n or 0,
            listen_accept.rom_name(),
            now()
        ),
        "a"
    )
    pcall(function()
        if m then
            listen_accept.cpu = m.devices and m.devices[":maincpu"]
            listen_accept.prev_cpu_rn = listen_accept.cpu_river_count(m)
            listen_accept.prev_river = listen_accept.snapshot_cpu_river(m)
            -- post-swap 不装弃牌写劫持
            listen_accept.disc_taps_rm()
        end
    end)
end

function listen_accept.pc_player_or_draw(cpu)
    local pc = listen_accept.pc_value(cpu)
    if not pc then
        return true
    end
    -- 玩家摸/打、电脑摸：勿改写
    if pc >= 0xA24D and pc <= 0xA25F then
        return true
    end
    if pc >= 0x8C60 and pc <= 0x8C80 then
        return true
    end
    if pc >= 0xA210 and pc <= 0xA225 then
        return true
    end
    if pc >= 0xA380 and pc <= 0xA3A0 then
        return true
    end
    -- mjelct3：9F64/9F35 是摸侧，不是弃牌提交（弃=9FE0/9605）
    if pc >= 0x9F20 and pc <= 0x9F70 then
        return true
    end
    return false
end

function listen_accept.pc_cpu_discard(cpu)
    local pc = listen_accept.pc_value(cpu)
    if not pc then
        return false
    end
    -- 主版：A2CE / 9850 / 9168 / 95E8
    if pc >= 0xA2C0 and pc <= 0xA2E8 then
        return true
    end
    if pc >= 0x9840 and pc <= 0x9870 then
        return true
    end
    if pc >= 0x9140 and pc <= 0x9190 then
        return true
    end
    if pc >= 0x95D0 and pc <= 0x95F0 then
        return true -- 吃后弃 95E8（勿扩到 9605，那是 mjelct3 窗）
    end
    -- mjelct3：只劫持真弃牌写（9FE0 / 9605 / 9627）；9644 不在此窗（结束标记另判）
    if pc >= 0x9FD0 and pc <= 0x9FF0 then
        return true
    end
    if pc >= 0x95F8 and pc <= 0x9610 then
        return true -- 9605
    end
    if pc >= 0x9618 and pc <= 0x9630 then
        return true -- 9627
    end
    return false
end

function listen_accept.pc_cpu_discard_strict(cpu)
    return listen_accept.pc_cpu_discard(cpu)
end

function listen_accept.cpu_has_bcd(bcd)
    if not bcd or not listen_accept.mach then
        return false
    end
    -- 副露后读 live 镜像（@77C0/@7100），勿死盯空的 @7240；再空则看透视缓存
    if listen_accept.count_bcd_in_hand(listen_accept.mach, bcd) > 0 then
        return true
    end
    return listen_accept.count_bcd_in_cache(bcd) > 0
end

function listen_accept.mark_feed_done(why, was, wait)
    listen_accept.feed_n = (listen_accept.feed_n or 0) + 1
    listen_accept.feed_done = true
    listen_accept.pending_clear_wait = why or "fed"
    if (listen_accept.feed_log_n or 0) < 50 then
        listen_accept.feed_log_n = (listen_accept.feed_log_n or 0) + 1
        local pc = listen_accept.pc_value(listen_accept.cpu) or 0
        listen_accept.pending_feed_log = string.format(
            "=== [listen-accept-feed] #%d %s pc=%04X was=%02X -> wait=%02X (oneshot) %s ===\n",
            listen_accept.feed_n,
            why or "tap",
            pc,
            was or 0,
            wait or 0,
            now()
        )
        listen_accept.pending_feed_wait = wait
        listen_accept.pending_feed_was = was or 0
    end
end

function listen_accept.try_feed_write(_data, _why)
    return nil
end

function listen_accept.read_tap_rm()
    if listen_accept.tap then
        pcall(function()
            listen_accept.tap:remove()
        end)
        listen_accept.tap = nil
    end
end

function listen_accept.feed_tap_rm()
    listen_accept.disc_taps_rm()
    listen_accept.hold_tap_rm()
end

function listen_accept.tap_rm()
    listen_accept.read_tap_rm()
    listen_accept.feed_tap_rm()
    listen_accept.cpu = nil
    listen_accept.mach = nil
end

function listen_accept.feed_tap_install(machine)
    if machine then
        listen_accept.mach = machine
        listen_accept.cpu = machine.devices and machine.devices[":maincpu"]
    end
    -- post-swap：不装 disc write tap
    return true
end

function listen_accept.read_tap_install(machine)
    listen_accept.read_tap_rm()
    if not listen_accept.on or not machine then
        return false
    end
    local cpu = machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space or not space.install_read_tap then
        return false
    end
    listen_accept.cpu = cpu
    listen_accept.mach = machine
    local ok, tap = pcall(function()
        return space:install_read_tap(
            listen_accept.addr,
            listen_accept.addr,
            "fei_listen7424",
            function(_offset, _data, _mask)
                if not listen_accept.on then
                    return
                end
                local hit = listen_accept.pc_ok(listen_accept.cpu)
                listen_accept.probe_note(listen_accept.cpu, hit)
                if hit then
                    return listen_accept.accept
                end
                if listen_accept.wait_bcd and listen_accept.probe_n < 80 then
                    local pc = listen_accept.pc_value(listen_accept.cpu)
                    if pc and pc >= 0x8000 and not listen_accept.seen_pc[pc] then
                        listen_accept.seen_pc[pc] = true
                        listen_accept.probe_n = listen_accept.probe_n + 1
                        write_log(
                            string.format(
                                "=== [listen-accept-pc] RON? #%d pc=%04X hit=N wait=%02X %s ===\n",
                                listen_accept.probe_n,
                                pc,
                                listen_accept.wait_bcd,
                                now()
                            ),
                            "a"
                        )
                    end
                end
            end
        )
    end)
    if ok and tap then
        listen_accept.tap = tap
        return true
    end
    return false
end

function listen_accept.ensure_feed(machine)
    if machine then
        listen_accept.mach = machine
        listen_accept.cpu = machine.devices and machine.devices[":maincpu"]
    end
end

function listen_accept.tap_install(machine)
    return listen_accept.read_tap_install(machine)
end

function force_draw.target_bcd()
    return FORCE_TILES[force_draw.tile_i] or 0x05
end

function ui_toast.show(msg, frames)
    if not msg or msg == "" then
        return
    end
    local lines = {}
    for line in string.gmatch(msg, "[^\n]+") do
        lines[#lines + 1] = line
    end
    if #lines == 0 then
        return
    end
    ui_toast.lines = lines
    ui_toast.frames = frames or 150
end

function ui_toast.draw(machine)
    if not ui_toast.lines or (ui_toast.frames or 0) <= 0 then
        ui_toast.lines = nil
        return
    end
    ui_toast.frames = ui_toast.frames - 1
    local ui = nil
    pcall(function()
        ui = machine.render.ui_container
    end)
    if not ui then
        return
    end
    local n = #ui_toast.lines
    local y0 = 0.010
    local line_h = 0.026
    local h = line_h * n + 0.014
    pcall(function()
        ui:draw_box(0.10, y0, 0.90, y0 + h, 0x60ffffff, 0xD0101828)
        for i, line in ipairs(ui_toast.lines) do
            ui:draw_text(0.12, y0 + 0.006 + (i - 1) * line_h, line, 0xffffffff)
        end
    end)
end

function force_draw.pc_player_draw(cpu)
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
    return pc and pc >= force_draw.pc_lo and pc <= force_draw.pc_hi
end

function force_draw.pool_zero_count(machine)
    local z = 0
    for i = 0, WALL_POOL_LEN - 1 do
        if (mem.read_u8(machine, WALL_POOL_ADDR + i) or 0) == 0 then
            z = z + 1
        end
    end
    return z
end

function force_draw.tap_rm()
    if force_draw.tap then
        pcall(function()
            force_draw.tap:remove()
        end)
        force_draw.tap = nil
    end
    force_draw.tap_cpu = nil
    force_draw.tap_dead = false
end

-- 玩家摸写 @7502 当下立刻恢复牌池（须在电脑下一摸之前），避免「你我各摸一张同牌才解除」
function force_draw.tap_fire_restore()
    if not force_draw.armed then
        return
    end
    local bak = force_draw.sticky_backup or force_draw.backup
    local bcd = force_draw.target_bcd()
    local name = tile_name(bcd)
    local m = nil
    pcall(function()
        m = manager.machine
    end)
    if m and bak then
        pcall(function()
            force_draw.restore_pool(m, bak)
        end)
    end
    force_draw.armed = false
    force_draw.backup = nil
    force_draw.armed_pl_n = nil
    force_draw.armed_zeros = 0
    force_draw.tick = 0
    force_draw.prev_n = nil
    force_draw.prev_pl_rn = nil
    force_draw.prev_7502 = nil
    force_draw.tap_dead = true
    listen_accept.on_force_disarm()
    force_draw.pending_log = string.format(
        "=== [force-draw] DISARM (tap_A24D) %s ===\n",
        now()
    )
    force_draw.pending_msg = string.format("控摸已摸入 · 曾锁 %s · 牌池已恢复", name)
end

function force_draw.tap_install(machine)
    force_draw.tap_rm()
    local cpu = machine and machine.devices and machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space or not space.install_write_tap then
        return false
    end
    force_draw.tap_cpu = cpu
    local ok, tap = pcall(function()
        return space:install_write_tap(
            TABLE_TILE_ADDR,
            TABLE_TILE_ADDR,
            "fei_force7502",
            function(_offset, _data, _mask)
                if force_draw.armed and force_draw.pc_player_draw(force_draw.tap_cpu) then
                    force_draw.tap_fire_restore()
                end
            end
        )
    end)
    if ok and tap then
        force_draw.tap = tap
        return true
    end
    force_draw.tap_cpu = nil
    return false
end

function force_draw.consume_pending(machine)
    if force_draw.tap_dead then
        force_draw.tap_rm()
    end
    if force_draw.pending_log then
        write_log(force_draw.pending_log, "a")
        force_draw.pending_log = nil
    end
    if force_draw.pending_msg then
        local msg = force_draw.pending_msg
        force_draw.pending_msg = nil
        ui_toast.show(msg, 150)
    end
end

function listen_accept.consume_pending(machine)
    if listen_accept.pending_w7502 and #listen_accept.pending_w7502 > 0 then
        for _, line in ipairs(listen_accept.pending_w7502) do
            write_log(line, "a")
        end
        listen_accept.pending_w7502 = nil
    end
    if listen_accept.pending_feed_log then
        write_log(listen_accept.pending_feed_log, "a")
        listen_accept.pending_feed_log = nil
    end
    if listen_accept.pending_feed_wait then
        local w = listen_accept.pending_feed_wait
        local was = listen_accept.pending_feed_was or 0
        listen_accept.pending_feed_wait = nil
        listen_accept.pending_feed_was = nil
        local wn, wasn = string.format("%02X", w), string.format("%02X", was)
        pcall(function()
            wn = tile_name(w)
            wasn = tile_name(was)
        end)
        if was == w then
            ui_toast.show(string.format("喂荣完成：电脑打出 %s · 已解锁", wn), 180)
        else
            ui_toast.show(string.format("喂荣完成：电脑改打 %s（原 %s）· 已解锁", wn, wasn), 180)
        end
    end
    if listen_accept.pending_clear_wait then
        local why = listen_accept.pending_clear_wait
        listen_accept.pending_clear_wait = nil
        listen_accept.clear_wait(why)
    end
end

-- 电脑河变长或同长改写末张：打完后再把「刚打出」换成锁定牌
function listen_accept.tick_feed(machine)
    if not machine then
        return
    end
    if listen_accept.hold then
        return
    end
    local rn = listen_accept.cpu_river_count(machine)
    if not listen_accept.wait_bcd then
        listen_accept.prev_river = listen_accept.snapshot_cpu_river(machine)
        listen_accept.prev_cpu_rn = #listen_accept.prev_river
        listen_accept.feed_done = false
        return
    end
    if listen_accept.feed_done then
        return
    end
    listen_accept.ensure_feed(machine)
    local prev = listen_accept.prev_cpu_rn
    local prev_bytes = listen_accept.prev_river
    local prev_n = prev_bytes and #prev_bytes or (prev or 0)

    -- 1) 河变长：新打出
    if prev ~= nil and rn > prev then
        local slot, last = listen_accept.detect_new_discard(machine, rn, prev_bytes)
        listen_accept.feed_fallback_rn = rn
        listen_accept.feed_pending_was = last
        listen_accept.prev_cpu_rn = rn
        listen_accept.prev_river = listen_accept.snapshot_cpu_river(machine)
        listen_accept.commit_feed(machine, last, "river_grow", slot)
        return
    end

    -- 2) 同长但内容变（副露后 mjelct3 常改写末格而不变长）
    --    注意：未触发前不可每帧刷新 prev，否则永远看不见 diff
    if rn >= 1 and prev_n >= 1 and rn == prev_n and prev_bytes then
        local cur = listen_accept.snapshot_cpu_river(machine)
        local changed = false
        local slot = rn
        for i = 1, rn do
            if (cur[i] or 0) ~= (prev_bytes[i] or 0) then
                changed = true
                slot = i
            end
        end
        if changed then
            local last = cur[slot] or cur[rn] or 0
            if (cur[rn] or 0) ~= (prev_bytes[rn] or 0) then
                slot = rn
                last = cur[rn] or 0
            end
            listen_accept.feed_fallback_rn = rn
            listen_accept.feed_pending_was = last
            listen_accept.prev_cpu_rn = rn
            listen_accept.prev_river = cur
            listen_accept.commit_feed(machine, last, "river_rewrite", slot)
            return
        end
        return
    end

    -- 3) 缩短（吃碰从河拿走）或首次：对齐快照
    if prev == nil or rn < prev_n then
        listen_accept.prev_cpu_rn = rn
        listen_accept.prev_river = listen_accept.snapshot_cpu_river(machine)
    end
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
    force_draw.armed_zeros = 0
    force_draw.tick = 0
    force_draw.prev_n = nil
    force_draw.prev_pl_rn = nil
    force_draw.prev_7502 = nil
end

function force_draw.clear_session()
    force_draw.tap_rm()
    force_draw.clear_armed()
    force_draw.sticky_backup = nil
    force_draw.pending_msg = nil
    force_draw.pending_log = nil
end

function listen_accept.toggle(machine)
    if listen_accept.on then
        listen_accept.on = false
        listen_accept.read_tap_rm()
        listen_accept.clear_ram(machine)
        listen_accept.probe_reset()
        machine:popmessage("听牌可胡关 · 已清 @7424")
        write_log(
            string.format(
                "=== [listen-accept] OFF %s verify7424=%02X feed=%s ===\n",
                now(),
                mem.read_u8(machine, listen_accept.addr) or 0,
                listen_accept.wait_name()
            ),
            "a"
        )
        return
    end
    listen_accept.on = true
    listen_accept.probe_reset()
    listen_accept.apply_rom_profile(machine)
    listen_accept.clear_ram(machine)
    local tap_ok = listen_accept.tap_install(machine)
    local rom = (machine and machine.system and machine.system.name) or "?"
    local wait_nm = listen_accept.wait_name()
    write_log(
        string.format(
            "=== [listen-accept] ON rom=%s tap+ %s disc_tap=%s window=%04X..%04X wait=%s 7424=%02X %s ===\n",
            rom,
            tap_ok and "Y" or "N",
            listen_accept.disc_tap and "Y" or "N",
            listen_accept.pc_lo,
            listen_accept.pc_hi,
            wait_nm,
            mem.read_u8(machine, listen_accept.addr) or 0,
            now()
        ),
        "a"
    )
    if tap_ok then
        ui_toast.show(
            string.format(
                "听牌可胡开 · 自摸旁路\n喂荣=%s（点电脑手锁定，与可胡无关）",
                wait_nm
            ),
            260
        )
        machine:popmessage(string.format("听牌可胡开 · 喂荣=%s", wait_nm))
    else
        listen_accept.on = false
        machine:popmessage("听牌可胡：读拦截安装失败")
    end
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

function hand_pat.closed_count(machine)
    local n = 0
    for i = 0, HAND_SORTED do
        local v = mem.read_u8(machine, HAND_ADDR + i)
        if tile_valid(v) then
            n = n + 1
        end
    end
    return n
end

function hand_pat.mirror_count(machine)
    local n = 0
    for i = 0, 13 do
        local v = mem.read_u8(machine, HAND_MIRROR_ADDR + i)
        if tile_valid(v) then
            n = n + 1
        end
    end
    return n
end

function hand_pat.write_tiles(machine, tiles, sync_screen)
    local nwrite = #tiles
    for i = 1, nwrite do
        mem.write_u8(machine, HAND_MIRROR_ADDR + i - 1, tiles[i])
    end
    if nwrite == 13 then
        mem.write_u8(machine, HAND_MIRROR_ADDR + 13, 0)
    end
    if not sync_screen then
        return
    end
    for i = 1, 13 do
        mem.write_u8(machine, HAND_ADDR + i - 1, (i <= nwrite) and tiles[i] or 0)
    end
    if nwrite == 14 then
        mem.write_u8(machine, HAND_ADDR + HAND_STAGING_OFF, tiles[14])
    else
        mem.write_u8(machine, HAND_ADDR + HAND_STAGING_OFF, 0)
    end
end

function hand_pat.write_cpu_tiles(machine, tiles)
    if not machine or not tiles then
        return
    end
    local nwrite = #tiles
    if nwrite > 14 then
        nwrite = 14
    end
    for _, base in ipairs(CPU_HAND_WRITABLE) do
        for i = 1, nwrite do
            mem.write_u8(machine, base + i - 1, tiles[i])
        end
        if nwrite < 14 then
            mem.write_u8(machine, base + nwrite, 0)
        end
    end
    -- 透视可信缓存同步，避免图与注入脱节
    local copy = {}
    local nshow = math.min(nwrite, CPU_HAND_MAX)
    for i = 1, nshow do
        copy[i] = tiles[i]
    end
    cpu_hand_trusted.raw = copy
    cpu_hand_trusted.src = CPU_HAND_ADDR
    cpu_hand_trusted.meld_count = 0
    cpu_hand_trusted.no_draw_discard = nil
    cpu_hand_trusted.stale = nil
    cpu_hand_cache = { raw = copy, src = CPU_HAND_ADDR }
end

function hand_pat.tick(machine)
    local h = hand_pat.hold
    if h and h.tiles and machine then
        h.frames = (h.frames or 0) - 1
        if h.frames < 0 then
            hand_pat.hold = nil
        else
            -- 开局换牌会反复刷镜像；短时间每帧盖回（类 cheat Always）
            hand_pat.write_tiles(machine, h.tiles, false)
        end
    end
    local hc = hand_pat.hold_cpu
    if hc and hc.tiles and machine then
        hc.frames = (hc.frames or 0) - 1
        if hc.frames < 0 then
            hand_pat.hold_cpu = nil
        else
            hand_pat.write_cpu_tiles(machine, hc.tiles)
        end
    end
end

function hand_pat.apply(machine, preset)
    if not machine or not preset then
        return false
    end
    local n_hand = hand_pat.closed_count(machine)
    local n_mir = hand_pat.mirror_count(machine)
    -- 开局换牌：@7120 常空，权威在 @72C0（与 MAME cheat 相同）
    local first_chance = n_hand < 13 and n_mir >= 13
    local n = first_chance and n_mir or math.max(n_hand, n_mir)
    local tiles = nil
    local mode = nil
    -- 换牌 UI 为 A–N 共 14 槽；只写 13 张会挤到 B–N，A 易剩扣牌/空（C 女孩+扣牌实机）
    -- 与 cheat 一致：换牌阶段一律写满 14 字节，勿清 @72CD
    if first_chance then
        if preset.tiles14 and #preset.tiles14 == 14 then
            tiles = preset.tiles14
            mode = "14fc"
        end
    elseif n >= 14 and preset.tiles14 and #preset.tiles14 == 14 then
        tiles = preset.tiles14
        mode = "14"
    elseif n >= 13 then
        tiles = preset.tiles13
        if (not tiles or #tiles ~= 13) and preset.tiles14 and #preset.tiles14 == 14 then
            tiles = {}
            for i = 1, 13 do
                tiles[i] = preset.tiles14[i]
            end
        end
        mode = "13"
    end
    if not tiles or (#tiles ~= 13 and #tiles ~= 14) then
        ui_toast.show(
            string.format(
                "牌型：需手或镜像≥13（手%d 镜像%d）·「%s」",
                n_hand,
                n_mir,
                preset.label or "?"
            ),
            180
        )
        return false
    end
    local sync_screen = not first_chance
    hand_pat.write_tiles(machine, tiles, sync_screen)
    if first_chance then
        hand_pat.hold = { tiles = tiles, frames = 240 }
    else
        hand_pat.hold = nil
    end
    local hex = {}
    for i = 1, #tiles do
        hex[#hex + 1] = string.format("%02X", tiles[i])
    end
    write_log(
        string.format(
            "=== [hand-pat] rom=%s id=%s %s mode=%s first_chance=%s hand=%d mir=%d tiles=%s %s ===\n",
            (machine.system and machine.system.name) or "?",
            preset.id or "?",
            preset.label or "",
            mode,
            first_chance and "Y" or "N",
            n_hand,
            n_mir,
            table.concat(hex, " "),
            now()
        ),
        "a"
    )
    if first_chance then
        ui_toast.show(
            string.format(
                "换牌阶段已套用「%s」(14槽镜像)\n勿只写13张；建议少扣牌或套用后再确认A键",
                preset.label or "?"
            ),
            260
        )
    elseif mode == "14" then
        ui_toast.show(
            string.format("已套用「%s」(14张)\n可直接荣/自摸试胡", preset.label or "?"),
            210
        )
    else
        ui_toast.show(
            string.format(
                "已套用「%s」(13张听)\n%s",
                preset.label or "?",
                preset.wait_hint or "摸一张后再胡（可控摸）"
            ),
            240
        )
    end
    hand_pat.menu_open = false
    hand_pat.menu_target = nil
    return true
end

function hand_pat.apply_cpu(machine, preset)
    if not machine or not preset then
        return false
    end
    local cpu_m = meld.read_blocks(machine, meld.CPU_ADDR)
    if #cpu_m > 0 then
        ui_toast.show("电脑已有副露，无法注入役满\n（需无副露）", 200)
        return false
    end
    local n_cpu = 0
    for i = 0, CPU_HAND_MAX - 1 do
        local v = mem.read_u8(machine, CPU_HAND_ADDR + i)
        if not tile_valid(v) then
            break
        end
        n_cpu = n_cpu + 1
    end
    if n_cpu < 1 then
        for i = 0, CPU_HAND_MAX - 1 do
            local v = mem.read_u8(machine, 0x77C0 + i)
            if not tile_valid(v) then
                break
            end
            n_cpu = n_cpu + 1
        end
    end
    local n_hand = hand_pat.closed_count(machine)
    local n_mir = hand_pat.mirror_count(machine)
    -- 开局换牌（first chance）：玩家手空镜像满；电脑侧常已有 13，宜尽早注入测天和
    local first_chance = n_hand < 13 and n_mir >= 13
    local tiles = nil
    local mode = nil
    if first_chance then
        if preset.tiles14 and #preset.tiles14 == 14 then
            tiles = preset.tiles14
            mode = "14fc-cpu"
        end
    elseif preset.tiles14 and #preset.tiles14 == 14 and n_cpu >= 14 then
        tiles = preset.tiles14
        mode = "14-cpu"
    end
    if not tiles then
        tiles = preset.tiles13
        if (not tiles or #tiles ~= 13) and preset.tiles14 and #preset.tiles14 == 14 then
            tiles = {}
            for i = 1, 13 do
                tiles[i] = preset.tiles14[i]
            end
        end
        if first_chance and preset.tiles14 and #preset.tiles14 == 14 then
            tiles = preset.tiles14
            mode = "14fc-cpu"
        else
            mode = mode or "13-cpu"
        end
    end
    if not tiles or (#tiles ~= 13 and #tiles ~= 14) then
        ui_toast.show(
            string.format("电脑役满：牌型无效·「%s」", preset.label or "?"),
            160
        )
        return false
    end
    if n_cpu < 7 and not first_chance then
        ui_toast.show(
            string.format(
                "电脑手数过少(%d)，请等发牌完成后再注\n换牌阶段可打开「电脑役满」选牌型",
                n_cpu
            ),
            220
        )
        return false
    end
    hand_pat.write_cpu_tiles(machine, tiles)
    hand_pat.hold_cpu = {
        tiles = tiles,
        frames = first_chance and 300 or 90,
    }
    local hex = {}
    for i = 1, #tiles do
        hex[#hex + 1] = string.format("%02X", tiles[i])
    end
    write_log(
        string.format(
            "=== [hand-pat-cpu] rom=%s id=%s %s mode=%s first_chance=%s cpu_n=%d tiles=%s %s ===\n",
            (machine.system and machine.system.name) or "?",
            preset.id or "?",
            preset.label or "",
            mode,
            first_chance and "Y" or "N",
            n_cpu,
            table.concat(hex, " "),
            now()
        ),
        "a"
    )
    pcall(function()
        cpu_win_probe.arm(preset, mode, first_chance, tiles)
    end)
    if first_chance then
        ui_toast.show(
            string.format(
                "换牌阶段已给电脑「%s」(%d张)\n测天和：少操作，确认后直接开打",
                preset.label or "?",
                #tiles
            ),
            280
        )
    elseif #tiles == 14 then
        ui_toast.show(
            string.format("已给电脑「%s」(14张·无副露)\n可试自摸/荣", preset.label or "?"),
            210
        )
    else
        ui_toast.show(
            string.format(
                "已给电脑「%s」(13张听·无副露)\n%s",
                preset.label or "?",
                preset.wait_hint or "摸一张后再胡"
            ),
            240
        )
    end
    hand_pat.menu_open = false
    hand_pat.menu_target = nil
    return true
end

function hand_pat.preset_by_id(id)
    for _, p in ipairs(hand_pat.presets) do
        if p.id == id then
            return p
        end
    end
    return nil
end

function hand_pat.draw(ui, machine)
    hand_pat.hits = {}
    if not ui or not peek_open then
        return
    end
    local g = nil
    if tiles_ui and tiles_ui.get_mjelctrn_geom then
        pcall(function()
            g = tiles_ui.get_mjelctrn_geom()
        end)
    end
    local gx0 = (g and g.gx0) or 0.08
    local gx1 = (g and g.gx1) or 0.92
    local gy0 = (g and g.gy0) or 0.02
    local bw = math.min(0.175, (gx1 - gx0) * 0.28)
    local bh = 0.050
    local gap_btn = 0.008
    local y0 = gy0 + 0.004
    local y1 = y0 + bh
    -- 右：「玩家役满」；左：「电脑役满」——共用同一套下拉列表
    local px1 = gx1
    local px0 = px1 - bw
    local cx1 = px0 - gap_btn
    local cx0 = cx1 - bw
    local pl_open = hand_pat.menu_open and hand_pat.menu_target == "player"
    local cpu_open = hand_pat.menu_open and hand_pat.menu_target == "cpu"
    pcall(function()
        if ui.draw_box then
            ui:draw_box(
                cx0,
                y0,
                cx1,
                y1,
                cpu_open and 0xffffc0d0 or 0xffc090a0,
                0xf0181018
            )
            ui:draw_box(
                px0,
                y0,
                px1,
                y1,
                pl_open and 0xffffe0a0 or 0xffd0c080,
                0xf0101018
            )
        end
        if ui.draw_text then
            ui:draw_text(
                cx0 + 0.006,
                y0 + 0.012,
                cpu_open and "电脑<<" or "电脑役满",
                0xffffe8f0
            )
            ui:draw_text(
                px0 + 0.006,
                y0 + 0.012,
                pl_open and "玩家<<" or "玩家役满",
                0xfffff8e0
            )
        end
    end)
    hand_pat.hits[#hand_pat.hits + 1] = {
        id = "toggle_cpu",
        x0 = cx0,
        y0 = y0,
        x1 = cx1,
        y1 = y1,
    }
    hand_pat.hits[#hand_pat.hits + 1] = {
        id = "toggle_player",
        x0 = px0,
        y0 = y0,
        x1 = px1,
        y1 = y1,
    }
    if not hand_pat.menu_open then
        return
    end
    local cols = 2
    local row_h = 0.060
    local gap = 0.010
    local menu_w = gx1 - gx0
    local col_w = menu_w / cols
    local my0 = y1 + 0.010
    local outline = cpu_open and 0xffc090a0 or 0xffc8b070
    for i, p in ipairs(hand_pat.presets) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local mx0 = gx0 + col * col_w
        local mx1 = mx0 + col_w - 0.006
        local my = my0 + row * (row_h + gap)
        local my1 = my + row_h
        pcall(function()
            if ui.draw_box then
                ui:draw_box(mx0, my, mx1, my1, outline, 0xf8101018)
            end
            if ui.draw_text then
                ui:draw_text(mx0 + 0.010, my + 0.008, p.label or p.id, 0xfffffaf0)
            end
        end)
        hand_pat.hits[#hand_pat.hits + 1] = {
            id = p.id,
            x0 = mx0,
            y0 = my,
            x1 = mx1,
            y1 = my1,
        }
    end
end

function hand_pat.hit(ux, uy)
    if not ux or not uy or not hand_pat.hits then
        return nil
    end
    for _, h in ipairs(hand_pat.hits) do
        if ux >= h.x0 and ux <= h.x1 and uy >= h.y0 and uy <= h.y1 then
            return h.id
        end
    end
    return nil
end

function hand_pat.toggle_menu(target)
    if hand_pat.menu_open and hand_pat.menu_target == target then
        hand_pat.menu_open = false
        hand_pat.menu_target = nil
    else
        hand_pat.menu_open = true
        hand_pat.menu_target = target
    end
end

function hand_pat.on_click(machine, id)
    if id == "toggle_player" then
        hand_pat.toggle_menu("player")
        return
    end
    if id == "toggle_cpu" then
        hand_pat.toggle_menu("cpu")
        return
    end
    -- 兼容旧 id
    if id == "toggle" then
        hand_pat.toggle_menu("player")
        return
    end
    local p = hand_pat.preset_by_id(id)
    if not p then
        return
    end
    if hand_pat.menu_target == "cpu" then
        hand_pat.apply_cpu(machine, p)
    else
        hand_pat.apply(machine, p)
    end
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
    -- 新局河皆空时：只清「残局短缓存」的 stale 标记，让完整 13 张实读能进来
    -- 切勿在 trust<13 时整段 reset——发牌过程中每帧都会误清（曾把 12 张清成空）
    if not tile_valid(mem.read_u8(machine, CPU_DISCARD_ADDR))
        and not tile_valid(mem.read_u8(machine, PLAYER_DISCARD_ADDR))
    then
        if cpu_hand_trusted.stale then
            cpu_hand_trusted.stale = nil
        end
        -- 新河空：副露计数也归零（新局）
        if (cpu_hand_trusted.meld_count or 0) > 0 then
            cpu_hand_trusted.meld_count = 0
        end
        cpu_hand_trusted.no_draw_discard = nil
        cpu_hand_trusted.meld_at_gen = nil
        cpu_hand_trusted.after_meld_miss = nil
        hud_sticky.pl_n = 0
        hud_sticky.pl_rn = 0
        hud_sticky.cpu_rn = 0
    end

    local trust = cpu_hand_trusted.raw
    local trust_n = trust and #trust or 0
    local stale = cpu_hand_trusted.stale
    local pl7120 = read_cpu_hand_at(machine, HAND_ADDR)
    local pl_melds = meld.read_blocks(machine, meld.PLAYER_ADDR)
    local pl_melds2 = meld.read_blocks(machine, meld.PLAYER_MIRROR)
    local cpu_melds = meld.read_blocks(machine, meld.CPU_ADDR)
    local pl_mn = math.max(#pl_melds, #pl_melds2)
    local cpu_mn = #cpu_melds
    -- @7250 有块 → 以 RAM 为准；空且非「刚副露未打牌」→ 清零（Donden 后勿留幽灵「电脑副露2」）
    if cpu_mn > 0 then
        cpu_hand_trusted.meld_count = cpu_mn
    elseif not cpu_hand_trusted.no_draw_discard then
        cpu_hand_trusted.meld_count = 0
    end
    -- 满手+无副露块仍挂 no_draw（expect=14）= 上局残留；勿在「刚 patch 尚未写表」时清
    if cpu_mn == 0
        and cpu_hand_trusted.no_draw_discard
        and trust_n >= 13
        and (cpu_hand_trusted.meld_count or 0) == 0
    then
        cpu_hand_trusted.no_draw_discard = nil
    end
    -- 幽灵副露1：无吃碰记账、缓存恰 10、总线满 13、且 @7250 也空 → Donden 中途残片误判
    if (cpu_hand_trusted.meld_count or 0) == 1
        and cpu_mn == 0
        and not cpu_hand_trusted.meld_at_gen
        and not cpu_hand_trusted.no_draw_discard
        and trust_n == 10
        and pl_mn == 0
    then
        local live13 = read_cpu_hand_at(machine, CPU_HAND_ADDR)
        if #live13 < 13 then
            live13 = read_cpu_hand_at(machine, 0x77C0)
        end
        if #live13 >= 13
            and not listen_accept.raw_looks_like_player(machine, live13)
        then
            write_log(
                string.format(
                    "=== [peek-hand] unstick phantom-meld1 trust=10 live=%d %s ===\n",
                    #live13,
                    now()
                ),
                "a"
            )
            cpu_hand_trusted.meld_count = 0
            cpu_hand_trusted.raw = {}
            cpu_hand_cache = { raw = {}, src = nil }
            trust = cpu_hand_trusted.raw
            trust_n = 0
            stale = nil
        end
    end
    local meld_n = cpu_hand_trusted.meld_count or 0
    local expect_n = meld.expected_closed_n(meld_n, cpu_hand_trusted.no_draw_discard)
    local prev_pl_mn = cpu_hand_trusted.prev_pl_meld_n
    local prev_cpu_mn = cpu_hand_trusted.prev_cpu_meld_n
    local meld_swapped = type(prev_pl_mn) == "number"
        and type(prev_cpu_mn) == "number"
        and (prev_pl_mn > 0 or prev_cpu_mn > 0)
        and pl_mn == prev_cpu_mn
        and cpu_mn == prev_pl_mn
        and (pl_mn ~= prev_pl_mn or cpu_mn ~= prev_cpu_mn)
    -- 对调后新电脑暗手期望 = 旧玩家副露数对应张数
    local expect_after_donden = meld.expected_closed_n(prev_pl_mn or 0)

    -- 串台自愈：缓存已等于玩家手（误把 prev 当电脑手）→ 丢弃，改回实读
    if trust_n >= 7
        and #pl7120 >= 7
        and listen_accept.multiset_equal_lists(trust, pl7120)
    then
        write_log(
            string.format(
                "=== [peek-hand] unstick player-like trust=%d %s ===\n",
                trust_n,
                now()
            ),
            "a"
        )
        cpu_hand_trusted.raw = {}
        cpu_hand_trusted.stale = nil
        cpu_hand_trusted.no_draw_discard = nil
        cpu_hand_trusted.meld_at_gen = nil
        cpu_hand_cache = { raw = {}, src = nil }
        cpu_hand_trusted.donden_cool_frames = 0
        -- 串台时不要清冷却又立刻被噪声地址二次 donden；给一点稳定窗
        cpu_hand_trusted.donden_cool_frames = 45
        trust = cpu_hand_trusted.raw
        trust_n = 0
        stale = nil
    end
    -- 无副露却短缓存（曾卡死在 3 张）：整手实读应能盖掉
    if meld_n == 0
        and trust_n > 0
        and trust_n < 7
        and expect_n >= 10
    then
        write_log(
            string.format(
                "=== [peek-hand] unstick short-trust=%d expect=%d %s ===\n",
                trust_n,
                expect_n,
                now()
            ),
            "a"
        )
        cpu_hand_trusted.raw = {}
        cpu_hand_trusted.stale = nil
        cpu_hand_trusted.no_draw_discard = nil
        cpu_hand_cache = { raw = {}, src = nil }
        trust = cpu_hand_trusted.raw
        trust_n = 0
        stale = nil
    end
    local best, best_addr, best_score = {}, nil, -1
    local rejected = nil
    local probe = {}
    local donden = false

    -- 冷却：对调后数秒内禁止再次 donden（镜像未对齐时会 77C0↔7630 交替）
    local cool_left = cpu_hand_trusted.donden_cool_frames or 0
    if cool_left > 0 then
        cpu_hand_trusted.donden_cool_frames = cool_left - 1
    end
    local in_cool = cool_left > 0
    -- 对调只信主镜像；@7610/@7630 是影子噪声，参与 donden 会整秒翻牌
    local DONDON_ADDRS = { [0x7240] = true, [0x77C0] = true }
    -- 无副露至少按 7 张护栏；有副露才允许短到 expect±1
    local min_live = 7
    if meld_n >= 1 then
        min_live = math.max(4, expect_n - 1)
    end

    for _, addr in ipairs(CPU_HAND_FALLBACKS) do
        local raws = read_cpu_hand_at(machine, addr)
        probe[addr] = #raws
        if #raws > 0 then
            local eq_player = listen_accept.multiset_equal_lists(raws, pl7120)
            local eq_trust = trust_n >= 7
                and listen_accept.multiset_equal_lists(raws, trust)
            -- Donden：玩家手≈旧电脑缓存，或副露块已互换；总线是另一副完整暗手
            -- 无副露时必须满 13 张——对调过程中会短暂出现 10 张，绝不能当「副露1」采纳
            local donden_hit = false
            local min_donden_n = 13
            if meld_swapped then
                min_donden_n = math.max(4, expect_after_donden)
            elseif meld_n >= 1 then
                min_donden_n = math.max(7, expect_n)
            end
            if not in_cool
                and DONDON_ADDRS[addr]
                and not eq_player
                and not eq_trust
                and #raws >= min_donden_n
                and trust_n >= 7
                and not listen_accept.raw_looks_like_player(machine, raws)
            then
                local ov_trust = listen_accept.multiset_overlap(raws, trust)
                local half = math.floor(math.max(#raws, trust_n) / 2)
                local pl_got_old_cpu = #pl7120 >= 7
                    and (
                        listen_accept.multiset_equal_lists(pl7120, trust)
                        or listen_accept.multiset_overlap(pl7120, trust)
                            >= math.min(#pl7120, trust_n) - 2
                    )
                local len_ok = true
                if meld_n == 0 and not meld_swapped then
                    len_ok = #raws >= 13 and #pl7120 >= 13
                elseif meld_swapped then
                    len_ok = math.abs(#raws - expect_after_donden) <= 1
                end
                if ov_trust <= half and len_ok and (pl_got_old_cpu or meld_swapped) then
                    -- 新电脑手不能大部分等于当前玩家手（对调残片）
                    local ov_pl = #pl7120 >= 7
                        and listen_accept.multiset_overlap(raws, pl7120)
                        or 0
                    if ov_pl <= math.floor(#raws / 2) then
                        donden_hit = true
                    end
                end
            end
            if donden_hit then
                local sc = (addr == CPU_HAND_ADDR) and 5200 or 5000
                if meld_swapped then
                    sc = sc + 400
                end
                if sc > best_score then
                    donden = true
                    best, best_addr, best_score = raws, addr, sc
                end
            elseif eq_player or listen_accept.raw_looks_like_player(machine, raws) then
                rejected = addr
            else
                -- Donden 冷却中：拒绝「玩家手片段」（3/5 张串台）
                local cool_reject = false
                if in_cool and #pl7120 >= 7 then
                    local ov = listen_accept.multiset_overlap(raws, pl7120)
                    local half = math.floor(#raws / 2)
                    if ov > half or (meld_n == 0 and #raws < 13) then
                        cool_reject = true
                        rejected = addr
                    end
                end
                if not cool_reject then
                local score = (CPU_HAND_PRIO[addr] or 0)
                local rivers_empty = not tile_valid(mem.read_u8(machine, CPU_DISCARD_ADDR))
                    and not tile_valid(mem.read_u8(machine, PLAYER_DISCARD_ADDR))
                -- 满手护栏：无副露时勿用「trust≥4」影子逻辑，否则 3 张短缓存会永久挡住 13
                local shadow = trust_n >= min_live and not rivers_empty
                -- Donden 中途残片（无副露却读到 10 张）：有满手缓存时一律拒收
                if meld_n == 0
                    and not rivers_empty
                    and trust_n >= 13
                    and #raws > 0
                    and #raws < 13
                then
                    score = score - 2500
                elseif #raws < min_live and (trust_n >= min_live or (meld_n == 0 and expect_n >= 10)) then
                    score = score - 2000
                elseif shadow and expect_n >= 4
                    and math.abs(#raws - expect_n) >= 2
                    and #raws ~= trust_n
                    and #raws ~= trust_n + 1
                    and #raws ~= trust_n - 1
                then
                    score = score - 1500
                elseif stale and listen_accept.multiset_equal_lists(raws, stale) then
                    score = score - 1000
                elseif shadow and #raws == expect_n then
                    score = score + 800
                    if trust_n == expect_n
                        and listen_accept.multiset_equal_lists(raws, trust)
                    then
                        score = score + 500
                    end
                elseif shadow and #raws == trust_n
                    and listen_accept.multiset_equal_lists(raws, trust)
                then
                    score = score + 500
                elseif shadow
                    and #raws == trust_n + 1
                    and listen_accept.multiset_is_subset(trust, raws)
                then
                    score = score + 2000
                elseif shadow
                    and #raws == trust_n - 1
                    and listen_accept.multiset_is_subset(raws, trust)
                    and not (stale or cpu_hand_trusted.no_draw_discard)
                then
                    score = score + 2000
                elseif shadow then
                    score = score - 1000
                elseif trust_n > 0 and #raws < trust_n and listen_accept.multiset_is_subset(raws, trust) then
                    local drop = trust_n - #raws
                    if drop == 1 then
                        score = score + 2000
                    else
                        score = score - 500
                    end
                elseif trust_n > 0 and #raws > trust_n then
                    if rivers_empty then
                        score = score + #raws
                    elseif (#raws - trust_n) == 1
                        and listen_accept.multiset_is_subset(trust, raws)
                    then
                        score = score + 2000
                    elseif trust_n < 7
                        and #raws >= math.min(13, expect_n)
                        and expect_n >= 10
                    then
                        -- 短缓存恢复：3 张挡住 13 张时走这里
                        score = score + 3000
                    else
                        score = score - 1000
                    end
                else
                    score = score + #raws
                end
                if score > best_score then
                    best, best_addr, best_score = raws, addr, score
                end
                end -- not cool_reject
            end
        end
    end

    -- 只丢弃「与扣牌前完全相同」的陈旧镜像；更长实读已在打分阶段抑制（防撑回 13）
    if #best > 0 and stale and listen_accept.multiset_equal_lists(best, stale) then
        best, best_addr = {}, nil
    end
    -- 打分为负：没有可用实读，继续用可信缓存
    if #best > 0 and best_score < 0 then
        best, best_addr = {}, nil
    end

    if #best > 0 then
        local copy = {}
        for i, v in ipairs(best) do
            copy[i] = v
        end
        -- 实读已不是「扣牌前」那副：镜像跟上或新摸，清掉 stale
        local keep_stale = stale
            and listen_accept.multiset_equal_lists(copy, stale)
        cpu_hand_cache = { raw = copy, src = best_addr }
        cpu_hand_trusted = {
            raw = copy,
            src = best_addr,
            prev_player = cpu_hand_trusted.prev_player,
            last_live = cpu_hand_trusted.last_live,
            donden_cool_frames = cpu_hand_trusted.donden_cool_frames,
            pl_discard_gen = cpu_hand_trusted.pl_discard_gen,
            meld_at_gen = cpu_hand_trusted.meld_at_gen,
            last_pl_discard = cpu_hand_trusted.last_pl_discard,
            last_discard_rn = cpu_hand_trusted.last_discard_rn,
            pending_draw = cpu_hand_trusted.pending_draw,
            no_draw_discard = cpu_hand_trusted.no_draw_discard,
            meld_count = cpu_hand_trusted.meld_count,
            prev_pl_meld_n = cpu_hand_trusted.prev_pl_meld_n,
            prev_cpu_meld_n = cpu_hand_trusted.prev_cpu_meld_n,
            stale = keep_stale and stale or nil,
        }
        -- 记录最近一次完整实读，供下一帧「总线整手跳变」检测
        if #copy >= 4 and best_addr and best_addr ~= 0xD0DE then
            local lv = {}
            for i, v in ipairs(copy) do
                lv[i] = v
            end
            cpu_hand_trusted.last_live = lv
        end
        cpu_hand_src_addr = best_addr
        if donden then
            -- 对调后整手作废旧扣牌/摸打状态；冷却约 5s，避免镜像未对齐时交替翻牌
            -- 副露/河随座位互换：以对调后 @7250 实读为准（勿用陈旧 prev_pl，易与镜像不同步）
            local post_cpu = meld.read_blocks(machine, meld.CPU_ADDR)
            cpu_hand_trusted.meld_count = #post_cpu
            cpu_hand_trusted.pl_discard_gen = nil
            cpu_hand_trusted.meld_at_gen = nil
            cpu_hand_trusted.last_pl_discard = nil
            cpu_hand_trusted.last_discard_rn = nil
            cpu_hand_trusted.pending_draw = nil
            cpu_hand_trusted.no_draw_discard = nil
            cpu_hand_trusted.stale = nil
            cpu_hand_trusted.donden_cool_frames = 300
            draw_track_prev = nil
            -- 立刻对齐 prev_player，避免下一帧再次判成「整手突变」
            do
                local pp = {}
                for i, v in ipairs(pl7120) do
                    pp[i] = v
                end
                cpu_hand_trusted.prev_player = pp
                local lv = {}
                for i, v in ipairs(copy) do
                    lv[i] = v
                end
                cpu_hand_trusted.last_live = lv
            end
            write_log(
                string.format(
                    "=== [peek-hand] donden-refresh @%04X n=%d pl=%d meld_n=%d expect=%d ram7250=%d meld_swap=%s %s ===\n",
                    best_addr or 0,
                    #copy,
                    #pl7120,
                    cpu_hand_trusted.meld_count or 0,
                    meld.expected_closed_n(cpu_hand_trusted.meld_count),
                    #post_cpu,
                    meld_swapped and "Y" or "N",
                    now()
                ),
                "a"
            )
        end
        return copy, best_addr, false
    end

    -- 无实读可采纳时，仍更新 last_live（若总线有完整手）
    do
        local live_n = probe[0x7240] or 0
        if live_n < 4 then
            live_n = probe[0x77C0] or 0
        end
        if live_n >= 4 then
            for _, addr in ipairs(CPU_HAND_FALLBACKS) do
                local raws = read_cpu_hand_at(machine, addr)
                if #raws >= 4 and not listen_accept.raw_looks_like_player(machine, raws) then
                    local lv = {}
                    for i, v in ipairs(raws) do
                        lv[i] = v
                    end
                    cpu_hand_trusted.last_live = lv
                    break
                end
            end
        end
    end

    if (listen_accept._peek_hand_log_n or 0) < 40 then
        if rejected or trust_n > 0 then
            listen_accept._peek_hand_log_n = (listen_accept._peek_hand_log_n or 0) + 1
            write_log(
                string.format(
                    "=== [peek-hand] 7240=%d 77C0=%d 7610=%d 7630=%d rej=%s trust=%d meld=%d expect=%d plM=%d cpuM=%d %s ===\n",
                    probe[0x7240] or 0,
                    probe[0x77C0] or 0,
                    probe[0x7610] or 0,
                    probe[0x7630] or 0,
                    rejected and string.format("%04X", rejected) or "-",
                    trust_n,
                    meld_n,
                    expect_n,
                    pl_mn,
                    cpu_mn,
                    now()
                ),
                "a"
            )
        end
    end
    if trust_n > 0 then
        cpu_hand_cache = { raw = trust, src = cpu_hand_trusted.src }
        cpu_hand_src_addr = cpu_hand_trusted.src
        return trust, cpu_hand_trusted.src, true
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

function listen_accept.multiset_losses(old_m, new_m)
    local g = {}
    for v, n in pairs(old_m) do
        local d = n - (new_m[v] or 0)
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
    -- 追踪优先实读；@7240 空时用可信镜像（拒玩家串台；勿用清空前缓存）
    local cpu_raw = cpu7240
    if #cpu_raw == 0 or listen_accept.raw_looks_like_player(machine, cpu_raw) then
        cpu_raw = {}
        for _, addr in ipairs(CPU_HAND_FALLBACKS) do
            if addr ~= CPU_HAND_ADDR then
                local raws = read_cpu_hand_at(machine, addr)
                if #raws > #cpu_raw
                    and not listen_accept.raw_looks_like_player(machine, raws)
                then
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
    local pl_river_shrank = pl_rn < (prev.pl_rn or 0)
    local cpu_river_shrank = cpu_rn < (prev.cpu_rn or 0)

    listen_accept._peek_pl_rn = pl_rn
    listen_accept._peek_cpu_rn = cpu_rn
    -- 玩家每多打进河一口，世代 +1；记末张；清电脑摸入（你刚打出，电脑还没摸）
    if pl_river_grew then
        local grew = pl_rn - (prev.pl_rn or 0)
        cpu_hand_trusted.pl_discard_gen = (cpu_hand_trusted.pl_discard_gen or 0) + grew
        local endv = live.player_discard_raw and live.player_discard_raw[pl_rn]
        if endv and tile_valid(endv) then
            cpu_hand_trusted.last_pl_discard = endv
        end
        cpu_hand_trusted.pending_draw = nil
    end

    -- 电脑吃/碰：只认「玩家刚打出的那张」从河里消失/被改写（勿用 lost[1]，易认错牌）
    do
        local last = cpu_hand_trusted.last_pl_discard
        local prev_disc = prev.pl_discard_raw or {}
        local cur_disc = live.player_discard_raw or {}
        local claimed_gone = false
        if last and tile_valid(last) then
            if pl_river_shrank then
                local lost = listen_accept.multiset_losses(multiset_of(prev_disc), multiset_of(cur_disc))
                for _, v in ipairs(lost) do
                    if v == last then
                        claimed_gone = true
                        break
                    end
                end
                -- 缩短但集合对不上时：若上一口就在原河末，也认
                if not claimed_gone and (prev.pl_rn or 0) >= 1 then
                    if prev_disc[prev.pl_rn] == last then
                        claimed_gone = true
                    end
                end
            elseif pl_rn >= 1
                and pl_rn == (prev.pl_rn or 0)
                and prev_disc[pl_rn] == last
                and (cur_disc[pl_rn] or 0) ~= last
            then
                claimed_gone = true
            end
        end
        if claimed_gone
            and not cpu_river_shrank
            and cpu_hand_trusted.raw
            and #cpu_hand_trusted.raw >= 4
        then
            listen_accept._peek_meld_why = pl_river_shrank and "shrink" or "endchg"
            if listen_accept.patch_cache_after_cpu_meld(machine, last) then
                pcall(meld.dump_hunt, machine, string.format(
                    "auto-cpu-meld-claim=%02X",
                    last
                ))
            end
        end
    end

    -- @7250 块数增加但河缩检测漏了：按 RAM 强制对齐暗手（修「副露1 后一直 10」）
    do
        local cpu_m_now = meld.read_blocks(machine, meld.CPU_ADDR)
        local ram_n = #cpu_m_now
        local prev_cpu = cpu_hand_trusted.prev_cpu_meld_n
        if type(prev_cpu) == "number"
            and ram_n > prev_cpu
            and cpu_hand_trusted.raw
            and #cpu_hand_trusted.raw >= 4
        then
            local await = not cpu_river_grew
            if not cpu_hand_trusted.no_draw_discard then
                -- 若本帧尚未经 patch，先试正常扣牌
                local last = cpu_hand_trusted.last_pl_discard
                local did = false
                if last and tile_valid(last) then
                    listen_accept._peek_meld_why = "ram-grow"
                    -- 绕过 same-gen：对齐函数直接改张数
                    did = listen_accept.align_trust_to_cpu_melds(
                        machine,
                        ram_n,
                        await,
                        "ram-grow"
                    )
                else
                    did = listen_accept.align_trust_to_cpu_melds(
                        machine,
                        ram_n,
                        await,
                        "ram-grow-noclaim"
                    )
                end
                if did then
                    pcall(meld.dump_hunt, machine, string.format(
                        "auto-cpu-meld-ram=%d",
                        ram_n
                    ))
                end
            else
                -- 已标记副露后必打，仍可能张数没扣够
                listen_accept.align_trust_to_cpu_melds(
                    machine,
                    ram_n,
                    true,
                    "ram-grow-await"
                )
            end
        elseif ram_n >= 1
            and cpu_hand_trusted.raw
            and #cpu_hand_trusted.raw
                > meld.expected_closed_n(ram_n, cpu_hand_trusted.no_draw_discard) + 1
        then
            -- 稳态自愈：口数对但暗手多出 ≥2（漏扣副露或漏扣弃牌）
            listen_accept.align_trust_to_cpu_melds(
                machine,
                ram_n,
                cpu_hand_trusted.no_draw_discard and true or false,
                "stuck-oversize"
            )
        end
    end

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

    -- 电脑河变长：摸切/手切/副露后必打
    if cpu_river_grew then
        local river_end = live.cpu_discard_raw and live.cpu_discard_raw[cpu_rn]
        -- 二口副露常不缩玩家河：电脑未摸就打牌 → 先补扣吃碰
        -- 注意：@7502 常被写成「你刚打的那张」，不能当成 pending 摸入，否则永远挡掉补扣
        if cpu_hand_trusted.last_pl_discard
            and (cpu_hand_trusted.pl_discard_gen or 0) >= 1
            and cpu_hand_trusted.meld_at_gen ~= cpu_hand_trusted.pl_discard_gen
            and not cpu_hand_trusted.no_draw_discard
            and cpu_hand_trusted.raw
            and #cpu_hand_trusted.raw >= 4
        then
            local last = cpu_hand_trusted.last_pl_discard
            local pending = cpu_hand_trusted.pending_draw
            local pending_is_claim = pending and pending == last
            local real_draw = pending and not pending_is_claim
            if not real_draw then
                if pending_is_claim then
                    cpu_hand_trusted.pending_draw = nil
                end
                local cur_end = live.player_discard_raw and live.player_discard_raw[pl_rn]
                local table_is_claim = table_v and table_v == last
                -- 弃牌已离河末，或台面仍是该弃牌（吃碰未改河）
                local claim_like = (not cur_end)
                    or cur_end ~= last
                    or table_is_claim
                -- 即便 can_meld 认不出组合也要走 patch（内部 force-shrink）
                if claim_like then
                    listen_accept._peek_meld_why = "pre-discard"
                    if listen_accept.patch_cache_after_cpu_meld(machine, last) then
                        pcall(meld.dump_hunt, machine, string.format(
                            "auto-cpu-meld-predisc=%02X",
                            last
                        ))
                    end
                end
            end
        end
        local allow_disc = live.cpu_from_cache or cpu_hand_trusted.no_draw_discard
        if allow_disc
            and river_end
            and tile_valid(river_end)
            and (
                cpu_hand_trusted.no_draw_discard
                or (cpu_hand_trusted.last_discard_rn or 0) < cpu_rn
            )
        then
            if listen_accept.patch_cache_after_cpu_discard(river_end, table_v) then
                cpu_hand_trusted.last_discard_rn = cpu_rn
            end
        end
        if listen_accept.wait_bcd and not listen_accept.feed_done and not listen_accept.hold then
            pcall(listen_accept.tick_feed, machine)
        end
        if #cpu_gains > 0 then
            local pick = nil
            for _, v in ipairs(cpu_gains) do
                if v ~= river_end then
                    pick = v
                    break
                end
            end
            last_cpu_draw = pick or cpu_gains[1]
        elseif n_cpu > 0 and (prev.n_cpu or 0) > 0 then
            if tile_valid(river_end) then
                last_cpu_draw = river_end
            end
        end
        cpu_hand_trusted.pending_draw = nil
        if river_end and tile_valid(river_end) then
            -- 摸切：河末即摸入
            if last_cpu_draw and last_cpu_draw == river_end then
                pcall(cpu_win_probe.on_cpu_draw, last_cpu_draw)
            elseif last_cpu_draw then
                pcall(cpu_win_probe.on_cpu_draw, last_cpu_draw)
            end
            pcall(cpu_win_probe.on_cpu_discard, machine, river_end)
        end
    elseif n_cpu > (prev.n_cpu or 0) and not cpu_river_grew and #cpu_gains > 0 then
        -- 实读到摸入（或缓存模式下手数偶发可见）
        local pick = nil
        for _, v in ipairs(cpu_gains) do
            if table_v and v == table_v then
                pick = v
                break
            end
        end
        last_cpu_draw = pick or cpu_gains[1]
        if live.cpu_from_cache and last_cpu_draw and not cpu_hand_trusted.no_draw_discard then
            cpu_hand_trusted.pending_draw = last_cpu_draw
        end
        pcall(cpu_win_probe.on_cpu_draw, last_cpu_draw)
    elseif live.cpu_from_cache
        and not cpu_river_grew
        and not pl_river_grew
        and not cpu_hand_trusted.no_draw_discard
        and table_v
        and tile_valid(table_v)
        and table_v ~= prev.table
        and table_v ~= cpu_hand_trusted.last_pl_discard
        and not (n_pl > (prev.n_pl or 0))
    then
        -- 缓存模式下看不见电脑手增减时：用 @7502 变作本巡摸入候选（排除「刚吃的那张」）
        cpu_hand_trusted.pending_draw = table_v
    end

    pcall(cpu_win_probe.on_hand_count, n_cpu)

    -- 供下一帧 Donden：与 read_cpu_hand 同一套 @7120 连续读（勿用 sorted 截断，会误判对调）
    do
        local pl_snap = read_cpu_hand_at(machine, HAND_ADDR)
        if #pl_snap >= 7 then
            local pp = {}
            for i, v in ipairs(pl_snap) do
                pp[i] = v
            end
            cpu_hand_trusted.prev_player = pp
        end
        -- 副露块也随 Donden 互换：记下本帧计数供下一帧比对（两槽取大，连续块）
        local pl_m = meld.read_blocks(machine, meld.PLAYER_ADDR)
        local pl_m2 = meld.read_blocks(machine, meld.PLAYER_MIRROR)
        local cpu_m = meld.read_blocks(machine, meld.CPU_ADDR)
        local pl_n = math.max(#pl_m, #pl_m2)
        local prev_pl = cpu_hand_trusted.prev_pl_meld_n
        if type(prev_pl) == "number" and pl_n > prev_pl then
            pcall(meld.dump_hunt, machine, string.format(
                "auto-pl-meld %d→%d",
                prev_pl,
                pl_n
            ))
        end
        cpu_hand_trusted.prev_pl_meld_n = pl_n
        cpu_hand_trusted.prev_cpu_meld_n = #cpu_m
    end

    draw_track_prev = {
        pl = pl,
        cpu = cpu,
        table = table_v,
        pl_rn = pl_rn,
        cpu_rn = cpu_rn,
        n_pl = n_pl,
        n_cpu = n_cpu,
        pl_discard_raw = live.player_discard_raw,
        cpu_discard_raw = live.cpu_discard_raw,
    }
end

local function read_discard_hist(machine, addr)
    local raw, names = {}, {}
    -- 副露瞬间河首字节偶发 B7 等状态码：最多跳过 2 个非牌字节再读
    local start = 0
    while start < 2 do
        local v = mem.read_u8(machine, addr + start)
        if tile_valid(v) then
            break
        end
        if not v or v == 0 or v == 0xFF then
            break
        end
        start = start + 1
    end
    for i = start, DISCARD_HIST_MAX - 1 do
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
    local wait = listen_accept.wait_bcd
    for _, v in ipairs(cpu_raw) do
        local t = bcd_tile_obj(v)
        if wait and v == wait then
            t.force_hi = true
        end
        tiles[#tiles + 1] = t
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

function cpu_win_probe._pool_left(machine, bcd)
    if not machine or not bcd then
        return -1
    end
    local counts = wall_pool_counts(machine)
    return counts[bcd] or 0
end

function cpu_win_probe._emit(code, detail)
    local p = cpu_win_probe
    write_log(
        string.format(
            "=== [cpu-win-probe] #%d code=%s id=%s %s mode=%s fc=%s skip=%s disc=%d draw=%s detail=%s %s ===\n",
            p.session,
            code,
            p.id or "?",
            p.label or "",
            p.mode or "?",
            p.first_chance and "Y" or "N",
            p.saw_skip and "Y" or "N",
            p.discard_n,
            p.last_draw and tile_name(p.last_draw) or "-",
            detail or "",
            now()
        ),
        "a"
    )
    if code == "S_discard" or code == "S_pass" or code == "W_retry" or code == "W0" then
        pcall(function()
            ui_toast.show(
                string.format("电脑必和探测 %s\n%s", code, detail or ""),
                220
            )
        end)
    end
end

function cpu_win_probe.arm(preset, mode, first_chance, tiles)
    local p = cpu_win_probe
    p.active = true
    p.session = (p.session or 0) + 1
    p.id = preset and preset.id or "?"
    p.label = preset and preset.label or ""
    p.mode = mode or "?"
    p.first_chance = first_chance and true or false
    p.complete14 = tiles and #tiles == 14
    p.tenhou_only = preset and preset.tenhou_only and true or false
    p.wait = {}
    p.key = {}
    if preset and preset.wait_bcd then
        for _, v in ipairs(preset.wait_bcd) do
            p.wait[v] = true
        end
    end
    if preset and preset.key_bcd then
        for _, v in ipairs(preset.key_bcd) do
            p.key[v] = true
        end
    end
    -- 完整 14 张：任意弃牌都算错过必和窗（天和/已听满）
    if p.complete14 then
        for _, v in ipairs(tiles or {}) do
            p.key[v] = true
        end
    end
    p.saw_skip = false
    p.last_draw = nil
    p.draw_was_wait = false
    p.discard_n = 0
    p.coded = false
    p.last_n_cpu = tiles and #tiles or nil
    cpu_win_probe._emit(
        "ARM",
        string.format(
            "tiles=%d wait=%s tenhou_only=%s",
            tiles and #tiles or 0,
            (preset and preset.wait_hint) or "-",
            p.tenhou_only and "Y" or "N"
        )
    )
end

function cpu_win_probe.on_cpu_draw(v)
    local p = cpu_win_probe
    if not p.active or not v or not tile_valid(v) then
        return
    end
    p.last_draw = v
    p.draw_was_wait = p.wait[v] == true
        or (p.complete14 and false)
        or false
    -- 13 张听：摸入听张 = 必和摸胡窗
    if p.wait[v] then
        p.draw_was_wait = true
        write_log(
            string.format(
                "=== [cpu-win-probe] #%d MUSTWIN-DRAW %s (%02X) %s ===\n",
                p.session,
                tile_name(v),
                v,
                now()
            ),
            "a"
        )
    end
end

function cpu_win_probe.on_cpu_discard(machine, v)
    local p = cpu_win_probe
    if not p.active or not v or not tile_valid(v) then
        return
    end
    p.discard_n = p.discard_n + 1
    local pool_left = cpu_win_probe._pool_left(machine, v)
    local detail = string.format(
        "out=%s(%02X) pool_left=%d must_draw=%s",
        tile_name(v),
        v,
        pool_left,
        p.draw_was_wait and tile_name(p.last_draw) or "-"
    )
    local code = nil
    -- 天和/14 张窗：首打即弃和
    if p.complete14 and p.discard_n == 1 and not p.coded then
        code = "S_discard"
        detail = detail .. " why=tenhou_or_14_first_discard"
    elseif p.draw_was_wait and p.last_draw == v and not p.coded then
        code = "S_discard"
        detail = detail .. " why=tsumo_tile_cut"
    elseif p.draw_was_wait and p.key[v] and not p.coded then
        code = "S_discard"
        detail = detail .. " why=break_yakuman_after_wait"
    elseif p.draw_was_wait and not p.coded then
        -- 摸到听张却打了别的（未立刻和）
        code = "S_discard"
        detail = detail .. " why=had_wait_drew_but_discarded_other"
    elseif p.key[v] and p.discard_n <= 2 and not p.coded and (p.complete14 or p.tenhou_only) then
        code = "S_discard"
        detail = detail .. " why=key_tile_early"
    end
    if code then
        p.saw_skip = true
        p.coded = true
        cpu_win_probe._emit(code, detail)
    else
        write_log(
            string.format(
                "=== [cpu-win-probe] #%d DISCARD %s %s ===\n",
                p.session,
                detail,
                now()
            ),
            "a"
        )
    end
    p.draw_was_wait = false
end

function cpu_win_probe.on_hand_count(n_cpu)
    local p = cpu_win_probe
    if not p.active then
        return
    end
    local prev = p.last_n_cpu
    p.last_n_cpu = n_cpu
    if type(prev) ~= "number" or type(n_cpu) ~= "number" then
        return
    end
    -- 手数从听牌/和形骤降至 0：局终。若从未弃过且完整 14 → W0；若曾 S_* → W_retry
    if prev >= 10 and n_cpu == 0 then
        if p.saw_skip then
            cpu_win_probe._emit("W_retry", "hand_cleared_after_skip")
        elseif p.complete14 and p.discard_n == 0 then
            cpu_win_probe._emit("W0", "hand_cleared_no_discard")
        elseif p.discard_n == 0 then
            cpu_win_probe._emit("W0", "hand_cleared_no_discard_13listen")
        else
            cpu_win_probe._emit("END", string.format("hand_cleared disc=%d", p.discard_n))
        end
        p.active = false
    end
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
    local cpu_rn = #(live.cpu_discard_raw or {})
    local pl_rn = #(live.player_discard_raw or {})
    local pl_n = #(live.sorted_raw or {})
    -- 你副露时 @7120 常被清空：回退 @72C0 镜像手数
    if pl_n < 1 then
        local mir = read_cpu_hand_at(machine, HAND_MIRROR_ADDR)
        if #mir >= 1 then
            pl_n = #mir
        end
    end
    -- 副露/对调瞬间河表空读：HUD 暂用上次非零（逻辑追踪仍用本帧实读）
    if pl_n > 0 then
        hud_sticky.pl_n = pl_n
    elseif hud_sticky.pl_n > 0 then
        pl_n = hud_sticky.pl_n
    end
    if pl_rn > 0 then
        hud_sticky.pl_rn = pl_rn
    elseif hud_sticky.pl_rn > 0 then
        pl_rn = hud_sticky.pl_rn
    end
    if cpu_rn > 0 then
        hud_sticky.cpu_rn = cpu_rn
    elseif hud_sticky.cpu_rn > 0 then
        cpu_rn = hud_sticky.cpu_rn
    end
    local line1_parts = {
        string.format("牌池剩 %d", pool_n),
        string.format("你手%d", pl_n),
        string.format("你河%d", pl_rn),
        string.format("电脑河%d", cpu_rn),
    }
    do
        -- 你副露 / 电脑副露：直接读 RAM 块内容（81吃/82碰）
        local pl_blocks = meld.read_blocks(machine, meld.PLAYER_MIRROR)
        if #pl_blocks == 0 then
            pl_blocks = meld.read_blocks(machine, meld.PLAYER_ADDR)
        end
        local cpu_blocks = meld.read_blocks(machine, meld.CPU_ADDR)
        -- 电脑副露只信 @7250；对调后空表必须清计数（勿幽灵「副露2」）
        -- 刚吃碰尚未写表的一帧：保留 no_draw 期间的计数
        if #cpu_blocks > 0 then
            cpu_hand_trusted.meld_count = #cpu_blocks
        elseif not cpu_hand_trusted.no_draw_discard then
            cpu_hand_trusted.meld_count = 0
        end
        local cpu_meld_n = #cpu_blocks
        if cpu_meld_n == 0 and cpu_hand_trusted.no_draw_discard then
            cpu_meld_n = cpu_hand_trusted.meld_count or 0
        end
        if #pl_blocks > 0 then
            line1_parts[#line1_parts + 1] = string.format(
                "你副露%d:%s",
                #pl_blocks,
                meld.format_blocks(pl_blocks)
            )
        end
        if #cpu_blocks > 0 then
            local expect = meld.expected_closed_n(
                #cpu_blocks,
                cpu_hand_trusted.no_draw_discard
            )
            line1_parts[#line1_parts + 1] = string.format(
                "电脑副露%d→暗%d:%s",
                #cpu_blocks,
                expect,
                meld.format_blocks(cpu_blocks)
            )
        elseif cpu_meld_n > 0 then
            line1_parts[#line1_parts + 1] = string.format(
                "电脑副露%d→暗%d",
                cpu_meld_n,
                meld.expected_closed_n(cpu_meld_n, true)
            )
        end
    end
    if #cpu_hand > 0 then
        line1_parts[#line1_parts + 1] = string.format("电脑手%d", #cpu_hand)
        if live.cpu_from_cache then
            line1_parts[#line1_parts + 1] = "副露缓存"
        end
    else
        line1_parts[#line1_parts + 1] = "电脑手空"
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
    local src_tag = ""
    if live.cpu_from_cache then
        src_tag = " · 副露缓存"
    elseif live.cpu_src == 0x7240 then
        src_tag = " · 实读"
    elseif live.cpu_src then
        src_tag = " · 镜像"
    end
    local cpu_label = string.format("电脑手 (%d)%s", #cpu_hand, src_tag)
    if #cpu_hand == 0 then
        cpu_label = "电脑手（副露中·暂无可信读数）"
    end
    if listen_accept.wait_bcd then
        cpu_label = cpu_label .. " · 喂荣:" .. listen_accept.wait_name()
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
        note1 = "暗手张数=13-3×副露 · 副露随 Donden 互换",
        note2 = "玩家副露不改电脑暗手 · 喂荣改手已暂停",
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
    -- 只计 @7120..712C（13 张排序手）；勿含 @712D（台面缓冲，常已有牌 → 手数假 14 → 摸入检测永久失败）
    local n = 0
    for i = 0, HAND_SORTED - 1 do
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
            ui_toast.show("牌池已是控摸态且无真备份 · 请结束本局再开", 180)
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
    force_draw.armed_zeros = 0
    force_draw.prev_n = force_draw.armed_pl_n
    force_draw.prev_pl_rn = 0
    pcall(function()
        local raw = read_discard_hist(machine, PLAYER_DISCARD_ADDR)
        force_draw.prev_pl_rn = #raw
    end)
    force_draw.prev_7502 = mem.read_u8(machine, TABLE_TILE_ADDR)
    local tap_ok = force_draw.tap_install(machine)
    listen_accept.on_force_arm()
    write_log(
        string.format(
            "=== [force-draw] ARM %s (%02X) pool-only tap=%s %s ===\n",
            tile_name(bcd),
            bcd,
            tap_ok and "Y" or "N",
            now()
        ),
        "a"
    )
    ui_toast.show(
        string.format(
            "控摸开 → 下一摸 %s · 摸入自动关%s",
            tile_name(bcd),
            tap_ok and "" or " · 手数兜底"
        ),
        150
    )
end

function force_draw.disarm(machine, reason, toast_msg)
    reason = reason or "manual"
    local bak = force_draw.sticky_backup or force_draw.backup
    if not force_draw.armed and not bak then
        force_draw.tap_rm()
        return false
    end
    if bak then
        pcall(function()
            force_draw.restore_pool(machine, bak)
        end)
    end
    local forced_bak = force_draw.backup_looks_forced(bak)
    force_draw.clear_armed()
    force_draw.tap_rm()
    listen_accept.on_force_disarm()
    write_log(
        string.format("=== [force-draw] DISARM (%s) %s ===\n", reason, now()),
        "a"
    )
    if toast_msg then
        ui_toast.show(toast_msg, 150)
    elseif not bak then
        ui_toast.show("控摸关 · 无牌池备份可恢复", 150)
    elseif forced_bak then
        ui_toast.show("控摸关 · 备份已污染 · 本局多样性无法还原", 180)
    else
        ui_toast.show("控摸关 · 牌池已恢复", 120)
    end
    return true
end

function force_draw.run_tick(machine)
    force_draw.consume_pending(machine)
    listen_accept.consume_pending(machine)
    -- 喂荣 tick 只在主帧循环跑一次，避免双倍 countdown / 双 COMMIT
    if not force_draw.armed then
        return
    end
    if not force_draw.tap and (force_draw.tick % 32) == 2 then
        pcall(force_draw.tap_install, machine)
    end
    force_draw.tick = (force_draw.tick or 0) + 1
    local target = force_draw.target_bcd()
    local name = tile_name(target)
    local z = force_draw.pool_zero_count(machine)
    if z > (force_draw.armed_zeros or 0) then
        force_draw.disarm(
            machine,
            string.format("pool_taken_z%d", z),
            string.format("控摸已摸入 · 曾锁 %s · 牌池已恢复", name)
        )
        return
    end
    local n = player_hand_len(machine)
    local pl_rn = 0
    pcall(function()
        local raw = read_discard_hist(machine, PLAYER_DISCARD_ADDR)
        pl_rn = #raw
    end)
    local t7502 = mem.read_u8(machine, TABLE_TILE_ADDR)
    local base = force_draw.armed_pl_n or n
    if n < base then
        force_draw.disarm(
            machine,
            string.format("hand_drop_%d_to_%d", base, n),
            string.format("控摸：手数回落（%d→%d）已关 · 曾锁 %s", base, n, name)
        )
        return
    end
    local prev_7502 = force_draw.prev_7502
    if prev_7502 ~= nil and t7502 == target and prev_7502 ~= t7502 and pl_rn <= (force_draw.prev_pl_rn or pl_rn) then
        force_draw.disarm(
            machine,
            "7502_to_target",
            string.format("控摸已摸入 · 曾锁 %s · 牌池已恢复", name)
        )
        return
    end
    local prev_n = force_draw.prev_n
    local prev_rn = force_draw.prev_pl_rn or 0
    if prev_n ~= nil and n > prev_n and pl_rn <= prev_rn then
        force_draw.disarm(
            machine,
            string.format("sorted_+1_%d_to_%d", prev_n, n),
            string.format("控摸已摸入（手 %d→%d）· 曾锁 %s", prev_n, n, name)
        )
        return
    end
    if n > base then
        local jump = n - base
        if jump > 1 then
            force_draw.disarm(
                machine,
                string.format("player_hand_%d_to_%d", base, n),
                string.format("控摸：手数跳增（%d→%d）已关 · 曾锁 %s", base, n, name)
            )
        else
            force_draw.disarm(
                machine,
                string.format("player_hand_%d_to_%d", base, n),
                string.format("控摸已摸入（手 %d→%d）· 曾锁 %s", base, n, name)
            )
        end
        return
    end
    if (force_draw.tick % 8) == 1 then
        force_draw.fill_pool(machine, target)
        force_draw.armed_zeros = 0
    end
    force_draw.prev_n = n
    force_draw.prev_pl_rn = pl_rn
    force_draw.prev_7502 = t7502
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
        force_draw.armed_zeros = 0
        write_log(
            string.format("=== [force-draw] RETARGET %s (%02X) %s ===\n", tile_name(bcd), bcd, now()),
            "a"
        )
        ui_toast.show(string.format("控摸改 → %s · 摸入自动关", tile_name(bcd)), 120)
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
    if machine then
        local pl_m = meld.read_blocks(machine, meld.PLAYER_ADDR)
        local pl_m2 = meld.read_blocks(machine, meld.PLAYER_MIRROR)
        local cpu_m = meld.read_blocks(machine, meld.CPU_ADDR)
        local meld_n = cpu_hand_trusted.meld_count or 0
        t[#t + 1] = string.format(
            "  副露 pl@7130(%d): %s",
            #pl_m,
            meld.format_blocks(pl_m)
        )
        t[#t + 1] = string.format(
            "  副露 pl@72D0(%d): %s",
            #pl_m2,
            meld.format_blocks(pl_m2)
        )
        t[#t + 1] = string.format(
            "  副露 cpu@7250(%d): %s",
            #cpu_m,
            meld.format_blocks(cpu_m)
        )
        t[#t + 1] = string.format(
            "  暗手期望: cpu_meld_n=%d expect=%d trust=%d pl_meld_n=%d",
            meld_n,
            meld.expected_closed_n(meld_n, cpu_hand_trusted.no_draw_discard),
            cpu_hand_trusted.raw and #cpu_hand_trusted.raw or 0,
            #pl_m
        )
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

local cpu_feed_click_bcd = nil

local function hit_cpu_feed_xy(view, x, y)
    if not peek_open or not tiles_ui or not tiles_ui.hit_mjelctrn_cpu then
        return nil
    end
    local ux, uy
    if tiles_ui.view_to_ui01 then
        ux, uy = tiles_ui.view_to_ui01(view, x, y)
    elseif tiles_ui.view_to_screen then
        ux, uy = tiles_ui.view_to_screen(view, x, y)
    end
    if not ux then
        return nil
    end
    return tiles_ui.hit_mjelctrn_cpu(ux, uy)
end

local function apply_cpu_feed_click(machine)
    if not cpu_feed_click_bcd then
        return
    end
    local bcd = cpu_feed_click_bcd
    cpu_feed_click_bcd = nil
    listen_accept.set_wait(bcd)
end

local function hit_hand_pat_xy(view, x, y)
    if not peek_open then
        return nil
    end
    local ux, uy
    if tiles_ui and tiles_ui.view_to_ui01 then
        ux, uy = tiles_ui.view_to_ui01(view, x, y)
    elseif tiles_ui and tiles_ui.view_to_screen then
        ux, uy = tiles_ui.view_to_screen(view, x, y)
    end
    if not ux then
        return nil
    end
    return hand_pat.hit(ux, uy)
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
    if not peek_open then
        hand_pat.menu_open = false
        hand_pat.hits = {}
        -- 关透视不再清喂荣锁定（锁定后可关面板等电脑打牌）
    end
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

local function apply_hand_pat_click(machine)
    if not hand_pat.click_id then
        return
    end
    local id = hand_pat.click_id
    hand_pat.click_id = nil
    hand_pat.on_click(machine, id)
end

local function draw_peek_panel(machine)
    if not peek_open then
        return
    end
    -- 暂停时 screen 帧号不动：若仍用帧号去重，periodic 重画会被跳过 → 面板消失
    local paused = false
    pcall(function()
        paused = machine.paused and true or false
    end)
    local frame_n = nil
    pcall(function()
        local scr = machine.screens[":screen"]
        if scr and scr.frame_number then
            frame_n = scr:frame_number()
        end
    end)
    if (not paused) and frame_n ~= nil and frame_n == last_peek_draw_frame then
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
        pcall(hand_pat.draw, ui, machine)
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


function meld.diff_windows(a, b, tag)
    -- a/b 为 hot 区（基址 @7100）；副露块在 known 里会被 UNKNOWN 滤掉，这里单独 FULL diff
    local windows = {
        { name = "pl@7130", off = 0x7130 - 0x7100, len = 0x40 },
        { name = "pl@72D0", off = 0x72D0 - 0x7100, len = 0x40 },
        { name = "cpu@7250", off = 0x7250 - 0x7100, len = 0x40 },
    }
    for _, w in ipairs(windows) do
        if #a >= w.off + w.len and #b >= w.off + w.len then
            local sa = a:sub(w.off + 1, w.off + w.len)
            local sb = b:sub(w.off + 1, w.off + w.len)
            if sa ~= sb then
                write_log(
                    diff_bufs(sa, sb, tag .. " MELD " .. w.name, 0x7100 + w.off),
                    "a"
                )
            end
        end
    end
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
    meld.diff_windows(a, b, tag)
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
    pcall(meld.dump_hunt, machine, "baseline-" .. (snap.tag or "?"))
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
    pcall(meld.dump_hunt, machine, string.format("step-%d", step_idx))
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
    listen_accept.read_tap_rm()
    listen_accept.feed_tap_rm()
    listen_accept.clear_ram(machine)
    listen_accept.probe_reset()
    listen_accept.wait_bcd = nil
    listen_accept.feed_done = false
    listen_accept.feed_pending_was = nil
    listen_accept.feed_fallback_rn = nil
    listen_accept.feed_sticky = false
    listen_accept.pending_commit = nil
    listen_accept.pending_clear_wait = nil
    pool_click_bcd = nil
    cpu_feed_click_bcd = nil
    hand_pat.menu_open = false
    hand_pat.hits = {}
    hand_pat.click_id = nil
    hand_pat.hold = nil
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
            if not m.paused then
                ptr_tick()
                return
            end
            -- 暂停时 frame_done 不跑：补点击 + 持续重画透视（可与暂停并存）
            apply_peek_click(m)
            apply_sangen_click(m)
            apply_accept_click(m)
            if bleed.click then
                bleed.click = false
                bleed.arm(m)
            end
            apply_pool_click(m)
            apply_cpu_feed_click(m)
            apply_hand_pat_click(m)
            if bleed.press_frames > 0 then
                bleed.press_frames = bleed.press_frames - 1
            end
            if peek_open or SHOW_DEBUG_HUD then
                pcall(function()
                    local live = read_live_peek(m)
                    update_draw_track(m, live)
                end)
                pcall(draw_peek_panel, m)
                pcall(draw_text_hud, m)
            end
            pcall(ui_toast.draw, m)
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
            local hid = hit_hand_pat_xy(view, x, y)
            if hid then
                hand_pat.click_id = hid
                ptr_mark_busy(0.25)
                return
            end
            local feed_bcd = hit_cpu_feed_xy(view, x, y)
            if feed_bcd then
                cpu_feed_click_bcd = feed_bcd
                ptr_mark_busy(0.25)
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
    apply_cpu_feed_click(machine)
    apply_hand_pat_click(machine)
    if bleed.press_frames > 0 then
        bleed.press_frames = bleed.press_frames - 1
    end
    pcall(function()
        force_draw.run_tick(machine)
    end)
    pcall(function()
        hand_pat.tick(machine)
    end)
    pcall(listen_accept.tick_feed, machine)
    pcall(listen_accept.tick_hold, machine)
    pcall(listen_accept.consume_pending, machine)
    pcall(function()
        sangen_watch_tick(machine)
    end)
    pcall(ui_toast.draw, machine)
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
