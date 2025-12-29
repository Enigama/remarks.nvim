local M = {}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local git = require("remarks.git")

--- Create a Telescope picker for remarks
---@param opts { commit: string|nil }|nil Options
function M.pick_remarks(opts)
  opts = opts or {}

  local result = git.list()
  if not result.success then
    vim.notify("Failed to list remarks: " .. (result.error or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local remarks = result.remarks
  if #remarks == 0 then
    vim.notify("No active remarks", vim.log.levels.INFO)
    return
  end

  -- Filter by commit if specified
  if opts.commit then
    local head = git.get_head()
    remarks = vim.tbl_filter(function(r)
      return r.sha == head or r.is_head
    end, remarks)

    if #remarks == 0 then
      vim.notify("No remarks on current commit", vim.log.levels.INFO)
      return
    end
  end

  local config = require("remarks").config
  local theme_opts = {}
  if config.telescope.theme then
    local theme_fn = require("telescope.themes")["get_" .. config.telescope.theme]
    if theme_fn then
      theme_opts = theme_fn()
    end
  end

  pickers.new(theme_opts, {
    prompt_title = "Remarks",
    finder = finders.new_table({
      results = remarks,
      entry_maker = function(remark)
        local display = string.format(
          "[%s] %s · %s · %s%s",
          remark.id,
          remark.type,
          remark.age,
          remark.sha,
          remark.is_head and " (HEAD)" or ""
        )
        return {
          value = remark,
          display = display,
          ordinal = display,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Remark",
      define_preview = function(self, entry)
        local remark = entry.value
        local lines = {
          "id: " .. remark.id,
          "type: " .. remark.type,
          "commit: " .. remark.sha,
          "age: " .. remark.age,
          "",
          "---",
          "",
        }
        for line in remark.body:gmatch("[^\r\n]+") do
          table.insert(lines, line)
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = "yaml"
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      -- <CR> - Edit selected remark
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          require("remarks.buffer").edit_remark(selection.value)
        end
      end)

      -- d / x - Resolve (delete) selected remark
      local resolve_action = function()
        local selection = action_state.get_selected_entry()
        if selection then
          local remark = selection.value
          vim.ui.select({ "Yes", "No" }, {
            prompt = "Resolve remark [" .. remark.id .. "]?",
          }, function(choice)
            if choice == "Yes" then
              local result = git.resolve(remark.id)
              if result.success then
                vim.notify("Resolved [" .. remark.id .. "]", vim.log.levels.INFO)
                actions.close(prompt_bufnr)
                -- Reopen picker to refresh
                vim.schedule(function()
                  M.pick_remarks(opts)
                end)
              else
                vim.notify("Failed to resolve: " .. (result.error or "unknown"), vim.log.levels.ERROR)
              end
            end
          end)
        end
      end

      map("i", "<C-d>", resolve_action)
      map("n", "d", resolve_action)
      map("n", "x", resolve_action)

      -- a - Add new remark
      local add_action = function()
        actions.close(prompt_bufnr)
        require("remarks.buffer").quick_add()
      end

      map("i", "<C-a>", add_action)
      map("n", "a", add_action)

      -- <C-t> - Edit in new tab
      local edit_in_tab = function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          require("remarks.buffer").edit_remark(selection.value, { style = "tab" })
        end
      end

      map("i", "<C-t>", edit_in_tab)
      map("n", "<C-t>", edit_in_tab)

      return true
    end,
  }):find()
end

return M

