--- Optional Spidertron Patrols handoff (soft dependency via remote only).
--- Force manual while Hunter owns the spidertron; restore previous mode on disable.

local M = {}

local INTERFACE = "SpidertronPatrols"

--- @return boolean
local function has_fn(name)
  local iface = remote and remote.interfaces and remote.interfaces[INTERFACE]
  return iface ~= nil and iface[name] ~= nil
end

--- @param element LuaGuiElement
--- @param name string
--- @return LuaGuiElement?
local function find_named(element, name)
  if not element or not element.valid then
    return nil
  end
  if element.name == name then
    return element
  end
  local children = element.children
  if not children then
    return nil
  end
  for i = 1, #children do
    local found = find_named(children[i], name)
    if found then
      return found
    end
  end
  return nil
end

--- @return boolean
function M.is_available()
  return has_fn("set_on_patrol")
end

--- Whether Patrols currently has this spidertron in automatic mode.
--- May return nil when Patrols is absent, the call fails, or the remote
--- does not return patrol data (SpidertronPatrols' get_patrol_data remote
--- historically omits `return`, so callers always see nil).
--- @param spidertron LuaEntity
--- @return boolean? was_auto
function M.get_was_auto(spidertron)
  if not has_fn("get_patrol_data") then
    return nil
  end
  local ok, data = pcall(function()
    return remote.call(INTERFACE, "get_patrol_data", spidertron)
  end)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data.on_patrol ~= nil
end

--- Fallback: read Automatic/Manual switch from an open Patrols schedule pane.
--- left = automatic, right = manual.
--- @param spidertron LuaEntity
--- @return boolean? was_auto
function M.read_was_auto_from_gui(spidertron)
  if not game or not game.players or not spidertron then
    return nil
  end
  local ok, result = pcall(function()
    for _, player in pairs(game.players) do
      if player.valid and player.opened == spidertron then
        local root = player.gui.relative["sp-relative-frame"]
        if root and root.valid then
          local switch = find_named(root, "on_patrol_switch")
          if switch and switch.valid and switch.type == "switch" then
            return switch.switch_state == "left"
          end
        end
      end
    end
    return nil
  end)
  if ok then
    return result
  end
  return nil
end

--- Prior auto/manual to restore after Hunter disable.
--- Prefer remote data; else open schedule GUI; else assume manual so we never
--- flip a manual schedule to auto when the read remote is broken.
--- @param spidertron LuaEntity
--- @return boolean? was_auto nil if Patrols is not available
function M.capture_was_auto(spidertron)
  if not M.is_available() then
    return nil
  end
  local was = M.get_was_auto(spidertron)
  if was ~= nil then
    return was
  end
  local from_gui = M.read_was_auto_from_gui(spidertron)
  if from_gui ~= nil then
    return from_gui
  end
  return false
end

--- Switch Patrols to manual so Hunter can own autopilot.
--- @param spidertron LuaEntity
--- @return boolean success
function M.set_manual(spidertron)
  if not has_fn("set_on_patrol") then
    return false
  end
  local ok = pcall(function()
    remote.call(INTERFACE, "set_on_patrol", spidertron, false)
  end)
  return ok
end

--- Restore Patrols auto after Hunter disable when it was auto before.
--- If it was already manual, leave it (do not call set_on_patrol(false) again —
--- that clears autopilot_destination).
--- @param spidertron LuaEntity
--- @param was_auto boolean?
--- @return boolean did_restore
function M.restore(spidertron, was_auto)
  if was_auto ~= true then
    return false
  end
  if not has_fn("set_on_patrol") then
    return false
  end
  local ok = pcall(function()
    remote.call(INTERFACE, "set_on_patrol", spidertron, true)
  end)
  return ok
end

return M
