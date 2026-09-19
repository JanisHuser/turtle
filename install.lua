-- Downloads the swarm code onto this computer/turtle.
-- Usage: install <base-url>
--   e.g. install https://raw.githubusercontent.com/<you>/<repo>/main/
-- The URL is remembered, so later updates are just: install

local FILES = {
  "config.lua",
  "startup.lua",
  "setup.lua",
  "install.lua",
  "miner.lua",
  "atm.lua",
  "ore.lua",
  "worker.lua",
  "home.lua",
  "fly.lua",
  "lib/state.lua",
  "lib/tools.lua",
  "lib/nav.lua",
  "lib/net.lua",
  "lib/inv.lua",
  "lib/dock.lua",
  "station/crafter.lua",
  "station/coordinator.lua",
}

local base = arg[1] or settings.get("swarm.url")
if not base then
  print("Usage: install <base-url>")
  return
end
if base:sub(-1) ~= "/" then base = base .. "/" end

for _, file in ipairs(FILES) do
  write(file .. " ... ")
  local res, err = http.get(base .. file .. "?t=" .. os.epoch("utc"))
  if not res then
    print("FAILED")
    error("install: " .. tostring(err))
  end
  local body = res.readAll()
  res.close()
  local h = fs.open("/" .. file, "w")
  h.write(body)
  h.close()
  print("ok")
end

settings.set("swarm.url", base)
settings.save()
print("Installed. First time? Run: setup <miner|worker|anchor|coordinator|gps|crafter>")
