--- Standalone lake-aware remote pathing (Ctrl+RMB without Hunter AI enabled).
local pathfinder = require("scripts.pathfinder")
local util = require("scripts.util")

local M = {}

--- Ensure ephemeral path state for AI-off spidertrons.
--- @param spidertron LuaEntity
--- @param goal MapPosition
local function ensure_path_only(spidertron, goal)
  storage.path_only = storage.path_only or {}
  storage.path_only[spidertron.unit_number] = {
    entity = spidertron,
    pending_goal = { x = goal.x, y = goal.y },
    path_start_tick = nil,
  }
end

--- Lake-aware go-to for any eligible spidertron (AI on or off).
--- @param spidertron LuaEntity
--- @param position MapPosition?
--- @param player LuaPlayer?
--- @return boolean started
function M.go_lake_aware(spidertron, position, player)
  if not util.is_valid_spidertron(spidertron) or not position then
    return false
  end

  local goal = { x = position.x, y = position.y }
  local ai = storage.spiders and storage.spiders[spidertron.unit_number]
  if not ai or ai.state == "idle" then
    ensure_path_only(spidertron, goal)
  end

  spidertron.follow_target = nil
  spidertron.autopilot_destination = goal

  local started = pathfinder.request_path_to(spidertron, goal)
  if not started and player then
    util.flying_text(player, { "no-path" }, position)
  end
  return started
end

--- Drop standalone path tracking for one spider.
--- @param unit_number integer
function M.clear_path_only(unit_number)
  if storage.path_only then
    storage.path_only[unit_number] = nil
  end
end

return M
