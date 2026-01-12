local M = {}

local git = require("remarks.git")

--- Format a remark for display in vim.ui.select
---@param remark table The remark object
---@return string
local function format_remark(remark)
  return string.format(
    "[%s] %s · %s · %s%s",
    remark.id,
    remark.type,
    remark.age,
    remark.sha,
    remark.is_head and " (HEAD)" or ""
  )
end

--- Default picker using vim.ui.select
---@param remarks table[] List of remarks
---@param opts table Options passed to the picker
local function default_picker(remarks, opts)
  vim.ui.select(remarks, {
    prompt = opts.commit and "Remarks on current commit:" or "All remarks:",
    format_item = format_remark,
  }, function(selected)
    if selected then
      require("remarks.buffer").edit_remark(selected)
    end
  end)
end

--- Fetch and filter remarks based on options
---@param opts { commit: string|nil }|nil Options
---@return table[]|nil remarks List of remarks or nil on error
local function get_remarks(opts)
  opts = opts or {}

  local result = git.list()
  if not result.success then
    vim.notify("Failed to list remarks: " .. (result.error or "unknown error"), vim.log.levels.ERROR)
    return nil
  end

  local remarks = result.remarks
  if #remarks == 0 then
    vim.notify("No active remarks", vim.log.levels.INFO)
    return nil
  end

  -- Filter by commit if specified
  if opts.commit then
    local head = git.get_head()
    remarks = vim.tbl_filter(function(r)
      return r.sha == head or r.is_head
    end, remarks)

    if #remarks == 0 then
      vim.notify("No remarks on current commit", vim.log.levels.INFO)
      return nil
    end
  end

  return remarks
end

--- Open the remarks picker
---@param opts { commit: string|nil }|nil Options
function M.pick_remarks(opts)
  opts = opts or {}

  local remarks = get_remarks(opts)
  if not remarks then
    return
  end

  local config = require("remarks").config
  local picker = config.picker

  if type(picker) == "function" then
    picker(remarks, opts)
  else
    default_picker(remarks, opts)
  end
end

return M
