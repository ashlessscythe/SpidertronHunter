--- Minimal assert helpers for pure-Lua tests (no Factorio runtime).

local harness = {}

local failures = 0
local passes = 0

function harness.assert_eq(a, b, msg)
  if a ~= b then
    failures = failures + 1
    error((msg or "assert_eq") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
  end
  passes = passes + 1
end

function harness.assert_true(v, msg)
  if not v then
    failures = failures + 1
    error((msg or "assert_true") .. ": expected truthy, got " .. tostring(v), 2)
  end
  passes = passes + 1
end

function harness.assert_false(v, msg)
  if v then
    failures = failures + 1
    error((msg or "assert_false") .. ": expected falsy, got " .. tostring(v), 2)
  end
  passes = passes + 1
end

function harness.assert_near(a, b, eps, msg)
  eps = eps or 1e-9
  if type(a) ~= "number" or type(b) ~= "number" or math.abs(a - b) > eps then
    failures = failures + 1
    error((msg or "assert_near") .. ": " .. tostring(a) .. " !~ " .. tostring(b), 2)
  end
  passes = passes + 1
end

--- Test selection. `patterns`: run only tests whose name contains any of them (case-insensitive,
--- plain text). `list_only`: print names instead of running.
local patterns = {}
local list_only = false
local skipped = 0

--- @param opts {patterns: string[]?, list_only: boolean?}
function harness.configure(opts)
  patterns = {}
  for _, p in ipairs(opts.patterns or {}) do
    patterns[#patterns + 1] = p:lower()
  end
  list_only = opts.list_only or false
end

local function selected(name)
  if #patterns == 0 then
    return true
  end
  local lname = name:lower()
  for _, p in ipairs(patterns) do
    if lname:find(p, 1, true) then
      return true
    end
  end
  return false
end

function harness.run(name, fn)
  if not selected(name) then
    skipped = skipped + 1
    return
  end
  if list_only then
    print(name)
    return
  end
  local ok, err = pcall(fn)
  if ok then
    print("  PASS  " .. name)
  else
    failures = failures + 1
    print("  FAIL  " .. name .. " — " .. tostring(err))
  end
end

function harness.is_list_only()
  return list_only
end

function harness.summary()
  print(string.format("\n%d passed, %d failed%s", passes, failures,
    skipped > 0 and (", " .. skipped .. " tests skipped by filter") or ""))
  return failures == 0
end

function harness.reset()
  failures = 0
  passes = 0
  skipped = 0
end

return harness
