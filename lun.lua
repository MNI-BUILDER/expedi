-- AE — ENCOUNTER NPC / WANDERING TRADER RECON v2
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local SCAN_MODULES = true    -- require data modules and search their contents
local MAX_REQUIRES = 500
local WATCH_TIME   = 240

local WORDS = {"wander","trader","merchant","vendor","peddle","caravan","encounter","travel","barter","stall"}
local SKIP_PATH = {"Sift","Fusion","React","Roact","Promise","Janitor","Trove","TestEZ","_Index","Nodes","ReplicaWrite","CmdrClient.Commands"}

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)
local buf = {}
local function w(s) buf[#buf+1] = tostring(s) end
local function p(s) w(s) print(s) end

local function fullpath(o)
    local t, cur = {}, o
    while cur and cur ~= game do table.insert(t, 1, cur.Name) cur = cur.Parent end
    return table.concat(t, ".")
end

local function hasWord(s)
    local l = string.lower(tostring(s))
    for _, k in ipairs(WORDS) do if l:find(k, 1, true) then return k end end
    return nil
end

local function skipPath(path)
    for _, s in ipairs(SKIP_PATH) do if path:find(s, 1, true) then return true end end
    return false
end

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
            if cur.AbsoluteSize.X <= 1 then return false end
        end
        cur = cur.Parent
    end
    return false
end

local function ser(v, d, seen)
    d, seen = d or 0, seen or {}
    if type(v) ~= "table" then return tostring(v) end
    if seen[v] or d > 4 then return "{...}" end
    seen[v] = true
    local out, n = {}, 0
    for k, val in pairs(v) do
        n = n + 1
        if n > 60 then out[#out+1] = string.rep("  ", d+1) .. "..." break end
        out[#out+1] = string.rep("  ", d+1) .. "[" .. tostring(k) .. "] = " .. ser(val, d+1, seen)
    end
    if n == 0 then return "{}" end
    return "{\n" .. table.concat(out, ",\n") .. "\n" .. string.rep("  ", d) .. "}"
end

p("========== ENCOUNTER NPC RECON | " .. os.date("%X") .. " ==========")

----------------------------------------------------------------
-- 1. THE MONEY SHOT — EncounterNPC type
----------------------------------------------------------------
p("\n##### [1] EncounterNPC #####")
local targets = {}
for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") then
        local n = string.lower(d.Name)
        if n:find("encounter", 1, true) or n:find("npc", 1, true) then targets[#targets+1] = d end
    end
end
for _, m in ipairs(targets) do
    p("  📦 " .. fullpath(m))
    local ok, res = pcall(require, m)
    if ok then
        p("     -> " .. ser(res))
    else
        p("     ✗ require failed: " .. tostring(res))
    end
end
if #targets == 0 then p("  none found by name") end

----------------------------------------------------------------
-- 2. ALL PROXIMITY PROMPTS (unfiltered)
----------------------------------------------------------------
p("\n##### [2] ALL PROMPTS IN WORKSPACE #####")
local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
local count = 0
pcall(function()
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            count = count + 1
            local dist = "?"
            pcall(function()
                local par = d.Parent
                local pos = par:IsA("BasePart") and par.Position
                    or (par:IsA("Model") and par:GetPivot().Position)
                    or (par:IsA("Attachment") and par.WorldPosition)
                if pos and hrp then dist = math.floor((hrp.Position - pos).Magnitude) end
            end)
            local star = hasWord(tostring(d.ObjectText) .. tostring(d.ActionText) .. fullpath(d)) and " ⭐" or ""
            p(string.format('  [%s] "%s" / "%s" dist=%s%s', d.Enabled and "on" or "off",
                tostring(d.ObjectText), tostring(d.ActionText), tostring(dist), star))
            w("      " .. fullpath(d))
        end
    end
end)
p("  total prompts: " .. count)

----------------------------------------------------------------
-- 3. NPC MODELS IN WORKSPACE
----------------------------------------------------------------
p("\n##### [3] NAMED MODELS #####")
local shown = 0
pcall(function()
    for _, d in ipairs(workspace:GetDescendants()) do
        if (d:IsA("Model") or d:IsA("Folder")) and hasWord(d.Name) then
            shown = shown + 1
            if shown <= 25 then p("  ⭐ " .. fullpath(d)) end
        end
    end
end)
p("  matches: " .. shown)

----------------------------------------------------------------
-- 4. MODULE CONTENT SCAN
----------------------------------------------------------------
if SCAN_MODULES then
    p("\n##### [4] MODULE CONTENT SCAN #####")
    local scanned, hits = 0, 0

    local function deepFind(tbl, path, seen, depth)
        if depth > 4 or seen[tbl] then return end
        seen[tbl] = true
        for k, v in pairs(tbl) do
            local kw = hasWord(k)
            if kw then
                hits = hits + 1
                p("     ⭐ key " .. path .. "." .. tostring(k) .. " -> " .. ser(v, 0, {}):sub(1, 400))
            elseif type(v) == "string" and hasWord(v) then
                hits = hits + 1
                p("     ⭐ str " .. path .. "." .. tostring(k) .. ' = "' .. v .. '"')
            end
            if type(v) == "table" then deepFind(v, path .. "." .. tostring(k), seen, depth + 1) end
        end
    end

    for _, m in ipairs(RS:GetDescendants()) do
        if m:IsA("ModuleScript") and scanned < MAX_REQUIRES then
            local path = fullpath(m)
            if not skipPath(path) then
                scanned = scanned + 1
                local ok, res = pcall(require, m)
                if ok and type(res) == "table" then
                    local before = hits
                    pcall(deepFind, res, m.Name, {}, 1)
                    if hits > before then p("  📦 " .. path) end
                end
            end
        end
    end
    p("  modules scanned: " .. scanned .. " | content hits: " .. hits)
end

----------------------------------------------------------------
-- 5. REMOTES (broadened)
----------------------------------------------------------------
p("\n##### [5] REMOTES (broadened) #####")
local rh = 0
for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("RemoteFunction") or d:IsA("RemoteEvent") then
        local path = fullpath(d)
        if hasWord(path) or path:lower():find("shop", 1, true) or path:lower():find("stock", 1, true) then
            rh = rh + 1
            p("  ⭐ [" .. d.ClassName .. "] " .. path)
        end
    end
end
p("  hits: " .. rh)

----------------------------------------------------------------
local function flush()
    pcall(function()
        if writefile then writefile("AE_ENCOUNTER.txt", table.concat(buf, "\n")) print("💾 AE_ENCOUNTER.txt") end
    end)
end
flush()

if httpreq then
    task.spawn(function()
        local head = {}
        for i = 1, math.min(#buf, 250) do head[i] = buf[i] end
        local chunks, cur = {}, ""
        for line in string.gmatch(table.concat(head, "\n"), "[^\n]+") do
            if #cur + #line + 1 > 3500 then chunks[#chunks+1] = cur cur = "" end
            cur = cur .. line .. "\n"
        end
        if cur ~= "" then chunks[#chunks+1] = cur end
        for i, c in ipairs(chunks) do
            if i > 5 then break end
            pcall(httpreq, {Url = DISCORD_WEBHOOK, Method = "POST",
                Headers = {["Content-Type"]="application/json", ["User-Agent"]="Mozilla/5.0"},
                Body = HttpService:JSONEncode({content = "🧭 **ENCOUNTER RECON** " .. i,
                    embeds = {{description = "```\n" .. c .. "```", color = 3447003}}})})
            task.wait(1.5)
        end
    end)
end

----------------------------------------------------------------
-- 6. WATCHER — open the trader when it shows up
----------------------------------------------------------------
p("\n##### [6] WATCHER (" .. WATCH_TIME .. "s) — open the trader if it's around #####")
task.spawn(function()
    local seen, t = {}, 0
    while t < WATCH_TIME do
        for _, sg in ipairs(PG:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled then
                local score, sample = 0, nil
                for _, d in ipairs(sg:GetDescendants()) do
                    local tx = getText(d)
                    if tx and tx ~= "" and visible(d) then
                        if tx:match("^%d+%s*[Ll]eft") then score = score + 3 sample = tx end
                        if tx:lower() == "buy" then score = score + 2 end
                        if hasWord(tx) then score = score + 5 sample = tx end
                    end
                end
                local key = sg.Name .. ":" .. score
                if score >= 3 and not seen[key] then
                    seen[key] = true
                    p("\n🟢 " .. sg.Name .. " (score " .. score .. ")")
                    local n = 0
                    for _, d in ipairs(sg:GetDescendants()) do
                        local tx = getText(d)
                        if tx and tx ~= "" and visible(d) then
                            n = n + 1
                            local line = '   ' .. fullpath(d):gsub("^.*" .. sg.Name .. "%.", "") .. ' = "' .. tx .. '"'
                            if n <= 60 then p(line) else w(line) end
                        end
                    end
                    flush()
                end
            end
        end
        task.wait(1)
        t = t + 1
    end
    flush()
end)

print("🚀 running")
