-- ANIME EXPEDITIONS GOLD SHOP MONITOR v2 — gold shop only, endpoint auto-detect
print("🪙 AE Gold Shop Monitor v2 booting...")

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local GuiService  = game:GetService("GuiService")
local VIM         = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local PRIMARY_ENDPOINT  = "http://204.12.233.39:3000/api/stocks/animeexpeditions/goldshop"
local FALLBACK_ENDPOINT = "http://204.12.233.39:3000/api/stocks/animeexpeditions"
local API_KEY           = "GAMERSBERGGAG"
local DISCORD_WEBHOOK   = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local TARGET_SHOP = "Gold Shop"   -- never touches Cosmetic Shop
local AUTO_SCROLL = true
local VERIFY_WINDOW = 2.2

local CHECK_INTERVAL     = 2
local POST_INTERVAL      = 15
local HEARTBEAT_INTERVAL = 30
local STATUS_INTERVAL    = 900
local DEBUG = true

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999)),
    updateCounter = 0, lastPost = 0, lastHeartbeat = 0, lastStatus = 0,
    endpoint = PRIMARY_ENDPOINT, usingFallback = false,
    gui = nil, data = nil, wasOpen = false, clickMethod = nil
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
    local l = t:lower():gsub("hours?","h"):gsub("hrs?","h")
        :gsub("minutes?","m"):gsub("mins?","m"):gsub("seconds?","s"):gsub("secs?","s")
    local h = tonumber(l:match("(%d+)%s*h")) or 0
    local m = tonumber(l:match("(%d+)%s*m")) or 0
    local s = tonumber(l:match("(%d+)%s*s")) or 0
    if (h+m+s) > 0 then return h*3600 + m*60 + s end
    local a,b,c = t:match("(%d+):(%d+):(%d+)")
    if a then return tonumber(a)*3600 + tonumber(b)*60 + tonumber(c) end
    return nil
end

local function isTimeText(t)
    local l = t:lower()
    if l:match("%d+%s*:%s*%d+") then return true end
    if l:match("%d+%s*hour") or l:match("%d+%s*minute") or l:match("%d+%s*second") then return true end
    if l:match("%d+%s*h[%s,]") or l:match("%d+%s*m[%s,]") then return true end
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

----------------------------------------------------------------
-- GUI DISCOVERY
----------------------------------------------------------------
local function findShopGui()
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

local function shopShowing()
    local gui = Cache.gui
    if not gui or not gui.Parent or (gui:IsA("ScreenGui") and not gui.Enabled) then
        Cache.gui = findShopGui()
        gui = Cache.gui
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

local function shopHeader()
    local gui = Cache.gui
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

----------------------------------------------------------------
-- GOLD SHOP TAB ONLY
----------------------------------------------------------------
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

local function ensureGoldShop()
    local header = shopHeader()
    if header == TARGET_SHOP then return true end
    local gui = Cache.gui
    if not gui then return false end
    for _, d in ipairs(gui:GetDescendants()) do
        if getText(d) == TARGET_SHOP and visible(d) then
            local btn = nearestButton(d, gui)
            if btn then
                local m = trySignals(btn, function() return shopHeader() == TARGET_SHOP end)
                if m then
                    if not Cache.clickMethod then
                        Cache.clickMethod = m
                        print("🖱 switched to " .. TARGET_SHOP .. " via " .. m)
                    end
                    return true
                end
            end
        end
    end
    return false
end

----------------------------------------------------------------
-- CARD PARSING
----------------------------------------------------------------
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
            elseif t:match("^[%d,]+$") then numbers[#numbers+1] = {text = t, node = d}
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

local function findScrollFrame(gui)
    local best, bestArea
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("ScrollingFrame") and visible(d) then
            local area = d.AbsoluteSize.X * d.AbsoluteSize.Y
            if not bestArea or area > bestArea then best, bestArea = d, area end
        end
    end
    return best
end

local function scanShop()
    local gui = Cache.gui
    if not gui then return nil end
    if shopHeader() ~= TARGET_SHOP then return nil end

    local items = {}
    collectCards(gui, items)

    if AUTO_SCROLL then
        local sf = findScrollFrame(gui)
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
    if #list == 0 then return nil end

    return {
        shop = TARGET_SHOP, items = list, itemCount = #list, totalStock = total,
        restockText = restockText, restockSeconds = parseTime(restockText),
        lastSeen = os.time()
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
            color = color or 16763904, footer = {text = "AE GoldShop | " .. Cache.sessionId},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")}}}))
end

local function sendToAPI()
    local d = Cache.data
    if not d then return end
    Cache.updateCounter = Cache.updateCounter + 1
    local now = os.time()
    local payload = {
        sessionId = Cache.sessionId, game = "animeexpeditions", shop = "goldshop",
        shopName = d.shop, updateNumber = Cache.updateCounter, timestamp = now,
        playerName = LP.Name, userId = LP.UserId,
        restock = {text = d.restockText, seconds = d.restockSeconds},
        itemCount = d.itemCount, totalStock = d.totalStock,
        ageSeconds = now - d.lastSeen,
        items = d.items,
        goldshop = {items = d.items, restock = {text = d.restockText, seconds = d.restockSeconds},
                    itemCount = d.itemCount, lastSeen = d.lastSeen}
    }
    local body = HttpService:JSONEncode(payload)
    local headers = {
        ["Content-Type"]="application/json", ["Authorization"]=API_KEY,
        ["Cache-Control"]="no-cache, no-store, must-revalidate",
        ["X-Session-ID"]=Cache.sessionId, ["X-Shop"]="goldshop",
        ["X-Update-Number"]=tostring(Cache.updateCounter)
    }
    local url = Cache.endpoint .. "?session=" .. Cache.sessionId .. "&shop=goldshop&t=" .. now
    local ok, code = post(url, headers, body)

    if ok and code == "404" and not Cache.usingFallback then
        Cache.usingFallback = true
        Cache.endpoint = FALLBACK_ENDPOINT
        print("↩️ /goldshop 404 — falling back to the base route with ?shop=goldshop")
        print("   ⚠️ this route also holds the SUMMON record — expect them to overwrite each other")
        discord("⚠️ **ROUTE FALLBACK**", "`/goldshop` returned 404, using base route — summon and gold shop will clobber", 16776960)
        ok, code = post(FALLBACK_ENDPOINT .. "?session=" .. Cache.sessionId .. "&shop=goldshop&t=" .. now, headers, body)
    end

    print(ok and ("✅ POST #"..Cache.updateCounter.." -> "..code.." | "..d.itemCount.." items"
        ..(Cache.usingFallback and " (fallback route)" or ""))
        or ("❌ POST failed: "..tostring(code)))
    Cache.lastPost = now
end

local function heartbeat()
    post(Cache.endpoint .. "/heartbeat",
        {["Content-Type"]="application/json", ["Authorization"]=API_KEY, ["X-Session-ID"]=Cache.sessionId},
        HttpService:JSONEncode({sessionId=Cache.sessionId, status="ALIVE",
            game="animeexpeditions", shop="goldshop", timestamp=os.time()}))
end

----------------------------------------------------------------
-- RECORD
----------------------------------------------------------------
local function sig(d)
    if not d then return "" end
    local t = {}
    for _, it in ipairs(d.items) do
        t[#t+1] = it.name..":"..tostring(it.stock)..":"..tostring(it.price)
    end
    table.sort(t)
    return table.concat(t, "|")
end

local function record(data)
    if not data then return false end
    local prev = Cache.data
    local changed = (sig(prev) ~= sig(data))
    Cache.data = data

    if not prev then
        print("🆕 CACHED " .. data.shop .. " — " .. data.itemCount .. " items | restock " .. tostring(data.restockText))
        local lines = {}
        for _, it in ipairs(data.items) do
            print("      " .. it.name .. "  stock=" .. tostring(it.stock) .. "  price=" .. tostring(it.price))
            lines[#lines+1] = "• **"..it.name.."** — "..tostring(it.stock).." left · "..tostring(it.price).."g"
        end
        discord("🪙 **GOLD SHOP**", table.concat(lines,"\n").."\n\n⏱ restock: "..tostring(data.restockText))
    elseif changed then
        local lines = {}
        for _, it in ipairs(data.items) do
            local old
            for _, o in ipairs(prev.items) do if o.name == it.name then old = o end end
            local mark = ""
            if not old then mark = " 🆕"
            elseif old.stock ~= it.stock then mark = " (was " .. tostring(old.stock) .. ")" end
            lines[#lines+1] = "• **"..it.name.."** — "..tostring(it.stock).." left · "..tostring(it.price).."g"..mark
        end
        discord("🔄 **GOLD SHOP CHANGED**", table.concat(lines,"\n").."\n\n⏱ restock: "..tostring(data.restockText), 16729344)
    end
    return changed
end

----------------------------------------------------------------
-- BOOT
----------------------------------------------------------------
print("🔌 http=" .. tostring(httpreq ~= nil) .. " | getconnections=" .. tostring(getconnections ~= nil))
discord("🪙 **GOLD SHOP MONITOR v2 ONLINE**", "session `"..Cache.sessionId.."`", 5763719)

pcall(function()
    local VU = game:GetService("VirtualUser")
    LP.Idled:Connect(function() VU:CaptureController() VU:ClickButton2(Vector2.new()) end)
end)

print("👉 open the Gold Shop")
repeat
    Cache.gui = findShopGui()
    task.wait(1)
until shopShowing()
print("📂 shop GUI: " .. Cache.gui:GetFullName())
ensureGoldShop()

task.spawn(function()
    while true do
        if shopShowing() then
            if not Cache.wasOpen then print("📂 shop open") Cache.wasOpen = true end
            ensureGoldShop()
            local ok, data = pcall(scanShop)
            if ok and data then
                if record(data) then sendToAPI() end
                print("🪙 " .. data.itemCount .. " items | total stock " .. data.totalStock
                    .. " | restock " .. tostring(data.restockText))
            end
        elseif Cache.wasOpen then
            Cache.wasOpen = false
            print("📁 shop closed — serving last snapshot ("
                .. (Cache.data and Cache.data.itemCount or 0) .. " items)")
        end

        local now = os.time()
        if (now - Cache.lastPost) >= POST_INTERVAL then sendToAPI() end
        if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then heartbeat() Cache.lastHeartbeat = now end
        if (now - Cache.lastStatus) >= STATUS_INTERVAL then
            discord("📊 **GOLD SHOP STATUS**", "updates: "..Cache.updateCounter
                .."\nitems: "..(Cache.data and Cache.data.itemCount or 0)
                .."\nroute: "..(Cache.usingFallback and "fallback" or "goldshop"))
            Cache.lastStatus = now
        end
        task.wait(CHECK_INTERVAL)
    end
end)

print("🚀 GOLD SHOP v2 RUNNING | session " .. Cache.sessionId)
