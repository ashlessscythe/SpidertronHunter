--- Autopilot wrappers. Final motion is always vanilla spidertron autopilot.
local pathfinder = require("scripts.pathfinder")
local util = require("scripts.util")

local M = {}

--- @param spidertron LuaEntity
--- @param goal MapPosition
--- @param lake_aware boolean?
function M.go_to(spidertron, goal, lake_aware)
  if not util.is_valid_spidertron(spidertron) then
    return
  end
  if lake_aware == false then
    spidertron.follow_target = nil
    spidertron.autopilot_destination = goal
    return
  end
  pathfinder.request_path_to(spidertron, goal)
end

--- @param spidertron LuaEntity
--- @param target LuaEntity
function M.follow(spidertron, target)
  if not util.is_valid_spidertron(spidertron) then
    return
  end
  if not target or not target.valid then
    return
  end
  spidertron.autopilot_destination = nil
  spidertron.follow_target = target
end

--- @param spidertron LuaEntity
function M.clear(spidertron)
  if not spidertron or not spidertron.valid then
    return
  end
  spidertron.follow_target = nil
  spidertron.autopilot_destination = nil
end

--- @param spidertron LuaEntity
--- @param position MapPosition
--- @param radius number?
--- @return boolean
function M.is_near(spidertron, position, radius)
  radius = radius or 5
  return util.distance(spidertron.position, position) <= radius
end

--- @param ai table
--- @return MapPosition
function M.home_position(ai)
  return { x = ai.home.x, y = ai.home.y }
end

return M
