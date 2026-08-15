-- AE — DIALOGUE / SHOP REGISTRY RECON v3
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local WATCH_TIME = 600     -- watches for the trader spawning

local SHOPWORDS = {"shop","stock","trade","trader","wander","merchant","vendor","restock","item","currency","price","offer","deal"}

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)
local buf = {}
local function w(s) buf[#buf+1] = tostring(s) end
local function p(s) w(s) print(s) end

local function fullpath(o)
    local t, cur = {}, o
    while cur and cur ~= game do table.insert(t, 1, cur.Name) cur = cur.Parent end
    return table.concat(t, ".")
end

local function hasWord(s, list)
    local l = string.lower(tostring(s))
    for _, k in ipairs(list or SHOPWORDS) do if l:find(k, 1, true) then return k end end
    return nil
end

-- deep serializer, functions labelled so nothing hides
local function ser(v, d, seen)
    d, seen = d or 0, seen or {}
    local tv = type(v)
    if tv == "function" then return "<function>" end
    if tv ~= "table" then return tostring(v) end
    if seen[v] then return "<cycle>" end
    if d > 8 then return "{...}" end
    seen[v] = true
    local out, n = {}, 0
    for k, val in pairs(v) do
        n = n + 1
        if n > 80 then out[#out+1] = string.rep("  ", d+1) .. "..." break end
        out[#out+1] = string.rep("  ", d+1) .. "[" .. tostring(k) .. "] = " .. ser(val, d+1, seen)
    end
    seen[v] = nil
    if n == 0 then return "{}" end
    return "{\n" .. table.concat(out, ",\n") .. "\n" .. string.rep("  ", d) .. "}"
end

p("========== DIALOGUE / SHOP RECON v3 | " .. os.date("%X") .. " ==========")

----------------------------------------------------------------
-- 1. EVERY Dialogue module, full depth
----------------------------------------------------------------
p("\n##### [1] ReplicatedStorage.Dialogue #####")
local dlg = RS:FindFirstChild("Dialogue")
if dlg then
    local kids = dlg:GetChildren()
    local names = {}
    for _, c in ipairs(kids) do names[#names+1] = c.Name end
    table.sort(names)
    p("  children (" .. #kids .. "): " .. table.concat(names, ", "))
    p("")
    for _, m in ipairs(kids) do
        if m:IsA("ModuleScript") then
            local ok, res = pcall(require, m)
            local star = hasWord(m.Name) and " ⭐" or ""
            p("  📦 " .. m.Name .. star)
            if ok then p("     " .. ser(res)) else p("     ✗ " .. tostring(res)) end
        end
    end
else
    p("  ✗ no Dialogue folder")
end

----------------------------------------------------------------
-- 2. Shared.Information tree
----------------------------------------------------------------
p("\n##### [2] Shared.Information #####")
local shared = RS:FindFirstChild("Shared")
local info = shared and shared:FindFirstChild("Information")
if info then
    local function walk(node, depth, pad)
        if depth > 2 then return end
        for _, c in ipairs(node:GetChildren()) do
            local star = hasWord(c.Name) and " ⭐" or ""
            p(pad .. c.Name .. " [" .. c.ClassName .. "]" .. star)
            walk(c, depth + 1, pad .. "   ")
        end
    end
    walk(info, 1, "  ")
else
    p("  ✗ not found — dumping RS top level instead")
    for _, c in ipairs(RS:GetChildren()) do p("  " .. c.Name .. " [" .. c.ClassName .. "]") end
end

----------------------------------------------------------------
-- 3. Shop-ish data modules, top-level keys
----------------------------------------------------------------
p("\n##### [3] SHOP DATA MODULES #####")
local found = 0
for _, m in ipairs(RS:GetDescendants()) do
    if m:IsA("ModuleScript") and hasWord(m.Name) then
        local path = fullpath(m)
        if not path:find("CmdrClient", 1, true) and not path:find("Sift", 1, true)
           and not path:find("Fusion", 1, true) then
            local ok, res = pcall(require, m)
            if ok and type(res) == "table" then
                found = found + 1
                local keys, n = {}, 0
                for k in pairs(res) do
                    n = n + 1
                    if n <= 25 then keys[#keys+1] = tostring(k) end
                end
                p("  📦 " .. path .. "  (" .. n .. " keys)")
                p("     " .. table.concat(keys, ", "))
                if n <= 12 then p("     " .. ser(res, 0, {}):sub(1, 1500)) end
            end
        end
    end
end
p("  shop-ish modules: " .. found)

----------------------------------------------------------------
-- 4. Workspace NPC roster
----------------------------------------------------------------
p("\n##### [4] Workspace.NPCS #####")
local npcs = workspace:FindFirstChild("NPCS")
local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
if npcs then
    for _, m in ipairs(npcs:GetChildren()) do
        local pr = m:FindFirstChildWhichIsA("ProximityPrompt", true)
        local dist = "?"
        pcall(function()
            local pos = m:IsA("Model") and m:GetPivot().Position or (m:IsA("BasePart") and m.Position)
            if pos and hrp then dist = math.floor((hrp.Position - pos).Magnitude) end
        end)
        p(string.format('  %-22s "%s" dist=%s', m.Name,
            pr and tostring(pr.ObjectText) or "no prompt", tostring(dist)))
    end
    p("  total: " .. #npcs:GetChildren())
end

----------------------------------------------------------------
-- 5. Shop / dialogue remotes
----------------------------------------------------------------
p("\n##### [5] REMOTES #####")
local rn = 0
for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("RemoteFunction") or d:IsA("RemoteEvent") then
        local path = fullpath(d)
        if hasWord(path) or path:lower():find("dialogue", 1, true) or path:lower():find("view", 1, true) then
            rn = rn + 1
            p("  ⭐ [" .. d.ClassName .. "] " .. path)
        end
    end
end
p("  hits: " .. rn)

----------------------------------------------------------------
local function flush()
    pcall(function()
        if writefile then writefile("AE_DIALOGUE.txt", table.concat(buf, "\n")) print("💾 AE_DIALOGUE.txt") end
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
            if i > 6 then break end
            pcall(httpreq, {Url = DISCORD_WEBHOOK, Method = "POST",
                Headers = {["Content-Type"]="application/json", ["User-Agent"]="Mozilla/5.0"},
                Body = HttpService:JSONEncode({content = "📜 **DIALOGUE RECON** " .. i,
                    embeds = {{description = "```\n" .. c .. "```", color = 10181046}}})})
            task.wait(1.5)
        end
    end)
end

----------------------------------------------------------------
-- 6. SPAWN WATCHER — catches the trader appearing
----------------------------------------------------------------
p("\n##### [6] SPAWN WATCHER (" .. WATCH_TIME .. "s) #####")
task.spawn(function()
    if npcs then
        npcs.ChildAdded:Connect(function(c)
            p("🟢 NPC SPAWNED: " .. c.Name)
            task.wait(1)
            local pr = c:FindFirstChildWhichIsA("ProximityPrompt", true)
            if pr then p('   prompt: "' .. tostring(pr.ObjectText) .. '" / "' .. tostring(pr.ActionText) .. '"') end
            flush()
        end)
    end
    workspace.DescendantAdded:Connect(function(d)
        if d:IsA("ProximityPrompt") then
            task.wait(0.5)
            p('🟢 PROMPT ADDED: "' .. tostring(d.ObjectText) .. '" / "'
                .. tostring(d.ActionText) .. '" @ ' .. fullpath(d))
            flush()
        end
    end)
    task.wait(WATCH_TIME)
    p("watcher done")
    flush()
end)

print("🚀 running")
