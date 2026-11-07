-- SplitScreenCoop: local two-player split screen for We Happy Few.
-- Adds player 2 once player 1 has a character in a game world, and removes player 2
-- on the main menu. Gamepad 1 drives player 1, gamepad 2 drives player 2.
local UEHelpers = require("UEHelpers")

local MENU_MAP = "ShellMenu"
local SETTLE_SECONDS = 5 -- player 1 must have a pawn this long before player 2 is added

-- Widgets drawn once per player over the whole window, confined to the owner's half.
local HALF_SCREEN_WIDGETS = { "LightHUDWidget_C", "NotificationsAreaWidget_C" }

local readySince = nil

local function log(msg)
    print("[SplitScreenCoop] " .. msg .. "\n")
end

local logged = {}

local function logOnce(msg)
    if not logged[msg] then
        logged[msg] = true
        log(msg)
    end
end

local function name(obj)
    return (obj and obj:IsValid()) and obj:GetFName():ToString() or "none"
end

-- FindAllOf/FindFirstOf each cost about 60 ms here (whole-object-array scans; measured 2026-11-03),
-- so lookups are cached and only repeated when a cached object is no longer valid.
local viewportClient = nil

local function viewportWorld()
    if not (viewportClient and viewportClient:IsValid()) then
        viewportClient = FindFirstOf("GameViewportClient")
    end
    if viewportClient and viewportClient:IsValid() then return viewportClient.World end
    return nil
end

local function hasPlayer2(world)
    local pc = UEHelpers.GetGameplayStatics():GetPlayerController(world, 1)
    return pc ~= nil and pc:IsValid()
end

local function onMenu(world)
    return world:GetFullName():find(MENU_MAP, 1, true) ~= nil
end

local function statics()
    return UEHelpers.GetGameplayStatics()
end

local function addPlayer2(world)
    -- Diagnostics switch: with Mods/SplitScreenCoop/no_p2.txt present, player 2 is never added.
    local f = io.open("Mods/SplitScreenCoop/no_p2.txt", "r")
    if f then f:close() logOnce("no_p2.txt present: player 2 not added") return end
    local maps = UEHelpers.GetGameMapsSettings()
    maps.bUseSplitscreen = true
    maps.bOffsetPlayerGamepadIds = false
    local pc = statics():CreatePlayer(world, 1, true)
    if pc and pc:IsValid() then
        log("player 2 added: " .. pc:GetFullName())
    else
        log("CreatePlayer failed")
    end
end

-- LocalPlayer.ControllerId is not a readable property in 4.13 (it reads as a UObject),
-- so extra players are found by player index instead.
local function removeExtraPlayers(world)
    for i = 3, 1, -1 do
        local pc = statics():GetPlayerController(world, i)
        if pc and pc:IsValid() then
            log("removing " .. pc:GetFullName())
            statics():RemovePlayer(pc, true)
        end
    end
end

-- On the story map the game mode gives player 2 only a spectator, so the game's own player
-- setup (GlimpseCharacter, PlayerMenu, menu access) never runs for them; it runs on Possess.
-- RestartPlayer is not a UFunction in 4.13, so: spawn with SpawnDefaultPawnFor at player 1,
-- using player 1's class (DefaultPawnClass swapped for the call; the default is the generic
-- DefaultPlayerCharacter_C), then Possess.
local function ensurePlayer2Pawn(world)
    local p1 = statics():GetPlayerController(world, 0)
    local p2 = statics():GetPlayerController(world, 1)
    if not (p1 and p1:IsValid() and p2 and p2:IsValid()) then return end
    if p2.Pawn:IsValid() or not p1.Pawn:IsValid() then return end
    local gm = world.AuthorityGameMode
    local original = gm.DefaultPawnClass
    gm.DefaultPawnClass = p1.Pawn:GetClass()
    local ok, pawn = pcall(function() return gm:SpawnDefaultPawnFor(p2, p1.Pawn) end)
    gm.DefaultPawnClass = original
    if ok and pawn and pawn:IsValid() then
        p2:Possess(pawn)
        log("player 2 pawn spawned: " .. name(pawn) .. ", GlimpseCharacter=" .. name(p2.GlimpseCharacter))
    else
        logOnce("could not spawn a pawn for player 2")
    end
end

local layoutLibrary = nil

local function halfScreenHeight(world)
    layoutLibrary = layoutLibrary or StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local px = layoutLibrary:GetViewportSize(world)
    return px.Y / layoutLibrary:GetViewportScale(world) / 2
end

-- 0 for player 1's widgets, 1 for player 2's.
local function ownerIndex(w, world)
    local owner = w:GetOwningPlayer()
    if not (owner and owner:IsValid()) then return nil end
    return owner:GetFullName() == statics():GetPlayerController(world, 0):GetFullName() and 0 or 1
end

-- The game's per-player widgets must stay where the game put them: taking the HUD off screen
-- crashed the game (GlimpseGame.exe+0x52CB2C, 3 of 3 runs on the story map). Instead, each
-- full-stretch layer of the widget's root canvas gets its original margins plus half the screen
-- height on one side. Anchors are left alone: UE4SS 3.0.1 zeroes a nested-struct table passed to
-- SetAnchors, while a flat FMargin table converts correctly.
local originalOffsets = {}
local panelClass = nil

local skipLayers = nil

-- HUDCanvas (the LightHUDWidget layer with compass, bars, quick slots, prompts and the loot box) is NOT shrunk:
-- the game positions ContainerLootBoxHost itself in full-screen coordinates (anchor 0,0, Top ~531), so in a
-- half-height canvas the loot box fell outside it and looting took everything without showing the loot screen
-- (owner bisect, 2026-11-04). Instead every child keeps its size and is moved into its owner's half by its
-- anchor: an element at anchor height a (0 top .. 1 bottom) moves by -a*H/2 for player 1 and (1-a)*H/2 for
-- player 2. Children the game positions itself are left alone.
local CANVAS_LAYER = "HUDCanvas"
local CANVAS_SKIP = { ContainerLootBoxHost = true }
local originalChildOffsets = {}

local function moveCanvasChildren(w, canvas, index, half)
    local H = half * 2
    for i = 0, canvas:GetChildrenCount() - 1 do
        local c = canvas:GetChildAt(i)
        local cname = c:GetFName():ToString()
        local slot = c.Slot
        if CANVAS_SKIP[cname] and slot and slot:IsValid() and slot:GetClass():GetFName():ToString() == "CanvasPanelSlot" then
            -- The loot box keeps the layout the game gives it (full-screen coordinates) and is only drawn at half
            -- scale inside its owner's half: point (x, y) maps to (x/2 + W/4, y/2 [+ H/2]). Pivot at its top-left, so
            -- the translation moves that corner to where the mapping puts it. Owner: it showed full size over both.
            local o = slot:GetOffsets()
            local W = H * 16 / 9
            pcall(function() W = layoutLibrary:GetViewportSize(viewportWorld()).X / layoutLibrary:GetViewportScale(viewportWorld()) end)
            local tx = (o.Left / 2 + W / 4) - o.Left
            local ty = (o.Top / 2 + ((index == 0) and 0 or H / 2)) - o.Top
            local key = w:GetFullName() .. "#loot"
            local last = originalChildOffsets[key]
            if not last or math.abs(last.tx - tx) > 0.5 or math.abs(last.ty - ty) > 0.5 then
                c:SetRenderTransformPivot({ X = 0, Y = 0 })
                c:SetRenderScale({ X = 0.5, Y = 0.5 })
                c:SetRenderTranslation({ X = tx, Y = ty })
                originalChildOffsets[key] = { tx = tx, ty = ty }
                logOnce("loot box drawn at half scale in its owner's half")
            end
        elseif not CANVAS_SKIP[cname] and slot and slot:IsValid() and slot:GetClass():GetFName():ToString() == "CanvasPanelSlot" then
            local key = w:GetFullName() .. "#" .. cname
            local o = slot:GetOffsets()
            local base = originalChildOffsets[key]
            if not base then
                local a = slot:GetAnchors()
                base = { Left = o.Left, Top = o.Top, Right = o.Right, Bottom = o.Bottom,
                    minY = a.Minimum.Y, maxY = a.Maximum.Y }
                originalChildOffsets[key] = base
            end
            -- Reference anchor: for stretched elements the edge anchor nearer to the screen edge (the top-left icon
            -- row is anchored 0..0.13: its mid anchor moved player 1's icons up 35 px, cut off, and put player 2's
            -- at 505 instead of 540, over player 1's half).
            local aMid = (base.minY + base.maxY) / 2
            local ref = (base.minY == base.maxY) and base.minY or ((aMid < 0.5) and base.minY or base.maxY)
            local shift = (index == 0) and (-ref * H / 2) or ((1 - ref) * H / 2)
            local stretched = base.minY ~= base.maxY
            local want = { Left = base.Left, Top = base.Top + shift, Right = base.Right,
                Bottom = stretched and (base.Bottom - shift) or base.Bottom }
            if math.abs(o.Top - want.Top) > 0.5 or math.abs(o.Bottom - want.Bottom) > 0.5 then
                slot:SetOffsets(want)
                logOnce("HUD canvas children moved into player halves")
            end
        end
    end
end

local function confineToHalf(w, index, half)
    panelClass = panelClass or StaticFindObject("/Script/UMG.PanelWidget")
    local root = w.WidgetTree.RootWidget
    if not (root and root:IsValid() and root:IsA(panelClass)) then
        logOnce("not a panel root, left alone: " .. w:GetClass():GetFName():ToString())
        return
    end
    -- Diagnostics: layer names listed (one per line) in Mods/SplitScreenCoop/skip_layers.txt are left alone.
    if skipLayers == nil then
        skipLayers = {}
        local f = io.open("Mods/SplitScreenCoop/skip_layers.txt", "r")
        if f then
            for line in f:lines() do
                local n = line:match("^%s*(%S+)")
                if n then skipLayers[n] = true end
            end
            f:close()
            log("skip_layers.txt: layers left alone")
        end
    end
    for i = 0, root:GetChildrenCount() - 1 do
        local child = root:GetChildAt(i)
        local slot = child.Slot
        if skipLayers[child:GetFName():ToString()] then
            logOnce("layer left alone: " .. child:GetFName():ToString())
        elseif child:GetFName():ToString() == CANVAS_LAYER and child:IsA(panelClass) then
            moveCanvasChildren(w, child, index, half)
        elseif slot and slot:IsValid() and slot:GetClass():GetFName():ToString() == "CanvasPanelSlot" then
            local a = slot:GetAnchors()
            if a.Minimum.X == 0 and a.Minimum.Y == 0 and a.Maximum.X == 1 and a.Maximum.Y == 1 then
                local key = w:GetFullName() .. "#" .. i
                local o = slot:GetOffsets()
                local base = originalOffsets[key]
                if not base then
                    base = { Left = o.Left, Top = o.Top, Right = o.Right, Bottom = o.Bottom }
                    originalOffsets[key] = base
                end
                local want = {
                    Left = base.Left,
                    Top = base.Top + (index == 0 and 0 or half),
                    Right = base.Right,
                    Bottom = base.Bottom + (index == 0 and half or 0),
                }
                if o.Left ~= want.Left or o.Top ~= want.Top or o.Right ~= want.Right or o.Bottom ~= want.Bottom then
                    slot:SetOffsets(want)
                    logOnce("confined to player half: " .. w:GetClass():GetFName():ToString())
                end
            end
        end
    end
end

local halfWidgets = nil -- { {widget, ownerIndex}, ... } for the current world
local halfWidgetsScanned = nil

local function layoutHalfScreenWidgets(world)
    if halfWidgets then
        for _, e in ipairs(halfWidgets) do
            if not e[1]:IsValid() then halfWidgets = nil break end
        end
    end
    -- 2 widget classes x 2 players; if some are missing, rescan at most every 10 s.
    if not halfWidgets or (#halfWidgets < 4 and os.time() - (halfWidgetsScanned or 0) >= 10) then
        halfWidgetsScanned = os.time()
        halfWidgets = {}
        for _, cls in ipairs(HALF_SCREEN_WIDGETS) do
            for _, w in ipairs(FindAllOf(cls) or {}) do
                if w:IsValid() then
                    local index = ownerIndex(w, world)
                    if index then halfWidgets[#halfWidgets + 1] = { w, index } end
                end
            end
        end
        log("half-screen widgets found: " .. #halfWidgets)
    end
    local half = halfScreenHeight(world)
    for _, e in ipairs(halfWidgets) do confineToHalf(e[1], e[2], half) end
end

-- Player menus (inventory, skills, crafting, map, journal...) are drawn as a half-size copy of the full-screen menu:
-- each root canvas layer of the PlayerMenu (backgrounds, manila box, sub-menu overlay, safe zone) is moved into
-- ScaleBox > SizeBox(full screen size minus its margin), and the ScaleBox is placed in a W/2 x H/2 box centred in
-- the owner's half. The menu lays out exactly as on a full screen and the ScaleBox shrinks it in LAYOUT, so Slate
-- gamepad navigation still works (RenderScale broke it; offsets alone squeezed the fixed-size fonts of the skills
-- and crafting menus). Owner-checked live, 2026-11-07.
local MENU_LAYER_MARGIN = { PlayerMenuBackgrounds = 0, MenuManilaBox = 0, SubMenuOverlay = 0, SafeZoneCanvas = 30 }
local menuChecked = {}
local scaleBoxClass, sizeBoxClass = nil, nil

local function wrapMenuLayers(m, root, W, H)
    scaleBoxClass = scaleBoxClass or StaticFindObject("/Script/UMG.ScaleBox")
    sizeBoxClass = sizeBoxClass or StaticFindObject("/Script/UMG.SizeBox")
    local layers = {}
    for j = 0, root:GetChildrenCount() - 1 do
        local c = root:GetChildAt(j)
        if MENU_LAYER_MARGIN[c:GetFName():ToString()] then layers[#layers + 1] = c end
    end
    if #layers == 0 then return false end
    for _, layer in ipairs(layers) do layer:RemoveFromParent() end
    for _, layer in ipairs(layers) do
        local nm = layer:GetFName():ToString()
        local b = MENU_LAYER_MARGIN[nm]
        local sb = StaticConstructObject(scaleBoxClass, m.WidgetTree, FName("CoopScale_" .. nm))
        local sz = StaticConstructObject(sizeBoxClass, m.WidgetTree, FName("CoopSize_" .. nm))
        sz:SetWidthOverride(W - 2 * b)
        sz:SetHeightOverride(H - 2 * b)
        sz:AddChild(layer)
        sb:AddChild(sz)
        root:AddChildToCanvas(sb)
    end
    return true
end

local function layoutPlayerMenus(world)
    local W, H = nil, nil
    local now = os.clock()
    for i = 0, 1 do
        local pc = statics():GetPlayerController(world, i)
        local m = pc and pc:IsValid() and pc.PlayerMenu
        if m and m:IsValid() and not (menuChecked[i] and now - menuChecked[i] < 0.5) then
            menuChecked[i] = now
            if not W then
                layoutLibrary = layoutLibrary or StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
                local px = layoutLibrary:GetViewportSize(world)
                local sc = layoutLibrary:GetViewportScale(world)
                W, H = px.X / sc, px.Y / sc
            end
            if m.RenderTransform.Scale.X ~= 1 then m:SetRenderScale({ X = 1, Y = 1 }) end
            local root = m.WidgetTree.RootWidget
            if wrapMenuLayers(m, root, W, H) then
                logOnce("player menu layers wrapped in half-size scale boxes for player " .. (i + 1))
            end
            for j = 0, root:GetChildrenCount() - 1 do
                local c = root:GetChildAt(j)
                local nm = c:GetFName():ToString():match("^CoopScale_(.+)$")
                local b = nm and MENU_LAYER_MARGIN[nm]
                if b then
                    local slot = c.Slot
                    local want = { X = W / 4 + b / 2, Y = ((i == 0) and 0 or H / 2) + b / 2 }
                    local pos = slot:GetPosition()
                    if math.abs(pos.X - want.X) > 0.5 or math.abs(pos.Y - want.Y) > 0.5 then
                        slot:SetPosition(want)
                        slot:SetSize({ X = (W - 2 * b) / 2, Y = (H - 2 * b) / 2 })
                    end
                end
            end
        end
    end
end


-- Visible bodies. Each pawn's own mesh is first-person arms (FPP_Arthur, bOnlyOwnerSee), so the
-- other player saw floating arms. The full-body SK_Arthur is in memory, but no animation in memory
-- uses its skeleton (0 of 1194 AnimSequences), so it stays in T-pose. NPC citizen meshes and the
-- male NPC animations share Common_NPC_Skeleton and are loaded on the story map. Each player gets a
-- SkeletalMeshActor with an NPC mesh, attached to the pawn, owned by it and bOwnerNoSee (only the
-- other player sees it), playing idle/walk/run with PlayAnimation by the pawn's speed.
-- The *_RM walk/run play in place on the single-node instance (owner-checked, 2026-11-03).
local BODY_MESHES = {
    "/Game/Character/Common_NPCs/GenericMaleNPC/SK_Male_SweaterVest.SK_Male_SweaterVest",
    "/Game/Character/Common_NPCs/GenericMaleNPC/Male_NPC.Male_NPC",
}
local ANIM = {
    idle = "/Game/Animations/Male_NPC/Male_Idle.Male_Idle",
    walk = "/Game/Animations/Male_NPC/Male_Walk_RM.Male_Walk_RM",
    run = "/Game/Animations/Male_NPC/Male_Run_RM.Male_Run_RM",
    fall = "/Game/Animations/Male_NPC/Male_Fall.Male_Fall",
    land = "/Game/Animations/Male_NPC/Male_Fall_LandSoft.Male_Fall_LandSoft",
    -- NPCs never crouch: no crouch anim exists on Common_NPC_Skeleton. Candidates: Male_Cower,
    -- Bobby_InvestigateGround_Look (crouched looking at the ground).
    crouch = "/Game/Animations/Bobby_NPC/Bobby_InvestigateGround_Look.Bobby_InvestigateGround_Look",
    -- First one in memory is used (Male_DeadGround_Pose04 is not loaded in the sandbox).
    down = {
        "/Game/Animations/Male_NPC/Male_DeadGround_Pose04.Male_DeadGround_Pose04",
        "/Game/Animations/Male_NPC/Male_DeadGround_Floating_Pose02.Male_DeadGround_Floating_Pose02",
        "/Game/Animations/Male_NPC/Male_SitGround_Idle.Male_SitGround_Idle",
        "/Game/Animations/Male_NPC/Male_Cower.Male_Cower",
    },
}
local LOOPING = { idle = true, walk = true, run = true, fall = true, crouch = true, land = false, down = true }
local LAND_SECONDS = 0.4
-- Normal walking reaches MaxWalkSpeed 540; at 400 the run anim played while walking (owner).
local WALK_SPEED, RUN_SPEED = 20, 600 -- cm/s
local loggedSpeed = {}
local bodies = {} -- pawn full name -> { actor = ..., state = ... }

local function valid(o) return o ~= nil and o:IsValid() end

local function findFirst(paths)
    for _, p in ipairs(paths) do
        local o = StaticFindObject(p)
        if valid(o) then return o end
    end
    return nil
end

local function ensureBody(world, pawn)
    local key = pawn:GetFullName()
    local b = bodies[key]
    if b and valid(b.actor) then return b end
    local mesh = findFirst(BODY_MESHES)
    if not mesh then
        logOnce("no NPC body mesh in memory on this map")
        return nil
    end
    local actor = world:SpawnActor(StaticFindObject("/Script/Engine.SkeletalMeshActor"), {}, {})
    if not valid(actor) then
        logOnce("could not spawn a body actor")
        return nil
    end
    local comp = actor.SkeletalMeshComponent
    -- SetMobility errors under UE4SS 3.0.1 here; spawned SkeletalMeshActors are already Movable (2).
    comp:SetSkeletalMesh(mesh, true)
    comp:SetCollisionEnabled(0)
    comp:SetOwnerNoSee(true)
    actor:SetOwner(pawn)
    actor:K2_AttachToActor(pawn, FName("None"), 2, 2, 1, false) -- snap location/rotation, keep scale
    local hh = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    comp:K2_SetRelativeLocation({ X = 0, Y = 0, Z = -hh }, false, {}, false)
    comp:K2_SetRelativeRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, false)
    b = { actor = actor, state = nil }
    bodies[key] = b
    log("body attached to " .. name(pawn) .. " (" .. name(actor) .. ", " .. name(mesh) .. ")")
    return b
end

-- Arthur: the NPC body above keeps playing the animations (only Common_NPC_Skeleton has locomotion), shrunk to 1% so
-- nobody sees it (BoundsScale x100 keeps it "rendered", so its bones keep updating: a hidden NPC body froze Arthur),
-- and a PoseableMeshComponent with SK_Arthur attached to it is posed from it every frame (arthur_retarget.lua).
-- SK_Arthur is not loaded on most maps: CoopMenuFix v13+ loads it; the Lua cannot register a component it creates:
-- CoopMenuFix v14+ registers it when ResetBoneTransformByName is called on it unregistered.
local ARTHUR_MESH = "/Game/Character/Narrative/Arthur/SK_Arthur.SK_Arthur"
local NPC_HIDE_SCALE = 0.01
local okRetarget, arthurRetarget = pcall(require, "arthur_retarget")
local poseableClass = nil
local dllRegisters = nil

local function dllCanRegister()
    if dllRegisters == nil then
        dllRegisters = false
        local f = io.open("Mods/CoopMenuFix/menufix.log", "r")
        if f then
            -- Per DLL start: "registration hook ... ready" comes just before "vN hooked ShowPlayerMenuWithContext".
            local pending = false
            for line in f:lines() do
                if line:find("registration hook on ResetBoneTransformByName ready") then pending = true end
                if line:find("hooked ShowPlayerMenuWithContext") then dllRegisters = pending; pending = false end
            end
            f:close()
        end
        log("CoopMenuFix component registration " .. (dllRegisters and "available" or "NOT available: Arthur body off"))
    end
    return dllRegisters
end

local function ensureArthur(b, pawn)
    if b.pose or b.arthurOff then return end
    if not okRetarget then
        logOnce("arthur_retarget.lua failed to load: " .. tostring(arthurRetarget))
        b.arthurOff = true
        return
    end
    if not dllCanRegister() then b.arthurOff = true return end
    local mesh = StaticFindObject(ARTHUR_MESH)
    if not valid(mesh) then
        logOnce("waiting for SK_Arthur (loaded by CoopMenuFix)")
        return
    end
    poseableClass = poseableClass or StaticFindObject("/Script/Engine.PoseableMeshComponent")
    local npc = b.actor.SkeletalMeshComponent
    local p = StaticConstructObject(poseableClass, b.actor, FName("CoopArthurBody"))
    p:SetSkeletalMesh(mesh, true)
    p:SetCollisionEnabled(0)
    p:SetOwnerNoSee(true)
    p:ResetBoneTransformByName(FName("None")) -- CoopMenuFix registers it
    p:K2_AttachToComponent(npc, FName("None"), 2, 2, 2, false)
    p:Activate(true)
    p:SetComponentTickEnabled(true)
    npc.BoundsScale = 1 / NPC_HIDE_SCALE
    npc:SetRelativeScale3D({ X = NPC_HIDE_SCALE, Y = NPC_HIDE_SCALE, Z = NPC_HIDE_SCALE })
    p:SetRelativeScale3D({ X = 1 / NPC_HIDE_SCALE, Y = 1 / NPC_HIDE_SCALE, Z = 1 / NPC_HIDE_SCALE })
    b.pose = p
    log("Arthur body on " .. name(pawn))
end

-- Keeps the body's feet on the ground: crouching shrinks the capsule (88 -> 49 half height) around a
-- lowered centre, so the body's offset follows the current half height.
local function placeBody(b, pawn)
    local hh = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    if b.hh ~= hh then
        b.actor.SkeletalMeshComponent:K2_SetRelativeLocation({ X = 0, Y = 0, Z = -hh }, false, {}, false)
        b.hh = hh
    end
end

local function animateBody(b, pawn)
    placeBody(b, pawn)
    local okA, errA = pcall(ensureArthur, b, pawn)
    if not okA then
        logOnce("Arthur body error: " .. tostring(errA))
        b.arthurOff = true
    end
    local falling = pawn.CharacterMovement:IsFalling()
    local want
    if b.downed then
        want = "down"
    elseif falling then
        want = "fall"
    elseif b.state == "fall" then
        want, b.landUntil = "land", os.clock() + LAND_SECONDS
    elseif b.state == "land" and os.clock() < (b.landUntil or 0) then
        return
    elseif pawn.bIsCrouched then
        want = "crouch"
    else
        local v = pawn:GetVelocity()
        local speed = math.sqrt(v.X * v.X + v.Y * v.Y)
        want = speed < WALK_SPEED and "idle" or (speed < RUN_SPEED and "walk" or "run")
    end
    if b.state == want then return end
    local seq = type(ANIM[want]) == "table" and findFirst(ANIM[want]) or StaticFindObject(ANIM[want])
    if not valid(seq) then
        logOnce("animation not in memory: " .. want)
        b.state = want
        return
    end
    b.actor.SkeletalMeshComponent:PlayAnimation(seq, LOOPING[want])
    b.state = want
    log("body " .. name(pawn) .. " -> " .. want)
end

-- Bodies are keyed by pawn full name and never keep the pawn object: a pawn destroyed on death (player 2 fell
-- out of the world) was still touched through a cached reference and crashed UE4SS (UE4SS.dll+0x4BAAAF).
-- A body whose pawn is gone is destroyed (it would otherwise stay where the pawn died).
local function ensureBodies(world)
    local live = {}
    for i = 0, 1 do
        local pc = statics():GetPlayerController(world, i)
        if valid(pc) and valid(pc.Pawn) then
            local pawn = pc.Pawn
            live[pawn:GetFullName()] = true
            local ok, err = pcall(function()
                local b = ensureBody(world, pawn)
                if b then animateBody(b, pawn) end
            end)
            if not ok then logOnce("body error: " .. tostring(err)) end
        end
    end
    for key, b in pairs(bodies) do
        if not live[key] then
            if valid(b.actor) then pcall(function() b.actor:K2_DestroyActor() end) end
            bodies[key] = nil
            log("body of a gone pawn removed")
        end
    end
end

local currentWorld = nil
local activeWorld = nil -- world object while split, for the fast loop
local menuWasOpen = { false, false }
local menuOpenedAt = nil -- os.clock() when a player menu last opened
local UNDO_PAUSE_WINDOW = 1.5 -- seconds after an opening in which its pause is undone

-- Opening a player menu pauses the game through a pause counter on the GameInstance's UI stack
-- (SetPause(true) only when the counter goes 0 -> 1; RE notes phase 9). While split, a player's
-- inventory must not stop the other player, so that pause is undone, but only in the first moments
-- after an opening: the real pause menu (and quitting from it) must still pause. v1 undid every pause
-- while an inventory was open, including the pause menu's.
local function undoMenuPause(world)
    for i = 0, 1 do
        local pc = statics():GetPlayerController(world, i)
        local open = valid(pc) and pc:IsPlayerMenuVisible() or false
        if open and not menuWasOpen[i + 1] then menuOpenedAt = os.clock() end
        menuWasOpen[i + 1] = open
    end
    if menuOpenedAt and os.clock() - menuOpenedAt <= UNDO_PAUSE_WINDOW and statics():IsGamePaused(world) then
        statics():SetGamePaused(world, false)
        log("player menu opened: pause undone")
        menuOpenedAt = nil
    end
end

-- Cutscenes. The game sets AGlimpsePlayerController.bCutsceneInputMode on the controller whose player is in
-- the cutscene. While any controller has it: one full-screen view (bUseSplitscreen off, laid out again every
-- frame by the engine), the co-op bodies and the half-screen HUDs hidden, the other player teleported behind
-- the cutscene player with its input ignored. If the cutscene player is player 2, player 1's view (the one
-- shown full screen) follows player 2's view target. Everything is undone when the flag clears.
local cutscene = nil -- { owner = 0|1, viewFollow = bool, widgets = { {w, visibility}, ... } }
local pendingRegroup = nil -- { at = os.clock() time, owner = 0|1 } after a cutscene ends
local fallingSince = { nil, nil }
local lastPos = { nil, nil }
local p2PawnName = nil -- player 2's current pawn; a new one is brought next to player 1

local function inCutsceneMode(pc)
    local ok, v = pcall(function() return pc.bCutsceneInputMode end)
    return ok and v == true
end

local ownTeleportAt = 0 -- os.clock() of the mod's last teleport (not a game teleport)

local function teleportBehind(pawn, target)
    ownTeleportAt = os.clock()
    local loc, rot = target:K2_GetActorLocation(), target:K2_GetActorRotation()
    local yaw = math.rad(rot.Yaw)
    local fx, fy = math.cos(yaw), math.sin(yaw)
    for _, off in ipairs({ { -120, 0 }, { 0, 120 }, { 0, -120 }, { 120, 0 }, { -200, 0 }, { 0, 200 }, { 0, -200 }, { 200, 0 } }) do
        -- off = { forward, right } in the target's frame
        local dest = { X = loc.X + fx * off[1] - fy * off[2], Y = loc.Y + fy * off[1] + fx * off[2], Z = loc.Z }
        if pawn:K2_TeleportTo(dest, { Pitch = 0, Yaw = rot.Yaw, Roll = 0 }) then
            -- TeleportTo may push the pawn to a nearby free spot; accept it only if it stayed close.
            local got = pawn:K2_GetActorLocation()
            local dx, dy, dz = got.X - dest.X, got.Y - dest.Y, got.Z - dest.Z
            if dx * dx + dy * dy + dz * dz < 60 * 60 then return true end
        end
    end
    return false
end

-- Safe placement (2026-11-07: in the campaign player 2 was put "behind" player 1 on the far side of a thin wall,
-- outside the level, fell and died, and the game went back to the checkpoint). Candidates, in order:
--   1. breadcrumbs: spots where the target player recently stood on the ground (proven floor), 1-10 m away, newest
--      first, at a similar height;
--   2. the fixed offsets around the target (old behaviour);
--   3. the target's own location (TeleportTo moves the pawn to the nearest free spot).
-- Each try is verified 0.5 s later: if the moved player is falling and already 1.5 m below the spot, the next
-- candidate is tried. (No line traces: UE4SS 3.0.1 could not call LineTraceSingle_NEW here.)
local crumbs = {} -- pawn full name -> { {X, Y, Z}, ... } newest last
local MAX_CRUMBS = 40
local safeMove = nil -- { mover = 1|2, target = 1|2, cands = {...}, idx = n, verifyAt = t, z = Z, reason = s }

local function recordCrumb(pawn)
    local key = pawn:GetFullName()
    local list = crumbs[key]
    if not list then list = {}; crumbs[key] = list end
    local p = pawn:K2_GetActorLocation()
    local last = list[#list]
    if last then
        local dx, dy, dz = p.X - last[1], p.Y - last[2], p.Z - last[3]
        if dx * dx + dy * dy + dz * dz < 75 * 75 then return end
    end
    list[#list + 1] = { p.X, p.Y, p.Z }
    if #list > MAX_CRUMBS then table.remove(list, 1) end
end

local function safeCandidates(target)
    local loc, rot = target:K2_GetActorLocation(), target:K2_GetActorRotation()
    local cands = {}
    local list = crumbs[target:GetFullName()] or {}
    for k = #list, 1, -1 do
        local c = list[k]
        local dx, dy, dz = c[1] - loc.X, c[2] - loc.Y, c[3] - loc.Z
        local d2 = dx * dx + dy * dy
        if d2 >= 100 * 100 and d2 <= 1000 * 1000 and math.abs(dz) < 250 then
            cands[#cands + 1] = { X = c[1], Y = c[2], Z = c[3] + 5, yaw = rot.Yaw, kind = "breadcrumb" }
            if #cands >= 6 then break end
        end
    end
    local yaw = math.rad(rot.Yaw)
    local fx, fy = math.cos(yaw), math.sin(yaw)
    for _, off in ipairs({ { -120, 0 }, { 0, 120 }, { 0, -120 }, { 120, 0 } }) do
        cands[#cands + 1] = { X = loc.X + fx * off[1] - fy * off[2], Y = loc.Y + fy * off[1] + fx * off[2], Z = loc.Z,
            yaw = rot.Yaw, kind = "offset" }
    end
    cands[#cands + 1] = { X = loc.X, Y = loc.Y, Z = loc.Z + 10, yaw = rot.Yaw, kind = "on target", last = true }
    return cands
end

-- Tries candidates from safeMove.idx until TeleportTo accepts one; returns true if one was.
local function trySafeCandidates(pawn)
    local m = safeMove
    while m.idx <= #m.cands do
        local c = m.cands[m.idx]
        ownTeleportAt = os.clock()
        local ok = pawn:K2_TeleportTo({ X = c.X, Y = c.Y, Z = c.Z }, { Pitch = 0, Yaw = c.yaw, Roll = 0 })
        if ok then
            local got = pawn:K2_GetActorLocation()
            local dx, dy, dz = got.X - c.X, got.Y - c.Y, got.Z - c.Z
            if c.last or dx * dx + dy * dy + dz * dz < 80 * 80 then
                m.verifyAt, m.z = os.clock() + 0.5, got.Z
                log(string.format("%s: player %d -> %s spot %d/%d near player %d", m.reason, m.mover, c.kind, m.idx, #m.cands, m.target))
                return true
            end
        end
        m.idx = m.idx + 1
    end
    log(m.reason .. ": no spot accepted for player " .. m.mover)
    safeMove = nil
    return false
end

local function teleportSafe(pcs, mover, target, reason)
    local pawn, tpawn = pcs[mover].Pawn, pcs[target].Pawn
    if not (valid(pawn) and valid(tpawn)) then return false end
    safeMove = { mover = mover, target = target, cands = safeCandidates(tpawn), idx = 1, reason = reason,
        moverName = pawn:GetFullName() }
    return trySafeCandidates(pawn)
end

-- Every fast step: verifies the last safe move and retries with the next candidate if the spot was bad.
local function verifySafeMove(pcs)
    local m = safeMove
    if not (m and m.verifyAt and os.clock() >= m.verifyAt) then return end
    local pawn = pcs[m.mover].Pawn
    if not (valid(pawn) and pawn:GetFullName() == m.moverName) then safeMove = nil return end
    local p = pawn:K2_GetActorLocation()
    if pawn.CharacterMovement:IsFalling() and p.Z < m.z - 150 and m.idx < #m.cands then
        log(string.format("%s: spot %d was bad (falling, %.0f cm below), trying the next one", m.reason, m.idx, m.z - p.Z))
        m.idx, m.verifyAt = m.idx + 1, nil
        trySafeCandidates(pawn)
    else
        safeMove = nil
    end
end

local killZ = nil -- current world's KillZ (nil: unknown / none)

local function setBodiesHidden(hidden)
    for _, b in pairs(bodies) do
        if valid(b.actor) then b.actor:SetActorHiddenInGame(hidden) end
    end
end

local function startCutscene(world, pcs, owner)
    local a, b = pcs[owner + 1], pcs[2 - owner]
    cutscene = { owner = owner, viewFollow = false, widgets = {} }
    log("cutscene started (player " .. (owner + 1) .. ")")
    b:SetIgnoreMoveInput(true)
    b:SetIgnoreLookInput(true)
    UEHelpers.GetGameMapsSettings().bUseSplitscreen = false
    setBodiesHidden(true)
    for _, e in ipairs(halfWidgets or {}) do
        if e[1]:IsValid() then
            cutscene.widgets[#cutscene.widgets + 1] = { e[1], e[1]:GetVisibility() }
            e[1]:SetVisibility(2) -- Hidden
        end
    end
    cutscene.viewFollow = owner == 1
end

local function endCutscene(pcs)
    local b = pcs[2 - cutscene.owner]
    UEHelpers.GetGameMapsSettings().bUseSplitscreen = true
    if valid(b) then
        b:ResetIgnoreMoveInput()
        b:ResetIgnoreLookInput()
    end
    if cutscene.viewFollow and valid(pcs[1]) and valid(pcs[1].Pawn) then
        pcall(function() pcs[1]:SetViewTargetWithBlend(pcs[1].Pawn, 0, 0, 0, false) end)
    end
    setBodiesHidden(false)
    for _, e in ipairs(cutscene.widgets) do
        if e[1]:IsValid() then e[1]:SetVisibility(e[2]) end
    end
    log("cutscene ended (player " .. (cutscene.owner + 1) .. ")")
    -- The cutscene may leave its player somewhere else (another room). Half a second later, when the game
    -- has placed that player, the other one is brought next to it. (At the start, "behind the player" was
    -- inside the censorship machine's desk.)
    pendingRegroup = { at = os.clock() + 0.5, owner = cutscene.owner }
    cutscene = nil
end

-- Unstuck: a player holding Select/View (Gamepad_Special_Left) for 2 s is brought next to the other player.
local unstuckSince = { nil, nil }
local selectKey = nil

local function checkUnstuck(pcs)
    selectKey = selectKey or { KeyName = FName("Gamepad_Special_Left") }
    for i = 1, 2 do
        local pc, other = pcs[i], pcs[3 - i]
        local ok, down = pcall(function() return pc:IsInputKeyDown(selectKey) end)
        if ok and down then
            unstuckSince[i] = unstuckSince[i] or os.clock()
            if os.clock() - unstuckSince[i] >= 2.0 and valid(pc.Pawn) and valid(other.Pawn) then
                unstuckSince[i] = nil
                teleportSafe(pcs, i, 3 - i, "unstuck")
            end
        else
            unstuckSince[i] = nil
        end
    end
end

local function updateCutscene(world)
    local pcs = { statics():GetPlayerController(world, 0), statics():GetPlayerController(world, 1) }
    if not (valid(pcs[1]) and valid(pcs[2])) then return end
    verifySafeMove(pcs)
    if pendingRegroup and os.clock() >= pendingRegroup.at then
        local a, b = pcs[pendingRegroup.owner + 1], pcs[2 - pendingRegroup.owner]
        if valid(a.Pawn) and valid(b.Pawn) then
            teleportSafe(pcs, 2 - pendingRegroup.owner, pendingRegroup.owner + 1, "regroup")
        end
        pendingRegroup = nil
    end
    if not cutscene then checkUnstuck(pcs) end
    -- Keep together across game teleports. Single-player transitions (shelter ladders, hatches, fast travel)
    -- move player 1 even when player 2 used them; any far jump of one player that the mod did not cause brings
    -- the other player along.
    for i = 1, 2 do
        local pawn = pcs[i].Pawn
        if valid(pawn) then
            local p = pawn:K2_GetActorLocation()
            local last = lastPos[i]
            lastPos[i] = { X = p.X, Y = p.Y, Z = p.Z, pawn = pawn:GetFullName() }
            if last and last.pawn == lastPos[i].pawn and not cutscene and os.clock() - ownTeleportAt > 1.0 then
                local dx, dy, dz = p.X - last.X, p.Y - last.Y, p.Z - last.Z
                if dx * dx + dy * dy + dz * dz > 1500 * 1500 and valid(pcs[3 - i].Pawn) then
                    crumbs[pawn:GetFullName()] = nil -- its old breadcrumbs are somewhere else now
                    teleportSafe(pcs, 3 - i, i, "player " .. i .. " was teleported by the game, follow")
                    lastPos[3 - i] = nil
                end
            end
        end
    end
    do
        -- Fall safety (also during cutscenes): a player falling for 3 s while the other stands is brought next to the other
        -- (player 2 spawned at the prologue's PlayerStart, outside the playable area, and fell to death).
        for i = 1, 2 do
            local pawn, other = pcs[i].Pawn, pcs[3 - i].Pawn
            if valid(pawn) and valid(other) and pawn.CharacterMovement:IsFalling() then
                fallingSince[i] = fallingSince[i] or os.clock()
                local t = os.clock() - fallingSince[i]
                local z, oz = pawn:K2_GetActorLocation().Z, other:K2_GetActorLocation().Z
                local otherGround = not other.CharacterMovement:IsFalling()
                -- Out of the world: near the map's KillZ, falling 1.2 s and 3 m below a standing partner, or 3 s.
                local why = nil
                if killZ and z < killZ + 1500 then why = "near KillZ"
                elseif t >= 1.2 and otherGround and z < oz - 300 then why = "falling below partner"
                elseif t >= 3.0 and otherGround then why = "falling 3 s" end
                if why and not (safeMove and safeMove.mover == i) then
                    fallingSince[i] = nil
                    teleportSafe(pcs, i, 3 - i, "fall safety (" .. why .. ")")
                end
            else
                fallingSince[i] = nil
                -- Breadcrumbs: spots this player stood on (not right after a teleport, not during cutscenes).
                if valid(pawn) and not cutscene and os.clock() - ownTeleportAt > 1.0 and pawn.CharacterMovement:IsMovingOnGround() then
                    recordCrumb(pawn)
                end
            end
        end
    end
    local m1, m2 = inCutsceneMode(pcs[1]), inCutsceneMode(pcs[2])
    if not cutscene and (m1 or m2) then
        startCutscene(world, pcs, m1 and 0 or 1)
    elseif cutscene and not (m1 or m2) then
        endCutscene(pcs)
    elseif cutscene then
        setBodiesHidden(true) -- a body respawned during the cutscene starts visible
        if cutscene.viewFollow then
            -- Cutscene camera cuts change player 2's view target; player 1's full-screen view follows it.
            -- (UE4SS userdata compare by wrapper, not by object: compare full names.)
            local vt, cur = pcs[2]:GetViewTarget(), pcs[1]:GetViewTarget()
            if valid(vt) and not (valid(cur) and cur:GetFullName() == vt:GetFullName()) then
                pcall(function() pcs[1]:SetViewTargetWithBlend(vt, 0, 0, 0, false) end)
            end
        end
    end
end

-- Co-op death: a lethal hit on a player is clamped (ReceiveTakeDamage hook below) so health stops at LAST_HEALTH.
-- A player whose health reaches DOWN_RATIO is downed: no movement (look allowed), crouched (low camera), body lying
-- for the other player. The other player revives by holding X (Gamepad_FaceButton_Left) within REVIVE_RANGE for
-- REVIVE_SECONDS; health comes back at REVIVE_HEALTH. If both are down, player 1 is killed so the game's own death
-- flow (death screen, reload) runs as in single player. (USurvivalComponent::DemiGod was tried first: in this game
-- it makes the character take no damage at all.)
local HEALTH = 0 -- ESurvivalNeed::Health
local REVIVE_RANGE, REVIVE_SECONDS, REVIVE_HEALTH = 200, 3.0, 0.3
-- Health is a 0..1 ratio here (GetStatMax = 1). v1 used an absolute floor of 1.5, so both players counted as
-- down at once and player 1 was killed. A downed player's health is held at DOWNED_HEALTH: the game's
-- low-health grey screen is window-wide and greyed both halves.
local DOWN_RATIO, DOWNED_HEALTH = 0.03, 0.5
local downed = { false, false }
local demigodPawn = { nil, nil }
local reviveSince = { nil, nil }
local reviveKey = nil
local gameOver = false
local reviveInfo = { { near = false, pct = nil }, { near = false, pct = nil } } -- per downed player

-- Revive prompts: a skull and a line of text added to each player's LightHUDWidget root canvas (so they sit in
-- that player's half and hide with the HUD during cutscenes). Position is in root-canvas units (viewport/scale).
local SKULL = "/Game/UI/PlayerMenu/Skull.Skull"
local reviveUi = { nil, nil } -- [player] = { hud = name, text, textSlot, skull, skullSlot }

local function playerHud(i)
    for _, e in ipairs(halfWidgets or {}) do
        if e[2] == i - 1 and e[1]:IsValid() and e[1]:GetClass():GetFName():ToString() == "LightHUDWidget_C" then return e[1] end
    end
end

local function ensureReviveUi(i, world)
    local hud = playerHud(i)
    if not hud then return nil end
    local u = reviveUi[i]
    if u and u.hud == hud:GetFullName() and u.text:IsValid() then return u end
    local root = hud.WidgetTree.RootWidget
    local text = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), hud.WidgetTree, FName("CoopReviveText"))
    local textSlot = root:AddChild(text)
    local skull = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), hud.WidgetTree, FName("CoopReviveSkull"))
    local skullSlot = root:AddChild(skull)
    pcall(function() skull:SetBrushFromTexture(StaticFindObject(SKULL), false) end)
    pcall(function()
        local f = text.Font
        text:SetFont({ FontObject = f.FontObject, FontMaterial = f.FontMaterial, TypefaceFontName = f.TypefaceFontName, Size = 30 })
    end)
    pcall(function() text:SetShadowOffset({ X = 2, Y = 2 }) end)
    pcall(function() text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 1 }) end)
    textSlot:SetAutoSize(true)
    textSlot:SetAlignment({ X = 0.5, Y = 0.5 })
    skullSlot:SetSize({ X = 96, Y = 96 })
    skullSlot:SetAlignment({ X = 0.5, Y = 0.5 })
    u = { hud = hud:GetFullName(), text = text, textSlot = textSlot, skull = skull, skullSlot = skullSlot, shown = nil }
    reviveUi[i] = u
    log("revive prompt widgets created for player " .. i)
    return u
end

local function showReviveUi(i, world, message, withSkull)
    local u = message and ensureReviveUi(i, world) or reviveUi[i]
    if not u or not u.text:IsValid() then return end
    if not message then
        if u.shown ~= false then
            u.text:SetVisibility(1) -- Collapsed
            u.skull:SetVisibility(1)
            u.shown = false
        end
        return
    end
    layoutLibrary = layoutLibrary or StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local px, sc = layoutLibrary:GetViewportSize(world), layoutLibrary:GetViewportScale(world)
    local W, H = px.X / sc, px.Y / sc
    local top = (i == 1) and 0 or H / 2
    u.skullSlot:SetPosition({ X = W / 2, Y = top + H / 2 * 0.38 })
    u.textSlot:SetPosition({ X = W / 2, Y = top + H / 2 * 0.56 })
    if u.message ~= message then
        u.text:SetText(FText(message))
        u.message = message
    end
    if u.shown ~= true or u.withSkull ~= withSkull then
        u.text:SetVisibility(3) -- HitTestInvisible
        u.skull:SetVisibility(withSkull and 3 or 1)
        u.shown, u.withSkull = true, withSkull
    end
end

local function updateReviveUi(world)
    for i = 1, 2 do
        local j = 3 - i
        local msg = nil
        if downed[i] then
            local pct = reviveInfo[i].pct
            msg = pct and string.format("Seu parceiro está te revivendo: %d%%", pct) or "Você caiu! Aguarde seu parceiro"
        elseif downed[j] then
            -- The standing player sees only the prompt, and only when close enough (owner's request).
            local info = reviveInfo[j]
            msg = info.pct and string.format("Revivendo: %d%%", info.pct) or (info.near and "Segure X para reviver" or nil)
        end
        showReviveUi(i, world, msg, downed[i])
    end
end

-- Calmed NPCs still re-targeted the downed player and cancelled swings mid-way. They also get
-- AGlimpseAICharacter::SetNoSuspicion(true) until nobody is down. (Marking the downed pawn bIsDead made the
-- game show the game-over screen.)
-- Only names are kept: a cached NPC/controller UObject can be destroyed between checks (despawn, streaming,
-- death) and touching it then crashes UE4SS.dll+0x4BAAAF. Live objects come from the current
-- FindAllOf("GlimpseAIController") list (or the damage hook's own pawn) every time.
local noSuspicionNpcs = {} -- NPC full name -> true

-- NPC full name -> { npc = character, ctrl = AI controller }, from a fresh controller list.
local function liveNpcs(controllers)
    local m = {}
    for _, c in ipairs(controllers or FindAllOf("GlimpseAIController") or {}) do
        if c:IsValid() then
            local npc = c.Pawn
            if valid(npc) then m[npc:GetFullName()] = { npc = npc, ctrl = c } end
        end
    end
    return m
end

-- One calmed NPC back to normal, aimed at `target` (the standing player who hit it or came into view).
-- SetNoSuspicion alone made calmed NPCs ignore the standing player completely, even when punched (owner).
-- `npc`/`ctrl` must be live objects fetched this frame.
local function releaseNpc(key, npc, ctrl, target, why)
    if not noSuspicionNpcs[key] then return end
    noSuspicionNpcs[key] = nil
    if valid(npc) then pcall(function() npc:SetNoSuspicion(false) end) end
    if valid(ctrl) and valid(target) then
        pcall(function() ctrl:SetTargetActor(target) end)
        pcall(function() ctrl:SetDetectionTarget(target) end)
    end
    log("calmed NPC released (" .. why .. ")")
end

local function releaseCalmedNpcs()
    local live, n = liveNpcs(), 0
    for k in pairs(noSuspicionNpcs) do
        local e = live[k]
        if e then pcall(function() e.npc:SetNoSuspicion(false) end) n = n + 1 end
        noSuspicionNpcs[k] = nil
    end
    if n > 0 then log(n .. " calmed NPC(s) back to normal suspicion") end
end

-- Lethal-hit clamp, from AGlimpseCharacter::ReceiveTakeDamage(Damage, ActualDamage&, ...): for a player pawn
-- (not after both are down), damage that would take health to 0 leaves LAST_HEALTH instead, so the player goes
-- down rather than dying.
local LAST_HEALTH = 0.02
local damageLogged = 0

local function onTakeDamage(ctx, damage, actual, damageType, instigator)
    if gameOver then return end
    local pawn = ctx:get()
    if not (pawn and pawn:IsValid()) then return end
    local key = pawn:GetFullName()
    if noSuspicionNpcs[key] then
        local ok, inst = pcall(function() return instigator:get() end)
        local attacker = ok and valid(inst) and inst.Pawn or nil
        releaseNpc(key, pawn, pawn.Controller, attacker, "was hit")
        return
    end
    local pc = pawn.Controller
    if not (valid(pc) and pc:IsA(StaticFindObject("/Script/GlimpseGame.GlimpsePlayerController"))) then return end
    local sc = pawn.SurvivalComponent
    local hp, d, a = sc:GetStat(HEALTH), damage:get(), actual:get()
    if damageLogged < 15 then
        damageLogged = damageLogged + 1
        log(string.format("damage to %s: Damage %.3f ActualDamage %.3f health %.3f", name(pawn), d, a, hp))
    end
    local hit = math.max(d, a)
    if hp - hit <= LAST_HEALTH then
        actual:set(math.max(0, hp - LAST_HEALTH))
        log(string.format("lethal hit on %s clamped (%.3f -> %.3f)", name(pawn), hit, actual:get()))
    end
end

-- NPCs kept hitting a downed player forever, and then stayed on alert next to it. While anyone is down, every
-- AGlimpseAIController whose target or detection target is a downed pawn either switches to the standing
-- player, if that player is within AI_RETARGET_RANGE of the NPC and in its line of sight, or calms down:
-- ClearSuspicion, no targets, suspicion state Suspicious (searching; it decays to normal on its own).
-- FindAllOf costs ~60 ms, so this runs every AI_RETARGET_SECONDS and only while someone is down.
local AI_RETARGET_SECONDS, AI_RETARGET_RANGE = 1.5, 1500
local SUSPICION_SUSPICIOUS = 2 -- EAISuspicionState
local lastRetarget = 0
local function retargetAIs(pcs)
    if os.clock() - lastRetarget < AI_RETARGET_SECONDS then return end
    lastRetarget = os.clock()
    local downName, standing = {}, nil
    for i = 1, 2 do
        local pawn = pcs[i].Pawn
        if valid(pawn) then
            if downed[i] then downName[pawn:GetFullName()] = true else standing = pawn end
        end
    end
    local sp = standing and standing:K2_GetActorLocation()
    local moved, calmed = 0, 0
    local controllers = FindAllOf("GlimpseAIController") or {}
    for _, c in ipairs(controllers) do
        if c:IsValid() then
            local t, d = c:GetTargetActor(), c:GetDetectionTarget()
            local onDowned = (valid(t) and downName[t:GetFullName()]) or (valid(d) and downName[d:GetFullName()])
            if onDowned then
                local npc = c.Pawn
                local near = false
                if sp and valid(npc) then
                    local np = npc:K2_GetActorLocation()
                    local dx, dy, dz = np.X - sp.X, np.Y - sp.Y, np.Z - sp.Z
                    near = dx * dx + dy * dy + dz * dz <= AI_RETARGET_RANGE * AI_RETARGET_RANGE
                    if near then
                        -- Distance alone let NPCs "see" the standing player through walls (owner).
                        local ok, los = pcall(function() return c:LineOfSightTo(standing, { X = 0, Y = 0, Z = 0 }, false) end)
                        near = ok and los == true
                    end
                end
                if near then
                    c:SetTargetActor(standing)
                    c:SetDetectionTarget(standing)
                    moved = moved + 1
                else
                    c:ClearSuspicion()
                    pcall(function() c:SetTargetActor(nil) end)
                    pcall(function() c:SetDetectionTarget(nil) end)
                    pcall(function() c:SetSuspicionState(SUSPICION_SUSPICIOUS) end)
                    if valid(npc) then
                        pcall(function() npc:SetNoSuspicion(true) end)
                        noSuspicionNpcs[npc:GetFullName()] = true
                    end
                    calmed = calmed + 1
                end
            end
        end
    end
    if moved + calmed > 0 then log("NPCs on the downed player: " .. moved .. " -> standing player, " .. calmed .. " calmed") end
    -- A calmed NPC that now sees the standing player close by reacts to it again.
    if standing then
        local live = liveNpcs(controllers) -- same list, no second FindAllOf
        for key in pairs(noSuspicionNpcs) do
            local e = live[key]
            if e then
                local np = e.npc:K2_GetActorLocation()
                local dx, dy, dz = np.X - sp.X, np.Y - sp.Y, np.Z - sp.Z
                if dx * dx + dy * dy + dz * dz <= AI_RETARGET_RANGE * AI_RETARGET_RANGE then
                    local ok, los = pcall(function() return e.ctrl:LineOfSightTo(standing, { X = 0, Y = 0, Z = 0 }, false) end)
                    if ok and los == true then releaseNpc(key, e.npc, e.ctrl, standing, "sees the standing player") end
                end
            else
                noSuspicionNpcs[key] = nil
            end
        end
    end
end

local function bodyOfPawn(pawn)
    return bodies[pawn:GetFullName()]
end

local function setDowned(i, pc, value)
    downed[i] = value
    local pawn = pc.Pawn
    local b = valid(pawn) and bodyOfPawn(pawn)
    if b then b.downed = value end
    if valid(pawn) then
        pcall(function() pawn.bCanBeDamaged = not value end) -- no damage while down
    end
    if value then
        pc:SetIgnoreMoveInput(true)
        pcall(function() pawn:Crouch(false) end)
        log("player " .. i .. " is down")
    else
        pc:ResetIgnoreMoveInput()
        pcall(function() pawn:UnCrouch(false) end)
        log("player " .. i .. " revived")
    end
end

local function updateDowned(world)
    local pcs = { statics():GetPlayerController(world, 0), statics():GetPlayerController(world, 1) }
    if gameOver or not (valid(pcs[1]) and valid(pcs[2])) then return end
    reviveKey = reviveKey or { KeyName = FName("Gamepad_FaceButton_Left") }
    for i = 1, 2 do
        local pawn = pcs[i].Pawn
        if valid(pawn) then
            local sc = pawn.SurvivalComponent
            local pname = pawn:GetFullName()
            if demigodPawn[i] ~= pname then
                -- New pawn (join, respawn, map): not downed. (DemiGod made the players fully invulnerable in
                -- this game, so lethal hits are clamped in the ReceiveTakeDamage hook instead.)
                demigodPawn[i] = pname
                if downed[i] then setDowned(i, pcs[i], false) end
            end
            local hp, max = sc:GetStat(HEALTH), sc:GetStatMax(HEALTH)
            if not downed[i] and hp <= max * DOWN_RATIO then
                log(string.format("player %d health %.2f of %.0f", i, hp, max))
                setDowned(i, pcs[i], true)
            end
            if downed[i] then
                local b = bodyOfPawn(pawn)
                if b then b.downed = true end
                if not pcs[i]:IsMoveInputIgnored() then pcs[i]:SetIgnoreMoveInput(true) end -- cutscene end resets it
                if hp < max * DOWNED_HEALTH then sc:SetStatPercent(HEALTH, DOWNED_HEALTH) end -- no grey screen
            end
        end
    end
    if downed[1] and downed[2] then
        gameOver = true
        log("both players down: normal death")
        -- Downed pawns have bCanBeDamaged off; Kill() did nothing with it off (both down, no game over).
        pcall(function() pcs[1].Pawn.bCanBeDamaged = true end)
        pcall(function() pcs[1].Pawn:Kill() end)
        return
    end
    if downed[1] or downed[2] then
        local ok, err = pcall(retargetAIs, pcs)
        if not ok then logOnce("retarget error: " .. tostring(err)) end
    elseif next(noSuspicionNpcs) then
        releaseCalmedNpcs()
    end
    -- Revive: the standing player holds X near the downed one.
    reviveInfo = { { near = false, pct = nil }, { near = false, pct = nil } }
    for i = 1, 2 do
        local j = 3 - i
        if downed[i] and not downed[j] and valid(pcs[i].Pawn) and valid(pcs[j].Pawn) then
            local a, c = pcs[i].Pawn:K2_GetActorLocation(), pcs[j].Pawn:K2_GetActorLocation()
            local dx, dy, dz = a.X - c.X, a.Y - c.Y, a.Z - c.Z
            local near = dx * dx + dy * dy + dz * dz <= REVIVE_RANGE * REVIVE_RANGE
            local ok, held = pcall(function() return pcs[j]:IsInputKeyDown(reviveKey) end)
            reviveInfo[i].near = near
            if near and ok and held then
                reviveSince[i] = reviveSince[i] or os.clock()
                reviveInfo[i].pct = math.min(100, math.floor((os.clock() - reviveSince[i]) / REVIVE_SECONDS * 100))
                if os.clock() - reviveSince[i] >= REVIVE_SECONDS then
                    reviveSince[i] = nil
                    setDowned(i, pcs[i], false)
                    pcs[i].Pawn.SurvivalComponent:SetStatPercent(HEALTH, REVIVE_HEALTH)
                end
            else
                reviveSince[i] = nil
            end
        else
            reviveSince[i] = nil
        end
    end
end

-- World streaming. The game's dynamic streaming, NPC spawning and nav mesh are centred on player 1; player 2's
-- surroundings showed only green proxies, no NPCs and no props. Every radius below gets the distance between
-- the players added (capped), so the disc around player 1 also covers player 2. Owner tests (2026-11-04):
-- raising only g.GlimpseDynamicStreamingRadius brought the houses back but not NPCs/props (bodies, tables): the
-- eviction radius (12800) evicted them again. 80000/70000 for the first two crashed the game (heap corruption).
-- Defaults read from the CVar registrations in GlimpseGame.exe.
local STREAM_RADII = {
    { "g.GlimpseDynamicStreamingRadius", 9200 },
    { "g.GlimpseDynamicSpawnRadius", 6400 },
    { "g.GlimpseDynamicEvictionRadius", 12800 },
    { "g.NPCSpawnRadius", 6000 },
    { "g.NPCDespawnRadius", 8000 },
    { "g.NPCPhysicsLivenessRadius", 3000 },
    { "g.NavMeshLiveRadius", 4800 },
    { "g.NavMeshCacheRadius", 6400 },
}
-- Extra radius in fixed steps: re-sending the radii every few seconds while player 2 walked (+10k..+14k) made the
-- game spawn and despawn things at the disc edge constantly and UE4SS crashed (UE4SS.dll+0x47960F). A step is
-- taken up as soon as the distance needs it and down only after LOWER_DELAY seconds below it.
local EXTRA_STEPS = { 0, 10000, 20000, 30800 } -- streaming radius at most 9200 + 30800 = 40000
local LOWER_DELAY = 15
local appliedExtra = nil
local lowerSince = nil

local function stepFor(distance)
    for _, st in ipairs(EXTRA_STEPS) do
        if distance <= st then return st end
    end
    return EXTRA_STEPS[#EXTRA_STEPS]
end

local function updateStreamingRadius(world)
    local p1, p2 = statics():GetPlayerController(world, 0), statics():GetPlayerController(world, 1)
    local d = 0
    if valid(p1) and valid(p2) and valid(p1.Pawn) and valid(p2.Pawn) then
        local a, b = p1.Pawn:K2_GetActorLocation(), p2.Pawn:K2_GetActorLocation()
        d = math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
    end
    -- CoopMenuFix (v9) moves the streaming centre to the midpoint between the players when they are more than
    -- 2000 apart, so the radii only need half the distance: the smallest step that covers d / 2.
    local want = (d < 2000) and 0 or stepFor(d / 2)
    if appliedExtra == want then lowerSince = nil return end
    if appliedExtra and want < appliedExtra then
        lowerSince = lowerSince or os.clock()
        if os.clock() - lowerSince < LOWER_DELAY then return end
    end
    lowerSince = nil
    local ksl = UEHelpers.GetKismetSystemLibrary()
    for _, r in ipairs(STREAM_RADII) do
        ksl:ExecuteConsoleCommand(world, r[1] .. " " .. (r[2] + want), p1)
    end
    appliedExtra = want
    log(string.format("streaming/NPC radii +%d (players %.0f m apart)", want, d / 100))
end

local function tick()
    local world = viewportWorld()
    if not (world and world:IsValid()) then
        readySince = nil
        return
    end
    local wname = world:GetFullName()
    if wname ~= currentWorld then
        currentWorld = wname
        bodies, halfWidgets, activeWorld = {}, nil, nil
        menuWasOpen, menuOpenedAt = { false, false }, nil
        pendingRegroup, p2PawnName, fallingSince, lastPos = nil, nil, { nil, nil }, { nil, nil }
        crumbs, safeMove, killZ = {}, nil, nil
        pcall(function()
            local ws = FindFirstOf("WorldSettings")
            local kz = ws and ws:IsValid() and ws.KillZ
            if kz and kz > -1000000 then killZ = kz end
            log("KillZ " .. tostring(killZ))
        end)
        appliedExtra, lowerSince = nil, nil
        downed, demigodPawn, reviveSince, gameOver = { false, false }, { nil, nil }, { nil, nil }, false
        reviveUi, reviveInfo = { nil, nil }, { { near = false }, { near = false } }
        noSuspicionNpcs = {}
        if cutscene then
            -- Left the world mid-cutscene: put the global setting back; everything else died with the world.
            UEHelpers.GetGameMapsSettings().bUseSplitscreen = true
            cutscene = nil
        end
    end
    if onMenu(world) then
        activeWorld = nil
        readySince = nil
        -- Player 2 is kept on the main menu (one full view). Removing it there (RemovePlayer) left UI code
        -- holding player 2's destroyed controller: loading the next save crashed in
        -- AGlimpsePlayerController stats access (GlimpseGame.exe+0x2C9640, 2026-11-03).
        UEHelpers.GetGameMapsSettings().bUseSplitscreen = false
        return
    end
    if hasPlayer2(world) then
        if not activeWorld and not cutscene then UEHelpers.GetGameMapsSettings().bUseSplitscreen = true end
        activeWorld = world
        ensurePlayer2Pawn(world)
        -- A new player 2 pawn (join or respawn) may be at the map's PlayerStart, which on some maps is
        -- outside the playable area: bring it next to player 1 (unless a cutscene is running).
        local p2pawn = statics():GetPlayerController(world, 1).Pawn
        local pname = valid(p2pawn) and p2pawn:GetFullName() or nil
        if pname and pname ~= p2PawnName and not cutscene then
            p2PawnName = pname
            pendingRegroup = { at = os.clock() + 0.3, owner = 0 }
            log("new player 2 pawn: regroup with player 1")
        end
        -- Diagnostics switches (loot screen investigation): no_hudhalves.txt / no_menuscale.txt in Mods/SplitScreenCoop.
        local function flag(n) local f = io.open("Mods/SplitScreenCoop/" .. n, "r") if f then f:close() return true end return false end
        if flag("no_hudhalves.txt") then logOnce("no_hudhalves.txt: HUD halves off") else layoutHalfScreenWidgets(world) end
        if flag("no_menulayout.txt") then logOnce("no_menulayout.txt: player menu half layout off") else
            local okMenus, errMenus = pcall(layoutPlayerMenus, world)
            if not okMenus then logOnce("player menu layout error: " .. tostring(errMenus)) end
        end
        ensureBodies(world)
        local ok, err = pcall(updateStreamingRadius, world)
        if not ok then logOnce("streaming radius error: " .. tostring(err)) end
        return
    end

    local p1 = statics():GetPlayerController(world, 0)
    if not (p1 and p1:IsValid() and p1.Pawn:IsValid()) then
        readySince = nil
        return
    end
    readySince = readySince or os.time()
    if os.time() - readySince >= SETTLE_SECONDS then
        readySince = nil
        addPlayer2(world)
    end
end

-- Animation, menu pause and cutscene state, 4 times a second; setup once a second.
local lastFast, lastSlow = 0, 0

local function fastStep()
    -- Map change (e.g. quitting to the main menu): cached pawns, bodies and the old world may be destroyed;
    -- nothing cached is touched until the 1 s step has reset for the new world.
    -- (Quitting with player 2's inventory open crashed inside UE4SS.dll, 2026-11-03.)
    local w = viewportClient and viewportClient:IsValid() and viewportClient.World
    if not (w and w:IsValid() and activeWorld and w:GetFullName() == currentWorld) then return end
    for i = 0, 1 do
        -- Pawns fetched fresh from the controllers (never cached; see ensureBodies).
        local pc = statics():GetPlayerController(w, i)
        local pawn = valid(pc) and pc.Pawn or nil
        local b = valid(pawn) and bodies[pawn:GetFullName()] or nil
        if b and valid(b.actor) then animateBody(b, pawn) end
    end
    undoMenuPause(w)
    local ok, err = pcall(updateCutscene, w)
    if not ok then logOnce("cutscene error: " .. tostring(err)) end
    ok, err = pcall(updateDowned, w)
    if not ok then logOnce("downed error: " .. tostring(err)) end
    ok, err = pcall(updateReviveUi, w)
    if not ok then logOnce("revive prompt error: " .. tostring(err)) end
end

-- Arthur bodies follow their NPC body's pose every frame (onFrame runs from several ticks: about once per frame).
local lastPose = 0
local function retargetBodies()
    local w = viewportClient and viewportClient:IsValid() and viewportClient.World
    if not (w and w:IsValid() and activeWorld and w:GetFullName() == currentWorld) then return end
    for _, b in pairs(bodies) do
        if b.pose and valid(b.actor) then
            local ok, err = pcall(arthurRetarget.apply, b.actor.SkeletalMeshComponent, b.pose)
            if not ok then logOnce("Arthur retarget error: " .. tostring(err)) end
        end
    end
end

function onFrame()
    local now = os.clock()
    if now - lastPose >= 0.011 then
        lastPose = now
        local ok, err = pcall(retargetBodies)
        if not ok then logOnce("retarget step error: " .. tostring(err)) end
    end
    if now - lastSlow >= 1.0 then
        lastSlow = now
        local ok, err = pcall(tick)
        if not ok then log("error: " .. tostring(err)) end
    end
    if now - lastFast >= 0.25 then
        lastFast = now
        local ok, err = pcall(fastStep)
        if not ok then logOnce("fast step error: " .. tostring(err)) end
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
    -- Pawns do not tick while the game is paused, so opening an inventory (which pauses) stopped onFrame and the
    -- pause was never undone (and the menus could not be navigated). Widgets keep ticking while paused.
    "/Game/UI/PlayerMenu/PlayerMenuWidget.PlayerMenuWidget_C:Tick",
    "/Script/GlimpseGame.GlimpseCharacter:ReceiveTakeDamage",
}
local HOOK_FN = {
    ["/Script/GlimpseGame.GlimpseCharacter:ReceiveTakeDamage"] = function(ctx, damage, actual, damageType, instigator)
        local ok, err = pcall(onTakeDamage, ctx, damage, actual, damageType, instigator)
        if not ok then logOnce("damage hook error: " .. tostring(err)) end
    end,
}
local hookState = {} -- path -> "pending" | "done"
local inFrame = false

local function frameHook()
    if inFrame then return end
    inFrame = true
    local ok, err = pcall(onFrame)
    inFrame = false
    if not ok then logOnce("frame error: " .. tostring(err)) end
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
                        local ok, err = pcall(RegisterHook, path, HOOK_FN[path] or frameHook)
                        hookState[path] = ok and "done" or nil
                        log((ok and "frame hook registered: " or "frame hook failed: ") .. path .. (ok and "" or (" " .. tostring(err))))
                    end)
                end
            end
        end
    end
    return allDone
end)

log("loaded")
