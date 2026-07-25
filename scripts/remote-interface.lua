--- Public remote interfaces for other mods / console debugging.
local ai = require("scripts.ai")
local persistence = require("scripts.persistence")
local targeting = require("scripts.targeting")
local scout = require("scripts.scout")

local function print_debug(player_index)
  local dump = ai.debug_dump()
  local lines = {
    string.format(
      "SpidertronHunter: %d spiders, cache entries=%d claims=%d",
      #dump.spiders,
      dump.cache.entries,
      dump.cache.claims
    ),
  }
  for i = 1, #dump.spiders do
    local s = dump.spiders[i]
    lines[#lines + 1] = string.format(
      "  #%s role=%s state=%s valid=%s target=%s wait=%s wp=%s",
      tostring(s.unit_number),
      tostring(s.role),
      tostring(s.state),
      tostring(s.valid),
      tostring(s.target),
      tostring(s.wait_reason),
      tostring(s.waypoints)
    )
  end
  local text = table.concat(lines, "\n")
  log("[SpidertronHunter]\n" .. text)
  if player_index then
    local player = game.get_player(player_index)
    if player then
      player.print(text)
    end
  else
    game.print(text)
  end
  return dump
end

local methods = {
  enable = function(spidertron)
    return ai.enable(spidertron, nil)
  end,

  disable = function(spidertron)
    ai.disable(spidertron, nil)
  end,

  is_enabled = function(spidertron)
    return ai.is_enabled(spidertron)
  end,

  get_role = function(spidertron)
    return ai.get_role(spidertron)
  end,

  set_role = function(spidertron, role)
    return ai.set_role(spidertron, role, nil)
  end,

  get_ai_data = function(spidertron)
    local data = persistence.get_ai_for_entity(spidertron)
    if not data then
      return nil
    end
    return {
      state = data.state,
      role = data.role,
      home = data.home,
      focus = data.focus_pos,
      waypoints = data.waypoints and #data.waypoints or 0,
      unit_number = data.unit_number,
      claim_id = data.claim_id,
      wait_reason = data.wait_reason,
    }
  end,

  set_home = function(spidertron, position)
    return ai.set_home(spidertron, position)
  end,

  clear_home = function(spidertron)
    return ai.clear_home(spidertron)
  end,

  follow_player = function(spidertron, player)
    return ai.follow_player(spidertron, player)
  end,

  return_home = function(spidertron)
    return ai.return_home(spidertron)
  end,

  set_scout_focus = function(spidertron, position)
    if not spidertron or not spidertron.valid then
      return false
    end
    if ai.get_role(spidertron) ~= "scout" then
      if not ai.enable_scout(spidertron, nil) then
        return false
      end
    end
    local data = persistence.get_ai_for_entity(spidertron)
    if not data or not position then
      return false
    end
    scout.set_focus(data, position)
    return true
  end,

  add_scout_waypoint = function(spidertron, position)
    if not spidertron or not spidertron.valid or not position then
      return false
    end
    if ai.get_role(spidertron) ~= "scout" then
      if not ai.enable_scout(spidertron, nil) then
        return false
      end
    end
    local data = persistence.get_ai_for_entity(spidertron)
    if not data then
      return false
    end
    scout.add_waypoint(data, position)
    return true
  end,

  clear_scout_waypoints = function(spidertron)
    local data = persistence.get_ai_for_entity(spidertron)
    if not data then
      return false
    end
    scout.clear_waypoints(data)
    return true
  end,

  debug = function(player_index)
    return print_debug(player_index)
  end,

  reset = function()
    targeting.reset()
    for _, data in pairs(storage.spiders) do
      data.claim_id = nil
      data.target_entity = nil
      data.target_pos = nil
      data.pending_goal = nil
      data.path_start_tick = nil
      data.player_goal = nil
      data.wait_reason = nil
      data.scout_goal = nil
      data.scout_goal_kind = nil
    end
    storage.path_requests = {}
    storage.path_statuses = {}
    storage.path_queue = {}
    log("[SpidertronHunter] reset cache and path state")
    return true
  end,

  scan = function(spidertron)
    return ai.force_scan(spidertron)
  end,
}

remote.add_interface("SpidertronHunter", methods)
-- Alias requested for console / scripting convenience.
remote.add_interface("spidertron_hunter", methods)
