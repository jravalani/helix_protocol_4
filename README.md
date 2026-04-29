# Helix Protocol

**Helix Protocol** is a top-down 2D real-time management game developed in Godot 4. The player assumes the role of a lone operator aboard a deteriorating deep-space station, tasked with maintaining a data-pipe network to generate currency, fund the construction of an escape rocket, and survive escalating hull pressure before the station reaches catastrophic failure.

This repository contains the final prototype submitted for Deliverable 3 by Group 44.

---

## Table of Contents

- [Gameplay Overview](#gameplay-overview)
- [Zone Structure](#zone-structure)
- [Special Tiles](#special-tiles)
- [Rocket Progression](#rocket-progression)
- [Technical Architecture](#technical-architecture)
- [Art and Audio Design](#art-and-audio-design)
- [Team](#team)
- [Built With](#built-with)

---

## Gameplay Overview

The central loop of Helix Protocol asks players to balance three competing demands simultaneously: growing and maintaining a functional pipe network, managing the flow of data packets through that network to accumulate currency, and spending that currency on rocket construction before hull pressure reaches a terminal threshold.

A standard run lasts approximately 35 minutes, a deliberate reduction from the earlier 55–60 minute sessions documented in Deliverable 2. This change was made to improve player attentiveness and retention by ensuring the pressure escalation felt urgent throughout the session rather than only in the final stretch.

The game's three core interactions are:

- **Building** pipes and connecting vents to hubs across four station zones
- **Managing** data packet routing to generate income
- **Funding** rocket construction through five sequential upgrade segments

---

## Zone Structure

The station map is organised into four concentric zones. Zone access is gated behind rocket progression to prevent players from overextending into high-yield but structurally fragile territory before they have the infrastructure to support it.

| Zone | Unlocked At | Risk Level | Yield |
|------|-------------|------------|-------|
| Core | Start | Low | Low |
| Inner | Rocket Segment 1 | Low–Medium | Medium |
| Outer | Rocket Segment 2 | Medium–High | High |
| Frontier | Rocket Segment 3 | Very High | Very High |

The zone structure also functions as a piece of environmental storytelling. The safe, densely connected Core versus the sparse, volatile Frontier mirrors the survival theme of the game: as the station deteriorates, the player is pushed outward into increasingly dangerous decision-making territory.

---

## Special Tiles

The Special Tile system, introduced for the final build, is the most significant design addition since Deliverable 2. Four tile types spawn dynamically across the station map via a flood-fill algorithm that produces irregular, organically shaped patches rather than geometrically uniform regions. Each tile type is framed as a real station phenomenon rather than an abstract game-mechanical modifier.

| Tile | Colour | Mechanical Effect |
|------|--------|-------------------|
| Boost Corridor | Cyan/Green | 1.5× data yield for packets routed through the tile |
| Pressure Sink | Deep Blue | Reduces hull pressure rate by 10–25%, scaling with packet traffic volume |
| Unstable Conduit | Amber | Normal routing; immediately destroyed by fracture waves or adjacent pipe fractures |
| Dead Zone | Alert Red | Slows packets by 20–40%; can be cleared by spending Data at a cost that scales with tile size |

Each tile progresses through a four-stage lifecycle: `PRE_SPAWN`, `ACTIVE`, `DECAYING`, and `EXPIRED`. Players receive advance notice of incoming tiles via ghost outlines during the pre-spawn phase, and approaching expiry is communicated through accelerated glitch effects, jittered label positions, and a red countdown timer. The system was designed to ensure players can assess a tile's benefit or risk at a glance, before committing to a routing decision.

---

## Rocket Progression

The five-stage rocket construction sequence serves as the game's primary progression spine. Rather than functioning as a simple win-condition counter, each purchased segment triggers a suite of persistent gameplay upgrades applied through the Director's `apply_segment_effects()` function.

- **Segment 1** — Unlocks Inner Zone
- **Segment 2** — Unlocks Outer Zone; applies a global vent interval multiplier that benefits frontier vents proportionally more
- **Segment 3** — Unlocks Frontier Zone; activates the fracture wave warning system (11-second audio and notification alert ahead of each wave)
- **Segment 4** — Expands the hub rate window, increasing network throughput capacity
- **Segment 5** — Completes the rocket and ends the run

The rocket remains visible at the centre of the map throughout the session. Every resource expenditure decision is made within sight of the object the player is either advancing or deferring, a deliberate design choice intended to maintain emotional stakes across the full run.

---

## Technical Architecture

Helix Protocol is built in Godot 4 using GDScript. The codebase is structured around a small set of autoloaded globals, each owning a distinct responsibility, communicating exclusively through a central signal bus. No system holds a direct reference to another; all cross-system interaction is mediated through signals or through shared state in `GameData`. This separation made it possible to introduce the Special Tile system and the rocket upgrade chain during the final development sprint without modifying the core packet or vent scripts.

### Core Autoloads

**`GameData`** is the single source of truth for all persistent session state. It owns the grid dictionaries (`road_grid`, `building_grid`, `fractured_pipes`, `special_tiles`), the live `AStar2D` pathfinding instance, all economy variables, all pressure modifiers, and the full `ROCKET_UPGRADES` dictionary. Full session serialisation is handled through `serialize()` and `deserialize()`, making save and load deterministic. Zone classification is performed by `get_zone_for_cell()`, a single Euclidean distance function that maps cells to one of four `Zone` enum values (`CORE < 6`, `INNER < 11`, `OUTER < 14`, `FRONTIER >= 14`).

**`ResourceManager`** owns all Data economy transactions. No system writes to `GameData.total_data` directly; all spending and earning routes through `ResourceManager`, which emits `resources_updated` after every change to keep the UI synchronised. The pipe reward system lives here as well, issuing bonus pipe tiles at exponentially scaling thresholds to teach the mechanic early and require sustained performance later.

**`SignalBus`** is a pure signal declaration autoload with no logic of its own. It defines every cross-system event in the game as a typed signal. The architectural benefit is that the Director never requires a direct reference to the UI, the vent nodes, or the camera — it emits a signal and every interested system responds independently. Adding a new reactive system requires only a signal connection; existing systems remain untouched.

**`Director`** runs the main game loop in `_process()`. Each frame it advances pressure using the formula:

```
increment = BASE_RATE × (1 + pressure_ratio²) × GameData.pressure_rate_multiplier
```

Fracture waves are resolved through a depth-first search chain-building pass across `road_grid`, sorted by zone priority, with total fractures capped at 25% of all pipes. At least one pipe per fractured chain is always guaranteed to remain intact, preventing total network isolation from a single event.

### Pathfinding

`GameData.get_clean_path()` is the function every Packet calls to build its route. Before querying the `AStar2D` instance, it temporarily disables all foreign vent entrance cells, ensuring packets never route through another vent's driveway. The disable and re-enable cycle happens within a single function call, so the pathfinding graph is never left in an inconsistent state.

### Notable Performance Optimisations

- A* query caching with `has_point` guards before every `get_id_path` call, preventing queries against stale or destroyed node IDs
- Deferred child addition via `add_child.call_deferred()` to avoid modifying the scene tree mid-physics-frame
- Atomic tile cleanup on expiry, clearing both `GameData.special_tiles` entries and A* weight overrides simultaneously to prevent stale weight data from corrupting subsequent packet routing
- Capacity restoration on packet exit via `Packet._exit_tree()`, ensuring vents never permanently lose throughput capacity due to packets destroyed mid-flight by fracture events
- Spawn attempt throttling with exponential backoff (15–25 seconds on failure, 60–180 seconds on repeated failures) to prevent expensive full-map candidate scans from running every frame when the map approaches capacity

---

## Art and Audio Design

The visual identity of Helix Protocol is built around a single constraint: every aesthetic decision must also serve a functional purpose. The game takes place aboard a failing station, and the visual language is designed to communicate system state, urgency, and information hierarchy at a glance, without requiring players to consult numerical readouts.

The interface uses a dark obsidian grey background, chosen to maximise contrast for the animated data packet network. The pressure gauge is the dominant screen element, displayed with colour-threshold markers at 70% (amber) and 85% (red), thresholds introduced after playtesting revealed players were unprepared for late-game difficulty spikes. Zone boundaries are communicated implicitly through spatial layout rather than explicit borders, allowing players to internalise the map's structure through play.

Audio is treated as a pacing and emotional instrument rather than a decorative layer. Background music adapts dynamically to game state: the Director calls `MusicManager.stop_music()` with a fade duration ahead of fracture waves, creating silence that amplifies tension before the structural event. After the wave resolves, the ambient score resumes via `MusicManager.play_game_music()`, signalling a return to manageable conditions. Camera shake is emitted at wave onset and at the peak fracture moment, combining haptic and audio feedback into a unified escalation signal.

---

## Team

**Group 44**

- Jay Ravalani
- Mian Abdullah Zahid
- Joshin Aji
- Arshad Ahmed Abdul Jaffar Sadiq

---

## Built With

- [Godot 4](https://godotengine.org/) — Game engine
- GDScript — Primary scripting language
