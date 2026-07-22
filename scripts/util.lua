--- Shared helpers. Prefer reuse over allocation in hot paths.
local util = {}

local DENYLIST_PREFIXES = {
  "constructron",
  "deconstructron",
  "ss-docked-",
}

--- @param name string
--- @return boolean
function util.is_allowed_spidertron_name(name)
  if not name then
    return false
  end
  for i = 1, #DENYLIST_PREFIXES do
    local prefix = DENYLIST_PREFIXES[i]
    if name == prefix or name:sub(1, #prefix) == prefix then
      return false
    end
  end
  return true
end

--- @param entity LuaEntity?
--- @return boolean
function util.is_valid_spidertron(entity)
  return entity ~= nil
    and entity.valid
    and entity.type == "spider-vehicle"
    and util.is_allowed_spidertron_name(entity.name)
end

--- @param a MapPosition
--- @param b MapPosition
--- @return number
function util.distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

--- @param a MapPosition
--- @param b MapPosition
--- @return number
function util.distance_squared(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return dx * dx + dy * dy
end

--- Chunk key as a single integer for stable indexing (deterministic).
--- @param position MapPosition
--- @return integer
function util.chunk_key(position)
  local cx = math.floor(position.x / 32)
  local cy = math.floor(position.y / 32)
  -- Pack into one number; Factorio maps stay within practical bounds.
  return cx * 65536 + cy
end

--- Combined hull (+ optional shield) integrity in [0, 1].
--- @param spidertron LuaEntity
--- @param include_shields boolean?
--- @return number
function util.defense_ratio(spidertron, include_shields)
  if not spidertron or not spidertron.valid then
    return 0
  end
  local health = spidertron.health or 0
  local max_health = spidertron.max_health or 1
  if max_health <= 0 then
    max_health = 1
  end
  if not include_shields then
    return health / max_health
  end

  local shield = 0
  local max_shield = 0
  local grid = spidertron.grid
  if grid then
    for _, eq in pairs(grid.equipment) do
      local eq_max = eq.max_shield or 0
      if eq_max > 0 then
        shield = shield + (eq.shield or 0)
        max_shield = max_shield + eq_max
      end
    end
  end

  return (health + shield) / (max_health + max_shield)
end

--- flib-style capped iteration for UPS staggering.
--- @param tbl table
--- @param from_k any
--- @param n number
--- @param callback fun(value: any, key: any): any, boolean?, boolean?
--- @return any next_key
--- @return table results
--- @return boolean reached_end
function util.for_n_of(tbl, from_k, n, callback)
  if from_k and not tbl[from_k] then
    from_k = nil
  end

  local delete
  local prev
  local abort
  local result = {}

  for _ = 1, n do
    local v
    if not delete then
      prev = from_k
      from_k, v = next(tbl, from_k)
    else
      local next_k
      next_k, v = next(tbl, from_k)
      tbl[from_k] = nil
      from_k = next_k
      delete = nil
    end

    if from_k == nil then
      return nil, result, true
    end

    local r, d, a = callback(v, from_k)
    if r ~= nil then
      result[from_k] = r
    end
    delete = d
    if a then
      abort = true
      break
    end
  end

  if delete then
    local next_k = next(tbl, from_k)
    tbl[from_k] = nil
    from_k = next_k
  end

  return from_k, result, abort == true and false or from_k == nil
end

--- @param player LuaPlayer?
--- @param text LocalisedString
--- @param position MapPosition?
function util.flying_text(player, text, position)
  if not player or not player.valid then
    return
  end
  player.create_local_flying_text({
    text = text,
    position = position,
    create_at_cursor = position == nil,
  })
end

--- Flying text over a spidertron when debug mode is on (also writes to the log).
--- @param msg string
--- @param at LuaEntity|table|nil entity or ai table (needs .entity)
function util.debug_log(msg, at)
  if not storage.settings_cache or not storage.settings_cache.debug_mode then
    return
  end
  log("[SpidertronHunter] " .. msg)

  local entity
  if at then
    if at.object_name == "LuaEntity" then
      entity = at
    elseif at.entity then
      entity = at.entity
    end
  end
  if not entity or not entity.valid then
    return
  end

  local position = entity.position
  local surface_index = entity.surface_index
  for _, player in pairs(game.connected_players) do
    if player.valid and player.surface_index == surface_index then
      player.create_local_flying_text({
        text = msg,
        position = position,
      })
    end
  end
end

return util
