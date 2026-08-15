-- ANIME EXPEDITIONS SUMMON MONITOR v6 (FINAL) — manual UI, teleport only, no clicking
print("🎴 AE Summon Monitor v6 booting...")

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

local TELEPORT_TO_NPC   = true    -- walk to the summon NPC at boot + after respawn
local TELEPORT_ON_SPAWN = true
local PROMPT_WORDS      = {"summon", "open menu"}
local EXPECTED_BANNERS  = 4

local CHECK_INTERVAL     = 1
local POST_INTERVAL      = 5
local HEARTBEAT_INTERVAL = 30
local STATUS_INTERVAL    = 900
local STALE_AFTER        = 900    -- flag a cached banner older than this

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999)),
    updateCounter = 0, lastPost = 0, lastHeartbeat = 0, lastStatus = 0,
    activeBanner = "Unknown", banners = {}, order = {},
    fullSetAnnounced = false, wasOpen = false
}

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
-- TELEPORT TO NPC (only automation left)
----------------------------------------------------------------
local function promptMatches(p)
    local ot = string.lower(tostring(p.ObjectText or ""))
    local at = string.lower(tostring(p.ActionText or ""))
    for _, wd in ipairs(PROMPT_WORDS) do
        if ot:find(wd, 1, true) or at:find(wd, 1, true) then return true end
    end
    return false
end

local function promptPos(p)
    local par = p.Parent
    if not par then return nil end
    if par:IsA("BasePart") then return par.Position end
    if par:IsA("Attachment") then return par.WorldPosition end
    if par:IsA("Model") then
        local ok, cf = pcall(function() return par:GetPivot() end)
        if ok then return cf.Position end
    end
    return nil
end

local function findPrompt()
    local best, bestPos
    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and promptMatches(d) then
                local pos = promptPos(d)
                if pos and not best then best, bestPos = d, pos end
            end
        end
    end)
    return best, bestPos
end

local function teleportToNPC()
    if not TELEPORT_TO_NPC then return false end
    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp then print("⚠️ no character yet") return false end
    local prompt, pos = findPrompt()
    if not prompt or not pos then
        print("⚠️ summon NPC prompt not found — walk over manually")
        return false
    end
    local ok = pcall(function() hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 5)) end)
    if ok then
        print("🚶 teleported to summon NPC (" .. tostring(prompt.ObjectText) .. ")")
        return true
    end
    return false
end

----------------------------------------------------------------
-- SCAN
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

local function scanAll()
    local gui = getGui()
    if not gui then return nil end
    local panel, titleNode = resolvePanel()
    if not titleNode then return nil end
    local scope = panel or titleNode.Parent

    local title, subtitle, timerText, changeNode = getText(titleNode), nil, nil, nil
    local rarities, featured = {}, 0

    for _, sib in ipairs(titleNode.Parent:GetChildren()) do
        local st = getText(sib)
        if sib ~= titleNode and st and st ~= "" and not st:match("Banner$") then subtitle = st break end
    end

    -- panel scope: units + timer
    for _, d in ipairs(scope:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" and visible(d) then
            if t == "Banner Change" then changeNode = d end
            if isTimeText(t) and not timerText then timerText = t end
            local rar = t:match("^(%a+)%s+Unit$")
            if rar then rarities[#rarities+1] = {node = d, rarity = rar, x = d.AbsolutePosition.X} end
            if t == "[Featured]" then featured = featured + 1 end
        end
    end

    -- gui scope: costs, packs, pity
    local pity, costs, packs = {}, {}, {}
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" and visible(d) then
            local pn = t:match("^(%a+)%s+Pity$")
            if pn then
                for _, sib in ipairs(d.Parent:GetChildren()) do
                    local st = getText(sib)
                    if sib ~= d and st and st:match("^[%d,]+/[%d,]+$") then pity[pn] = st break end
                end
            end
            if t == "Summon" or t == "Summon 10x" then
                local btn = nearestButton(d, gui)
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
        banner = title, subtitle = subtitle, units = units, unitCount = #units,
        timerText = timerText, timerSeconds = parseTime(timerText),
        cost = costs, currency = currency, featuredTags = featured,
        pity = pity, lastSeen = os.time()
    }
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
    if not ok then print("⚠️ discord failed: " .. tostring(code)) end
end

local function bannerCount()
    local n = 0
    for _ in pairs(Cache.banners) do n = n + 1 end
    return n
end

local function sendToAPI()
    local n = bannerCount()
    if n == 0 then return end
    Cache.updateCounter = Cache.updateCounter + 1
    local now = os.time()
    for name, b in pairs(Cache.banners) do
        b.ageSeconds = now - (b.lastSeen or now)
        b.isActive = (name == Cache.activeBanner)
        b.stale = b.ageSeconds > STALE_AFTER
    end
    local active = Cache.banners[Cache.activeBanner]
    local ok, code = post(API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. now, {
        ["Content-Type"]="application/json", ["Authorization"]=API_KEY,
        ["Cache-Control"]="no-cache, no-store, must-revalidate",
        ["X-Session-ID"]=Cache.sessionId, ["X-Update-Number"]=tostring(Cache.updateCounter)
    }, HttpService:JSONEncode({
        sessionId = Cache.sessionId, game = "animeexpeditions",
        updateNumber = Cache.updateCounter, timestamp = now,
        playerName = LP.Name, userId = LP.UserId,
        activeBanner = Cache.activeBanner, bannerOrder = Cache.order,
        bannerCount = n, expectedBanners = EXPECTED_BANNERS,
        bannerChange = active and {text = active.timerText, seconds = active.timerSeconds} or nil,
        banners = Cache.banners,
        player = active and {pity = active.pity} or nil
    }))
    print(ok and ("✅ POST #"..Cache.updateCounter.." -> "..code.." | banners: "..n.."/"..EXPECTED_BANNERS)
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

local function missingList()
    local have = {}
    for n in pairs(Cache.banners) do have[n] = true end
    local out = {}
    for _, n in ipairs({"Beginner's Banner","Villain Banner","Standard Banner","Mini Banner"}) do
        if not have[n] then out[#out+1] = n end
    end
    return out
end

local function record(data)
    if not data or not data.banner then return false end
    local prev = Cache.banners[data.banner]
    local changed = (unitString(prev) ~= unitString(data))

    if not prev then
        Cache.order[#Cache.order+1] = data.banner
        print("🆕 CACHED " .. data.banner .. " — " .. data.unitCount .. " units | "
            .. tostring(data.currency) .. " | " .. tostring(data.cost.single) .. "/"
            .. tostring(data.cost.ten) .. "   [" .. (bannerCount()) .. "/" .. EXPECTED_BANNERS .. "]")
        local miss = missingList()
        if #miss > 0 then print("   still need: " .. table.concat(miss, ", ")) end
    end

    Cache.banners[data.banner] = data
    Cache.activeBanner = data.banner

    if changed and prev then
        local lines = {}
        for _, u in ipairs(data.units) do lines[#lines+1] = "• **"..u.name.."** — "..u.rarity end
        discord("🔄 **BANNER ROTATED**", "**"..data.banner.."**\n"..(data.subtitle or "").."\n\n"
            ..table.concat(lines,"\n").."\n\n⏱ "..tostring(data.timerText), 16729344)
    end

    if not Cache.fullSetAnnounced and bannerCount() >= EXPECTED_BANNERS then
        Cache.fullSetAnnounced = true
        print("🎉 ALL " .. EXPECTED_BANNERS .. " BANNERS CACHED — payload is complete")
        discord("🎉 **FULL SET CACHED**", "all " .. EXPECTED_BANNERS .. " banners in the payload", 5763719)
    end
    return changed
end

----------------------------------------------------------------
-- BOOT
----------------------------------------------------------------
print("🔌 http=" .. tostring(httpreq ~= nil))
discord("🎴 **AE MONITOR v6 ONLINE**", "session `"..Cache.sessionId.."`", 5763719)

pcall(function()
    local VU = game:GetService("VirtualUser")
    LP.Idled:Connect(function() VU:CaptureController() VU:ClickButton2(Vector2.new()) end)
end)

if TELEPORT_ON_SPAWN then
    LP.CharacterAdded:Connect(function()
        task.wait(6)
        print("♻️ respawned")
        teleportToNPC()
    end)
end

teleportToNPC()
print("👉 press E at the NPC, then click each banner tab once — every one you open gets cached")

----------------------------------------------------------------
-- MAIN
----------------------------------------------------------------
task.spawn(function()
    while true do
        local open = panelShowing()
        if open then
            if not Cache.wasOpen then print("📂 summon menu open") Cache.wasOpen = true end
            local ok, data = pcall(scanAll)
            if ok and data then
                if record(data) then sendToAPI() end
                print("🎴 "..data.banner.." | "..data.unitCount.." units | "..tostring(data.timerText)
                    .." | "..tostring(data.currency).." | "..tostring(data.cost.single)
                    .."/"..tostring(data.cost.ten).." | cached "..bannerCount().."/"..EXPECTED_BANNERS)
            end
        elseif Cache.wasOpen then
            Cache.wasOpen = false
            print("📁 menu closed — serving " .. bannerCount() .. " cached banners")
        end

        local now = os.time()
        if (now - Cache.lastPost) >= POST_INTERVAL then sendToAPI() end
        if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then heartbeat() Cache.lastHeartbeat = now end
        if (now - Cache.lastStatus) >= STATUS_INTERVAL then
            discord("📊 **AE STATUS**", "updates: "..Cache.updateCounter.."\nbanners: "..bannerCount()
                .."/"..EXPECTED_BANNERS.."\nactive: "..Cache.activeBanner)
            Cache.lastStatus = now
        end
        task.wait(CHECK_INTERVAL)
    end
end)

print("🚀 v6 RUNNING | session " .. Cache.sessionId)
