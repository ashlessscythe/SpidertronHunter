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

function harness.run(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("  PASS  " .. name)
  else
    failures = failures + 1
    print("  FAIL  " .. name .. " — " .. tostring(err))
  end
end

function harness.summary()
  print(string.format("\n%d passed, %d failed", passes, failures))
  return failures == 0
end

function harness.reset()
  failures = 0
  passes = 0
end

return harness
