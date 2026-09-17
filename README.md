# Turtle Swarm (ATM10, CC: Tweaked + Advanced Peripherals)

Turtles that mine coal and prosperity shards (and later loot chests) and bring
everything home.

- **Start here: `miner.lua`**, one turtle with a pickaxe + geo scanner. No GPS,
  modem or chunk loader needed.
- Later: the swarm (`worker.lua` + station), see further below.

## Single miner (start here)

### What it does

1. Starts at home, refuels from the COAL container on its right.
2. Uses the shaft behind home to go to each mining level (`miner.levels`).
3. On each level it visits a grid of scan points (5x5 by default, 16 blocks
   apart) and scans radius 8 with the geo scanner.
4. Mines every coal / prosperity ore it found, throws away stone and other junk.
5. Goes home when the inventory is full, fuel is getting low, or the area is
   done: coal into the right container, shards into the left one.
6. Continues with the next scan point. When all levels are done it stops at
   home (`miner reset` to start over).

It never digs inside the protected box around home (`miner.protect`, default
8 blocks sideways, 3 down, 5 up), except the one-block corridor behind the
turtle and the shaft column. It never breaks chests, barrels, drawers,
computers, turtles, spawners or bedrock.

### Layout

Top view, turtle looking north (any direction works):

```
          [ wall ]
[PICKUP]  [TURTLE]  [ COAL ]
          [ shaft]   <- the turtle digs straight up and down here
```

- **COAL** (right): coal or coal blocks for fuel. Mined coal goes in here too.
  If it refuses raw coal (drawer locked to coal blocks), coal goes to PICKUP.
- **PICKUP** (left): prosperity shards (import bus into ME if you like).
- **Shaft column**: behind the turtle, straight up to Y 16 and down to the
  lowest level. Nothing you care about should be in that column, and it
  leaves an open 1x1 hole in the floor behind the turtle: don't fall in
  (or increase `shaftDistance`).

Home is set in `config.lua`: `miner.home = { x = 39, y = -45, z = -1319 }`.

### Levels

Prosperity ore spawns evenly from Y -60 to 24; coal only above Y 0.
Default `levels = { 16, -45 }`:
- **Y 16**: coal + prosperity (scans Y 8..24)
- **Y -45**: prosperity only (scans Y -53..-37), right next to home

Add `32` for more coal (no prosperity there).

### Setup

1. Put ~16 coal (or a few coal blocks) into the COAL container.
2. Install the code on the turtle (see "Getting the code onto the server").
3. Run `setup miner`, then answer which way the turtle faces (stand behind it,
   look the same way, read "Facing" in F3). It reboots and starts mining.

### While it runs

- It only works while its chunks are loaded: stay nearby, within the server's
  simulation distance. With `rings = 2` it goes at most ~40 blocks from the shaft.
- If you leave or the server restarts, it continues where it stopped once the
  chunk is loaded again.
- `Ctrl+T` stops it; `miner` starts it again; `miner reset` forgets progress.
- If you pick the turtle up, run `setup miner` again after placing it back home.

---

# Swarm (later)

Worker turtles that go out to mine and loot, then come back to one station to
unload and refuel.

## What is done

| Part | File | Status |
|---|---|---|
| Single miner (coal + prosperity) | `miner.lua` | done |
| Persistent state, survives server restarts | `lib/state.lua`, `lib/nav.lua` | done |
| GPS navigation, cruise layers, protected zone | `lib/nav.lua` | done |
| Tool swapping (pickaxe / ender modem / geo scanner) | `lib/tools.lua` | done |
| Docking: queue, unload, refuel, park | `lib/dock.lua` | done |
| Coal to coal block crafter (only needed without ME) | `station/crafter.lua` | done |
| Coordinator (status screen + bay queue) | `station/coordinator.lua` | done |
| Swarm mining job | - | later |
| Chest looting job | - | later |

## Hardware per device

- **Worker** (one per turtle): advanced turtle, diamond pickaxe, ender modem,
  Advanced Peripherals **chunk controller**. The chunk controller stays
  equipped; pickaxe and modem swap automatically on the other side.
- **Anchor**: any turtle with a **chunk controller**, parked at the station.
  It keeps the station chunk (ME, power, GPS, coordinator) loaded.
  (Or force-load the chunk with FTB Chunks and skip it.)
- **Coordinator**: advanced computer, ender modem, optional advanced monitor.
- **GPS tower**: 4 computers, each with an ender modem.
- FUEL and PICKUP storage: barrels, or drawers (e.g. an oak drawer for FUEL,
  which holds far more coal blocks than a barrel). Avoid chests, they can
  merge into double chests.
- Your ME system: import bus, export bus + crafting card, molecular assembler
  with a coal block pattern.

## Station layout

Build everything (station, ME, power, GPS computers, coordinator, anchor)
**inside one chunk** (F3+G shows chunk borders), because a chunk controller
only loads its own chunk.

Side view:

```
 y+1  [FUEL  ] <- export bus: coal blocks (crafting card, autocrafts from coal)
 y    [ BAY  ]    empty block, workers stop here
 y-1  [PICKUP] <- import bus: everything the turtles bring, including coal
```

- **Entry column**: the block on the `entry` side of BAY (default west) and
  everything above it up to the highest cruise layer
  (`cruise.base + cruise.layers`) must be air.
- **Exit column**: the same for the `exit` side (default north).
- **Park column** (`station.park`): air at cruise height. Idle and queued
  turtles hover there, each at its own height.
- If ME is full or unpowered, PICKUP fills up and turtles wait in the bay
  ("PICKUP barrel is full") instead of dropping items anywhere.
- If ME runs out of coal, FUEL stays empty; a turtle with at least
  `fuel.minToLeave` leaves anyway, otherwise it waits.
- **Mystical Agriculture coal**: send the farm's coal into ME as well.

Without ME: set `coalItems = { ["minecraft:coal"] = true }`, put a COAL barrel
on the `bayFacing` side and use `station/crafter.lua` (turtle with crafting
table + chunk controller above COAL, facing FUEL) instead.

Write the BAY coordinates into `config.lua` (`station.bay`) and check
`park`, `cruise.base` (must be above your base) and `protectRadius`.

## Getting the code onto the server

Turtles download the files over HTTP. The easiest host is a public GitHub repo:

1. Push this repo to GitHub (github.com/JanisHuser/turtle, must be public).
2. On every computer/turtle, run:

```
wget https://raw.githubusercontent.com/JanisHuser/turtle/main/install.lua install
install https://raw.githubusercontent.com/JanisHuser/turtle/main/
```

After changing code or `config.lua`, push, then run `install` on each device
(it remembers the URL). Edit `config.lua` in the repo, not on the turtle,
because installing overwrites it.

## Setup order

1. **GPS tower**: 4 computers with ender modems, spread out inside the chunk
   and at **different heights** (not all in one flat plane). On each one:
   `setup gps` and enter that computer's coordinates.
   Test with a turtle: `gps locate`.
2. **Coordinator**: `setup coordinator`.
3. **Anchor**: `setup anchor` on the station turtle. Check that ME autocrafts
   coal blocks into FUEL when you put coal into PICKUP.
4. **Workers**: put the chunk controller, diamond pickaxe, ender modem and some
   coal into the turtle, run `refuel all`, then `setup worker`. The turtle
   equips the chunk controller, finds its heading via GPS, flies home, docks and parks.

## Useful commands on a worker

- `home`: fly home, unload, refuel, park (stop the running program with Ctrl+T first)
- `fly <x> <y> <z>`: test flight
- Delete `/.nav` if a turtle got picked up and placed somewhere else (it will re-locate with GPS).

## Rules the turtles follow

- They travel at `cruise.base + (id % cruise.layers)`, so every turtle has its
  own height. Keep `layers` at least as large as the number of workers.
- Inside `protectRadius` of the bay (below cruise height) they **never dig and
  never attack**. They wait, or hop up to get around something.
- They never dig blocks matching `noDig` (chests, barrels, computers, turtles,
  spawners, bedrock).
- **Outside** the protected zone they dig through whatever is in the way at
  cruise height, including other players' builds. Pick a `cruise.base` above
  anything you care about.
- Only one turtle at a time is let into the bay. If the coordinator is offline
  they dock without the queue and simply wait for each other.

## Tested

The logic was tested in a simulated turtle world (not in Minecraft): the
miner in two layouts (home at the surface, home deep underground with levels
above and below it), interrupted at every single move; a full dock round trip, a crash (server stop) at every move of the trip with and
without GPS afterwards, and the (optional) crafter recipe. The first test in real ATM10
should be one worker with `home` and `fly`.
