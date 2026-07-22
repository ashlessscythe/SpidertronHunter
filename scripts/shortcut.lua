--- Toolbar shortcut toggle highlighting.
local persistence = require("scripts.persistence")
local util = require("scripts.util")

local M = {}

local SHORTCUT = "sh-toggle-autonomy"

--- Toolbar highlight when every selected spider has Hunter AI on.
--- @param player LuaPlayer
--- @return boolean
local function selection_all_enabled(player)
  local found = false
  local function consider(e)
    if not util.is_valid_spidertron(e) then
      return true
    end
    found = true
    local ai = persistence.get_ai_for_entity(e)
    return ai ~= nil and ai.state ~= "idle"
  end

  if player.spidertron_remote_selection then
    for _, e in pairs(player.spidertron_remote_selection) do
      if util.is_valid_spidertron(e) and not consider(e) then
        return false
      end
    end
  end
  if not found and player.vehicle then
    if not consider(player.vehicle) then
      return false
    end
  end
  if not found and player.opened and player.opened.object_name == "LuaEntity" then
    if not consider(player.opened) then
      return false
    end
  end
  return found
end

--- @param player LuaPlayer
function M.sync_player(player)
  if not player or not player.valid then
    return
  end
  player.set_shortcut_toggled(SHORTCUT, selection_all_enabled(player))
end

--- Sync every connected player (after enable/disable that may affect shared fleets).
function M.sync_all()
  for _, player in pairs(game.connected_players) do
    M.sync_player(player)
  end
end

M.SHORTCUT = SHORTCUT

return M
