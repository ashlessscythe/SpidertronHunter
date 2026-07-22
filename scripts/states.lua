--- Finite state machine registry and dispatch.
local util = require("scripts.util")

local States = {}

States.IDLE = "idle"
States.PATROL = "patrol"
States.SEARCH = "search"
States.MOVING = "moving"
States.ATTACKING = "attacking"
States.RETURNING = "returning"
States.RESTOCKING = "restocking"
States.WAITING = "waiting"

-- Skip patrol↔search chatter; only surface meaningful phase changes.
local DEBUG_FLYING = {
  moving = true,
  attacking = true,
  returning = true,
  restocking = true,
  waiting = true,
}

--- @type table<string, {enter: fun(ai: table), update: fun(ai: table): string?, exit: fun(ai: table)}>
local handlers = {}

--- @param name string
--- @param handler {enter: fun(ai: table)?, update: fun(ai: table): string?, exit: fun(ai: table)?}
function States.register(name, handler)
  handlers[name] = {
    enter = handler.enter or function() end,
    update = handler.update or function() end,
    exit = handler.exit or function() end,
  }
end

--- @param ai table
--- @param new_state string
function States.transition(ai, new_state)
  if not new_state or new_state == ai.state then
    return
  end
  local old = handlers[ai.state]
  if old then
    old.exit(ai)
  end
  ai.state = new_state
  ai.state_entered_tick = game.tick
  local neu = handlers[new_state]
  if neu then
    neu.enter(ai)
  end
  if DEBUG_FLYING[new_state] then
    util.debug_log(new_state, ai)
  end
end

--- @param ai table
function States.update(ai)
  local handler = handlers[ai.state]
  if not handler then
    return
  end
  local next_state = handler.update(ai)
  if not next_state or next_state == ai.state then
    return
  end
  States.transition(ai, next_state)
  -- Chain one follow-up update so PATROL→SEARCH→MOVING can complete in one think.
  local follow = handlers[ai.state]
  if follow then
    local chained = follow.update(ai)
    if chained and chained ~= ai.state then
      States.transition(ai, chained)
    end
  end
end

return States
