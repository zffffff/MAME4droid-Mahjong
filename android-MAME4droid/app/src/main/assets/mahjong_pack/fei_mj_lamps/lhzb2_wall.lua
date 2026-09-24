-- lhzb2（龙虎争霸2）透视 Phase 0：内存 hunt + 文字 HUD 骨架
-- 硬件（MAME igs017）：MC68000；工作区候选：
--   0x100000..0x103FFF  sharedprotram（与保护 MCU 共享）
--   0x500000..0x503FFF  nvram（局内状态常在此）
-- 编码未知：同时扫 BCD-A / BCD-B / 0..33 线性，找到后再钉死。
--
-- 热键（右 Ctrl，避免杠牌键冲突）：
--   右Ctrl+5  基准快照（覆盖 log）+ open/meld/cpu-discard hunt
--   右Ctrl+2  步进 diff + open/meld/cpu-discard hunt
--   右Ctrl+3  仅全扫（含上述 hunt）
--   右Ctrl+9 / 右Ctrl+0  开/关牌图透视（复用 ui_tiles）
--   右Ctrl+7  控摸：切换目标牌
--   右Ctrl+8  控摸：开/关（整池只留目标种；remain 下降则单次自动关并恢复）
--   右/左Ctrl+6  下一摸强制搓（换牌/局中均=暗牌旗@501444；搓中=脱困）
--   透视开时：点电脑手=锁定要打出的牌；点牌池=控摸；电脑手只读对齐
--   电脑弃牌：若已锁定则改河末（不暂停）；待打窗自动写 [disc-decision]（猎手切）
--   搓牌：自然 remain↓ 暗牌窗 @501444=01 @50173E=00（@217 仍02）；进 UI 后游戏改 @217
--   （不用 F9：MAME 默认 F9=跳帧/skip，会抢走）
-- log：smoke_logs/lhzb2_wall.log
--
-- 玩法备注（2026-09-22 用户）：
--   玩家永远庄（先摸）；开局交换牌等待后摸第一张才正式开打。
--   强制搓（2026-09-24 结案）：局中 remain↓ 写暗牌旗即可完整走通（含暗牌动画）。
--
-- 已钉（2026-09-22 画面核对）：玩家手 @50019A、电脑手 @50013E；
--   编码高半字节花色(0万/1筒/2条/3字)、低半字节 0..8→1..9；@500199=01 头字节。
--   刚摸可疑 @50033A；弃牌 @500185。
--   搓牌模式候选 @500217：搓牌中=00 / 正常=02；@500339 搓牌中=00 / 正常=01。
--   剩张 @500918、牌池 34×@50091A 已确认；有序山未钉。
--   存档读档后连摸五张牌序不同 → 更像「库存池+RNG」而非固定有序墙（同电子基盘类机制）。
--   副露后 @50013E 常带长度头：一口 0x0A、二口 0x07（合法「8万」码，须当长度头）。
--   HUD 只直读主槽+长度头（不开镜像 fallback）；明牌局用 [open-hand-hunt] 钉显示/逻辑源。
--   押20/听牌后电脑明牌 → 优先对照画面找缓冲；暗手下验证是否同一地址。

local LOG_PATH = "smoke_logs/lhzb2_wall.log"

local LHZB2_FAMILY = {
    lhzb2 = true,
    lhzb2a = true,
    lhzb2b = true,
    lhzb2c = true,
}

-- 先扫这两块；命中后可再扩
local RANGES = {
    { tag = ":maincpu", space = "program", start = 0x100000, size = 0x4000, name = "68k_prot" },
    { tag = ":maincpu", space = "program", start = 0x500000, size = 0x4000, name = "68k_nvram" },
}

local BCD_A = {} -- 01-09 / 11-19 / 21-29 / 31-37（电子基盘/rbmk 常见）
local BCD_B = {} -- 11-19 / 21-29 / 31-39 / 41-47
for i = 1, 9 do
    BCD_A[i] = true
    BCD_A[0x10 + i] = true
    BCD_A[0x20 + i] = true
    BCD_B[0x10 + i] = true
    BCD_B[0x20 + i] = true
    BCD_B[0x30 + i] = true
end
for i = 1, 7 do
    BCD_A[0x30 + i] = true
    BCD_B[0x40 + i] = true
end

local peek_open = false -- 默认关；点透视钮或 Ctrl+9/0 开；暂停时靠 periodic 画/读键
local snap_base = nil
local step_idx = 0
local last_hits = {}
local PAUSE_ON_HUNT = true -- Ctrl+5/2/3 与副露 auto 仍可暂停
-- 电脑每打一张：不再自动暂停（河采数已够；喂荣时也不能停）
local AUTO_DISCARD_PAUSE = false
local AUTO_DISCARD_HUNT_LOG = false -- 未喂荣时不刷 AUTO-DISCARD 全文
-- 2026-09-22 用户牌面钉死（step02）：
-- 玩家 @50019A：14 14 15 15 16 17 21 21 30 30 30 31 32（前一字节 @500199=01 像头/标志）
-- 电脑 @50013E：06 07 12 13 14 15 16 16 16 21 21 23 24
local PLAYER_HAND_ADDR = 0x50019A
local CPU_HAND_ADDR = 0x50013E
-- 明牌缓冲：hunt 用；暗/明共用主槽后一般保持 nil
local OPEN_HAND_ADDR = nil
-- 电脑副露标记表（2026-09-23 三口碰实测）：按口 1 字节追加，非 mark+3 牌
local MELD_CPU_ADDR = 0x50014C
local MELD_PTR_ADDR = 0x500156 -- 常见 01 xx，随口数变（BC→78→34…）
local HYP_LAST_DRAW = 0x50033A
-- 电脑河 @500185 起追加，读到玩家手前一字节为止（@50019A）
local CPU_RIVER_ADDR = 0x500185
local CPU_RIVER_END = 0x50019A -- exclusive；越过会把玩家手读进「河」
local CPU_RIVER_SPAN = CPU_RIVER_END - CPU_RIVER_ADDR
local HYP_LAST_DISC = CPU_RIVER_ADDR -- 兼容旧名：河首；最新弃牌用 read_cpu_river 末张
-- 弃牌邻域 + 河前若干；回合头 @50013D
local CPU_DISC_WATCH = {
    0x50013D,
    0x500185,
    0x500186,
    0x500187,
    0x500188,
    0x500189,
    0x50018A,
    0x50018B,
    0x50018C,
    0x50018D,
    0x50018E,
    0x50018F,
    0x500190,
    0x500191,
    0x50033A,
    0x50033B,
    0x500217,
    0x500339,
    -- 手切/摸切决定猎取（2026-09-23 bin）
    0x50089A,
    0x50089B,
    0x50089C,
    0x50089D,
    0x50089E,
    0x5008A2,
    0x5008A6,
    0x5008A7,
    0x5008A8,
    0x5008A9,
    0x5008AA,
    0x500233,
    0x500235,
    0x500469,
}
-- 待打窗自动轻量采数（非整 nvram）
local DISCARD_DECISION_AUTO = true
-- 锁定后在待打窗改写「决定带」试控打（手切候选 @500890..89E + 摸槽）
local DISCARD_DECISION_POKE = true
local DISCARD_DECISION_POKE_LO = 0x500890
local DISCARD_DECISION_POKE_HI = 0x50089E
local DISCARD_DECISION_RANGES = {
    { 0x50013C, 0x500160 }, -- 回合头+暗手
    { 0x500220, 0x500250 }, -- 结构表（手切候选区）
    { 0x500460, 0x500480 },
    { 0x500890, 0x5008B0 }, -- 89D=摸切候选；8A2+=弃牌史；手切见 891/89C
    { 0x500330, 0x500340 }, -- 摸槽
}
local PROT_TURN_WATCH = { 0x100299, 0x10029A, 0x10029B, 0x10029F, 0x100201, 0x100203 }
-- 点电脑手锁定目标：河追加时改河末+镜像；手槽对调默认关（会污染 HUD、画面手仍不变）
local DISCARD_HIJACK_ENABLE = false -- 实测：写 @50013E 只改 HUD，真手/播报仍跟原弃牌
local DISCARD_FEED_ENABLE = true -- 河末/镜像喂荣
local discard_lock = {
    lhzb = nil,
    armed = false,
    feed_hold = nil, -- { addr, v, was, mirrors={addr…}, frames, swapped }
    river_tap = nil,
    hold_tap = nil,
}
local BONUS_MODE_ADDR = 0x500217 -- 搓牌中=00 / 正常=02；强制进搓 POKE 目标
local DRAW_FLAG_ADDR = 0x500339 -- 搓牌中=00 / 正常=01；进搓后助加深
local BONUS_1FE_ADDR = 0x5001FE -- 进搓同拍常 →FF
local BONUS_33F_ADDR = 0x50033F -- 搓中常 D0→1C/57
local WALL_REMAIN_ADDR = 0x500918 -- 已确认剩余张数（例 110→109）
local WALL_POOL_ADDR = 0x50091A -- 34 字节牌型库存 0..4；3筒在 +11=@925
local WALL_POOL_LEN = 34
local WALL_BASE_ADDR = nil -- 有序「下摸队列」尚未钉
local BONUS_ARM_ENABLE = true -- 右Ctrl+6：仅换牌等待预约（局中禁用）
local BONUS_AUTO_HUNT = false -- 结案后默认关；开启会每巡 dump bin，打牌明显卡顿
local BONUS_AUTO_PAUSE = false -- 注入 hunt 期间不停机，方便连续打牌
local bonus_force_suppress_auto_pause = false -- 强制写入期间勿因 enter 自动暂停
local periodic_on = false
local boot_toast_done = false
local bonus_arm = false -- 已预约「下一摸」
local last_draw_slot = nil
-- 搓牌 API 表：提前声明，供指针点击闭包引用（勿放在 apply_* 之后再 local B）
local B = {}
local bonus_arm_state = {
    prev_remain = nil,
    prev_player_n = nil,
    prev_river_n = nil,
    river_grow_at = nil,
    river_stable = 0,
    holding = false,
    hold_tick = 0,
    fired = false,
    bak = nil,
    hold_why = nil,
    guard_exit = false,
    await_deepen = false,
    post_pulse_tick = 0,
    from_exchange = false,
    auto_finish = false,
    auto_finish_tick = 0,
    exit_hold_left = 0,
    toggle_cool = 0,
}
local bonus_auto = {
    prev_217 = nil,
    prev_339 = nil,
    prev_1fe = nil,
    prev_33f = nil,
    prev_067 = nil,
    prev_remain = nil,
    prev_33a = nil,
    prev_player_n = nil,
    player_n_stable = 0,
    prev_river_n = nil,
    river_grow_at = nil,
    river_stable = 0,
    cooldown = 0,
    seq = 0,
    last_snap = nil,
    in_round = false, -- 已见正常局内 @217=02 且手牌有效
    predraw_067_mode = nil, -- 常态摸前 @067（多见 3F）
    predraw_1fe_mode = nil,
    last_disc_frame = -999,
    seen_enter = false,
    prev_135 = nil,
    -- 电脑打完→开摸：连续采（不停机）
    predraw_stream = false,
    predraw_tick = 0,
    predraw_snaps = 0,
    predraw_sig = nil,
}
-- 仅副露后主槽短暂空读时粘滞；开局不稳不用 hold 顶假满手
local cpu_hand_hold = { bytes = {}, addr = CPU_HAND_ADDR, remain = nil, disc = nil, empty_streak = 0 }
local peek_state = nil
local pool_click_bcd = nil
local cpu_click_bcd = nil
local last_peek_draw_frame = -1
local hand_live_cache = { frame = -1, bytes = nil, addr = nil, held = false }
local meld_watch = {
    prev_n = nil,
    stable_n = nil,
    stable_frames = 0,
    cpu_addr = nil,
    blocks = {},
    bag_hint = nil,
}
-- 电脑弃牌自动抓拍：待打张数→打完（14→13 / 11→10 / …）
local discard_auto = {
    prev_n = nil,
    stable_n = nil,
    stable_frames = 0,
    snap_pre = nil,
    cooldown = 0,
    last_disc = nil,
    prev_river_n = nil,
    river_stable = 0,
}
-- 待打窗轻量快照：进 await 记一枪，河+1 再 diff（猎手切决定）
local discard_decision = {
    await_on = false,
    stable = 0,
    dumped = false,
    pre = nil, -- { t, draw, hand_n, bytes={ [addr]=v } }
    seq = 0,
}
local open_hand_watch = { pinned = nil, last_cands = {} }
-- 控摸目标：lhzb 编码（与池下标对应）
local FORCE_TILES = {}
do
    for i = 0, 8 do
        FORCE_TILES[#FORCE_TILES + 1] = i
    end
    for i = 0x10, 0x18 do
        FORCE_TILES[#FORCE_TILES + 1] = i
    end
    for i = 0x20, 0x28 do
        FORCE_TILES[#FORCE_TILES + 1] = i
    end
    for i = 0x30, 0x36 do
        FORCE_TILES[#FORCE_TILES + 1] = i
    end
end
local force_draw = {
    armed = false,
    tile_i = 5, -- 默认 五万 (0x04)
    backup = nil, -- { pool=34bytes, remain=n }
    sticky_backup = nil,
    prev_remain = nil,
    prev_target_cnt = nil,
    tick = 0,
}
local tiles_ui = nil
pcall(function()
    local loader = loadfile("fei_mj_lamps/ui_tiles.lua")
    tiles_ui = loader and loader() or nil
end)

local seq5, seq2, seq3, seq9, seq0, seq6, seq6l, seq7, seq8
local prev = {}
local keys_bound_ok = false
local function now()
    return os.date("%H:%M:%S")
end

local function is_family(name)
    return name and LHZB2_FAMILY[name] == true
end

local function write_log(text, mode)
    local f = io.open(LOG_PATH, mode or "a")
    if not f then
        f = io.open("lhzb2_wall.log", mode or "a")
    end
    if not f then
        print("[lhzb2_wall] cannot open log")
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
        return v
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

local function read_region(machine, r)
    local buf = {}
    local n = r.size
    for i = 0, n - 1 do
        buf[i + 1] = string.char(mem.read_u8(machine, r.start + i) or 0)
    end
    return table.concat(buf)
end

local function snapshot_all(machine)
    local snap = { regions = {}, hits = {}, rom = machine.system.name, t = now() }
    for _, r in ipairs(RANGES) do
        local data = read_region(machine, r)
        snap.regions[#snap.regions + 1] = {
            name = r.name,
            start = r.start,
            size = r.size,
            data = data,
        }
    end
    return snap
end

local function region(snap, name)
    for _, r in ipairs(snap.regions or {}) do
        if r.name == name then
            return r
        end
    end
    return nil
end

local function tile_name_lhzb(v)
    -- IGS lhzb2：低半字节 0..8 = 点数1..9；高半字节 0=万 1=筒 2=条 3=字(东南西北白发中)
    if not v then
        return "?"
    end
    local hi = math.floor(v / 16)
    local lo = v % 16
    if hi == 0 and lo <= 8 then
        return string.format("%d万", lo + 1)
    end
    if hi == 1 and lo <= 8 then
        return string.format("%d筒", lo + 1)
    end
    if hi == 2 and lo <= 8 then
        return string.format("%d条", lo + 1)
    end
    if hi == 3 and lo <= 6 then
        local n = { "东", "南", "西", "北", "白", "发", "中" }
        return n[lo + 1]
    end
    return string.format("[%02X]", v)
end

local function tiles_preview_lhzb(bytes, maxn)
    maxn = maxn or 14
    local names = {}
    for i = 1, math.min(#bytes, maxn) do
        names[#names + 1] = tile_name_lhzb(bytes[i])
    end
    return table.concat(names, " ")
end

local function tile_name_bcd(v)
    return tile_name_lhzb(v)
end

local function tiles_preview(bytes, enc, maxn)
    -- enc 保留兼容旧扫描；显示统一走 lhzb 编码
    return tiles_preview_lhzb(bytes, maxn)
end

local function tile_valid_lhzb(v)
    if not v or v == 0xFF then
        return false
    end
    local hi = math.floor(v / 16)
    local lo = v % 16
    if hi <= 2 then
        return lo <= 8
    end
    if hi == 3 then
        return lo <= 6
    end
    return false
end

-- 电脑河 @500185 起追加（可夹 FF）；返回 {addr,v}[]
local function read_cpu_river(machine)
    local out = {}
    local gap = 0
    for i = 0, CPU_RIVER_SPAN - 1 do
        local a = CPU_RIVER_ADDR + i
        local v = mem.read_u8(machine, a)
        if tile_valid_lhzb(v) then
            gap = 0
            out[#out + 1] = { addr = a, v = v }
        else
            gap = gap + 1
            if #out > 0 and gap >= 4 then
                break
            end
        end
    end
    return out
end

local function cpu_river_last(machine)
    local riv = read_cpu_river(machine)
    if #riv == 0 then
        return nil, 0, nil
    end
    local last = riv[#riv]
    return last.v, #riv, last.addr
end

local function format_cpu_river(machine, maxn)
    maxn = maxn or 16
    local riv = read_cpu_river(machine)
    if #riv == 0 then
        return "-"
    end
    local names = {}
    local from = math.max(1, #riv - maxn + 1)
    for i = from, #riv do
        names[#names + 1] = tile_name_lhzb(riv[i].v)
    end
    return string.format("河%d:%s", #riv, table.concat(names, " "))
end

-- lhzb 编码 低位 0..8 → ui_tiles BCD 低位 1..9（字 0..6 → 0x31..0x37）
local function lhzb_to_bcd(v)
    if not v then
        return 0
    end
    local hi = math.floor(v / 16)
    local lo = v % 16
    if hi <= 2 and lo <= 8 then
        return hi * 16 + (lo + 1)
    end
    if hi == 3 and lo <= 6 then
        return 0x30 + (lo + 1)
    end
    return 0
end

local function lhzb_pool_index(v)
    if not tile_valid_lhzb(v) then
        return nil
    end
    local hi = math.floor(v / 16)
    local lo = v % 16
    if hi <= 2 then
        return hi * 9 + lo -- 0..26
    end
    return 27 + lo -- 27..33
end

local function pool_count(machine, tile_v)
    local idx = lhzb_pool_index(tile_v)
    if idx == nil then
        return nil
    end
    return mem.read_u8(machine, WALL_POOL_ADDR + idx)
end

local function pool_count_in_snap(snap, tile_v)
    local idx = lhzb_pool_index(tile_v)
    if idx == nil then
        return nil
    end
    for _, r in ipairs(snap.regions or {}) do
        if r.name == "68k_nvram" then
            local off = (WALL_POOL_ADDR - r.start) + 1 -- 1-based string
            return r.data:byte(off + idx)
        end
    end
    return nil
end

local function pool_index_to_lhzb(idx)
    if not idx or idx < 0 or idx > 33 then
        return nil
    end
    if idx <= 26 then
        local suit = math.floor(idx / 9)
        local lo = idx % 9
        return suit * 16 + lo
    end
    return 0x30 + (idx - 27)
end

local function bcd_to_lhzb(bcd)
    if not bcd then
        return nil
    end
    local hi = math.floor(bcd / 16)
    local lo = bcd % 16
    if hi <= 2 and lo >= 1 and lo <= 9 then
        return hi * 16 + (lo - 1)
    end
    if hi == 3 and lo >= 1 and lo <= 7 then
        return 0x30 + (lo - 1)
    end
    return nil
end

function force_draw.target_lhzb()
    return FORCE_TILES[force_draw.tile_i] or 0x04
end

function force_draw.backup_pool(machine)
    local pool = {}
    for i = 0, WALL_POOL_LEN - 1 do
        pool[i + 1] = mem.read_u8(machine, WALL_POOL_ADDR + i) or 0
    end
    return {
        pool = pool,
        remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0,
    }
end

function force_draw.restore_pool(machine, bak)
    if not bak or not bak.pool then
        return
    end
    for i = 0, WALL_POOL_LEN - 1 do
        mem.write_u8(machine, WALL_POOL_ADDR + i, bak.pool[i + 1] or 0)
    end
    if bak.remain ~= nil then
        mem.write_u8(machine, WALL_REMAIN_ADDR, bak.remain & 0xFF)
    end
end

function force_draw.fill_pool(machine, lhzb)
    local idx = lhzb_pool_index(lhzb)
    if idx == nil then
        return false
    end
    local bak = force_draw.sticky_backup or force_draw.backup
    local total = bak and bak.remain or (mem.read_u8(machine, WALL_REMAIN_ADDR) or 0)
    if total < 1 then
        local s = 0
        if bak and bak.pool then
            for i = 1, WALL_POOL_LEN do
                s = s + (bak.pool[i] or 0)
            end
        end
        total = s > 0 and s or 1
    end
    for i = 0, WALL_POOL_LEN - 1 do
        mem.write_u8(machine, WALL_POOL_ADDR + i, 0)
    end
    mem.write_u8(machine, WALL_POOL_ADDR + idx, math.min(total, 255))
    mem.write_u8(machine, WALL_REMAIN_ADDR, total & 0xFF)
    return true
end

function force_draw.clear_armed()
    force_draw.armed = false
    force_draw.backup = nil
    force_draw.prev_remain = nil
    force_draw.prev_target_cnt = nil
    force_draw.tick = 0
end

function force_draw.arm(machine)
    local lhzb = force_draw.target_lhzb()
    local idx = lhzb_pool_index(lhzb)
    if idx == nil then
        machine:popmessage("控摸失败：非法目标")
        return
    end
    if not force_draw.sticky_backup then
        force_draw.sticky_backup = force_draw.backup_pool(machine)
    end
    force_draw.backup = force_draw.sticky_backup
    force_draw.armed = true
    force_draw.tick = 0
    force_draw.fill_pool(machine, lhzb)
    force_draw.prev_remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
    force_draw.prev_target_cnt = mem.read_u8(machine, WALL_POOL_ADDR + idx) or 0
    write_log(
        string.format(
            "=== [force-draw] ARM %s (lhzb=%02X idx=%d remain=%d) %s ===\n",
            tile_name_lhzb(lhzb),
            lhzb,
            idx,
            force_draw.prev_remain,
            now()
        ),
        "a"
    )
    machine:popmessage(string.format("控摸开 → 下一摸 %s\n摸后 remain↓ 自动关", tile_name_lhzb(lhzb)))
end

function force_draw.disarm(machine, reason)
    reason = reason or "manual"
    local bak = force_draw.sticky_backup or force_draw.backup
    local was = force_draw.armed
    if bak then
        force_draw.restore_pool(machine, bak)
    end
    force_draw.clear_armed()
    -- 单次控摸：恢复后清 sticky，避免下局仍用旧备份
    if reason ~= "manual_keep_sticky" then
        force_draw.sticky_backup = nil
    end
    write_log(string.format("=== [force-draw] DISARM (%s) %s ===\n", reason, now()), "a")
    if was or bak then
        machine:popmessage(
            bak and string.format("控摸关 · %s · 牌池已恢复", reason) or "控摸关 · 无备份"
        )
    end
    return true
end

function force_draw.toggle(machine)
    if force_draw.armed then
        force_draw.disarm(machine, "toggle")
    else
        force_draw.arm(machine)
    end
end

function force_draw.cycle(machine)
    force_draw.tile_i = (force_draw.tile_i % #FORCE_TILES) + 1
    local lhzb = force_draw.target_lhzb()
    if force_draw.armed then
        force_draw.fill_pool(machine, lhzb)
        local idx = lhzb_pool_index(lhzb)
        force_draw.prev_remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
        force_draw.prev_target_cnt = idx and (mem.read_u8(machine, WALL_POOL_ADDR + idx) or 0) or 0
    end
    machine:popmessage(
        string.format(
            "控摸目标：%s%s",
            tile_name_lhzb(lhzb),
            force_draw.armed and "（已填充）" or "（右Ctrl+8 开）"
        )
    )
end

function force_draw.select(machine, bcd)
    local lhzb = bcd_to_lhzb(bcd)
    if not lhzb then
        return
    end
    local idx = nil
    for i, v in ipairs(FORCE_TILES) do
        if v == lhzb then
            idx = i
            break
        end
    end
    if not idx then
        return
    end
    if force_draw.armed and force_draw.tile_i == idx then
        force_draw.disarm(machine, "click_same")
        return
    end
    force_draw.tile_i = idx
    force_draw.arm(machine)
end

function force_draw.run_tick(machine)
    if not force_draw.armed then
        return
    end
    force_draw.tick = (force_draw.tick or 0) + 1
    local lhzb = force_draw.target_lhzb()
    local idx = lhzb_pool_index(lhzb)
    local remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
    local cnt = idx and (mem.read_u8(machine, WALL_POOL_ADDR + idx) or 0) or 0
    local prev_r = force_draw.prev_remain
    local prev_c = force_draw.prev_target_cnt
    if prev_r ~= nil and remain < prev_r then
        force_draw.disarm(machine, "remain_drop")
        return
    end
    if prev_c ~= nil and cnt < prev_c then
        force_draw.disarm(machine, "pool_taken")
        return
    end
    -- 若游戏把非目标种写回，只清其它格，不抬 remain（避免盖住摸牌 −1）
    if idx and (force_draw.tick % 8) == 0 then
        for i = 0, WALL_POOL_LEN - 1 do
            if i ~= idx then
                local v = mem.read_u8(machine, WALL_POOL_ADDR + i) or 0
                if v ~= 0 then
                    mem.write_u8(machine, WALL_POOL_ADDR + i, 0)
                end
            end
        end
        if cnt < 1 then
            mem.write_u8(machine, WALL_POOL_ADDR + idx, 1)
            cnt = 1
        end
    end
    force_draw.prev_remain = remain
    force_draw.prev_target_cnt = cnt
end

local function read_pool_tiles(machine)
    local bak = force_draw.armed and (force_draw.sticky_backup or force_draw.backup) or nil
    local force_lhzb = force_draw.armed and force_draw.target_lhzb() or nil
    local list = {}
    local n = 0
    for i = 0, WALL_POOL_LEN - 1 do
        local cnt
        if bak and bak.pool then
            cnt = bak.pool[i + 1] or 0
        else
            cnt = mem.read_u8(machine, WALL_POOL_ADDR + i) or 0
        end
        local lhzb = pool_index_to_lhzb(i)
        local bcd = lhzb_to_bcd(lhzb)
        n = n + cnt
        list[#list + 1] = {
            raw = bcd,
            enc = "bcd",
            name = tile_name_lhzb(lhzb),
            count = cnt,
            dim = cnt == 0,
            force_hi = force_lhzb ~= nil and lhzb == force_lhzb,
            empty = false,
        }
    end
    return list, n
end

local function read_hand_lhzb(machine, addr, maxn)
    maxn = maxn or 14
    local bytes = {}
    for i = 0, maxn - 1 do
        local v = mem.read_u8(machine, addr + i)
        if not tile_valid_lhzb(v) then
            break
        end
        bytes[#bytes + 1] = v
    end
    return bytes
end

local function hand_len_ok(n)
    return n == 13 or n == 14 or n == 10 or n == 11 or n == 7 or n == 8 or n == 4 or n == 5
end

-- 副露后常见：长度头 + 若干 FF 空洞 + 暗手（本局见 0x0C FF FF FF + 10 张）
-- 勿把暗手后的副露零散字节（如 FF 2筒 FF 4筒）读进暗手
local function read_hand_lhzb_skip_ff(machine, addr, maxn, span)
    maxn = maxn or 14
    span = span or 24
    local bytes = {}
    local gap = 0
    for i = 0, span - 1 do
        if #bytes >= maxn then
            break
        end
        local v = mem.read_u8(machine, addr + i)
        if v == nil then
            break
        end
        if v == 0xFF then
            gap = gap + 1
            if #bytes >= 4 and hand_len_ok(#bytes) and gap >= 1 then
                break
            end
        elseif tile_valid_lhzb(v) then
            if gap >= 1 and #bytes >= 4 and hand_len_ok(#bytes) then
                break
            end
            gap = 0
            bytes[#bytes + 1] = v
        else
            if #bytes > 0 then
                break
            end
            gap = 0
        end
    end
    if #bytes > 0 and not hand_len_ok(#bytes) then
        for _, n in ipairs({ 14, 13, 11, 10, 8, 7, 5, 4 }) do
            if #bytes >= n then
                local t = {}
                for i = 1, n do
                    t[i] = bytes[i]
                end
                return t
            end
        end
    end
    return bytes
end

local function looks_like_len_hdr(v)
    -- 仅「非牌」字节可当长度头（0x0A/0x0C 等）。
    -- 切勿把 5~9万(04..08) 当头，否则满手会被截成 4~8 张。
    if not v or tile_valid_lhzb(v) then
        return false
    end
    return v >= 4 and v <= 14
end

-- 优先直读牌序列；仅非牌长度头时跳过头（可跳 FF；可试 addr-1）
local function read_hand_at(machine, addr, maxn)
    maxn = maxn or 14
    if not addr then
        return {}, addr
    end

    local function try_hdr(hdr_addr)
        local first = mem.read_u8(machine, hdr_addr)
        if first == nil or not looks_like_len_hdr(first) then
            return nil, nil
        end
        local body = read_hand_lhzb_skip_ff(machine, hdr_addr + 1, math.max(first, 14), 28)
        if #body >= 4 and hand_len_ok(#body) then
            return body, hdr_addr + 1
        end
        return nil, nil
    end

    -- 先按牌直读（避免 7万=06 被当成长度 6）
    local plain = read_hand_lhzb_skip_ff(machine, addr, maxn, 28)
    if #plain >= 4 and hand_len_ok(#plain) then
        return plain, addr
    end

    local body, used = try_hdr(addr)
    if body then
        return body, used
    end
    body, used = try_hdr(addr - 1)
    if body then
        return body, used
    end

    if #plain >= 4 then
        return plain, addr
    end
    plain = read_hand_lhzb(machine, addr, maxn)
    if #plain >= 4 then
        return plain, addr
    end
    return plain, addr
end

local function hand_bag_counts(bytes)
    local c = {}
    for _, v in ipairs(bytes or {}) do
        c[v] = (c[v] or 0) + 1
    end
    return c
end

local function hand_bag_key(bytes)
    local c = hand_bag_counts(bytes)
    local parts = {}
    for v = 0, 0x36 do
        if c[v] then
            parts[#parts + 1] = string.format("%02X:%d", v, c[v])
        end
    end
    return table.concat(parts, ",")
end

local function maybe_strip_discard(bytes, disc)
    if not bytes or not disc or not tile_valid_lhzb(disc) then
        return bytes
    end
    local n = #bytes
    if n ~= 14 and n ~= 11 and n ~= 8 then
        return bytes
    end
    local out = {}
    local removed = false
    for _, v in ipairs(bytes) do
        if (not removed) and v == disc then
            removed = true
        else
            out[#out + 1] = v
        end
    end
    if removed and hand_len_ok(#out) then
        return out
    end
    return bytes
end

local function clear_cpu_hand_hold(why)
    cpu_hand_hold.bytes = {}
    cpu_hand_hold.addr = CPU_HAND_ADDR
    cpu_hand_hold.disc = nil
    cpu_hand_hold.empty_streak = 0
    cpu_hand_hold._clear_why = why
    hand_live_cache.frame = -1
end

-- 期望暗手张数：13-3n；待打 +1
local function expected_closed_n(meld_n, awaiting)
    meld_n = meld_n or 0
    local n = 13 - 3 * meld_n
    if awaiting then
        n = n + 1
    end
    if n < 1 then
        n = 1
    end
    return n
end

local function infer_meld_n(closed_n)
    if not closed_n or closed_n >= 13 then
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

-- 真实手牌多样；全是 00/1万 这类 nvram 噪声不当明锚
local function hand_uniq_n(bytes)
    if not bytes or #bytes == 0 then
        return 0
    end
    local u = {}
    local n = 0
    for _, v in ipairs(bytes) do
        if not u[v] then
            u[v] = true
            n = n + 1
        end
    end
    return n
end

local function hand_plausible(bytes)
    local n = bytes and #bytes or 0
    if n < 4 or not hand_len_ok(n) then
        return false
    end
    local uniq = hand_uniq_n(bytes)
    if n >= 13 then
        return uniq >= 6
    end
    if n >= 10 then
        return uniq >= 5
    end
    return uniq >= 3
end

local function read_cpu_hand_live(machine)
    local frame_n = -1
    pcall(function()
        local scr = machine.screens and machine.screens[":screen"]
        if scr and scr.frame_number then
            frame_n = scr:frame_number()
        end
    end)
    if frame_n >= 0 and frame_n == hand_live_cache.frame and hand_live_cache.bytes then
        return hand_live_cache.bytes, hand_live_cache.addr, hand_live_cache.held
    end

    local remain = mem.read_u8(machine, WALL_REMAIN_ADDR)
    local disc_v = select(1, cpu_river_last(machine))
    if remain and cpu_hand_hold.remain and remain > (cpu_hand_hold.remain + 15) then
        clear_cpu_hand_hold("remain_jump")
    end
    if remain then
        cpu_hand_hold.remain = remain
    end

    local player = read_hand_lhzb(machine, PLAYER_HAND_ADDR, 14)
    local pl_key = hand_bag_key(player)

    local function try_addr(addr)
        if not addr then
            return nil, addr, -1
        end
        local bytes, used = read_hand_at(machine, addr, 14)
        bytes = maybe_strip_discard(bytes, disc_v)
        local key = hand_bag_key(bytes)
        if #bytes < 4 or not hand_len_ok(#bytes) or not hand_plausible(bytes) then
            -- 明锚读到噪声则 unpin，避免下帧继续抢分
            if addr == OPEN_HAND_ADDR then
                OPEN_HAND_ADDR = nil
                open_hand_watch.pinned = nil
            end
            return nil, used, -1
        end
        if key == "" or key == pl_key then
            if addr == OPEN_HAND_ADDR then
                OPEN_HAND_ADDR = nil
                open_hand_watch.pinned = nil
            end
            return nil, used, -1
        end
        -- 远「明锚」易串玩家镜像，只信近主槽
        if addr == OPEN_HAND_ADDR and math.abs((used or addr) - CPU_HAND_ADDR) > 0x80 then
            OPEN_HAND_ADDR = nil
            open_hand_watch.pinned = nil
            return nil, used, -1
        end
        local score = #bytes
        if addr == OPEN_HAND_ADDR then
            score = score + 1000
        end
        if addr == CPU_HAND_ADDR or used == CPU_HAND_ADDR or used == CPU_HAND_ADDR + 1 then
            score = score + 100
        end
        return bytes, used, score
    end

    local best, best_addr, best_score = {}, CPU_HAND_ADDR, -1
    -- 优先明牌钉死地址，再主槽（勿把 nil 放进 ipairs 表，否则会提前停）
    local addrs = {}
    if OPEN_HAND_ADDR then
        addrs[#addrs + 1] = OPEN_HAND_ADDR
    end
    addrs[#addrs + 1] = CPU_HAND_ADDR
    for _, addr in ipairs(addrs) do
        local bytes, used, sc = try_addr(addr)
        if sc and sc > best_score then
            best_score = sc
            best = bytes
            best_addr = used
        end
    end

    local held = false
    if best_score >= 0 and #best >= 4 then
        cpu_hand_hold.bytes = best
        cpu_hand_hold.addr = best_addr
        cpu_hand_hold.disc = disc_v
        cpu_hand_hold.empty_streak = 0
    else
        -- 开局/发牌不稳：不要用旧满手 hold 顶；仅副露后短暂空读用短 hold
        local hold = cpu_hand_hold.bytes or {}
        local hold_n = #hold
        cpu_hand_hold.empty_streak = (cpu_hand_hold.empty_streak or 0) + 1
        if hold_n >= 4 and hold_n <= 11 and (cpu_hand_hold.empty_streak or 0) <= 45 then
            best = maybe_strip_discard(hold, disc_v)
            best_addr = cpu_hand_hold.addr or CPU_HAND_ADDR
            held = true
        else
            if hold_n >= 13 then
                clear_cpu_hand_hold("reject_full_hold")
            end
            best = {}
            best_addr = OPEN_HAND_ADDR or CPU_HAND_ADDR
            held = false
        end
    end

    if frame_n >= 0 then
        hand_live_cache.frame = frame_n
        hand_live_cache.bytes = best
        hand_live_cache.addr = best_addr
        hand_live_cache.held = held
    end
    return best, best_addr, held
end

local function format_live_hands(machine)
    local cpu, cpu_addr, held = read_cpu_hand_live(machine)
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW)
    local disc_v, riv_n = cpu_river_last(machine)
    local remain = mem.read_u8(machine, WALL_REMAIN_ADDR)
    local draw_pool = tile_valid_lhzb(draw_v) and pool_count(machine, draw_v) or nil
    local meld_n = infer_meld_n(#cpu)
    return string.format(
        "电脑@%04X(%d%s%s): %s\n摸=%s 弃=%s(河%d) 剩=%d 池[%s]=%s 副露≈%d",
        cpu_addr or CPU_HAND_ADDR,
        #cpu,
        held and "·hold" or "",
        OPEN_HAND_ADDR and "·open" or "",
        #cpu > 0 and tiles_preview_lhzb(cpu) or "(发牌中/-)",
        tile_valid_lhzb(draw_v) and tile_name_lhzb(draw_v) or string.format("%02X", draw_v or 0),
        tile_valid_lhzb(disc_v) and tile_name_lhzb(disc_v) or string.format("%02X", disc_v or 0),
        riv_n or 0,
        remain or 0,
        tile_valid_lhzb(draw_v) and tile_name_lhzb(draw_v) or "?",
        draw_pool ~= nil and tostring(draw_pool) or "?",
        meld_n
    )
end

-- --- 明牌 / 副露 hunt -------------------------------------------------

local function scan_tile_runs_in_region(data, base, min_len, max_len)
    min_len = min_len or 13
    max_len = max_len or 14
    local hits = {}
    local i = 1
    local n = #data
    while i <= n do
        local b = data:byte(i)
        if tile_valid_lhzb(b) then
            local run = { b }
            local j = i + 1
            while j <= n and #run < max_len and tile_valid_lhzb(data:byte(j)) do
                run[#run + 1] = data:byte(j)
                j = j + 1
            end
            if #run >= min_len and hand_plausible(run) then
                hits[#hits + 1] = {
                    addr = base + i - 1,
                    len = #run,
                    bytes = run,
                    key = hand_bag_key(run),
                    uniq = hand_uniq_n(run),
                    preview = tiles_preview_lhzb(run, 14),
                }
            end
            i = j
        else
            i = i + 1
        end
    end
    return hits
end

local function dump_open_hand_hunt(machine, why, snap)
    snap = snap or snapshot_all(machine)
    local primary, paddr = read_hand_at(machine, CPU_HAND_ADDR, 14)
    local pkey = hand_bag_key(primary)
    local lines = {
        string.format("=== [open-hand-hunt] %s %s ===", why or "?", now()),
        string.format(
            "  primary@%04X len=%d key=%s  %s",
            paddr or CPU_HAND_ADDR,
            #primary,
            pkey ~= "" and pkey or "-",
            #primary > 0 and tiles_preview_lhzb(primary) or "-"
        ),
    }
    if OPEN_HAND_ADDR then
        local ob, oa = read_hand_at(machine, OPEN_HAND_ADDR, 14)
        local ok = hand_plausible(ob)
        local same = (hand_bag_key(ob) == pkey and pkey ~= "")
        lines[#lines + 1] = string.format(
            "  pinned-open@%04X len=%d uniq=%d%s%s  %s",
            oa or OPEN_HAND_ADDR,
            #ob,
            hand_uniq_n(ob),
            ok and " ok" or " BAD",
            same and " =prim" or "",
            #ob > 0 and tiles_preview_lhzb(ob) or "-"
        )
        -- 假阳性（如 @50000A 全是 1万）：立刻 unpin，避免 HUD 跟噪声
        if not ok or (pkey ~= "" and not same and #ob >= 13) then
            lines[#lines + 1] = string.format(
                "  >> unpin OPEN_HAND_ADDR=@%06X (not plausible / != primary bag)",
                OPEN_HAND_ADDR
            )
            OPEN_HAND_ADDR = nil
            open_hand_watch.pinned = nil
        end
    end
    local cands = {}
    for _, r in ipairs(snap.regions or {}) do
        if r.name == "68k_nvram" then
            for _, h in ipairs(scan_tile_runs_in_region(r.data, r.start, 13, 14)) do
                local same = (h.key == pkey and pkey ~= "")
                local near = math.abs(h.addr - CPU_HAND_ADDR) < 0x200
                h.same_primary = same
                h.near_primary = near
                cands[#cands + 1] = h
            end
        end
    end
    table.sort(cands, function(a, b)
        local sa = (a.same_primary and 0 or 1) + (a.near_primary and 0 or 2)
        local sb = (b.same_primary and 0 or 1) + (b.near_primary and 0 or 2)
        if sa ~= sb then
            return sa < sb
        end
        if (a.uniq or 0) ~= (b.uniq or 0) then
            return (a.uniq or 0) > (b.uniq or 0)
        end
        return a.addr < b.addr
    end)
    open_hand_watch.last_cands = cands
    lines[#lines + 1] = string.format("  hand-runs %d plausible (show ≤12):", #cands)
    for i = 1, math.min(#cands, 12) do
        local h = cands[i]
        lines[#lines + 1] = string.format(
            "  #%d @%06X len=%d uniq=%d%s%s  %s",
            i,
            h.addr,
            h.len,
            h.uniq or 0,
            h.same_primary and " =prim" or "",
            h.near_primary and " near" or "",
            h.preview
        )
    end
    -- 与 primary 同 bag 且地址不同 → 疑似明牌拷贝；自动钉最近的一份供暗下验证
    if not OPEN_HAND_ADDR and pkey ~= "" then
        for _, h in ipairs(cands) do
            -- 仅钉主槽附近的同 bag（远镜像如 @5008B6 会串成玩家手）
            if h.same_primary
                and h.addr ~= CPU_HAND_ADDR
                and h.addr ~= CPU_HAND_ADDR + 1
                and math.abs(h.addr - CPU_HAND_ADDR) < 0x80
            then
                OPEN_HAND_ADDR = h.addr
                open_hand_watch.pinned = h.addr
                lines[#lines + 1] = string.format(
                    "  >> auto-pin OPEN_HAND_ADDR=@%06X (same bag near primary)",
                    h.addr
                )
                break
            end
        end
    end
    if not OPEN_HAND_ADDR and pkey ~= "" then
        lines[#lines + 1] =
            "  (no separate same-bag copy → 明牌多半共用 @50013E，暗手下继续直读主槽)"
    end
    write_log(table.concat(lines, "\n") .. "\n", "a")
    return cands
end

local function dump_open_hand_diff(snap_old, snap_new, why)
    if not snap_old or not snap_new then
        return
    end
    local lines = { string.format("=== [open-hand-diff] %s %s ===", why or "?", now()) }
    local appeared = {}
    for _, rn in ipairs(snap_new.regions or {}) do
        if rn.name == "68k_nvram" then
            local ro = nil
            for _, x in ipairs(snap_old.regions or {}) do
                if x.name == rn.name then
                    ro = x
                    break
                end
            end
            if not ro then
                break
            end
            local news = scan_tile_runs_in_region(rn.data, rn.start, 13, 14)
            local olds = scan_tile_runs_in_region(ro.data, ro.start, 13, 14)
            local old_keys = {}
            for _, h in ipairs(olds) do
                old_keys[h.addr] = h.key
            end
            for _, h in ipairs(news) do
                if old_keys[h.addr] ~= h.key then
                    appeared[#appeared + 1] = h
                end
            end
        end
    end
    -- 从 snap 里抽主槽 bag（不依赖 manager.machine）
    local primary = {}
    local pkey = ""
    for _, rn in ipairs(snap_new.regions or {}) do
        if rn.name == "68k_nvram" and rn.start <= CPU_HAND_ADDR then
            local off = CPU_HAND_ADDR - rn.start + 1
            if off >= 1 and off + 13 <= #rn.data then
                -- 与 read_hand_at 一致：可能有长度头
                local head = rn.data:byte(off)
                local start = off
                if head == 0x0A or head == 0x07 or head == 0x04 or head == 0x0D then
                    -- 长度头候选：若下一字节像牌则跳过头
                    local nxt = rn.data:byte(off + 1)
                    if tile_valid_lhzb(nxt) then
                        start = off + 1
                    end
                end
                for k = 0, 13 do
                    local v = rn.data:byte(start + k)
                    if not tile_valid_lhzb(v) then
                        break
                    end
                    primary[#primary + 1] = v
                    if #primary >= 14 then
                        break
                    end
                end
                -- 截到合法长度
                while #primary > 0 and not hand_len_ok(#primary) do
                    primary[#primary] = nil
                end
                pkey = hand_bag_key(primary)
            end
            break
        end
    end
    lines[#lines + 1] = string.format(
        "  changed/new 13–14 plausible runs: %d  primary_key=%s",
        #appeared,
        pkey ~= "" and pkey or "-"
    )
    local pinned = false
    for i = 1, math.min(#appeared, 15) do
        local h = appeared[i]
        local same = (pkey ~= "" and h.key == pkey)
        lines[#lines + 1] = string.format(
            "  @%06X len=%d uniq=%d%s  %s",
            h.addr,
            h.len,
            h.uniq or hand_uniq_n(h.bytes),
            same and " =prim" or "",
            h.preview
        )
        -- 仅：与主槽同 bag、非主槽本身 → 才钉（暗→明拷贝）
        if (not OPEN_HAND_ADDR) and (not pinned) and same and h.addr ~= CPU_HAND_ADDR and h.addr ~= CPU_HAND_ADDR + 1 then
            OPEN_HAND_ADDR = h.addr
            open_hand_watch.pinned = h.addr
            pinned = true
            lines[#lines + 1] = string.format(
                "  >> auto-pin OPEN_HAND_ADDR=@%06X (diff same bag)",
                h.addr
            )
        end
    end
    if not pinned and not OPEN_HAND_ADDR then
        lines[#lines + 1] = "  (diff 无同 bag 新 run → 不钉；继续用 @50013E)"
    end
    write_log(table.concat(lines, "\n") .. "\n", "a")
end

-- 副露：扫「非牌字节 + 三张合法牌」；IGS 标记未知，先广搜
local function scan_meld_like(data, base)
    local hits = {}
    local i = 1
    local n = #data
    while i <= n - 3 do
        local mark = data:byte(i)
        local t1, t2, t3 = data:byte(i + 1), data:byte(i + 2), data:byte(i + 3)
        if (not tile_valid_lhzb(mark))
            and tile_valid_lhzb(t1)
            and tile_valid_lhzb(t2)
            and tile_valid_lhzb(t3)
            and mark ~= 0xFF
            and mark ~= 0x00
        then
            -- 碰：三张同；吃：同花色连续（宽松）
            local pon = t1 == t2 and t2 == t3
            local chi = false
            if (not pon) and math.floor(t1 / 16) == math.floor(t2 / 16) and math.floor(t2 / 16) == math.floor(t3 / 16) then
                local a, b, c = t1 % 16, t2 % 16, t3 % 16
                local s = { a, b, c }
                table.sort(s)
                chi = (s[2] == s[1] + 1 and s[3] == s[2] + 1)
            end
            if pon or chi or (mark >= 0x40 and mark <= 0x90) then
                -- 00=1万：C7 00 00 00 一类全是垫字节，绝不当碰
                if t1 == 0 and t2 == 0 and t3 == 0 then
                    -- skip
                else
                    hits[#hits + 1] = {
                        addr = base + i - 1,
                        mark = mark,
                        kind = pon and "pon" or (chi and "chi" or "mk"),
                        tiles = { t1, t2, t3 },
                        preview = string.format(
                            "%s %s %s",
                            tile_name_lhzb(t1),
                            tile_name_lhzb(t2),
                            tile_name_lhzb(t3)
                        ),
                    }
                end
            end
        end
        i = i + 1
    end
    return hits
end

-- 副露标记表：连续非 FF/非 00 字节，每口 1 标记（实测 47=碰8万 54=碰5筒 42=碰3万）
local function read_meld_marks_at(machine, base, max_n)
    max_n = max_n or 4
    local marks = {}
    if not base then
        return marks
    end
    for i = 0, max_n - 1 do
        local m = mem.read_u8(machine, base + i)
        if not m or m == 0xFF or m == 0 then
            break
        end
        -- 排除误读进暗手牌码（正常标记多在 0x40+）
        if tile_valid_lhzb(m) and m < 0x40 then
            break
        end
        marks[#marks + 1] = { addr = base + i, mark = m }
    end
    return marks
end

-- 兼容旧 hunt：若仍是 mark+3 布局则读块；否则退回标记表
local function read_meld_blocks_at(machine, base, max_blocks)
    max_blocks = max_blocks or 4
    local blocks = {}
    if not base then
        return blocks
    end
    if base == MELD_CPU_ADDR then
        for _, m in ipairs(read_meld_marks_at(machine, base, max_blocks)) do
            blocks[#blocks + 1] = {
                addr = m.addr,
                mark = m.mark,
                tiles = {},
                kind = "mark",
            }
        end
        return blocks
    end
    for i = 0, max_blocks - 1 do
        local off = i * 4
        local mark = mem.read_u8(machine, base + off)
        local t1 = mem.read_u8(machine, base + off + 1)
        local t2 = mem.read_u8(machine, base + off + 2)
        local t3 = mem.read_u8(machine, base + off + 3)
        if not mark or tile_valid_lhzb(mark) or mark == 0xFF or mark == 0 then
            break
        end
        if not (tile_valid_lhzb(t1) and tile_valid_lhzb(t2) and tile_valid_lhzb(t3)) then
            break
        end
        blocks[#blocks + 1] = {
            addr = base + off,
            mark = mark,
            tiles = { t1, t2, t3 },
        }
    end
    return blocks
end

local function format_meld_blocks(blocks)
    if not blocks or #blocks == 0 then
        return "-"
    end
    local parts = {}
    for _, b in ipairs(blocks) do
        if b.tiles and #b.tiles >= 3 then
            parts[#parts + 1] = string.format(
                "@%04X/%02X[%s %s %s]",
                b.addr,
                b.mark,
                tile_name_lhzb(b.tiles[1]),
                tile_name_lhzb(b.tiles[2]),
                tile_name_lhzb(b.tiles[3])
            )
        else
            parts[#parts + 1] = string.format("@%04X/%02X", b.addr, b.mark)
        end
    end
    return table.concat(parts, " ")
end

local function dump_meld_hunt(machine, why, snap)
    snap = snap or snapshot_all(machine)
    local cpu, _, _ = read_cpu_hand_live(machine)
    local closed_n = #cpu
    local infer = infer_meld_n(closed_n)
    local disc = mem.read_u8(machine, HYP_LAST_DISC)
    local lines = {
        string.format(
            "=== [meld-hunt] %s closed=%d infer_meld≈%d expect=%d/%d disc=%s %s ===",
            why or "?",
            closed_n,
            infer,
            expected_closed_n(infer, false),
            expected_closed_n(infer, true),
            tile_valid_lhzb(disc) and tile_name_lhzb(disc) or string.format("%02X", disc or 0),
            now()
        ),
    }
    if MELD_CPU_ADDR then
        local blocks = read_meld_blocks_at(machine, MELD_CPU_ADDR, 4)
        meld_watch.blocks = blocks
        lines[#lines + 1] = string.format(
            "  pinned@%04X n=%d %s",
            MELD_CPU_ADDR,
            #blocks,
            format_meld_blocks(blocks)
        )
    end
    local hits = {}
    for _, r in ipairs(snap.regions or {}) do
        if r.name == "68k_nvram" then
            for _, h in ipairs(scan_meld_like(r.data, r.start)) do
                local d = math.min(math.abs(h.addr - CPU_HAND_ADDR), math.abs(h.addr - PLAYER_HAND_ADDR))
                h.dist = d
                hits[#hits + 1] = h
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.dist ~= b.dist then
            return a.dist < b.dist
        end
        return a.addr < b.addr
    end)
    meld_watch.last_hits = hits
    lines[#lines + 1] = string.format("  meld-like hits %d (show ≤20):", #hits)
    for i = 1, math.min(#hits, 20) do
        local h = hits[i]
        lines[#lines + 1] = string.format(
            "  #%d @%06X %s mark=%02X  %s",
            i,
            h.addr,
            h.kind,
            h.mark,
            h.preview
        )
    end
    -- 仅步进/全扫时尝试钉；auto-closed 闪烁禁止钉（易钉 @500102 垃圾）
    local allow_pin = why and not tostring(why):find("auto-closed", 1, true)
    if allow_pin and not MELD_CPU_ADDR and infer >= 1 and #hits > 0 then
        for _, h in ipairs(hits) do
            if h.dist < 0x40 and h.kind ~= "mk" and not (h.tiles[1] == 0 and h.tiles[2] == 0 and h.tiles[3] == 0) then
                local blocks = read_meld_blocks_at(machine, h.addr, 4)
                if #blocks >= 1 then
                    MELD_CPU_ADDR = h.addr
                    meld_watch.cpu_addr = h.addr
                    lines[#lines + 1] = string.format(
                        "  >> auto-pin MELD_CPU_ADDR=@%06X blocks=%d",
                        h.addr,
                        #blocks
                    )
                    break
                end
            end
        end
    end
    -- 清掉已知假钉
    if MELD_CPU_ADDR == 0x500102 then
        lines[#lines + 1] = "  >> unpin MELD_CPU_ADDR=@500102 (junk 2万2万1万)"
        MELD_CPU_ADDR = nil
        meld_watch.cpu_addr = nil
        meld_watch.blocks = {}
    end
    write_log(table.concat(lines, "\n") .. "\n", "a")
    return hits
end

local function bag_counts(bytes)
    local c = {}
    for _, v in ipairs(bytes or {}) do
        c[v] = (c[v] or 0) + 1
    end
    return c
end

local function bag_lost_tiles(old_bytes, new_bytes)
    local o = bag_counts(old_bytes)
    local n = bag_counts(new_bytes)
    local lost = {}
    for v, cnt in pairs(o) do
        local d = cnt - (n[v] or 0)
        for _ = 1, d do
            lost[#lost + 1] = v
        end
    end
    table.sort(lost)
    return lost
end

local function hand_has_lhzb(bytes, lhzb)
    if not bytes or not lhzb then
        return false
    end
    for _, v in ipairs(bytes) do
        if v == lhzb then
            return true
        end
    end
    return false
end

local function is_awaiting_discard_n(closed_n, meld_n)
    if not closed_n or closed_n < 1 then
        return false
    end
    meld_n = meld_n or infer_meld_n(closed_n)
    return closed_n == expected_closed_n(meld_n, true)
end

-- 暗手物理槽（含 FF 空洞跳过），供弃牌劫持对调末张
local function read_hand_phys_slots(machine, addr, maxn)
    maxn = maxn or 14
    local body, used = read_hand_at(machine, addr, maxn)
    if not used or #body == 0 then
        return {}, used
    end
    local slots = {}
    local gap = 0
    for i = 0, 27 do
        if #slots >= #body then
            break
        end
        local a = used + i
        local v = mem.read_u8(machine, a)
        if v == nil then
            break
        end
        if v == 0xFF then
            gap = gap + 1
            if #slots >= 4 and hand_len_ok(#slots) and gap >= 1 then
                break
            end
        elseif tile_valid_lhzb(v) then
            if gap >= 1 and #slots >= 4 and hand_len_ok(#slots) then
                break
            end
            gap = 0
            slots[#slots + 1] = { addr = a, v = v }
        else
            if #slots > 0 then
                break
            end
            gap = 0
        end
    end
    return slots, used
end

local function dump_cpu_discard_hunt(machine, why, snap, snap_old)
    snap = snap or snapshot_all(machine)
    local cpu = select(1, read_cpu_hand_live(machine))
    local closed_n = #cpu
    local meld_n = 0
    if MELD_CPU_ADDR then
        meld_n = #read_meld_blocks_at(machine, MELD_CPU_ADDR, 4)
    end
    if meld_n == 0 then
        meld_n = infer_meld_n(closed_n)
    end
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW)
    local disc_v, riv_n, riv_addr = cpu_river_last(machine)
    local await = is_awaiting_discard_n(closed_n, meld_n)
    local lines = {
        string.format(
            "=== [cpu-discard-hunt] %s closed=%d meld≈%d await=%s draw=%s last=%s(河%d@%04X) %s ===",
            why or "?",
            closed_n,
            meld_n,
            await and "Y" or "N",
            tile_valid_lhzb(draw_v) and tile_name_lhzb(draw_v) or string.format("%02X", draw_v or 0),
            tile_valid_lhzb(disc_v) and tile_name_lhzb(disc_v) or "-",
            riv_n or 0,
            riv_addr or 0,
            now()
        ),
    }
    lines[#lines + 1] = string.format(
        "  hand@%04X  %s",
        CPU_HAND_ADDR,
        #cpu > 0 and tiles_preview_lhzb(cpu) or "-"
    )
    lines[#lines + 1] = "  " .. format_cpu_river(machine, 24)
    if await then
        lines[#lines + 1] = "  >> WINDOW: 待打窗（暗手=期望+1）"
    end
    local watch_parts = {}
    for _, a in ipairs(CPU_DISC_WATCH) do
        local v = mem.read_u8(machine, a)
        watch_parts[#watch_parts + 1] = string.format(
            "@%04X=%02X%s",
            a,
            v or 0,
            tile_valid_lhzb(v) and ("(" .. tile_name_lhzb(v) .. ")") or ""
        )
    end
    lines[#lines + 1] = "  watch " .. table.concat(watch_parts, " ")
    local prot_parts = {}
    for _, a in ipairs(PROT_TURN_WATCH) do
        local v = mem.read_u8(machine, a)
        prot_parts[#prot_parts + 1] = string.format("@%06X=%02X", a, v or 0)
    end
    lines[#lines + 1] = "  prot  " .. table.concat(prot_parts, " ")

    if snap_old then
        local old_cpu = {}
        for _, r in ipairs(snap_old.regions or {}) do
            if r.name == "68k_nvram" then
                local off = CPU_HAND_ADDR - r.start + 1
                if off >= 1 and off <= #r.data then
                    local function at(i)
                        if i < 1 or i > #r.data then
                            return nil
                        end
                        return r.data:byte(i)
                    end
                    local start = off
                    local head = at(off)
                    if looks_like_len_hdr(head) then
                        local nxt = at(off + 1)
                        if nxt == 0xFF or tile_valid_lhzb(nxt) then
                            start = off + 1
                        end
                    end
                    local gap = 0
                    for i = 0, 27 do
                        if #old_cpu >= 14 then
                            break
                        end
                        local v = at(start + i)
                        if v == nil then
                            break
                        end
                        if v == 0xFF then
                            gap = gap + 1
                            if #old_cpu >= 4 and hand_len_ok(#old_cpu) and gap >= 1 then
                                break
                            end
                        elseif tile_valid_lhzb(v) then
                            if gap >= 1 and #old_cpu >= 4 and hand_len_ok(#old_cpu) then
                                break
                            end
                            gap = 0
                            old_cpu[#old_cpu + 1] = v
                        else
                            if #old_cpu > 0 then
                                break
                            end
                            gap = 0
                        end
                    end
                    if #old_cpu > 0 and not hand_len_ok(#old_cpu) then
                        for _, n in ipairs({ 14, 13, 11, 10, 8, 7, 5, 4 }) do
                            if #old_cpu >= n then
                                while #old_cpu > n do
                                    old_cpu[#old_cpu] = nil
                                end
                                break
                            end
                        end
                    end
                end
                break
            end
        end
        local lost = bag_lost_tiles(old_cpu, cpu)
        if #lost > 0 then
            local names = {}
            for _, v in ipairs(lost) do
                names[#names + 1] = tile_name_lhzb(v)
            end
            lines[#lines + 1] = string.format(
                "  bag-lost (%d): %s",
                #lost,
                table.concat(names, " ")
            )
            -- 弃牌提交：nvram 里新变成「刚从手里消失的那张」的字节
            local commits = {}
            for _, rn in ipairs(snap.regions or {}) do
                if rn.name == "68k_nvram" then
                    local ro = nil
                    for _, x in ipairs(snap_old.regions or {}) do
                        if x.name == rn.name then
                            ro = x
                            break
                        end
                    end
                    if ro then
                        local n = math.min(#rn.data, #ro.data)
                        for i = 1, n do
                            local vn = rn.data:byte(i)
                            local vo = ro.data:byte(i)
                            if vn ~= vo then
                                for _, lost_v in ipairs(lost) do
                                    if vn == lost_v then
                                        local addr = rn.start + i - 1
                                        -- 排除手槽本体被改写
                                        if addr < CPU_HAND_ADDR or addr > CPU_HAND_ADDR + 0x20 then
                                            commits[#commits + 1] = {
                                                addr = addr,
                                                v = vn,
                                                was = vo,
                                            }
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                    break
                end
            end
            table.sort(commits, function(a, b)
                return a.addr < b.addr
            end)
            lines[#lines + 1] = string.format(
                "  commit-cands (new=lost-tile, not hand): %d",
                #commits
            )
            for i = 1, math.min(#commits, 24) do
                local c = commits[i]
                lines[#lines + 1] = string.format(
                    "  #%d @%06X %02X→%02X %s",
                    i,
                    c.addr,
                    c.was or 0,
                    c.v,
                    tile_name_lhzb(c.v)
                )
            end
            if #commits == 0 then
                lines[#lines + 1] =
                    "  (无袋外 commit：可能晚拍；或弃牌只改手槽/河在别处)"
            end
        else
            lines[#lines + 1] = "  bag-lost: (none)"
        end
        -- 邻域字节变了也列出来
        local neigh = {}
        for _, a in ipairs(CPU_DISC_WATCH) do
            local vo, vn = nil, mem.read_u8(machine, a)
            for _, r in ipairs(snap_old.regions or {}) do
                if r.name == "68k_nvram" and a >= r.start and a < r.start + r.size then
                    vo = r.data:byte(a - r.start + 1)
                    break
                end
            end
            if vo ~= nil and vn ~= nil and vo ~= vn then
                neigh[#neigh + 1] = string.format(
                    "@%04X %02X→%02X%s",
                    a,
                    vo,
                    vn,
                    tile_valid_lhzb(vn) and ("(" .. tile_name_lhzb(vn) .. ")") or ""
                )
            end
        end
        if #neigh > 0 then
            lines[#lines + 1] = "  watch-diff " .. table.concat(neigh, " ")
        end
    end
    write_log(table.concat(lines, "\n") .. "\n", "a")
end

local function discard_tap_rm(which)
    local function rm(key)
        local t = discard_lock[key]
        if t then
            pcall(function()
                t:remove()
            end)
            discard_lock[key] = nil
        end
    end
    if which == "river" or which == "all" or not which then
        rm("river_tap")
    end
    if which == "hold" or which == "all" or not which then
        rm("hold_tap")
    end
end

local function discard_prog_space(machine)
    local cpu = machine and machine.devices and machine.devices[":maincpu"]
    return cpu and cpu.spaces and cpu.spaces["program"]
end

-- 读暗手槽位（带地址），供弃牌后 wait↔was 对调
local function read_cpu_hand_slots(machine)
    local bytes, used = read_hand_at(machine, CPU_HAND_ADDR, 14)
    if #bytes < 4 then
        return {}, used
    end
    local slots = {}
    local gap = 0
    local start = used or CPU_HAND_ADDR
    for i = 0, 27 do
        if #slots >= #bytes then
            break
        end
        local a = start + i
        local v = mem.read_u8(machine, a)
        if v == nil then
            break
        end
        if v == 0xFF then
            gap = gap + 1
            if #slots >= 4 and hand_len_ok(#slots) and gap >= 1 then
                break
            end
        elseif tile_valid_lhzb(v) then
            if gap >= 1 and #slots >= 4 and hand_len_ok(#slots) then
                break
            end
            gap = 0
            slots[#slots + 1] = { addr = a, v = v }
        else
            if #slots > 0 then
                break
            end
            gap = 0
        end
    end
    return slots, start
end

local function swap_hand_wait_was(machine, wait, was)
    if not DISCARD_HIJACK_ENABLE or not wait or not was or wait == was then
        return false
    end
    local slots = read_cpu_hand_slots(machine)
    for _, s in ipairs(slots) do
        if s.v == wait then
            mem.write_u8(machine, s.addr, was)
            hand_live_cache.frame = -1
            return true
        end
    end
    return false
end

-- 弃牌镜像：河邻域 + 决定带 + 摸槽
local function collect_discard_mirrors(machine, was, river_addr)
    local hits = {}
    local seen = { [river_addr] = true }
    local function try(a)
        if not a or seen[a] then
            return
        end
        if a >= CPU_HAND_ADDR and a < CPU_HAND_ADDR + 0x30 then
            return
        end
        if a >= PLAYER_HAND_ADDR and a < PLAYER_HAND_ADDR + 0x20 then
            return
        end
        if mem.read_u8(machine, a) == was then
            seen[a] = true
            hits[#hits + 1] = a
        end
    end
    for _, a in ipairs(CPU_DISC_WATCH) do
        try(a)
    end
    try(HYP_LAST_DRAW)
    try(0x5008AD)
    for a = 0x500180, 0x5001C0 do
        try(a)
    end
    for a = DISCARD_DECISION_POKE_LO, DISCARD_DECISION_POKE_HI do
        try(a)
    end
    for a = 0x5008A0, 0x5008B0 do
        try(a)
    end
    return hits
end

-- 待打窗：把决定带+摸槽写成锁定牌（试把手切/摸切决定改掉）
local function poke_decision_band(machine, want, why)
    if not DISCARD_DECISION_POKE or not want or not tile_valid_lhzb(want) then
        return 0
    end
    local n = 0
    for a = DISCARD_DECISION_POKE_LO, DISCARD_DECISION_POKE_HI do
        local cur = mem.read_u8(machine, a)
        if cur ~= want then
            mem.write_u8(machine, a, want)
            n = n + 1
        end
    end
    if mem.read_u8(machine, HYP_LAST_DRAW) ~= want then
        mem.write_u8(machine, HYP_LAST_DRAW, want)
        n = n + 1
    end
    -- @50013D 若已是合法牌，一并改（摸切时常见）
    local h = mem.read_u8(machine, 0x50013D)
    if tile_valid_lhzb(h) and h ~= want then
        mem.write_u8(machine, 0x50013D, want)
        n = n + 1
    end
    if why and n > 0 and (discard_lock._poke_log_n or 0) < 8 then
        discard_lock._poke_log_n = (discard_lock._poke_log_n or 0) + 1
        write_log(
            string.format(
                "=== [disc-decision] POKE %s →%s wrote≈%d @%04X..%04X+33A %s ===\n",
                why,
                tile_name_lhzb(want),
                n,
                DISCARD_DECISION_POKE_LO,
                DISCARD_DECISION_POKE_HI,
                now()
            ),
            "a"
        )
    end
    return n
end

local function poke_addrs(machine, addrs, v)
    for _, a in ipairs(addrs or {}) do
        mem.write_u8(machine, a, v)
    end
end

local function discard_hold_tap_install(machine, river_addr, mirrors, want)
    discard_tap_rm("hold")
    local space = discard_prog_space(machine)
    if not space or not space.install_write_tap or not river_addr or not want then
        return false
    end
    local lo = river_addr
    local hi = river_addr
    for _, a in ipairs(mirrors or {}) do
        if a < lo then
            lo = a
        end
        if a > hi then
            hi = a
        end
    end
    -- 河整段也护住，防机回写旧弃牌
    if lo > CPU_RIVER_ADDR then
        lo = CPU_RIVER_ADDR
    end
    if hi < CPU_RIVER_END - 1 then
        hi = CPU_RIVER_END - 1
    end
    local ok, tap = pcall(function()
        return space:install_write_tap(
            lo,
            hi,
            "fei_lhzb2_feed_hold",
            function(offset, data, _mask)
                local h = discard_lock.feed_hold
                if not h or not h.v then
                    return
                end
                local addr = offset
                if addr < 0x10000 then
                    addr = 0x500000 + (addr & 0xFFFF)
                end
                local cur = (data or 0) & 0xFF
                if cur == h.v then
                    return
                end
                if addr == h.addr then
                    return h.v
                end
                for _, a in ipairs(h.mirrors or {}) do
                    if addr == a then
                        return h.v
                    end
                end
            end
        )
    end)
    if ok and tap then
        discard_lock.hold_tap = tap
        return true
    end
    return false
end

-- 弃牌写入当下劫持（比「河变长后再改」早，尽量跟播报同源）
local function discard_river_tap_install(machine)
    discard_tap_rm("river")
    if not discard_lock.armed or not discard_lock.lhzb then
        return false
    end
    local space = discard_prog_space(machine)
    if not space or not space.install_write_tap then
        return false
    end
    local mach = machine
    local ok, tap = pcall(function()
        return space:install_write_tap(
            CPU_RIVER_ADDR,
            CPU_RIVER_END - 1,
            "fei_lhzb2_feed_riv",
            function(offset, data, _mask)
                if not DISCARD_FEED_ENABLE then
                    return
                end
                if not discard_lock.armed or not discard_lock.lhzb then
                    return
                end
                if discard_lock.feed_hold then
                    return
                end
                local want = discard_lock.lhzb
                local was = (data or 0) & 0xFF
                if not tile_valid_lhzb(was) then
                    return
                end
                if was == want then
                    return
                end
                local addr = offset
                if addr < 0x10000 then
                    addr = 0x500000 + (addr & 0xFFFF)
                end
                -- 只劫持「往空槽写牌」（非已有河牌），避免改历史河
                local prev = mem.read_u8(mach, addr)
                if prev ~= nil and tile_valid_lhzb(prev) and prev ~= 0xFF then
                    return
                end
                discard_lock._tap_pending = { addr = addr, was = was, want = want }
                return want
            end
        )
    end)
    if ok and tap then
        discard_lock.river_tap = tap
        return true
    end
    return false
end

local function discard_feed_commit(machine, river_addr, was, want, why)
    if not machine or not river_addr or not want then
        return false
    end
    was = was or mem.read_u8(machine, river_addr) or 0
    poke_decision_band(machine, want, why or "commit")
    mem.write_u8(machine, river_addr, want)
    local mirrors = {}
    if was ~= want and tile_valid_lhzb(was) then
        mirrors = collect_discard_mirrors(machine, was, river_addr)
        poke_addrs(machine, mirrors, want)
    end
    local swapped = false
    if was ~= want and tile_valid_lhzb(was) then
        swapped = swap_hand_wait_was(machine, want, was)
    end
    discard_lock.feed_hold = {
        addr = river_addr,
        v = want,
        was = was,
        mirrors = mirrors,
        frames = 90,
        swapped = swapped,
    }
    discard_hold_tap_install(machine, river_addr, mirrors, want)
    discard_lock.armed = false
    discard_lock.lhzb = nil
    discard_tap_rm("river")
    local mir_s = {}
    for i = 1, math.min(#mirrors, 12) do
        mir_s[#mir_s + 1] = string.format("%06X", mirrors[i])
    end
    write_log(
        string.format(
            "=== [cpu-discard-feed] COMMIT %s @%06X %s(%02X)→%s(%02X) swap=%s mirrors=%d [%s] %s ===\n",
            why or "?",
            river_addr,
            tile_valid_lhzb(was) and tile_name_lhzb(was) or "?",
            was or 0,
            tile_name_lhzb(want),
            want,
            swapped and "Y" or "N",
            #mirrors,
            table.concat(mir_s, ","),
            now()
        ),
        "a"
    )
    machine:popmessage(
        string.format(
            "控打→%s（原%s）\nmirror=%d 手槽不改",
            tile_name_lhzb(want),
            tile_valid_lhzb(was) and tile_name_lhzb(was) or "?",
            #mirrors
        )
    )
    return true
end

local function discard_lock_clear(why)
    if discard_lock.armed or discard_lock.feed_hold or discard_lock.river_tap then
        write_log(
            string.format(
                "=== [cpu-discard-feed] CLEAR %s was=%s ===\n",
                why or "?",
                discard_lock.lhzb and tile_name_lhzb(discard_lock.lhzb) or "-"
            ),
            "a"
        )
    end
    discard_lock.lhzb = nil
    discard_lock.armed = false
    discard_lock.feed_hold = nil
    discard_lock._tap_pending = nil
    discard_tap_rm("all")
end

local function discard_lock_select(machine, bcd)
    local lhzb = bcd_to_lhzb(bcd)
    if not lhzb or not tile_valid_lhzb(lhzb) then
        machine:popmessage("控打锁定：无效牌")
        return
    end
    if discard_lock.armed and discard_lock.lhzb == lhzb then
        discard_lock_clear("click_same")
        machine:popmessage("控打锁定取消")
        return
    end
    discard_lock.lhzb = lhzb
    discard_lock.armed = true
    discard_lock.feed_hold = nil
    discard_lock._tap_pending = nil
    discard_lock._poke_log_n = 0
    local tap_ok = discard_river_tap_install(machine)
    local poked = poke_decision_band(machine, lhzb, "lock")
    write_log(
        string.format(
            "=== [cpu-discard-feed] LOCK %s (%02X) tap=%s poke=%d %s ===\n",
            tile_name_lhzb(lhzb),
            lhzb,
            tap_ok and "Y" or "N",
            poked or 0,
            now()
        ),
        "a"
    )
    machine:popmessage(
        string.format(
            "锁→%s\n待打时改决定带+摸槽",
            tile_name_lhzb(lhzb)
        )
    )
end

-- 短时盖回河末+镜像；处理 tap 命中
local function discard_lock_run_tick(machine)
    local pend = discard_lock._tap_pending
    if pend and pend.addr and pend.want then
        discard_lock._tap_pending = nil
        discard_feed_commit(machine, pend.addr, pend.was, pend.want, "write-tap")
        discard_auto.cooldown = 40
        return
    end
    local h = discard_lock.feed_hold
    if not h or not h.addr or not h.v then
        return
    end
    if mem.read_u8(machine, h.addr) ~= h.v then
        mem.write_u8(machine, h.addr, h.v)
    end
    poke_addrs(machine, h.mirrors, h.v)
    if DISCARD_HIJACK_ENABLE
        and h.was
        and h.was ~= h.v
        and not h.swapped
        and (h.frames or 0) % 8 == 0
    then
        h.swapped = swap_hand_wait_was(machine, h.v, h.was) or h.swapped
    end
    h.frames = (h.frames or 0) - 1
    if h.frames <= 0 then
        discard_tap_rm("hold")
        discard_lock.feed_hold = nil
    end
end

-- 碰前 baseline → 碰后 step：找「新出现」的碰/吃块（不依赖暗手是否还能读）
local function meld_hit_sig(h)
    return string.format(
        "%06X:%02X:%02X%02X%02X",
        h.addr,
        h.mark or 0,
        h.tiles[1] or 0,
        h.tiles[2] or 0,
        h.tiles[3] or 0
    )
end

-- 从 nvram 快照抽电脑暗手（与 read_hand_at 同逻辑：头+跳 FF）
local function hand_from_nvram_data(data, base, addr)
    if not data or not addr or addr < base then
        return {}
    end
    local function at(a)
        local off = a - base + 1
        if off < 1 or off > #data then
            return nil
        end
        return data:byte(off)
    end
    local function skip_ff_body(start_addr, maxn)
        maxn = maxn or 14
        local bytes = {}
        local gap = 0
        for i = 0, 27 do
            if #bytes >= maxn then
                break
            end
            local v = at(start_addr + i)
            if v == nil then
                break
            end
            if v == 0xFF then
                gap = gap + 1
                if #bytes >= 4 and hand_len_ok(#bytes) and gap >= 1 then
                    break
                end
            elseif tile_valid_lhzb(v) then
                if gap >= 1 and #bytes >= 4 and hand_len_ok(#bytes) then
                    break
                end
                gap = 0
                bytes[#bytes + 1] = v
            else
                if #bytes > 0 then
                    break
                end
                gap = 0
            end
        end
        if #bytes > 0 and not hand_len_ok(#bytes) then
            for _, n in ipairs({ 14, 13, 11, 10, 8, 7, 5, 4 }) do
                if #bytes >= n then
                    local t = {}
                    for i = 1, n do
                        t[i] = bytes[i]
                    end
                    return t
                end
            end
        end
        return bytes
    end
    -- 与 read_hand_at 一致：先直读，非牌长度头再跳
    local plain = skip_ff_body(addr, 14)
    if #plain >= 4 and hand_len_ok(#plain) then
        return plain
    end
    local hdr = at(addr)
    if hdr and looks_like_len_hdr(hdr) then
        local body = skip_ff_body(addr + 1, math.max(hdr, 14))
        if #body >= 4 and hand_len_ok(#body) then
            return body
        end
    end
    hdr = at(addr - 1)
    if hdr and looks_like_len_hdr(hdr) then
        local body = skip_ff_body(addr, math.max(hdr, 14))
        if #body >= 4 and hand_len_ok(#body) then
            return body
        end
    end
    if #plain >= 4 then
        return plain
    end
    return plain
end

-- 暗手后 FF 间隔的零散牌（副露残片候选）
local function meld_tail_from_nvram(data, base, hand_end_addr)
    local tiles = {}
    local off0 = hand_end_addr - base + 1
    local i = off0
    local n = #data
    local guard = 0
    while i <= n and guard < 32 do
        local v = data:byte(i)
        if v == 0xFF then
            i = i + 1
            guard = guard + 1
        elseif tile_valid_lhzb(v) then
            tiles[#tiles + 1] = { addr = base + i - 1, tile = v }
            i = i + 1
            guard = guard + 1
            if #tiles >= 6 then
                break
            end
        else
            break
        end
    end
    return tiles
end

local function bag_sub(old_bytes, new_bytes)
    local c = hand_bag_counts(old_bytes)
    for _, v in ipairs(new_bytes or {}) do
        if c[v] then
            c[v] = c[v] - 1
            if c[v] <= 0 then
                c[v] = nil
            end
        end
    end
    local removed = {}
    for v, n in pairs(c) do
        for _ = 1, n do
            removed[#removed + 1] = v
        end
    end
    table.sort(removed)
    return removed
end

local function dump_meld_diff(snap_old, snap_new, why, machine)
    if not snap_old or not snap_new then
        return
    end
    local disc = machine and mem.read_u8(machine, HYP_LAST_DISC) or nil
    local lines = {
        string.format(
            "=== [meld-diff] %s disc=%s %s ===",
            why or "?",
            tile_valid_lhzb(disc) and tile_name_lhzb(disc) or string.format("%02X", disc or 0),
            now()
        ),
    }

    -- bag 差：暗手少了哪些牌（再扣掉电脑刚打出的一张）→ 副露来自手牌的部分
    local nv_old, nv_new = nil, nil
    for _, r in ipairs(snap_old.regions or {}) do
        if r.name == "68k_nvram" then
            nv_old = r
            break
        end
    end
    for _, r in ipairs(snap_new.regions or {}) do
        if r.name == "68k_nvram" then
            nv_new = r
            break
        end
    end
    if nv_old and nv_new then
        local hold = hand_from_nvram_data(nv_old.data, nv_old.start, CPU_HAND_ADDR)
        local hnew = hand_from_nvram_data(nv_new.data, nv_new.start, CPU_HAND_ADDR)
        local removed = bag_sub(hold, hnew)
        -- 电脑弃牌：@500185 或邻近新出现的单牌（本局见 @500186=六万）
        local cpu_disc = nil
        for a = HYP_LAST_DISC, HYP_LAST_DISC + 4 do
            local off = a - nv_new.start + 1
            if off >= 1 and off <= #nv_new.data then
                local v = nv_new.data:byte(off)
                local vo = nv_old.data:byte(off)
                if tile_valid_lhzb(v) and v ~= vo then
                    cpu_disc = v
                    break
                end
            end
        end
        local from_hand = {}
        local skipped_disc = false
        for _, v in ipairs(removed) do
            if (not skipped_disc) and cpu_disc and v == cpu_disc then
                skipped_disc = true
            else
                from_hand[#from_hand + 1] = v
            end
        end
        local tail = meld_tail_from_nvram(nv_new.data, nv_new.start, CPU_HAND_ADDR + 16)
        local tail_s = {}
        for _, t in ipairs(tail) do
            tail_s[#tail_s + 1] = string.format("@%04X:%s", t.addr, tile_name_lhzb(t.tile))
        end
        lines[#lines + 1] = string.format(
            "  bag: closed %d→%d removed=[%s] cpu_disc=%s from_hand=[%s]",
            #hold,
            #hnew,
            #removed > 0 and tiles_preview_lhzb(removed) or "-",
            cpu_disc and tile_name_lhzb(cpu_disc) or "-",
            #from_hand > 0 and tiles_preview_lhzb(from_hand) or "-"
        )
        if #tail_s > 0 then
            lines[#lines + 1] = "  tail-near-hand: " .. table.concat(tail_s, " ")
        end
        meld_watch.bag_hint = {
            from_hand = from_hand,
            cpu_disc = cpu_disc,
            closed_n = #hnew,
        }
        -- 玩家手少的那张 ≈ 被吃/碰的弃牌
        local pl_old = hand_from_nvram_data(nv_old.data, nv_old.start, PLAYER_HAND_ADDR)
        local pl_new = hand_from_nvram_data(nv_new.data, nv_new.start, PLAYER_HAND_ADDR)
        local pl_lost = bag_sub(pl_old, pl_new)
        if #pl_lost > 0 then
            lines[#lines + 1] = string.format(
                "  player_lost=[%s] (claim tile?)",
                tiles_preview_lhzb(pl_lost)
            )
            meld_watch.bag_hint.claim = pl_lost[1]
        end
    end

    local function collect(snap)
        local out = {}
        for _, r in ipairs(snap.regions or {}) do
            if r.name == "68k_nvram" then
                for _, h in ipairs(scan_meld_like(r.data, r.start)) do
                    h.dist = math.min(math.abs(h.addr - CPU_HAND_ADDR), math.abs(h.addr - PLAYER_HAND_ADDR))
                    out[#out + 1] = h
                end
            end
        end
        return out
    end
    local olds = collect(snap_old)
    local news = collect(snap_new)
    local old_sig = {}
    for _, h in ipairs(olds) do
        old_sig[meld_hit_sig(h)] = true
    end
    local appeared = {}
    local hint = meld_watch.bag_hint
    for _, h in ipairs(news) do
        if not old_sig[meld_hit_sig(h)] then
            local score = 0
            if h.kind == "pon" then
                score = score + 100
            elseif h.kind == "chi" then
                score = score + 40
            end
            if disc and h.tiles[1] == disc and h.tiles[2] == disc and h.tiles[3] == disc then
                score = score + 200
            end
            if disc
                and h.kind == "chi"
                and (h.tiles[1] == disc or h.tiles[2] == disc or h.tiles[3] == disc)
            then
                score = score + 120
            end
            -- bag 提示加分：块内牌与 from_hand / claim 重合
            if hint then
                local claim = hint.claim
                for _, t in ipairs(h.tiles) do
                    if claim and t == claim then
                        score = score + 80
                    end
                    for _, fh in ipairs(hint.from_hand or {}) do
                        if t == fh then
                            score = score + 50
                        end
                    end
                end
            end
            if h.tiles[1] == 0 and h.tiles[2] == 0 and h.tiles[3] == 0 then
                score = -999
            end
            if h.dist and h.dist < 0x100 then
                score = score + math.max(0, 80 - math.floor(h.dist / 2))
            end
            h.score = score
            if score >= 0 then
                appeared[#appeared + 1] = h
            end
        end
    end
    table.sort(appeared, function(a, b)
        if (a.score or 0) ~= (b.score or 0) then
            return (a.score or 0) > (b.score or 0)
        end
        return (a.dist or 0) < (b.dist or 0)
    end)
    lines[#lines + 1] = string.format("  new meld-like %d (show ≤15):", #appeared)
    for i = 1, math.min(#appeared, 15) do
        local h = appeared[i]
        lines[#lines + 1] = string.format(
            "  #%d @%06X %s mark=%02X score=%d dist=%d  %s",
            i,
            h.addr,
            h.kind,
            h.mark,
            h.score or 0,
            h.dist or -1,
            h.preview
        )
    end
    if not MELD_CPU_ADDR then
        for _, h in ipairs(appeared) do
            if (h.kind == "pon" or h.kind == "chi") and (h.score or 0) >= 150 then
                local blocks = machine and read_meld_blocks_at(machine, h.addr, 4) or {}
                if #blocks >= 1 or (h.tiles[1] == h.tiles[2] and h.tiles[2] == h.tiles[3]) or h.kind == "chi" then
                    MELD_CPU_ADDR = h.addr
                    meld_watch.cpu_addr = h.addr
                    meld_watch.blocks = #blocks > 0 and blocks
                        or { { addr = h.addr, mark = h.mark, tiles = h.tiles } }
                    lines[#lines + 1] = string.format(
                        "  >> auto-pin MELD_CPU_ADDR=@%06X (%s %s)",
                        h.addr,
                        h.kind,
                        h.preview
                    )
                    break
                end
            end
        end
    end
    if MELD_CPU_ADDR == 0x500102 then
        lines[#lines + 1] = "  >> unpin MELD_CPU_ADDR=@500102"
        MELD_CPU_ADDR = nil
    end
    if not MELD_CPU_ADDR then
        lines[#lines + 1] =
            "  (无高分新块 — bag/tail 仍写入 log；口数已可用 13-3n)"
    end
    write_log(table.concat(lines, "\n") .. "\n", "a")
    return appeared
end

local function tick_meld_watch(machine)
    local cpu = select(1, read_cpu_hand_live(machine))
    local n = #cpu
    if n < 4 then
        return
    end
    -- 要求同一张数连续多帧，避免 FF 解析闪烁触发 13→11→10→8
    if meld_watch.stable_n == n then
        meld_watch.stable_frames = (meld_watch.stable_frames or 0) + 1
    else
        meld_watch.stable_n = n
        meld_watch.stable_frames = 1
    end
    local prev = meld_watch.prev_n
    -- 一口 13→11/10；二口 11/10→8/7；三口 8/7→5/4
    local drop_ok = prev and n < prev and (prev - n == 3 or prev - n == 2 or prev - n == 4)
    local band_ok = (prev >= 13 and n <= 11)
        or (prev >= 10 and prev <= 11 and n <= 8)
        or (prev >= 7 and prev <= 8 and n <= 5)
    if prev and meld_watch.stable_frames >= 8 and drop_ok and band_ok then
        local why = string.format("auto-closed %d→%d", prev, n)
        local snap_now = nil
        pcall(function()
            snap_now = snapshot_all(machine)
            for _, r in ipairs(snap_now.regions or {}) do
                write_bin(string.format("smoke_logs/lhzb2_%s_auto.bin", r.name), r.data)
            end
            write_log(
                string.format(
                    "=== AUTO-SNAP %s closed=%d %s ===\n%s\n",
                    why,
                    n,
                    now(),
                    format_live_hands(machine)
                ),
                "a"
            )
            if snap_base then
                dump_meld_diff(snap_base, snap_now, why, machine)
            end
            dump_meld_hunt(machine, why, snap_now)
        end)
        pcall(function()
            if PAUSE_ON_HUNT and not machine.paused then
                emu.pause()
            end
        end)
        pcall(function()
            machine:popmessage(
                string.format(
                    "电脑暗手 %d→%d（疑似副露，已自动存盘）\n再按 右Ctrl+2 更稳",
                    prev,
                    n
                )
            )
        end)
        meld_watch.prev_n = n
    elseif meld_watch.stable_frames >= 8 then
        meld_watch.prev_n = n
    end
    if MELD_CPU_ADDR and MELD_CPU_ADDR ~= 0x500102 then
        meld_watch.blocks = read_meld_blocks_at(machine, MELD_CPU_ADDR, 4)
    elseif MELD_CPU_ADDR == 0x500102 then
        MELD_CPU_ADDR = nil
    end
end

local function is_await_closed_n(n)
    return n == 14 or n == 11 or n == 8 or n == 5
end

local function is_settled_closed_n(n)
    return n == 13 or n == 10 or n == 7 or n == 4
end

local function decision_capture_bytes(machine)
    local bytes = {}
    for _, rg in ipairs(DISCARD_DECISION_RANGES) do
        for a = rg[1], rg[2] do
            bytes[a] = mem.read_u8(machine, a) or 0
        end
    end
    for _, a in ipairs(PROT_TURN_WATCH) do
        bytes[a] = mem.read_u8(machine, a) or 0
    end
    for _, a in ipairs(CPU_DISC_WATCH) do
        bytes[a] = mem.read_u8(machine, a) or 0
    end
    return bytes
end

local function decision_fmt_watch(bytes, addrs)
    local parts = {}
    for _, a in ipairs(addrs) do
        local v = bytes and bytes[a]
        if v ~= nil then
            parts[#parts + 1] = string.format(
                "@%06X=%02X%s",
                a,
                v,
                tile_valid_lhzb(v) and ("(" .. tile_name_lhzb(v) .. ")") or ""
            )
        end
    end
    return table.concat(parts, " ")
end

local function decision_dump_await(machine, hand_n, draw_v)
    if not DISCARD_DECISION_AUTO then
        return
    end
    discard_decision.seq = (discard_decision.seq or 0) + 1
    local bytes = decision_capture_bytes(machine)
    discard_decision.pre = {
        t = now(),
        seq = discard_decision.seq,
        hand_n = hand_n,
        draw = draw_v,
        bytes = bytes,
    }
    local focus = {
        0x50013D,
        0x50033A,
        0x50033B,
        0x50089D,
        0x5008A2,
        0x500233,
        0x500235,
        0x100299,
        0x10029A,
        0x10029B,
    }
    write_log(
        string.format(
            "=== [disc-decision] AWAIT #%d closed=%d draw=%s(%02X) %s ===\n  %s\n",
            discard_decision.seq,
            hand_n or 0,
            tile_valid_lhzb(draw_v) and tile_name_lhzb(draw_v) or "-",
            draw_v or 0,
            now(),
            decision_fmt_watch(bytes, focus)
        ),
        "a"
    )
end

-- 河追加后：对照待打快照，找「已是弃牌」与「新变成弃牌」的地址
local function decision_dump_after(machine, disc_v, disc_addr)
    if not DISCARD_DECISION_AUTO or not disc_v then
        return
    end
    local pre = discard_decision.pre
    local post = decision_capture_bytes(machine)
    local draw_v = pre and pre.draw or mem.read_u8(machine, HYP_LAST_DRAW)
    local tedashi = draw_v and disc_v and draw_v ~= disc_v
    local early, newborn = {}, {}
    if pre and pre.bytes then
        for addr, pv in pairs(pre.bytes) do
            local nv = post[addr]
            if pv == disc_v then
                early[#early + 1] = addr
            end
            if nv == disc_v and pv ~= disc_v then
                newborn[#newborn + 1] = addr
            end
        end
        table.sort(early)
        table.sort(newborn)
    end
    local function list_addrs(t, maxn)
        maxn = maxn or 16
        local parts = {}
        for i = 1, math.min(#t, maxn) do
            local a = t[i]
            local pv = pre and pre.bytes and pre.bytes[a]
            local nv = post[a]
            parts[#parts + 1] = string.format(
                "@%06X %02X→%02X",
                a,
                pv or 0,
                nv or 0
            )
        end
        if #t > maxn then
            parts[#parts + 1] = string.format("…+%d", #t - maxn)
        end
        return table.concat(parts, " ")
    end
    write_log(
        string.format(
            "=== [disc-decision] AFTER #%d disc=%s(%02X)@%06X %s draw=%s tedashi=%s ===\n  early(pre==disc)=%d %s\n  newborn=%d %s\n",
            (pre and pre.seq) or 0,
            tile_name_lhzb(disc_v),
            disc_v,
            disc_addr or 0,
            now(),
            tile_valid_lhzb(draw_v) and tile_name_lhzb(draw_v) or "-",
            tedashi and "Y" or "N",
            #early,
            list_addrs(early, 20),
            #newborn,
            list_addrs(newborn, 20)
        ),
        "a"
    )
    discard_decision.pre = nil
    discard_decision.dumped = false
    discard_decision.await_on = false
    discard_decision.stable = 0
end

local function tick_discard_decision(machine)
    if not DISCARD_DECISION_AUTO then
        return
    end
    local cpu = select(1, read_cpu_hand_live(machine))
    local n = #cpu
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW)
    if is_await_closed_n(n) then
        if discard_decision.await_on then
            discard_decision.stable = (discard_decision.stable or 0) + 1
        else
            discard_decision.await_on = true
            discard_decision.stable = 1
            discard_decision.dumped = false
        end
        if (not discard_decision.dumped) and discard_decision.stable >= 6 then
            discard_decision.dumped = true
            pcall(decision_dump_await, machine, n, draw_v)
        end
        -- 已锁定：待打窗持续改写决定带（防机盖回）
        if discard_lock.armed and discard_lock.lhzb and (discard_decision.stable % 4) == 0 then
            pcall(poke_decision_band, machine, discard_lock.lhzb, nil)
        end
    else
        if discard_decision.await_on and not discard_decision.pre then
            discard_decision.await_on = false
            discard_decision.stable = 0
            discard_decision.dumped = false
        end
    end
end

-- 电脑河追加一张 → 河末喂荣（轻量：不扫 nvram、不写 bin）
local function tick_discard_auto(machine)
    pcall(tick_discard_decision, machine)
    if discard_auto.cooldown and discard_auto.cooldown > 0 then
        discard_auto.cooldown = discard_auto.cooldown - 1
    end
    local riv = read_cpu_river(machine)
    local rn = #riv
    local last_v = rn > 0 and riv[rn].v or nil
    local last_addr = rn > 0 and riv[rn].addr or nil

    -- 开局河空：prev 用 0，否则第一张 0→1 永远不触发（锁西打南就漏过）
    local prev_rn = discard_auto.prev_river_n
    if prev_rn == nil then
        discard_auto.prev_river_n = rn
        discard_auto.river_stable = 1
        discard_auto.last_disc = last_v
        return
    end

    if prev_rn == rn then
        discard_auto.river_stable = (discard_auto.river_stable or 0) + 1
    else
        if rn == prev_rn + 1 and last_v and (discard_auto.cooldown or 0) == 0 then
            discard_auto._pending_grow = {
                from = prev_rn,
                to = rn,
                v = last_v,
                addr = last_addr,
            }
            write_log(
                string.format(
                    "=== [cpu-discard-feed] RIVER-GROW %d→%d @%06X %s(%02X) armed=%s %s ===\n",
                    prev_rn,
                    rn,
                    last_addr or 0,
                    tile_name_lhzb(last_v),
                    last_v or 0,
                    (discard_lock.armed and discard_lock.lhzb)
                            and tile_name_lhzb(discard_lock.lhzb)
                        or "-",
                    now()
                ),
                "a"
            )
        elseif rn < prev_rn then
            -- 新局河缩短/清空：取消未决 grow，保留锁定供下一手
            discard_auto._pending_grow = nil
            discard_decision.pre = nil
            discard_decision.dumped = false
            discard_decision.await_on = false
        end
        discard_auto.prev_river_n = rn
        discard_auto.river_stable = 1
    end

    local pend = discard_auto._pending_grow
    if pend and discard_auto.river_stable >= 2 and rn == pend.to and (discard_auto.cooldown or 0) == 0 then
        local fed = false
        local feed_v = pend.v
        -- 写监视未命中时的兜底（电子基盘也有 post-river commit）
        if DISCARD_FEED_ENABLE
            and discard_lock.armed
            and discard_lock.lhzb
            and pend.addr
            and not discard_lock.feed_hold
        then
            local want = discard_lock.lhzb
            local was = pend.v
            if discard_feed_commit(machine, pend.addr, was, want, "river-grow") then
                feed_v = want
                fed = true
            end
        elseif discard_lock.feed_hold and pend.addr == discard_lock.feed_hold.addr then
            fed = true
            feed_v = discard_lock.feed_hold.v
        end

        -- 真弃牌值用 pend.v（AI 原值），喂荣后 feed_v 可能已改
        pcall(decision_dump_after, machine, pend.v, pend.addr)

        if fed or AUTO_DISCARD_HUNT_LOG then
            write_log(
                string.format(
                    "=== AUTO-DISCARD auto-river %d→%d @%04X %s%s %s ===\n",
                    pend.from,
                    pend.to,
                    pend.addr or 0,
                    tile_name_lhzb(feed_v),
                    fed and " FEED" or "",
                    now()
                ),
                "a"
            )
        end
        if AUTO_DISCARD_HUNT_LOG then
            pcall(function()
                local snap_now = snapshot_all(machine)
                dump_cpu_discard_hunt(machine, "auto-river", snap_now, discard_auto.snap_pre)
            end)
        end
        if (not fed) and AUTO_DISCARD_PAUSE then
            pcall(function()
                if PAUSE_ON_HUNT and not machine.paused then
                    emu.pause()
                end
            end)
            pcall(function()
                machine:popmessage(
                    string.format(
                        "电脑河+%s @%04X\n取消暂停继续",
                        tile_name_lhzb(pend.v),
                        pend.addr or 0
                    )
                )
            end)
        end
        discard_auto.cooldown = fed and 40 or 120
        discard_auto.snap_pre = nil
        discard_auto._pending_grow = nil
        discard_auto.last_disc = feed_v
        return
    end

    if not pend or rn ~= (pend and pend.to) then
        discard_auto._pending_grow = nil
    end
    discard_auto.last_disc = last_v
end

-- 牌山候选：连续合法牌、长度够、取值多样（排除大片 00）
local function scan_wall_candidates(snap)
    local hits = {}
    for _, r in ipairs(snap.regions or {}) do
        local data = r.data
        local i = 1
        local n = #data
        while i <= n do
            local b = data:byte(i)
            if tile_valid_lhzb(b) then
                local run = { b }
                local uniq = { [b] = true }
                local j = i + 1
                while j <= n and #run < 140 and tile_valid_lhzb(data:byte(j)) do
                    local v = data:byte(j)
                    run[#run + 1] = v
                    uniq[v] = true
                    j = j + 1
                end
                local nu = 0
                for _ in pairs(uniq) do
                    nu = nu + 1
                end
                local zero_n = 0
                for _, v in ipairs(run) do
                    if v == 0 then
                        zero_n = zero_n + 1
                    end
                end
                if #run >= 40 and nu >= 10 and zero_n < (#run * 0.45) then
                    hits[#hits + 1] = {
                        addr = r.start + i - 1,
                        len = #run,
                        uniq = nu,
                        preview = tiles_preview_lhzb(run, 16),
                        head = run[1],
                    }
                end
                i = j
            else
                i = i + 1
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.len ~= b.len then
            return a.len > b.len
        end
        return a.uniq > b.uniq
    end)
    return hits
end

local function format_wall_hits(hits, limit)
    limit = limit or 12
    local lines = {
        string.format("wall-candidates %d (show %d):", #hits, math.min(#hits, limit)),
    }
    for i = 1, math.min(#hits, limit) do
        local h = hits[i]
        lines[#lines + 1] = string.format(
            "  #%d @%06X len=%d uniq=%d head=%02X  %s",
            i,
            h.addr,
            h.len,
            h.uniq,
            h.head or 0,
            h.preview
        )
    end
    return table.concat(lines, "\n")
end

-- 摸一张后：找「旧山头==摸入牌、且新山是旧山去掉头」的缓冲
local function hunt_wall_consume(snap_old, snap_new, draw_v)
    if not draw_v or not tile_valid_lhzb(draw_v) or not snap_old or not snap_new then
        return {}
    end
    local out = {}
    for _, rb in ipairs(snap_new.regions or {}) do
        local ra = nil
        for _, r in ipairs(snap_old.regions or {}) do
            if r.name == rb.name then
                ra = r
                break
            end
        end
        if ra and #ra.data == #rb.data then
            local a, bdata = ra.data, rb.data
            local n = #a
            local i = 1
            while i <= n - 40 do
                if a:byte(i) == draw_v then
                    local ok = true
                    local matched = 0
                    for k = 0, 39 do
                        local old_v = a:byte(i + 1 + k)
                        local new_v = bdata:byte(i + k)
                        if not tile_valid_lhzb(old_v) then
                            break
                        end
                        if old_v ~= new_v then
                            ok = false
                            break
                        end
                        matched = matched + 1
                    end
                    if ok and matched >= 20 then
                        out[#out + 1] = {
                            addr = ra.start + i - 1,
                            matched = matched,
                            draw = draw_v,
                        }
                    end
                end
                i = i + 1
            end
        end
    end
    return out
end

local function format_wall_consume(hits)
    if not hits or #hits == 0 then
        return "wall-consume: (none)"
    end
    local lines = { string.format("wall-consume %d:", #hits) }
    for i = 1, math.min(#hits, 12) do
        local h = hits[i]
        lines[#lines + 1] = string.format(
            "  #%d @%06X matched=%d draw=%02X(%s)",
            i,
            h.addr,
            h.matched,
            h.draw,
            tile_name_lhzb(h.draw)
        )
    end
    return table.concat(lines, "\n")
end

local function scan_runs(data, base, pred, enc_name, want_len)
    local hits = {}
    local i = 1
    local n = #data
    while i <= n do
        local b = data:byte(i)
        if pred(b) then
            local run = { b }
            local j = i + 1
            while j <= n and #run < 20 and pred(data:byte(j)) do
                run[#run + 1] = data:byte(j)
                j = j + 1
            end
            if #run >= want_len then
                hits[#hits + 1] = {
                    addr = base + i - 1,
                    len = #run,
                    enc = enc_name,
                    bytes = run,
                    preview = tiles_preview(run, enc_name == "lin33" and "lin" or "bcd", 14),
                }
            end
            i = j
        else
            i = i + 1
        end
    end
    return hits
end

local function scan_hand_candidates(snap)
    local hits = {}
    local function add_all(list)
        for _, h in ipairs(list) do
            hits[#hits + 1] = h
        end
    end
    for _, r in ipairs(snap.regions or {}) do
        add_all(scan_runs(r.data, r.start, function(b)
            return BCD_A[b] == true
        end, "bcdA", 13))
        add_all(scan_runs(r.data, r.start, function(b)
            return BCD_B[b] == true
        end, "bcdB", 13))
        add_all(scan_runs(r.data, r.start, function(b)
            return b <= 33
        end, "lin33", 13))
    end
    -- 优先 13/14 张
    table.sort(hits, function(a, b)
        local sa = (a.len == 13 or a.len == 14) and 0 or 1
        local sb = (b.len == 13 or b.len == 14) and 0 or 1
        if sa ~= sb then
            return sa < sb
        end
        return a.addr < b.addr
    end)
    return hits
end

local function format_hits(hits, limit)
    limit = limit or 12
    local lines = {}
    lines[#lines + 1] = string.format("hand-candidates %d (show %d):", #hits, math.min(#hits, limit))
    for i = 1, math.min(#hits, limit) do
        local h = hits[i]
        lines[#lines + 1] = string.format(
            "  #%d @%06X len=%d enc=%s  %s",
            i,
            h.addr,
            h.len,
            h.enc,
            h.preview
        )
    end
    return table.concat(lines, "\n")
end

local function collect_diff_runs(a, b, base, max_runs)
    max_runs = max_runs or 40
    local runs = {}
    local i = 1
    local n = math.min(#a, #b)
    while i <= n and #runs < max_runs do
        if a:byte(i) ~= b:byte(i) then
            local s = i
            local oldb, newb = {}, {}
            while i <= n and a:byte(i) ~= b:byte(i) and (#oldb < 48) do
                oldb[#oldb + 1] = string.format("%02X", a:byte(i))
                newb[#newb + 1] = string.format("%02X", b:byte(i))
                i = i + 1
            end
            runs[#runs + 1] = {
                addr = base + s - 1,
                len = i - s,
                old = table.concat(oldb, " "),
                new = table.concat(newb, " "),
            }
        else
            i = i + 1
        end
    end
    return runs
end

local function format_diff(snap_old, snap_new)
    local lines = { string.format("=== DIFF %s ===", now()) }
    for _, rb in ipairs(snap_new.regions or {}) do
        local ra = region(snap_old, rb.name)
        if ra and #ra.data == #rb.data then
            local runs = collect_diff_runs(ra.data, rb.data, rb.start, 48)
            lines[#lines + 1] = string.format("[%s] changed_runs=%d", rb.name, #runs)
            for j = 1, math.min(#runs, 24) do
                local u = runs[j]
                lines[#lines + 1] = string.format(
                    "  @%06X +%d\n    - %s\n    + %s",
                    u.addr,
                    u.len,
                    u.old,
                    u.new
                )
            end
        end
    end
    return table.concat(lines, "\n")
end

local function pause_for_hunt(machine)
    if not PAUSE_ON_HUNT then
        return
    end
    pcall(function()
        if not machine.paused then
            emu.pause()
        end
    end)
end

local function bind_keys(machine)
    local input = machine.input
    if not input or not input.seq_from_tokens then
        return
    end
    -- 允许补绑：旧会话若先跑过无 seq6 的版本，不能因 seq5 已有就永久跳过
    if not seq5 then
        seq5 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_5")
        seq2 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_2")
        seq3 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_3")
        seq9 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_9")
        seq0 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_0")
    end
    if not seq6 then
        seq6 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_6")
    end
    if not seq6l then
        seq6l = input:seq_from_tokens("KEYCODE_LCONTROL KEYCODE_6")
    end
    if not seq7 then
        seq7 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_7")
    end
    if not seq8 then
        seq8 = input:seq_from_tokens("KEYCODE_RCONTROL KEYCODE_8")
    end
    keys_bound_ok = (seq6 ~= nil) or (seq6l ~= nil) or (seq7 ~= nil) or (seq8 ~= nil)
end

local function edge(slot, seq)
    if not seq then
        return false
    end
    local input = manager.machine.input
    local down = false
    pcall(function()
        down = input:seq_pressed(seq)
    end)
    local was = prev[slot]
    prev[slot] = down
    return down and not was
end

local peek_click = false
local bonus_click = false
local hooked_views = {}
local ptr_held = {}
local ptr_lock_frames = 0

local function toggle_pause()
    pcall(function()
        if manager.machine.paused then
            emu.unpause()
        else
            emu.pause()
        end
    end)
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

-- 指针命中（与 mjelctrn 同款）：坐标可能是 layout 像素或 0–1
local PTR = {
    skin = {
        peek = { lx0 = 1400, ly0 = 10, lx1 = 1542, ly1 = 125, px0 = 3, py0 = 1110, px1 = 145, py1 = 1240 },
        pause = { lx0 = 1400, ly0 = 130, lx1 = 1542, ly1 = 245, px0 = 855, py0 = 1110, px1 = 997, py1 = 1240 },
        cuopai = { lx0 = 58, ly0 = 10, lx1 = 200, ly1 = 125, px0 = 145, py0 = 980, px1 = 287, py1 = 1110 },
    },
    dbg_left = 8,
}

function PTR.hit_rect(x, y, x0, y0, x1, y1)
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

function PTR.land(view)
    local name = ""
    pcall(function()
        name = tostring(view and view.name or "")
    end)
    return name:find("Landscape", 1, true) ~= nil
end

function PTR.norm(view, x, y)
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
    if PTR.land(view) then
        return x / 1600, y / 900
    end
    return x / 1000, y / 1640
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
    if PTR.hit_rect(x, y, x0, y0, x1, y1) then
        return true
    end
    local nx, ny = PTR.norm(view, x, y)
    local bx0, by0 = PTR.norm(view, x0, y0)
    local bx1, by1 = PTR.norm(view, x1, y1)
    return PTR.hit_rect(nx, ny, bx0, by0, bx1, by1)
end

local function hit_skin_xy(view, id, key, x, y)
    if hit_item_xy(view, id, x, y) then
        return true
    end
    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local r = PTR.skin[key]
    if not r then
        return false
    end
    local land = PTR.land(view)
    local x0, y0, x1, y1
    if land then
        x0, y0, x1, y1 = r.lx0, r.ly0, r.lx1, r.ly1
    else
        x0, y0, x1, y1 = r.px0, r.py0, r.px1, r.py1
    end
    if x <= 2 and y <= 2 then
        local vw, vh = land and 1600 or 1000, land and 900 or 1640
        return PTR.hit_rect(x, y, x0 / vw, y0 / vh, x1 / vw, y1 / vh)
    end
    return PTR.hit_rect(x, y, x0, y0, x1, y1)
end

local function hit_peek_xy(view, x, y)
    return hit_skin_xy(view, "btn_peek", "peek", x, y)
end

local function hit_pause_xy(view, x, y)
    return hit_skin_xy(view, "btn_pause", "pause", x, y)
end

local function hit_cuopai_xy(view, x, y)
    return hit_skin_xy(view, "btn_cuopai", "cuopai", x, y)
end

local function hit_pool_tile_xy(view, x, y)
    if not peek_open or not tiles_ui or not tiles_ui.hit_mjelctrn_pool then
        return nil
    end
    if not peek_state or not peek_state.pool then
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
    return tiles_ui.hit_mjelctrn_pool(ux, uy, peek_state.pool)
end

local function hit_cpu_tile_xy(view, x, y)
    if not peek_open or not tiles_ui or not tiles_ui.hit_mjelctrn_cpu then
        return nil
    end
    if not peek_state or not peek_state.queue then
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

local function hook_peek_pointer(machine)
    local render = machine.render
    if not render then
        return
    end
    local function bind_view(view)
        if not view then
            return
        end
        local vkey = tostring(view.name or "")
        if vkey == "" then
            vkey = tostring(view)
        end
        if hooked_views[vkey] then
            return
        end
        local has_peek = false
        pcall(function()
            has_peek = view.items and view.items["btn_peek"] ~= nil
        end)
        if not has_peek then
            return
        end
        hooked_views[vkey] = true
        pcall(function()
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
            bind_state("btn_peek", function()
                return peek_open and 1 or 0
            end)
            bind_state("btn_pause", function()
                return (manager.machine.paused and 1) or 0
            end)
            bind_state("btn_cuopai", function()
                return bonus_arm and 1 or 0
            end)
            if view.set_pointer_updated_callback then
                view:set_pointer_updated_callback(function(_, pid, _, x, y, _, pressed)
                    local down = type(pressed) == "number" and (pressed & 1) ~= 0
                    local key = tostring(pid or 0)
                    local was = ptr_held[key]
                    ptr_held[key] = down
                    if not down or was then
                        return
                    end
                    if ptr_lock_frames > 0 then
                        return
                    end
                    if (PTR.dbg_left or 0) > 0 then
                        PTR.dbg_left = PTR.dbg_left - 1
                        local cx0, cy0, cx1, cy1 = item_bounds(view.items and view.items["btn_cuopai"])
                        write_log(
                            string.format(
                                "[ptr] down x=%.4f y=%.4f land=%s cuopai_hit=%s bounds=%s,%s,%s,%s %s\n",
                                x or -1,
                                y or -1,
                                tostring(PTR.land(view)),
                                tostring(hit_cuopai_xy(view, x, y)),
                                tostring(cx0),
                                tostring(cy0),
                                tostring(cx1),
                                tostring(cy1),
                                now()
                            ),
                            "a"
                        )
                    end
                    if hit_pause_xy(view, x, y) then
                        toggle_pause()
                        ptr_lock_frames = 12
                        return
                    end
                    if hit_cuopai_xy(view, x, y) then
                        bonus_click = true
                        ptr_lock_frames = 12
                        return
                    end
                    if hit_peek_xy(view, x, y) then
                        peek_click = true
                        ptr_lock_frames = 12
                        return
                    end
                    local pool_bcd = hit_pool_tile_xy(view, x, y)
                    if pool_bcd then
                        pool_click_bcd = pool_bcd
                        ptr_lock_frames = 12
                        return
                    end
                    local cpu_bcd = hit_cpu_tile_xy(view, x, y)
                    if cpu_bcd then
                        cpu_click_bcd = cpu_bcd
                        ptr_lock_frames = 12
                        return
                    end
                end)
            end
            write_log(
                string.format(
                    "[pointer] bound %s peek=%s cuopai=%s %s\n",
                    vkey,
                    tostring(view.items["btn_peek"] ~= nil),
                    tostring(view.items["btn_cuopai"] ~= nil),
                    now()
                ),
                "a"
            )
        end)
    end
    pcall(function()
        if render.ui_target and render.ui_target.current_view then
            bind_view(render.ui_target.current_view)
        end
        if render.targets then
            for i = 1, 4 do
                local t = render.targets[i]
                if t and not t.hidden and t.current_view then
                    bind_view(t.current_view)
                end
            end
        end
    end)
end

local function toggle_peek(machine)
    peek_open = not peek_open
    if peek_open and tiles_ui then
        tiles_ui.ensure_art(machine)
    end
    machine:popmessage(
        peek_open and ("透视开\n" .. format_live_hands(machine)) or "透视关"
    )
end

local function apply_peek_click(machine)
    if peek_click then
        peek_click = false
        toggle_peek(machine)
    end
end

local function apply_bonus_click(machine)
    -- 已并入 process_hotkeys（与 Ctrl+6 同一路径）；保留空函数防旧调用
end

local function apply_pool_click(machine)
    if not pool_click_bcd then
        return
    end
    local bcd = pool_click_bcd
    pool_click_bcd = nil
    force_draw.select(machine, bcd)
end

local function apply_cpu_click(machine)
    if not cpu_click_bcd then
        return
    end
    local bcd = cpu_click_bcd
    cpu_click_bcd = nil
    discard_lock_select(machine, bcd)
end

local function hud_ui(machine)
    local ui = machine and machine.render and machine.render.ui_container
    if ui and ui.draw_text then
        return ui, "norm"
    end
    local mui = nil
    pcall(function()
        mui = manager.ui
    end)
    if mui and mui.draw_text then
        return mui, "named"
    end
    return nil, nil
end

local function draw_text_hud(machine)
    if not peek_open then
        return
    end
    local ui, mode = hud_ui(machine)
    if not ui then
        return
    end
    local lines = {
        string.format(
            "[lhzb2] step=%d 下摸搓=%s | 自动采#%d",
            step_idx,
            bonus_arm and (bonus_arm_state.holding and "维持" or "预约") or "-",
            bonus_auto.seq or 0
        ),
    }
    for line in string.gmatch(format_live_hands(machine) .. "\n", "(.-)\n") do
        lines[#lines + 1] = line
    end
    local lh = 0.028
    pcall(function()
        if manager.ui and manager.ui.line_height then
            lh = manager.ui.line_height
        end
    end)
    local y0 = 0.02
    local function paint_norm()
        ui:draw_box(0.0, y0 - 0.008, 1.0, y0 + lh * (#lines + 0.35), 0x00000000, 0xC0101020)
        for i, line in ipairs(lines) do
            local col = (i == 1) and 0xffffff50 or 0xffffffff
            if i == 3 then
                col = 0xffffd0a0
            end
            ui:draw_text(0.015, y0 + lh * (i - 1), line, col)
        end
    end
    if mode == "norm" and pcall(paint_norm) then
        return
    end
    local row0 = 0
    for i, line in ipairs(lines) do
        local col = (i == 1) and 0xffffff50 or 0xffffffff
        pcall(function()
            ui:draw_text("left", row0 + i - 1, line, col, 0xc0101020)
        end)
    end
end

local set_baseline, record_step, scan_only, process_hotkeys, ensure_periodic
-- 搓牌相关函数一律挂 B.*（B 已在文件前部声明），避免主 chunk local 超 200

function B.dump_watch(machine, title)
    local keys = B.HUNT_KEYS
    local parts = { title }
    for _, a in ipairs(keys) do
        parts[#parts + 1] = string.format("@%06X=%02X", a, mem.read_u8(machine, a) or 0)
    end
    return table.concat(parts, " ")
end

-- 摸前注入 hunt：比 dump 略宽的监视带（挂 B 上，不占主 chunk local）
B.HUNT_KEYS = {
    0x500061,
    0x500062,
    0x500063,
    0x500064,
    0x500066,
    0x500067,
    0x500068,
    0x500134,
    0x500135,
    0x500136,
    0x5001FC,
    0x5001FD,
    BONUS_1FE_ADDR,
    0x5001FF,
    0x500214,
    0x500215,
    0x500216,
    BONUS_MODE_ADDR,
    0x500218,
    DRAW_FLAG_ADDR,
    HYP_LAST_DRAW,
    BONUS_33F_ADDR,
    0x500340,
    HYP_LAST_DISC,
    WALL_REMAIN_ADDR,
    -- 2026-09-24 自然搓：remain↓ 瞬间独有（暗牌窗）@501444=01 @50173E=00
    0x501444,
    0x50173E,
}

function B.hunt_sig(machine)
    local t = {}
    for _, a in ipairs(B.HUNT_KEYS) do
        t[#t + 1] = string.format("%02X", mem.read_u8(machine, a) or 0)
    end
    return table.concat(t)
end

function B.in_round(pn, remain, v217)
    -- 副露后暗手可 <13；hunt 以剩张+模式为主
    if pn < 1 or pn > 14 then
        return false
    end
    if remain < 30 or remain > 120 then
        return false
    end
    if v217 ~= 0x02 and v217 ~= 0x00 then
        return false
    end
    return true
end

function B.predraw_anomaly(v067, v1fe)
    local mode067 = bonus_auto.predraw_067_mode
    local mode1fe = bonus_auto.predraw_1fe_mode
    if mode067 ~= nil and v067 ~= mode067 then
        return true, string.format("067:%02X≠mode%02X", v067, mode067)
    end
    if mode1fe ~= nil and v1fe ~= mode1fe and v067 == 0x02 then
        return true, string.format("1FE:%02X+067=02", v1fe)
    end
    if v067 == 0x02 then
        return true, "067=02"
    end
    return false, nil
end

function B.auto_snap(machine, why, do_pause)
    bonus_auto.seq = (bonus_auto.seq or 0) + 1
    local seq = bonus_auto.seq
    local snap = snapshot_all(machine)
    local prev = bonus_auto.last_snap
    write_log(
        string.format("=== AUTO-BONUS #%d %s %s ===\n", seq, why, now()),
        "a"
    )
    write_log(B.dump_watch(machine, why) .. "\n", "a")
    write_log(format_live_hands(machine) .. "\n", "a")
    if prev then
        write_log(format_diff(prev, snap) .. "\n", "a")
    end
    for _, r in ipairs(snap.regions or {}) do
        write_bin(
            string.format("smoke_logs/lhzb2_%s_bonus%02d.bin", r.name, seq),
            r.data
        )
    end
    bonus_auto.last_snap = snap
    bonus_auto.cooldown = (do_pause and BONUS_AUTO_PAUSE) and 50 or 12
    local allow_pause = do_pause and BONUS_AUTO_PAUSE and not bonus_force_suppress_auto_pause
    if allow_pause then
        pause_for_hunt(machine)
        pcall(function()
            machine:popmessage(
                string.format("搓牌自动采 #%d %s\nF5 继续", seq, why)
            )
        end)
    elseif why == "enter" or why == "exit" or why == "deepen" then
        pcall(function()
            machine:popmessage(string.format("自动采 #%d %s（未暂停）", seq, why))
        end)
    end
    write_log(
        string.format(
            "  (bin → lhzb2_*_bonus%02d.bin pause=%s)\n",
            seq,
            tostring(allow_pause)
        ),
        "a"
    )
end

function B.save_bak(machine)
    if bonus_arm_state.bak then
        return
    end
    bonus_arm_state.bak = {
        v1fe = mem.read_u8(machine, BONUS_1FE_ADDR) or 0,
        v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0x02,
        v339 = mem.read_u8(machine, DRAW_FLAG_ADDR) or 0x01,
        v067 = mem.read_u8(machine, 0x500067) or 0,
        v063 = mem.read_u8(machine, 0x500063) or 0,
        v33f = mem.read_u8(machine, BONUS_33F_ADDR) or 0,
    }
end

function B.restore(machine)
    local bak = bonus_arm_state.bak
    if bak then
        mem.write_u8(machine, BONUS_1FE_ADDR, bak.v1fe)
        mem.write_u8(machine, BONUS_MODE_ADDR, bak.v217)
        mem.write_u8(machine, DRAW_FLAG_ADDR, bak.v339 or 0x01)
        mem.write_u8(machine, 0x500067, bak.v067)
        mem.write_u8(machine, 0x500063, bak.v063)
        if bak.v33f then
            mem.write_u8(machine, BONUS_33F_ADDR, bak.v33f)
        end
    else
        mem.write_u8(machine, BONUS_MODE_ADDR, 0x02)
        mem.write_u8(machine, DRAW_FLAG_ADDR, 0x01)
    end
    bonus_arm_state.bak = nil
end

function B.poke_enter(machine, why, do_log)
    B.save_bak(machine)
    mem.write_u8(machine, BONUS_1FE_ADDR, 0xFF)
    mem.write_u8(machine, BONUS_MODE_ADDR, 0x00)
    -- 必须先落在环节1：局中摸前 @339 常已是 00，不写回 01 会假 deepen 卡死
    mem.write_u8(machine, DRAW_FLAG_ADDR, 0x01)
    mem.write_u8(machine, 0x500067, 0x25)
    mem.write_u8(machine, 0x500063, 0x01)
    if do_log then
        write_log(
            string.format("=== BONUS_ARM FIRE %s %s ===\n", why or "?", now()),
            "a"
        )
        write_log(B.dump_watch(machine, "fire") .. "\n", "a")
        write_log(format_live_hands(machine) .. "\n", "a")
    end
end

-- 补全 deepen：@339=00 且 @063=78（仅 @339=00 不够）
function B.poke_deepen(machine)
    mem.write_u8(machine, DRAW_FLAG_ADDR, 0x00)
    mem.write_u8(machine, 0x500063, 0x78)
    write_log(string.format("=== BONUS_ARM DEEPEN-MANUAL %s ===\n", now()), "a")
    write_log(B.dump_watch(machine, "deepen-manual") .. "\n", "a")
end

-- 强制搓卡在环节2时：旗标已像「已退出」但摸牌未入手（仍13张）→ 补写入手
function B.commit_draw_to_hand(machine)
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW) or 0
    -- 0x00=1万，合法；仅 FF 表示空槽
    if draw_v == 0xFF then
        return false
    end
    local hand = read_hand_lhzb(machine, PLAYER_HAND_ADDR, 14)
    local n = #hand
    if n >= 14 then
        return false
    end
    -- 已在手里则不再写
    for i = 1, n do
        if hand[i] == draw_v then
            -- 可能是旧牌；仍允许在摸位写入末槽（搓残局常 13 张）
            break
        end
    end
    local slot = PLAYER_HAND_ADDR + n
    mem.write_u8(machine, slot, draw_v)
    if n + 1 < 14 then
        mem.write_u8(machine, slot + 1, 0xFF)
    end
    write_log(
        string.format(
            "=== BONUS_ARM COMMIT-DRAW @%06X=%02X hand=%d→%d %s ===\n",
            slot,
            draw_v,
            n,
            n + 1,
            now()
        ),
        "a"
    )
    return true
end

function B.is_ghost_stuck(machine)
    local v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
    local v063 = mem.read_u8(machine, 0x500063) or 0
    local v339 = mem.read_u8(machine, DRAW_FLAG_ADDR) or 0
    local v33f = mem.read_u8(machine, BONUS_33F_ADDR) or 0
    local v1fe = mem.read_u8(machine, BONUS_1FE_ADDR) or 0
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW) or 0
    local pn = #read_hand_lhzb(machine, PLAYER_HAND_ADDR, 14)
    if v217 == 0x00 then
        return true
    end
    -- 真残局：搓后旗标残留。
    -- 注意：摸前窗口 @063 是帧计数，会扫过 01/5A/78，绝不能单靠 @063 判残局
    -- （否则早按 Ctrl+6 会误脱困并把 @33A 写回手→河/手双三条 + 画面闪）
    if pn <= 13 and draw_v ~= 0xFF then
        if v33f == 0x57 then
            return true
        end
        if v339 == 0x00 and (v063 == 0x5A or v063 == 0x78) then
            return true
        end
        if v1fe == 0xFF and v339 == 0x00 then
            return true
        end
    end
    return false
end

-- 对齐自然 exit：@063=5A @067=3D @217=02 @339=00 @33F=57，@1FE 保留摸牌码
function B.write_exit_bundle(machine)
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW) or 0
    mem.write_u8(machine, BONUS_MODE_ADDR, 0x02)
    mem.write_u8(machine, DRAW_FLAG_ADDR, 0x00)
    mem.write_u8(machine, 0x500063, 0x5A)
    mem.write_u8(machine, 0x500067, 0x3D)
    mem.write_u8(machine, BONUS_33F_ADDR, 0x57)
    local v1fe = mem.read_u8(machine, BONUS_1FE_ADDR) or 0
    if v1fe == 0xFF then
        if draw_v ~= 0xFF then
            mem.write_u8(machine, BONUS_1FE_ADDR, draw_v)
        else
            mem.write_u8(machine, BONUS_1FE_ADDR, 0x00)
        end
    end
end

function B.force_exit_sticky(machine, why)
    -- 仅搓中（@217=00）才把摸牌塞回手；误判脱困时勿改手牌
    local v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
    local committed = false
    if v217 == 0x00 then
        committed = B.commit_draw_to_hand(machine)
    end
    B.write_exit_bundle(machine)
    mem.write_u8(machine, 0x500063, 0x00)
    mem.write_u8(machine, DRAW_FLAG_ADDR, 0x01)
    mem.write_u8(machine, BONUS_33F_ADDR, 0xD0)
    -- 少写几帧，避免整屏闪烁
    bonus_arm_state.exit_hold_left = 24
    bonus_arm_state.guard_exit = false
    bonus_arm_state.await_deepen = false
    bonus_arm_state.auto_finish = false
    bonus_arm_state.pending_convert = false
    bonus_arm_state.mid_post_draw = false
    bonus_arm_state.mid_pre_draw = false
    bonus_arm_state.exchange_mimic = false
    bonus_arm_state.bak_33a = nil
    bonus_arm_state.dark_flag = false
    bonus_arm_state.dark_wait = 0
    bonus_force_suppress_auto_pause = false
    bonus_arm = false
    bonus_arm_state.fired = false
    bonus_arm_state.holding = false
    bonus_arm_state.bak = nil
    bonus_arm_state.toggle_cool = 20
    write_log(
        string.format(
            "=== BONUS_ARM FORCE-EXIT %s commit=%s %s ===\n",
            why or "?",
            tostring(committed),
            now()
        ),
        "a"
    )
    write_log(B.dump_watch(machine, "force-exit") .. "\n", "a")
    write_log(format_live_hands(machine) .. "\n", "a")
end

function B.poke_phase2_nudge(machine)
    local v063 = mem.read_u8(machine, 0x500063) or 0
    if v063 == 0x01 then
        B.poke_deepen(machine)
        return "deepen"
    end
    if v063 == 0x78 then
        mem.write_u8(machine, 0x500063, 0x5A)
        mem.write_u8(machine, BONUS_33F_ADDR, 0x57)
        mem.write_u8(machine, 0x500067, 0x3D)
        write_log(string.format("=== BONUS_ARM PHASE2-NUDGE %s ===\n", now()), "a")
        write_log(B.dump_watch(machine, "phase2-nudge") .. "\n", "a")
        return "nudge"
    end
    B.force_exit_sticky(machine, "manual")
    return "exit"
end

function B.start_hold(machine, why)
    bonus_arm_state.fired = true
    bonus_arm_state.holding = true
    bonus_arm_state.hold_tick = 0
    bonus_arm_state.hold_why = why
    bonus_force_suppress_auto_pause = true
    bonus_arm_state.from_exchange = false
    B.poke_enter(machine, why, true)
    pcall(function()
        machine:popmessage("下一摸搓牌：摸前已立旗\n等开摸由游戏进搓\n再按Ctrl+6取消")
    end)
end

function B.handoff_after_deepen(machine, why)
    bonus_arm = false
    bonus_arm_state.holding = false
    bonus_arm_state.fired = false
    bonus_arm_state.hold_why = nil
    bonus_arm_state.bak = nil
    bonus_arm_state.auto_finish = false
    bonus_force_suppress_auto_pause = true
    bonus_arm_state.guard_exit = true
    bonus_arm_state.await_deepen = false
    write_log(string.format("=== BONUS_ARM HANDOFF %s %s ===\n", why or "?", now()), "a")
    write_log(B.dump_watch(machine, "handoff") .. "\n", "a")
    pcall(function()
        machine:popmessage("已进入搓牌\n请操作环节；卡死再按Ctrl+6退出")
    end)
end

function B.pulse_enter(machine, why)
    B.poke_enter(machine, why, true)
    bonus_auto.prev_217 = 0x00
    bonus_auto.prev_339 = mem.read_u8(machine, DRAW_FLAG_ADDR) or 0
    bonus_auto.prev_1fe = 0xFF
    bonus_arm_state.bak = nil
    bonus_arm = false
    bonus_arm_state.fired = false
    bonus_arm_state.holding = false
    bonus_arm_state.hold_why = nil
    bonus_force_suppress_auto_pause = true
    bonus_arm_state.guard_exit = true
    bonus_arm_state.await_deepen = true
    bonus_arm_state.post_pulse_tick = 0
    bonus_arm_state.from_exchange = (why == "exchange-then-draw")
    bonus_arm_state.auto_finish = false
    bonus_arm_state.auto_finish_tick = 0
    -- 局中勿在 deepen 后自动收搓（会看起来像第一环节被掐成普通摸）
    write_log(
        string.format("=== BONUS_ARM PULSE-DONE %s %s ===\n", why or "?", now()),
        "a"
    )
    pcall(function()
        machine:popmessage("下一摸搓牌：已写入\n等待游戏走搓牌")
    end)
end

function B.tick_guard(machine)
    if bonus_arm_state.toggle_cool and bonus_arm_state.toggle_cool > 0 then
        bonus_arm_state.toggle_cool = bonus_arm_state.toggle_cool - 1
    end
    if bonus_arm_state.exit_hold_left and bonus_arm_state.exit_hold_left > 0 then
        -- 隔帧写，减轻闪屏
        if (bonus_arm_state.exit_hold_left % 4) == 0 then
            B.write_exit_bundle(machine)
            mem.write_u8(machine, 0x500063, 0x00)
            mem.write_u8(machine, DRAW_FLAG_ADDR, 0x01)
            mem.write_u8(machine, BONUS_33F_ADDR, 0xD0)
        end
        bonus_arm_state.exit_hold_left = bonus_arm_state.exit_hold_left - 1
        if bonus_arm_state.exit_hold_left == 0 then
            write_log(string.format("=== BONUS_ARM EXIT-HOLD-END %s ===\n", now()), "a")
            write_log(B.dump_watch(machine, "exit-hold-end") .. "\n", "a")
        end
        return
    end


    if not bonus_arm_state.guard_exit and not bonus_arm_state.await_deepen then
        return
    end
    local v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
    local v339 = mem.read_u8(machine, DRAW_FLAG_ADDR) or 0
    local v063 = mem.read_u8(machine, 0x500063) or 0
    if bonus_arm_state.await_deepen then
        bonus_arm_state.post_pulse_tick = (bonus_arm_state.post_pulse_tick or 0) + 1
        local tick = bonus_arm_state.post_pulse_tick or 0
        if v217 == 0x02 then
            if tick < 90 then
                write_log(
                    string.format("=== BONUS_ARM ABORT-EARLY tick=%d %s ===\n", tick, now()),
                    "a"
                )
            end
            bonus_arm_state.await_deepen = false
        elseif v217 == 0x00 and v339 == 0x00 and v063 == 0x78 then
            write_log(
                string.format("=== BONUS_ARM DEEPEN-NATURAL tick=%d %s ===\n", tick, now()),
                "a"
            )
            write_log(B.dump_watch(machine, "deepen-ok") .. "\n", "a")
            bonus_arm_state.await_deepen = false
        elseif v217 == 0x00 and v339 == 0x00 and v063 == 0x01 and tick == 100 then
            mem.write_u8(machine, 0x500063, 0x78)
            write_log(
                string.format("=== BONUS_ARM FIX-063 tick=%d %s ===\n", tick, now()),
                "a"
            )
            write_log(B.dump_watch(machine, "fix-063") .. "\n", "a")
        elseif tick > 900 then
            bonus_arm_state.await_deepen = false
        end
    end
    if bonus_arm_state.guard_exit then
        if v217 == 0x02 then
            bonus_arm_state.guard_exit = false
            bonus_force_suppress_auto_pause = false
            write_log(string.format("=== BONUS_ARM GUARD-END %s ===\n", now()), "a")
        elseif (bonus_arm_state.post_pulse_tick or 0) > 900 then
            bonus_arm_state.guard_exit = false
            bonus_force_suppress_auto_pause = false
        end
    end
end
function B.stop(machine, why, do_restore)
    local restore = do_restore
    if restore == nil then
        restore = why == "cancel"
            or why == "timeout"
            or why == "too-late"
            or why == "abort"
    end
    if restore then
        B.restore(machine)
    else
        bonus_arm_state.bak = nil
    end
    bonus_arm = false
    bonus_arm_state.fired = false
    bonus_arm_state.holding = false
    bonus_arm_state.hold_why = nil
    bonus_arm_state.await_deepen = false
    bonus_arm_state.pending_convert = false
    bonus_arm_state.convert_delay = 0
    bonus_arm_state.mid_post_draw = false
    bonus_arm_state.mid_pre_draw = false
    bonus_arm_state.exchange_mimic = false
    bonus_arm_state.bak_33a = nil
    bonus_arm_state.dark_flag = false
    bonus_arm_state.dark_wait = 0
    if restore then
        bonus_arm_state.guard_exit = false
        bonus_force_suppress_auto_pause = false
    end
    write_log(
        string.format(
            "=== BONUS_ARM STOP %s restore=%s %s ===\n",
            why or "?",
            tostring(restore),
            now()
        ),
        "a"
    )
    write_log(B.dump_watch(machine, "stop") .. "\n", "a")
end

B.toggle = function(machine)
    if not BONUS_ARM_ENABLE then
        machine:popmessage("强制搓牌未启用")
        return
    end

    local player = read_hand_lhzb(machine, PLAYER_HAND_ADDR, 14)
    local pn = #player
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW) or 0
    local v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
    local v063 = mem.read_u8(machine, 0x500063) or 0
    -- 仅明确搓中/真残局才脱困；勿用「1FE=FF+13张」——正常摸前也会误伤
    local stuck = (v217 == 0x00) or B.is_ghost_stuck(machine)

    -- 搓中/残局：脱困优先，不受 cool 挡住
    if stuck and not bonus_arm then
        if v217 == 0x00 and (v063 == 0x01 or v063 == 0x78) then
            local step = B.poke_phase2_nudge(machine)
            if step ~= "exit" then
                bonus_arm_state.toggle_cool = 15
                machine:popmessage(
                    "环节2助推：" .. tostring(step) .. "\n仍卡再按Ctrl+6强制脱困"
                )
                return
            end
        end
        B.force_exit_sticky(machine, "toggle-stuck")
        machine:popmessage(
            "已强制脱困\n若画面仍乱，请读档/F3"
        )
        return
    end

    if (bonus_arm_state.toggle_cool or 0) > 0 then
        write_log(
            string.format(
                "=== BONUS_ARM TOGGLE-BUSY cool=%d %s ===\n",
                bonus_arm_state.toggle_cool or 0,
                now()
            ),
            "a"
        )
        return
    end
    bonus_arm_state.toggle_cool = 25

    if bonus_arm then
        B.stop(machine, "cancel", true)
        machine:popmessage("下一摸搓牌：已取消")
        return
    end

    if pn >= 14 then
        machine:popmessage(
            "下一摸搓牌：已摸满待打\n请先打出后再预约"
        )
        write_log(
            string.format("=== BONUS_ARM REJECT hand=%d %s ===\n", pn, now()),
            "a"
        )
        return
    end

    -- 开局换牌 / 局中：统一暗牌旗（remain↓ 写 @501444/@50173E，不碰 @217）
    bonus_arm = true
    bonus_arm_state.fired = false
    bonus_arm_state.holding = false
    bonus_arm_state.bak = nil
    bonus_arm_state.hold_why = nil
    bonus_arm_state.pending_convert = false
    bonus_arm_state.convert_delay = 0
    bonus_arm_state.mid_post_draw = false
    bonus_arm_state.mid_pre_draw = false
    bonus_arm_state.exchange_mimic = false
    bonus_arm_state.dark_flag = true
    bonus_arm_state.bak_33a = nil
    bonus_arm_state.dark_wait = 0
    bonus_arm_state.prev_remain = mem.read_u8(machine, WALL_REMAIN_ADDR)
    bonus_arm_state.prev_player_n = pn
    bonus_arm_state.prev_river_n = select(2, cpu_river_last(machine)) or 0
    bonus_arm_state.river_grow_at = nil
    bonus_arm_state.river_stable = 0
    bonus_arm_state.prev_33a = draw_v
    bonus_arm_state.prev_067 = mem.read_u8(machine, 0x500067) or 0
    last_draw_slot = draw_v
    local why_arm = (draw_v == 0xFF) and "dark-flag-exchange" or "dark-flag-mid"
    write_log(string.format("=== BONUS_ARM ARM %s %s ===\n", why_arm, now()), "a")
    if draw_v == 0xFF then
        machine:popmessage(
            "下一摸搓牌：换牌中已预约\n开摸 remain↓ 写暗牌旗\n再点取消"
        )
    else
        machine:popmessage(
            "下一摸搓牌：已预约\nremain↓ 写暗牌旗\n再点取消"
        )
    end
end

B.tick_arm = function(machine)
    last_draw_slot = mem.read_u8(machine, HYP_LAST_DRAW)
    B.tick_guard(machine)
    if not BONUS_ARM_ENABLE or not bonus_arm then
        return
    end
    if machine.paused then
        return
    end

    -- 暗牌旗快路径：每帧只读 remain/@217/@33A，不扫手牌/河（预约搓时防卡顿）
    if bonus_arm_state.dark_flag then
        local remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
        local v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
        local draw_v = mem.read_u8(machine, HYP_LAST_DRAW) or 0
        local prev_r = bonus_arm_state.prev_remain
        local remain_drop = prev_r ~= nil and remain < prev_r
        local left_exchange = (bonus_arm_state.prev_33a == 0xFF) and draw_v ~= 0xFF

        if not bonus_arm_state.fired then
            if v217 == 0x00 then
                B.stop(machine, "natural", false)
                bonus_arm_state.prev_remain = remain
                bonus_arm_state.prev_33a = draw_v
                return
            end
            if remain_drop then
                mem.write_u8(machine, 0x501444, 0x01)
                mem.write_u8(machine, 0x50173E, 0x00)
                bonus_arm_state.fired = true
                bonus_arm_state.dark_wait = 120
                write_log(
                    string.format(
                        "=== BONUS_ARM DARK-FLAG remain-drop left_ex=%s %s ===\n",
                        tostring(left_exchange),
                        now()
                    ),
                    "a"
                )
                pcall(function()
                    machine:popmessage("已写暗牌旗\n等待游戏进搓")
                end)
            end
            bonus_arm_state.prev_remain = remain
            bonus_arm_state.prev_33a = draw_v
            return
        end

        -- fired：等 @217→00；隔帧重写旗，避免每帧双写
        if v217 == 0x00 then
            bonus_arm = false
            bonus_arm_state.dark_flag = false
            bonus_arm_state.dark_wait = 0
            bonus_force_suppress_auto_pause = true
            bonus_arm_state.guard_exit = true
            bonus_arm_state.await_deepen = true
            bonus_arm_state.post_pulse_tick = 0
            write_log(string.format("=== BONUS_ARM DARK-FLAG ENTER-OK %s ===\n", now()), "a")
            pcall(function()
                machine:popmessage("已进搓\n卡死再点搓牌/Ctrl+6脱困")
            end)
        else
            local w = bonus_arm_state.dark_wait or 0
            if w > 0 then
                bonus_arm_state.dark_wait = w - 1
                if (w % 8) == 0 then
                    mem.write_u8(machine, 0x501444, 0x01)
                    mem.write_u8(machine, 0x50173E, 0x00)
                end
            else
                mem.write_u8(machine, 0x501444, 0x00)
                mem.write_u8(machine, 0x50173E, 0x01)
                B.stop(machine, "dark-flag-timeout", false)
                pcall(function()
                    machine:popmessage("暗牌旗：未进搓已还原")
                end)
            end
        end
        bonus_arm_state.prev_remain = remain
        bonus_arm_state.prev_33a = draw_v
        return
    end

    local remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
    local player = read_hand_lhzb(machine, PLAYER_HAND_ADDR, 14)
    local pn = #player
    local v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
    local v339 = mem.read_u8(machine, DRAW_FLAG_ADDR) or 0
    local v063 = mem.read_u8(machine, 0x500063) or 0
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW) or 0

    if bonus_arm_state.holding then
        local deepened = v217 == 0x00 and v339 == 0x00 and v063 == 0x78
        if deepened then
            B.handoff_after_deepen(machine, bonus_arm_state.hold_why or "hold-deepen")
            bonus_arm_state.prev_remain = remain
            bonus_arm_state.prev_33a = draw_v
            return
        end
        bonus_arm_state.hold_tick = (bonus_arm_state.hold_tick or 0) + 1
        if bonus_arm_state.hold_tick > 480 then
            B.stop(machine, "timeout", true)
            pcall(function()
                machine:popmessage("下一摸搓牌：超时已还原")
            end)
            bonus_arm_state.prev_remain = remain
            bonus_arm_state.prev_33a = draw_v
            return
        end
        if (bonus_arm_state.hold_tick % 3) == 0 then
            B.poke_enter(machine, "hold", false)
        end
        bonus_arm_state.prev_remain = remain
        bonus_arm_state.prev_33a = draw_v
        return
    end

    if pn >= 14 then
        bonus_arm_state.prev_remain = remain
        bonus_arm_state.prev_33a = draw_v
        return
    end
    if v217 == 0x00 and not bonus_arm_state.fired then
        B.stop(machine, "natural", false)
        bonus_arm_state.prev_remain = remain
        bonus_arm_state.prev_33a = draw_v
        return
    end

    bonus_arm_state.prev_remain = remain
    bonus_arm_state.prev_33a = draw_v
end

B.tick_auto = function(machine)
    if not BONUS_AUTO_HUNT then
        return
    end
    if machine.paused then
        return
    end
    -- 强制维持旗标期间：只同步 prev，禁止任何 AUTO-BONUS 边沿（防刷盘卡死）
    if bonus_arm_state.holding or bonus_force_suppress_auto_pause then
        bonus_auto.prev_217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
        bonus_auto.prev_339 = mem.read_u8(machine, DRAW_FLAG_ADDR) or 0
        bonus_auto.prev_1fe = mem.read_u8(machine, BONUS_1FE_ADDR) or 0
        bonus_auto.prev_33f = mem.read_u8(machine, BONUS_33F_ADDR) or 0
        bonus_auto.prev_067 = mem.read_u8(machine, 0x500067) or 0
        bonus_auto.prev_135 = mem.read_u8(machine, 0x500135) or 0
        bonus_auto.prev_remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
        bonus_auto.prev_33a = mem.read_u8(machine, HYP_LAST_DRAW) or 0
        local _, riv_n = cpu_river_last(machine)
        bonus_auto.prev_river_n = riv_n or 0
        local player = read_hand_lhzb(machine, PLAYER_HAND_ADDR, 14)
        if #player >= 4 then
            bonus_auto.prev_player_n = #player
        end
        return
    end
    if bonus_auto.cooldown and bonus_auto.cooldown > 0 then
        bonus_auto.cooldown = bonus_auto.cooldown - 1
        -- 冷却中仍更新 prev，避免边沿堆积
    end

    local v217 = mem.read_u8(machine, BONUS_MODE_ADDR) or 0
    local v339 = mem.read_u8(machine, DRAW_FLAG_ADDR) or 0
    local v1fe = mem.read_u8(machine, BONUS_1FE_ADDR) or 0
    local v33f = mem.read_u8(machine, BONUS_33F_ADDR) or 0
    local v067 = mem.read_u8(machine, 0x500067) or 0
    local remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW) or 0
    local _, riv_n = cpu_river_last(machine)
    riv_n = riv_n or 0
    local player = read_hand_lhzb(machine, PLAYER_HAND_ADDR, 14)
    local pn = #player
    local round_ok = B.in_round(pn, remain, v217)
    if round_ok and v217 == 0x02 then
        bonus_auto.in_round = true
    end
    if remain > 120 or pn < 4 then
        bonus_auto.in_round = false
        bonus_auto.seen_enter = false
        bonus_auto.predraw_067_mode = nil
        bonus_auto.predraw_1fe_mode = nil
    end

    if bonus_auto.prev_217 == nil then
        bonus_auto.prev_217 = v217
        bonus_auto.prev_339 = v339
        bonus_auto.prev_1fe = v1fe
        bonus_auto.prev_33f = v33f
        bonus_auto.prev_067 = v067
        bonus_auto.prev_remain = remain
        bonus_auto.prev_33a = draw_v
        bonus_auto.prev_player_n = pn
        bonus_auto.prev_river_n = riv_n
        bonus_auto.player_n_stable = 1
        -- 读档已在搓中：记下但不视为本段 enter，避免立刻假 exit
        if v217 == 0x00 then
            bonus_auto.seen_enter = false
        end
        return
    end

    local cooling = bonus_auto.cooldown and bonus_auto.cooldown > 0
    local why = nil
    local pause = true
    local v135 = mem.read_u8(machine, 0x500135) or 0
    local prev_135 = bonus_auto.prev_135
    if prev_135 == nil then
        bonus_auto.prev_135 = v135
        prev_135 = v135
    end

    -- 严格 02↔00；进搓/加深/搓完不受 cooldown 阻挡
    if bonus_auto.in_round and bonus_auto.prev_217 == 0x02 and v217 == 0x00 then
        why = "enter"
        bonus_auto.seen_enter = true
    elseif
        bonus_auto.in_round
        and v217 == 0x00
        and bonus_auto.prev_339 ~= 0
        and v339 == 0
    then
        why = "deepen"
    elseif bonus_auto.in_round and bonus_auto.prev_217 == 0x00 and v217 == 0x02 then
        if bonus_auto.seen_enter then
            why = "exit"
            bonus_auto.seen_enter = false
        end
        -- 未见 enter 的 00→02：读档收尾，静默吞掉
    end

    -- 仍为 02 时预约边沿：优先 @1FE→FF；@135 0→非0；@067 仅从摸前众数(常3F)跳到 02
    if
        not why
        and not cooling
        and bonus_auto.in_round
        and v217 == 0x02
        and bonus_auto.prev_217 == 0x02
    then
        local tip = nil
        local do_pause_arm = true
        if v1fe == 0xFF and bonus_auto.prev_1fe ~= 0xFF then
            tip = string.format("1FE=%02X→FF", bonus_auto.prev_1fe or 0)
        elseif
            v067 == 0x02
            and bonus_auto.prev_067 ~= 0x02
            and bonus_auto.predraw_067_mode ~= nil
            and bonus_auto.prev_067 == bonus_auto.predraw_067_mode
        then
            tip = string.format("067=%02X→02(from mode)", bonus_auto.prev_067)
        elseif prev_135 == 0 and v135 ~= 0 then
            -- 多见瞬时 2C，与进搓无稳定对应 → 只记不停
            tip = string.format("135=00→%02X", v135)
            do_pause_arm = false
        end
        if tip then
            why = "arm-edge/" .. tip
            pause = do_pause_arm
        end
    end

    -- remain↓1 且仍 02：摸瞬间（只记；若同时 armish 已由上条暂停）
    if
        not why
        and not cooling
        and bonus_auto.in_round
        and v217 == 0x02
        and bonus_auto.prev_remain
        and remain == bonus_auto.prev_remain - 1
    then
        why = "remain-drop"
        pause = false
    end

    -- 电脑河 +1 稳定 → 摸前（默认只记；异常才暂停）
    if riv_n == (bonus_auto.prev_river_n or 0) + 1 then
        bonus_auto.river_grow_at = riv_n
        bonus_auto.river_stable = 1
    elseif bonus_auto.river_grow_at and riv_n == bonus_auto.river_grow_at then
        bonus_auto.river_stable = (bonus_auto.river_stable or 0) + 1
    else
        if not bonus_auto.river_grow_at or riv_n ~= bonus_auto.river_grow_at then
            bonus_auto.river_grow_at = nil
            bonus_auto.river_stable = 0
        end
    end
    if
        not why
        and not cooling
        and bonus_auto.in_round
        and bonus_auto.river_grow_at
        and (bonus_auto.river_stable or 0) >= 8
        and v217 == 0x02
    then
        local anom, tip = B.predraw_anomaly(v067, v1fe)
        if anom then
            why = "predraw-ARM?" .. (tip and ("/" .. tip) or "")
            pause = true
        else
            why = "cpu-done-predraw"
            pause = false
            -- 学习常态
            if bonus_auto.predraw_067_mode == nil then
                bonus_auto.predraw_067_mode = v067
            end
            if bonus_auto.predraw_1fe_mode == nil then
                bonus_auto.predraw_1fe_mode = v1fe
            elseif v1fe == bonus_auto.predraw_1fe_mode then
                -- keep
            elseif bonus_auto.predraw_067_mode == v067 then
                -- 同 @067 下允许 1FE 漂移，不立刻当异常；用众数：第二次相同才锁
                bonus_auto._1fe_cand = bonus_auto._1fe_cand or v1fe
                if bonus_auto._1fe_cand == v1fe then
                    bonus_auto.predraw_1fe_mode = v1fe
                end
            end
        end
        bonus_auto.river_grow_at = nil
        bonus_auto.river_stable = 0
        -- 打开摸前连续采：直到 remain↓ / enter
        bonus_auto.predraw_stream = true
        bonus_auto.predraw_tick = 0
        bonus_auto.predraw_snaps = 0
        bonus_auto.predraw_sig = B.hunt_sig(machine)
    end

    -- 摸前流：监视带有变化就采（限每窗 12 枪，不停机）
    if
        not why
        and bonus_auto.predraw_stream
        and bonus_auto.in_round
        and v217 == 0x02
    then
        bonus_auto.predraw_tick = (bonus_auto.predraw_tick or 0) + 1
        local sig = B.hunt_sig(machine)
        if sig ~= bonus_auto.predraw_sig then
            bonus_auto.predraw_sig = sig
            local n = bonus_auto.predraw_snaps or 0
            if n < 12 then
                why = string.format("predraw-delta/t%d", bonus_auto.predraw_tick)
                pause = false
                bonus_auto.predraw_snaps = n + 1
            else
                write_log(
                    string.format(
                        "=== predraw-delta-light t%d %s ===\n%s\n",
                        bonus_auto.predraw_tick,
                        now(),
                        B.dump_watch(machine, "predraw-light")
                    ),
                    "a"
                )
            end
        elseif (bonus_auto.predraw_tick or 0) > 240 then
            bonus_auto.predraw_stream = false
            write_log(
                string.format("=== predraw-stream timeout %s ===\n", now()),
                "a"
            )
        end
    end

    if why == "remain-drop" or why == "enter" or why == "exit" or why == "deepen" then
        if bonus_auto.predraw_stream then
            write_log(
                string.format(
                    "=== predraw-stream end by %s snaps=%d %s ===\n",
                    why,
                    bonus_auto.predraw_snaps or 0,
                    now()
                ),
                "a"
            )
        end
        bonus_auto.predraw_stream = false
    end

    -- 玩家打出：张数稳定后再认，防抖
    if pn == bonus_auto.prev_player_n then
        bonus_auto.player_n_stable = (bonus_auto.player_n_stable or 0) + 1
    else
        local dropped = bonus_auto.prev_player_n and pn == bonus_auto.prev_player_n - 1
        local from_await = bonus_auto.prev_player_n == 14
            or bonus_auto.prev_player_n == 11
            or bonus_auto.prev_player_n == 8
        if
            not why
            and not cooling
            and bonus_auto.in_round
            and dropped
            and from_await
            and (bonus_auto.player_n_stable or 0) >= 4
            and v217 == 0x02
        then
            why = "player-disc"
            pause = false
        end
        bonus_auto.player_n_stable = 1
    end

    if why then
        -- 摸前/打出/remain 在冷却中跳过；进搓与 arm-edge 仍记
        local is_edge = why == "enter"
            or why == "deepen"
            or why == "exit"
            or (type(why) == "string" and why:find("arm-edge", 1, true) ~= nil)
        if is_edge or not cooling then
            local ok, err = pcall(B.auto_snap, machine, why, pause)
            if not ok then
                write_log(string.format("ERROR auto-bonus %s %s\n", why, tostring(err)), "a")
            end
        end
    end

    bonus_auto.prev_217 = v217
    bonus_auto.prev_339 = v339
    bonus_auto.prev_1fe = v1fe
    bonus_auto.prev_33f = v33f
    bonus_auto.prev_067 = v067
    bonus_auto.prev_135 = v135
    bonus_auto.prev_remain = remain
    bonus_auto.prev_33a = draw_v
    if pn >= 4 then
        bonus_auto.prev_player_n = pn
    end
    bonus_auto.prev_river_n = riv_n
end

local function hand_to_tile_list(bytes)
    local list = {}
    for i = 1, #bytes do
        local bcd = lhzb_to_bcd(bytes[i])
        if bcd ~= 0 then
            list[#list + 1] = {
                raw = bcd,
                enc = "bcd",
                name = tile_name_lhzb(bytes[i]),
                empty = false,
            }
        end
    end
    return list
end

local function build_peek_state(machine)
    local cpu, cpu_addr, held = read_cpu_hand_live(machine)
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW)
    local disc_v = select(1, cpu_river_last(machine))
    local remain = mem.read_u8(machine, WALL_REMAIN_ADDR) or 0
    local pool, pool_n = read_pool_tiles(machine)
    local force_nm = tile_name_lhzb(force_draw.target_lhzb())
    local cpu_hand = hand_to_tile_list(cpu)
    if discard_lock.armed and discard_lock.lhzb then
        local lock_bcd = lhzb_to_bcd(discard_lock.lhzb)
        for _, t in ipairs(cpu_hand) do
            if t.raw == lock_bcd then
                t.force_hi = true
            end
        end
    end
    local meld_n = infer_meld_n(#cpu)
    local meld_blocks = {}
    if MELD_CPU_ADDR then
        meld_blocks = read_meld_blocks_at(machine, MELD_CPU_ADDR, 4)
        meld_n = math.max(meld_n, #meld_blocks)
    end
    local src = OPEN_HAND_ADDR and "open" or "cpu"
    local cpu_label = string.format(
        "电脑手@%04X%s%s·点选要打出的牌",
        cpu_addr or CPU_HAND_ADDR,
        held and "·hold" or "",
        OPEN_HAND_ADDR and "·明锚" or ""
    )
    local note2 = ""
    if #meld_blocks > 0 then
        local ptr = mem.read_u8(machine, MELD_PTR_ADDR + 1)
        note2 = string.format(
            "副露%d标 %s | ptr@%04X=%02X | 暗手期望%d",
            #meld_blocks,
            format_meld_blocks(meld_blocks),
            MELD_PTR_ADDR,
            ptr or 0,
            expected_closed_n(#meld_blocks, false)
        )
    elseif meld_watch.bag_hint and meld_watch.bag_hint.from_hand then
        local h = meld_watch.bag_hint
        local parts = {}
        for _, v in ipairs(h.from_hand or {}) do
            parts[#parts + 1] = tile_name_lhzb(v)
        end
        if h.claim then
            parts[#parts + 1] = tile_name_lhzb(h.claim) .. "(荣)"
        end
        if #parts > 0 then
            note2 = string.format(
                "副露≈%d bag:%s",
                meld_n > 0 and meld_n or 1,
                table.concat(parts, " ")
            )
        end
    elseif meld_n > 0 then
        note2 = string.format("副露≈%d 期望暗手%d", meld_n, expected_closed_n(meld_n, false))
    elseif #cpu == 0 then
        note2 = "发牌中或槽不稳"
    elseif force_draw.armed then
        note2 = "控摸：整池只留目标；摸走自动恢复"
    elseif discard_lock.armed and discard_lock.lhzb then
        note2 = string.format(
            "锁→%s：出牌写入时劫持（同电子基盘）",
            tile_name_lhzb(discard_lock.lhzb)
        )
    end
    local await = is_awaiting_discard_n(#cpu, math.max(meld_n, #meld_blocks))
    return {
        title = "龙虎争霸2 透视",
        line1 = string.format(
            "摸=%s 弃=%s 剩=%d 暗%d≈副露%d%s%s",
            tile_valid_lhzb(draw_v) and tile_name_lhzb(draw_v) or "-",
            tile_valid_lhzb(disc_v) and tile_name_lhzb(disc_v) or "-",
            remain,
            #cpu,
            meld_n,
            force_draw.armed and (" ·控摸" .. force_nm) or "",
            discard_lock.armed and discard_lock.lhzb and (" ·锁" .. tile_name_lhzb(discard_lock.lhzb))
                or ""
        ),
        queue_label = cpu_label,
        queue = cpu_hand,
        queue_hi_first = false,
        queue_dim_after = 99,
        pool_label = force_draw.armed
                and string.format("牌池 · 控摸中→%s · 点同种关", force_nm)
            or string.format("牌池 · 剩 %d · 点选控摸", pool_n),
        pool = pool,
        pool_rows = 2,
        note1 = string.format(
            "源=%s 剩@%04X 池@%04X | 点电脑手锁定%s",
            src,
            WALL_REMAIN_ADDR,
            WALL_POOL_ADDR,
            await and " ·待打" or ""
        ),
        note2 = note2,
        cpu_label = cpu_label,
        cpu = cpu_hand,
        seq_a = {},
        seq_b = {},
        name_a = " ",
        name_b = " ",
        marked = true,
    }
end

local function draw_peek_panel(machine)
    if not peek_open then
        return
    end
    -- periodic 远快于帧率：同帧只画一次，避免牌池面板反复重建卡死
    local paused = false
    pcall(function()
        paused = machine.paused and true or false
    end)
    local frame_n = nil
    pcall(function()
        local scr = machine.screens and machine.screens[":screen"]
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

    peek_state = build_peek_state(machine)
    if tiles_ui then
        tiles_ui.ensure_art(machine)
        -- 与电子基盘相同：牌池 HUD 画在 ui_container（全窗 0–1），
        -- 与 mjelctrn_geom / view_to_ui01 / hit_mjelctrn_pool 同空间。
        -- 勿用 :screen/game_container —— 否则 layout 左右 inset 会再缩一次，点击错位。
        local ui = machine.render and machine.render.ui_container
        if ui and tiles_ui.draw_mjelctrn_panel then
            if pcall(tiles_ui.draw_mjelctrn_panel, ui, peek_state) then
                return
            end
        end
        if ui and tiles_ui.draw_panel then
            if pcall(tiles_ui.draw_panel, ui, peek_state) then
                return
            end
        end
    end
    draw_text_hud(machine)
end

set_baseline = function(machine)
    snap_base = snapshot_all(machine)
    step_idx = 0
    last_hits = scan_hand_candidates(snap_base)
    local walls = scan_wall_candidates(snap_base)
    write_log(string.format("=== BASELINE %s rom=%s ===\n", now(), machine.system.name), "w")
    write_log(format_hits(last_hits, 20) .. "\n", "a")
    write_log(format_wall_hits(walls, 15) .. "\n", "a")
    write_log(format_live_hands(machine) .. "\n", "a")
    pcall(dump_open_hand_hunt, machine, "baseline", snap_base)
    pcall(dump_meld_hunt, machine, "baseline", snap_base)
    pcall(dump_cpu_discard_hunt, machine, "baseline", snap_base, nil)
    for _, r in ipairs(snap_base.regions) do
        write_bin(string.format("smoke_logs/lhzb2_%s_base.bin", r.name), r.data)
    end
    pause_for_hunt(machine)
    local tip = ""
    if OPEN_HAND_ADDR then
        tip = tip .. string.format("\n明锚@%04X", OPEN_HAND_ADDR)
    end
    if MELD_CPU_ADDR then
        tip = tip .. string.format("\n副露@%04X", MELD_CPU_ADDR)
    end
    if tip == "" and #walls > 0 then
        tip = string.format("\n山候选#%d @%06X len=%d", 1, walls[1].addr, walls[1].len)
    end
    machine:popmessage("基准 OK（含 open/meld/discard hunt）\n" .. format_live_hands(machine) .. tip)
end

record_step = function(machine)
    if not snap_base then
        machine:popmessage("请先 右Ctrl+5 设基准")
        return
    end
    step_idx = step_idx + 1
    local snap_old = snap_base
    local snap = snapshot_all(machine)
    last_hits = scan_hand_candidates(snap)
    local walls = scan_wall_candidates(snap)
    local draw_v = mem.read_u8(machine, HYP_LAST_DRAW)
    local consume = hunt_wall_consume(snap_old, snap, draw_v)
    if #consume > 0 and not WALL_BASE_ADDR then
        WALL_BASE_ADDR = consume[1].addr
    end
    local remain_old, remain_new = nil, mem.read_u8(machine, WALL_REMAIN_ADDR)
    for _, r in ipairs(snap_old.regions or {}) do
        if r.name == "68k_nvram" then
            remain_old = r.data:byte((WALL_REMAIN_ADDR - r.start) + 1)
            break
        end
    end
    local pool_old = pool_count_in_snap(snap_old, draw_v)
    local pool_new = pool_count_in_snap(snap, draw_v)
    write_log(string.format("=== STEP #%d %s ===\n", step_idx, now()), "a")
    write_log(format_diff(snap_old, snap) .. "\n", "a")
    write_log(format_hits(last_hits, 20) .. "\n", "a")
    write_log(format_wall_hits(walls, 12) .. "\n", "a")
    write_log(format_wall_consume(consume) .. "\n", "a")
    write_log(
        string.format(
            "remain @%04X %s->%s  pool[%s] %s->%s\n",
            WALL_REMAIN_ADDR,
            tostring(remain_old),
            tostring(remain_new),
            tile_valid_lhzb(draw_v) and tile_name_lhzb(draw_v) or "?",
            tostring(pool_old),
            tostring(pool_new)
        ),
        "a"
    )
    write_log(format_live_hands(machine) .. "\n", "a")
    pcall(dump_open_hand_diff, snap_old, snap, string.format("step-%d", step_idx))
    pcall(dump_open_hand_hunt, machine, string.format("step-%d", step_idx), snap)
    pcall(dump_meld_diff, snap_old, snap, string.format("step-%d", step_idx), machine)
    pcall(dump_meld_hunt, machine, string.format("step-%d", step_idx), snap)
    pcall(dump_cpu_discard_hunt, machine, string.format("step-%d", step_idx), snap, snap_old)
    for _, r in ipairs(snap.regions) do
        write_bin(string.format("smoke_logs/lhzb2_%s_step%02d.bin", r.name, step_idx), r.data)
    end
    snap_base = snap
    pause_for_hunt(machine)
    local extra = {}
    if remain_old and remain_new and remain_new == remain_old - 1 then
        extra[#extra + 1] = string.format("剩%d→%d", remain_old, remain_new)
    end
    if pool_old and pool_new and pool_new == pool_old - 1 then
        extra[#extra + 1] = string.format(
            "池%s %d→%d",
            tile_name_lhzb(draw_v),
            pool_old,
            pool_new
        )
    end
    if #consume > 0 then
        extra[#extra + 1] = string.format("山头?@%06X", consume[1].addr)
    end
    if OPEN_HAND_ADDR then
        extra[#extra + 1] = string.format("明@%04X", OPEN_HAND_ADDR)
    end
    if MELD_CPU_ADDR then
        extra[#extra + 1] = string.format("副露@%04X", MELD_CPU_ADDR)
    end
    local cpu_now = select(1, read_cpu_hand_live(machine))
    if is_awaiting_discard_n(#cpu_now, infer_meld_n(#cpu_now)) then
        extra[#extra + 1] = "待打窗"
    end
    local head = #extra > 0 and ("STEP #" .. step_idx .. " " .. table.concat(extra, " "))
        or ("STEP #" .. step_idx .. " (无山头消耗匹配)")
    machine:popmessage(head .. "\n" .. format_live_hands(machine))
end

scan_only = function(machine)
    local snap = snapshot_all(machine)
    last_hits = scan_hand_candidates(snap)
    local walls = scan_wall_candidates(snap)
    write_log(string.format("=== SCAN %s rom=%s ===\n", now(), machine.system.name), "a")
    write_log(format_hits(last_hits, 30) .. "\n", "a")
    write_log(format_wall_hits(walls, 20) .. "\n", "a")
    write_log(format_live_hands(machine) .. "\n", "a")
    pcall(dump_open_hand_hunt, machine, "scan", snap)
    pcall(dump_meld_hunt, machine, "scan", snap)
    pcall(dump_cpu_discard_hunt, machine, "scan", snap, nil)
    pause_for_hunt(machine)
    local tip = (#walls > 0) and string.format("山候选 @%06X len=%d\n", walls[1].addr, walls[1].len) or ""
    machine:popmessage("全扫\n" .. tip .. format_live_hands(machine))
end

process_hotkeys = function(machine)
    bind_keys(machine)
    local from_btn = bonus_click
    if from_btn then
        bonus_click = false
    end
    local bonus_edge = from_btn
        or (seq6 and edge(8, seq6))
        or (seq6l and edge(10, seq6l))
    -- 搓牌钮优先：勿被同帧其它热键 elseif 吃掉
    if bonus_edge then
        write_log(
            string.format(
                "=== %s arm edge %s bound=%s toggle=%s ===\n",
                from_btn and "BTN" or "KEY",
                now(),
                tostring(keys_bound_ok),
                type(B.toggle)
            ),
            "a"
        )
        local ok, err = pcall(B.toggle, machine)
        if not ok then
            write_log(string.format("ERROR bonus_arm %s\n", tostring(err)), "a")
            machine:popmessage("预约搓牌错误，见 log")
        end
    elseif seq9 and edge(5, seq9) then
        toggle_peek(machine)
    elseif seq0 and edge(6, seq0) then
        toggle_peek(machine)
    elseif seq7 and edge(12, seq7) then
        local ok, err = pcall(force_draw.cycle, machine)
        if not ok then
            write_log(string.format("ERROR force_cycle %s\n", tostring(err)), "a")
            machine:popmessage("控摸换种错误，见 log")
        end
    elseif seq8 and edge(11, seq8) then
        local ok, err = pcall(force_draw.toggle, machine)
        if not ok then
            write_log(string.format("ERROR force_toggle %s\n", tostring(err)), "a")
            machine:popmessage("控摸开关错误，见 log")
        end
    elseif edge(7, seq5) then
        local ok, err = pcall(set_baseline, machine)
        if not ok then
            write_log(string.format("ERROR baseline %s\n", tostring(err)), "a")
            machine:popmessage("baseline 错误，见 log")
        end
    elseif edge(2, seq2) then
        local ok, err = pcall(record_step, machine)
        if not ok then
            write_log(string.format("ERROR step %s\n", tostring(err)), "a")
            machine:popmessage("step 错误，见 log")
        end
    elseif edge(3, seq3) then
        local ok, err = pcall(scan_only, machine)
        if not ok then
            write_log(string.format("ERROR scan %s\n", tostring(err)), "a")
            machine:popmessage("scan 错误，见 log")
        end
    end
end

ensure_periodic = function()
    if periodic_on then
        return
    end
    periodic_on = true
    pcall(function()
        emu.register_periodic(function()
            local m = manager and manager.machine
            if not m or not m.system or not LHZB2_FAMILY[m.system.name] then
                return
            end
            -- 暂停时 frame_done / 灯控回调不跑：这里补读键 + 画 HUD
            pcall(process_hotkeys, m)
            pcall(B.tick_arm, m)
            pcall(B.tick_auto, m)
            pcall(force_draw.run_tick, m)
            pcall(discard_lock_run_tick, m)
            pcall(tick_meld_watch, m)
            pcall(tick_discard_auto, m)
            pcall(hook_peek_pointer, m)
            pcall(apply_peek_click, m)
            pcall(apply_bonus_click, m)
            pcall(apply_pool_click, m)
            pcall(apply_cpu_click, m)
            if ptr_lock_frames > 0 then
                ptr_lock_frames = ptr_lock_frames - 1
            end
            if peek_open then
                pcall(draw_peek_panel, m)
            end
            if not boot_toast_done then
                boot_toast_done = true
                write_log(
                    string.format(
                        "\n=== LHZB2 session %s ===\n"
                            .. "  强制搓：暗牌旗 @501444/@50173E（点搓牌钮或 Ctrl+6）\n"
                            .. "  自动采 BONUS_AUTO_HUNT=%s\n",
                        now(),
                        tostring(BONUS_AUTO_HUNT)
                    ),
                    "a"
                )
                pcall(function()
                    m:popmessage(
                        "强制搓：点「搓牌」或 Ctrl+6\n预约下一摸暗牌旗\n搓中再按脱困"
                    )
                end)
            end
        end)
    end)
end

-- 插件加载时就挂 periodic，不依赖首帧灯控回调
ensure_periodic()

return function(machine)
    if not machine or not is_family(machine.system.name) then
        return
    end
    ensure_periodic()
    hook_peek_pointer(machine)
    process_hotkeys(machine)
    apply_peek_click(machine)
    apply_bonus_click(machine)
    draw_peek_panel(machine)
end
