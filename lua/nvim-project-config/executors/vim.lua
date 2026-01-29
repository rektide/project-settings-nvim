local function vim_executor(ctx, file_path)
  local ok, err = pcall(vim.cmd.source, file_path)
  if not ok then
    error(err)
  end
end

return vim_executor
