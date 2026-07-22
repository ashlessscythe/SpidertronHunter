--- Combat spacing: preferred range, acid avoidance, strafe/circle/flank.
--- Uses short direct autopilot hops (not follow_target) so hunters do not walk into puddles.
local util = require("scripts.util")
local settings_mod = require("scripts.settings")

local M = {}

local ACID_PROBE_RADIUS = 6
local CANDIDATE_TRIES = 6

--- Factorio Lua: prefer math.atan2 when present, else two-arg math.atan.
local function atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end
  return math.atan(y, x)
end

--- @param entity LuaEntity
--- @return boolean
local function is_acid_fire(entity)
  return entity.valid and entity.type == "fire" and string.find(entity.name, "acid", 1, true) ~= nil
end

--- @param surface LuaSurface
--- @param position MapPosition
--- @param radius number?
--- @return boolean
function M.is_acid_nearby(surface, position, radius)
  radius = radius or ACID_PROBE_RADIUS
  local fires = surface.find_entities_filtered({
    position = position,
    radius = radius,
    type = "fire",
    limit = 8,
  })
  for i = 1, #fires do
    if is_acid_fire(fires[i]) then
      return true
    end
  end
  return false
end

--- @param spidertron LuaEntity
--- @return boolean
function M.has_acid_sticker(spidertron)
  local stickers = spidertron.stickers
  if not stickers then
    return false
  end
  for i = 1, #stickers do
    local s = stickers[i]
    if s.valid and string.find(s.name, "acid", 1, true) then
      return true
    end
  end
  return false
end

--- @param center MapPosition
--- @param angle number
--- @param dist number
--- @return MapPosition
local function offset_at_angle(center, angle, dist)
  return {
    x = center.x + math.cos(angle) * dist,
    y = center.y + math.sin(angle) * dist,
  }
end

--- @param from MapPosition
--- @param to MapPosition
--- @return number
local function angle_between(from, to)
  return atan2(from.y - to.y, from.x - to.x)
end

--- Pick a combat waypoint around the target.
--- @param spidertron LuaEntity
--- @param target LuaEntity
--- @param ai table
--- @return MapPosition?
function M.pick_position(spidertron, target, ai)
  local cfg = settings_mod.get()
  local range = cfg.combat_range or 20
  local style = cfg.combat_style or "strafe"
  local avoid_acid = cfg.avoid_acid ~= false
  local tp = target.position
  local sp = spidertron.position
  local surface = spidertron.surface
  local base_angle = angle_between(sp, tp)

  if style == "circle" then
    ai.orbit_angle = (ai.orbit_angle or base_angle) + 0.55
    base_angle = ai.orbit_angle
  elseif style == "strafe" then
    ai.strafe_sign = -(ai.strafe_sign or 1)
    base_angle = base_angle + ai.strafe_sign * 0.9
  elseif style == "flank" then
    if not ai.flank_sign then
      -- Deterministic per spider so multiplayer stays consistent.
      ai.flank_sign = (ai.unit_number % 2 == 0) and 1 or -1
    end
    base_angle = base_angle + ai.flank_sign * 1.8
  end
  -- "hold" keeps base_angle (radial line from target through spider).

  local urgent = avoid_acid and (
    M.is_acid_nearby(surface, sp, ACID_PROBE_RADIUS)
    or M.has_acid_sticker(spidertron)
  )

  for try = 0, CANDIDATE_TRIES - 1 do
    local angle = base_angle + try * (math.pi * 2 / CANDIDATE_TRIES)
    local dist = range
    if urgent then
      dist = range + 4 + try * 2
    end
    local candidate = offset_at_angle(tp, angle, dist)
    if not avoid_acid or not M.is_acid_nearby(surface, candidate, ACID_PROBE_RADIUS) then
      local non_collide = surface.find_non_colliding_position(
        spidertron.name,
        candidate,
        6,
        1
      )
      return non_collide or candidate
    end
  end

  -- Fallback: just back away from target along current radial.
  return offset_at_angle(tp, angle_between(sp, tp), range + (urgent and 8 or 0))
end

--- Whether the spider should issue a new combat micro-move this tick.
--- @param ai table
--- @param spidertron LuaEntity
--- @param target LuaEntity
--- @return boolean
function M.should_reposition(ai, spidertron, target)
  local cfg = settings_mod.get()
  local range = cfg.combat_range or 20
  local move_interval = cfg.combat_move_interval or 90
  local pause = cfg.combat_pause_ticks or 45
  local style = cfg.combat_style or "strafe"
  local dist = util.distance(spidertron.position, target.position)

  local urgent = cfg.avoid_acid ~= false and (
    M.is_acid_nearby(spidertron.surface, spidertron.position, ACID_PROBE_RADIUS)
    or M.has_acid_sticker(spidertron)
  )
  if urgent then
    return true
  end

  -- Too close or too far → correct spacing.
  if dist < range * 0.65 or dist > range * 1.35 then
    if not ai.combat_next_move_tick or game.tick >= ai.combat_next_move_tick then
      return true
    end
  end

  if style == "hold" then
    return false
  end

  local last = ai.combat_last_move_tick or 0
  if game.tick < last + pause then
    return false
  end
  if game.tick < last + move_interval then
    return false
  end
  return true
end

--- Apply a combat reposition if needed. Returns true if a move was issued.
--- @param ai table
--- @param spidertron LuaEntity
--- @param target LuaEntity
--- @return boolean
function M.update(ai, spidertron, target)
  if not M.should_reposition(ai, spidertron, target) then
    -- Hold still to shoot: clear follow so we do not walk into the target.
    if spidertron.follow_target then
      spidertron.follow_target = nil
    end
    return false
  end

  local goal = M.pick_position(spidertron, target, ai)
  if not goal then
    return false
  end

  -- Short combat hops: direct autopilot (pathfinder is overkill and fights micro-moves).
  spidertron.follow_target = nil
  spidertron.autopilot_destination = goal
  ai.combat_last_move_tick = game.tick
  ai.combat_next_move_tick = game.tick + (settings_mod.get().combat_pause_ticks or 45)
  ai.pending_goal = { x = goal.x, y = goal.y }
  return true
end

return M
