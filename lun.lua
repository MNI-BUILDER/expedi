-- ANIME EXPEDITIONS RECON v2.1 — patched (loud errors + real webhook status)
-- OPEN THE SUMMON MENU FIRST, then run.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local SEND_DISCORD = true
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local LIVE_ECHO = 30

local httpreq = request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request)

local ANCHORS = {
    "banner change","villain banner","standard banner","mini banner","beginner",
    "limited","mythic unit","legendary unit","secret unit","epic unit",
    "legendary pity","mythic pity","secret pity",
    "summon 10x","luck potion","shiny hunter","rates","settings"
}
local TIME_PATTERNS = {"%d+m,%s*%d+s","%d+h,%s*%d+m","%d+:%d+:%d+","%d+:%d+"}
local SKIP_CLASS = {
    UIListLayout=true,UIGridLayout=true,UIPadding=true,UICorner=true,UIStroke=true,
    UIGradient=true,UIAspectRatioConstraint=true,UITextSizeConstraint=true,
    UIScale=true,UISizeConstraint=true,UIPageLayout=true
}

local buf = {}
local function w(s) buf[#buf+1] = tostring(s) end
local function p(s) w(s) print(s) end

local function section(name, fn)
    local ok, err = pcall(fn)
    if not ok then p("  ❌ SECTION "..name.." CRASHED: "..tostring(err)) end
end

local function prop(o, name, default)
    local ok, v = pcall(function() return o[name] end)
    if ok and v ~= nil then return v end
    return default
end

local function fullpath(o)
    local t, cur = {}, o
    while cur and cur ~= game do table.insert(t,1,cur.Name) cur = cur.Parent end
    return table.concat(t,".")
end

local function relpath(o, root)             -- ← no pattern magic, this was the crash
    local full, rp = fullpath(o), fullpath(root)
    if full:sub(1,#rp) == rp then return full:sub(#rp+2) end
    return full
end

local function col3(c)
    if typeof(c) ~= "Color3" then return "n/a" end
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
        for j=1,math.min(#base,#a) do if base[j]==a[j] then n=j else break end end
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
            if c:IsA("GuiObject") then s = s.." vis="..tostring(prop(c,"Visible","?")) end
            local t = getText(c)
            if t and t ~= "" then s = s..' txt="'..t..'"' end
            if c:IsA("ViewportFrame") then s = s.." <VIEWPORT>" end
            w(s)
            tree(c, depth+1, pad.."   ", maxd)
        end
    end
end

p("========== AE SUMMON RECON v2.1 | "..os.date("%X").." ==========")
p("http fn: "..tostring(httpreq ~= nil))

local hits, timerNodes, root = {}, {}, nil

section("1 ANCHORS", function()
    p("\n##### [1] ANCHOR HITS #####")
    for _,d in ipairs(PG:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" then
            local a = isAnchor(t)
            if a then
                table.insert(hits, d)
                if a == "TIMER" then table.insert(timerNodes, d) end
                p("  ["..a.."] "..fullpath(d))
                p('        txt="'..t..'"  vis='..tostring(prop(d,"Visible","?")))
            end
        end
    end
    p("  total: "..#hits)
    if #hits == 0 then p("  ⚠️ menu probably wasn't open when you ran this") end
end)

section("2 ROOT", function()
    p("\n##### [2] SUMMON ROOT #####")
    root = commonAncestor(hits)
    if not root then p("  none") return end
    p("  ROOT -> "..fullpath(root).." ["..root.ClassName.."]")
    local sg = root
    while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
    if sg then p("  SCREENGUI -> "..sg.Name.." enabled="..tostring(prop(sg,"Enabled","?"))) end
end)

section("3 TEXT", function()
    p("\n##### [3] ALL TEXT UNDER ROOT #####")
    if not root then return end
    local n = 0
    for _,d in ipairs(root:GetDescendants()) do
        local t = getText(d)
        if t and t ~= "" then
            n = n + 1
            local line = '  '..relpath(d, root)..' = "'..t..'"'
            if n <= 40 then p(line) else w(line) end
        end
    end
    p("  total text nodes: "..n)
end)

section("4 TABS", function()
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
    if not tabParent then p("  not resolved") return end
    p("  TAB CONTAINER -> "..fullpath(tabParent))
    for _,tab in ipairs(tabParent:GetChildren()) do
        if not SKIP_CLASS[tab.ClassName] then
            p(string.format("   • %s [%s] bg=%s z=%s vis=%s",
                tab.Name, tab.ClassName,
                col3(prop(tab,"BackgroundColor3")),
                tostring(prop(tab,"ZIndex","?")),
                tostring(prop(tab,"Visible","?"))))
            for _,sub in ipairs(tab:GetDescendants()) do
                local ln = string.lower(sub.Name)
                if sub:IsA("UIStroke") then
                    p("        UIStroke enabled="..tostring(prop(sub,"Enabled","?"))
                      .." thick="..tostring(prop(sub,"Thickness","?"))
                      .." col="..col3(prop(sub,"Color")))
                elseif ln:find("select") or ln:find("outline") or ln:find("highlight") or ln:find("glow") or ln:find("active") then
                    p("        ⭐ "..sub.Name.." ["..sub.ClassName.."] vis="..tostring(prop(sub,"Visible","?")))
                end
            end
        end
    end
end)

section("5 UNITS", function()
    p("\n##### [5] UNIT SLOTS #####")
    if not root then return end
    local n = 0
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("ViewportFrame") then
            n = n + 1
            p("  VIEWPORT "..relpath(d, root))
            for _,m in ipairs(d:GetChildren()) do p("      model: "..m.Name.." ["..m.ClassName.."]") end
        end
    end
    p("  viewports: "..n)
end)

section("6 TIMERS", function()
    p("\n##### [6] TIMER CANDIDATES #####")
    for _,t in ipairs(timerNodes) do p('  '..fullpath(t)..' = "'..tostring(getText(t))..'"') end
    if #timerNodes == 0 then p("  none — check section 3") end
end)

section("7 TREE", function()
    w("\n##### [7] FULL TREE #####")
    if root then tree(root, 1, "   ", 8) end
end)

pcall(function()
    if writefile then writefile("AE_SUMMON.txt", table.concat(buf,"\n")) print("💾 saved AE_SUMMON.txt") end
end)

-- DISCORD (loud)
if SEND_DISCORD then
    task.spawn(function()
        if not httpreq then print("❌ DISCORD SKIPPED — no http function") return end
        local head = {}
        for i=1,math.min(#buf,400) do head[i]=buf[i] end
        local chunks, cur = {}, ""
        for line in string.gmatch(table.concat(head,"\n"), "[^\n]+") do
            if #cur + #line + 1 > 3500 then chunks[#chunks+1]=cur cur="" end
            cur = cur..line.."\n"
        end
        if cur ~= "" then chunks[#chunks+1]=cur end
        print("📦 chunks to send: "..#chunks)

        for i,c in ipairs(chunks) do
            if i > 6 then break end
            local ok, res = pcall(httpreq, {
                Url = DISCORD_WEBHOOK, Method = "POST",
                Headers = {["Content-Type"]="application/json", ["User-Agent"]="Mozilla/5.0"},
                Body = HttpService:JSONEncode({
                    content = "🔎 **AE RECON** part "..i,
                    embeds = {{description = "```\n"..c.."```", color = 16729344}}
                })
            })
            if ok then
                print("  part "..i.." -> status "..tostring(res.StatusCode).." "..tostring(res.StatusMessage))
                if res.StatusCode ~= 200 and res.StatusCode ~= 204 then
                    print("     body: "..tostring(res.Body):sub(1,300))
                end
            else
                print("  part "..i.." -> CALL FAILED: "..tostring(res))
            end
            task.wait(2)
        end
    end)
end

if LIVE_ECHO > 0 and #timerNodes > 0 then
    task.spawn(function()
        print("\n##### [9] LIVE ECHO #####")
        local t = 0
        while t < LIVE_ECHO do
            local parts = {}
            for _,n in ipairs(timerNodes) do parts[#parts+1] = n.Name.."="..tostring(getText(n)) end
            print("  ⏱ "..table.concat(parts," | "))
            task.wait(2) t = t + 2
        end
    end)
end
