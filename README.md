# 🛰️ Helix Protocol

> *Maintain the network. Fund the escape. Survive the pressure.*

**Helix Protocol** is a top-down 2D real-time management game built in **Godot 4**. Players maintain a data-pipe network aboard a deteriorating deep-space station, generating currency to fund rocket construction while hull pressure escalates toward catastrophic failure.

---

## 🎮 Gameplay Overview

You are the lone operator of a failing deep-space station. Your only chance at survival: keep the data-pipe network running long enough to build a rocket and escape.

- **Build** pipes and connect vents to hubs across four station zones
- **Manage** data packet flow to generate currency
- **Fund** rocket construction through five progressive segments
- **Survive** escalating hull pressure, fracture waves, and environmental hazards

A single run lasts approximately **35 minutes** — fast enough to stay tense, long enough to feel the weight of every decision.

---

## 🗺️ Zone Structure

The station is divided into four concentric zones, each unlocked through rocket progression:

| Zone | Unlock | Risk | Reward |
|------|--------|------|--------|
| **Core** | Available from start | Low | Low |
| **Inner** | Rocket Segment 1 | Low–Med | Med |
| **Outer** | Rocket Segment 2 | Med–High | High |
| **Frontier** | Rocket Segment 3 | Very High | Very High |

Zones aren't just map regions — they're a survival metaphor. Desperation drives you outward into increasingly volatile territory.

---

## ⚡ Special Tiles

Four dynamic environmental tile types spawn throughout the station, each requiring active routing decisions:

| Tile | Color | Effect |
|------|-------|--------|
| **Boost Corridor** | Cyan/Green | 1.5× data yield for active packets |
| **Pressure Sink** | Deep Blue | Reduces pressure rate by 10–25% (scales with traffic) |
| **Unstable Conduit** | Amber | High-yield routing — instantly destroyed by fracture waves |
| **Dead Zone** | Alert Red | Slows packets 20–40%; clearable by spending Data |

Tiles progress through a four-phase lifecycle — `PRE_SPAWN → ACTIVE → DECAYING → EXPIRED` — each with distinct visual and audio states. Glitch-in spawn animations, pulsing LED indicators, and escalating decay effects give you real-time feedback without breaking flow.

---

## 🚀 Rocket Progression

Purchasing each of the five rocket segments triggers persistent gameplay upgrades:

- **Segment 1** — Unlocks Inner Zone
- **Segment 2** — Unlocks Outer Zone + global vent interval multiplier
- **Segment 3** — Unlocks Frontier Zone + fracture wave warning system (11-second audio alert)
- **Segment 4** — Hub rate window expansion
- **Segment 5** — Escape. You win.

The rocket is always visible at the map's centre — every spending decision happens within sight of the thing you're either advancing or deferring.

---

## 🏗️ Technical Architecture

Built in **Godot 4 / GDScript** using a signal-bus architecture. No system holds a direct reference to another — all cross-system communication is mediated through signals or shared state in `GameData`.

### Core Systems

- **`GameData`** — Central state store. Owns the grid dictionaries, live `AStar2D` pathfinding instance, all economy variables, pressure modifiers, and full session serialisation.
- **`ResourceManager`** — All Data economy transactions route through here. Emits `resources_updated` after every change to keep the UI in sync.
- **`SignalBus`** — Pure signal declaration autoload. Defines every cross-system event (`pressure_updated`, `fracture_wave`, `rocket_segment_purchased`, `zone_unlocked`, etc.) with no logic of its own.
- **`Director`** — Runs the main game loop. Advances pressure each frame, manages fracture wave DFS chain-building, and controls the Special Tile objective spawning loop.

### Pressure Formula

```
increment = BASE_RATE × (1 + pressure_ratio²) × GameData.pressure_rate_multiplier
```

### Pathfinding

`GameData.get_clean_path()` temporarily disables foreign vent entrance cells before querying `AStar2D`, ensuring packets never accidentally route through another vent's driveway. The graph is never left in a dirty state.

### Performance Optimisations

- A* query caching with `has_point` guards before every `get_id_path` call
- Deferred child addition via `add_child.call_deferred()` to avoid mid-frame scene tree modification
- Atomic tile cleanup on expiry — clears both `GameData.special_tiles` entries and A* weight overrides simultaneously
- Spawn attempt throttling with exponential backoff (15–25s on failure, 60–180s on max failures)

---

## 🎨 Art & Audio

**Visual philosophy:** Every aesthetic decision must also be functional.

- Dark obsidian grey background maximises contrast for the animated data packet network
- Pressure gauge dominates the UI with colour-threshold markers at **70% (amber)** and **85% (red)**
- Zone boundaries communicated through spatial layout — no explicit borders
- Tile health states communicated through glitch shaders, pulsing LEDs, and decay animations

**Audio:** Music adapts dynamically to game state. Fracture waves are preceded by silence (via `MusicManager.stop_music()`) before resuming ambient score on resolution. Camera shake pairs with audio feedback at fracture onset and peak.

---

## 👥 Team

**Group 44**

- Jay Ravalani
- Mian Abdullah Zahid
- Joshin Aji
- Arshad Ahmed Abdul Jaffar Sadiq

---

## 🛠️ Built With

- [Godot 4](https://godotengine.org/) — Game engine
- GDScript — Primary scripting language

---

*Helix Protocol — Deliverable 3 Final Report*
