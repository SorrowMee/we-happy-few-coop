# We Happy Few: local split-screen co-op

Two players on one PC, each with a gamepad and half of the screen, in the regular campaign and the
sandbox. Built on [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (a Lua mod) plus a small native helper DLL.

> **Português:** co-op local em tela dividida para We Happy Few, dois controles no mesmo PC.
> Instalação e problemas conhecidos abaixo (em inglês).

**Status:** playable, tested by hand by the author (two gamepads, sandbox and story). No automated tests.

## What works

- Player 2 joins automatically (gamepad 2) a few seconds after player 1 has a character; leaves on the main menu.
- Each player has their own HUD, loot screen and player menus (inventory, skills, crafting, map, journal) in
  their half of the screen. Menus are laid out at half size and keep gamepad navigation; opening one does not
  pause the game for the other player. Each inventory belongs to its own player.
- NPC suspicion/hostility indicators for player 2.
- The other player is drawn as full-body Arthur, animated (idle, walk, run, jump, fall, crouch, downed). The game
  has no locomotion animations for Arthur's skeleton, so his model is posed every frame from a hidden animated
  citizen body (runtime retarget).
- World streaming, NPC spawning and nav mesh follow both players (streaming centred between them).
- Cutscenes: one full screen view, then the other player is brought back.
- Downed / revive instead of dying: a player at 0 HP goes down; the other holds **X** next to them to revive.
- Keep-together and rescue: game teleports (ladders, hatches, fast travel) bring the other player along; a player
  falling out of the world is put back next to the partner. New positions prefer spots the partner recently stood
  on (breadcrumbs) and are verified; a bad spot is retried.
- **Unstuck:** hold **Select / View** for 2 s to teleport next to the other player (both players).
- Player 2's inventory is saved: the game only saves player 1, so the mod keeps player 2's items (bag, holster,
  clothes), their durability and currency in `Mods\SplitScreenCoop\p2_inventory_<map>.txt` and gives them back when
  player 2 joins. Worn clothes come back in the bag and quickslots are not restored. One file per map: all save
  slots on the same map share it.

## Known issues

- Some lights occasionally flicker on player 2's half (cause not found yet).
- The game froze a few times right after player 2 joined. The cause found was the `-log` console window blocking
  the game thread; **do not use the `-log` launch option**. Not verified over a long session.
- Untested: both players down at once (game over), DLC maps, a full campaign playthrough.
- Player 2 once stopped responding to input (not reproduced).

## Requirements

- We Happy Few on Steam, **build 4660512** (`GlimpseGame.exe` SHA-256
  `51CF287329BC4516CE696FF5A77DC563A9B66E2909AEFD95C94541070DD4F46E`). The DLL patches fixed addresses of this exe
  and checks the bytes before hooking; on another build those features turn themselves off.
- [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip)
  (SHA-256 `4B47D4BCEDDD2F561A4E395BFA00924CCFC945AF576A2D0C613E6537846C57EC`).
- Two gamepads (gamepad 1 = player 1, gamepad 2 = player 2).
- To build the DLL: Visual Studio 2022 Build Tools with the C++ workload.

## Install

Back up your saves first (`%USERPROFILE%\Documents\My Games\We Happy Few\SaveGames`).

**Easiest:** download `we-happy-few-coop-vX.Y.Z.zip` from [Releases](https://github.com/SorrowMee/we-happy-few-coop/releases)
(helper DLL included), extract UE4SS v3.0.1 into `<game dir>\GlimpseGame\Binaries\Win64`, then extract the zip into
the same folder and let it replace `Mods\mods.txt`. Start the game normally (no `-log`).

**From source:**

1. Extract UE4SS v3.0.1 into `<game dir>\GlimpseGame\Binaries\Win64`.
2. Build the helper DLL: run `src\coop_menufix\build.cmd`. It writes `mod\Mods\CoopMenuFix\dlls\main.dll`.
3. Copy the folders in `mod\Mods\` (`SplitScreenCoop`, `CoopMenuFix`) into `<game dir>\GlimpseGame\Binaries\Win64\Mods\`.
4. In that folder's `mods.txt`, add `SplitScreenCoop : 1` and `CoopMenuFix : 1`, and keep `Keybinds`,
   `ConsoleEnablerMod` and `ConsoleCommandsMod` at `0` (they conflicted). UE4SS 3.0.1 loads `dlls\main.dll` even
   when a mod is set to 0; rename the DLL to disable it.
5. Start the game normally (no `-log`), load a save with gamepad 1, then use gamepad 2.

Logs: `UE4SS.log` next to the exe (lines tagged `[SplitScreenCoop]`) and `Mods\CoopMenuFix\menufix.log`.

## How it works

- `mod/Mods/SplitScreenCoop/Scripts/main.lua`: the co-op logic (second local player, HUD and menu layout per half,
  bodies, cutscenes, downed/revive, streaming radii, safe teleports). It runs from Blueprint ticks on the game
  thread.
- `mod/Mods/SplitScreenCoop/Scripts/arthur_retarget.lua`: per-bone retarget from the citizen skeleton to Arthur's.
- `src/coop_menufix/coop_menufix.c` (DLL, MinHook): fixes in native code Lua cannot reach. It routes menus, UI focus
  and inventory item widgets to the right player and keeps player menus from pausing the game. It gives player 2
  NPC indicators and centres world streaming between the players. It also loads assets the map has not loaded
  (Arthur's model) and registers components created from Lua.
- `docs/NOTES.md`: the full reverse-engineering and test log (addresses, what failed, why).
- `dev/CoopBridge`: development-only UE4SS mod that runs a Lua file on request. Not needed to play; do not install
  it for normal use.

No game files are included.

## License

MIT, see [LICENSE](LICENSE). MinHook (`third_party/minhook-1.3.4`) is BSD-2-Clause, see its `LICENSE.txt`.
