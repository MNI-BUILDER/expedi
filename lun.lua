-- ANIME EXPEDITIONS GOLD SHOP MONITOR v1 — auto-discover, scroll-aware, tab cycling
print("🪙 AE Gold Shop Monitor booting...")

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local GuiService  = game:GetService("GuiService")
local VIM         = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local API_ENDPOINT    = "http://204.12.233.39:3000/api/stocks/animeexpeditions/goldshop"
local API_KEY         = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"

local TAB_CYCLE   = true     -- auto-switch Gold Shop <-> Cosmetic Shop
local AUTO_SCROLL = true     -- walk the canvas to catch items below the fold
local TAB_DWELL   = 6
local VERIFY_WINDOW = 2.2
local EXPECTED_SHOPS = 2

local CHECK_INTERVAL     = 2
local POST_INTERVAL      = 10
local HEARTBEAT_INTERVAL = 30
local STATUS_INTERVAL    = 900
local STALE_AFTER        = 1800
local DEBUG = true

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999)),
    updateCounter = 0, lastPost = 0, lastHeartbeat = 0, lastStatus = 0,
    activeShop = "Unknown", shops = {}, order = {},
    gui = nil, cycling = false, clickMethod = nil,
    failedCycles = 0, manualMode = false, wasOpen = false
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
    local l = t:lower()
        :gsub("hours?", "h"):gsub("hrs?", "h")
        :gsub("minutes?", "m"):gsub("mins?", "m")
        :gsub("seconds?", "s"):gsub("secs?", "s")
    local h = tonumber(l:match("(%d+)%s*h")) or 0
    local m = tonumber(l:match("(%d+)%s*m")) or 0
    local s = tonumber(l:match("(%d+)%s*s")) or 0
    if (h + m + s) > 0 then return h*3600 + m*60 + s end
    local a,b,c = t:match("(%d+):(%d+):(%d+)")
    if a then return tonumber(a)*3600 + tonumber(b)*60 + tonumber(c) end
    local d,e = t:match("^(%d+):(%d+)$")
    if d then return tonumber(d)*60 + tonumber(e) end
    return nil
end

local function isTimeText(t)
    local l = t:lower()
    if l:match("%d+%s*:%s*%d+") then return true end
    if l:match("%d+%s*hour") or l:match("%d+%s*minute") or l:match("%d+%s*second") then return true end
    if l:match("%d+%s*h[%s,]") or l:match("%d+%s*m[%s,]") then return true end
    if l:match("^%d+%s*[hms]$") then return true end
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
-- FIND THE SHOP GUI (no hardcoded name)
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
        if t and visible(d) and (t:lower():find("shop restock", 1, true) or t:match("^%d+%s*[Ll]eft")) then
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
            if n then
                stock = tonumber(n)
            elseif t:lower() == "buy" then
                buyNode = d
            elseif t:lower():find("out of stock", 1, true) or t:lower():find("sold out", 1, true) then
                soldOut = true
            elseif t:match("^[%d,]+$") then
                numbers[#numbers+1] = {text = t, node = d}
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
        name = name, stock = stock, price = price,
        description = desc, icon = icon, soldOut = soldOut,
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
    local header = shopHeader()
    if not header then return nil end

    local items = {}
    collectCards(gui, items)

    local scrolled = false
    if AUTO_SCROLL then
        local sf = findScrollFrame(gui)
        if sf then
            local ok = pcall(function()
                local start = sf.CanvasPosition
                local canvasY = sf.AbsoluteCanvasSize.Y
                local viewY = sf.AbsoluteWindowSize.Y
                if canvasY > viewY + 5 then
                    scrolled = true
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
            if not ok then dbg("scroll walk failed") end
        end
    end

    local list = {}
    for _, it in pairs(items) do list[#list+1] = it end
    table.sort(list, function(a, b)
        if math.abs(a.y - b.y) > 5 then return a.y < b.y end
        return a.x < b.x
    end)
    for i, it in ipairs(list) do
        it.index = i
        it.x, it.y = nil, nil
    end

    local restockText
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and visible(d) and t:lower():find("shop restock", 1, true) then
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

    local totalStock = 0
    for _, it in ipairs(list) do totalStock = totalStock + (it.stock or 0) end

    return {
        shop = header, items = list, itemCount = #list, totalStock = totalStock,
        restockText = restockText, restockSeconds = parseTime(restockText),
        scrolled = scrolled, lastSeen = os.time()
    }
end

----------------------------------------------------------------
-- TABS
----------------------------------------------------------------
local function findTabs()
    local gui = Cache.gui
    if not gui then return {} end
    local tabs, seen = {}, {}
    for _, d in ipairs(gui:GetDescendants()) do
        local t = getText(d)
        if t and t:match("^.+%s+[Ss]hop$") and visible(d) then
            local btn = nearestButton(d, gui)
            if btn and not seen[btn] then
                seen[btn] = true
                tabs[#tabs+1] = {btn = btn, name = t, y = btn.AbsolutePosition.Y}
            end
        end
    end
    table.sort(tabs, function(a,b) return a.y < b.y end)
    return tabs
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

local function clickTab(tab)
    local before = shopHeader()
    if before == tab.name then return "already" end
    return trySignals(tab.btn, function()
        local now = shopHeader()
        return now ~= nil and now ~= before
    end)
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
        HttpService:JSONEncode({content = title, embeds = {{description = desc:sub(1,3800), color = color or 16763904,
            footer = {text = "AE GoldShop | " .. Cache.sessionId}, timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")}}}))
    if not ok then print("⚠️ discord failed: " .. tostring(code)) end
end

local function shopCount()
    local n = 0
    for _ in pairs(Cache.shops) do n = n + 1 end
    return n
end

local function sendToAPI()
    local n = shopCount()
    if n == 0 then return end
    Cache.updateCounter = Cache.updateCounter + 1
    local now = os.time()
    for name, s in pairs(Cache.shops) do
        s.ageSeconds = now - (s.lastSeen or now)
        s.isActive = (name == Cache.activeShop)
        s.stale = s.ageSeconds > STALE_AFTER
    end
    local active = Cache.shops[Cache.activeShop]
    local ok, code = post(API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. now, {
        ["Content-Type"]="application/json", ["Authorization"]=API_KEY,
        ["Cache-Control"]="no-cache, no-store, must-revalidate",
        ["X-Session-ID"]=Cache.sessionId, ["X-Update-Number"]=tostring(Cache.updateCounter)
    }, HttpService:JSONEncode({
        sessionId = Cache.sessionId, game = "animeexpeditions", shopType = "goldshop",
        updateNumber = Cache.updateCounter, timestamp = now,
        playerName = LP.Name, userId = LP.UserId,
        activeShop = Cache.activeShop, shopOrder = Cache.order,
        shopCount = n, expectedShops = EXPECTED_SHOPS,
        restock = active and {text = active.restockText, seconds = active.restockSeconds} or nil,
        shops = Cache.shops
    }))
    print(ok and ("✅ POST #"..Cache.updateCounter.." -> "..code.." | shops: "..n)
             or ("❌ POST failed: "..tostring(code)))
    Cache.lastPost = now
end

local function heartbeat()
    post(API_ENDPOINT .. "/heartbeat",
        {["Content-Type"]="application/json", ["Authorization"]=API_KEY, ["X-Session-ID"]=Cache.sessionId},
        HttpService:JSONEncode({sessionId=Cache.sessionId, status="ALIVE",
            game="animeexpeditions", shopType="goldshop", timestamp=os.time()}))
end

----------------------------------------------------------------
-- RECORD
----------------------------------------------------------------
local function sig(s)
    if not s or not s.items then return "" end
    local t = {}
    for _, it in ipairs(s.items) do
        t[#t+1] = it.name .. ":" .. tostring(it.stock) .. ":" .. tostring(it.price)
    end
    table.sort(t)
    return table.concat(t, "|")
end

local function record(data)
    if not data or not data.shop or data.itemCount == 0 then return false end
    local prev = Cache.shops[data.shop]
    local changed = (sig(prev) ~= sig(data))

    if not prev then
        Cache.order[#Cache.order+1] = data.shop
        Cache.shops[data.shop] = data
        print("🆕 CACHED " .. data.shop .. " — " .. data.itemCount .. " items | restock "
            .. tostring(data.restockText) .. "  [" .. shopCount() .. "/" .. EXPECTED_SHOPS .. "]")
        for _, it in ipairs(data.items) do
            print("      " .. it.name .. "  stock=" .. tostring(it.stock) .. "  price=" .. tostring(it.price))
        end
        local lines = {}
        for _, it in ipairs(data.items) do
            lines[#lines+1] = "• **" .. it.name .. "** — " .. tostring(it.stock) .. " left · " .. tostring(it.price) .. "g"
        end
        discord("🪙 **" .. data.shop .. "**", table.concat(lines, "\n")
            .. "\n\n⏱ restock: " .. tostring(data.restockText))
    else
        Cache.shops[data.shop] = data
        if changed then
            local lines = {}
            for _, it in ipairs(data.items) do
                local old
                for _, o in ipairs(prev.items) do if o.name == it.name then old = o end end
                local mark = ""
                if not old then mark = " 🆕"
                elseif old.stock ~= it.stock then mark = " (was " .. tostring(old.stock) .. ")" end
                lines[#lines+1] = "• **" .. it.name .. "** — " .. tostring(it.stock) .. " left · "
                    .. tostring(it.price) .. "g" .. mark
            end
            discord("🔄 **" .. data.shop .. " CHANGED**", table.concat(lines, "\n")
                .. "\n\n⏱ restock: " .. tostring(data.restockText), 16729344)
        end
    end

    Cache.activeShop = data.shop
    return changed
end

----------------------------------------------------------------
-- BOOT
----------------------------------------------------------------
print("🔌 http=" .. tostring(httpreq ~= nil)
    .. " | getconnections=" .. tostring(getconnections ~= nil)
    .. " | firesignal=" .. tostring(firesignal ~= nil))
discord("🪙 **AE GOLD SHOP MONITOR ONLINE**", "session `" .. Cache.sessionId .. "`", 5763719)

pcall(function()
    local VU = game:GetService("VirtualUser")
    LP.Idled:Connect(function() VU:CaptureController() VU:ClickButton2(Vector2.new()) end)
end)

print("👉 open the Gold Shop — I'll find the GUI myself")
repeat
    Cache.gui = findShopGui()
    task.wait(1)
until shopShowing()
print("📂 shop GUI: " .. Cache.gui:GetFullName())

local tabs = findTabs()
print("🗂 tabs: " .. #tabs)
for _, t in ipairs(tabs) do print("   • " .. t.name) end

----------------------------------------------------------------
-- TAB CYCLE
----------------------------------------------------------------
if TAB_CYCLE then
    task.spawn(function()
        while true do
            if not shopShowing() then
                Cache.cycling = false
                task.wait(3)
            else
                tabs = findTabs()
                local wins = 0
                for _, tab in ipairs(tabs) do
                    if not shopShowing() then break end
                    Cache.cycling = true
                    local m = clickTab(tab)
                    if m then
                        wins = wins + 1
                        if not Cache.clickMethod and m ~= "already" then
                            Cache.clickMethod = m
                            print("🖱 tab clicks working via: " .. m)
                        end
                        task.wait(0.7)
                        local ok, data = pcall(scanShop)
                        if ok and data then record(data) sendToAPI() end
                    else
                        dbg("✗ " .. tab.name .. " didn't respond")
                    end
                    Cache.cycling = false
                    task.wait(TAB_DWELL)
                end
                if #tabs > 0 and wins == 0 and not Cache.manualMode then
                    Cache.failedCycles = Cache.failedCycles + 1
                    if Cache.failedCycles >= 2 then
                        Cache.manualMode = true
                        print("🖐 auto-switch blocked — click the shop tabs yourself, I'll cache each")
                    end
                else
                    Cache.failedCycles = 0
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
        local open = shopShowing()
        if open then
            if not Cache.wasOpen then print("📂 shop open") Cache.wasOpen = true end
            if not Cache.cycling then
                local ok, data = pcall(scanShop)
                if ok and data then
                    if record(data) then sendToAPI() end
                    print("🪙 " .. data.shop .. " | " .. data.itemCount .. " items | total stock "
                        .. data.totalStock .. " | restock " .. tostring(data.restockText)
                        .. " | cached " .. shopCount() .. "/" .. EXPECTED_SHOPS)
                end
            end
        elseif Cache.wasOpen then
            Cache.wasOpen = false
            print("📁 shop closed — serving " .. shopCount() .. " cached shops")
        end

        local now = os.time()
        if (now - Cache.lastPost) >= POST_INTERVAL then sendToAPI() end
        if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then heartbeat() Cache.lastHeartbeat = now end
        if (now - Cache.lastStatus) >= STATUS_INTERVAL then
            discord("📊 **GOLD SHOP STATUS**", "updates: " .. Cache.updateCounter
                .. "\nshops: " .. shopCount() .. "\nactive: " .. Cache.activeShop)
            Cache.lastStatus = now
        end
        task.wait(CHECK_INTERVAL)
    end
end)

print("🚀 GOLD SHOP MONITOR RUNNING | session " .. Cache.sessionId)
