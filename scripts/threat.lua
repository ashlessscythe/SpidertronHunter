--- Threat awareness: skip nests a hunter is unlikely to beat.
--- Danger is the sum of "points" for worms/turrets and spawners near a candidate target; capacity
--- is the hunter's current hull + shield health. Judgements are remembered per spider for a while
--- so the scanner does not search the area again every scan.
local alerts = require("scripts.alerts")
local settings_mod = require("scripts.settings")

local M = {}

--- Radius around a candidate target that is assessed together (worms outrange most things).
M.ASSESS_RADIUS = 40
--- How long a "too dangerous" verdict is remembered.
M.AVOID_TICKS = 3600
--- How long a "fine to attack" verdict is remembered (so a hunter fighting its way in is not re-judged).
M.SAFE_TICKS = 600
--- Health points of capacity per danger point (a 3000 hp spidertron ~ 100 points at "normal").
--- Calibrated from the multi-nest scenario: a nest scoring 19 cost a full-health hunter ~250 hp.
M.HEALTH_PER_POINT = 30

local MODE_MULTIPLIER = { normal = 1.0, cautious = 0.5 }

--- Ordered so longer tier names are matched before shorter ones that could be substrings.
local WORM_POINTS = {
  { "behemoth", 30 },
  { "big", 12 },
  { "medium", 6 },
  { "small", 3 },
}
local UNKNOWN_TURRET_POINTS = 6
local SPAWNER_POINTS = 1

--- @param name string
--- @param entity_type string
--- @return number
function M.points(name, entity_type)
  if entity_type == "unit-spawner" then
    return SPAWNER_POINTS
  end
  if entity_type == "turret" then
    for i = 1, #WORM_POINTS do
      if name:find(WORM_POINTS[i][1] .. "-worm", 1, true) then
        return WORM_POINTS[i][2]
      end
    end
    return UNKNOWN_TURRET_POINTS
  end
  return 0
end

--- @param entities {name: string, type: string, valid: boolean?}[]
--- @return number
function M.danger(entities)
  local total = 0
  for i = 1, #entities do
    local e = entities[i]
    if e.valid ~= false then
      total = total + M.points(e.name, e.type)
    end
  end
  return total
end

--- Current hull + shield health, in danger points, scaled by the awareness mode.
--- @param spidertron LuaEntity
--- @param mode string
--- @return number? capacity  nil when awareness is off
function M.capacity(spidertron, mode)
  local multiplier = MODE_MULTIPLIER[mode]
  if not multiplier then
    return nil
  end
  local hp = spidertron.health or 0
  local grid = spidertron.grid
  if grid then
    for _, eq in pairs(grid.equipment) do
      hp = hp + (eq.shield or 0)
    end
  end
  return hp / M.HEALTH_PER_POINT * multiplier
end

--- Previously judged zone covering `pos`, or nil. Expired zones are dropped.
--- @param ai table
--- @param pos MapPosition
--- @param tick integer
--- @return "avoid"|"safe"|nil
function M.remembered_verdict(ai, pos, tick)
  local zones = ai.threat_zones
  if not zones then
    return nil
  end
  local verdict = nil
  local kept = {}
  for i = 1, #zones do
    local z = zones[i]
    if z.expires > tick then
      kept[#kept + 1] = z
      local dx, dy = pos.x - z.x, pos.y - z.y
      if dx * dx + dy * dy <= z.radius * z.radius then
        -- "avoid" wins over "safe" if both cover the point.
        if z.verdict == "avoid" or not verdict then
          verdict = z.verdict
        end
      end
    end
  end
  ai.threat_zones = kept
  return verdict
end

--- @param ai table
--- @param pos MapPosition
--- @param verdict "avoid"|"safe"
--- @param tick integer
local function remember(ai, pos, verdict, tick)
  ai.threat_zones = ai.threat_zones or {}
  local zones = ai.threat_zones
  zones[#zones + 1] = {
    x = pos.x,
    y = pos.y,
    radius = M.ASSESS_RADIUS,
    verdict = verdict,
    expires = tick + (verdict == "avoid" and M.AVOID_TICKS or M.SAFE_TICKS),
  }
  -- Bound memory: keep the newest few.
  while #zones > 16 do
    table.remove(zones, 1)
  end
end

--- Is it acceptable for this hunter to go after a target at `pos`?
--- @param ai table
--- @param spidertron LuaEntity
--- @param pos MapPosition
--- @return boolean
function M.judge(ai, spidertron, pos)
  local mode = settings_mod.get().threat_awareness
  if not MODE_MULTIPLIER[mode] or ai.role == "scout" then
    return true
  end
  local tick = game.tick
  local known = M.remembered_verdict(ai, pos, tick)
  if known then
    return known == "safe"
  end

  local found = spidertron.surface.find_entities_filtered({
    position = pos,
    radius = M.ASSESS_RADIUS,
    force = "enemy",
    type = { "turret", "unit-spawner" },
  })
  local danger = M.danger(found)
  local capacity = M.capacity(spidertron, mode)
  if capacity and danger > capacity then
    remember(ai, pos, "avoid", tick)
    alerts.notify(spidertron, "too-dangerous", ai, string.format("%d", danger))
    return false
  end
  remember(ai, pos, "safe", tick)
  return true
end

return M
