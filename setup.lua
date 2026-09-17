-- Assign this device a role and check its hardware.
-- Usage: setup <miner|worker|anchor|coordinator|gps|crafter>

package.path = "/?.lua;/?/init.lua;" .. package.path

local role = arg[1]
local roles = { miner = true, worker = true, anchor = true, crafter = true, coordinator = true, gps = true }
if not roles[role] then
  print("Usage: setup <miner|worker|anchor|coordinator|gps|crafter>")
  return
end

local function ask(prompt)
  write(prompt)
  return read()
end

if role == "miner" then
  if not turtle then error("the miner must be a turtle") end
  local tools = require("lib.tools")
  local l, r = tools.equippedOn("left"), tools.equippedOn("right")
  if not peripheral.find("geoScanner") then error("setup: equip a geo scanner") end
  if l ~= "pickaxe" and r ~= "pickaxe" then error("setup: equip a diamond pickaxe") end
  print("Put the turtle in its home spot: PICKUP container on its left,")
  print("COAL container on its right. The shaft is dug up and down behind it.")
  local h = require("config").miner.home or {}
  local x, y, z = h.x, h.y, h.z
  if x and y and z then
    print(("Home from config.lua: %d %d %d"):format(x, y, z))
  else
    print("Enter the turtle's coordinates (look at it, F3 'Targeted Block').")
    x = tonumber(ask("x: "))
    y = tonumber(ask("y: "))
    z = tonumber(ask("z: "))
    if not (x and y and z) then error("setup: coordinates must be numbers") end
  end
  print("Which way does the turtle face? Stand behind it, look the same")
  print("way and read 'Facing' in F3.")
  local facing = ask("north/east/south/west: ")
  local headings = { north = true, east = true, south = true, west = true }
  if not headings[facing] then error("setup: facing must be north, east, south or west") end
  settings.set("swarm.home", { x = x, y = y, z = z, facing = facing })
  require("lib.state").clear("/.nav")
  require("lib.state").clear("/.miner")
  if not os.getComputerLabel() then os.setComputerLabel("miner") end
  if turtle.getFuelLevel() < 500 then
    print("Warning: fuel is " .. turtle.getFuelLevel() .. ". Put coal into the right container.")
  end

elseif role == "worker" then
  if not turtle then error("a worker must be a turtle") end
  local ok, err = require("lib.tools").setupWorker()
  if not ok then error("setup: " .. err) end
  if not os.getComputerLabel() then os.setComputerLabel("worker-" .. os.getComputerID()) end
  if turtle.getFuelLevel() < 500 then
    print("Warning: fuel is " .. turtle.getFuelLevel() .. ". Put some coal in and run 'refuel all' first.")
  end

elseif role == "anchor" then
  if not turtle then error("the anchor must be a turtle") end
  local tools = require("lib.tools")
  if tools.equippedOn("left") ~= "chunky" and tools.equippedOn("right") ~= "chunky" then
    local slot = tools.find("chunky")
    if not slot then error("setup: put an Advanced Peripherals chunk controller in the inventory") end
    turtle.select(slot)
    turtle.equipRight()
  end
  if not os.getComputerLabel() then os.setComputerLabel("anchor") end

elseif role == "crafter" then
  if not turtle then error("the crafter must be a turtle") end
  if not (turtle.craft or peripheral.find("workbench")) then
    error("setup: equip a crafting table on this turtle")
  end
  if not os.getComputerLabel() then os.setComputerLabel("crafter") end

elseif role == "coordinator" then
  if not peripheral.find("modem", function(_, m) return m.isWireless() end) then
    error("setup: attach an ender modem")
  end
  if not os.getComputerLabel() then os.setComputerLabel("coordinator") end

elseif role == "gps" then
  if not peripheral.find("modem", function(_, m) return m.isWireless() end) then
    error("setup: attach an ender modem")
  end
  print("Enter the coordinates of THIS computer (look at it and press F3).")
  local x = tonumber(ask("x: "))
  local y = tonumber(ask("y: "))
  local z = tonumber(ask("z: "))
  if not (x and y and z) then error("setup: coordinates must be numbers") end
  settings.set("swarm.gps", { x = x, y = y, z = z })
  if not os.getComputerLabel() then os.setComputerLabel("gps-" .. os.getComputerID()) end
end

settings.set("swarm.role", role)
settings.save()
print("Role set to '" .. role .. "'. Rebooting...")
sleep(1)
os.reboot()
