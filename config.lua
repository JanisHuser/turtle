-- Shared configuration for every computer and turtle in the swarm.
-- Edit this once, then re-run the installer on each device.
--
-- Directions follow Minecraft: north = -Z, east = +X, south = +Z, west = -X.

return {
  -- Single turtle miner (miner.lua): pickaxe + geo scanner, no GPS needed.
  --
  --   top view, turtle facing "up" in this picture:
  --
  --              [ wall ]
  --     [PICKUP] [TURTLE] [ COAL ]     left = PICKUP, right = COAL/fuel
  --              [ shaft]              the shaft goes up + down behind the turtle
  --
  miner = {
    -- The turtle's home block (between PICKUP and COAL). `setup miner` asks
    -- which way it faces.
    home = { x = 39, y = -45, z = -1319 },

    -- Protected box around home: never dug into (except the corridor to the
    -- shaft and the shaft itself). Make it cover your base.
    protect = { radius = 8, below = 3, above = 5 },

    -- Y levels to mine at, in this order. Each scan covers +-scanRadius blocks.
    -- Prosperity ore: Y -60..24, evenly spread. Coal: only above Y 0.
    --   16  = coal + prosperity (Y 8..24)
    --  -45  = prosperity only (Y -53..-37), next to home, cheap to reach
    levels = { 16, -45 },
    scanRadius = 8,       -- 8 is free; larger radius costs fuel per scan
    cellSize = 16,        -- distance between scan points (2 * scanRadius)
    rings = 2,            -- scan points around the shaft: 2 rings = 5x5 = 80x80 blocks
                          -- keep the area inside your simulation distance!
    shaftDistance = 1,    -- how far behind home the shaft is; it goes straight
                          -- up AND down from there, so keep that column free
    minY = -58,           -- never go below this (bedrock)

    fuelTarget = 5000,    -- refuel up to this at home
    fuelReserve = 200,    -- extra on top of the distance home before turning back

    -- Blocks to mine when the scanner sees them.
    targets = {
      ["minecraft:coal_ore"] = true,
      ["minecraft:deepslate_coal_ore"] = true,
      ["mysticalagriculture:prosperity_ore"] = true,
      ["mysticalagriculture:deepslate_prosperity_ore"] = true,
    },
    -- Items to bring home (Lua patterns). Everything else is thrown away.
    keep = {
      "^minecraft:coal$",
      "^mysticalagriculture:prosperity_shard$",
    },
    -- Items that go into the COAL container (right). If it doesn't accept
    -- them (e.g. a drawer locked to coal blocks) they go into PICKUP instead.
    coal = {
      ["minecraft:coal"] = true,
    },
  },

  station = {
    -- The bay: the block a worker turtle occupies while unloading/refuelling.
    --   above the bay:            FUEL barrel   (coal blocks, filled by the crafter)
    --   below the bay:            PICKUP barrel (loot / shards for you)
    --   on the `bayFacing` side:  COAL barrel   (only if `coalItems` below is not empty)
    bay = { x = 0, y = 64, z = 0 },
    bayFacing = "east",

    -- Side of the bay turtles enter from / leave through. Both columns must be
    -- open air from bay height up to the top cruise layer.
    entry = "west",
    exit = "north",

    -- Turtles hover here (at their own cruise layer) while waiting for the bay
    -- and while idle. Must be open air at cruise height. Keep it a few blocks
    -- away from the entry/exit columns.
    park = { x = -6, z = -6 },

    -- No digging and no attacking within this horizontal distance of the bay
    -- (below cruise height). Protects your base and you.
    protectRadius = 16,
  },

  cruise = {
    -- Turtles travel horizontally at `base + (computer id % layers)`.
    -- `layers` should be >= the number of worker turtles so no two share a layer.
    -- `base` must be above everything you have built around the station.
    base = 120,
    layers = 16,
  },

  fuel = {
    target = 20000,     -- refuel up to this level at the station
    minToLeave = 2000,  -- leave the station if the fuel barrel is empty but we have this much
    reserve = 300,      -- extra fuel kept on top of the distance home
    -- Items a turtle may burn from its own inventory when running low.
    items = {
      ["minecraft:coal"] = true,
      ["minecraft:charcoal"] = true,
      ["minecraft:coal_block"] = true,
    },
  },

  -- Items delivered to a COAL barrel (on the `bayFacing` side) instead of PICKUP.
  -- Empty = everything goes into PICKUP and the ME system autocrafts coal blocks.
  -- Without ME: { ["minecraft:coal"] = true } plus station/crafter.lua.
  coalItems = {},

  tools = {
    -- The chunk controller stays equipped on the other side permanently.
    swapSide = "left",
    items = {
      pickaxe = { "minecraft:diamond_pickaxe", "minecraft:netherite_pickaxe" },
      modem = { "computercraft:wireless_modem_advanced" },
      scanner = { "advancedperipherals:geo_scanner" },
      chunky = { "advancedperipherals:chunk_controller" },
    },
  },

  -- Lua patterns of blocks turtles must never dig (they wait or path around).
  noDig = {
    "^computercraft:",
    "^advancedperipherals:",
    "^ae2:",
    "chest",
    "barrel",
    "drawer",
    "^functionalstorage:",
    "shulker_box",
    "spawner",
    "^minecraft:bedrock$",
  },
}
