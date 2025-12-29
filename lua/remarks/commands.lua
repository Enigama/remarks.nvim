local M = {}

function M.setup()
  local git = require("remarks.git")

  -- :Remarks - Open Telescope picker with all active remarks
  vim.api.nvim_create_user_command("Remarks", function()
    require("remarks.telescope").pick_remarks()
  end, {
    desc = "Open Telescope picker with all active remarks",
  })

  -- :RemarksAdd [type] - Quick add via vim.ui.input
  vim.api.nvim_create_user_command("RemarksAdd", function(opts)
    local remark_type = opts.args ~= "" and opts.args or nil
    require("remarks.buffer").quick_add(remark_type)
  end, {
    nargs = "?",
    desc = "Quick add a remark via input prompt",
    complete = function()
      return { "thought", "doubt", "todo", "decision" }
    end,
  })

  -- :RemarksAddFull - Full add via buffer with YAML template
  vim.api.nvim_create_user_command("RemarksAddFull", function()
    require("remarks.buffer").full_add()
  end, {
    desc = "Add a remark via buffer with full template",
  })

  -- :RemarksShow - Telescope picker filtered to current commit
  vim.api.nvim_create_user_command("RemarksShow", function()
    require("remarks.telescope").pick_remarks({ commit = "HEAD" })
  end, {
    desc = "Show remarks on current commit",
  })

  -- :RemarksInit - Run git remarks init
  vim.api.nvim_create_user_command("RemarksInit", function()
    local result = git.init()
    if result.success then
      vim.notify(result.output, vim.log.levels.INFO)
    else
      vim.notify(result.error, vim.log.levels.ERROR)
    end
  end, {
    desc = "Initialize git-remarks hooks in the repository",
  })
end

return M

