--- Detection stage for nvim-project-config pipeline
--- Checks for file/directory existence and triggers on_match callback
--- @module nvim-project-config.stages.detect

local uv = require("coop.uv")
local matchers = require("nvim-project-config.matchers")
local pipeline_mod = require("nvim-project-config.pipeline")

--- Create a detection stage
--- @param opts table|nil options
--- @param opts.matcher string|table|function what to look for (file/dir name to check existence)
--- @param opts.on_match function(ctx, path) called when matcher matches
--- @return function stage function(ctx, input_rx, output_tx)
local function detect(opts)
  opts = opts or {}
  local matcher_fn = matchers.process(opts.matcher)
  local on_match = opts.on_match

  local function check_exists(path, name)
    local target = path .. "/" .. name
    local err, stat = uv.fs_stat(target)
    return stat ~= nil and stat.type ~= nil
  end

  local function check_match(path)
    local matcher = opts.matcher
    if matcher == nil then
      return true
    elseif type(matcher) == "string" then
      return check_exists(path, matcher)
    elseif type(matcher) == "table" then
      for _, m in ipairs(matcher) do
        if type(m) == "string" then
          if check_exists(path, m) then
            return true
          end
        elseif type(m) == "function" then
          if m(path) then
            return true
          end
        end
      end
      return false
    elseif type(matcher) == "function" then
      return matcher(path)
    else
      return matcher_fn(path)
    end
  end

  return function(ctx, input_rx, output_tx)
    while true do
      if ctx._pipeline_stopped then
        return
      end

      local path = input_rx.recv()
      if path == nil or path == pipeline_mod.DONE then
        break
      end

      local matched = check_match(path)

      if matched and on_match then
        on_match(ctx, path)
      end

      output_tx.send(path)
    end
  end
end

return detect
