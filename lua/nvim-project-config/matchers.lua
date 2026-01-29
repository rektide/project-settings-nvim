--- Flexible matching utilities for nvim-project-config
--- A matcher can be a string, table, function, or vim.regex userdata.
--- @module nvim-project-config.matchers

local M = {}

--- Check if a value is a vim.regex userdata
--- @param val any
--- @return boolean
local function is_vim_regex(val)
  return type(val) == "userdata" and pcall(function() val:match_str("") end)
end

--- Get the basename from a path
--- @param path string
--- @return string
local function basename(path)
  return vim.fn.fnamemodify(path, ":t")
end

--- Wrap a function explicitly as a matcher
--- @param func function receives path, returns boolean
--- @return function
function M.fn(func)
  return func
end

--- Create a literal string matcher (exact basename match)
--- @param str string the string to match exactly
--- @return function
function M.literal(str)
  return function(path)
    return basename(path) == str
  end
end

--- Create a Lua pattern matcher
--- @param str string the Lua pattern to match against basename
--- @return function
function M.pattern(str)
  return function(path)
    return basename(path):match(str) ~= nil
  end
end

--- Negate a matcher
--- @param matcher any a matcher (string, table, function, or vim.regex)
--- @return function
function M.not_(matcher)
  local fn = M.process(matcher)
  return function(path)
    return not fn(path)
  end
end

--- OR combinator: returns true if any matcher matches
--- @vararg any matchers to combine
--- @return function
function M.any(...)
  local matchers = { ... }
  local fns = {}
  for i, m in ipairs(matchers) do
    fns[i] = M.process(m)
  end
  return function(path)
    for _, fn in ipairs(fns) do
      if fn(path) then
        return true
      end
    end
    return false
  end
end

--- AND combinator: returns true if all matchers match
--- @vararg any matchers to combine
--- @return function
function M.all(...)
  local matchers = { ... }
  local fns = {}
  for i, m in ipairs(matchers) do
    fns[i] = M.process(m)
  end
  return function(path)
    for _, fn in ipairs(fns) do
      if not fn(path) then
        return false
      end
    end
    return true
  end
end

--- Normalize any input to a matcher function
--- Handles: nil, string, table, function, vim.regex userdata
--- @param item any the matcher specification
--- @return function a function(path) -> boolean
function M.process(item)
  if item == nil then
    return function(_)
      return true
    end
  end

  if type(item) == "string" then
    return M.literal(item)
  end

  if type(item) == "table" then
    return M.any(unpack(item))
  end

  if type(item) == "function" then
    return item
  end

  if is_vim_regex(item) then
    return function(path)
      return item:match_str(basename(path)) ~= nil
    end
  end

  error("matchers.process: unsupported matcher type: " .. type(item))
end

return M
