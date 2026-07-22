-- v0.1.7: fleet path queue (no direct-into-water fallback when budget full).
local persistence = require("scripts.persistence")
persistence.init_storage()

storage.path_queue = storage.path_queue or {}
storage.path_requests = storage.path_requests or {}
storage.path_statuses = storage.path_statuses or {}
storage.path_requests_this_tick = 0

-- Clear in-flight path bookkeeping so hunters re-request with the new queue.
storage.path_requests = {}
storage.path_statuses = {}
storage.path_queue = {}

for _, ai in pairs(storage.spiders or {}) do
  if type(ai) == "table" then
    ai.path_stuck_since = nil
    ai.path_stuck_pos = nil
    ai.path_start_tick = nil
    ai.pending_goal = nil
  end
end
