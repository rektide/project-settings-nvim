--- Lua file executor for nvim-project-config
--- @module nvim-project-config.executors.lua

--- Execute a Lua config file
--- @param ctx table pipeline context
--- @param file_path string absolute path to the Lua file
--- @return any result from the executed file (if any)
local function lua_executor(ctx, file_path)
  local ok, result = pcall(dofile, file_path)
  if not ok then
    error(result)
  end
  return result
end

return lua_executor
