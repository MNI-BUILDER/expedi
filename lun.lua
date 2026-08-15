-- ANIME EXPEDITIONS — WANDERING TRADER RECON
-- Run in Main Lobby. Works closed (watcher) or open (instant dump). -> console + AE_TRADER.txt + Discord

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local PROBE_REMOTES = false     -- true = invoke matched RemoteFunctions with read-only args
local WATCH_TIME    = 240

local KEYWORDS = {"wandering","wander","trader","trade","merchant","peddler","caravan","travel","exchange","barter"}
local STOCK_HINTS = {"left!","left","stock","restock","buy","sold out","out of stock","leaves in","departs","available until"}

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)
local buf = {}
local function w(s) buf[#buf+1] = tostring(s) end
local function p(s) w(s) print(s) end

local function getText(o)
    local ok, t = pcall(function() return o.Text end)
    if ok and type(t) == "string" then return t end
    return nil
end

local function visible(o)
    local cur = o
    while cur and cur ~= game do
        if cur:IsA("ScreenGui") then return cur.Enabled end
        if cur:IsA("GuiObject") then
            if not cur.Visible then return false end
            if cur.AbsoluteSize.X <= 1 or cur.AbsoluteSize.Y <= 1 then return false end
        end
        cur = cur.Parent
    end
    return false
end

local function hasKeyword(s, list)
    local l = string.lower(s)
    for _, k in ipairs(list) do if l:find(k, 1, true) then return k end end
    return nil
end

local function fullpath(o)
    local t, cur = {}, o
    while cur and cur ~= game do table.insert(t, 1, cur.Name) cur = cur.Parent end
    return table.concat(t, ".")
end

local function relpath(o, root)
    local f, r = fullpath(o), fullpath(root)
    if f:sub(1, #r) == r then return f:sub(#r + 2) end
    return f
end

local function ser(v, d)
    d = d or 0
    if type(v) ~= "table" then return tostring(v) end
    if d > 3 then return "{...}" end
    local out, n = {}, 0
    for k, val in pairs(v) do
        n = n + 1
        if n > 40 then out[#out+1] = string.rep("  ", d+1) .. "..." break end
        out[#out+1] = string.rep("  ", d+1) .. "[" .. tostring(k) .. "] = " .. ser(val, d+1)
    end
    if n == 0 then return "{}" end
    return "{\n" .. table.concat(out, ",\n") .. "\n" .. string.rep("  ", d) .. "}"
end

p("========== WANDERING TRADER RECON | " .. os.date("%X") .. " ==========")

----------------------------------------------------------------
-- 1. REMOTES  (Material Dealer was solved here — check first)
----------------------------------------------------------------
p("\n##### [1] REMOTES #####")
local hits = {}
pcall(function()
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteFunction") or d:IsA("RemoteEvent") or d:IsA("BindableFunction") then
            local path = fullpath(d)
            local k = hasKeyword(d.Name, KEYWORDS) or hasKeyword(path, KEYWORDS)
            if k then
                hits[#hits+1] = d
                p("  ⭐ [" .. d.ClassName .. "] " .. path)
            else
                w("  [" .. d.ClassName .. "] " .. path)
            end
        end
    end
end)
p("  keyword remotes: " .. #hits)

p("\n##### [2] MODULES #####")
local mods = {}
pcall(function()
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("ModuleScript") then
            local path = fullpath(d)
            if hasKeyword(d.Name, KEYWORDS) or hasKeyword(path, KEYWORDS) then
                mods[#mods+1] = d
                p("  ⭐ " .. path)
            else
                w("  " .. path)
            end
        end
    end
end)
p("  keyword modules: " .. #mods)

----------------------------------------------------------------
-- 3. NPC PROMPTS
----------------------------------------------------------------
p("\n##### [3] PROMPTS IN WORKSPACE #####")
local found = 0
pcall(function()
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local blob = tostring(d.ObjectText) .. " " .. tostring(d.ActionText) .. " " .. fullpath(d)
            if hasKeyword(blob, KEYWORDS) then
                found = found + 1
                local dist = "?"
                pcall(function()
                    local par = d.Parent
                    local pos = par:IsA("BasePart") and par.Position
                        or (par:IsA("Model") and par:GetPivot().Position)
                        or (par:IsA("Attachment") and par.WorldPosition)
                    if pos and hrp then dist = math.floor((hrp.Position - pos).Magnitude) end
                end)
                p('  ⭐ "' .. tostring(d.ObjectText) .. '" / "' .. tostring(d.ActionText)
                    .. '" | dist=' .. tostring(dist) .. " | " .. fullpath(d))
            end
        end
    end
end)
if found == 0 then p("  none — trader NPC may not be spawned right now") end

----------------------------------------------------------------
-- 4. SHOP-SHAPED GUIS
----------------------------------------------------------------
local function shopScore(sg)
    local score, sample = 0, {}
    for _, d in ipairs(sg:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" and visible(d) then
            if t:match("^%d+%s*[Ll]eft") then score = score + 3 sample[#sample+1] = t end
            if t:lower() == "buy" then score = score + 2 end
            if hasKeyword(t, STOCK_HINTS) then score = score + 1 end
            if hasKeyword(t, KEYWORDS) then score = score + 5 sample[#sample+1] = t end
        end
    end
    return score, sample
end

local function dumpGui(sg, label)
    p("\n>>> " .. label .. " :: " .. sg:GetFullName())
    local n = 0
    for _, d in ipairs(sg:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" and visible(d) then
            n = n + 1
            local line = '   ' .. relpath(d, sg) .. ' = "' .. t .. '"'
            if n <= 60 then p(line) else w(line) end
        end
    end
    p("   text nodes: " .. n)

    -- card guess, same heuristics as the gold shop parser
    local cards = 0
    for _, d in ipairs(sg:GetDescendants()) do
        local t = getText(d)
        if t and visible(d) and (t:match("^%d+%s*[Ll]eft") or t:lower() == "buy") then
            local cur = d
            for _ = 1, 6 do
                cur = cur.Parent
                if not cur or cur == sg then break end
                local texts = 0
                for _, s in ipairs(cur:GetDescendants()) do
                    local st = getText(s)
                    if st and st ~= "" and visible(s) then texts = texts + 1 end
                end
                if texts >= 4 then
                    cards = cards + 1
                    local parts = {}
                    for _, s in ipairs(cur:GetDescendants()) do
                        local st = getText(s)
                        if st and st ~= "" and visible(s) then parts[#parts+1] = st end
                    end
                    p("   🃏 CARD: " .. table.concat(parts, " | "))
                    break
                end
            end
        end
    end
    p("   cards detected: " .. cards)
end

p("\n##### [4] SHOP-SHAPED GUIS #####")
local best, bestScore = nil, 0
for _, sg in ipairs(PG:GetChildren()) do
    if sg:IsA("ScreenGui") and sg.Enabled then
        local sc, sample = shopScore(sg)
        if sc > 0 then
            p("  " .. sg.Name .. "  score=" .. sc
                .. (sample[1] and ("  e.g. \"" .. sample[1] .. "\"") or ""))
            if sc > bestScore then best, bestScore = sg, sc end
        end
    end
end
if best then dumpGui(best, "BEST MATCH") else p("  nothing shop-shaped visible — open the trader UI") end

-- always dump Prompt, the gold shop lived there
local prompt = PG:FindFirstChild("Prompt")
if prompt and prompt ~= best then dumpGui(prompt, "PlayerGui.Prompt") end

----------------------------------------------------------------
-- 5. REMOTE PROBE (opt-in)
----------------------------------------------------------------
if PROBE_REMOTES then
    p("\n##### [5] PROBE #####")
    local ARGS = {{"Get"},{"GetStock"},{"GetData"},{"GetShop"},{"GetTrader"},{"Stock"},{"Info"},{}}
    for _, r in ipairs(hits) do
        if r:IsA("RemoteFunction") then
            for _, a in ipairs(ARGS) do
                local ok, res = pcall(function() return r:InvokeServer(unpack(a)) end)
                if ok and res ~= nil then
                    p("  ✅ " .. fullpath(r) .. " (" .. (a[1] or "no args") .. ") -> " .. ser(res))
                end
            end
        end
    end
else
    p("\n[5] probe off — set PROBE_REMOTES = true once we see a promising remote")
end

----------------------------------------------------------------
local function flush()
    pcall(function()
        if writefile then writefile("AE_TRADER.txt", table.concat(buf, "\n")) print("💾 AE_TRADER.txt saved") end
    end)
end
flush()

if httpreq then
    task.spawn(function()
        local head = {}
        for i = 1, math.min(#buf, 300) do head[i] = buf[i] end
        local chunks, cur = {}, ""
        for line in string.gmatch(table.concat(head, "\n"), "[^\n]+") do
            if #cur + #line + 1 > 3500 then chunks[#chunks+1] = cur cur = "" end
            cur = cur .. line .. "\n"
        end
        if cur ~= "" then chunks[#chunks+1] = cur end
        for i, c in ipairs(chunks) do
            if i > 5 then break end
            pcall(httpreq, {
                Url = DISCORD_WEBHOOK, Method = "POST",
                Headers = {["Content-Type"]="application/json", ["User-Agent"]="Mozilla/5.0"},
                Body = HttpService:JSONEncode({content = "🧭 **TRADER RECON** part " .. i,
                    embeds = {{description = "```\n" .. c .. "```", color = 3447003}}})
            })
            task.wait(1.5)
        end
    end)
end

----------------------------------------------------------------
-- 6. LIVE WATCHER — open the trader now
----------------------------------------------------------------
p("\n##### [6] WATCHER — OPEN THE TRADER UI NOW (" .. WATCH_TIME .. "s) #####")
task.spawn(function()
    local seen, t = {}, 0
    while t < WATCH_TIME do
        for _, sg in ipairs(PG:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled then
                local sc = shopScore(sg)
                local key = sg.Name .. ":" .. sc
                if sc >= 3 and not seen[key] then
                    seen[key] = true
                    p("\n🟢 SHOP UI DETECTED: " .. sg.Name .. " (score " .. sc .. ")")
                    dumpGui(sg, "LIVE")
                    flush()
                end
            end
        end
        task.wait(1)
        t = t + 1
    end
    p("watcher done")
    flush()
end)

print("🚀 recon running — open the Wandering Trader")
