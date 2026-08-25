-- rbmk 牌山定位 v2：BCD 编码 + 热区 dump + 正确 MCU idata。
--   Ctrl+0  把当前 ● 行标成本局玩家（新一局自动清；杠后若没自动对调可再按一次）
--   Ctrl+1  发完 13 张 → 快照 A（覆盖 rbmk_wall.log）
--   Ctrl+2  摸一张     → 快照 B 并对比
--   Ctrl+9 / F9 / 点右上「透视」按钮：开/关透视面板
-- 报告：smoke_logs/rbmk_wall.log ；work2 二进制：rbmk_work2_A.bin / _B.bin
--
-- 已确认：
--   岭上从队头顺序摸，不是牌尾。玩家杠会摸走本该电脑摸的下一张，两行对调。
--   本游戏没有字牌（东、南、西、北、中、发、白从未出现），只有万/筒/条
--   各 36 张，外加赤五万/筒/条（85/95/A5，替换普通五，不是额外牌）。
--   本游戏不能吃。每局玩家、电脑各最多打出约 13 张，外加碰/杠补张，所以
--   预览每行 13 张（各方最多摸打约 13 张）；竖屏按游戏区宽度缩放。
-- 待查（暂不改 HUD）：
--   玩家听牌后 0x504150 整段会换成另一套。例：听四五筒时，听前玩家行是
--   七筒 二条 五筒 …，前两张摸对了，第三张本该五筒时牌山已重排（剩余 67→58），
--   旧玩家行后半和旧电脑行后半对调，五筒等几张从可见队列消失。可能是听牌时
--   程序重洗/换山/换成死牌区，或 HUD 读到了另一段缓冲。
--   再逮到一次（听七筒，手A/手B 未对调）：听牌待机 13 张。换山前剩余 65，
--     下摸 A=六条，B 队头正好是七筒（要胡的那张）。换山后剩余 63，A/B 整行对调：
--     新 A = 旧 B 去掉队头七筒（下摸变成二条 一筒 赤五万…），
--     新 B = 旧 A 去掉队头六条、八筒（七万 二万 八万…）。
--     七筒从可见牌山消失，玩家没摸到。像是听牌将成时把两行对调并抽走听牌。
--     同帧手A@5051F8 仍是玩家、手B@504F86 仍是电脑。
--   流局/终局会出「海底機會」：12 张盖牌（两行各 6），翻开的牌不必是
--   0x504150 队头。例：HUD 下摸仍是八万（玩家）剩余 56，翻开的是四筒，
--   且不在当时玩家/电脑行队头附近。海底可能是另一段 RAM / 听牌时抽走的
--   那批牌 / 牌尾死牌区，需要另找缓冲，不要默认等于当前牌山下一张。
--   图17 补充：流局前剩余山接下是九筒、二筒；若海底第二张是二筒，更像接着摸山。
--   听牌判定（已确认）：必须自己已有番才算听牌。机台不会先把「海底」当成可能的番
--   再发海底机会。无役听牌 → 流局判没听 → 没有海底。
--   胡牌后翻牌加番（暂不改 HUD）：先出「翻羽」，5 张盖牌标 A~E（「請押 A~E 鍵」）。
--   有时只选 1 张，有时选 2 张，规律未明（可能和庄/自摸荣和/杠数/听牌/RATE/古月
--   有关，下次可对着结算框记下来）。结算分项：古月、翻羽、红翻、役、得。
--   例：古月 1，翻羽 5 格里翻出八万/八筒等得 4，红翻再亮 3 张（含赤五万）得 2，
--   役 0，总得 7。过程中 HUD 牌山不变（例：下摸仍是七条/电脑、剩余 45），
--   这些加番牌不像从当前队头扣掉，需另找翻羽/红翻缓冲（可能与听牌抽走、海底同源）。
--   翻羽 A~E 作宝牌指示：翻出点数 N，宝牌是 N+1（九之后是否回到一未测）。
--   实测：B=二万 → 三万、三筒；D=四筒 → 五万、五筒；A=五万 → 六万；E=八筒 → 九万、九条。
--   不只同花色：像是三门里所有 N+1 都算（这局没九筒，九筒是否也宝未看见）。
--   另：听八筒无人碰杠，按 B 行第 3 张摸到八筒并自摸，摸牌顺序未被碰杠打乱。
--
-- 手牌（暂不改 HUD，继续测）：
--   0x5042D0 不是屏幕手牌。HUD 目前扫 0x504800–0x505800 里干净牌码槽。
--   每个槽按 14 格读取（天听/刚摸可能 14 张），画面只画前 13 张、不画空槽。
--   FD/00 就停（否则天听/庄家 14 张会被截成 13）。括号里仍是实际张数。
--   本游戏赤牌只有赤五万/筒/条（85/95/A5）。「赤三万/赤九万/赤六筒」是普通牌被 +0x80
--   误译，那种槽不是手牌。
--   图1 开局：玩家@5051F6 与底栏一致（四张三万+赤五万+三张九万+三张六筒+三条+八条）。
--   电脑@50480E 不可信：又出现三万（玩家已有四张），且有赤三万/赤九万/赤六筒。
--   图2 电脑打九万、玩家杠九万后：两行对调——「手电脑」变成排序后的玩家牌（少一张），
--   「手玩家」变成图1 那份假电脑槽。地址也漂（玩家变成 @50480E）。
--   图3 杠后岭上摸到 A 队头七万：「手电脑」换成十三张、赤的也是五X，开始像真电脑手。
--   图4 再杠三万：手电脑行不变。
--   图5 岭上摸到 B 队头七筒。
--   图6 玩家打八条，电脑摸走图5 A 队头三筒并打一条：手电脑少一条、多三筒。
--   图7 玩家摸入图6 B 队头六条：原先「手电脑」整行跑到「手玩家」；新的「手电脑」
--   高度像玩家手牌，但缺已杠的三万、九万，刚摸的六条后面又多出五张条（像凑长度）。
--   图8 又打两三张无异常；那多出来的五张仍像垫数，不是真手牌。
--   图9 玩家打一万，电脑摸六万又打六万（手牌应不变），但玩家还未摸时 HUD 仍留着
--   六万、七条却没了——显示错位/滞后，不是牌真变了。
--   图10 玩家摸入六万后，「手电脑」又对上了。
--   图11 玩家打七筒听三条，电脑打出三条：两行内容又变得很像。按前面规律三条还应
--   留在电脑手里，但这帧「手玩家」里有三条，带赤五筒/赤五条的那行没有。玩家本可
--   胡这张三条却胡不了——怀疑九万杠是从电脑打出的，无番。
--   图12 玩家摸入五万：「手玩家」又变成正常电脑手，「手电脑」变回带凑数的玩家手，
--   但刚摸的五万两边都没有。
--   图13 打五万继续听三条，电脑摸八筒打八筒：两行又回到图11 那种几乎镜像。
--   图14 摸六条打六条继续听三条；电脑摸六筒打四条，听三六筒。
--   图15 玩家摸二筒，「手电脑」仍不显示二筒（疑电脑判定玩家不会留二筒）。
--   图16 玩家打三条改听二筒。按牌山这局多半流局。
--   图17 打完最后一张即将流局：牌山接下两张按序是九筒（A）再二筒（B）。若海底捞
--   能在第二张捞到二筒，说明海底可能就是后续牌山，不是另起的死牌区。
--   图18 电脑判定玩家没听牌，因此没有海底。已确认：无独立番就不算听，不会先发
--   海底当番。听二筒若只有海底这一役，流局仍判没听。
--   Overlay 只读、不写 RAM。但每帧扫 0x504800–0x505800 会极卡，68K 与 MCU 时序
--   被拖慢时偶发怪结果不能完全排除。手牌扫描改为剩余张数变化或每 8 帧才扫一次。
--   手牌槽（已对上画面，HUD 暂不改标签逻辑）：
--     0x5051F8 vis：手A，底栏玩家手，带赤。刚摸时可能还是 13 张。
--     0x504F86 cpu：手B，电脑手，带赤。电脑打出的牌会从这里消失。这两行目前较稳。
--     0x504EE6 sort「去赤」、0x5054E0「电脑拷」：有时是电脑去赤（图1/2：跟手B），
--       有时开局起就是玩家去赤（图4：跟手A，赤五万→五万，并可能多一张刚摸的）。
--       点胡之后也会变成玩家去赤（14 张，含胡进的那张）。不能按地址写死是谁的。
--     0x505600 live「缓冲」：平时常是工作区/电脑相关拷贝；点胡后也变成玩家去赤，
--       但第 1 张会被写成八筒（与牌山下一张无关，例：下摸是五条时缓冲仍以八筒开头）。
--   「另」两行是谁的去赤要看内容跟手A还是手B更像，不能按地址写死。
--   电脑听牌后 cpu 槽可能暂时空；手B 保留听前那手并标「听留」。

local LOG_PATH = "smoke_logs/rbmk_wall.log"

local RANGES = {
    { tag = ":maincpu", space = "program", start = 0x100000, size = 0x10000, name = "68k_work1" },
    { tag = ":maincpu", space = "program", start = 0x500000, size = 0x10000, name = "68k_work2" },
    { tag = ":maincpu", space = "program", start = 0x980000, size = 0x4000, name = "68k_extra" },
    { tag = ":maincpu", space = "program", start = 0x9C0000, size = 0x1000, name = "vidram" },
}

local HOT_DUMP = {
    { start = 0x004140, size = 0x00F0, name = "wall 0x504140-0x50422F" },
    { start = 0x0042D0, size = 0x0080, name = "work 0x5042D0 (not visual hand)" },
    { start = 0x004270, size = 0x0060, name = "hist 0x504270" },
    { start = 0x0051F0, size = 0x0150, name = "hands 0x5051F0-0x50533F" },
}

local WALL_BASE = 0x504150
local WALL_WORDS = 140
local last_wall_sig = nil
-- false：不画画面中间那块调试字（下摸/手A@地址）。透视窗口、读牌逻辑仍在。
-- 做海底/翻宝牌时改 true 即可，不必删代码。
local SHOW_TEXT_HUD = false
local live_hud = { ok = false, line1 = "", line2 = "", line3 = "", line4 = "", line5 = "", line6 = "", line7 = "" }
local round_remain0 = 0
local last_remain_n = 0
local wall_dim_base = 0
local last_first_raw = nil
local player_side = nil -- "A" or "B", 本局用 Ctrl+0 锁定
local prev_wall_raws = nil
local dealt_raws = {}
local cpu_recon = nil
-- 岭上从队头摸：玩家摸走了本该电脑摸的那张时，两行对调
local pending_rinshan = nil
local hand_cache = { slots = {}, n = nil, age = 8 }
-- 手A=画面玩家 vis（0x5051xx，带赤），手B=电脑 cpu（0x504F8x）；去赤/工作槽只进「另」
local hand_id = { p_addr = nil, p_list = nil, c_addr = nil, c_list = nil }
local extra_hold = {}
local cpu_hand_prev = nil
local EXTRA_TTL = 150
local OVERLAP_SAME = 10
local HAND_VIS_LO, HAND_VIS_HI = 0x5051F0, 0x505300
local HAND_SORT_LO, HAND_SORT_HI = 0x504EE0, 0x504F80
local HAND_CPU_LO, HAND_CPU_HI = 0x504F80, 0x5051F0
local HAND_LIVE_LO, HAND_LIVE_HI = 0x505600, 0x505800

local input, seq0, seq1, seq2, seq3, seq9, seq_f9
local prev = { false, false, false, false, false, false }
local peek_open = false
local peek_click = false
local mark_click = false
local hooked_views = {}
local pause_poll_hooked = false
local pause_guard = 0
local ptr_held = {}
local ptr_lock_until = 0
local ptr_lock_frames = 0

local MASK_PEEK, MASK_PAUSE, MASK_MARK = 1, 8, 64
local key4_idle = nil
local key4_prev = 0
local key4_port_tag = nil
local snap_a = nil
local logged_map = false
local tiles_ui = nil
pcall(function()
    local loader = loadfile("fei_mj_lamps/ui_tiles.lua")
    tiles_ui = loader and loader() or nil
end)

local BCD_A = {} -- 01-09 / 11-19 / 21-29 / 31-37
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

local function now()
    return os.date("%H:%M:%S")
end

local function write_log(text, mode)
    local f = io.open(LOG_PATH, mode or "a")
    if not f then
        f = io.open("rbmk_wall.log", mode or "a")
    end
    if not f then
        print("[rbmk_wall] cannot open log")
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

local function wall_hits_set(s, valid)
    local n = #s
    local hits = {}
    if n < 136 then
        return hits
    end
    local freq = {}
    local bad = 0
    local function addv(v, d)
        if not valid[v] then
            bad = bad + d
            return
        end
        freq[v] = (freq[v] or 0) + d
    end
    local function exact()
        if bad ~= 0 then
            return false
        end
        for v in pairs(valid) do
            if (freq[v] or 0) ~= 4 then
                return false
            end
        end
        return true
    end
    for i = 1, 136 do
        addv(s:byte(i), 1)
    end
    if exact() then
        hits[#hits + 1] = 0
    end
    for i = 2, n - 135 do
        addv(s:byte(i - 1), -1)
        addv(s:byte(i + 135), 1)
        if exact() then
            hits[#hits + 1] = i - 1
        end
    end
    return hits
end

local function wall_hits_0_33(s)
    local valid = {}
    for i = 0, 33 do
        valid[i] = true
    end
    return wall_hits_set(s, valid)
end

local function wall_hits_1_34(s)
    local valid = {}
    for i = 1, 34 do
        valid[i] = true
    end
    return wall_hits_set(s, valid)
end

local function hist34_hits(s)
    -- 34 字节，每字节 0-4，和为 84..136（剩余牌计数表）
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

local function words_low_bytes(s)
    if (#s % 2) ~= 0 then
        return nil
    end
    local t = {}
    for i = 1, #s, 2 do
        t[#t + 1] = string.char(s:byte(i + 1))
    end
    return table.concat(t)
end

local function words_high_bytes(s)
    if (#s % 2) ~= 0 then
        return nil
    end
    local t = {}
    for i = 1, #s, 2 do
        t[#t + 1] = string.char(s:byte(i))
    end
    return table.concat(t)
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
    if n >= 136 then
        for _, off in ipairs(wall_hits_0_33(s)) do
            add("wall136 v=0-33 x4", off, 136, label)
        end
        for _, off in ipairs(wall_hits_1_34(s)) do
            add("wall136 v=1-34 x4", off, 136, label)
        end
        for _, off in ipairs(wall_hits_set(s, BCD_A)) do
            add("wall136 BCD 01-09/11-19/21-29/31-37", off, 136, label)
        end
        for _, off in ipairs(wall_hits_set(s, BCD_B)) do
            add("wall136 BCD 11-19/21-29/31-39/41-47", off, 136, label)
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
    local hits = scan_buf(s, name .. "/u8", base_addr)
    local low = words_low_bytes(s)
    if low and #s >= 272 then
        local extra = scan_buf(low, name .. "/u16.lo", base_addr)
        for _, h in ipairs(extra) do
            if h.kind:find("wall136", 1, true) then
                h.addr = base_addr + h.off * 2
                h.note = h.note .. " (word stride)"
                hits[#hits + 1] = h
            end
        end
    end
    local high = words_high_bytes(s)
    if high and #s >= 272 then
        local extra = scan_buf(high, name .. "/u16.hi", base_addr)
        for _, h in ipairs(extra) do
            if h.kind:find("wall136", 1, true) then
                h.addr = base_addr + h.off * 2
                h.note = h.note .. " (word stride hi)"
                hits[#hits + 1] = h
            end
        end
    end
    return hits
end

local function format_hits(hits)
    local walls = {}
    local other = {}
    for _, h in ipairs(hits) do
        if h.kind:find("wall136", 1, true) then
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

local function diff_bufs(a, b, name, base_addr)
    local n = math.min(#a, #b)
    local runs = {}
    local i = 1
    while i <= n do
        if a:byte(i) ~= b:byte(i) then
            local j = i
            while j <= n and a:byte(j) ~= b:byte(j) do
                j = j + 1
            end
            local len = j - i
            runs[#runs + 1] = {
                addr = base_addr + (i - 1),
                off = i - 1,
                len = len,
                before = hex_preview(a:sub(i, i + math.min(len, 32) - 1), 32),
                after = hex_preview(b:sub(i, i + math.min(len, 32) - 1), 32),
            }
            i = j
        else
            i = i + 1
        end
    end
    local t = { string.format("[%s] %d changed run(s)\n", name, #runs) }
    table.sort(runs, function(x, y)
        if x.len ~= y.len then
            return x.len > y.len
        end
        return x.addr < y.addr
    end)
    for k = 1, math.min(#runs, 24) do
        local r = runs[k]
        t[#t + 1] = string.format(
            "  run @ 0x%06X len=%d\n    A %s\n    B %s\n",
            r.addr, r.len, r.before, r.after
        )
    end
    return table.concat(t), runs
end

local function snapshot_all(machine)
    local snap = { regions = {}, hits = {} }
    local cpu = machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    for _, spec in ipairs(RANGES) do
        local sp = space
        if spec.tag ~= ":maincpu" then
            local dev = machine.devices[spec.tag]
            sp = dev and dev.spaces and dev.spaces[spec.space]
        end
        if sp then
            local s = dump_space(sp, spec.start, spec.size)
            snap.regions[#snap.regions + 1] = {
                name = spec.name,
                start = spec.start,
                size = spec.size,
                data = s,
            }
            local hits = scan_region(s, spec.name, spec.start)
            for _, h in ipairs(hits) do
                snap.hits[#snap.hits + 1] = h
            end
        end
    end
    local mcu = machine.devices[":mcu"]
    local idata = mcu and mcu.spaces and mcu.spaces["idata"]
    if idata then
        local s = dump_space(idata, 0, 0x80)
        snap.regions[#snap.regions + 1] = {
            name = "mcu_idata",
            start = 0,
            size = 0x80,
            data = s,
        }
    end
    local share = machine.memory and machine.memory.shares and machine.memory.shares[":mcu:internal_ram"]
    if share and share.size then
        -- share 可能没有 read_u8；有 idata 就够了
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

local function dump_hot(snap)
    local t = {}
    local work2 = region(snap, "68k_work2")
    if work2 then
        for _, h in ipairs(HOT_DUMP) do
            t[#t + 1] = string.format("[%s]\n", h.name)
            t[#t + 1] = hex_dump(work2.data, work2.start, h.start, h.size)
        end
    end
    local extra = region(snap, "68k_extra")
    if extra then
        t[#t + 1] = "[68k_extra 0x980000] (nonzero lines only)\n"
        local shown = 0
        for off = 0, #extra.data - 1, 16 do
            local nz = false
            for j = 1, 16 do
                if extra.data:byte(off + j) ~= 0 then
                    nz = true
                    break
                end
            end
            if nz then
                t[#t + 1] = hex_dump(extra.data, extra.start, off, 16)
                shown = shown + 1
                if shown >= 48 then
                    t[#t + 1] = "  ... extra truncated\n"
                    break
                end
            end
        end
        if shown == 0 then
            t[#t + 1] = "  (all zero)\n"
        end
    end
    local vid = region(snap, "vidram")
    if vid then
        t[#t + 1] = "[vidram 0x9C0000] (nonzero lines only)\n"
        local shown = 0
        for off = 0, #vid.data - 1, 16 do
            local nz = false
            for j = 1, 16 do
                if vid.data:byte(off + j) ~= 0 then
                    nz = true
                    break
                end
            end
            if nz then
                t[#t + 1] = hex_dump(vid.data, vid.start, off, 16)
                shown = shown + 1
                if shown >= 64 then
                    t[#t + 1] = "  ... vidram truncated\n"
                    break
                end
            end
        end
    end
    local mcu = region(snap, "mcu_idata")
    if mcu then
        t[#t + 1] = "[mcu_idata]\n"
        t[#t + 1] = hex_dump(mcu.data, 0, 0, #mcu.data)
    end
    return table.concat(t)
end

local function log_map(machine)
    if logged_map then
        return
    end
    logged_map = true
    local lines = { string.format("=== rbmk wall hunt map %s ===\n", now()) }
    for tag, dev in pairs(machine.devices) do
        if type(tag) == "string" and (tag:find("cpu", 1, true) or tag:find("mcu", 1, true)) then
            lines[#lines + 1] = string.format("device %s short=%s\n", tag, tostring(dev.shortname))
            if dev.spaces then
                for name, space in pairs(dev.spaces) do
                    lines[#lines + 1] = string.format("  space %s\n", tostring(name))
                end
            end
        end
    end
    write_log(table.concat(lines), "a")
end

local function bind_keys(machine)
    if seq1 then
        return
    end
    input = machine.input
    seq1 = input:seq_from_tokens("KEYCODE_LCONTROL KEYCODE_1")
    seq2 = input:seq_from_tokens("KEYCODE_LCONTROL KEYCODE_2")
    seq3 = input:seq_from_tokens("KEYCODE_LCONTROL KEYCODE_3")
    seq0 = input:seq_from_tokens("KEYCODE_LCONTROL KEYCODE_0")
    seq9 = input:seq_from_tokens("KEYCODE_LCONTROL KEYCODE_9")
    seq_f9 = input:seq_from_tokens("KEYCODE_F9")
end

local function edge(idx, seq)
    local down = input:seq_pressed(seq)
    local fire = down and not prev[idx]
    prev[idx] = down
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

local function ptr_mark_busy()
    local t, hz = osd_now()
    if t > 0 and hz and hz > 0 then
        ptr_lock_until = t + hz * 0.22
    end
    ptr_lock_frames = 14
    pause_guard = t
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

local function find_key4(machine)
    if key4_port_tag then
        return machine.ioport.ports[key4_port_tag]
    end
    local ports = machine.ioport and machine.ioport.ports
    if not ports then
        return nil
    end
    for _, tag in ipairs({ ":KEY4", "KEY4" }) do
        if ports[tag] then
            key4_port_tag = tag
            return ports[tag]
        end
    end
    for tag, _ in pairs(ports) do
        if type(tag) == "string" and tag:upper():find("KEY4", 1, true) then
            key4_port_tag = tag
            return ports[tag]
        end
    end
    return nil
end

local function poll_skin_buttons(_machine)
    -- 透视/暂停/标记不再绑 KEY4：mask 1 是退币，上分界面连点透视会洗分。
end

-- set_bounds_callback 必须返回渲染目标坐标（窗口约 0~1）。传像素会把贴图放到巨幅上采样，MAME 直接闪退。
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

local function hit_pause_xy(view, x, y)
    if hit_item_xy(view, "btn_pause", x, y) then
        return true
    end
    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local land = view_is_landscape(view)
    if x <= 2 and y <= 2 then
        if land then
            return x >= (1400 / 1600) and x <= (1542 / 1600) and y >= (130 / 900) and y <= (245 / 900)
        end
        return x >= 0.855 and x <= 0.997 and y >= (1110 / 1640) and y <= (1240 / 1640)
    end
    if land then
        return x >= 1400 and x <= 1542 and y >= 130 and y <= 245
    end
    return x >= 855 and x <= 997 and y >= 1110 and y <= 1240
end

local function hit_peek_xy(view, x, y)
    if hit_item_xy(view, "btn_peek", x, y) then
        return true
    end
    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local land = view_is_landscape(view)
    if x <= 2 and y <= 2 then
        if land then
            return x >= (1400 / 1600) and x <= (1542 / 1600) and y >= (10 / 900) and y <= (125 / 900)
        end
        return x >= 0.003 and x <= 0.145 and y >= (1110 / 1640) and y <= (1240 / 1640)
    end
    if land then
        return x >= 1400 and x <= 1542 and y >= 10 and y <= 125
    end
    return x >= 3 and x <= 145 and y >= 1110 and y <= 1240
end

local function hit_mark_xy(view, x, y)
    if not peek_open then
        return false
    end
    if hit_item_xy(view, "btn_mark", x, y) then
        return true
    end
    if tiles_ui and tiles_ui.view_to_screen and tiles_ui.hit_mark then
        local sx, sy = tiles_ui.view_to_screen(view, x, y)
        if sx then
            return tiles_ui.hit_mark(sx, sy)
        end
    end
    return false
end

local function apply_mark(machine)
    local next_side = "A"
    if live_hud.peek and live_hud.peek.next_side then
        next_side = live_hud.peek.next_side
    end
    player_side = next_side
    mark_click = false
    if machine and machine.popmessage then
        machine:popmessage("已标记：" .. ((next_side == "A") and "上行=玩家摸" or "下行=玩家摸"))
    end
end

local function hook_peek_pointer(machine)
    local render = machine.render
    if not render or not render.targets then
        return
    end
    local function bind_view(view)
        if not view or hooked_views[view] then
            return
        end
        local has_btn = false
        pcall(function()
            has_btn = view.items and view.items["btn_peek"] ~= nil
        end)
        if not has_btn then
            return
        end
        hooked_views[view] = true
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
            local mark_item = view.items["btn_mark"]
            if mark_item then
                bind_state("btn_mark", function()
                    return 0
                end)
                if mark_item.set_bounds_callback and emu.render_bounds then
                    mark_item:set_bounds_callback(function()
                        local ok, b = pcall(function()
                            if not peek_open then
                                return rt_bounds(-0.40, -0.20, -0.22, -0.08)
                            end
                            local m = tiles_ui and tiles_ui.mark_target_rect and tiles_ui.mark_target_rect(view)
                            if m and m.x0 and m.x1 > m.x0 then
                                return rt_bounds(m.x0, m.y0, m.x1, m.y1)
                            end
                            return rt_bounds(-0.40, -0.20, -0.22, -0.08)
                        end)
                        if ok and b then
                            return b
                        end
                        return rt_bounds(-0.40, -0.20, -0.22, -0.08)
                    end)
                end
            end
            if view.set_pointer_updated_callback then
                view:set_pointer_updated_callback(function(_, pid, _, x, y, _, pressed)
                    local down = type(pressed) == "number" and (pressed & 1) ~= 0
                    local key = tostring(pid or 0)
                    local was = ptr_held[key]
                    ptr_held[key] = down
                    if not down or was then
                        return
                    end
                    if ptr_busy() then
                        return
                    end
                    if peek_open and hit_mark_xy(view, x, y) then
                        apply_mark(manager.machine)
                        ptr_mark_busy()
                        return
                    end
                    if hit_pause_xy(view, x, y) then
                        toggle_pause()
                        return
                    end
                    if hit_peek_xy(view, x, y) then
                        peek_click = true
                        ptr_mark_busy()
                        return
                    end
                end)
            end
        end)
    end
    if render.ui_target and render.ui_target.current_view then
        bind_view(render.ui_target.current_view)
    end
    for i = 1, 4 do
        local t = render.targets[i]
        if t and not t.hidden and t.current_view then
            bind_view(t.current_view)
        end
    end
end

local function toggle_peek(machine)
    peek_open = not peek_open
    if tiles_ui then
        tiles_ui.ensure_art(machine)
    end
    machine:popmessage(peek_open and "透视开" or "透视关")
end

local function apply_peek_click(machine)
    if peek_click then
        peek_click = false
        toggle_peek(machine)
    end
end

local function ensure_pause_poll()
    if pause_poll_hooked then
        return
    end
    pause_poll_hooked = true
    pcall(function()
        emu.register_periodic(function()
            local m = manager.machine
            if not m or not m.paused or not m.system or m.system.name ~= "rbmk" then
                return
            end
            poll_skin_buttons(m)
            apply_peek_click(m)
            ptr_tick()
        end)
    end)
end

local MAN = { "一万", "二万", "三万", "四万", "五万", "六万", "七万", "八万", "九万" }
local PIN = { "一筒", "二筒", "三筒", "四筒", "五筒", "六筒", "七筒", "八筒", "九筒" }
local SOU = { "一条", "二条", "三条", "四条", "五条", "六条", "七条", "八条", "九条" }

local function suited_name(base)
    local hi = base >> 4
    local lo = base & 0x0F
    if lo < 1 or lo > 9 then
        return nil
    end
    if hi == 0 then
        return MAN[lo]
    end
    if hi == 1 then
        return PIN[lo]
    end
    if hi == 2 then
        return SOU[lo]
    end
    return nil
end

local function tile_name(v)
    v = v & 0xFF
    -- 空位 / 表头 / 胡牌时冲掉的垃圾值
    if v == 0x00 or v == 0xFD or v == 0x2D or v == 0xA0 or v == 0xFF then
        return nil
    end
    -- 0x85/95/A5 = 赤五万/筒/条（高位 +0x80）
    local red = false
    local base = v
    if v >= 0x80 then
        local low = v - 0x80
        if suited_name(low) then
            red = true
            base = low
        end
    end
    local su = suited_name(base)
    if su then
        if red then
            return "赤" .. su
        end
        return su
    end
    -- 无字牌：0x3x/4x/5x 不当东南西北中发白，留给日志看十六进制
    return string.format("[%02X]", v)
end

local function is_hole(v)
    return v == 0xFD or v == 0x00 or v == 0xA0
end

-- 已摸的牌会变成 FD，堆在数组前部。第二局常在 FD 之前残留一张旧牌（整局不变），
-- 真正的牌山从第一段 FD 空洞之后开始。
local function read_wall(space)
    local words = {}
    local ok_all, data = pcall(function()
        local w = {}
        for i = 0, WALL_WORDS - 1 do
            w[i + 1] = space:read_u16(WALL_BASE + i * 2) & 0xFF
        end
        return w
    end)
    if ok_all and data then
        words = data
    else
        return {}, nil, 1
    end
    local first_fd
    for i = 1, #words do
        if words[i] == 0xFD then
            first_fd = i
            break
        end
    end
    local start_i = 1
    if first_fd then
        local j = first_fd
        while j <= #words and is_hole(words[j]) do
            j = j + 1
        end
        start_i = j
    end
    local tiles = {}
    for i = start_i, #words do
        local name = tile_name(words[i])
        if name then
            tiles[#tiles + 1] = { raw = words[i], name = name }
        end
    end
    return tiles, words, start_i
end

local function is_clean_tile(v)
    v = v & 0xFF
    if v == 0 or v == 0xFD or v == 0x2D or v == 0xA0 or v == 0xFF then
        return false
    end
    local n = tile_name(v)
    return n ~= nil and n:sub(1, 1) ~= "["
end

-- 手牌槽常见 16 字对齐；画面上最多 14 张（13 待机 + 1 摸牌/天听）。
local HAND_SHOW = 14
local HAND_EMPTY = "＿"

local function filled_count(list)
    if not list then
        return 0
    end
    if list.filled then
        return list.filled
    end
    local n = 0
    for _, t in ipairs(list) do
        if not t.empty and t.raw and t.raw ~= 0 then
            n = n + 1
        end
    end
    return n
end

-- 跳过前导非牌后固定读 14 格；中间的空槽显示占位，不再截断。
local function read_hand_slot(space, addr)
    local list = {}
    local i = 0
    while i < 6 do
        local ok, w = pcall(function()
            return space:read_u16(addr + i * 2)
        end)
        if not ok then
            list.filled = 0
            return list
        end
        if is_clean_tile(w & 0xFF) then
            break
        end
        i = i + 1
    end
    local filled = 0
    for k = 0, HAND_SHOW - 1 do
        local ok, w = pcall(function()
            return space:read_u16(addr + (i + k) * 2)
        end)
        if not ok then
            list[#list + 1] = { raw = 0, name = HAND_EMPTY, empty = true }
        else
            local v = w & 0xFF
            if is_clean_tile(v) then
                list[#list + 1] = { raw = v, name = tile_name(v), empty = false }
                filled = filled + 1
            else
                list[#list + 1] = { raw = 0, name = HAND_EMPTY, empty = true }
            end
        end
    end
    list.filled = filled
    return list
end

local function bag_key(list)
    if not list then
        return ""
    end
    local c = {}
    for _, t in ipairs(list) do
        if not t.empty and t.raw and t.raw ~= 0 then
            local r = t.raw
            c[r] = (c[r] or 0) + 1
        end
    end
    local keys = {}
    for r, n in pairs(c) do
        keys[#keys + 1] = string.format("%02X:%d", r, n)
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- 赤五（+0x80）与普通五算同一张，用来丢掉「去赤的玩家拷贝」
local function bag_key_plain(list)
    if not list then
        return ""
    end
    local c = {}
    for _, t in ipairs(list) do
        if not t.empty and t.raw and t.raw ~= 0 then
            local r = t.raw & 0xFF
            if r >= 0x80 then
                local low = r - 0x80
                if suited_name(low) then
                    r = low
                end
            end
            c[r] = (c[r] or 0) + 1
        end
    end
    local keys = {}
    for r, n in pairs(c) do
        keys[#keys + 1] = string.format("%02X:%d", r, n)
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- 0x504800–0x505800：干净牌码槽。不去重成「同一袋只留一个地址」，
-- 否则 0x5051xx 真手会被 0x504EEx 去赤拷贝挤掉。
local function is_real_aka(v)
    v = v & 0xFF
    return v == 0x85 or v == 0x95 or v == 0xA5
end

local function slot_legal(list, addr)
    local c = {}
    for _, t in ipairs(list) do
        if not t.empty and t.raw and t.raw ~= 0 then
            local v = t.raw & 0xFF
            if v >= 0x80 then
                if not is_real_aka(v) then
                    return false
                end
                v = v - 0x80
            end
            c[v] = (c[v] or 0) + 1
            local maxc = (v == 0x05 or v == 0x15 or v == 0x25) and 5 or 4
            if c[v] > maxc then
                return false
            end
        end
    end
    local n = filled_count(list)
    -- 电脑碰杠后暗手只有 10/7 张，槽尾常残留刚打出的牌
    if addr and addr >= HAND_CPU_LO and addr < HAND_CPU_HI then
        return n >= 7
    end
    return n >= 13
end

local function addr_kind(addr)
    if addr >= HAND_LIVE_LO and addr < HAND_LIVE_HI then
        return "live"
    elseif addr >= HAND_VIS_LO and addr < HAND_VIS_HI then
        return "vis"
    elseif addr >= HAND_SORT_LO and addr < HAND_SORT_HI then
        return "sort"
    elseif addr >= HAND_CPU_LO and addr < HAND_CPU_HI then
        return "cpu"
    elseif addr >= 0x504800 and addr < HAND_SORT_LO then
        return "early"
    end
    return "other"
end

local function cluster_taken(slots, addr)
    for _, s in ipairs(slots) do
        if math.abs(s.addr - addr) < 28 then
            return true
        end
    end
    return false
end

local function hunt_clean_hands(space)
    local slots = {}
    local addr = 0x504800
    while addr <= 0x5057F0 do
        if addr >= 0x504150 and addr < 0x504500 then
            addr = 0x504500
        else
            local list = read_hand_slot(space, addr)
            local first_ok = list[1] and not list[1].empty
            if first_ok and slot_legal(list, addr) and not cluster_taken(slots, addr) then
                slots[#slots + 1] = { addr = addr, list = list, kind = addr_kind(addr) }
                addr = addr + math.max(2, HAND_SHOW * 2)
            else
                addr = addr + 2
            end
        end
    end
    return slots
end

local function get_hand_slots(space, n)
    hand_cache.age = hand_cache.age + 1
    if hand_cache.slots and hand_cache.n == n and hand_cache.age < 16 then
        return hand_cache.slots
    end
    hand_cache.age = 0
    hand_cache.n = n
    hand_cache.slots = hunt_clean_hands(space)
    return hand_cache.slots
end

local function snap_hand(space, addr)
    if not addr then
        return nil, nil
    end
    local best, best_a, best_n, best_d = nil, nil, 0, 99
    for off = -8, 8 do
        local a = addr + off * 2
        if a >= 0x504800 and a <= 0x5057F0 then
            local list = read_hand_slot(space, a)
            local n = filled_count(list)
            local minn = (a >= HAND_CPU_LO and a < HAND_CPU_HI) and 7 or 12
            if list[1] and not list[1].empty and slot_legal(list, a) and n >= minn then
                local d = math.abs(off)
                if n > best_n or (n == best_n and d < best_d) then
                    best, best_a, best_n, best_d = list, a, n, d
                end
            end
        end
    end
    return best, best_a
end

local function overlap_plain(a, b)
    if not a or not b then
        return 0
    end
    local ca = {}
    for _, t in ipairs(a) do
        if not t.empty and t.raw and t.raw ~= 0 then
            local r = t.raw & 0xFF
            if r >= 0x80 then
                local low = r - 0x80
                if suited_name(low) then
                    r = low
                end
            end
            ca[r] = (ca[r] or 0) + 1
        end
    end
    local n = 0
    for _, t in ipairs(b) do
        if not t.empty and t.raw and t.raw ~= 0 then
            local r = t.raw & 0xFF
            if r >= 0x80 then
                local low = r - 0x80
                if suited_name(low) then
                    r = low
                end
            end
            if (ca[r] or 0) > 0 then
                ca[r] = ca[r] - 1
                n = n + 1
            end
        end
    end
    return n
end

local function is_same_hand(a, b)
    return a and b and overlap_plain(a, b) >= OVERLAP_SAME
end

local function compact_tiles(list)
    local out = {}
    if not list then
        return out
    end
    for _, t in ipairs(list) do
        if not t.empty and t.raw and t.raw ~= 0 then
            out[#out + 1] = t
        end
    end
    out.filled = #out
    return out
end

-- 碰杠后 cpu 槽尾可能残留刚打出的牌。顺序匹配会把正常 13 张裁成 10，先停用。
-- 目前不能可靠判断电脑何时碰/杠（没有独立副露表，只靠手牌槽长度/内容启发式）。
local function sanitize_cpu_hand(curr, held)
    if not curr then
        cpu_hand_prev = nil
        return curr
    end
    cpu_hand_prev = compact_tiles(curr)
    return curr
end

local KIND_RANK = { vis = 5, sort = 3, cpu = 2, other = 1, early = 0, live = 0 }

local function best_of_kind(slots, kind)
    local best = nil
    for _, s in ipairs(slots) do
        local k = s.kind or addr_kind(s.addr)
        if k == kind then
            if not best or filled_count(s.list) > filled_count(best.list) then
                best = s
            elseif best and filled_count(s.list) == filled_count(best.list) and s.addr < best.addr then
                best = s
            end
        end
    end
    return best
end

local function unique_hands(slots)
    local uniq = {}
    for _, s in ipairs(slots) do
        local kind = s.kind or addr_kind(s.addr)
        if kind ~= "sort" and kind ~= "live" then
            local hit = nil
            for _, u in ipairs(uniq) do
                if is_same_hand(u.list, s.list) then
                    hit = u
                    break
                end
            end
            if hit then
                local n_new, n_old = filled_count(s.list), filled_count(hit.list)
                local r_new, r_old = KIND_RANK[kind] or 0, KIND_RANK[hit.kind] or 0
                if n_new > n_old or (n_new == n_old and r_new > r_old) then
                    hit.addr, hit.list, hit.kind = s.addr, s.list, kind
                end
            else
                uniq[#uniq + 1] = { addr = s.addr, list = s.list, kind = kind }
            end
        end
    end
    return uniq
end

local function remember_extra(addr, list, tag)
    extra_hold[addr] = { list = list, tag = tag or "", ttl = EXTRA_TTL }
end

local function decay_extras(space, keep)
    local dead = {}
    for addr, e in pairs(extra_hold) do
        if keep[addr] then
            e.ttl = EXTRA_TTL
        else
            local list, a = snap_hand(space, addr)
            if list then
                e.list = list
                e.ttl = EXTRA_TTL
                if a and a ~= addr then
                    extra_hold[a] = { list = list, tag = e.tag or "", ttl = EXTRA_TTL }
                    dead[#dead + 1] = addr
                end
            else
                e.ttl = e.ttl - 1
                if e.ttl <= 0 then
                    dead[#dead + 1] = addr
                end
            end
        end
    end
    for _, addr in ipairs(dead) do
        extra_hold[addr] = nil
    end
end

local function assign_hands(space, slots)
    local vis = best_of_kind(slots, "vis")
    local sort = best_of_kind(slots, "sort")
    local cpu = best_of_kind(slots, "cpu")
    local hand_a, addr_a, hand_b, addr_b = nil, nil, nil, nil
    local b_held = false

    if vis then
        hand_a, addr_a = vis.list, vis.addr
    elseif sort then
        hand_a, addr_a = sort.list, sort.addr
    elseif hand_id.p_addr then
        local list, a = snap_hand(space, hand_id.p_addr)
        local kind = a and addr_kind(a)
        if list and (kind == "vis" or kind == "sort") then
            hand_a, addr_a = list, a
        end
    end

    if cpu and (not hand_a or not is_same_hand(cpu.list, hand_a)) then
        hand_b, addr_b = cpu.list, cpu.addr
    elseif hand_id.c_addr then
        local list, a = snap_hand(space, hand_id.c_addr)
        local kind = a and addr_kind(a)
        if list and kind == "cpu" and not is_same_hand(list, hand_a) then
            hand_b, addr_b = list, a
        end
    end
    if not hand_b then
        local uniq = unique_hands(slots)
        for _, s in ipairs(uniq) do
            if s.kind ~= "vis" and s.kind ~= "sort" and s.kind ~= "live" and not is_same_hand(s.list, hand_a) then
                hand_b, addr_b = s.list, s.addr
                break
            end
        end
    end
    if not hand_b and hand_id.c_list and not is_same_hand(hand_id.c_list, hand_a) then
        hand_b, addr_b = hand_id.c_list, hand_id.c_addr
        b_held = true
    end

    if hand_a then
        hand_id.p_list, hand_id.p_addr = hand_a, addr_a
    end
    if hand_b and not b_held then
        hand_id.c_list, hand_id.c_addr = hand_b, addr_b
    end

    local keep = {}
    if addr_a then
        keep[addr_a] = true
    end
    if addr_b and not b_held then
        keep[addr_b] = true
    end
    local function note(s)
        if not s or keep[s.addr] then
            return
        end
        local kind = s.kind or addr_kind(s.addr)
        local tag = ""
        if kind == "live" then
            tag = "缓冲"
        elseif kind == "sort" or is_same_hand(hand_a, s.list) then
            tag = "去赤"
        elseif is_same_hand(hand_b, s.list) then
            tag = "电脑拷"
        end
        remember_extra(s.addr, s.list, tag)
        keep[s.addr] = true
    end
    for _, s in ipairs(slots) do
        note(s)
    end
    decay_extras(space, keep)
    if addr_a then
        extra_hold[addr_a] = nil
    end
    if addr_b and not b_held then
        extra_hold[addr_b] = nil
    end
    return hand_a, addr_a, hand_b, addr_b, b_held
end

local function hand_has_tile(space, raw)
    raw = raw & 0xFF
    if raw == 0 then
        return false
    end
    for _, s in ipairs(get_hand_slots(space, last_remain_n)) do
        for _, t in ipairs(s.list) do
            if not t.empty and t.raw == raw then
                return true
            end
        end
    end
    return false
end

local function bag_minus(src_raws, sub_list)
    local need = {}
    for _, t in ipairs(sub_list) do
        if not t.empty and t.raw and t.raw ~= 0 then
            local r = t.raw
            need[r] = (need[r] or 0) + 1
        end
    end
    local out = {}
    for _, r in ipairs(src_raws) do
        if (need[r] or 0) > 0 then
            need[r] = need[r] - 1
        else
            out[#out + 1] = { raw = r, name = tile_name(r) or string.format("[%02X]", r) }
        end
    end
    return out
end

local function join_hand(list)
    if not list or #list == 0 then
        return "（无）"
    end
    local t = {}
    for i = 1, math.min(HAND_SHOW, #list) do
        t[#t + 1] = list[i].name
    end
    while #t < HAND_SHOW do
        t[#t + 1] = HAND_EMPTY
    end
    return table.concat(t, " ")
end

local function suffix_consumed(prev, curr)
    if not prev or #curr > #prev then
        return false, 0
    end
    local k = #prev - #curr
    for i = 1, #curr do
        if prev[k + i] ~= curr[i] then
            return false, 0
        end
    end
    return true, k
end

local function live_preview(machine)
    if not peek_open and not SHOW_TEXT_HUD then
        return
    end
    local cpu = machine.devices[":maincpu"]
    local space = cpu and cpu.spaces and cpu.spaces["program"]
    if not space then
        live_hud.ok = false
        return
    end
    local tiles, words, start_i = read_wall(space)
    if #tiles < 1 then
        live_hud.ok = false
        last_wall_sig = nil
        return
    end
    local n = #tiles
    local curr_raws = {}
    for i = 1, n do
        curr_raws[i] = tiles[i].raw
    end
    if n > last_remain_n + 15 or round_remain0 == 0 then
        round_remain0 = n
        player_side = nil
        pending_rinshan = nil
        last_first_raw = nil
        dealt_raws = {}
        cpu_recon = nil
        prev_wall_raws = nil
        hand_cache = { slots = {}, n = nil, age = 8 }
        hand_id = { p_addr = nil, p_list = nil, c_addr = nil, c_list = nil }
        extra_hold = {}
        cpu_hand_prev = nil
        wall_dim_base = 0
    end
    if prev_wall_raws then
        local ok, k = suffix_consumed(prev_wall_raws, curr_raws)
        if ok and k > 0 then
            for i = 1, k do
                dealt_raws[#dealt_raws + 1] = prev_wall_raws[i]
            end
        end
    end
    -- 只少 1 张：正常摸或岭上。若摸走的是电脑那行的队头、且进了玩家手牌 → 杠后对调
    if player_side and last_remain_n > 0 and n == last_remain_n - 1 and last_first_raw then
        local last_consumed = round_remain0 - last_remain_n
        if last_consumed < 0 then
            last_consumed = 0
        end
        local last_next = ((last_consumed % 2) == 0) and "A" or "B"
        pending_rinshan = {
            raw = last_first_raw,
            from_cpu = (last_next ~= player_side),
            frames = 30,
        }
    end
    if pending_rinshan then
        pending_rinshan.frames = pending_rinshan.frames - 1
        if pending_rinshan.from_cpu and hand_has_tile(space, pending_rinshan.raw) then
            player_side = (player_side == "A") and "B" or "A"
            pending_rinshan = nil
        elseif pending_rinshan.frames <= 0 then
            pending_rinshan = nil
        end
    end
    last_remain_n = n
    last_first_raw = tiles[1].raw
    prev_wall_raws = curr_raws
    local consumed = round_remain0 - n
    if consumed < 0 then
        consumed = 0
        round_remain0 = n
    end
    local seq_a, seq_b = {}, {}
    for i = 1, n do
        local orig = consumed + i
        if (orig % 2) == 1 then
            seq_a[#seq_a + 1] = tiles[i]
        else
            seq_b[#seq_b + 1] = tiles[i]
        end
    end
    local function join_seq(list)
        if #list == 0 then
            return "（无）"
        end
        local t = {}
        for i = 1, math.min(13, #list) do
            t[#t + 1] = list[i].name
        end
        return table.concat(t, " ")
    end
    local next_side = ((consumed % 2) == 0) and "A" or "B"
    if seq0 and edge(4, seq0) then
        player_side = next_side
        machine:popmessage("已标记：" .. ((next_side == "A") and "上行=玩家摸" or "下行=玩家摸"))
    elseif mark_click then
        mark_click = false
        player_side = next_side
        machine:popmessage("已标记：" .. ((next_side == "A") and "上行=玩家摸" or "下行=玩家摸"))
    end
    local name_a, name_b = "A", "B"
    if player_side == "A" then
        name_a, name_b = "玩家", "电脑"
    elseif player_side == "B" then
        name_a, name_b = "电脑", "玩家"
    end
    local who = next_side
    if player_side then
        who = (next_side == player_side) and "玩家" or "电脑"
    end
    live_hud.ok = true
    live_hud.line1 = string.format("下摸 %s（%s）  剩余 %d", tiles[1].name, who, n)
    live_hud.line2 = string.format("%s%s %s", next_side == "A" and "●" or " ", name_a, join_seq(seq_a))
    live_hud.line3 = string.format("%s%s %s", next_side == "B" and "●" or " ", name_b, join_seq(seq_b))
    local slots = get_hand_slots(space, n)
    local hand_a, addr_a, hand_b, addr_b, b_held = assign_hands(space, slots)
    if hand_b then
        hand_b = sanitize_cpu_hand(hand_b, b_held)
    end
    if not cpu_recon and #dealt_raws >= 26 and hand_a and filled_count(hand_a) >= 12 then
        local recon = bag_minus(dealt_raws, hand_a)
        if #recon >= 10 and #recon <= 16 then
            cpu_recon = recon
        end
    end
    live_hud.line4 = string.format("手A@%s(%d) %s", addr_a and string.format("%06X", addr_a) or "------", filled_count(hand_a), join_hand(hand_a))
    if hand_b then
        local mark = b_held and "听留" or ""
        live_hud.line5 = string.format("手B%s@%06X(%d) %s", mark, addr_b, filled_count(hand_b), join_hand(hand_b))
    elseif cpu_recon then
        live_hud.line5 = string.format("手B推(%d) %s", filled_count(cpu_recon), join_hand(cpu_recon))
    else
        live_hud.line5 = "手B （电脑听后常要等你摸牌才写回）"
    end
    local extra_addrs = {}
    for addr in pairs(extra_hold) do
        extra_addrs[#extra_addrs + 1] = addr
    end
    table.sort(extra_addrs)
    local extra_lines = {}
    for i = 1, math.min(2, #extra_addrs) do
        local addr = extra_addrs[i]
        local e = extra_hold[addr]
        extra_lines[#extra_lines + 1] = string.format("另 @%06X%s(%d) %s", addr, (e.tag ~= "" and e.tag) or "", filled_count(e.list), join_hand(e.list))
    end
    live_hud.line6 = extra_lines[1] or ""
    live_hud.line7 = extra_lines[2] or ""
    -- 半透明从「发完牌、开始摸打」起算，发牌那 26 张不算。
    if wall_dim_base == 0 and n >= 40 then
        if round_remain0 - n >= 20 or round_remain0 <= 92 then
            wall_dim_base = n
        end
    end
    local play_taken = 0
    if wall_dim_base > 0 then
        play_taken = wall_dim_base - n
        if play_taken < 0 then
            play_taken = 0
            wall_dim_base = n
        end
    end
    live_hud.peek = {
        title = "实战麻将王 透视",
        line1 = live_hud.line1,
        cpu_label = "电脑手",
        cpu = hand_b,
        seq_a = seq_a,
        seq_b = seq_b,
        name_a = name_a,
        name_b = name_b,
        next_side = next_side,
        marked = player_side ~= nil,
        dim_a = math.max(0, 13 - math.ceil(play_taken / 2)),
        dim_b = math.max(0, 13 - math.floor(play_taken / 2)),
        note1 = "听牌时电脑可能换山，下摸会突然对不上。",
        note2 = "电脑碰杠后，电脑手后半可能错乱（含刚打出的牌）。",
    }
    if tiles_ui then
        tiles_ui.ensure_art(machine)
    end
    local ui = nil
    local on_game = false
    if tiles_ui and tiles_ui.game_container then
        ui, on_game = tiles_ui.game_container(machine)
    else
        ui = machine.render and machine.render.ui_container
    end
    if ui then
        local function paint()
            if peek_open and tiles_ui then
                tiles_ui.draw_panel(ui, live_hud.peek)
                return
            end
            if not SHOW_TEXT_HUD then
                return
            end
            local lh = 0.035
            pcall(function()
                lh = manager.ui.line_height
            end)
            -- 抬到画面中下部，避开底部手牌；多两行手牌
            local y0 = 0.48
            local extra = 0
            if live_hud.line6 ~= "" then
                extra = extra + 1
            end
            if live_hud.line7 ~= "" then
                extra = extra + 1
            end
            local rows = 7.3 + extra
            ui:draw_box(0.0, y0 - 0.008, 1.0, y0 + lh * rows, 0x00000000, 0xB0101020)
            ui:draw_text(0.015, y0, live_hud.line1, 0xffffff40)
            ui:draw_text(0.015, y0 + lh, live_hud.line2, 0xffffffff)
            ui:draw_text(0.015, y0 + lh * 2, live_hud.line3, 0xffb0b0b0)
            ui:draw_text(0.015, y0 + lh * 3, live_hud.line4, 0xffc8ffc8)
            ui:draw_text(0.015, y0 + lh * 4, live_hud.line5, 0xffffd0a0)
            local row = 5
            if live_hud.line6 ~= "" then
                ui:draw_text(0.015, y0 + lh * row, live_hud.line6, 0xff808080)
                row = row + 1
            end
            if live_hud.line7 ~= "" then
                ui:draw_text(0.015, y0 + lh * row, live_hud.line7, 0xff808080)
                row = row + 1
            end
            ui:draw_text(0.015, y0 + lh * row, "听牌时电脑可能换山，下摸会突然对不上。", 0xffffa060)
            ui:draw_text(0.015, y0 + lh * (row + 1), "电脑碰杠后，电脑手后半可能错乱。", 0xffff8060)
        end
        if not pcall(paint) then
            if SHOW_TEXT_HUD then
            pcall(function()
                ui:draw_text("left", 12, live_hud.line1, 0xffffff40, 0xb0101020)
                ui:draw_text("left", 13, live_hud.line2, 0xffffffff, 0xb0101020)
                ui:draw_text("left", 14, live_hud.line3, 0xffb0b0b0, 0xb0101020)
                ui:draw_text("left", 15, live_hud.line4, 0xffc8ffc8, 0xb0101020)
                ui:draw_text("left", 16, live_hud.line5, 0xffffd0a0, 0xb0101020)
                if live_hud.line6 ~= "" then
                    ui:draw_text("left", 17, live_hud.line6, 0xff808080, 0xb0101020)
                end
                if live_hud.line7 ~= "" then
                    ui:draw_text("left", 18, live_hud.line7, 0xff808080, 0xb0101020)
                end
            end)
            end
        end
    end
    local sig = { next_side, live_hud.line4, live_hud.line5, live_hud.line6, live_hud.line7 }
    for i = 1, math.min(12, n) do
        sig[#sig + 1] = string.format("%02X", tiles[i].raw)
    end
    sig = table.concat(sig, ",")
    if sig == last_wall_sig then
        return
    end
    last_wall_sig = sig
    if not SHOW_TEXT_HUD then
        return
    end
    print("[rbmk_wall] " .. live_hud.line1 .. " | " .. live_hud.line4 .. " | " .. live_hud.line5)
    local lines = {
        string.format("=== LIVE WALL %s remain=%d start_i=%s consumed=%d dealt=%d A/B ===\n", now(), n, tostring(start_i), consumed, #dealt_raws),
        live_hud.line1 .. "\n",
        live_hud.line2 .. "\n",
        live_hud.line3 .. "\n",
        live_hud.line4 .. "\n",
        live_hud.line5 .. "\n",
        live_hud.line6 ~= "" and (live_hud.line6 .. "\n") or "",
        live_hud.line7 ~= "" and (live_hud.line7 .. "\n") or "",
    }
    if words then
        local raw = {}
        for i = 1, math.min(24, #words) do
            raw[#raw + 1] = string.format("%02X", words[i])
        end
        lines[#lines + 1] = "raw[0x504150..] " .. table.concat(raw, " ") .. "\n"
    end
    pcall(function()
        local p = {}
        for a = 0x504130, 0x50414E, 2 do
            p[#p + 1] = string.format("%06X=%04X", a, space:read_u16(a))
        end
        lines[#lines + 1] = "meta " .. table.concat(p, " ") .. "\n"
    end)
    pcall(function()
        for _, s in ipairs(slots) do
            lines[#lines + 1] = string.format("hand@%06X %s\n", s.addr, join_hand(s.list))
        end
    end)
    for i = 1, #tiles do
        lines[#lines + 1] = string.format("%3d %s (%02X)\n", i, tiles[i].name, tiles[i].raw)
    end
    local f = io.open("smoke_logs/rbmk_next.txt", "w")
    if f then
        f:write(table.concat(lines))
        f:close()
    end
end

local function report_scan(snap, title, mode)
    local body = {
        string.format("=== %s %s ===\n", title, now()),
        format_hits(snap.hits),
        dump_hot(snap),
    }
    write_log(table.concat(body), mode)
    local walls = 0
    local first
    for _, h in ipairs(snap.hits) do
        if h.kind:find("wall136", 1, true) then
            walls = walls + 1
            if not first then
                first = h
            end
        end
    end
    if first then
        return string.format("rbmk wall: %d wall hit(s), first %s @ 0x%06X", walls, first.kind, first.addr)
    end
    return "rbmk wall: no 136-tile signature (hot dump in log)"
end

return function(machine)
    if not machine or machine.system.name ~= "rbmk" then
        return
    end
    bind_keys(machine)
    ensure_pause_poll()
    ptr_tick()
    poll_skin_buttons(machine)
    apply_peek_click(machine)
    if mark_click then
        apply_mark(machine)
    end
    if seq9 and edge(5, seq9) then
        toggle_peek(machine)
    elseif seq_f9 and edge(6, seq_f9) then
        toggle_peek(machine)
    end
    hook_peek_pointer(machine)
    live_preview(machine)

    if edge(1, seq1) then
        log_map(machine)
        snap_a = snapshot_all(machine)
        local work2 = region(snap_a, "68k_work2")
        if work2 then
            write_bin("smoke_logs/rbmk_work2_A.bin", work2.data)
        end
        local msg = report_scan(snap_a, "SNAP A (deal)", "w")
        machine:popmessage(msg .. "\nCtrl+2 after drawing")
        print("[rbmk_wall] " .. msg)
    elseif edge(2, seq2) then
        local snap_b = snapshot_all(machine)
        local work2 = region(snap_b, "68k_work2")
        if work2 then
            write_bin("smoke_logs/rbmk_work2_B.bin", work2.data)
        end
        local msg = report_scan(snap_b, "SNAP B (after draw)", "a")
        if snap_a then
            write_log(string.format("=== DIFF A->B %s ===\n", now()), "a")
            for _, rb in ipairs(snap_b.regions) do
                local ra = region(snap_a, rb.name)
                if ra and #ra.data == #rb.data then
                    local text = diff_bufs(ra.data, rb.data, rb.name, rb.start)
                    write_log(text, "a")
                end
            end
            msg = msg .. " / diff written"
        else
            msg = msg .. " / no snap A (Ctrl+1 first)"
        end
        machine:popmessage(msg)
        print("[rbmk_wall] " .. msg)
    elseif edge(3, seq3) then
        local snap = snapshot_all(machine)
        local msg = report_scan(snap, "SCAN only", "a")
        machine:popmessage(msg)
        print("[rbmk_wall] " .. msg)
    end
end
