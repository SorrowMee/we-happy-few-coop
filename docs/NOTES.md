# We Happy Few: co-op notes

## Phase 0: triage (2026-10-30)

### Observed
- Store: Steam, app 320240, build id 4660512.
- Main exe: `<game dir>\GlimpseGame\Binaries\Win64\GlimpseGame.exe`, 62,278,656 bytes,
  SHA-256 `51CF287329BC4516CE696FF5A77DC563A9B66E2909AEFD95C94541070DD4F46E`.
- Engine: Unreal Engine 4.13.1 (exe string `4.13.1-88966+++depot+Glimpse-Release`).
- OS: Windows 11 Pro (26200).
- Content ships as 8 `.pak` files (`GlimpseGame*-WindowsNoEditor.pak`, plus the Lightbearer DLC pak).
- Engine netcode is in the exe: `IpNetDriver` (57 string hits), `SteamNetDriver` (7),
  `NetDriverDefinitions` (2), `OnlineSubsystemSteam` (606). Steamworks SDK v132 `steam_api64.dll`.
- No existing co-op mod found. The only mod that turned up unlocks the dev console and quicksave
  ([gamepressure](https://www.gamepressure.com/download/we-happy-few-unlock-developer-console-and-quicksave-v1-mod/z21249b)).
  The devs said single-player only ([gamepressure](https://gamepressure.com/newsroom/is-we-happy-few-multiplayer-or-coop-in-2024-answered/z3674b)).
- coop-anything DIRECTORY.md and `games/` have no entry. GitHub issues/PRs not checked (`gh` not installed).

### Derived
- Path: build from zero, along the lines of the UE4 row in `playbook/engine-families.md`
  (Genesis Alpha One: `open <map>?listen` with `IpNetDriver`, then fix single-player Blueprints).
- UE4SS documents support for UE 4.12 through 5.x ([docs.ue4ss.com](https://docs.ue4ss.com/)), so 4.13 is inside the range.

### Unknown
- Whether `?listen` and a second-client join actually work in this build.
- Whether UE4SS hooks this exe without per-game AOB signatures.
- How procedural world generation (seeded maps) and the save system behave across two clients.

## Phase 2: workspace (2026-10-30)

### Observed
- Test copy made with robocopy (361 files, 11.275 GB). Its `GlimpseGame.exe` SHA-256 matches the original.
- UE4SS v3.0.1 (stable, released 2024-02-14) from
  https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip,
  5,523,402 bytes, SHA-256 `4B47D4BCEDDD2F561A4E395BFA00924CCFC945AF576A2D0C613E6537846C57EC`
  (computed locally; the release publishes no digest). Size matches the API asset size.
- Installed into the test copy's `GlimpseGame\Binaries\Win64` (`dwmapi.dll` proxy). Default mods.txt:
  ConsoleEnablerMod, CheatManagerEnablerMod, ConsoleCommandsMod, BPModLoaderMod on. Added `steam_appid.txt` (320240).
- Python 3.12.10 and GitHub CLI 2.103.3 installed via winget (installer hashes verified by winget).

### Not yet run
- (none)

## Phase 2b: UE4SS smoke test (2026-10-30)

### Observed (one launch, `-windowed -ResX=1280 -ResY=720 -log`, Steam running)
- UE4SS v3.0.1 hooks the exe with its default config and no game-specific config:
  `Found EngineVersion: 4.13`, `GUObjectArray`, `GMalloc`, `FName::ToString`, `FName::FName(wchar_t*)`,
  `StaticConstructObject_Internal`, `FText::FText(FString&&)` all found; 23/23 types constructed.
- Lua mods started: ConsoleCommandsMod, ConsoleEnablerMod, BPModLoaderMod, BPML_GenericFunctions, Keybinds.
- ConsoleEnabler logged `Was unable to find an instance of UEngine` twice, then bound the console:
  `ConsoleKey[1]: F10` (about 8 s after start).
- Game still running about 30 s after the mods loaded; no crash.

### Next
- Dump map names (ActorDumperMod / console), then try `open <map>?listen` on one instance and
  `open 127.0.0.1` on a second (see playbook/multi-instance-testing.md).

## Goal change (2026-10-30)

Owner wants split screen. Route chosen: the engine's own local multiplayer inside one copy
(GameMapsSettings.bUseSplitscreen + GameplayStatics.CreatePlayer, as in UE4SS's SplitScreenMod).
One world, so procedural maps, saves and story need no network sync. Steam Remote Play Together can
carry a local split-screen game to friends online. The multi-copy route (Nucleus/Couchlink on top of
network co-op) stays a fallback.

## Phase 3: first runs (2026-10-30)

### Observed
- In-game version label: `v1.9.88966`.
- The first UE4SS launch crashed about 50 s in: unhandled C++ exception `e06d7363`, empty call stack in
  CrashContext. The last UE4SS line, in the same second: `[Lua] AssetRegistryHelpers is not valid`
  (BPModLoaderMod). With BPModLoaderMod and BPML_GenericFunctions off, three runs of 180 to 240 s had no crash.
- The game writes config to `%USERPROFILE%\Documents\My Games\We Happy Few\Config` even from a copied install,
  and `-ResX/-ResY` were saved into `GameUserSettings.ini`. Saves live in `...\We Happy Few\SaveGames`.
  The test launcher now snapshots `Config` before each run and restores it after.
- Main menu world: `/Game/Maps/SpawnMaps/Special/ShellMenu_VLG_PERS`. One `PlayerController` with
  `GlimpseLocalPlayer_0`, no pawn. `UEHelpers.GetPlayerController()` finds none there (UE4SS 3.0.1).
- Console `open /Game/Maps/Test/BasicMapTest?listen`, run with `KismetSystemLibrary.ExecuteConsoleCommand`
  from the menu: no travel 13 s later (world unchanged, no NetDriver).
- `GameplayStatics.OpenLevel(world, "/Game/Maps/Test/BasicMapTest", true, "")` travels (world changed within 45 s):
  `DefaultPlayerController_C_0` + `DefaultPlayerCharacter_C_0`.
- After `bUseSplitscreen = true` on the GameMapsSettings CDO, `CreatePlayer(world, 1, true)` returns
  `DefaultPlayerController_C_1` with `GlimpseLocalPlayer_1` and its own `DefaultPlayerCharacter_C_1`.
- Screenshot of the game window after that: the 3D view is split top/bottom (the same road markings
  in both halves, one half-height apart). HUD and pause menu are drawn once over the whole window.
  The pause menu was open (window had lost focus).

### Unknown
- Whether player 2 gets gamepad input (bOffsetPlayerGamepadIds = true, not tested).
- Behaviour in a real game world (GlimpseSandbox, a story save) rather than the test map.
- Whether `?listen` works through OpenLevel (not tried; no longer the main route).

## Phase 3b: gamepad input check, run 1 (2026-10-30)

### Observed
- Two Xbox One wireless controllers, XInput slots 0 and 1. Bridge set `bOffsetPlayerGamepadIds = false`.
- BasicMapTest + CreatePlayer as before (P2 = DefaultPlayerController_C_1 / DefaultPlayerCharacter_C_1).
- `track 90` logged `K2_GetActorLocation()` = (0,0,0) for both P1 and P2 on every tick for 90 s,
  while the owner was asked to move each controller in turn.

### Unknown
- Whether either player moved (owner's on-screen report pending; no screenshot, game had closed).
- Whether `K2_GetActorLocation()`'s struct return reads correctly in UE4SS 3.0.1. Next run also logs
  `RootComponent.RelativeLocation`.

## Incident: test runs wrote the owner's saves (2026-10-30)

### Observed
- The copied install writes `%USERPROFILE%\Documents\My Games\We Happy Few\SaveGames` (not only Config).
  Before testing, that folder's newest file was from 2026-10-25. After the runs it holds
  `Settings\UserProfile.sav` (2121 bytes) and `Slot0\Playthrough.sav` (314 bytes), both written 20:06.
- Steam Cloud (remotecache.vdf) lists only those two paths and took the test-run versions at 20:00:32,
  during the run that went menu -> OpenLevel(BasicMapTest). So the cloud copy is the test-run version too.
- Earlier contents of SaveGames are unknown (only folder timestamps were recorded). No File History;
  shadow copies could not be queried without admin.

### Derived
- Leaving the menu with OpenLevel (or loading BasicMapTest) likely rewrote Slot0's playthrough file.

### Change
- run-test.ps1 now snapshots and restores both Config and SaveGames around every run.
- Lesson for the playbook: snapshot the game's whole user-data folder (config AND saves, and check
  Steam Cloud) before the first launch of a test copy, not after.

## Phase 3c: split screen in the real game (2026-10-30)

### Observed
- Owner loaded the save from the main menu with controller 1. World: `/Game/Maps/GlimpsePrologue_Arthur`
  (prologue, HUD "Dia 0"). P1 pawn `ArthurCharacter_C_0`.
- About 25 s after P1 had a pawn: bUseSplitscreen = true, bOffsetPlayerGamepadIds = false,
  `CreatePlayer(world, 1, true)` -> `DefaultPlayerController_C_1` + `ArthurCharacter_C_1` (a second Arthur).
- `track 75`: P2 moved across about 570 units over ~27 s while P1 stayed fixed at (-8088,-7937,3296); then
  P1 started moving (owner was moving controller 2 first, then controller 1). `K2_GetActorLocation()` and
  `RootComponent.RelativeLocation` agree, so the (0,0,0) readings on BasicMapTest were real: the
  test-map pawns never moved.
- Screenshot: 3D view split top/bottom, each half its own camera. The game HUD (compass, day/time,
  bottom-right widgets) and the pause menu are drawn once, over the whole window.

### Derived
- Gamepad 1 -> P1, gamepad 2 -> P2 works with the engine's own local-player input.

## Phase 4: SplitScreenCoop mod, run 1 (2026-10-30)

### Observed
- New mod `SplitScreenCoop` (separate from the CoopBridge dev tool): 1 s game-thread tick; when the
  viewport world is not the menu and P1 has had a pawn for 5 s, CreatePlayer(world, 1). Owner loaded the
  save with controller 1: `player 2 added` about 5 s later, no command sent. Both players moved (P2 also jumped).
- HUD: two `LightHUDPresenter_C` actors (an AHUD subclass), one owned by each controller.
  `UserWidget` instances with `IsInViewport()`: 0.
- Back on the main menu, removing P2 failed every tick: `attempt to compare number with UObject` on
  `pc.Player.ControllerId` (not a readable property in 4.13). Fixed: find extra players with
  `GameplayStatics:GetPlayerController(world, i)` for i >= 1, then `RemovePlayer`.

## Phase 4: SplitScreenCoop mod, run 2 (2026-10-30)

### Observed
- Auto-add again ~5 s after the save loaded. Back to the main menu: `removing PlayerController ...
  ShellMenu_VLG_PERS...PlayerController_1`; status then shows 1 controller on the menu.
- Live UserWidget classes (none report IsInViewport): HUD pieces mostly x3 (CompassWidget_C, StaminaBar_C,
  ReticleWidget_C, StatusWidget_C, QuickSlots_C, MapWidget_C, JournalWidget_C, SkillTree_C,
  InventorySubMenu_C, CraftingMenuWidget_C ...), LightHUDWidget_C x2, PlayerMenuWidget_C x2,
  MainMenuWidget_C x1, ShellMenuWidget_C x1.

### Guess
- x3 = one template + one per player; LightHUDWidget_C x2 = one per player. If both are added to the whole
  viewport, P2's HUD is drawn on top of P1's. Next test: RemoveFromParent + AddToPlayerScreen per owner.

## Phase 5: per-player HUD, run 1 (2026-10-30)

### Observed
- Before: both `LightHUDWidget_C` (outer = each DefaultPlayerController) report `IsInViewport()=false`,
  parent none, visibility 4 (SelfHitTestInvisible), yet the HUD is drawn over the whole window.
  So the game puts the HUD on screen some way other than AddToViewport (presenter / Slate direct; unverified).
- `RemoveFromParent()` + `AddToPlayerScreen(0)` on each: both then report inViewport=true.
  Screenshot after: P1's compass, Joy meter and day/time sit in the top half; P2's in the bottom half.
  Interaction prompts ("X Levantar") show in both views.
- Left over at full-window positions: quick-slot D-pad and the "RB" phone widget (two RB icons visible).
  HUD keeps full-screen scale inside each half.

### Unknown
- Whether the full-window copy of P1's HUD is still drawn under the top-half one (positions coincide).
- Whether the game re-adds the HUD on events (menus, cutscenes, level change).

## Phase 5: per-player HUD, run 2 (2026-10-30)

### Observed
- Owner report (run 1): stamina bar displaced; each controller's menu opens over the whole window.
- SplitScreenCoop now moves each LightHUDWidget_C to its owner's screen from the tick (logged at join),
  and hooks `/Script/UMG.UserWidget:AddToViewport` to do the same for owned widgets while split.
- `StaminaBar_C` and `QuickSlots_C` are children of each LightHUDWidget (`... < HUDCanvas < CanvasPanel_1`),
  not separate widgets. Menu panels live under `PlayerMenuWidget_C_0/_1` (one per controller).
- Screenshot: P1 looking at the restoration machine; its prompt ("Maquina de restauracao", hold X / hold Y)
  appears in BOTH halves. P2's HUD shows P1's interaction prompt.

### Derived
- The prompt (and likely more HUD bindings) reads player 0, not the widget's owning player.

## Crash during HUD run 2 (2026-10-30)

### Observed
- Game exited with code 3 at 20:35:25, ~2 min after P2 joined: access violation `c0000005` in
  `GlimpseGame.exe` at offset `0x52CB2C` (WER). CrashContext has no message or stack.
- No `moving to player screen` line for any widget other than LightHUDWidget_C before the crash.
  ConsoleEnablerMod logged its F10 binding twice at 23:34:45 (UE4SS log clock), 40 s before the crash.

### Guess
- The AddToViewport hook calling RemoveFromParent/AddToPlayerScreen inside AddToViewport (before its log
  line). Changed: the hook only queues; the 1 s tick moves queued widgets. Owner's action at crash time: pending.

## Crash 2 (2026-10-30)

### Observed
- Owner loaded a later save: world `/Game/Maps/Story/GlimpseStory`. P2 added 23:47:03, HUD moved 23:47:04,
  CheatManagerEnablerMod `Constructed CheatManager` 23:47:07, crash 20:47:12 local (~9 s after join).
  Same access violation, same address: GlimpseGame.exe+0x52CB2C. Nothing was queued by the AddToViewport hook.
- The earlier manual-hudfix run (no AddToViewport hook; owner opened menus) ran 4+ min without a crash.

### Guess
- Registering `RegisterHook("/Script/UMG.UserWidget:AddToViewport")` under UE4SS 3.0.1 on UE 4.13 breaks the
  call itself. Both crash runs had it; the long run did not.

### Change
- Hook removed; menus found by scanning owned top-level widgets with IsInViewport each tick.
- CheatManagerEnablerMod disabled (second suspect, not needed).

## Crash 3 (2026-10-30)

### Observed
- No AddToViewport hook, CheatManagerEnablerMod off. GlimpseStory save: P2 added 23:49:00, HUD moved 23:49:01,
  crash 20:49:11 local (~12 s after join). Same: c0000005 at GlimpseGame.exe+0x52CB2C. No menu moved.
- So the hook guess (crash 2) is wrong. Crashes: 3 of 3 runs on GlimpseStory within 12 s; the prologue
  survived minutes (one prologue run crashed after ~2 min, owner's action unknown).

### Next
- Isolation: P2 only, widget moves off (MOVE_WIDGETS = false).

## Phase 5: HUD layout without moving the widget (2026-10-30)

### Observed
- Isolation run: GlimpseStory save, P2 added, widget moves OFF: no crash in 91 s (earlier: 3/3 crashes within 12 s
  with the LightHUDWidget RemoveFromParent + AddToPlayerScreen). So moving the HUD widget causes the crash.
- LightHUDWidget root `CanvasPanel_1` has 4 children, all CanvasPanelSlot full-stretch (0,0)-(1,1):
  StealthVignette, WaypointAndIndicatorPanel, HUDCanvas (offsets 30), Overlay_61.
- UE4SS 3.0.1 struct handling here: reading nested struct fields works; writing `slot.LayoutData.Anchors.Maximum.Y`
  is silently dropped (copy); `SetAnchors(slot.LayoutData.Anchors)` errors (error value is a function);
  `SetAnchors({Minimum={...},Maximum={...}})` zeroed the anchors to (0,0)-(0,0).
  Flat struct table works: `SetOffsets({Left=,Top=,Right=,Bottom=})` reads back exactly.
- With point anchors, offsets = position + size. Viewport 1920x1080, scale 1.0. P1 children -> (0,0,1920,540),
  P2 -> (0,540,1920,540); HUDCanvas keeps its 30 margin. Game kept running.

### Derived
- Crash cause (likely): the game's native HUD presenter keeps a pointer to the widget's Slate content;
  taking the widget off screen leaves it dangling. Keep the game's widget in place; only change layout.
- Owner's visual check of the offset layout (live, via snippet): "its good" (each HUD in its own half).
  No screenshot: the game ran fullscreen and the window reported no client area.

### Change
- SplitScreenCoop: HUD widget is never moved. Each tick while split, every root-canvas layer of each
  LightHUDWidget gets inset margins (FMargin via SetOffsets) confining it to its owner's half
  (P1 Bottom = H/2, P2 Top = H/2, HUDCanvas +30). Recomputed from viewport size, so resolution changes apply.
- Menus: scan-and-move (RemoveFromParent + AddToPlayerScreen) enabled for the next test; untested.

## Phase 5: automatic HUD layout + menus, run 1 (2026-10-30)

### Observed
- GlimpseStory save: P2 added 23:59:31, `HUD laid out in half` 23:59:32. No crash (owner: "looks like it didnt crash").
- Menu scan (owned top-level widgets with IsInViewport) never fired: the game's menus are not AddToViewport widgets.
- Owner: P2 can open its pause menu; P2 cannot open its inventory.
- Visible root widgets with no menu open: CursorWidget_C_0 (no owner), LightHUDWidget_C_0/1 (P1/P2),
  NotificationsAreaWidget_C_0/1 (P1/P2), PlayerMenuWidget_C_1 (owner P1, visibility 4).

## Phase 6: menus (2026-10-30)

### Observed
- Opening P2's pause menu changed no widget's visibility/parent/viewport state; it only rebuilt 4
  CustomDifficultyOptionWidget_C entries under `DifficultyOptionSelector < ShellMenuWidget_C_0 < MainMenuWidget_C_0`.
  The in-game pause menu is the single main-menu widget (no owner). Decision: keep it full screen, shared.
- Inventory/journal live in `PlayerMenuWidget_C` (one per player). Menu functions are native on
  `GlimpsePlayerController`: ShowPlayerMenu, ShowPlayerMenuWithContext, CanShowPlayerMenu, IsPlayerMenuVisible,
  SetCanAccessPlayerMenu, SetAllowGameModeMenu, HidePlayerMenu ...
- `CanShowPlayerMenu()`: P1 true, P2 false. `P2:SetCanAccessPlayerMenu(true)` runs but CanShowPlayerMenu stays false.
- UE4SS 3.0.1: `UFunction:ForEachProperty` errors (opaque error value). A generic diff that read every
  property of the controller (`obj[name]` for all property types) crashed the game inside UE4SS.dll
  (c0000005 at UE4SS.dll+0x4BDD9E). Only read simple property types (bool/int/float/name/object).

## Phase 6b: player 2 had no pawn on the story map (2026-10-30)

### Observed
- Safe diff (bool/int/float/byte/name/object/enum only) of P1 vs P2 GlimpsePlayerController: P2 has
  GlimpseCharacter none, PlayerMenu none, CutsceneWidget none, DeathMenu/DeathMenuPresenter none,
  bRecipesInitialized false, RespawnType 0 (P1 5), AcknowledgedPawn none, bPlayerIsWaiting true, SpectatorPawn set.
- On GlimpseStory, P2.Pawn = none: CreatePlayer gives P2 only a spectator. (The prologue spawned a second ArthurCharacter.)
- Game mode `GlimpseStoryGame_C`. `RestartPlayer` is not a UFunction in 4.13. Callable: `SpawnDefaultPawnFor`,
  `GetDefaultPawnClassForController` (-> DefaultPlayerCharacter_C), `FindPlayerStart`, `ChoosePlayerStart`.
- `gm:SpawnDefaultPawnFor(p2, p1.Pawn)` -> DefaultPlayerCharacter_C_0; `p2:Possess(pawn)` ok. After that:
  GlimpseCharacter set, PlayerMenu = PlayerMenuWidget_C_2, CanShowPlayerMenu true, bPlayerIsWaiting false.

### Derived
- The game's per-player setup (character link, player menu) runs on Possess. P2 must get a pawn and be possessed.
- Pawn class: default is the generic DefaultPlayerCharacter_C; P1 is ArthurCharacter_C. Next: spawn P1's class.

## Phase 6c: inventory per player (2026-10-30)

### Observed
- PlayerMenuWidget root `BaseCanvas` (CanvasPanel), 4 full-stretch layers: PlayerMenuBackgrounds, MenuManilaBox,
  SubMenuOverlay, SafeZoneCanvas (offset 30). Inset margins to a half: works, but owner says too squeezed to read.
- Better: restore margins, `SetRenderTransformPivot({X=0.5,Y=0|1})` + `SetRenderScale({X=0.5,Y=0.5})` on the
  PlayerMenuWidget. Owner: "I can read it now its perfect". Owner chose half-screen inventories over full screen.
- Opening P2's inventory pauses the game (`IsGamePaused` true, time dilation 1.0; P1 hangs mid-jump).
  `SetGamePaused(false)` works; the game re-paused only 2 times in 30 s while the menu stayed open.
- Controller 1 drives P2's open inventory; controller 2 cannot drive P1's. Repeating every 200 ms
  (158 times, 0 errors): unpause + `WidgetBlueprintLibrary.SetInputMode_GameOnly(p1)` + `P2.PlayerMenu:SetUserFocus(p2)`
  -> owner: P1 still drives P2's inventory and now cannot jump.

### Guess
- Menu input is routed by native code (GlimpsePlayerController / GlimpsePlayerMenu in GlimpseGame.exe), likely
  from player 0's input to whichever player menu is open. Needs reverse engineering of the exe.
- P2 pawn class: `gm.DefaultPawnClass = p1.Pawn:GetClass()` (object property write works), SpawnDefaultPawnFor,
  restore DefaultPawnClass, Possess, destroy the placeholder -> P2 = ArthurCharacter_C_1 with GlimpseCharacter,
  PlayerMenu (PlayerMenuWidget_C_3) and CanShowPlayerMenu true.

### Change (SplitScreenCoop rewrite)
- ensurePlayer2Pawn: while split, if P2 has no pawn, spawn P1's class at P1 and possess (also a respawn rule).
- confineToHalf for LightHUDWidget_C and NotificationsAreaWidget_C: full-stretch root-canvas layers get their
  recorded original offsets plus half the screen height on one side.
- layoutPlayerMenus: each PlayerMenu at render scale 0.5, pivot top (P1) / bottom (P2).
- Removed the scan-and-move menu code (game menus are not AddToViewport widgets).
- Known limitation: opening an inventory pauses the game, and controller 1 drives any open inventory.

## Phase 7: seeing the other player (2026-10-30)

### Observed
- Owner: P2 (spawned ArthurCharacter_C) looks like Arthur and moves normally in first person; invisible to the other player.
- Each player pawn has one body mesh `CharacterMesh0` (GlimpseSkeletalMeshComponent): visible, bOnlyOwnerSee=true,
  bOwnerNoSee=false. Plus `PlayerFogCube` (StaticMeshComponent, not visible).
- `pawn.Mesh:SetOnlyOwnerSee(false)` on both pawns: ok, reads back false. Owner's view of it: pending.

### Tools
- Ghidra 12.2 (sha256 2c2cd776...a7be67) refuses JDK 21 ("JDK 25+ could not be found"). Getting Temurin
  25.0.5+8 (sha256 636bdc13...6c96c42). In UE4SS 3.0.1, `pawn:K2_GetComponentsByClass(...)` + `:ForEach` failed with
  the opaque error; FindAllOf(component class) + `GetOwner()` works.
- Owner: with bOnlyOwnerSee off, the other player sees only floating arms. `CharacterMesh0` is
  `/Game/Character/Player_Character/FPP_Arthur` (first-person arms). Reverted to owner-only.
- Full-body Arthur exists in the paks: `/Game/Character/Narrative/Arthur/SK_Arthur` (+ `_withMask`, `_Headless`),
  skeleton `SK_Arthur_Skeleton`, and `/Game/Character/Narrative/Arthur/Arthur` (27 KB, type unknown).
- UE4SS 3.0.1 `LoadAsset(path)` errors on this game (it needs AssetRegistryHelpers, absent in 4.13; same as the
  BPModLoader crash). So unloaded assets cannot be loaded from Lua. Options: a UE4SS C++ mod calling
  StaticLoadObject, or borrow an already-loaded NPC mesh.

## Phase 8: native loader for assets (2026-10-30, in progress)

### Plan
- Official UE4SS C++ mods need the UEPseudo submodule (Epic-account-linked GitHub access) - not used.
- Instead: standalone DLL `CoopLoader` (MSVC + MinHook v1.3.4, BSD; source zip sha256
  172708123DAA0C98D20D3A980B16A50BE14AF243DC95DEE6F79C24193AD010E4), loaded by UE4SS from Mods/CoopLoader/dlls/main.dll,
  pins itself, hooks UObject::ProcessEvent, and on the game thread calls LoadPackage(nullptr, "/Game/...", 0) for
  paths Lua writes to request.txt (results in result.txt). Lua then StaticFindObject's the loaded asset.
- Byte check at both RVAs before hooking; unknown build -> no hook.
- Address search: Ghidra 12.2 headless, anchors = UTF-16 strings in ProcessEvent ("%s  Function: '%s'")
  and LoadPackage's log messages.
- Tools: VS 2022 Build Tools (C++ workload) via winget.

## Phase 8b: full body without a native loader (2026-11-03)

### Observed
- Ghidra 12.2 headless analysis of GlimpseGame.exe aborted: `java.lang.OutOfMemoryError: Java heap space`.
- `/Script/Engine.ObjectLibrary:LoadAssetsFromPath` (and CreateLibrary etc.) are not UFunctions in this build.
- `SK_Arthur` (skeleton `SK_Arthur_Skeleton`) is already in memory on the main menu: `SK_Arthur_2`, a
  SkeletalMeshActor in `ShellMenu_VLG_GEO`, with AnimClass `/Game/Character/Common_NPC/Houseboy_AnimBlueprint`.
- SplitScreenCoop pins it on the menu: `StaticConstructObject(SkeletalMeshComponent, GameInstance, 0,
  RF_Transient|RF_MarkAsRootSet)` holding SkeletalMesh + AnimClass. Logged `body assets pinned`; both still
  found on GlimpseStory after loading the save.
- `World:SpawnActor(SkeletalMeshActor, {}, {})` works. `SetSkeletalMesh(mesh, true)`, `SetAnimInstanceClass`,
  `SetCollisionEnabled(0)`, `SetOwnerNoSee(true)`, `SetOwner(pawn)`, `K2_AttachToActor(pawn, FName("None"), 2, 2, 1, false)`,
  `K2_SetRelativeLocation({Z=-halfHeight})`, `K2_SetRelativeRotation({Yaw=-90})` all ok. `SetMobility(2)` errors
  (Mobility is already 2). `SetSkeletalMesh(mesh)` with one argument errors.
- Owner, body attached to P2 by hand: full-body Arthur visible to P1, height right, follows P2 and turns with it,
  but stays in T-pose (Houseboy anim BP not animating it).
- A diagnostic snippet that read `AnimationMode`, `bPauseAnims`, `bNoSkeletonUpdate`, `MeshComponentUpdateFlag`
  and `AnimClass.TargetSkeleton` crashed the game inside UE4SS.dll (exit 3) within 4 s. Avoid reading those.

### Next
- Drive the body with `PlayAnimation(seq, true)` (idle/walk by pawn speed) instead of the NPC anim BP.
  Need AnimSequences on SK_Arthur_Skeleton that are in memory.
- In GlimpseStory memory: 0 of 1194 AnimSequences use SK_Arthur_Skeleton; the spawned bodies' GetAnimInstance()
  was none (Houseboy targets Common_NPC_Skeleton). 19 NPC meshes on Common_NPC_Skeleton are loaded
  (e.g. `/Game/Character/Common_NPCs/GenericMaleNPC/SK_Male_SweaterVest`), plus male NPC anims
  (`/Game/Animations/Male_NPC/Male_Idle`, `Male_Walk_RM`, `Male_Run_RM`, ...).
- Live on P2's body: `SetSkeletalMesh(SK_Male_SweaterVest, true)` + `PlayAnimation(Male_Walk_RM, true)` ->
  AnimSingleNodeInstance, IsPlaying true. Owner: walks in place (no root-motion drift), height right.
- `pawn:GetVelocity()` reads correctly; `CharacterMovement.MaxWalkSpeed` = 540.

### Change
- SplitScreenCoop bodies: NPC mesh (SweaterVest, fallback Male_NPC) instead of SK_Arthur; idle/walk/run by
  horizontal speed (<20 / <400 / above) via PlayAnimation, on a 250 ms loop. Arthur pinning removed.

## Phase 8c: lag and body rotation (2026-11-03)

### Observed
- Owner: noticeable lag with bodies on; walking forward played the run anim; idle and slow walk right;
  body faced the wrong way (looking at a wall, the body faced the door).
- Timed in-game (avg of 5): `FindAllOf("LocalPlayer")` 64.6 ms, `FindFirstOf("GameViewportClient")` 60.6 ms,
  `FindAllOf("LightHUDWidget_C")` 63.0 ms; StaticFindObject, GetFullName, GetVelocity ~0 ms.
  The 1 s tick did ~4 scans (~250 ms) and the 250 ms anim loop 2 scans (~120 ms) each run.
- Pawn yaw = control yaw (bUseControllerRotationYaw true). NPC characters (Waste1_Wastrel_C) use
  Mesh RelativeRotation yaw 0 and RelativeLocation Z -86 with capsule half height 84.1.

### Change
- SplitScreenCoop: GameViewportClient cached; player-2 check via GetPlayerController(world, 1) instead of
  scanning LocalPlayers; half-screen widgets scanned once per world (rescan only if one dies, or every 10 s
  if fewer than 4); anim loop uses cached bodies only. Body yaw 0 (was -90). Run threshold 600 (was 400);
  each anim switch is logged with the speed, to tune the threshold.
- Owner, after the change: lag gone, body faces the camera direction, walk/run/sprint right.
  Logged speeds: walking 21-226, sprint 669-810; RUN_SPEED 600 sits between.

### Open
- No jump/crouch/fall anims on the body (stays walk/idle).
- Body is a generic citizen (SK_Male_SweaterVest), not Arthur: no AnimSequence on SK_Arthur_Skeleton is in memory.
  NPC meshes/anims were checked on GlimpseStory only; other maps (prologue, other islands) unverified.
- Still from phase 6: opening an inventory pauses the game, and controller 1 drives any open inventory.

## Phase 9: inventory input and pause (2026-11-03, in progress)

### Observed (reverse engineering, Ghidra 12.2 headless with -noanalysis + DecompileAt.java on chosen RVAs)
- Native exec thunks found by `lea r8,[exec]; lea rdx,["Name"]; call 0xD02080` (RegisterFunction):
  ShowPlayerMenu exec 0x8E9BB0 -> impl 0x2E8E10; HidePlayerMenu 0x8CB310 -> 0x2CDC00;
  IsPlayerMenuVisible 0x8CDEF0 -> 0x2D0390; CanShowPlayerMenu 0x8B9740 -> 0x2BFDF0.
- ShowPlayerMenu impl: CanShowPlayerMenu; GlimpseHUD (PC+0x800) mode 5; menu Show 0x526C30, which pushes
  the menu onto a single UI stack in the GameInstance (TArray at GI+0x680) via 0x438C60 -> 0x438CE0
  (args: GI, widget, layer, bPause=1, bFocus=1, 1, 1).
- 0x438CE0: bPause -> pause counter GI+0xD14, SetPause(true) only when it goes 0 -> 1 (first local PC).
  bFocus -> GI.UIPlayer (TWeakObjectPtr<GlimpseLocalPlayer> at GI+0x674) -> its PlayerController ->
  0x2BACF0(PC, widget, 1): pushes the widget onto that PC's own UI input stack (PC+0x828).
  So every player menu's UI input goes to UIPlayer's controller (player 1).
- Live monitor: with P2's menu open, P1's user focus is inside it; opening one player's menu closes the other's;
  `bPauseGameInPlayerMenu` reads false on both controllers (the pause comes from the UI stack counter).

### Incident
- 21:41 (local) the game froze (not responding, CPU flat) ~1 min after the owner loaded; no snippet ran.
  Last log line 21:41:50 (anim switch). Cause unknown.
- Restarted fine; the freeze did not recur.

### Changes and results (2026-11-03)
- Pause: SplitScreenCoop undoes the pause once per player-menu opening (250 ms loop, IsPlayerMenuVisible +
  IsGamePaused -> SetGamePaused(false)). Owner: the other player keeps playing. The real pause menu still pauses.
- UE4SS 3.0.1 accepts a write to a TWeakObjectPtr property (`gi.UIPlayer = lp2`) but ignores it.
- Native DLL `CoopMenuFix` (local/native/coop_menufix, MSVC + MinHook 1.3.4, loaded by UE4SS from
  Mods/CoopMenuFix/dlls/main.dll; UE4SS logs "Failed to find exported mod lifecycle functions", expected).
  Byte-checked hooks, Steam build 4660512 only:
  - 0x2E8E30 ShowPlayerMenuWithContext(PC, type, FName): notes the opening controller.
  - 0x2BACF0 PushUIInput(PC, widget, a, b) (PC UI input stack PC+0x828, entries {widget, flags}; a flag blocks
    movement): inside an opening, the widget goes to the opener's stack; widget -> controller remembered.
  - 0x2E1A50 RemoveUIInput(PC, widget): removal goes to the remembered owner (covers every close path; before,
    P2 stayed unable to move after closing by some paths).
  - 0x43BAA0 UpdateUIFocus(GI): SetInputMode(GameAndUI, focus top widget) on UIPlayer's controller, or GameOnly.
    Runs with UIPlayer->PlayerController (LocalPlayer+0x30) swapped to the top widget's owner. Afterwards every
    local player (GI LocalPlayers, GI+0x38) with no menu of its own gets SetInputMode(GameOnly) (vslot 0xAF8,
    FInputModeGameOnly vftable RVA 0x2B76910, struct {vptr, byte 1}).
- Findings on the way: GameAndUI moved every Slate user's focus to the focused menu, so player 2's presses
  never reached the viewport while player 1's menu was open (logged at UGameViewportClient::InputKey, vslot 8
  of FViewportClient at +0x28, RVA 0x1A6FB10: no controllerId 1 events). Menu close = action delegate from
  PlayerTick input processing -> HidePlayerMenu (0x2CDC00) -> menu virtual Hide (vslot 0x438, RVA 0x50A730)
  -> fade-out finished (0x483960) -> GI pop (0x44E620) -> RemoveUIInput.
- v4 crashed (c0000005 in main.dll) calling SetInputMode on the main menu's destroyed controller after loading
  a save. Fixed: remembered controllers/widgets are dropped when UIPlayer's controller changes.
- Owner, v6: each controller drives only its own inventory; both inventories open at once in either order;
  neither pauses the game; both players walk after closing.

- Owner then quit to the main menu with player 2's inventory open: crash c0000005 in UE4SS.dll+0x4BAAAF
  (not the DLL; its log shows no removal to a stale controller). Two Lua faults: the 250 ms loop undid every
  pause while an inventory was open (also the real pause menu's), and it kept touching cached pawns/world
  across the map change. Fixed: pause undone only within 1.5 s of an inventory opening; the fast loop does
  nothing unless the viewport's world is still the one the 1 s tick set up.
  Owner retest: Start pauses with player 2's inventory open; quitting to the main menu no longer crashes.

### Open
- The DLL still has diagnostic hooks (HidePlayerMenu, menu Hide logging) and dormant key-logging code.

## Phase 10: jump/crouch body anims, and a UE4SS deadlock (2026-11-03)

### Observed
- On Common_NPC_Skeleton in memory: Male_Fall, Male_Fall_LandSoft, Male_Fall_LandHard; no crouch anims (NPCs never
  crouch). Crouch-like: Male_Cower, Bobby_InvestigateGround_Look, Male_Pickup_Ground. Player: bIsCrouched,
  CharacterMovement:IsFalling()/IsCrouching() readable; capsule half height 88 standing, CrouchedHalfHeight 49.
- Freeze #2 (22:37) right after both players crouched, with crouch-pose previews playing on the bodies.
  Hung-process stack sample (local/re-work/scripts/thread_stacks.py): two game threads inside UE4SS hooks
  (UE4SS.dll+554E01, from GlimpseGame+20FB4B and +D527E1) waiting on a UE4SS std::mutex (UE4SS+372D99), ~13
  UE4SS threads waiting on another lock (UE4SS+2A4CB7). Nothing from CoopMenuFix on any stack. Deadlock in UE4SS.
- ConsoleEnablerMod registers NotifyOnNewObject("/Script/Engine.PlayerController"), so object construction on any
  thread (async loading included) goes through UE4SS's Lua side.

### Change
- mods.txt: ConsoleEnablerMod, ConsoleCommandsMod, Keybinds off (dev console/hotkeys, not needed). Watch for freezes.
- After disabling those mods: owner crouched/stood 5-6 times with both players, walked crouched: no freeze.
- Crash 22:42:39, 1 s after re-running the crouch-pose preview snippet (FindAllOf SkeletalMeshActor + PlayAnimation
  on both bodies): unhandled C++ exception e06d7363 (KERNELBASE). Cause unknown; the preview snippet was dropped.
- SplitScreenCoop bodies now: fall (CharacterMovement:IsFalling) -> Male_Fall loop; landing -> Male_Fall_LandSoft once
  (0.4 s); crouched (bIsCrouched) -> Bobby_InvestigateGround_Look loop; body Z follows the current capsule half
  height. Owner: jump/fall/land "perfect"; Bobby_InvestigateGround_Look chosen over Male_Cower for crouch.
- Prologue (GlimpsePrologue_Arthur): P2 joined; NPC body mesh (SK_Male_SweaterVest) present; cutscene handling
  (bCutsceneInputMode -> one screen, bodies/HUD hidden, other player teleported, input ignored) fired 3 times.
- Freeze #3 at the prologue pinata cutscene (23:09): same stacks as #2 with the console mods off: a game thread
  (...196361A -> 198B58E -> 2AD5A70 -> 1E4F293 -> UE4SS+554E01 hook -> GlimpseGame+D527E1) waits on a UE4SS
  std::mutex (UE4SS+372D99); the game thread (2244) waits in GlimpseGame+193A166; ~12 UE4SS threads wait at
  UE4SS+2A4CB7. Suspect: LoopAsync threads (4: SplitScreenCoop 2, CoopBridge 2) holding UE4SS's Lua lock
  while the game constructs objects on another thread.
- Owner: in the prologue, interacting with the censorship machine at the start "bugged" player 2 (details pending).

### Change
- SplitScreenCoop moves off LoopAsync/ExecuteInGameThread: driven by RegisterHook on DefaultPlayerCharacter_C
  ReceiveTick (player pawn BP tick, game thread, every frame incl. cutscenes) and ShellMenuWidget_C Tick (main menu).
- Owner after the frame-hook change: pinata cutscene no longer freezes; cutscene handling (one screen, bodies and
  half HUDs hidden, other player's input ignored) "perfect".
- Teleport at cutscene START put player 2 inside the censorship machine's desk and did not help the pinata
  cutscene (it moves player 1 to another room). Changed: no teleport at start; 0.5 s after the cutscene ends
  the other player goes next to the cutscene player (8 candidate spots around it; a spot counts only if
  K2_TeleportTo left the pawn within 60 units of it).
- Prologue start: player 2's pawn spawned at the map's PlayerStart, outside the playable area, fell and died
  (death screen over the window). Changed: every new player 2 pawn (join/respawn) is brought next to player 1;
  fall safety: a player falling > 3 s while the other is not falling is brought next to the other (also in
  cutscenes). Unstuck: holding Select/View (Gamepad_Special_Left, PC:IsInputKeyDown({KeyName=FName(..)}))
  for 2 s brings that player next to the other.
- Owner: all of the above works in the prologue (start, censorship machine, pinata, unstuck).

### Open
- Player death in co-op: player 2's death screen covered the whole window (seen once); not handled yet.

## Phase 11: co-op death (downed/revive), menu and teleports (2026-11-03)

### Observed
- USurvivalComponent (AGlimpseCharacter.SurvivalComponent): DemiGod(bool), GetStat/GetStatMax/SetStatPercent(ESurvivalNeed,
  ...); ESurvivalNeed::Health = 0. Health is a 0..1 ratio (GetStatMax = 1).
- v1 downed threshold was absolute (<= 1.5): both players "down" at once, player 1 killed -> game over (my bug).
- Owner: a player's death/low health greys the whole window (both halves).
- Crash 23:42:18 loading a save after returning to the menu: c0000005 at GlimpseGame+0x2C9640 =
  AGlimpsePlayerController "top of SpawnStats" (TArray at PC+0xD08, element 0x460) on an invalid controller;
  callers in UI/presenter code (0x47A7xx, 0x48xxxx). Player 2 had been removed (RemovePlayer) on the menu 40 s before.
- Owner: player 2 used a ladder (shelter-style transition) and the game teleported player 1.

### Change
- Downed/revive: both players DemiGod; health <= 3% -> downed (move input ignored, crouched, body lying: first of
  Male_DeadGround_Pose04 / _Floating_Pose02 / Male_SitGround_Idle / Male_Cower in memory); downed health held at 50%
  (no grey screen); revive = other player holds X (Gamepad_FaceButton_Left) within 200 units for 3 s -> 30% health;
  both down -> DemiGod off, player 1 Kill() (normal death flow).
- Main menu: player 2 is no longer removed; bUseSplitscreen off on the menu, back on in game.
- Keep together: a far jump (> 1500 units between 0.25 s steps) of one player not caused by the mod brings the other.
- Owner: DemiGod made both players take no damage at all. Replaced by a Lua RegisterHook on
  /Script/GlimpseGame.GlimpseCharacter:ReceiveTakeDamage: a hit that would leave a player at <= 2% health is
  clamped (ActualDamage:set). Owner: health drops, player goes down (Cower pose in the sandbox), X-hold revives.
- Revive UI (owner-confirmed): UMG TextBlock + Image (texture /Game/UI/PlayerMenu/Skull) constructed with
  StaticConstructObject into each player's LightHUDWidget WidgetTree and AddChild'ed to its root CanvasPanel
  (CanvasPanelSlot SetPosition/SetAlignment/SetSize/SetAutoSize with flat tables work; FText("...") works).
  Downed player: skull + "Você caiu! Aguarde seu parceiro" / "Seu parceiro está te revivendo: N%".
  Standing player: only "Segure X para reviver" when within range, "Revivendo: N%" while holding.
- NPCs kept attacking a downed player: AGlimpseAIController Get/SetTargetActor, Get/SetDetectionTarget; every 1.5 s
  while someone is down, targets on the downed pawn move to the standing pawn; downed pawn bCanBeDamaged=false.
  Log showed "retargeted 2 NPC target(s)".

## Phase 12: NPC indicators for player 2 (2026-11-04)

### Observed
- Owner: player 2's HUD shows no detection/health indicators over NPCs.
- Only one Widget_NPC_Indicator_C (UNPCIndicator) existed, in player 1's LightHUDWidget WaypointAndIndicatorPanel.
  Both HUDs (LightHUDPresenter_C) have bShowAISuspicion = true.
- RE: NPC function 0x24EC70(npc, state, float) takes the HUD of the first local player (FUN_1403a88c0 ->
  0x1C38CA0 GetHUD), checks HUD+0x538 bit 2 (bShowAISuspicion) and the NPC's 0x23B900 (show?) and calls
  0x4DAFA0(HUD, npc, state, float) (HUD+0x548 widget -> add/update indicator, list at widget+0x898, entries 0x20)
  or 0x4BCB50(HUD, npc) (remove). Widget update 0x4DBE50 projects with the widget owner's view.

### Change
- CoopMenuFix v7 hooks 0x24EC70: after the game's call, the same add/update/remove for player 2's HUD
  (GI LocalPlayers[1] + 0x30 controller, + 0x4B8 MyHUD); NPCs on player 2's HUD are tracked.

### Open
- Owner: when player 2 goes far from player 1 the world stops rendering/streaming around player 2.
- CoopMenuFix v7 owner-confirmed: player 2's HUD shows NPC indicators. (One v7 startup crash, heap corruption
  0xC0000374 in ntdll ~12 s after launch, did not repeat.)
- NPC behaviour around a downed player, final (owner-confirmed): every 1.5 s while someone is down, NPCs targeting
  the downed pawn switch to the standing player only if within 1500 units AND LineOfSightTo; otherwise
  ClearSuspicion, targets nil, SetSuspicionState(Suspicious), AGlimpseAICharacter::SetNoSuspicion(true). A calmed
  NPC is released (NoSuspicion off, target = the player) when hit (ReceiveTakeDamage DamageInstigator) or when the
  standing player is within range and in sight; all released when nobody is down.
  Tried and dropped: retarget by distance only (saw through walls); downed pawn bIsDead=true (game-over screen);
  SetNoSuspicion without release (NPCs ignored the standing player even when punched).

## Phase 13: world streaming around player 2, stale-object crashes (2026-11-04) — CHECKPOINT

### Observed
- Moving only player 2 away in 14 m steps (bridge; steps stay under the 1500-unit keep-together threshold):
  at ~550 m player 2's half shows only fog, no ground/buildings, and player 2 falls (Z -310). The game's own
  streaming (UGlimpseStreamingManager: WorldStreamingLevels +0x370, AlwaysResident +0x390, ManuallyLoaded +0x3E0,
  Proxies +0x768) only follows player 1. Its centre source is not found yet: none of the 27 callers of
  0x3A88C0 (first local player controller) touch the streaming manager fields.
- My teleport test pulled player 1 along (keep-together rule) and caused fall damage: both players ended up down,
  and the game over did NOT trigger (Kill() with bCanBeDamaged off). Fixed in Lua (damage back on before Kill), untested.
- Crash 00:45:28: c0000005 UE4SS.dll+0x4BAAAF (same address as the quit-to-menu crash) right after player 2's pawn
  died/respawned. Suspect: bodies[].pawn cached UObject used after the pawn was destroyed.
- tools/shot.ps1 was not DPI-aware: at 150% scaling it captured only the top-left 1280x720 of 1920x1080 (fixed;
  the revive skull/text are centred, not offset).

### Change (not yet run)
- Bodies keyed by pawn full name, pawn never cached; animation loop fetches pawns from the controllers each step;
  bodies of gone pawns are destroyed (K2_DestroyActor).

- (2026-11-04, session 2) noSuspicionNpcs now holds NPC full names only; live NPC/controller objects come from
  the FindAllOf("GlimpseAIController") list of the same retarget pass (liveNpcs), or from the damage hook's own
  pawn. Lua syntax checked (luaparser); not run in game yet.

### Next (in order)
1. Restart, check SplitScreenCoop loads (UE4SS.log "frame hook registered" x3), retest downed/revive, both-down
   game over, and player 2 death/respawn (no crash).
2. Code done (see Change): retest calmed NPCs (one player down -> NPCs calm; standing player hits or comes
   into view of one -> it reacts; revive -> all back to normal).
3. Streaming around player 2: find what UGlimpseStreamingManager uses as its centre (RE), or fall back to a
   distance leash (owner to choose).
4. Later: body is a generic citizen (not Arthur); DLC maps untested; DLL cleanup (diagnostic logging, v5.4 key code).

## Phase 14: world streaming for two players (2026-11-04, in progress)

### Observed
- Wrong lead: 0x4D3DA0 / 0x4CC850 / 0x4BA9B0 / 0x4D1580 (focus array +0x4D0, "zone" +0x4E8/+0x508) belong to many
  0x7xx-sized objects, NOT the streaming manager (DLL v8 diagnostics showed dozens of instances).
- Runtime (sandbox): one UGlimpseStreamingManager (SurvivalSandBoxMode_C_0.StreamingManager), one
  GlimpseWorldInstanceV2, 2305 GlimpseStreamingProxy.
- Class registration 0x778704 (GetPrivateStaticClassBody, size 0x7D0) -> InternalConstructor 0x73B260 ->
  ctor 0x62D2A0: primary vtable 0x2BFB338, FTickableGameObject vtable at +0x28 = 0x2BFB518
  [0x65CC90 Tick, 0x64F820 IsTickable, ...]. Tick(this=mgr+0x28, dt) -> sub-updates 0x65D280, 0x65E3D0.
- 0x65D280: centre = first element of FUN_1403a90d0(GameMode, 0) (a list of 2D points); box half-size and
  radius from CVars. CVars (registered at 0x92xxx): g.GlimpseDynamicStreamingRadius (0x37DC838, 9200,
  "distance at which to stream in stuff"), g.GlimpseDynamicSpawnRadius (0x37DC83C, 6400),
  g.GlimpseStreamingAuto (0x37DC870, "currently streamed zone will be determined..."),
  g.GlimpseStreamDecorators (0x37DC828), g.GlimpseDecorationCyclesTimeSlice (0x37DC868).
- Console via bridge (ExecuteConsoleCommand) accepted "g.GlimpseDynamicStreamingRadius 80000" and
  "g.GlimpseDynamicSpawnRadius 70000"; screenshot showed player 2's half rendered at ~105 m (fog state before
  unknown). 17 s later: crash 0xC0000374 heap corruption (same code as the one v7 startup crash).
  Suspects: radius far too large, or the v8 diagnostic hooks (they read +0x510 as FString on non-manager objects).
- tools/shot.ps1 DPI fix verified (full 1920x1080 capture).

### Change
- DLL back to v7 (v8 diagnostics removed; source kept as coop_menufix.c.v8-diag).

### Next
- Retest with v7: player 2 ~400-600 m away (fog), then raise g.GlimpseDynamicStreamingRadius moderately
  (e.g. 27600 = 3x) and see if player 2's world appears; check stability/memory.
- Find what FUN_1403a90d0(GameMode, 0) returns (centre list) — if it holds per-player points, the sub-update
  could use the nearest; and check whether world geometry is this "dynamic" streaming or zone streaming
  (g.GlimpseStreamingAuto).
- DLL v7 + "g.GlimpseDynamicStreamingRadius 27600" / "g.GlimpseDynamicSpawnRadius 19200" with player 2 ~166 m
  away: before = green translucent proxy where a house should be; after (12 s) = the real house. No crash.
- Change: SplitScreenCoop sets both CVars each second (ExecuteConsoleCommand) to base + player distance,
  capped at 40000, re-sent only on >10% change; back to 9200/6400 when together. Untested.
- Owner: with only the two dynamic radii scaled, houses load around player 2 but not NPCs or props (bodies,
  tables). CVar defaults read from GlimpseGame.exe registrations: g.GlimpseDynamicEvictionRadius 12800,
  g.GlimpseStreamGuardRadius 1600, g.GlimpseDynamicUnstreamTimeDelay 3, g.NPCSpawnRadius 6000,
  g.NPCDespawnRadius 8000, g.NPCCriticalRadius 1200, g.NPCPhysicsLivenessRadius 3000, g.NavMeshLiveRadius 4800,
  g.NavMeshCacheRadius 6400, g.DynamicRoadLiveRadius 20000.
- Change: the mod adds the player distance (capped 30800, 0 when < 2000) to streaming, spawn, eviction,
  NPC spawn/despawn/physics-liveness and nav mesh live/cache radii. Untested.
- Owner, all radii scaled: props (bodies, tables) now spawn around player 2; NPCs still do not.
- Crash 18:59:12: c0000005 UE4SS.dll+0x47960F (new address). Log before it: radii re-sent every 3-6 s
  (+13148, +11738, +10367, +11477, +12745, +14358) while player 2 walked: constant spawn/despawn churn at
  the disc edge; most likely Lua touching a just-destroyed object again.

### Next
- Quantize the extra radius (0 / 10000 / 20000 / 30800), raise immediately, lower only after 15 s below.
- NPCs around player 2: radii alone do not spawn them; find the AI manager's spawn centre
  (CVars g.GlimpseAIManagerSpawnLimit, g.UseAIPopulations, g.GlimpseAIManagerLiveBudget, g.DecoratorAI*).
- Change: radii extra in steps 0/10000/20000/30800, up immediately, down after 15 s (anti-churn). Untested.
- Owner, stepped radii: walked player 2 far and back, no crash; props and (apparently) NPCs now appear around
  player 2.
- Owner: player 2's view feels laggy when far (disc around player 1 with radius base + full distance).
- RE: FUN_1403a90d0(GameMode, refresh) (14 callers incl. streaming tick 0x65D280) builds the per-frame streaming
  points, TArray<FVector> at GameMode+0xDC8: an override list (GameMode+0xDD8, count +0xDE0) if set, else the
  first player controller's view point (vtable 0x680) and its pawn location (PC+0x430 -> +0x160 root -> +0x170).
- Change: CoopMenuFix v9 hooks 0x3A90D0: when players are > 2000 apart and no override is set, every point is
  replaced by the midpoint of the two pawns (values only, game buffer). Lua radii steps now use d/2 (cap covers
  ~616 m separation). Untested.
- Owner, v9 midpoint streaming: works, "a little lag but fine". Log: 204 m apart -> +20000 (was +30800).
- Incident (19:09, v9, sandbox): player 2 stopped responding (no move/jump/look) ~1.5 min after load; game
  responsive, P2 movementMode walking, move/look not ignored, no menu/cutscene/pause; DLL log showed only normal
  inventory open/close and focus updates. Not reproduced after reloading the save. Cause unknown (controller
  disconnect not ruled out).
- Loot screen bisect (2026-11-04): fails for both players with the co-op mods; works with no co-op mods, with the mod but no player 2, and with player 2 but HUD halves + menu scaling off. A bridge snippet reading LightHUDWidget_C.ContainerLootBoxWidget / QuickLootInstance crashed UE4SS (UE4SS.dll+0x388F37) — avoid.
- Bisect result: with only LightHUDWidget layer HUDCanvas left full-size, the loot screen works for both players.
  HUDCanvas has 21 children; ContainerLootBoxHost (NativeWidgetHost) anchor (0,0) offsets L11 T531 — positioned
  by the game in full-screen coordinates, so it fell outside the half-height canvas.
- Change: HUDCanvas stays full-size; each child (except ContainerLootBoxHost) keeps its size and is moved by its
  anchor (P1: -a*H/2, P2: (1-a)*H/2; stretched: Top+=shift, Bottom-=shift). Untested.
- Note: UE4SS 3.0.1 loads Mods/<mod>/dlls/main.dll even when mods.txt says 0; rename the DLL to disable it.
  CoopMenuFix re-enabled after the loot bisect.
- Freeze #4 (19:41-19:42, DLL v9.1 + new HUD layout, ~1 min after P2 joined): CPU flat. No game thread inside a
  UE4SS hook this time; main thread 5296 waiting in the engine loop (...1A41A73 -> BEF1F8 -> BE47FE event wait);
  UE4SS Lua threads idle at 2A4C20. Cause unknown.
- With HUDCanvas children moved per anchor, the loot screen came back for both players but drawn full size over
  both halves. Change: ContainerLootBoxHost keeps the game's layout and gets a render transform (pivot 0,0,
  scale 0.5, translation mapping (x,y) -> (x/2 + W/4, y/2 [+H/2])). Owner: loot screen "working perfectly" for
  both players.
- Regression (owner): inventories paused the game again and could not be navigated (both players). Cause: since
  the move to frame hooks, onFrame runs from the pawn's ReceiveTick, and pawns do not tick while paused, so the
  pause was never undone (no "pause undone" in the log). Change: PlayerMenuWidget_C:Tick
  (/Game/UI/PlayerMenu/PlayerMenuWidget) added as a frame source (widgets tick while paused). Untested.
- Owner: still paused with PlayerMenuWidget tick added (no "pause undone" in log: that hook did not run onFrame
  during the pause); inventory navigation broken for both; HUD icon row cut on P1 and over the divider on P2.
- Change: DLL v10 hooks the GI UI stack push 0x438CE0 and clears bPause when called inside
  ShowPlayerMenuWithContext (player menus never pause). Lua: stretched HUDCanvas children use the edge anchor
  nearer the screen edge as reference (mid anchor moved the 0..0.13 icon row by 35 px). Untested.
- DLL v10 owner/log: "player menu push: pause suppressed" -> inventories no longer pause (owner-confirmed).
  HUD stretched-anchor fix: icon row OK (owner).
- Inventory navigation (owner): with menus at render scale 0.5, player 1's item navigation/highlight is erratic;
  at full size player 1 is fine. Player 2 is erratic even at full size. Navigation is Slate gamepad focus
  navigation over a UniformGridPanel (UGlimpseInventoryMenu; items UInventoryItemImplement_C, native
  bHighlighted never true in snapshots). Snapshots with P2's menu open: the visible item widgets are all owned by
  player 1; player 2's user focus moves over them. SetOwningPlayer(p2) on 3 items (found via outer chain) made it
  worse, and the game recreated them with player 1 as owner. Reverted.
- Likely root causes to work on: (a) item widgets created by native code with the first local player as owner
  (fix at the source in the DLL, like the NPC indicators); (b) Slate directional navigation ignores render
  transforms, so a half-size inventory needs a layout-based shrink, not RenderScale.
- Owner agrees the menu RenderScale broke navigation again. Menus set back to full size (no_menuscale.txt kept as the switch) until a layout-based half-size inventory exists.
- Root cause found for P2 item highlight: UGlimpseInventoryMenu MakeItemWidget 0x4EE080 creates item widgets via
  CreateWidget(UWorld*) 0x4E2EA0, which sets the FIRST local player's context (FUN_141df7df0). DLL v11 hooks both:
  inside MakeItemWidget, if the menu's character (weak, menu+0x6E0) is local player N>0's pawn, the widget is
  built the same way (NewObject 0x2B4A70, FLocalPlayerContext 0x1AE0460, SetPlayerContext 0x1560230,
  Initialize vslot 0x210) with player N's context. Log line "inventory ... belongs to local player N". Untested.
- Freeze #5 (20:12-20:13, DLL v11, right after P2 joined, before any inventory opened; no "inventory belongs" log):
  same signature as #4: main thread ...1A41A73 -> BEF1F8 -> 37E5210 -> BEF34D -> BE47FE event wait; another
  engine thread (26944) waits at BE47FE via 149FC74. No main.dll / UE4SS frame on any game thread. Both freezes
  came within ~1 min of P2 joining. Stacks: local/re-work/freeze5_stacks.txt. Suspects: game/render-thread
  wait around the second view joining, or the streaming radius console commands applied at P2's join.

## Phase 15: per-player inventory item widgets (2026-11-07)
- Owner: loot screen fine for both players. Inventory still buggy (navigation/highlight).
- v11 log: "inventory ... belongs to local player -1" for BOTH players' menus: menu+0x6E0 (character weak ptr) is not
  valid yet when MakeItemWidget runs (items are built inside ShowPlayerMenuWithContext), so v11 never applied.
- Change: DLL v12 falls back to the opener controller (g_opener -> local player index), and remembers menu -> player
  for later item rebuilds. Log now says "(character|opener|remembered)". v11 source: coop_menufix.c.v11,
  v11 binary: out/main.v11.dll.bak. Untested.
- Owner retest v12: both inventories open together, no pause; navigation still broken (could not move right).
  Dump: P2's inventory was simply empty (ItemLayout UniformGridPanel with no children, Empty_asset shown) — that is
  why no "belongs" line for P2. Menus are built from ScaleBoxes.
- Layout-based half-size menus (bridge, live): RenderScale back to 1; PlayerMenu root canvas layers
  PlayerMenuBackgrounds / MenuManilaBox / SubMenuOverlay / SafeZoneCanvas (all anchors 0..1, offsets 0, SafeZone 30)
  get offsets L/R W/4, T/B H/2 (16:9 box in the owner's half). Owner: both players navigate normally.
- Fixed-pixel parts shrunk with RenderScale (not navigation targets): tab bar SafeZoneCanvas/Overlay_2/MenuButtonParent
  0.6 (pivot top), hints SafeZoneCanvas/Overlay_2/Overlay_1/SubMenuInputDisplays 0.5 (pivot bottom), quickslot hint
  (InventorySubMenu .../QuickslotDisplay/.../VerticalBox/Border_2) 0.5, InventorySubMenu InputBindingDisplays 0.5.
- Change (mod, needs restart): layoutPlayerMenus does the above (layers by offsets every frame, parts by name path
  once a second while the menu is visible). Switch: no_menulayout.txt (no_menuscale.txt is now ignored). Backup
  main.lua.bak-phase15. Untested in a fresh session; other sub-menus (journal, crafting, map) not checked.
- Freeze #6 (14:40, right after P2 joined, new menu layout session): same main-thread signature as #4/#5
  (stacks: local/re-work/freeze6_stacks.txt). Decompiled (projects2/WHF2, DecompileAt): 0x1A41A20 = FOutputDevice
  log call, 0xBEF2B5 = FOutputDeviceRedirector flush on the master thread, 0xCB131A = FOutputDeviceConsoleWindows::
  Serialize -> return address 0xCB13F8 is right after its WriteConsoleW call (0x2DA4EA8/0x2DA20B4 on the stack are its
  format strings). ROOT CAUSE (likely): the game thread blocks in WriteConsoleW on the -log console window (QuickEdit
  selection / busy console); P2 joining logs a burst of lines. Fix: run-test.ps1 no longer passes -log (log still goes
  to Saved/Logs and UE4SS.log). UE4SS's own external console was already off.
- Owner: inventory OK with offsets, but other sub-menus not (skills: "PONTOS DISPONIVEIS"/titles overlap; crafting:
  recipe names huge) — they use fixed-size fonts, not ScaleBoxes.
- Live (bridge snippet_wrap.lua): each PlayerMenu root layer (PlayerMenuBackgrounds, MenuManilaBox, SubMenuOverlay,
  SafeZoneCanvas[margin 30]) RemoveFromParent -> SizeBox(W-2b x H-2b) -> ScaleBox (StaticConstructObject, outer
  WidgetTree) -> root:AddChildToCanvas, slot SetPosition(W/4+b/2, [H/2]+b/2) SetSize((W-2b)/2,(H-2b)/2).
  Result: skills and crafting look like an exact half-size full-screen menu for both players; per-part render
  scales no longer needed (reset to 1).
- Change (mod, needs restart; DELETE Mods/SplitScreenCoop/no_menulayout.txt first — it was created to keep the old
  code off during the live test): layoutPlayerMenus now wraps the layers this way (once per menu instance, checked
  every 0.5 s, slot position kept in sync), called under pcall. Untested in a fresh session.
- Owner (fresh session, mod-wrapped menus): "funcionando perfeitamente" — all tabs, both players, navigation OK. No freeze this session (first run without -log).

## Phase 16: Arthur body (2026-11-07)
- Pak scan (index + first compressed block of each .uasset): only 26 AnimSequences use SK_Arthur_Skeleton, all
  cinematic (CIN_*_Arthur, CharacterSelect_Arthur, Central_Station_Exit...). No locomotion for Arthur.
- UE4SS 3.0.1 LoadAsset needs AssetRegistryHelpers (UE 4.17+): fails. DLL v13 loads SK_Arthur itself with
  StaticLoadObject 0xD63220 (found as LoadObject's call in 0x2B3460; "Failed to find object" ref) every 2 s on the
  game thread (stream points hook) while 2 players exist; class = UObject (GEngine class -> SuperStruct root).
  Unreferenced, it is GC'd and reloaded (StaticFindObject finds it only part of the time) until a component uses it.
- Master pose (SetMasterPoseComponent) on SK_Arthur from the NPC body: grotesque — unmapped bones (face, glasses,
  extra fingers) stay at reference component-space positions.
- Bones: same names for body/limbs (Hips, Spine1/2, Collar, Neck, Head, Clavicle/Arm/Elbow/Wrist, Leg/Knee/Ankle/Heel/
  Ball/Toe, Index/Thumb); Arthur root is Root_Reference (NPC: Root); reference orientations differ (NPC Hips ~identity,
  Arthur 90 deg about X); Arthur ~6% taller.
- UE 4.13 has no FinishAddComponent; RegisterComponent is not a UFUNCTION. DLL v14 hooks UPoseableMeshComponent::
  ResetBoneTransformByName 0x1984D10: on an unregistered component (+0xA8 bit 0) it calls RegisterComponent 0x193D040
  (the call in AActor::AddComponent impl 0x180A870) instead.
- UE4SS 3.0.1 pitfalls found: function-returned TArray elements need :get(); GetAttachedActors (out param) returns
  nothing; nested structs (FTransform) passed from Lua arrive zeroed (bones got scale 0 -> invisible): use flat
  FRotator/FVector setters (SetBoneRotationByName / SetBoneLocationByName / SetBoneScaleByName).
- Live result: retargeted Arthur visible with the right height. Hidden NPC body (SetVisibility false) stops updating
  bones -> Arthur frozen. Writing MeshComponentUpdateFlag=0 did not help, and the game exited (code 3) a minute later
  (cause unclear: that write or the GetAttachedActors out-param call).
- Change (mod): body = NPC (still animated by PlayAnimation) shrunk to 1% with BoundsScale x100 + CoopArthurBody
  PoseableMeshComponent (SK_Arthur, registered via DLL v14) attached to it, relative scale x100, retargeted every
  frame (Scripts/arthur_retarget.lua, reference rotations embedded). Needs DLL v14 (checked in menufix.log).
  Backup main.lua.bak-phase16. Untested.
- Fix: dllCanRegister read menufix.log in the wrong order ("registration hook ready" precedes "vN hooked" per start).
- Owner (fresh session, mod only): both players see the other as full-body Arthur; "se mexendo normal, andando e
  correndo". Jump/crouch/downed poses, the 1% NPC speck, and performance over a long session not checked yet.

## Phase 17: robust player placement (2026-11-07)
- Owner report (campaign, earlier session with a second player): player 2 spawned outside the world, died, and the
  game went back to the checkpoint. Old teleportBehind: fixed offsets (1.2/2 m around the target, same Z) accepted if
  TeleportTo succeeded nearby — no floor/wall check (thin walls -> outside the level); fall safety only after 3 s.
- Probes: KismetSystemLibrary has only *_NEW traces (LineTraceSingle_NEW etc.), but UE4SS 3.0.1 calls fail with every
  argument form (and UFunction:ForEachProperty errors); NavigationSystem.ProjectPointToNavigation returns the input
  point even in mid-air (useless). Sandbox KillZ = -1048575 (none).
- Change (mod): teleportSafe(pcs, mover, target, reason): candidates = target's breadcrumbs (spots it stood on with
  IsMovingOnGround, 1-10 m away, |dz| < 2.5 m, newest first, up to 6) -> old offsets -> target's own spot; each move
  verified 0.5 s later (falling and 1.5 m below -> next candidate). Fall safety: near KillZ (+15 m), falling 1.2 s and
  3 m below a standing partner, or falling 3 s. Breadcrumbs cleared on game teleports and world change. Used by
  regroup (join/respawn/after cutscene), game-teleport follow, unstuck and fall safety. Backup main.lua.bak-phase17.
  Untested.
- Owner: teleport/fall safety work. Select-hold unstuck works for both players (P1's first try was too short; log
  18:54 "unstuck: player 1 -> breadcrumb spot 1/11"). Breadcrumbs used when available; bad offset spots retried.

## Open: lights flickering on player 2's screen (2026-11-07)
- Owner saw some lights flicker on P2's half; it stopped by itself before any change (nothing was changed).
- Suspects to toggle live (bridge console commands) when it happens again, one at a time:
  1. g.GlimpseAiManagerLiveLightBudget (game light budget, probably centred on player 1 like the streaming was);
  2. light occlusion queries across two views (r.DisableLightOcclusionQueries / r.LightOcclusionStagger);
  3. cached whole-scene shadows of movable lights (r.Shadow.CacheWholeSceneShadows 0).
- Published: https://github.com/SorrowMee/we-happy-few-coop (public, 2026-11-07; repo folder cooptudo/we-happy-few-coop; DLL not committed, build with src/coop_menufix/build.cmd).
- Release v0.1.0 published (zip with prebuilt DLL, SHA-256 d32a3f35...0874); release DLL verified loading in the test copy.

## Phase 18: player 2 inventory persistence (2026-11-07)
- Owner: player 2 loses the whole inventory on every load (the game saves player 1 only).
- RE: GlimpseCharacter:AddPickup(class, count, bool) (exec 0x8B4E70 -> vslot 0x9A8, returns the pickup);
  GlimpsePlayerController:RebuildInventoryFromDump is an empty stub in this build. Characters have several
  InventoryComponent instances (GetComponentsByClass): InventoryComponent (bag), HolsterComponent (belt weapon),
  ClothingComponent (worn clothes); Contents = TArray of GlimpsePickup (CurrentStackSize, Durability, bEquipped).
  Currency = GlimpseCharacter.Currency (int). AddPickup(.., true) puts melee weapons into the holster when it is free.
- Change: mod saves player 2's items of all inventory components + currency to
  Mods/SplitScreenCoop/p2_inventory_<map>.txt every 5 s (when changed) and restores them on a new player 2 pawn
  with an empty inventory (durability set after AddPickup). DLL v15 loads object paths listed in
  Mods/CoopMenuFix/load.txt (classes not loaded on the map); restore retries 30 s, unresolved items stay in the file.
- Test (bridge-driven, no second gamepad): gave P2 3 rocks, rolling pin at 7%, 4 bottles, frying pan, 25 currency ->
  file written; restart + reload: "player 2 inventory restored: 4 item(s), currency 25", rolling pin 0.07 in the
  holster. Not restored: worn clothes (come back in the bag), quickslot assignment. One file per map, shared by all
  save slots of that map.
