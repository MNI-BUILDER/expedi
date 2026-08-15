-- ANIME EXPEDITIONS SUMMON MONITOR v1 — text-anchored single-pass
print("🎴 AE Summon Monitor booting...")

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local API_ENDPOINT    = "http://204.12.233.39:3000/api/stocks/animeexpeditions"
local API_KEY         = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
-- ^ if the boot test prints 401 or 404, this webhook is DEAD. make a new one.

local CHECK_INTERVAL   = 1
local POST_INTERVAL    = 5      -- forced post every N s (changes post instantly)
local HEARTBEAT_INTERVAL = 30
local STATUS_INTERVAL  = 900    -- discord "still alive" ping
local AUTO_CYCLE       = false  -- true = auto-click banner tabs to read all 4
local CYCLE_INTERVAL   = 20
local FORCE_UI         = false  -- true = force the Summon ScreenGui to stay enabled

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

----------------------------------------------------------------
-- CACHE
----------------------------------------------------------------
local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999)),
    updateCounter = 0,
    lastPost = 0,
    lastHeartbeat = 0,
    lastStatus = 0,
    lastCycle = 0,
    activeBanner = "Unknown",
    banners = {},
    tabs = nil,
    tabIndex = 1
}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function getText(o)
    local ok, t = pcall(function() return o.Text end)
    if ok and type(t) == "string" then return t end
    return nil
end

local function onScreen(o)
    local cur = o
    while cur and cur ~= game do
        if cur:IsA("ScreenGui") then return cur.Enabled end
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        cur = cur.Parent
    end
    return false
end

local function inButton(o)
    local cur = o.Parent
    while cur and cur ~= game do
        if cur:IsA("GuiButton") then return true end
        cur = cur.Parent
    end
    return false
end

local function num(s)
    if not s then return nil end
    return tonumber((s:gsub("[,%s]", "")))
end

local function parseTime(t)
    if not t then return nil end
    local h = tonumber(t:match("(%d+)%s*h")) or 0
    local m = tonumber(t:match("(%d+)%s*m")) or 0
    local s = tonumber(t:match("(%d+)%s*s")) or 0
    if (h + m + s) > 0 then return h*3600 + m*60 + s end
    local a,b,c = t:match("(%d+):(%d+):(%d+)")
    if a then return tonumber(a)*3600 + tonumber(b)*60 + tonumber(c) end
    local d,e = t:match("^(%d+):(%d+)$")
    if d then return tonumber(d)*60 + tonumber(e) end
    return nil
end

local function isTimeText(t)
    return t:match("%d+%s*m,%s*%d+%s*s") or t:match("%d+%s*h,%s*%d+%s*m")
        or t:match("^%d+%s*s$") or t:match("%d+:%d+")
end

local function getGui()
    local g = PG:FindFirstChild("Summon")
    if g and FORCE_UI and g:IsA("ScreenGui") and not g.Enabled then
        pcall(function() g.Enabled = true end)
    end
    return g
end

----------------------------------------------------------------
-- SINGLE-PASS SCAN
----------------------------------------------------------------
local function scanUI()
    local gui = getGui()
    if not gui then return nil, "no Summon ScreenGui" end
    if gui:IsA("ScreenGui") and not gui.Enabled then return nil, "summon ui closed" end

    local B = {
        title = nil, subtitle = nil,
        bannerChangeNode = nil, timers = {},
        rarities = {}, pity = {}, costs = {}, packs = {}, featured = 0
    }

    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" and onScreen(d) then

            -- main banner title: full "X Banner" (tabs split it across two labels)
            local bn = t:match("^(.+)%s+Banner$")
            if bn and t ~= "Banner" and not inButton(d) and not B.title then
                B.title = t
                for _, sib in ipairs(d.Parent:GetChildren()) do
                    local st = getText(sib)
                    if sib ~= d and st and st ~= "" and not st:match("Banner$") then
                        B.subtitle = st
                        break
                    end
                end
            end

            if t == "Banner Change" then B.bannerChangeNode = d end
            if isTimeText(t) then table.insert(B.timers, d) end

            -- "Mythic Unit" / "Legendary Unit" / "Secret Unit"
            local rar = t:match("^(%a+)%s+Unit$")
            if rar then table.insert(B.rarities, {node = d, rarity = rar}) end

            if t == "[Featured]" then B.featured = B.featured + 1 end

            -- pity rows
            local pn = t:match("^(%a+)%s+Pity$")
            if pn then
                for _, sib in ipairs(d.Parent:GetChildren()) do
                    local st = getText(sib)
                    if sib ~= d and st and st:match("^[%d,]+/[%d,]+$") then
                        B.pity[pn] = st
                        break
                    end
                end
            end

            -- summon costs
            if t == "Summon" or t == "Summon 10x" then
                local btn, cur = nil, d
                while cur and cur ~= gui do
                    if cur:IsA("GuiButton") then btn = cur break end
                    cur = cur.Parent
                end
                if btn then
                    for _, sub in ipairs(btn:GetDescendants()) do
                        local stt = getText(sub)
                        if stt and stt:match("^[%d,]+$") then
                            B.costs[t == "Summon" and "single" or "ten"] = num(stt)
                            break
                        end
                    end
                end
            end

            -- currency packs: "1,000 Gems" / "2,500 Villain Coins"
            local amt, curname = t:match("^([%d,]+)%s+(%a[%w%s']*)$")
            if amt and curname and #curname <= 24 then
                table.insert(B.packs, {amount = num(amt), currency = curname})
            end
        end
    end

    if not B.title then return nil, "banner title not visible" end

    -- countdown: prefer a timer sibling of "Banner Change"
    local timerText
    if B.bannerChangeNode then
        for _, sib in ipairs(B.bannerChangeNode.Parent:GetChildren()) do
            local st = getText(sib)
            if sib ~= B.bannerChangeNode and st and isTimeText(st) then timerText = st break end
        end
    end
    if not timerText and B.timers[1] then timerText = getText(B.timers[1]) end

    -- units: name is the sibling of the rarity label
    local units, seen = {}, {}
    for _, r in ipairs(B.rarities) do
        for _, sib in ipairs(r.node.Parent:GetChildren()) do
            local st = getText(sib)
            if sib ~= r.node and st and st ~= "" and not st:match("%s+Unit$") and not st:match("^%[") then
                if not seen[st] then
                    seen[st] = true
                    table.insert(units, {name = st, rarity = r.rarity})
                end
                break
            end
        end
    end

    -- dominant currency across the shop packs
    local counts, currency, best = {}, nil, 0
    for _, p in ipairs(B.packs) do
        counts[p.currency] = (counts[p.currency] or 0) + 1
        if counts[p.currency] > best then best = counts[p.currency] currency = p.currency end
    end

    return {
        banner = B.title,
        subtitle = B.subtitle,
        units = units,
        timerText = timerText,
        timerSeconds = parseTime(timerText),
        cost = B.costs,
        currency = currency,
        featuredTags = B.featured,
        pity = B.pity,
        lastSeen = os.time()
    }
end

----------------------------------------------------------------
-- TABS / AUTO-CYCLE
----------------------------------------------------------------
local function findTabs(gui)
    local tabs = {}
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("GuiButton") then
            local parts = {}
            for _, c in ipairs(d:GetDescendants()) do
                local t = getText(c)
                if t and t ~= "" then parts[#parts+1] = t end
            end
            if #parts == 2 and (parts[1] == "Banner" or parts[2] == "Banner") then
                local label = (parts[1] == "Banner") and parts[2] or parts[1]
                table.insert(tabs, {btn = d, name = label .. " Banner"})
            end
        end
    end
    return tabs
end

local function clickTab(btn)
    local gc = getconnections or (getgenv and getgenv().getconnections)
    if not gc then return false end
    local fired = false
    pcall(function()
        for _, c in ipairs(gc(btn.MouseButton1Click)) do
            local ok = pcall(function() c:Fire() end)
            if not ok then pcall(function() c.Function() end) end
            fired = true
        end
    end)
    return fired
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
    if not DISCORD_WEBHOOK or DISCORD_WEBHOOK == "" then return end
    local ok, code = post(DISCORD_WEBHOOK,
        {["Content-Type"] = "application/json", ["User-Agent"] = "Mozilla/5.0"},
        HttpService:JSONEncode({
            content = title,
            embeds = {{description = desc, color = color or 5814783,
                       footer = {text = "AE | " .. Cache.sessionId},
                       timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")}}
        }))
    if not ok then print("  ⚠️ discord call failed: " .. tostring(code))
    elseif code ~= "204" and code ~= "200" then print("  ⚠️ discord status " .. code) end
end

local function sendToAPI(payload)
    Cache.updateCounter = Cache.updateCounter + 1
    payload.updateNumber = Cache.updateCounter
    local ok, code = post(API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. os.time(),
        {
            ["Content-Type"] = "application/json",
            ["Authorization"] = API_KEY,
            ["Cache-Control"] = "no-cache, no-store, must-revalidate",
            ["X-Session-ID"] = Cache.sessionId,
            ["X-Update-Number"] = tostring(Cache.updateCounter)
        },
        HttpService:JSONEncode(payload))
    print(ok and ("✅ POST #" .. Cache.updateCounter .. " -> " .. code)
             or ("❌ POST #" .. Cache.updateCounter .. " failed: " .. tostring(code)))
    return ok
end

local function heartbeat()
    post(API_ENDPOINT .. "/heartbeat",
        {["Content-Type"] = "application/json", ["Authorization"] = API_KEY, ["X-Session-ID"] = Cache.sessionId},
        HttpService:JSONEncode({sessionId = Cache.sessionId, status = "ALIVE", game = "animeexpeditions", timestamp = os.time()}))
end

----------------------------------------------------------------
-- PAYLOAD + CHANGE DETECTION
----------------------------------------------------------------
local function unitString(b)
    if not b or not b.units then return "" end
    local t = {}
    for _, u in ipairs(b.units) do t[#t+1] = u.name .. ":" .. u.rarity end
    table.sort(t)
    return table.concat(t, "|")
end

local function buildPayload()
    local active = Cache.banners[Cache.activeBanner]
    return {
        sessionId = Cache.sessionId,
        game = "animeexpeditions",
        timestamp = os.time(),
        playerName = LP.Name,
        userId = LP.UserId,
        activeBanner = Cache.activeBanner,
        bannerChange = active and {text = active.timerText, seconds = active.timerSeconds} or nil,
        banners = Cache.banners,
        player = active and {pity = active.pity} or nil
    }
end

----------------------------------------------------------------
-- SETUP
----------------------------------------------------------------
local function antiAFK()
    local VU = game:GetService("VirtualUser")
    LP.Idled:Connect(function()
        VU:CaptureController()
        VU:ClickButton2(Vector2.new())
    end)
end

print("🔌 http fn: " .. tostring(httpreq ~= nil))
discord("🎴 **AE MONITOR ONLINE**", "session `" .. Cache.sessionId .. "`", 5763719)
print("📨 webhook boot test sent — check the status line above")

antiAFK()

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
task.spawn(function()
    while true do
        local ok, data, err = pcall(scanUI)
        if ok and data then
            local prev = Cache.banners[data.banner]
            local changedBanner = (Cache.activeBanner ~= data.banner)
            local changedUnits  = (unitString(prev) ~= unitString(data))

            Cache.banners[data.banner] = data
            Cache.activeBanner = data.banner

            if not Cache.tabs then
                local g = getGui()
                if g then
                    Cache.tabs = findTabs(g)
                    print("🗂 tabs found: " .. #Cache.tabs)
                end
            end

            local now = os.time()
            if changedBanner or changedUnits or (now - Cache.lastPost) >= POST_INTERVAL then
                sendToAPI(buildPayload())
                Cache.lastPost = now
            end

            if changedUnits and prev then
                local lines = {}
                for _, u in ipairs(data.units) do lines[#lines+1] = "• **" .. u.name .. "** — " .. u.rarity .. " Unit" end
                discord("🔄 **BANNER ROTATED**",
                    "**" .. data.banner .. "**\n" .. (data.subtitle or "") .. "\n\n"
                    .. table.concat(lines, "\n") .. "\n\n⏱ next change: " .. tostring(data.timerText), 16729344)
            end

            if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                heartbeat() Cache.lastHeartbeat = now
            end
            if (now - Cache.lastStatus) >= STATUS_INTERVAL then
                local n = 0
                for _ in pairs(Cache.banners) do n = n + 1 end
                discord("📊 **AE STATUS**", "updates: " .. Cache.updateCounter
                    .. "\nbanners cached: " .. n .. "\nactive: " .. Cache.activeBanner, 5814783)
                Cache.lastStatus = now
            end

            if AUTO_CYCLE and Cache.tabs and #Cache.tabs > 0 and (now - Cache.lastCycle) >= CYCLE_INTERVAL then
                Cache.tabIndex = (Cache.tabIndex % #Cache.tabs) + 1
                local tab = Cache.tabs[Cache.tabIndex]
                if clickTab(tab.btn) then print("↔️ switched to " .. tab.name)
                else print("⚠️ getconnections unavailable — auto-cycle off") AUTO_CYCLE = false end
                Cache.lastCycle = now
            end

            print("🎴 " .. data.banner .. " | " .. #data.units .. " units | "
                .. tostring(data.timerText) .. " | " .. tostring(data.currency))
        else
            print("⏸ " .. tostring(data or err or "scan failed"))
        end
        task.wait(CHECK_INTERVAL)
    end
end)

print("🚀 MONITORING STARTED | session " .. Cache.sessionId)
