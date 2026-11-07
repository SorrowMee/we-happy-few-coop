// CoopMenuFix: per-player menu input for SplitScreenCoop on We Happy Few (UE 4.13).
//
// The game pushes every player menu onto one UI stack in the GameInstance, and that stack hands the
// widget to GameInstance.UIPlayer's PlayerController (always player 1) through a per-controller UI
// input stack (PC+0x828, entries {widget, flags}; a flag blocks movement). So controller 1 drove
// player 2's inventory, and player 2 stayed blocked when the menu closed by another path.
// Reverse engineering (games/we-happy-few/NOTES.md, phase 9):
//   0x2E8E30 ShowPlayerMenuWithContext(PC, type, FName)  - every way a player menu opens
//   0x2BACF0 PushUIInput(PC, widget, a, b)               - add to a controller's UI input stack
//   0x2E1A50 RemoveUIInput(PC, widget)                   - remove from it (every way a menu closes)
//   0x43BAA0 UpdateUIFocus(GI, ...)                      - when the GI stack changed: SetInputMode
//            (GameAndUI, focus = top widget) on UIPlayer's controller, or GameOnly if none
// This DLL notes which controller is opening a menu; the push inside that call goes to that
// controller's stack instead, and the widget -> controller pair is remembered so the later removal
// (called with player 1's controller) goes to the same controller. UpdateUIFocus runs with UIPlayer's
// PlayerController (LocalPlayer+0x30) pointed at the owner of the widget it will focus; a controller
// that had focus before and is no longer the target is put back in GameOnly input mode.
//
// Loaded by UE4SS from Mods/CoopMenuFix/dlls/main.dll. It exports no UE4SS mod interface; it pins
// itself so it is never unloaded while hooks point into it. Log: Mods/CoopMenuFix/menufix.log.
//
// RVAs are for GlimpseGame.exe Steam build 4660512 (SHA-256 51CF2873...DD4F46E). The first bytes at
// every RVA are checked first; on any other build nothing is hooked. All three run on the game thread.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "MinHook.h"

#define RVA_SHOW_MENU 0x2E8E30
#define RVA_PUSH_UI 0x2BACF0
#define RVA_REMOVE_UI 0x2E1A50
#define RVA_UPDATE_FOCUS 0x43BAA0
#define RVA_NPC_INDICATOR 0x24EC70     // NPC: update its HUD indicator (uses player 1's HUD only)
#define RVA_NPC_SHOW_INDICATOR 0x23B900 // NPC: should the indicator show (char)
#define RVA_HUD_ADD_INDICATOR 0x4DAFA0  // (HUD, NPC, state, float): add/update the NPC indicator
#define RVA_HUD_REMOVE_INDICATOR 0x4BCB50 // (HUD, NPC): remove it
#define OFF_PC_MYHUD 0x4B8
#define OFF_HUD_FLAGS 0x538             // bit 1 (value 2): bShowAISuspicion
// Streaming points: FUN_1403a90d0(GameMode, refresh) builds the per-frame list of points the world streaming,
// NPC spawning etc. are centred on (TArray<FVector> at GameMode+0xDC8: player 1's view point and pawn location).
// While the players are apart, those points are moved to the midpoint between them, so the Lua mod only has to
// add half the distance to the streaming radii (much less loaded area than a disc around player 1).
#define RVA_STREAM_POINTS 0x3A90D0
// StaticLoadObject(Class, Outer, Name, Filename, LoadFlags, Sandbox, bAllowObjectReconciliation): found as the call
// in LoadObject (0x2B3460, ConstructorHelpers) and by its "Failed to find object" message. UE4SS 3.0.1's LoadAsset
// needs AssetRegistryHelpers (absent in UE 4.13), so assets the Lua mod needs but the map has not loaded (the full-body
// SK_Arthur) are loaded here on the game thread while two players exist, every 2 s (a cheap find once in memory;
// the components the Lua mod gives it to keep it alive).
#define RVA_STATIC_LOAD_OBJECT 0xD63220
#define RVA_GENGINE 0x3AAF7A8
#define LOAD_NOWARN_QUIET 0x2010
// Lua cannot register a component it constructs (UE 4.13 has no FinishAddComponent; RegisterComponent is not a
// UFUNCTION). UPoseableMeshComponent::ResetBoneTransformByName(FName) 0x1984D10 (exec 0x1FB8F80) is hooked: called on
// a component that is not registered yet (bRegistered = +0xA8 bit 0), it registers it instead, with
// UActorComponent::RegisterComponent 0x193D040 (owner's world; found as the call in AActor::AddComponent 0x180A870).
#define RVA_RESET_BONE 0x1984D10
#define RVA_REGISTER_COMPONENT 0x193D040
// GI UI stack push (GI, widget, layer, bPause, bFocus, ...): bPause increments the pause counter. Player menus
// opened through ShowPlayerMenuWithContext are pushed without pause, so an inventory never stops the other
// player (the Lua unpause stopped working when the mod moved to pawn ticks, which do not run while paused).
#define RVA_UI_STACK_PUSH 0x438CE0
// Inventory item widgets: UGlimpseInventoryMenu::MakeItemWidget 0x4EE080 (menu, ..., world, ...) creates them with
// CreateWidget(UWorld*) 0x4E2EA0, which gives every widget the FIRST local player's context. Inside an
// inventory whose character (menu+0x6E0, weak) is another local player's pawn, the widget is created the same way
// but with that player's context (player 2's item highlight followed player 1).
#define RVA_MAKE_ITEM_WIDGET 0x4EE080
#define RVA_CREATE_WIDGET_WORLD 0x4E2EA0
#define RVA_NEW_OBJECT 0x2B4A70         // StaticConstructObject(outer, class, name, flags, template, copy, graph)
#define RVA_LP_CONTEXT 0x1AE0460        // FLocalPlayerContext(ctx, LocalPlayer, world)
#define RVA_SET_PLAYER_CONTEXT 0x1560230 // UUserWidget::SetPlayerContext(widget, ctx)
#define RVA_USERWIDGET_CLASS 0x1571FB0  // UUserWidget::StaticClass() style getter (arg: registration)
#define RVA_USERWIDGET_REG 0x2AD8858
#define RVA_ITEMWIDGET_CLASS 0x77B4E0   // UInventoryItemWidget class getter (arg: registration)
#define RVA_ITEMWIDGET_REG 0x2A8FC80
#define OFF_MENU_CHARACTER 0x6E0
#define VSLOT_WIDGET_INITIALIZE 0x210
#define OFF_CTRL_PAWN 0x430      // AController::Pawn
#define OFF_ACTOR_ROOT 0x160     // AActor::RootComponent
#define OFF_COMP_WORLDLOC 0x170  // USceneComponent ComponentToWorld translation
#define MIDPOINT_MIN_DIST 2000.0f
#define RVA_HIDE_MENU 0x2CDC00          // AGlimpsePlayerController::HidePlayerMenu() (diagnostics)
#define VSLOT_MENU_HIDE 0x438           // UGlimpsePlayerMenu virtual Hide (diagnostics)
#define RVA_WEAK_GET 0xD6B170           // FWeakObjectPtr::Get()
#define RVA_WEAK_VALID 0xD6B9F0         // FWeakObjectPtr::IsValid()
#define RVA_VTBL_INPUT_GAMEONLY 0x2B76910 // FInputModeGameOnly vftable (as built in UpdateUIFocus)

#define OFF_GI_UIPLAYER 0x674       // UGlimpseGameInstance::UIPlayer (TWeakObjectPtr)
#define OFF_GI_STACK 0x680          // TArray<Entry*> UI stack: data, num at +8
#define OFF_GI_DIRTY 0x690          // bit 0: focus update pending
#define OFF_ENTRY_WIDGET 0x08       // Entry: Slate widget pointer
#define OFF_ENTRY_FOCUS 0x1C        // Entry: focus mode, 0 = none
#define OFF_PLAYER_CONTROLLER 0x30  // UPlayer::PlayerController
#define VSLOT_SET_INPUT_MODE 0xAF8  // APlayerController::SetInputMode(const FInputModeDataBase&)

static const unsigned char EXPECT_SHOW[] = { 0x48, 0x89, 0x5C, 0x24, 0x08, 0x4C, 0x89, 0x44, 0x24, 0x18, 0x57, 0x48, 0x83, 0xEC, 0x20, 0x48 };
static const unsigned char EXPECT_PUSH[] = { 0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74, 0x24, 0x10, 0x57, 0x48, 0x83, 0xEC, 0x30, 0x48 };
static const unsigned char EXPECT_NPC_IND[] = { 0x48, 0x89, 0x5C, 0x24, 0x10, 0x56, 0x48, 0x83, 0xEC, 0x30, 0x0F, 0x29, 0x74, 0x24, 0x20, 0x8B };
static const unsigned char EXPECT_HUD_ADD[] = { 0x48, 0x8B, 0x89, 0x48, 0x05, 0x00, 0x00, 0x48, 0x85, 0xC9, 0x0F, 0x85, 0x10, 0x00, 0x00, 0x00 };
static const unsigned char EXPECT_NPC_SHOW[] = { 0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0xE8, 0xB5, 0xCF, 0x16, 0x00, 0x48, 0x85, 0xC0, 0x74, 0x57 };
static const unsigned char EXPECT_MAKEITEM[] = { 0x4C, 0x89, 0x44, 0x24, 0x18, 0x55, 0x53, 0x56, 0x57, 0x41, 0x54, 0x41, 0x56, 0x48, 0x8B, 0xEC };
static const unsigned char EXPECT_CREATEW[] = { 0x48, 0x89, 0x5C, 0x24, 0x18, 0x57, 0x48, 0x83, 0xEC, 0x50, 0x48, 0x8B, 0xDA, 0x48, 0x8B, 0xF9 };
static const unsigned char EXPECT_STACKPUSH[] = { 0x44, 0x88, 0x4C, 0x24, 0x20, 0x55, 0x53, 0x56, 0x41, 0x56, 0x41, 0x57, 0x48, 0x8D, 0x6C, 0x24 };
static const unsigned char EXPECT_LOAD[] = { 0x40, 0x55, 0x56, 0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57, 0x48, 0x8D, 0xAC, 0x24, 0xB8 };
static const unsigned char EXPECT_RESETBONE[] = { 0x48, 0x89, 0x54, 0x24, 0x10, 0x53, 0x48, 0x83, 0xEC, 0x40, 0x48, 0x83, 0xB9, 0xF8, 0x07, 0x00 };
static const unsigned char EXPECT_REGCOMP[] = { 0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x8B, 0x89, 0xB0, 0x00, 0x00, 0x00 };
static const unsigned char EXPECT_POINTS[] = { 0x48, 0x89, 0x7C, 0x24, 0x20, 0x41, 0x56, 0x48, 0x83, 0xEC, 0x50, 0x44, 0x0F, 0xB6, 0xF2, 0x48 };
static const unsigned char EXPECT_HIDE[] = { 0x40, 0x53, 0x48, 0x83, 0xEC, 0x30, 0x48, 0x83, 0xB9, 0x10, 0x0B, 0x00, 0x00, 0x00, 0x48, 0x8B };
static const unsigned char EXPECT_UPDATE[] = { 0x48, 0x8B, 0xC4, 0x55, 0x41, 0x56, 0x48, 0x8D, 0x68, 0xA1, 0x48, 0x81, 0xEC, 0xC8, 0x00, 0x00 };
static const unsigned char EXPECT_WEAK_GET[] = { 0x48, 0x89, 0x6C, 0x24, 0x20, 0x56, 0x48, 0x83, 0xEC, 0x20, 0x44, 0x8B, 0x41, 0x04, 0x33, 0xED };
static const unsigned char EXPECT_WEAK_VALID[] = { 0x48, 0x83, 0xEC, 0x28, 0x8B, 0x51, 0x04, 0x85, 0xD2, 0x75, 0x07, 0x32, 0xC0, 0x48, 0x83, 0xC4 };
static const unsigned char EXPECT_REMOVE[] = { 0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8D, 0x99, 0x28, 0x08, 0x00 };

typedef void(__fastcall *ShowFn)(void *pc, int menuType, unsigned long long contextName);
typedef void(__fastcall *PushFn)(void *pc, void *widget, unsigned long long a, unsigned long long b);
typedef void(__fastcall *RemoveFn)(void *pc, void *widget);
typedef void(__fastcall *UpdateFn)(unsigned char *gi, unsigned long long a, unsigned long long b, unsigned long long c);
typedef void *(__fastcall *WeakGetFn)(const void *weak);
typedef char(__fastcall *WeakValidFn)(const void *weak);
typedef void(__fastcall *SetInputModeFn)(void *pc, const void *mode);

static ShowFn g_origShow;
static PushFn g_origPush;
static RemoveFn g_origRemove;
static UpdateFn g_origUpdate;
typedef void(__fastcall *HideFn)(void *self);
static HideFn g_origHidePC, g_origMenuHide;
static int g_menuHideHooked;
typedef void(__fastcall *NpcIndicatorFn)(void *npc, int state, float value);
typedef char(__fastcall *NpcShowFn)(void *npc);
typedef void(__fastcall *HudAddFn)(void *hud, void *npc, int state, float value);
typedef void(__fastcall *HudRemoveFn)(void *hud, void *npc);
static NpcIndicatorFn g_origNpcIndicator;
static NpcShowFn g_npcShow;
static HudAddFn g_hudAdd;
static HudRemoveFn g_hudRemove;
static unsigned char *g_gi; // GameInstance, seen in UpdateUIFocus
typedef unsigned char *(__fastcall *PointsFn)(unsigned char *gameMode, char refresh);
typedef void(__fastcall *StackPushFn)(void *gi, void *widget, int layer, char pause, char focus, char p6, int p7, void *p8);
static StackPushFn g_origStackPush;
typedef unsigned long long(__fastcall *MakeItemFn)(void *menu, void *p2, void *p3, void *pickup, void *world, void *p6);
typedef void *(__fastcall *CreateWFn)(void *world, unsigned char *cls);
typedef void *(__fastcall *NewObjectFn)(void *outer, void *cls, unsigned long long name, unsigned long long flags, void *tmpl, unsigned long long copy, void *graph);
typedef void *(__fastcall *LpContextFn)(void *ctx, void *lp, void *world);
typedef void(__fastcall *SetCtxFn)(void *widget, void *ctx);
typedef unsigned char *(__fastcall *ClassGetFn)(void *reg);
static MakeItemFn g_origMakeItem;
static CreateWFn g_origCreateW;
static NewObjectFn g_newObject;
static LpContextFn g_lpContext;
static SetCtxFn g_setCtx;
static ClassGetFn g_userWidgetClass, g_itemWidgetClass;
static unsigned char *g_base;
static void *g_itemMenu;  // inventory menu inside MakeItemWidget, else NULL
static void *g_lastLoggedMenu;
static PointsFn g_origPoints;
#define MAX_NPC2 256
static void *g_npcOnHud2[MAX_NPC2]; // NPCs whose indicator is on player 2's HUD
static WeakGetFn g_weakGet;
static WeakValidFn g_weakValid;
static void *g_vtblGameOnly;
#define MAX_PCS 4
static void *g_uiModePcs[MAX_PCS]; // other players' controllers UpdateUIFocus put in a UI input mode
// UIPlayer's controller when these lists were filled. A different one means the world changed and
// every remembered controller may be gone: the lists are dropped without touching them
// (v4 crashed calling SetInputMode on the main menu's destroyed controller after loading a save).
static void *g_epochUiPc;
static void *g_opener; // controller inside ShowPlayerMenuWithContext, else NULL

#define MAX_OWNED 16
static struct { void *widget, *pc; } g_owned[MAX_OWNED];
#define MAX_MENU_OWNERS 8
static struct { void *menu; int idx; } g_menuOwners[MAX_MENU_OWNERS];
static int g_menuOwnerNext;

static wchar_t g_dir[MAX_PATH];

static void forget_all(void)
{
    memset(g_uiModePcs, 0, sizeof g_uiModePcs);
    memset(g_owned, 0, sizeof g_owned);
    memset(g_npcOnHud2, 0, sizeof g_npcOnHud2);
    memset(g_menuOwners, 0, sizeof g_menuOwners);
}

static void log_line(const char *fmt, ...)
{
    wchar_t path[MAX_PATH];
    FILE *f;
    va_list ap;
    SYSTEMTIME t;
    _snwprintf_s(path, MAX_PATH, _TRUNCATE, L"%s\\menufix.log", g_dir);
    if (_wfopen_s(&f, path, L"a") != 0 || !f) return;
    GetLocalTime(&t);
    fprintf(f, "%02d:%02d:%02d ", t.wHour, t.wMinute, t.wSecond);
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static void remember(void *widget, void *pc)
{
    int i, free_slot = -1;
    for (i = 0; i < MAX_OWNED; i++) {
        if (g_owned[i].widget == widget) { g_owned[i].pc = pc; return; }
        if (!g_owned[i].widget && free_slot < 0) free_slot = i;
    }
    if (free_slot < 0) free_slot = 0; // full: overwrite the oldest slot
    g_owned[free_slot].widget = widget;
    g_owned[free_slot].pc = pc;
}

static void *owner_of(void *widget)
{
    int i;
    for (i = 0; i < MAX_OWNED; i++)
        if (g_owned[i].widget == widget) return g_owned[i].pc;
    return NULL;
}

// Logs up to 12 caller frames as GlimpseGame.exe RVAs (others as absolute addresses).
static void log_stack(const char *what)
{
    void *frames[26];
    char buf[700];
    unsigned char *base = (unsigned char *)GetModuleHandleW(NULL);
    USHORT n = RtlCaptureStackBackTrace(1, 26, frames, NULL), i;
    int len = 0;
    for (i = 0; i < n && len < (int)sizeof buf - 24; i++) {
        unsigned char *f = (unsigned char *)frames[i];
        if (f >= base && f < base + 0x4000000)
            len += sprintf_s(buf + len, sizeof buf - len, " %X", (unsigned)(f - base));
        else
            len += sprintf_s(buf + len, sizeof buf - len, " ext");
    }
    log_line("%s stack:%s", what, buf);
}

static void *take_owner(void *widget)
{
    int i;
    for (i = 0; i < MAX_OWNED; i++) {
        if (g_owned[i].widget == widget) {
            void *pc = g_owned[i].pc;
            g_owned[i].widget = g_owned[i].pc = NULL;
            return pc;
        }
    }
    return NULL;
}

// NPC indicators (suspicion/aggression/health over NPC heads): the game only ever gives them to player 1's
// HUD. After the game's own update, the same is done for player 2's HUD (GI LocalPlayers[1] -> controller ->
// MyHUD), remembering which NPCs are on it so they are removed when the game would remove them.
static void *player2_hud(void)
{
    void **lps;
    unsigned char *lp, *pc;
    if (!g_gi || *(int *)(g_gi + 0x40) < 2) return NULL;
    lps = *(void ***)(g_gi + 0x38);
    lp = (unsigned char *)lps[1];
    pc = lp ? *(unsigned char **)(lp + OFF_PLAYER_CONTROLLER) : NULL;
    return pc ? *(void **)(pc + OFF_PC_MYHUD) : NULL;
}

static int npc_slot(void *npc, int create)
{
    int i, free_slot = -1;
    for (i = 0; i < MAX_NPC2; i++) {
        if (g_npcOnHud2[i] == npc) return i;
        if (!g_npcOnHud2[i] && free_slot < 0) free_slot = i;
    }
    if (create && free_slot >= 0) { g_npcOnHud2[free_slot] = npc; return free_slot; }
    return -1;
}

static void __fastcall hook_npc_indicator(void *npc, int state, float value)
{
    char show = g_npcShow(npc);
    unsigned char *hud2;
    g_origNpcIndicator(npc, state, value);
    hud2 = (unsigned char *)player2_hud();
    if (!hud2) return;
    if (show) {
        if (hud2[OFF_HUD_FLAGS] & 2) {
            if (npc_slot(npc, 0) < 0) log_line("NPC indicator %p added to player 2's HUD", npc);
            g_hudAdd(hud2, npc, state, value);
            npc_slot(npc, 1);
        }
    } else {
        int k = npc_slot(npc, 0);
        if (k >= 0) {
            g_hudRemove(hud2, npc);
            g_npcOnHud2[k] = NULL;
        }
    }
}

// World location of local player i's pawn, or 0 if there is none.
static int player_location(int i, float out[3])
{
    void **lps;
    unsigned char *lp, *pc, *pawn, *root;
    if (!g_gi || *(int *)(g_gi + 0x40) <= i) return 0;
    lps = *(void ***)(g_gi + 0x38);
    lp = (unsigned char *)lps[i];
    pc = lp ? *(unsigned char **)(lp + OFF_PLAYER_CONTROLLER) : NULL;
    pawn = pc ? *(unsigned char **)(pc + OFF_CTRL_PAWN) : NULL;
    root = pawn ? *(unsigned char **)(pawn + OFF_ACTOR_ROOT) : NULL;
    if (!root) return 0;
    memcpy(out, root + OFF_COMP_WORLDLOC, 12);
    return 1;
}

typedef void *(__fastcall *StaticLoadFn)(void *cls, void *outer, const wchar_t *name, const wchar_t *file, unsigned flags, void *sandbox, char reconcile);
static StaticLoadFn g_staticLoad;
static const wchar_t *LOAD_ASSETS[] = { L"/Game/Character/Narrative/Arthur/SK_Arthur.SK_Arthur" };

static void load_coop_assets(void)
{
    static ULONGLONG last;
    static int logged[sizeof LOAD_ASSETS / sizeof LOAD_ASSETS[0]];
    ULONGLONG now = GetTickCount64();
    unsigned char *engine, *cls;
    int i;
    if (!g_staticLoad || now - last < 2000) return;
    last = now;
    engine = *(unsigned char **)(g_base + RVA_GENGINE);
    cls = engine ? *(unsigned char **)(engine + 0x10) : NULL; // UObjectBase::ClassPrivate
    while (cls && *(unsigned char **)(cls + 0x30)) cls = *(unsigned char **)(cls + 0x30); // SuperStruct -> UObject
    if (!cls) return;
    for (i = 0; i < (int)(sizeof LOAD_ASSETS / sizeof LOAD_ASSETS[0]); i++) {
        void *o = g_staticLoad(cls, NULL, LOAD_ASSETS[i], NULL, LOAD_NOWARN_QUIET, NULL, 1);
        if (logged[i] != (o ? 1 : 2)) {
            log_line("asset %ls: %s (%p)", LOAD_ASSETS[i], o ? "loaded" : "NOT found", o);
            logged[i] = o ? 1 : 2;
        }
    }
}

typedef void(__fastcall *ResetBoneFn)(unsigned char *comp, unsigned long long boneName);
typedef void(__fastcall *RegisterCompFn)(unsigned char *comp);
static ResetBoneFn g_origResetBone;
static RegisterCompFn g_registerComponent;

static void __fastcall hook_reset_bone(unsigned char *comp, unsigned long long boneName)
{
    if (comp && !(comp[0xA8] & 1) && g_registerComponent) {
        log_line("registering component %p (asked through ResetBoneTransformByName)", comp);
        g_registerComponent(comp);
        return;
    }
    g_origResetBone(comp, boneName);
}

static unsigned char *__fastcall hook_stream_points(unsigned char *gameMode, char refresh)
{
    unsigned char *arr = g_origPoints(gameMode, refresh); // TArray<FVector>: data, num
    float a[3], b[3];
    float *pts;
    int n, k;
    if (!arr || !player_location(0, a) || !player_location(1, b)) return arr;
    load_coop_assets();
    if (*(int *)(gameMode + 0xDE0) != 0) return arr; // the game's own override points (e.g. cutscenes): leave them
    if ((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) < MIDPOINT_MIN_DIST * MIDPOINT_MIN_DIST) return arr;
    pts = *(float **)arr;
    n = *(int *)(arr + 8);
    for (k = 0; k < n && k < 4 && pts; k++) {
        pts[k * 3 + 0] = (a[0] + b[0]) * 0.5f;
        pts[k * 3 + 1] = (a[1] + b[1]) * 0.5f;
        pts[k * 3 + 2] = (a[2] + b[2]) * 0.5f;
    }
    return arr;
}

static void __fastcall hook_stack_push(void *gi, void *widget, int layer, char pause, char focus, char p6, int p7, void *p8)
{
    if (g_opener && pause) {
        log_line("player menu push: pause suppressed (opener %p)", g_opener);
        pause = 0;
    }
    g_origStackPush(gi, widget, layer, pause, focus, p6, p7, p8);
}

static int is_child_of(unsigned char *cls, unsigned char *parent)
{
    for (; cls; cls = *(unsigned char **)(cls + 0x30)) if (cls == parent) return 1;
    return 0;
}

// Local player index whose pawn is the inventory menu's character, or -1.
static int menu_player(void *menu)
{
    void **lps;
    void *ch;
    int i, n;
    if (!g_gi || !g_weakValid((unsigned char *)menu + OFF_MENU_CHARACTER)) return -1;
    ch = g_weakGet((unsigned char *)menu + OFF_MENU_CHARACTER);
    lps = *(void ***)(g_gi + 0x38);
    n = *(int *)(g_gi + 0x40);
    for (i = 0; i < n && i < 8; i++) {
        unsigned char *pc = lps[i] ? *(unsigned char **)((unsigned char *)lps[i] + OFF_PLAYER_CONTROLLER) : NULL;
        if (pc && ch && *(void **)(pc + OFF_CTRL_PAWN) == ch) return i;
    }
    return -1;
}

// Local player index of a player controller, or -1.
static int pc_player(void *pc)
{
    void **lps;
    int i, n;
    if (!g_gi || !pc) return -1;
    lps = *(void ***)(g_gi + 0x38);
    n = *(int *)(g_gi + 0x40);
    for (i = 0; i < n && i < 8; i++)
        if (lps[i] && *(void **)((unsigned char *)lps[i] + OFF_PLAYER_CONTROLLER) == pc) return i;
    return -1;
}

// Inventory menu -> local player, learned while the menu is being shown (menu+0x6E0 is not set yet then:
// v11 logged "local player -1" for both players), reused when the game rebuilds items later.

static int menu_owner_lookup(void *menu)
{
    int i;
    for (i = 0; i < MAX_MENU_OWNERS; i++)
        if (g_menuOwners[i].menu == menu) return g_menuOwners[i].idx;
    return -1;
}

static void menu_owner_store(void *menu, int idx)
{
    int i;
    for (i = 0; i < MAX_MENU_OWNERS; i++)
        if (g_menuOwners[i].menu == menu) { g_menuOwners[i].idx = idx; return; }
    g_menuOwners[g_menuOwnerNext].menu = menu;
    g_menuOwners[g_menuOwnerNext].idx = idx;
    g_menuOwnerNext = (g_menuOwnerNext + 1) % MAX_MENU_OWNERS;
}

static void *__fastcall hook_create_widget(void *world, unsigned char *cls)
{
    void *menu = g_itemMenu;
    int idx;
    const char *how;
    unsigned char ctx[16];
    unsigned char *w;
    if (!menu || !world || !cls) return g_origCreateW(world, cls);
    idx = menu_player(menu);
    how = "character";
    if (idx < 0 && g_opener) { idx = pc_player(g_opener); how = "opener"; }
    if (idx < 0) { idx = menu_owner_lookup(menu); how = "remembered"; }
    else menu_owner_store(menu, idx);
    if (menu != g_lastLoggedMenu) {
        log_line("inventory %p belongs to local player %d (%s)", menu, idx, how);
        g_lastLoggedMenu = menu;
    }
    if (idx <= 0) return g_origCreateW(world, cls);
    // Same steps as the game's CreateWidget(UWorld*), with local player idx instead of the first one.
    if (!is_child_of(cls, g_userWidgetClass(g_base + RVA_USERWIDGET_REG))) return NULL;
    if (*(unsigned *)(cls + 0xB4) & 0x82000001) return NULL;
    w = (unsigned char *)g_newObject(world, cls, 0, 0, NULL, 0, NULL);
    if (!w) return NULL;
    memset(ctx, 0, sizeof ctx);
    g_setCtx(w, g_lpContext(ctx, (*(void ***)(g_gi + 0x38))[idx], NULL));
    (*(void(__fastcall **)(void *))(*(unsigned char **)w + VSLOT_WIDGET_INITIALIZE))(w);
    if (!is_child_of(*(unsigned char **)(w + 0x10), g_itemWidgetClass(g_base + RVA_ITEMWIDGET_REG))) return NULL;
    return w;
}

static unsigned long long __fastcall hook_make_item(void *menu, void *p2, void *p3, void *pickup, void *world, void *p6)
{
    void *prev = g_itemMenu;
    unsigned long long r;
    g_itemMenu = menu;
    r = g_origMakeItem(menu, p2, p3, pickup, world, p6);
    g_itemMenu = prev;
    return r;
}

static void __fastcall hook_hide_pc(void *pc)
{
    log_line("HidePlayerMenu: controller %p", pc);
    log_stack("HidePlayerMenu");
    g_origHidePC(pc);
}

static void __fastcall hook_menu_hide(void *menu)
{
    log_line("menu Hide (vtable 0x438): menu %p", menu);
    log_stack("menu Hide");
    g_origMenuHide(menu);
}

// Diagnostics: log the game viewport client's vtables (UObject part and FViewportClient part at +0x28)
// as RVAs, to find InputKey statically. GEngine is the global at RVA 0x3AAF7A8; GameViewport at +0x608.
static void log_viewport_vtables(void)
{
    unsigned char *base = (unsigned char *)GetModuleHandleW(NULL);
    unsigned char *engine = *(unsigned char **)(base + 0x3AAF7A8);
    unsigned char *gvc = engine ? *(unsigned char **)(engine + 0x608) : NULL;
    int part, i;
    if (!gvc) { log_line("no game viewport client"); return; }
    for (part = 0; part < 2; part++) {
        unsigned char **vt = *(unsigned char ***)(gvc + (part ? 0x28 : 0));
        char buf[600];
        int len = sprintf_s(buf, sizeof buf, "viewport client vtable %s at RVA %X:", part ? "FViewportClient(+0x28)" : "UObject",
                            (unsigned)((unsigned char *)vt - base));
        for (i = 0; i < 24 && len < (int)sizeof buf - 12; i++)
            len += sprintf_s(buf + len, sizeof buf - len, " %X", (unsigned)(vt[i] - base));
        log_line("%s", buf);
    }
}

// Diagnostics: every key event at the viewport (with ControllerId) and at each PlayerController.
// FKey is passed by pointer; its first 8 bytes are the key's FName (index, number).
typedef char(__fastcall *VpInputKeyFn)(void *self, void *viewport, int controllerId, void *key, int event, float amount, char gamepad);
typedef char(__fastcall *PcInputKeyFn)(void *pc, void *key, int event, float amount, char gamepad);
static VpInputKeyFn g_origVpInputKey;
static PcInputKeyFn g_origPcInputKey;

static char __fastcall hook_vp_input_key(void *self, void *viewport, int controllerId, void *key, int event, float amount, char gamepad)
{
    if (event == 0 || event == 1) { // IE_Pressed / IE_Released
        log_line("viewport key %X ev %d controllerId %d gamepad %d", *(unsigned *)key, event, controllerId, gamepad);
        if (event == 0 && *(unsigned *)key == 0x9EC) log_stack("viewport key 9EC");
    }
    return g_origVpInputKey(self, viewport, controllerId, key, event, amount, gamepad);
}

static char __fastcall hook_pc_input_key(void *pc, void *key, int event, float amount, char gamepad)
{
    char r = g_origPcInputKey(pc, key, event, amount, gamepad);
    if (event == 0 || event == 1)
        log_line("  controller %p key %X ev %d -> %d", pc, *(unsigned *)key, event, r);
    return r;
}

static void hook_input_diagnostics(void *pc)
{
    unsigned char *base = (unsigned char *)GetModuleHandleW(NULL);
    unsigned char *engine = *(unsigned char **)(base + 0x3AAF7A8);
    unsigned char *gvc = engine ? *(unsigned char **)(engine + 0x608) : NULL;
    void *vpFn = gvc ? (*(void ***)(gvc + 0x28))[8] : NULL;
    void *pcFn = *(void **)(*(unsigned char **)pc + 0xB28);
    if (vpFn && MH_CreateHook(vpFn, (void *)hook_vp_input_key, (void **)&g_origVpInputKey) == MH_OK && MH_EnableHook(vpFn) == MH_OK)
        log_line("hooked viewport InputKey at RVA %X", (unsigned)((unsigned char *)vpFn - base));
    if (MH_CreateHook(pcFn, (void *)hook_pc_input_key, (void **)&g_origPcInputKey) == MH_OK && MH_EnableHook(pcFn) == MH_OK)
        log_line("hooked PlayerController InputKey at RVA %X", (unsigned)((unsigned char *)pcFn - base));
}

static void hook_menu_hide_once(void *pc)
{
    unsigned char *menu = *(unsigned char **)((unsigned char *)pc + 0xB10);
    void *fn;
    if (g_menuHideHooked || !menu) return;
    g_menuHideHooked = 1;
    (void)hook_input_diagnostics; // v5.4 key diagnostics, off
    fn = *(void **)(*(unsigned char **)menu + VSLOT_MENU_HIDE);
    if (MH_CreateHook(fn, (void *)hook_menu_hide, (void **)&g_origMenuHide) == MH_OK && MH_EnableHook(fn) == MH_OK)
        log_line("hooked menu Hide at RVA %X", (unsigned)((unsigned char *)fn - (unsigned char *)GetModuleHandleW(NULL)));
    else
        log_line("could not hook menu Hide");
}

static void __fastcall hook_show(void *pc, int menuType, unsigned long long contextName)
{
    void *outer = g_opener;
    log_line("show menu requested: controller %p, type %d, context %llX", pc, menuType, contextName);
    log_stack("show menu");
    hook_menu_hide_once(pc);
    g_opener = pc;
    g_origShow(pc, menuType, contextName);
    g_opener = outer;
}

static void __fastcall hook_push(void *pc, void *widget, unsigned long long a, unsigned long long b)
{
    if (g_opener && g_opener != pc) {
        log_line("push widget %p: controller %p -> %p (opener)", widget, pc, g_opener);
        remember(widget, g_opener);
        pc = g_opener;
    }
    g_origPush(pc, widget, a, b);
}

static void __fastcall hook_remove(void *pc, void *widget)
{
    void *owner = take_owner(widget);
    if (owner && owner != pc) {
        log_line("remove widget %p: controller %p -> %p (owner)", widget, pc, owner);
        pc = owner;
    }
    g_origRemove(pc, widget);
}

static void set_game_only(void *pc)
{
    struct { void *vtbl; unsigned char flag; unsigned char pad[7]; } mode = { g_vtblGameOnly, 1, { 0 } };
    SetInputModeFn fn = *(SetInputModeFn *)(*(unsigned char **)pc + VSLOT_SET_INPUT_MODE);
    fn(pc, &mode);
}

static void note_ui_mode(void *pc)
{
    int i, free_slot = -1;
    for (i = 0; i < MAX_PCS; i++) {
        if (g_uiModePcs[i] == pc) return;
        if (!g_uiModePcs[i] && free_slot < 0) free_slot = i;
    }
    if (free_slot >= 0) g_uiModePcs[free_slot] = pc;
}

static void __fastcall hook_update(unsigned char *gi, unsigned long long a, unsigned long long b, unsigned long long c)
{
    unsigned char *lp;
    void **slot, *uiPc, *target, **data;
    g_gi = gi;
    void *withMenu[MAX_OWNED + 1];
    int n, i, j, nWith = 0, found = 0;
    if (!(*(unsigned *)(gi + OFF_GI_DIRTY) & 1) || !g_weakValid(gi + OFF_GI_UIPLAYER)) {
        g_origUpdate(gi, a, b, c);
        return;
    }
    lp = (unsigned char *)g_weakGet(gi + OFF_GI_UIPLAYER);
    slot = lp ? (void **)(lp + OFF_PLAYER_CONTROLLER) : NULL;
    uiPc = slot ? *slot : NULL;
    if (!uiPc) {
        g_origUpdate(gi, a, b, c);
        return;
    }
    if (uiPc != g_epochUiPc) {
        if (g_epochUiPc) log_line("UI player controller changed (%p -> %p): forgetting menus", g_epochUiPc, uiPc);
        forget_all();
        g_epochUiPc = uiPc;
    }
    // Owner of every focusable entry; the topmost one is what UpdateUIFocus will focus.
    target = uiPc;
    data = *(void ***)(gi + OFF_GI_STACK);
    n = *(int *)(gi + OFF_GI_STACK + 8);
    for (i = n - 1; i >= 0; i--) {
        unsigned char *e = (unsigned char *)data[i];
        if (e && e[OFF_ENTRY_FOCUS]) {
            void *owner = owner_of(*(void **)(e + OFF_ENTRY_WIDGET));
            if (!owner) owner = uiPc;
            if (!found) { target = owner; found = 1; }
            if (nWith < MAX_OWNED + 1) withMenu[nWith++] = owner;
        }
    }
    if (target != uiPc) {
        *slot = target;
        g_origUpdate(gi, a, b, c);
        *slot = uiPc;
        log_line("focus update: menu focus -> controller %p (not UI player %p)", target, uiPc);
    } else {
        g_origUpdate(gi, a, b, c);
    }
    if (found && target != uiPc) {
        int uiHas = 0;
        note_ui_mode(target);
        // Focus went to another player: UIPlayer's own controller may still be in GameAndUI from its
        // own menu (closed meanwhile), which let controller 1 drive player 2's menu.
        for (j = 0; j < nWith; j++) if (withMenu[j] == uiPc) uiHas = 1;
        if (!uiHas) set_game_only(uiPc);
    }
    // SetInputMode(GameAndUI) moves every Slate user's focus to the focused menu, so another player's
    // gamepad presses were swallowed by it (player 2 could not open its inventory while player 1's
    // was open). Every local player without a menu of its own gets game-only input back.
    // GameInstance LocalPlayers: TArray at GI+0x38 (data, num at +0x40).
    if (found) {
        void **lps = *(void ***)(gi + 0x38);
        int nlp = *(int *)(gi + 0x40);
        for (i = 0; i < nlp && i < 8; i++) {
            void *pc = lps[i] ? *(void **)((unsigned char *)lps[i] + OFF_PLAYER_CONTROLLER) : NULL;
            int has = 0;
            if (!pc || pc == target) continue;
            for (j = 0; j < nWith; j++) if (withMenu[j] == pc) has = 1;
            if (!has) {
                set_game_only(pc);
                log_line("focus update: local player %d controller %p has no menu, GameOnly", i, pc);
            }
        }
    }
    // Another player's controller with no focusable menu left goes back to game-only input.
    for (i = 0; i < MAX_PCS; i++) {
        void *pc = g_uiModePcs[i];
        int has = 0;
        if (!pc) continue;
        for (j = 0; j < nWith; j++) if (withMenu[j] == pc) has = 1;
        if (!has) {
            set_game_only(pc);
            log_line("focus update: controller %p has no menu left, GameOnly", pc);
            g_uiModePcs[i] = NULL;
        }
    }
}

static int bytes_match(const unsigned char *base, unsigned rva, const unsigned char *expect, size_t n)
{
    return memcmp(base + rva, expect, n) == 0;
}

static DWORD WINAPI install(LPVOID unused)
{
    unsigned char *base = (unsigned char *)GetModuleHandleW(NULL);
    (void)unused;
    if (!bytes_match(base, RVA_SHOW_MENU, EXPECT_SHOW, sizeof EXPECT_SHOW) ||
        !bytes_match(base, RVA_PUSH_UI, EXPECT_PUSH, sizeof EXPECT_PUSH) ||
        !bytes_match(base, RVA_REMOVE_UI, EXPECT_REMOVE, sizeof EXPECT_REMOVE) ||
        !bytes_match(base, RVA_UPDATE_FOCUS, EXPECT_UPDATE, sizeof EXPECT_UPDATE) ||
        !bytes_match(base, RVA_HIDE_MENU, EXPECT_HIDE, sizeof EXPECT_HIDE) ||
        !bytes_match(base, RVA_NPC_INDICATOR, EXPECT_NPC_IND, sizeof EXPECT_NPC_IND) ||
        !bytes_match(base, RVA_STREAM_POINTS, EXPECT_POINTS, sizeof EXPECT_POINTS) ||
        !bytes_match(base, RVA_UI_STACK_PUSH, EXPECT_STACKPUSH, sizeof EXPECT_STACKPUSH) ||
        !bytes_match(base, RVA_MAKE_ITEM_WIDGET, EXPECT_MAKEITEM, sizeof EXPECT_MAKEITEM) ||
        !bytes_match(base, RVA_CREATE_WIDGET_WORLD, EXPECT_CREATEW, sizeof EXPECT_CREATEW) ||
        !bytes_match(base, RVA_HUD_ADD_INDICATOR, EXPECT_HUD_ADD, sizeof EXPECT_HUD_ADD) ||
        !bytes_match(base, RVA_HUD_REMOVE_INDICATOR, EXPECT_HUD_ADD, sizeof EXPECT_HUD_ADD) ||
        !bytes_match(base, RVA_NPC_SHOW_INDICATOR, EXPECT_NPC_SHOW, sizeof EXPECT_NPC_SHOW) ||
        !bytes_match(base, RVA_WEAK_GET, EXPECT_WEAK_GET, sizeof EXPECT_WEAK_GET) ||
        !bytes_match(base, RVA_WEAK_VALID, EXPECT_WEAK_VALID, sizeof EXPECT_WEAK_VALID)) {
        log_line("unknown game build: bytes at the expected addresses differ, not hooking");
        return 0;
    }
    g_weakGet = (WeakGetFn)(base + RVA_WEAK_GET);
    g_base = base;
    if (bytes_match(base, RVA_STATIC_LOAD_OBJECT, EXPECT_LOAD, sizeof EXPECT_LOAD))
        g_staticLoad = (StaticLoadFn)(base + RVA_STATIC_LOAD_OBJECT);
    else
        log_line("StaticLoadObject bytes differ: asset loading off");

    g_newObject = (NewObjectFn)(base + RVA_NEW_OBJECT);
    g_lpContext = (LpContextFn)(base + RVA_LP_CONTEXT);
    g_setCtx = (SetCtxFn)(base + RVA_SET_PLAYER_CONTEXT);
    g_userWidgetClass = (ClassGetFn)(base + RVA_USERWIDGET_CLASS);
    g_itemWidgetClass = (ClassGetFn)(base + RVA_ITEMWIDGET_CLASS);
    g_weakValid = (WeakValidFn)(base + RVA_WEAK_VALID);
    g_vtblGameOnly = base + RVA_VTBL_INPUT_GAMEONLY;
    g_npcShow = (NpcShowFn)(base + RVA_NPC_SHOW_INDICATOR);
    g_hudAdd = (HudAddFn)(base + RVA_HUD_ADD_INDICATOR);
    g_hudRemove = (HudRemoveFn)(base + RVA_HUD_REMOVE_INDICATOR);
    if (MH_Initialize() != MH_OK ||
        MH_CreateHook(base + RVA_SHOW_MENU, (void *)hook_show, (void **)&g_origShow) != MH_OK ||
        MH_CreateHook(base + RVA_PUSH_UI, (void *)hook_push, (void **)&g_origPush) != MH_OK ||
        MH_CreateHook(base + RVA_REMOVE_UI, (void *)hook_remove, (void **)&g_origRemove) != MH_OK ||
        MH_CreateHook(base + RVA_UPDATE_FOCUS, (void *)hook_update, (void **)&g_origUpdate) != MH_OK ||
        MH_CreateHook(base + RVA_HIDE_MENU, (void *)hook_hide_pc, (void **)&g_origHidePC) != MH_OK ||
        MH_CreateHook(base + RVA_NPC_INDICATOR, (void *)hook_npc_indicator, (void **)&g_origNpcIndicator) != MH_OK ||
        MH_CreateHook(base + RVA_STREAM_POINTS, (void *)hook_stream_points, (void **)&g_origPoints) != MH_OK ||
        MH_CreateHook(base + RVA_UI_STACK_PUSH, (void *)hook_stack_push, (void **)&g_origStackPush) != MH_OK ||
        MH_CreateHook(base + RVA_MAKE_ITEM_WIDGET, (void *)hook_make_item, (void **)&g_origMakeItem) != MH_OK ||
        MH_CreateHook(base + RVA_CREATE_WIDGET_WORLD, (void *)hook_create_widget, (void **)&g_origCreateW) != MH_OK ||
        MH_EnableHook(MH_ALL_HOOKS) != MH_OK) {
        log_line("MinHook failed, not hooking");
        return 0;
    }
    if (bytes_match(base, RVA_REGISTER_COMPONENT, EXPECT_REGCOMP, sizeof EXPECT_REGCOMP) &&
        bytes_match(base, RVA_RESET_BONE, EXPECT_RESETBONE, sizeof EXPECT_RESETBONE)) {
        g_registerComponent = (RegisterCompFn)(base + RVA_REGISTER_COMPONENT);
        if (MH_CreateHook(base + RVA_RESET_BONE, (void *)hook_reset_bone, (void **)&g_origResetBone) == MH_OK &&
            MH_EnableHook(base + RVA_RESET_BONE) == MH_OK)
            log_line("component registration hook on ResetBoneTransformByName ready");
        else
            log_line("could not hook ResetBoneTransformByName");
    } else
        log_line("RegisterComponent/ResetBoneTransformByName bytes differ: registration hook off");
    log_line("v14 hooked ShowPlayerMenuWithContext, PushUIInput, RemoveUIInput, UpdateUIFocus; ready");
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        HMODULE pinned;
        wchar_t *slash;
        DisableThreadLibraryCalls(self);
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                           (LPCWSTR)DllMain, &pinned);
        GetModuleFileNameW(self, g_dir, MAX_PATH);
        if ((slash = wcsrchr(g_dir, L'\\'))) *slash = 0; // drop main.dll
        if ((slash = wcsrchr(g_dir, L'\\'))) *slash = 0; // drop dlls
        // Hooking under the loader lock is unsafe; a short-lived thread does it.
        CreateThread(NULL, 0, install, NULL, 0, NULL);
    }
    return TRUE;
}
