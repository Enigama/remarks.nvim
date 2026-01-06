local M = {}

-- Default configuration
M.config = {
  edit = {
    style = "float", -- "float" | "split" | "vsplit" | "tab"
    width = 0.6,     -- float width (0-1 = percentage)
    height = 0.4,    -- float height
  },
  default_type = "thought",
  picker = nil, -- function(remarks, opts) | nil for vim.ui.select fallback
}

--- Setup the remarks plugin
---@param opts table|nil Configuration options
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Register commands
  require("remarks.commands").setup()
end

return M

