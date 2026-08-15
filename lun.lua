-- ANIME EXPEDITIONS SUMMON MONITOR v3 — verified open + blacklist + no empty posts
print("🎴 AE Summon Monitor v3 booting...")

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local GuiService  = game:GetService("GuiService")
local VIM         = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local API_ENDPOINT    = "http://204.12.233.39:3000/api/stocks/animeexpeditions"
local API_KEY         = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local AUTO_OPEN   = true
local AUTO_CYCLE  = true
local OPEN_BUTTON_PATH = ""    -- paste an exact GetFullName here to skip the search
local GUI_BLACKLIST = {        -- never click inside these ScreenGuis
    TeleportIcons = true, Teleport = true, TeleportIcon = true,
    LevelIcons = true, Shop = true, Gamepasses = true
}

local TAB_DWELL    = 6
local SETTLE_WAIT  = 1.5
local OPEN_VERIFY  = 1.3       -- how long to wait before judging a click
local OPEN_COOLDOWN= 4
local MAX_OPEN_FAILS = 8
local CHECK_INTERVAL = 1
local POST_INTERVAL  = 5
local HEARTBEAT_INTERVAL = 30
local STATUS_INTERVAL = 900
local ALLOW_EMPTY_POST = false
local DEBUG = true

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999)),
    updateCounter = 0,
    lastPost = 0, lastHeartbeat = 0, lastStatus = 0, lastOpenTry = 0,
    activeBanner = "Unknown",
    banners = {}, order = {},
    tabs = {}, openBtn = nil, badBtns = {}, openFails = 0, cycling = false
}

local function dbg(s) if DEBUG then print("   " .. s) end end

----------------------------------------------------------------
-- BASICS
----------------------------------------------------------------
local function getText(o)
    local ok, t = pcall(function() return o.Text end)
    if ok and type(t) == "string" then return t end
    return nil
end

local function visible(o)
    local cur = o
    while cur and cur ~= game do
        if cur:IsA("ScreenGui") then return cur.Enabled end
        if cur:IsA("CanvasGroup") then
            local ok, g = pcall(function() return cur.GroupTransparency end)
            if ok and g >= 0.95 then return false end
        end
        if cur:IsA("GuiObject") then
            if not cur.Visible then return false end
            if cur.AbsoluteSize.X <= 1 or cur.AbsoluteSize.Y <= 1 then return false end
        end
        cur = cur.Parent
    end
    return false
end

local function num(s) if not s then return nil end return tonumber((s:gsub("[,%s]",""))) end

local function parseTime(t)
    if not t then return nil end
    local h = tonumber(t:match("(%d+)%s*h")) or 0
    local m = tonumber(t:match("(%d+)%s*m")) or 0
    local s = tonumber(t:match("(%d+)%s*s")) or 0
    if (h+m+s) > 0 then return h*3600 + m*60 + s end
    local a,b,c = t:match("(%d+):(%d+):(%d+)")
    if a then return tonumber(a)*3600 + tonumber(b)*60 + tonumber(c) end
    local d,e = t:match("^(%d+):(%d+)$")
    if d then return tonumber(d)*60 + tonumber(e) end
    return nil
end

local function isTimeText(t)
    return t:match("%d+%s*m,%s*%d+%s*s") or t:match("%d+%s*h,%s*%d+%s*m") or t:match("%d+:%d+")
end

local function nearestButton(node, stopAt)
    local cur = node
    while cur and cur ~= stopAt and cur ~= game do
        if cur:IsA("GuiButton") then return cur end
        cur = cur.Parent
    end
    return nil
end

local function getGui() return PG:FindFirstChild("Summon") end

local function panelShowing()
    local gui = getGui()
    if not gui or (gui:IsA("ScreenGui") and not gui.Enabled) then return false end
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "Banner" and t:match("^.+%s+Banner$") and visible(d) then return true end
    end
    return false
end

----------------------------------------------------------------
-- CLICK
----------------------------------------------------------------
local function clickGui(btn)
    local gc = getconnections
    if gc then
        local ok = pcall(function()
            local conns = gc(btn.MouseButton1Click)
            if #conns == 0 then error("none") end
            for _, c in ipairs(conns) do
                if c.Fire then c:Fire() else c.Function() end
            end
        end)
        if ok then return "signal" end
    end
    if firesignal then
        local ok = pcall(function() firesignal(btn.MouseButton1Click) end)
        if ok then return "firesignal" end
    end
    local ok = pcall(function()
        local p, s = btn.AbsolutePosition, btn.AbsoluteSize
        local sg = btn
        while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
        local yOff = (sg and sg.IgnoreGuiInset) and 0 or GuiService:GetGuiInset().Y
        local x, y = p.X + s.X/2, p.Y + s.Y/2 + yOff
        VIM:SendMouseButtonEvent(x, y, 0, true,  game, 1)
        task.wait(0.06)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
    return ok and "virtual" or nil
end

----------------------------------------------------------------
-- OPEN (verified)
----------------------------------------------------------------
local function openCandidates()
    local gui, out, seen = getGui(), {}, {}
    for _, sg in ipairs(PG:GetChildren()) do
        if sg ~= gui and sg:IsA("ScreenGui") and sg.Enabled and not GUI_BLACKLIST[sg.Name] then
            for _, d in ipairs(sg:GetDescendants()) do
                local t = getText(d)
                if t and t:lower():gsub("[%s'’]","") == "summon" and visible(d) then
                    local btn = nearestButton(d, sg) or (d:IsA("GuiButton") and d or nil)
                    if btn and not seen[btn] and not Cache.badBtns[btn] then
                        seen[btn] = true
                        out[#out+1] = {btn = btn, path = btn:GetFullName()}
                    end
                end
            end
        end
    end
    return out
end

local function ensureOpen()
    if panelShowing() then Cache.openFails = 0 return true end
    if not AUTO_OPEN then return false end
    if os.clock() - Cache.lastOpenTry < OPEN_COOLDOWN then return false end
    Cache.lastOpenTry = os.clock()

    if Cache.openFails >= MAX_OPEN_FAILS then
        print("🛑 can't find the Summon button — open the menu by hand, the monitor will pick it up")
        Cache.openFails = 0
        Cache.badBtns = {}
        task.wait(20)
        return false
    end

    local gui = getGui()
    if gui and gui:IsA("ScreenGui") and not gui.Enabled then
        pcall(function() gui.Enabled = true end)
        task.wait(0.5)
        if panelShowing() then dbg("opened via Enabled=true") return true end
    end

    if OPEN_BUTTON_PATH ~= "" and not Cache.openBtn then
        for _, sg in ipairs(PG:GetDescendants()) do
            if sg:GetFullName() == OPEN_BUTTON_PATH then Cache.openBtn = sg break end
        end
    end

    if Cache.openBtn and Cache.openBtn.Parent then
        clickGui(Cache.openBtn)
        task.wait(OPEN_VERIFY)
        if panelShowing() then return true end
        dbg("remembered button stopped working, re-searching")
        Cache.openBtn = nil
    end

    for _, c in ipairs(openCandidates()) do
        local m = clickGui(c.btn)
        task.wait(OPEN_VERIFY)
        if panelShowing() then
            Cache.openBtn = c.btn
            Cache.openFails = 0
            print("🔓 OPEN BUTTON FOUND (" .. tostring(m) .. "): " .. c.path)
            return true
        end
        Cache.badBtns[c.btn] = true
        dbg("✗ no panel after " .. c.path .. " — blacklisted")
    end

    Cache.openFails = Cache.openFails + 1
    return false
end

----------------------------------------------------------------
-- PANEL RESOLVE + SCAN
----------------------------------------------------------------
local function resolvePanel()
    local gui = getGui()
    if not gui then return nil end
    local titleNode
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "Banner" and t:match("^.+%s+Banner$") and visible(d) then
            if not nearestButton(d, gui) then titleNode = d break end
        end
    end
    if not titleNode then return nil end
    local cur = titleNode
    for _ = 1, 8 do
        cur = cur.Parent
        if not cur or cur:IsA("ScreenGui") then break end
        local rar, vp = 0, 0
        for _, d in ipairs(cur:GetDescendants()) do
            local t = getText(d)
            if t and t:match("^%a+%s+Unit$") then rar = rar + 1 end
            if d:IsA("ViewportFrame") then vp = vp + 1 end
        end
        if rar >= 1 and vp >= 1 then return cur, titleNode end
    end
    return nil, titleNode
end

local function scanPanel()
    local panel, titleNode = resolvePanel()
    if not titleNode then return nil end
    local scope = panel or titleNode.Parent
    local title = getText(titleNode)
    local subtitle, timerText, changeNode
    local rarities, pity, costs, packs, featured = {}, {}, {}, {}, 0

    for _, sib in ipairs(titleNode.Parent:GetChildren()) do
        local st = getText(sib)
        if sib ~= titleNode and st and st ~= "" and not st:match("Banner$") then subtitle = st break end
    end

    for _, d in ipairs(scope:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" and visible(d) then
            if t == "Banner Change" then changeNode = d end
            if isTimeText(t) and not timerText then timerText = t end
            local rar = t:match("^(%a+)%s+Unit$")
            if rar then rarities[#rarities+1] = {node = d, rarity = rar, x = d.AbsolutePosition.X} end
            if t == "[Featured]" then featured = featured + 1 end
            local pn = t:match("^(%a+)%s+Pity$")
            if pn then
                for _, sib in ipairs(d.Parent:GetChildren()) do
                    local st = getText(sib)
                    if sib ~= d and st and st:match("^[%d,]+/[%d,]+$") then pity[pn] = st break end
                end
            end
            if t == "Summon" or t == "Summon 10x" then
                local btn = nearestButton(d, scope)
                if btn then
                    local best, raw = nil, {}
                    for _, sub in ipairs(btn:GetDescendants()) do
                        local stt = getText(sub)
                        if stt and stt:match("^[%d,]+$") and visible(sub) then
                            raw[#raw+1] = stt
                            local v = num(stt)
                            if v and (not best or v > best) then best = v end
                        end
                    end
                    local key = (t == "Summon") and "single" or "ten"
                    costs[key] = best
                    costs[key .. "Raw"] = table.concat(raw, "/")
                end
            end
            local amt, cn = t:match("^([%d,]+)%s+(%a[%w%s']*)$")
            if amt and cn and #cn <= 24 then packs[#packs+1] = {amount = num(amt), currency = cn} end
        end
    end

    if changeNode then
        for _, sib in ipairs(changeNode.Parent:GetChildren()) do
            local st = getText(sib)
            if sib ~= changeNode and st and isTimeText(st) then timerText = st break end
        end
    end

    table.sort(rarities, function(a,b) return a.x < b.x end)
    local units, seen = {}, {}
    for _, r in ipairs(rarities) do
        for _, sib in ipairs(r.node.Parent:GetChildren()) do
            local st = getText(sib)
            if sib ~= r.node and st and st ~= "" and not st:match("%s+Unit$")
               and not st:match("^%[") and visible(sib) then
                if not seen[st] then
                    seen[st] = true
                    units[#units+1] = {name = st, rarity = r.rarity}
                end
                break
            end
        end
    end

    local counts, currency, best = {}, nil, 0
    for _, p in ipairs(packs) do
        counts[p.currency] = (counts[p.currency] or 0) + 1
        if counts[p.currency] > best then best = counts[p.currency] currency = p.currency end
    end

    return {
        banner = title, subtitle = subtitle,
        units = units, unitCount = #units,
        timerText = timerText, timerSeconds = parseTime(timerText),
        cost = costs, currency = currency,
        featuredTags = featured, pity = pity, lastSeen = os.time()
    }
end

----------------------------------------------------------------
-- TABS (any button holding a "Banner" label)
----------------------------------------------------------------
local function findTabs()
    local gui = getGui()
    if not gui then return {} end
    local tabs, seen = {}, {}
    for _, d in ipairs(gui:GetDescendants()) do
        if getText(d) == "Banner" then
            local btn = nearestButton(d, gui)
            if btn and not seen[btn] then
                local name
                for _, sib in ipairs(d.Parent:GetChildren()) do
                    local st = getText(sib)
                    if sib ~= d and st and st ~= "" and st ~= "Banner" then name = st break end
                end
                if name then
                    seen[btn] = true
                    tabs[#tabs+1] = {btn = btn, name = name .. " Banner", x = btn.AbsolutePosition.X}
                end
            end
        end
    end
    table.sort(tabs, function(a,b) return a.x < b.x end)
    return tabs
end

----------------------------------------------------------------
-- NETWORK
----------------------------------------------------------------
local function post(url, headers, body)
    if not httpreq then return false, "no http fn" end
    local ok, res = pcall(httpreq, {Url = url, Method = "POST", Headers = headers, Body = body})
    if not ok then return false, tostring(res) end
    local code = "?"
    pcall(function() code = tostring(res.StatusCode) end)
    return true, code
end

local function discord(title, desc, color)
    local ok, code = post(DISCORD_WEBHOOK,
        {["Content-Type"]="application/json", ["User-Agent"]="Mozilla/5.0"},
        HttpService:JSONEncode({content = title, embeds = {{description = desc, color = color or 5814783,
            footer = {text = "AE | " .. Cache.sessionId}, timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")}}}))
    if not ok then print("⚠️ discord failed: " .. tostring(code))
    elseif code ~= "204" and code ~= "200" then print("⚠️ discord status " .. code) end
end

local function bannerCount()
    local n = 0
    for _ in pairs(Cache.banners) do n = n + 1 end
    return n
end

local function sendToAPI()
    local n = bannerCount()
    if n == 0 and not ALLOW_EMPTY_POST then
        print("⏭ post skipped — no banner data yet (not overwriting the API)")
        return
    end
    Cache.updateCounter = Cache.updateCounter + 1
    local now = os.time()
    for name, b in pairs(Cache.banners) do
        b.ageSeconds = now - (b.lastSeen or now)
        b.isActive = (name == Cache.activeBanner)
    end
    local active = Cache.banners[Cache.activeBanner]
    local payload = {
        sessionId = Cache.sessionId, game = "animeexpeditions",
        updateNumber = Cache.updateCounter, timestamp = now,
        playerName = LP.Name, userId = LP.UserId,
        activeBanner = Cache.activeBanner,
        bannerOrder = Cache.order, bannerCount = n,
        bannerChange = active and {text = active.timerText, seconds = active.timerSeconds} or nil,
        banners = Cache.banners,
        player = active and {pity = active.pity} or nil
    }
    local ok, code = post(API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. now, {
        ["Content-Type"]="application/json", ["Authorization"]=API_KEY,
        ["Cache-Control"]="no-cache, no-store, must-revalidate",
        ["X-Session-ID"]=Cache.sessionId, ["X-Update-Number"]=tostring(Cache.updateCounter)
    }, HttpService:JSONEncode(payload))
    print(ok and ("✅ POST #"..Cache.updateCounter.." -> "..code.." | banners: "..n)
             or ("❌ POST failed: "..tostring(code)))
    Cache.lastPost = now
end

local function heartbeat()
    post(API_ENDPOINT .. "/heartbeat",
        {["Content-Type"]="application/json", ["Authorization"]=API_KEY, ["X-Session-ID"]=Cache.sessionId},
        HttpService:JSONEncode({sessionId=Cache.sessionId, status="ALIVE", game="animeexpeditions", timestamp=os.time()}))
end

----------------------------------------------------------------
-- RECORD
----------------------------------------------------------------
local function unitString(b)
    if not b or not b.units then return "" end
    local t = {}
    for _, u in ipairs(b.units) do t[#t+1] = u.name .. ":" .. u.rarity end
    table.sort(t)
    return table.concat(t, "|")
end

local function record(data, expect)
    if not data or not data.banner then return false end
    if expect and data.banner ~= expect then
        dbg("⚠️ clicked " .. expect .. " but panel reads " .. data.banner .. " — skipped")
        return false
    end
    local prev = Cache.banners[data.banner]
    local changed = (unitString(prev) ~= unitString(data))
    if not prev then
        Cache.order[#Cache.order+1] = data.banner
        print("🆕 cached " .. data.banner .. " (" .. data.unitCount .. " units)")
    end
    Cache.banners[data.banner] = data
    Cache.activeBanner = data.banner
    if changed and prev then
        local lines = {}
        for _, u in ipairs(data.units) do lines[#lines+1] = "• **"..u.name.."** — "..u.rarity end
        discord("🔄 **BANNER ROTATED**", "**"..data.banner.."**\n"..(data.subtitle or "").."\n\n"
            ..table.concat(lines,"\n").."\n\n⏱ "..tostring(data.timerText), 16729344)
    end
    return changed
end

----------------------------------------------------------------
-- BOOT
----------------------------------------------------------------
print("🔌 http fn: " .. tostring(httpreq ~= nil))
local names = {}
for _, sg in ipairs(PG:GetChildren()) do names[#names+1] = sg.Name end
print("🖥 PlayerGui: " .. table.concat(names, ", "))
for _, c in ipairs(openCandidates()) do print("   candidate: " .. c.path) end

discord("🎴 **AE MONITOR v3 ONLINE**", "session `"..Cache.sessionId.."`", 5763719)
pcall(function()
    local VU = game:GetService("VirtualUser")
    LP.Idled:Connect(function() VU:CaptureController() VU:ClickButton2(Vector2.new()) end)
end)

for _ = 1, 5 do
    if ensureOpen() then break end
    task.wait(1)
end
Cache.tabs = findTabs()
print("🗂 tabs: " .. #Cache.tabs .. (#Cache.tabs > 0 and (" -> " .. (function()
    local t = {} for _, x in ipairs(Cache.tabs) do t[#t+1] = x.name end return table.concat(t, ", ")
end)()) or ""))

----------------------------------------------------------------
-- CYCLE
----------------------------------------------------------------
if AUTO_CYCLE then
    task.spawn(function()
        while true do
            if #Cache.tabs == 0 then
                if ensureOpen() then Cache.tabs = findTabs() end
                task.wait(3)
            else
                for _, tab in ipairs(Cache.tabs) do
                    if panelShowing() then
                        Cache.cycling = true
                        local m = clickGui(tab.btn)
                        dbg("→ " .. tab.name .. " (" .. tostring(m) .. ")")
                        task.wait(SETTLE_WAIT)
                        local ok, data = pcall(scanPanel)
                        if ok and data and record(data, tab.name) then sendToAPI() end
                        Cache.cycling = false
                    else
                        ensureOpen()
                    end
                    task.wait(TAB_DWELL)
                end
            end
        end
    end)
end

----------------------------------------------------------------
-- MAIN
----------------------------------------------------------------
task.spawn(function()
    while true do
        if not panelShowing() then
            ensureOpen()
        elseif not Cache.cycling then
            local ok, data = pcall(scanPanel)
            if ok and data then
                if record(data) then sendToAPI() end
                print("🎴 "..data.banner.." | "..data.unitCount.." units | "..tostring(data.timerText)
                    .." | "..tostring(data.currency).." | cost "..tostring(data.cost.single)
                    .."/"..tostring(data.cost.ten).." raw("..tostring(data.cost.singleRaw)
                    ..","..tostring(data.cost.tenRaw)..")")
            end
        end
        local now = os.time()
        if (now - Cache.lastPost) >= POST_INTERVAL then sendToAPI() end
        if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then heartbeat() Cache.lastHeartbeat = now end
        if (now - Cache.lastStatus) >= STATUS_INTERVAL then
            discord("📊 **AE STATUS**", "updates: "..Cache.updateCounter.."\nbanners: "..bannerCount()
                .."\nactive: "..Cache.activeBanner)
            Cache.lastStatus = now
        end
        task.wait(CHECK_INTERVAL)
    end
end)

print("🚀 v3 RUNNING | session " .. Cache.sessionId)
