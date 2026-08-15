-- ANIME EXPEDITIONS RECON v2 — text-anchored summon path finder
-- OPEN THE SUMMON MENU FIRST, then run. Output -> console + AE_SUMMON.txt + Discord

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

----------------------------------------------------------------
local SEND_DISCORD = true
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local LIVE_ECHO = 30   -- seconds of live countdown echo (0 = off)

local ANCHORS = {
    "banner change","villain banner","standard banner","mini banner","beginner",
    "limited","mythic unit","legendary unit","secret unit","epic unit",
    "legendary pity","mythic pity","secret pity",
    "summon 10x","luck potion","shiny hunter","rates","settings"
}
local TIME_PATTERNS = { "%d+m,%s*%d+s", "%d+h,%s*%d+m", "%d+:%d+:%d+", "%d+:%d+" }

local SKIP_CLASS = {
    UIListLayout=true,UIGridLayout=true,UIPadding=true,UICorner=true,UIStroke=true,
    UIGradient=true,UIAspectRatioConstraint=true,UITextSizeConstraint=true,
    UIScale=true,UISizeConstraint=true,UIPageLayout=true
}
----------------------------------------------------------------

local buf = {}
local function w(s) buf[#buf+1] = tostring(s) end
local function p(s) w(s) print(s) end

local function fullpath(o)
    local t, cur = {}, o
    while cur and cur ~= game do table.insert(t,1,cur.Name) cur = cur.Parent end
    return table.concat(t,".")
end

local function col3(c)
    if typeof(c) ~= "Color3" then return "nil" end
    return string.format("(%d,%d,%d)", c.R*255, c.G*255, c.B*255)
end

local function getText(o)
    local ok, t = pcall(function() return o.Text end)
    if ok and type(t)=="string" then return t end
    return nil
end

local function isAnchor(txt)
    local l = string.lower(txt)
    for _,a in ipairs(ANCHORS) do if string.find(l,a,1,true) then return a end end
    for _,pat in ipairs(TIME_PATTERNS) do if string.match(txt,pat) then return "TIMER" end end
    return nil
end

local function chain(o)
    local t, cur = {}, o
    while cur and cur ~= game do table.insert(t,1,cur) cur = cur.Parent end
    return t
end

local function commonAncestor(objs)
    if #objs == 0 then return nil end
    local base = chain(objs[1])
    for i=2,#objs do
        local a, n = chain(objs[i]), 0
        for j=1, math.min(#base,#a) do
            if base[j]==a[j] then n=j else break end
        end
        local nb = {}
        for j=1,n do nb[j]=base[j] end
        base = nb
    end
    return base[#base]
end

local function tree(root, depth, pad, maxd)
    if depth > maxd then return end
    local kids = root:GetChildren()
    for i,c in ipairs(kids) do
        if i > 60 then w(pad.."... +"..(#kids-60).." more") break end
        if not SKIP_CLASS[c.ClassName] then
            local s = pad..c.Name.." ["..c.ClassName.."]"
            if c:IsA("GuiObject") then s = s.." vis="..tostring(c.Visible) end
            local t = getText(c)
            if t and t ~= "" then s = s..' txt="'..t..'"' end
            if c:IsA("ViewportFrame") then s = s.." <VIEWPORT>" end
            w(s)
            tree(c, depth+1, pad.."   ", maxd)
        end
    end
end

p("========== AE SUMMON RECON v2 | "..os.date("%X").." ==========")

----------------------------------------------------------------
-- 1. ANCHOR HITS
----------------------------------------------------------------
p("\n##### [1] ANCHOR HITS #####")
local hits, timerNodes = {}, {}
pcall(function()
    for _,d in ipairs(PG:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" then
            local a = isAnchor(t)
            if a then
                table.insert(hits, d)
                if a == "TIMER" then table.insert(timerNodes, d) end
                p(string.format('  [%s] %s\n        txt="%s"  vis=%s', a, fullpath(d), t, tostring(d.Visible)))
            end
        end
    end
end)
p("  total anchor hits: "..#hits)

if #hits == 0 then
    p("  ⚠️ NOTHING FOUND — menu probably wasn't open, or text is in ImageLabels. rerun with it open.")
end

----------------------------------------------------------------
-- 2. SUMMON ROOT
----------------------------------------------------------------
p("\n##### [2] SUMMON ROOT #####")
local root = commonAncestor(hits)
if root then
    p("  ROOT -> "..fullpath(root).." ["..root.ClassName.."]")
    local sg = root
    while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
    if sg then p("  SCREENGUI -> "..sg.Name.."  enabled="..tostring(sg.Enabled)) end
else
    p("  no root (no hits)")
end

----------------------------------------------------------------
-- 3. EVERY TEXT NODE UNDER ROOT
----------------------------------------------------------------
p("\n##### [3] ALL TEXT UNDER ROOT #####")
if root then
    local n = 0
    for _,d in ipairs(root:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" then
            n = n + 1
            if n <= 40 then
                p(string.format('  %s = "%s"', fullpath(d):gsub("^.*"..root.Name.."%.",""), t))
            else
                w(string.format('  %s = "%s"', fullpath(d), t))
            end
        end
    end
    p("  total text nodes: "..n.." (first 40 in console, rest in file)")
end

----------------------------------------------------------------
-- 4. BANNER TABS + SELECTED-STATE SIGNAL
----------------------------------------------------------------
p("\n##### [4] BANNER TABS #####")
local tabHits = {}
for _,d in ipairs(hits) do
    local t = string.lower(getText(d) or "")
    if t:find("beginner",1,true) or t:find("villain",1,true)
    or t:find("standard",1,true) or t:find("mini",1,true) then
        table.insert(tabHits, d)
    end
end
local tabParent = commonAncestor(tabHits)
if tabParent then
    p("  TAB CONTAINER -> "..fullpath(tabParent))
    for _,tab in ipairs(tabParent:GetChildren()) do
        if not SKIP_CLASS[tab.ClassName] then
            local bg = pcall(function() return tab.BackgroundColor3 end) and col3(tab.BackgroundColor3) or "n/a"
            local zi = pcall(function() return tab.ZIndex end) and tostring(tab.ZIndex) or "n/a"
            p(string.format("   • %-22s [%s] bg=%s z=%s size=%s", tab.Name, tab.ClassName, bg, zi, tostring(tab.Size)))
            for _,sub in ipairs(tab:GetDescendants()) do
                local ln = string.lower(sub.Name)
                if sub:IsA("UIStroke") then
                    p(string.format("        UIStroke enabled=%s thick=%s col=%s trans=%s",
                        tostring(sub.Enabled), tostring(sub.Thickness), col3(sub.Color), tostring(sub.Transparency)))
                elseif ln:find("select") or ln:find("outline") or ln:find("highlight") or ln:find("glow") or ln:find("active") then
                    p(string.format("        ⭐ %s [%s] vis=%s", sub.Name, sub.ClassName,
                        tostring(sub:IsA("GuiObject") and sub.Visible or "n/a")))
                end
            end
        end
    end
else
    p("  tab container not resolved")
end

----------------------------------------------------------------
-- 5. UNIT SLOTS (viewports/images)
----------------------------------------------------------------
p("\n##### [5] UNIT SLOTS #####")
if root then
    local n = 0
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("ViewportFrame") then
            n = n + 1
            p("  VIEWPORT "..fullpath(d))
            for _,m in ipairs(d:GetChildren()) do p("      model: "..m.Name.." ["..m.ClassName.."]") end
        end
    end
    p("  viewports: "..n.." (0 means units are ImageLabels or a Frame with a WorldModel)")
end

----------------------------------------------------------------
-- 6. TIMER NODES
----------------------------------------------------------------
p("\n##### [6] TIMER CANDIDATES #####")
for _,t in ipairs(timerNodes) do
    p('  '..fullpath(t)..' = "'..getText(t)..'"')
end
if #timerNodes == 0 then p("  none matched — check section 3 for the countdown string") end

----------------------------------------------------------------
-- 7. FULL TREE (file)
----------------------------------------------------------------
w("\n##### [7] FULL TREE UNDER ROOT #####")
if root then tree(root, 1, "   ", 8) end

----------------------------------------------------------------
local function flush()
    pcall(function()
        if writefile then
            writefile("AE_SUMMON.txt", table.concat(buf,"\n"))
            print("💾 saved AE_SUMMON.txt ("..#buf.." lines)")
        end
    end)
end
flush()

----------------------------------------------------------------
-- 8. DISCORD PUSH
----------------------------------------------------------------
if SEND_DISCORD then
    task.spawn(function()
        local head = {}
        for i = 1, math.min(#buf, 400) do head[i] = buf[i] end
        local text, chunks, cur = table.concat(head, "\n"), {}, ""
        for line in string.gmatch(text, "[^\n]+") do
            if #cur + #line + 1 > 3700 then chunks[#chunks+1] = cur cur = "" end
            cur = cur .. line .. "\n"
        end
        if cur ~= "" then chunks[#chunks+1] = cur end

        for i, c in ipairs(chunks) do
            if i > 6 then break end
            pcall(function()
                request({
                    Url = DISCORD_WEBHOOK,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = HttpService:JSONEncode({
                        content = "🔎 **AE SUMMON RECON** part "..i.."/"..math.min(#chunks,6),
                        embeds = {{ description = "```\n"..c.."```", color = 16729344 }}
                    })
                })
            end)
            task.wait(1.2)
        end
        print("📨 recon pushed to Discord")
    end)
end

----------------------------------------------------------------
-- 9. LIVE ECHO — confirms the countdown actually ticks
----------------------------------------------------------------
if LIVE_ECHO > 0 and #timerNodes > 0 then
    task.spawn(function()
        print("\n##### [9] LIVE ECHO ("..LIVE_ECHO.."s) #####")
        local t = 0
        while t < LIVE_ECHO do
            local parts = {}
            for _, n in ipairs(timerNodes) do
                parts[#parts+1] = n.Name.."="..tostring(getText(n))
            end
            print("  ⏱ "..table.concat(parts, " | "))
            task.wait(2)
            t = t + 2
        end
        print("  echo done")
    end)
end
