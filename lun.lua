-- ANIME EXPEDITIONS COMBINED MONITOR v1 — Summon + Gold Shop, single endpoint
print("🎴🪙 AE Combined Monitor booting...")

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

local SUMMON_TAB_CYCLE = true    -- auto-switch banner tabs
local GOLD_FORCE_TAB   = true    -- force Gold Shop tab (never Cosmetic)
local GOLD_AUTO_SCROLL = true
local TARGET_SHOP      = "Gold Shop"
local EXPECTED_BANNERS = 4

local TAB_DWELL      = 5
local VERIFY_WINDOW  = 2.2
local CHECK_INTERVAL = 1
local POST_INTERVAL  = 10
local HEARTBEAT_INTERVAL = 30
local STATUS_INTERVAL    = 900
local STALE_AFTER    = 1800
local DEBUG = true

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999)),
    updateCounter = 0, lastPost = 0, lastHeartbeat = 0, lastStatus = 0,
    -- summon
    banners = {}, bannerOrder = {}, activeBanner = "Unknown",
    summonCycling = false, summonClickMethod = nil, summonWasOpen = false,
    fullSetAnnounced = false,
    -- gold shop
    gold = nil, goldGui = nil, goldWasOpen = false, goldClickMethod = nil
}

local function dbg(s) if DEBUG then print("   " .. s) end end

----------------------------------------------------------------
-- SHARED HELPERS
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
    local l = t:lower():gsub("hours?","h"):gsub("hrs?","h")
        :gsub("minutes?","m"):gsub("mins?","m"):gsub("seconds?","s"):gsub("secs?","s")
    local h = tonumber(l:match("(%d+)%s*h")) or 0
    local m = tonumber(l:match("(%d+)%s*m")) or 0
    local s = tonumber(l:match("(%d+)%s*s")) or 0
    if (h+m+s) > 0 then return h*3600 + m*60 + s end
    local a,b,c = t:match("(%d+):(%d+):(%d+)")
    if a then return tonumber(a)*3600 + tonumber(b)*60 + tonumber(c) end
    local d,e = t:match("^(%d+):(%d+)$")
    if d then return tonumber(d)*60 + tonumber(e) end
    return nil
end

local function isTimeText(t)
    local l = t:lower()
    if l:match("%d+%s*m,%s*%d+%s*s") or l:match("%d+%s*h,%s*%d+%s*m") then return true end
    if l:match("%d+%s*:%s*%d+") then return true end
    if l:match("%d+%s*hour") or l:match("%d+%s*minute") or l:match("%d+%s*second") then return true end
    return false
end

local function nearestButton(node, stopAt)
    local cur = node
    while cur and cur ~= stopAt and cur ~= game do
        if cur:IsA("GuiButton") then return cur end
        cur = cur.Parent
    end
    return nil
end

local function waitFor(verify, timeout)
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or VERIFY_WINDOW) do
        local ok, r = pcall(verify)
        if ok and r then return true end
        task.wait(0.15)
    end
    return false
end

local function trySignals(btn, verify)
    local gc = getconnections
    if gc then
        for _, sig in ipairs({"Activated","MouseButton1Click","MouseButton1Down"}) do
            local fired = false
            pcall(function()
                for _, c in ipairs(gc(btn[sig])) do
                    fired = true
                    pcall(function() if c.Fire then c:Fire() else c.Function() end end)
                end
            end)
            if fired and waitFor(verify) then return "gc:" .. sig end
        end
    end
    if firesignal then
        for _, sig in ipairs({"Activated","MouseButton1Click"}) do
            local ok = pcall(function() firesignal(btn[sig]) end)
            if ok and waitFor(verify) then return "fs:" .. sig end
        end
    end
    local ok = pcall(function()
        local pos, sz = btn.AbsolutePosition, btn.AbsoluteSize
        local sg = btn
        while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
        local yOff = (sg and sg.IgnoreGuiInset) and 0 or GuiService:GetGuiInset().Y
        local x, y = pos.X + sz.X/2, pos.Y + sz.Y/2 + yOff
        VIM:SendMouseMoveEvent(x, y, game)
        task.wait(0.1)
        VIM:SendMouseButtonEvent(x, y, 0, true,  game, 1)
        task.wait(0.1)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
    if ok and waitFor(verify) then return "virtual" end
    return nil
end

----------------------------------------------------------------
-- SUMMON
----------------------------------------------------------------
local function summonGui() return PG:FindFirstChild("Summon") end

local function summonOpen()
    local gui = summonGui()
    if not gui or (gui:IsA("ScreenGui") and not gui.Enabled) then return false end
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "Banner" and t:match("^.+%s+Banner$") and visible(d) then return true end
    end
    return false
end

local function resolveBannerPanel()
    local gui = summonGui()
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

local function currentBannerTitle()
    local _, node = resolveBannerPanel()
    return node and getText(node) or nil
end

local function scanSummon()
    local gui = summonGui()
    if not gui then return nil end
    local panel, titleNode = resolveBannerPanel()
    if not titleNode then return nil end
    local scope = panel or titleNode.Parent

    local title, subtitle, timerText, changeNode = getText(titleNode), nil, nil, nil
    local rarities, featured = {}, 0

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
        end
    end

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

local function findBannerTabs()
    local gui = summonGui()
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
-- GOLD SHOP
----------------------------------------------------------------
local function findGoldGui()
    for _, sg in ipairs(PG:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled then
            for _, d in ipairs(sg:GetDescendants()) do
                local t = getText(d)
                if t and visible(d) then
                    if t:lower():find("shop restock", 1, true) then return sg end
                    if t:match("^%d+%s*[Ll]eft") then return sg end
                end
            end
        end
    end
    return nil
end

local function goldOpen()
    local gui = Cache.goldGui
    if not gui or not gui.Parent or (gui:IsA("ScreenGui") and not gui.Enabled) then
        Cache.goldGui = findGoldGui()
        gui = Cache.goldGui
    end
    if not gui then return false end
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and visible(d) and (t:lower():find("shop restock",1,true) or t:match("^%d+%s*[Ll]eft")) then
            return true
        end
    end
    return false
end

local function goldHeader()
    local gui = Cache.goldGui
    if not gui then return nil end
    local best, bestSize
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and t:match("^.+%s+[Ss]hop$") and visible(d) and not nearestButton(d, gui) then
            local sz = 0
            pcall(function() sz = d.TextSize end)
            if not bestSize or sz > bestSize then best, bestSize = t, sz end
        end
    end
    return best
end

local function ensureGoldTab()
    if not GOLD_FORCE_TAB then return true end
    if goldHeader() == TARGET_SHOP then return true end
    local gui = Cache.goldGui
    if not gui then return false end
    for _, d in ipairs(gui:GetDescendants()) do
        if getText(d) == TARGET_SHOP and visible(d) then
            local btn = nearestButton(d, gui)
            if btn then
                local m = trySignals(btn, function() return goldHeader() == TARGET_SHOP end)
                if m then
                    if not Cache.goldClickMethod then
                        Cache.goldClickMethod = m
                        print("🖱 gold tab via " .. m)
                    end
                    return true
                end
            end
        end
    end
    return false
end

local function cardRootFrom(node, gui)
    local cur = node
    for _ = 1, 6 do
        cur = cur.Parent
        if not cur or cur == gui or cur:IsA("ScreenGui") then break end
        local texts = 0
        for _, d in ipairs(cur:GetDescendants()) do
            local t = getText(d)
            if t and t ~= "" and visible(d) then texts = texts + 1 end
        end
        if texts >= 4 then return cur end
    end
    return nil
end

local function readCard(card)
    local stock, price, buyNode, soldOut = nil, nil, nil, false
    local words, numbers = {}, {}
    local icon, iconArea = nil, 0

    for _, d in ipairs(card:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" and visible(d) then
            local n = t:match("^(%d+)%s*[Ll]eft")
            if n then stock = tonumber(n)
            elseif t:lower() == "buy" then buyNode = d
            elseif t:lower():find("out of stock",1,true) or t:lower():find("sold out",1,true) then soldOut = true
            elseif t:match("^[%d,]+$") then numbers[#numbers+1] = {text = t}
            else
                local sz = 0
                pcall(function() sz = d.TextSize end)
                words[#words+1] = {text = t, size = sz, len = #t}
            end
        end
        if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and visible(d) then
            local ok, img = pcall(function() return d.Image end)
            if ok and img and img ~= "" then
                local area = d.AbsoluteSize.X * d.AbsoluteSize.Y
                if area > iconArea then icon, iconArea = img, area end
            end
        end
    end

    if buyNode then
        local btn = nearestButton(buyNode, card) or buyNode.Parent
        for _, d in ipairs(btn:GetDescendants()) do
            local t = getText(d)
            if t and t:match("^[%d,]+$") and visible(d) then price = num(t) break end
        end
    end
    if not price and numbers[1] then price = num(numbers[1].text) end

    local name, desc
    table.sort(words, function(a,b)
        if a.size ~= b.size then return a.size > b.size end
        return a.len < b.len
    end)
    for _, w in ipairs(words) do
        if not name then name = w.text
        elseif not desc or #w.text > #desc then desc = w.text end
    end
    if name and desc and #name > #desc then name, desc = desc, name end
    if soldOut then stock = 0 end
    if not name then return nil end

    return {
        name = name, stock = stock, price = price, description = desc,
        icon = icon, soldOut = soldOut,
        y = card.AbsolutePosition.Y, x = card.AbsolutePosition.X
    }
end

local function collectCards(gui, into)
    local roots = {}
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and visible(d) and (t:match("^%d+%s*[Ll]eft") or t:lower() == "buy") then
            local card = cardRootFrom(d, gui)
            if card then roots[card] = true end
        end
    end
    for card in pairs(roots) do
        local ok, item = pcall(readCard, card)
        if ok and item and item.name then
            local prev = into[item.name]
            if not prev or (item.stock ~= nil and prev.stock == nil) then into[item.name] = item end
        end
    end
end

local function scanGold()
    local gui = Cache.goldGui
    if not gui then return nil end
    if GOLD_FORCE_TAB and goldHeader() ~= TARGET_SHOP then return nil end

    local items = {}
    collectCards(gui, items)

    if GOLD_AUTO_SCROLL then
        local sf, area
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("ScrollingFrame") and visible(d) then
                local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
                if not area or a > area then sf, area = d, a end
            end
        end
        if sf then
            pcall(function()
                local start = sf.CanvasPosition
                local canvasY, viewY = sf.AbsoluteCanvasSize.Y, sf.AbsoluteWindowSize.Y
                if canvasY > viewY + 5 then
                    local step = math.max(viewY * 0.8, 50)
                    local y = 0
                    while y <= (canvasY - viewY) + step do
                        sf.CanvasPosition = Vector2.new(sf.CanvasPosition.X, y)
                        task.wait(0.12)
                        collectCards(gui, items)
                        y = y + step
                    end
                    sf.CanvasPosition = start
                end
            end)
        end
    end

    local list = {}
    for _, it in pairs(items) do list[#list+1] = it end
    if #list == 0 then return nil end
    table.sort(list, function(a,b)
        if math.abs(a.y - b.y) > 5 then return a.y < b.y end
        return a.x < b.x
    end)
    for i, it in ipairs(list) do it.index = i it.x, it.y = nil, nil end

    local restockText
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and visible(d) and t:lower():find("shop restock",1,true) then
            for _, sib in ipairs(d.Parent:GetChildren()) do
                local st = getText(sib)
                if sib ~= d and st and isTimeText(st) then restockText = st break end
            end
            if not restockText and d.Parent.Parent then
                for _, sib in ipairs(d.Parent.Parent:GetDescendants()) do
                    local st = getText(sib)
                    if st and isTimeText(st) and visible(sib) then restockText = st break end
                end
            end
            break
        end
    end

    local total = 0
    for _, it in ipairs(list) do total = total + (it.stock or 0) end

    return {
        shop = goldHeader() or TARGET_SHOP, items = list, itemCount = #list,
        totalStock = total, restockText = restockText,
        restockSeconds = parseTime(restockText), lastSeen = os.time()
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
    post(DISCORD_WEBHOOK, {["Content-Type"]="application/json", ["User-Agent"]="Mozilla/5.0"},
        HttpService:JSONEncode({content = title, embeds = {{description = desc:sub(1,3800),
            color = color or 5814783, footer = {text = "AE | " .. Cache.sessionId},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")}}}))
end

local function bannerCount()
    local n = 0
    for _ in pairs(Cache.banners) do n = n + 1 end
    return n
end

local function sendToAPI()
    local bc = bannerCount()
    if bc == 0 and not Cache.gold then
        return  -- never post an empty payload over good data
    end
    Cache.updateCounter = Cache.updateCounter + 1
    local now = os.time()

    for name, b in pairs(Cache.banners) do
        b.ageSeconds = now - (b.lastSeen or now)
        b.isActive = (name == Cache.activeBanner)
        b.stale = b.ageSeconds > STALE_AFTER
    end
    local active = Cache.banners[Cache.activeBanner]

    local gold
    if Cache.gold then
        gold = {
            shop = Cache.gold.shop, items = Cache.gold.items,
            itemCount = Cache.gold.itemCount, totalStock = Cache.gold.totalStock,
            restock = {text = Cache.gold.restockText, seconds = Cache.gold.restockSeconds},
            lastSeen = Cache.gold.lastSeen,
            ageSeconds = now - Cache.gold.lastSeen,
            stale = (now - Cache.gold.lastSeen) > STALE_AFTER
        }
    end

    local payload = {
        sessionId = Cache.sessionId, game = "animeexpeditions",
        updateNumber = Cache.updateCounter, timestamp = now,
        playerName = LP.Name, userId = LP.UserId,
        -- SUMMON (top level, frontend compat)
        activeBanner = Cache.activeBanner,
        bannerOrder = Cache.bannerOrder,
        bannerCount = bc, expectedBanners = EXPECTED_BANNERS,
        bannerChange = active and {text = active.timerText, seconds = active.timerSeconds} or nil,
        banners = Cache.banners,
        player = active and {pity = active.pity} or nil,
        -- GOLD SHOP (nested)
        goldshop = gold,
        sources = {
            summon = {cached = bc, open = summonOpen(),
                      lastSeen = active and active.lastSeen or nil},
            goldshop = {cached = gold and gold.itemCount or 0, open = goldOpen(),
                        lastSeen = gold and gold.lastSeen or nil}
        }
    }

    local ok, code = post(API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. now, {
        ["Content-Type"]="application/json", ["Authorization"]=API_KEY,
        ["Cache-Control"]="no-cache, no-store, must-revalidate",
        ["X-Session-ID"]=Cache.sessionId, ["X-Update-Number"]=tostring(Cache.updateCounter)
    }, HttpService:JSONEncode(payload))

    print(ok and ("✅ POST #"..Cache.updateCounter.." -> "..code
        .." | banners "..bc.."/"..EXPECTED_BANNERS
        .." | gold "..(gold and gold.itemCount or 0).." items")
        or ("❌ POST failed: "..tostring(code)))
    Cache.lastPost = now
end

local function heartbeat()
    post(API_ENDPOINT .. "/heartbeat",
        {["Content-Type"]="application/json", ["Authorization"]=API_KEY, ["X-Session-ID"]=Cache.sessionId},
        HttpService:JSONEncode({sessionId=Cache.sessionId, status="ALIVE",
            game="animeexpeditions", timestamp=os.time()}))
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

local function recordSummon(data)
    if not data or not data.banner then return false end
    local prev = Cache.banners[data.banner]
    local changed = (unitString(prev) ~= unitString(data))

    if not prev then
        Cache.bannerOrder[#Cache.bannerOrder+1] = data.banner
        Cache.banners[data.banner] = data
        print("🆕 BANNER " .. data.banner .. " — " .. data.unitCount .. " units | "
            .. tostring(data.currency) .. " | " .. tostring(data.cost.single) .. "/"
            .. tostring(data.cost.ten) .. "   [" .. bannerCount() .. "/" .. EXPECTED_BANNERS .. "]")
    else
        Cache.banners[data.banner] = data
    end
    Cache.activeBanner = data.banner

    if changed and prev then
        local lines = {}
        for _, u in ipairs(data.units) do lines[#lines+1] = "• **"..u.name.."** — "..u.rarity end
        discord("🔄 **BANNER ROTATED**", "**"..data.banner.."**\n"..(data.subtitle or "").."\n\n"
            ..table.concat(lines,"\n").."\n\n⏱ "..tostring(data.timerText), 16729344)
    end

    if not Cache.fullSetAnnounced and bannerCount() >= EXPECTED_BANNERS then
        Cache.fullSetAnnounced = true
        print("🎉 all " .. EXPECTED_BANNERS .. " banners cached")
        discord("🎉 **ALL BANNERS CACHED**", "payload now carries all " .. EXPECTED_BANNERS, 5763719)
    end
    return changed
end

local function goldSig(d)
    if not d then return "" end
    local t = {}
    for _, it in ipairs(d.items) do t[#t+1] = it.name..":"..tostring(it.stock)..":"..tostring(it.price) end
    table.sort(t)
    return table.concat(t, "|")
end

local function recordGold(data)
    if not data then return false end
    local prev = Cache.gold
    local changed = (goldSig(prev) ~= goldSig(data))
    Cache.gold = data

    if not prev then
        print("🆕 GOLD SHOP — " .. data.itemCount .. " items | restock " .. tostring(data.restockText))
        local lines = {}
        for _, it in ipairs(data.items) do
            print("      " .. it.name .. "  stock=" .. tostring(it.stock) .. "  price=" .. tostring(it.price))
            lines[#lines+1] = "• **"..it.name.."** — "..tostring(it.stock).." left · "..tostring(it.price).."g"
        end
        discord("🪙 **GOLD SHOP**", table.concat(lines,"\n").."\n\n⏱ restock: "..tostring(data.restockText), 16763904)
    elseif changed then
        local lines = {}
        for _, it in ipairs(data.items) do
            local old
            for _, o in ipairs(prev.items) do if o.name == it.name then old = o end end
            local mark = ""
            if not old then mark = " 🆕"
            elseif old.stock ~= it.stock then mark = " (was "..tostring(old.stock)..")" end
            lines[#lines+1] = "• **"..it.name.."** — "..tostring(it.stock).." left · "..tostring(it.price).."g"..mark
        end
        discord("🔄 **GOLD SHOP CHANGED**", table.concat(lines,"\n").."\n\n⏱ restock: "..tostring(data.restockText), 16729344)
    end
    return changed
end

----------------------------------------------------------------
-- BOOT
----------------------------------------------------------------
print("🔌 http=" .. tostring(httpreq ~= nil)
    .. " | getconnections=" .. tostring(getconnections ~= nil)
    .. " | firesignal=" .. tostring(firesignal ~= nil))
print("📡 " .. API_ENDPOINT)
discord("🎴🪙 **AE COMBINED MONITOR ONLINE**", "session `"..Cache.sessionId.."`", 5763719)

pcall(function()
    local VU = game:GetService("VirtualUser")
    LP.Idled:Connect(function() VU:CaptureController() VU:ClickButton2(Vector2.new()) end)
end)

print("👉 open the Summon menu (tabs auto-cycle), then the Gold Shop — both stay cached")

----------------------------------------------------------------
-- SUMMON TAB CYCLE
----------------------------------------------------------------
if SUMMON_TAB_CYCLE then
    task.spawn(function()
        while true do
            if not summonOpen() then
                Cache.summonCycling = false
                task.wait(3)
            else
                local tabs = findBannerTabs()
                for _, tab in ipairs(tabs) do
                    if not summonOpen() then break end
                    Cache.summonCycling = true
                    local before = currentBannerTitle()
                    local m = (before == tab.name) and "already" or trySignals(tab.btn, function()
                        local now = currentBannerTitle()
                        return now ~= nil and now ~= before
                    end)
                    if m then
                        if not Cache.summonClickMethod and m ~= "already" then
                            Cache.summonClickMethod = m
                            print("🖱 banner tabs via " .. m)
                        end
                        task.wait(0.6)
                        local ok, data = pcall(scanSummon)
                        if ok and data then recordSummon(data) sendToAPI() end
                    else
                        dbg("✗ " .. tab.name .. " no response")
                    end
                    Cache.summonCycling = false
                    task.wait(TAB_DWELL)
                end
                if #tabs == 0 then task.wait(3) end
            end
        end
    end)
end

----------------------------------------------------------------
-- MAIN
----------------------------------------------------------------
task.spawn(function()
    while true do
        -- SUMMON
        local sOpen = summonOpen()
        if sOpen then
            if not Cache.summonWasOpen then print("📂 summon open") Cache.summonWasOpen = true end
            if not Cache.summonCycling then
                local ok, data = pcall(scanSummon)
                if ok and data then
                    if recordSummon(data) then sendToAPI() end
                end
            end
        elseif Cache.summonWasOpen then
            Cache.summonWasOpen = false
            print("📁 summon closed — " .. bannerCount() .. " banners cached")
        end

        -- GOLD SHOP
        local gOpen = goldOpen()
        if gOpen then
            if not Cache.goldWasOpen then print("📂 gold shop open") Cache.goldWasOpen = true end
            ensureGoldTab()
            local ok, data = pcall(scanGold)
            if ok and data then
                if recordGold(data) then sendToAPI() end
            end
        elseif Cache.goldWasOpen then
            Cache.goldWasOpen = false
            print("📁 gold shop closed — " .. (Cache.gold and Cache.gold.itemCount or 0) .. " items cached")
        end

        if sOpen or gOpen then
            print("📊 banners " .. bannerCount() .. "/" .. EXPECTED_BANNERS
                .. " | gold " .. (Cache.gold and Cache.gold.itemCount or 0) .. " items"
                .. " | active " .. Cache.activeBanner)
        end

        local now = os.time()
        if (now - Cache.lastPost) >= POST_INTERVAL then sendToAPI() end
        if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then heartbeat() Cache.lastHeartbeat = now end
        if (now - Cache.lastStatus) >= STATUS_INTERVAL then
            discord("📊 **AE STATUS**", "updates: "..Cache.updateCounter
                .."\nbanners: "..bannerCount().."/"..EXPECTED_BANNERS
                .."\ngold items: "..(Cache.gold and Cache.gold.itemCount or 0)
                .."\nactive: "..Cache.activeBanner)
            Cache.lastStatus = now
        end
        task.wait(CHECK_INTERVAL)
    end
end)

print("🚀 COMBINED MONITOR RUNNING | session " .. Cache.sessionId)
