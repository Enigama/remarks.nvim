-- Prevent loading twice
if vim.g.loaded_remarks then
  return
end
vim.g.loaded_remarks = true

-- Check for git-remarks CLI
if vim.fn.executable("git-remarks") ~= 1 then
  vim.notify("remarks.nvim: git-remarks CLI not found in PATH", vim.log.levels.WARN)
end

