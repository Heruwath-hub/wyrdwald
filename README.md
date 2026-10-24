# Wyrdwald

Strategy survival RPG prototype. Godot 4.3+ (GL Compatibility renderer), GDScript.

Open the folder in the Godot project manager and run it. The boot scene (`scenes/main.tscn`) checks the content, then opens the main menu (`scenes/ui/main_menu.tscn`), from which the combat prototype is launched.

## Folder structure

| Folder | Purpose |
|---|---|
| `src/core/` | Shared enums, the `ContentDB` autoload, boot script |
| `src/data/` | Resource class definitions (`RaceData`, `ClassData`, `AttackData`, `TerrainData`, `BiomeData`, `ResourceNodeData`, `LocationData`) |
| `src/combat/` | Combat board, round flow, pattern resolution |
| `src/world/` | World generator, validator, pathing, party rules and the 3D map view |
| `src/strategic/` | Day/Night loop, AP, settlement, survival |
| `src/ui/` | Shared UI scripts |
| `content/` | Tunable `.tres` data, one file per entry, edited in the inspector |
| `scenes/` | `.tscn` scenes, mirroring `src/` |
| `assets/` | Art, audio, fonts; `assets/world/` holds the map art (see its README) |
| `docs/docs/` | Design bible, art guide, image prompts and implementation notes |
| `docs/media/` | Concept art, key art and biome images (reference only, not used by the game) |
| `tests/` | Headless checks for rules and content |

## Conventions

- **Data lives in `content/`.** Balance is changed in the inspector, never in code.
- **Content references use string ids.** `ClassData.attack_ids` and `ClassData.excelling_race_id` resolve through `ContentDB`.
- **`ContentDB.validate()`** returns every broken reference; the boot scene reports them as errors.
- **Enums live in `Enums`.** Lanes, attributes, patterns and board size constants are defined once.
- **Rules code takes plain data and returns plain results**, with no node dependencies, so combat resolution can be tested without a scene.

## Starter content

9 races with attribute weights, 9 classes (3 trunks × 3), and 29 attack cards (3 per class, plus a guard card each for Warrior and Smith). Attack `power` and `initiative` values are placeholders for tuning; higher initiative resolves earlier.

The Nocnica race is flagged `playable = false` until its role is decided.

## Combat prototype

Open `scenes/combat/combat_screen.tscn` and run the current scene (F6). The board fills the window; maximise it for the best view.

**Round flow**
1. Each side may play 7 cards per round, spread over its characters as it likes. A character can place up to 3 cards, each a different attack; every card after its first loses 6 initiative per card already placed, and the character then occupies several cells.
2. The sides place one card at a time, alternating. Who opens is random each round. Either side can pass to give up its remaining cards, and the other side then keeps placing.
3. On your turn click a character card in your hand at the bottom. Its attacks appear right above it. Pick an attack, then click a free slot in that character's lane (hover to preview). Hover enemy cards to see what they hit; your cards show `Threat -N` for the damage currently aimed at them.
4. When both sides are done, Resolve Round plays the cards one at a time in initiative order: the caster lights up, arrows show who is hit, numbers float up. Skip animation and Fast playback are available.

**Targeting.** Cards aim at the closest target when resolved, so earlier kills redirect later cards:

| Pattern | Hits |
|---|---|
| Single | Front card of the nearest occupied slot column (ties go to the lower slot) |
| Lane | Your lane type on the enemy side, or the nearest occupied lane |
| Column | The nearest occupied slot column, all three lanes |
| All | The whole enemy side |
| Pierce | Your own column in front of you, then the nearest enemy column through `Pierce enemy lanes` lanes. Ignores guards |

Ally attacks (Mend = Column, Soothing Rain = Lane, Lifebloom = All) use the same shapes on your side.

**Class identities.** Each class leans on a few patterns: Warrior (Single, Single+Delay, Guard, Lane), Reaver (Single, Column, All), Smith (heavy Single, Lane+Delay, Guard, Pierce), Hunter (Single, Single+Delay, Pierce), Rogue (fast Single, Column, Lane), Trickster (Single, Column, All, all with Delay), Witch (Single, Pierce, All), Druid (Single, Lane+Delay, Column), Healer (Column, Lane, All on allies).

**Guard and delay.** Guard cards (Shield Wall, Iron Ward) deal no damage. When they resolve they block a pool of damage aimed at the guardian's cell and every cell behind it in the same column until the round ends, so they need high initiative to be up before the heavy hits. Delay (Shield Bash, Dirty Trick, Entangle) pushes back the victim's remaining cards.

The side panel's Rules section holds the live settings: who places first, cards per round, max cards per character, extra-card penalty, friendly fire (off by default), cancel card if caster dies and pierce depth. Placement rules apply from the next round.

Teams live in `BattleSetup`. Code layout in `src/combat/`: `CombatRules` (toggles), `CombatBoard` and `CombatUnit` (state), `PlacedCard`, `PatternResolver` (slot + pattern to cells), `CombatEngine` (placement, step-by-step resolution), `SimpleAI`, `BattleSetup`, `combat_screen.gd` (UI built in code).

Damage is the attack's `power` value with no attribute scaling yet. Hit points are placeholders per lane in `BattleSetup`.

**The ground that remembers.** Every cell can hold one Ground tile under its card or entity: Oil, Grass, Fire, Water, Haze, Spike Pit, Tripwire, Snare, Flame Trap. Entities (Corpse, War Totem, Hex Totem, Warden, Spark) stand in a cell and block it for cards.

- **Lane choice.** Lane attacks (Sweeping Strike, Quake, Poison Cloud, Entangle, Soothing Rain) are pointed at a lane when placed, after the slot: click any cell of the lane you want. How deep a card reaches into the enemy side is a property of the card (`lane_reach`), not of its caster; melee cards have no reach and only touch the enemy front lane:

| Reach | Enemy lanes | Cards |
|---|---|---|
| 1 | Melee | Sweeping Strike, Quake, Stomp |
| 2 | Melee, Ranged | Poison Cloud, Spike Pit, Snare, Flame Trap, Tripwire, Disarm, Ember Throw, Oil Flask, Fog Pot |
| 3 | all | Entangle, Rain, Cleanse, Hex Totem |

  Cards aimed at your own side are never restricted. The Rules panel can switch the limit off (`restrict_lanes`).
- **Aimed cards.** Select a character, pick an aimed card, click your slot, then click the target cell. Esc or right-click steps back one stage. Hover any cell for ground, entity and trap details.
- **Placement traps** (Spike Pit, Tripwire, Snare) are one-shot and last 3 rounds. They spring the moment a card is placed on them. A trapped slot needs a second click to confirm.
- **Flame Trap** has a fuse of 2. It detonates at Upkeep unless cleared with Disarm, Cleanse or Rain, so you get one full round to answer it.
- **Answers.** Every removal card answers specific ground only:

| Ground | Answered by |
|---|---|
| Spike Pit | Stomp (Warrior) |
| Tripwire | Disarm (Rogue), fire (Ember Throw) |
| Snare | Disarm (Rogue), fire (Ember Throw) |
| Flame Trap | Disarm (Rogue), Rain (Druid) |
| Fire | Rain (Druid) |
| Oil | Rain (Druid), Cleanse (Healer) |
| Haze | Cleanse (Healer) |

  Rain leaves pits, cords and nets alone; fire leaves pits and Flame Traps alone.
- **Reactions.** Oil + Fire spreads fire over connected fuel; Fire + Water makes Haze (-3 initiative); Water washes oil and douses a Flame Trap; Fire burns away a Tripwire or Snare. Burning cells are marked "burns at Upkeep".
- **Upkeep** runs after Resolution: fuses tick, fire spreads and burns, Sparks act, ground and entities expire, corpses decay.
- **Totems** change power by 20% on neighbouring cells. Familiars (Warden, Spark) vanish with their owner.
- **Biome** (Rules panel): Random, Bare, Plains (Grass) or Wetlands (Water).

## World prototype

Open `scenes/world/world_map.tscn` and run the current scene (F6). It generates a continent from a seed and lets a party walk over it.

- **Seed.** A new random world every run. Type a number or any text into the Seed box and press New World to get the same world again. The generator version is shown beside the seed; a seed only means the same world for the same version.
- **Controls.** Right click walks the party along the cheapest route as far as today's AP allows (hover shows the route: green steps are affordable today, amber ones are not). Left click an NPC settlement to select it: its 2-ring access area is shaded and the panel lists the food, water and materials inside. Hold Shift to preview a settlement at the hovered hex (see Build sites below). Left drag turns the camera, middle drag or WASD pans, wheel zooms, Q/E rotate, Space ends the day.
- **Colours and models.** A tile's colour is its biome (see the legend); the model standing on it is its terrain: trees for forest, mounds for hills, peaks for mountains, reeds or tufts for marsh or grass where those are not the biome's plain terrain (`BiomeData.plain_terrain`: grass in Plainlands, marsh in Wetlands). Rivers, lakes and the sea keep their water colours. All of it is placeholder art.
- **Top bar.** Seed, New World, Randomize Seed (random seed, generates at once), start biome (any but Wyrdwood), season, weather (Auto or forced), overlay (terrain, biome, danger floor, AP cost, build sites) and End Day. Changing the start biome or season restarts the party.
- **Build sites.** The overlay colours every hex where a player settlement could stand: red to yellow to green by how much it reaches, dark where it cannot. A site needs a walkable non-river hex at least 3 hexes from an NPC settlement and, within 2 rings, a food source and a material that no NPC settlement reaches (nodes inside an NPC settlement's 2 rings are contested and do not count). Fresh water (each river hex in reach, plus springs as markers) is a food resource of kind "fresh water", valuable but not required. Score = the sum over resource kinds of weight x (1 + 0.4 x 2 x (1 - 0.5^(slots-1))), so the first slot of a kind carries the value, each further slot adds half as much as the one before, and variety wins; weights are the tier (1-3) for food and materials alike. Food variety (morale) adds 0.5 per unit of food-kind weight beyond the first, with no cap, so a tier 2 kind counts double and a tier 3 kind triple. Every site shows its value as a number on the hex. The colour scale runs from the world's 10th to its 90th percentile of sites. Holding Shift shows the NPC settlements' reach in blue and the reach of the hovered hex in yellow (orange where an NPC settlement reaches the same hex), and the hover panel gives the site verdict, the free slots and kinds, and what is shared.
- **Hover panel.** Terrain, biome, danger range, node, location, settlement, the route cost, and which nodes a camp (1 ring) or a settlement (2 rings) standing there would reach.

**Rules**

| Topic | Rule |
|---|---|
| Biomes | Plainlands (tier 1), Woodlands, Highlands, Wetlands (tier 2), Wyrdwood (tier 3). Wyrdwood can sit anywhere but never touches Plainlands; Plainlands and Wyrdwood each touch at least one tier 2 biome. Borders are clear-cut: every hex belongs to exactly one biome, each biome is one connected region and there are no transitional zones |
| Continent | One landmass, ringed by sea tiles. Each seed picks its own outline inside a rectangle of random proportions (wide, tall or square), plus a skeleton of lobes and arms, ruggedness, bays and peninsulas. The land has about 1,800 hexes and never runs straight along one hex axis for more than 6 hexes. Biomes get extra seeds and strong warping, so they grow arms and lobes |
| Terrain | One terrain per hex. Rivers are hexes. Grass 1 AP; hills, forest, marsh, river, twisted forest 2 AP; mountains, lakes and sea cannot be entered |
| Mountains | Appear in every biome, densest in Highlands, and form chains along ridges with hills beside them. A chain that cuts off land is opened with a pass; every pair of neighbouring biomes keeps at least two walkable crossings |
| AP per day | Spring, summer and autumn 4, winter 3, minus the day's weather (clear 0, rain 1, storm 2, snow 1), never below 1. Weather is rolled per seed, day and season (snow only in winter) and can be forced in the top bar. Entering a hex costs its terrain's AP; the party stops before a step it cannot pay |
| Nodes | Resources are scarce (about 15% of the land holds a node); further nodes are meant to be unlocked through events, quests and decisions. Never used up. At most one per hex, mountains can hold them. Each biome has a budget per 100 walkable hexes for tier 1 food, tier 1 materials and its own tier 2/3 materials (`BiomeData`); its tier 2/3 food (placeholder nodes `tier2_food_<biome>`, `tier3_food_wyrdwood`) gets half the tier 2/3 material budget on top (`signature_food_share`), split between kinds by node weight, and each node goes where it is furthest from other nodes, so resources spread evenly without hotspots. Tier 2 appears only in its own biome, tier 3 only in Wyrdwood. Camps reach 1 ring, settlements 2 rings |
| Lakes | Never touch the coast. A lake has one outflow river; rivers that flow in leave at least 1 hex between their last hex and the outflow's first hex, and no other river touches it |
| Fresh water | A river hex or a spring. A spring is always a river hex at the head of a river, at least 3 hexes from the coast. A river that starts at a lake has no spring. Rivers are at least 2 hexes long and no river hex touches more than 2 other river hexes (no confluences, no parallel runs). Lakes and marsh are not drinkable. It counts as one food slot (kind "fresh water") in any reach and feeds crafting variety. Fish live only in rivers, lakes and the sea within 2 hexes of the shore; most of it is sea fish, on water hexes outside the land, and counts towards reach |
| NPC settlements | Two per race, placed in the race's native biome (none in Wyrdwood), at least 7 hexes apart, at least 2 hexes from another biome and at least 3 hexes from the sea (inland sites are preferred), each with the same reach inside 2 rings: 2-3 food slots (tier 1 food nodes, fresh water as one slot), 2-3 material nodes (at least one tier 1 and, where the biome has one, a tier 2). Settlements are not tied to water. Surplus nodes are removed and missing ones added, so no settlement is rich or poor by luck. The base world stores only each settlement's race |
| Locations | Pre-placed, one per hex at most, sit at their biome's danger floor |
| Starts | Every biome but Wyrdwood has a start with at least 2 food slots (fresh water counts) within 8 AP and an NPC settlement within 4-16 AP |
| Crossing | A biome takes about a week at 4 AP (28 AP target) to cross; the check accepts 18-46 AP |

A world that breaks a rule is rebuilt with the next attempt number, up to 24 times; the same seed always ends on the same attempt. Nothing is reserved in the base world, so runtime events can still add locations, grow settlements and spawn nodes.

**Generator stages** (`WorldGenerator`, each with its own sub-seed): land, elevation, biomes (weighted regions with topology checks), hydrology (rivers and lakes), terrain, connectivity repair, nodes, settlements, starts, locations. `WorldValidator` checks the result. The generator uses its own hashing and noise (`WorldHash`, `WorldNoise`, `WorldRng`) instead of Godot's, so a seed gives the same world on every platform.

**Tuning.** Terrain mix, danger bands, settlements per race and the biome shares are in `content/biomes/`, node weights in `content/nodes/`, resource budgets per biome in `content/biomes/`, location densities in `content/locations/`, map size and the start rules in `WorldParams`. `tests/sim_worldgen.gd` generates many worlds and prints terrain shares, node and location counts and crossing times:

```
godot --headless --path . --script tests/sim_worldgen.gd -- 1 40 q
```

**Art.** `assets/world/` has one folder per terrain, prop, node, location, settlement and the party, named by content id. Drop models in and they are used; empty folders show placeholders. Every file in a folder is a variant picked by seed and hex; tiles are rotated in 60 degree steps. See `assets/world/README.md` for the model rules. `tests/shot_world.gd` renders screenshots under xvfb.

## Difficulty

The Rules panel's Difficulty applies from the next battle and also serves as progression.

| Tier | Your party | Enemies | Skills |
|---|---|---|---|
| Easy | Warrior, Hunter, Healer, Witch | Reaver, Trickster, Druid | 3–4 per character; traps: Spike Pit, Flame Trap |
| Normal | Warrior, Hunter, Rogue, Healer, Witch | Reaver, Trickster, Druid, Rogue | 4 per character |
| Hard | the same five | Normal plus a Witch | every skill |

Each tier also sets forgiveness levers (`BattleSetup.TIERS`):

| Tier | Enemy cards per round | Enemy initiative shift | Enemy reads your placed cards | Fallen casters' cards still resolve |
|---|---|---|---|---|
| Easy | 6 | -2 (their cards resolve later in the round) | 70% of turns | yes |
| Normal | all | -1 (later) | 85% | yes |
| Hard | all | 0 | always | no |

When the enemy does not read your cards it plays blind, choosing by its own board only.

The lists live in `BattleSetup.TIERS`. `tests/sim_difficulty.gd` (`DIFF=100`, `TIERS=1`) plays each tier with a competent player and with players who make random mistakes, and follows the Healer.

## AI behaviour report

```
BATTLES=200 godot --headless --path . --script tests/sim_ai_behaviour.gd
```

Plays the AI against itself and prints trap avoidance, bomb answers, totem use and a set of controlled situations. `tests/sim_herding.gd` (`HERD=100`) walls off slot columns with traps and measures where the squad stands and what a Pierce or fire follow-up does; `tests/sim_compare.gd` and `tests/sim_quick.gd` are shorter variants; `tests/ui_smoke.tscn` drives the real UI under xvfb.

## Tests

```
godot --headless --path . --script tests/run_tests.gd
```

Open the project in the editor once first so the script classes are registered. The script prints the check count and exits non-zero on any failure.

`tests/sim_balance.gd` plays battles (greedy or random player against the AI, with 3 to 5 enemies, enemy first or blind) and prints win rates. It takes about ten seconds.
