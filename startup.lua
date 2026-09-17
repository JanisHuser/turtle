-- Runs on every boot and starts the program for this device's role.
-- Set the role with: setup <role>

local role = settings.get("swarm.role")

if role == "miner" then
  shell.run("/miner.lua")
elseif role == "worker" then
  shell.run("/worker.lua")
elseif role == "crafter" then
  shell.run("/station/crafter.lua")
elseif role == "anchor" then
  -- Only here to keep the station chunk loaded with its chunk controller.
  print("Anchor: keeping the station chunk loaded.")
  while true do sleep(3600) end
elseif role == "coordinator" then
  shell.run("/station/coordinator.lua")
elseif role == "gps" then
  local p = settings.get("swarm.gps")
  shell.run("gps", "host", p.x, p.y, p.z)
else
  print("No role set. Run: setup <miner|worker|anchor|coordinator|gps|crafter>")
end
