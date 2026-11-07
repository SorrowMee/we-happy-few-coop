-- CoopBridge: runs console commands written to Mods/CoopBridge/cmd.txt, one per line,
-- and appends results to Mods/CoopBridge/status.txt. "status" prints world and net state.
local UEHelpers = require("UEHelpers")

local dir = "Mods/CoopBridge/"

local function readAll(p)
    local f = io.open(p, "r")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

local function clear(p)
    local f = io.open(p, "w")
    if f then f:close() end
end

local function report(msg)
    local f = io.open(dir .. "status.txt", "a")
    if f then
        f:write(os.date("%H:%M:%S ") .. msg .. "\n")
        f:close()
    end
    print("[CoopBridge] " .. msg .. "\n")
end

local function name(obj)
    if obj and obj:IsValid() then return obj:GetFullName() end
    return "none"
end

-- UEHelpers.GetPlayerController() finds none on this game's menu, so the world comes
-- from the game viewport and the controller is optional.
local function viewportWorld()
    local vp = FindFirstOf("GameViewportClient")
    if vp and vp:IsValid() then return vp.World end
    return nil
end

local function firstController()
    for _, p in ipairs(FindAllOf("PlayerController") or {}) do
        if p:IsValid() then return p end
    end
    return nil
end

local function status()
    local world = viewportWorld()
    report("world=" .. name(world))
    if world and world:IsValid() then
        report("netdriver=" .. name(world.NetDriver) .. " isServer=" ..
            tostring(UEHelpers.GetKismetSystemLibrary():IsServer(world)))
    end
    local pcs = FindAllOf("PlayerController") or {}
    report("playercontrollers=" .. #pcs)
    for _, p in ipairs(pcs) do
        report("  " .. name(p) .. " player=" .. name(p.Player) .. " pawn=" .. name(p.Pawn))
    end
end

-- Local split screen, as in UE4SS's SplitScreenMod: turn on the engine's splitscreen
-- setting, then add a local player with GameplayStatics:CreatePlayer.
-- false: gamepad 1 drives player 1 and gamepad 2 drives player 2 (keyboard stays on player 1).
local offsetGamepads = false

local function addPlayer()
    local maps = UEHelpers.GetGameMapsSettings()
    maps.bUseSplitscreen = true
    maps.bOffsetPlayerGamepadIds = offsetGamepads
    local world = viewportWorld()
    local count = #(FindAllOf("PlayerController") or {})
    local pc = UEHelpers.GetGameplayStatics():CreatePlayer(world, count, true)
    report("CreatePlayer(" .. count .. ") -> " .. name(pc) .. " pawn=" .. name(pc and pc.Pawn))
end

local function run(line)
    if line == "status" then
        status()
        return
    end
    if line == "addplayer" then
        addPlayer()
        return
    end
    if line == "widgets" then
        -- Which UMG widgets are on screen, and which player owns each.
        local n = 0
        for _, w in ipairs(FindAllOf("UserWidget") or {}) do
            if w:IsValid() and w:IsInViewport() then
                n = n + 1
                local owner = w:GetOwningPlayer()
                local id = owner and owner:IsValid() and owner.Player:IsValid() and owner.Player.ControllerId or "-"
                report(string.format("  widget %s owner=%s id=%s", w:GetFullName(), name(owner), tostring(id)))
            end
        end
        report("widgets in viewport=" .. n)
        -- None were in the viewport on the prologue map; list every live widget by class.
        local byClass = {}
        for _, w in ipairs(FindAllOf("UserWidget") or {}) do
            if w:IsValid() then
                local cls = w:GetClass():GetFName():ToString()
                byClass[cls] = (byClass[cls] or 0) + 1
            end
        end
        for cls, c in pairs(byClass) do report("  class " .. cls .. " x" .. c) end
        local huds = FindAllOf("HUD") or {}
        for _, h in ipairs(huds) do
            report("  hud " .. name(h) .. " owner=" .. name(h.PlayerOwner))
        end
        return
    end
    -- "hudinfo": each player's LightHUDWidget. "hudfix": move each one into its owner's
    -- split-screen area (RemoveFromParent + AddToPlayerScreen).
    if line == "hudinfo" or line == "hudfix" then
        for _, w in ipairs(FindAllOf("LightHUDWidget_C") or {}) do
            if w:IsValid() then
                local owner = w:GetOwningPlayer()
                local parent = w:GetParent()
                report(string.format("  %s owner=%s inViewport=%s parent=%s visibility=%s",
                    w:GetFullName(), name(owner), tostring(w:IsInViewport()), name(parent),
                    tostring(w:GetVisibility())))
                if line == "hudfix" and owner and owner:IsValid() then
                    w:RemoveFromParent()
                    w:AddToPlayerScreen(0)
                    report("    moved to player screen, inViewport=" .. tostring(w:IsInViewport()))
                end
            end
        end
        return
    end
    -- "runfile": run Mods/CoopBridge/snippet.lua on the game thread (dev only, never shipped).
    -- The snippet gets UEHelpers, report and name as globals and may return a string to log.
    if line == "runfile" then
        local chunk, err = loadfile(dir .. "snippet.lua")
        if not chunk then error(err) end
        _G.UEHelpers, _G.report, _G.name = UEHelpers, report, name
        local out = chunk()
        if out ~= nil then report("snippet: " .. tostring(out)) end
        return
    end
    -- "inspect <WidgetClass>": owner, viewport state and parent chain of each instance.
    local cls = line:match("^inspect%s+(%S+)$")
    if cls then
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if w:IsValid() then
                local chain = {}
                local p = w:GetParent()
                while p and p:IsValid() and #chain < 6 do
                    chain[#chain + 1] = p:GetFName():ToString()
                    p = p:GetParent()
                end
                report(string.format("  %s owner=%s inViewport=%s parents=%s", w:GetFullName(),
                    name(w:GetOwningPlayer()), tostring(w:IsInViewport()), table.concat(chain, " < ")))
            end
        end
        return
    end
    local secs = line:match("^track%s+(%d+)$")
    if secs then
        trackUntil = os.time() + tonumber(secs)
        return
    end
    -- "openlevel <map> [options]": the console's "open" did not travel from the menu.
    local map, opts = line:match("^openlevel%s+(%S+)%s*(.*)$")
    if map then
        UEHelpers.GetGameplayStatics():OpenLevel(viewportWorld(), FName(map), true, opts)
        return
    end
    local world = viewportWorld()
    if not (world and world:IsValid()) then error("no viewport world") end
    UEHelpers.GetKismetSystemLibrary():ExecuteConsoleCommand(world, line, firstController())
end

-- "track <seconds>": log every player's pawn location once a second.
trackUntil = 0

local function logPositions()
    local parts = {}
    for i, p in ipairs(FindAllOf("PlayerController") or {}) do
        local pawn = p.Pawn
        if pawn and pawn:IsValid() then
            -- K2_GetActorLocation() read (0,0,0) for both players in one run; the root
            -- component's RelativeLocation is a plain property read, logged beside it to compare.
            local v = pawn:K2_GetActorLocation()
            local r = pawn.RootComponent.RelativeLocation
            parts[#parts + 1] = string.format("P%d=(%.0f,%.0f,%.0f) root=(%.0f,%.0f,%.0f)",
                i, v.X, v.Y, v.Z, r.X, r.Y, r.Z)
        else
            parts[#parts + 1] = string.format("P%d=nopawn", i)
        end
    end
    report("pos " .. table.concat(parts, " "))
end

local lastCmd, lastTrack = 0, 0

function onFrame()
    local now = os.clock()
    if now - lastTrack >= 1.0 then
        lastTrack = now
        if os.time() < trackUntil then pcall(logPositions) end
    end
    if now - lastCmd >= 0.5 then
        lastCmd = now
        local s = readAll(dir .. "cmd.txt")
        if s and s:match("%S") then
            clear(dir .. "cmd.txt")
            for line in s:gmatch("[^\r\n]+") do
                local ok, err = pcall(run, line)
                report((ok and "ran: " or "error: ") .. line .. (ok and "" or (" -> " .. tostring(err))))
            end
        end
    end
end

-- Game-thread driver. UE4SS 3.0.1 LoopAsync threads + ExecuteInGameThread deadlocked the game twice (NOTES
-- phase 10: a loading thread inside a UE4SS hook waiting on a UE4SS lock while the game thread waited on it).
-- Instead, onFrame runs from Blueprint ticks the game calls on the game thread every frame: the player pawn's
-- ReceiveTick (every map, cutscenes included) and the main menu widget's Tick. A short LoopAsync only waits
-- for those functions to exist, registers the hooks on the game thread and then stops.
local FRAME_HOOKS = {
    "/Game/Blueprints/Game/DefaultPlayerCharacter.DefaultPlayerCharacter_C:ReceiveTick",
    "/Game/UI/ShellMenu/ShellMenuWidget.ShellMenuWidget_C:Tick",
}
local hookState = {} -- path -> "pending" | "done"
local inFrame = false

local function frameHook()
    if inFrame then return end
    inFrame = true
    local ok, err = pcall(onFrame)
    inFrame = false
    if not ok then report("frame error: " .. tostring(err)) end
end

LoopAsync(1000, function()
    local allDone = true
    for _, path in ipairs(FRAME_HOOKS) do
        if hookState[path] ~= "done" then
            allDone = false
            if hookState[path] == nil then
                local f = StaticFindObject(path)
                if f and f:IsValid() then
                    hookState[path] = "pending"
                    ExecuteInGameThread(function()
                        local ok, err = pcall(RegisterHook, path, frameHook)
                        hookState[path] = ok and "done" or nil
                        report((ok and "frame hook registered: " or "frame hook failed: ") .. path .. (ok and "" or (" " .. tostring(err))))
                    end)
                end
            end
        end
    end
    return allDone
end)

report("loaded")
