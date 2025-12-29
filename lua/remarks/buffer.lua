local M = {}

local git = require("remarks.git")

--- Quick add a remark via vim.ui.input
---@param remark_type string|nil Remark type (default from config)
function M.quick_add(remark_type)
  local config = require("remarks").config
  remark_type = remark_type or config.default_type

  vim.ui.input({
    prompt = "Remark (" .. remark_type .. "): ",
  }, function(input)
    if not input or input == "" then
      return
    end

    local result = git.add(input, { type = remark_type })
    if result.success then
      vim.notify(result.output, vim.log.levels.INFO)
    else
      vim.notify("Failed to add remark: " .. (result.error or "unknown"), vim.log.levels.ERROR)
    end
  end)
end

--- Full add via buffer with YAML template
function M.full_add()
  local config = require("remarks").config
  local branch = git.get_branch() or "unknown"
  local head = git.get_head() or "HEAD"

  local template = {
    "# New remark on " .. head .. " (" .. branch .. ")",
    "# Save and close to add, :q! to cancel",
    "",
    "type: " .. config.default_type,
    "",
    "---",
    "",
    "",
  }

  M.open_buffer({
    title = "New Remark",
    lines = template,
    on_save = function(lines)
      local remark_type, body = M.parse_remark_buffer(lines)
      if not body or body == "" then
        vim.notify("Remark body cannot be empty", vim.log.levels.ERROR)
        return false
      end

      local result = git.add(body, { type = remark_type })
      if result.success then
        vim.notify(result.output, vim.log.levels.INFO)
        return true
      else
        vim.notify("Failed to add remark: " .. (result.error or "unknown"), vim.log.levels.ERROR)
        return false
      end
    end,
  })
end

--- Edit an existing remark
---@param remark table Remark object from git.list()
---@param opts { style: string|nil }|nil Options (style overrides config)
function M.edit_remark(remark, opts)
  opts = opts or {}
  local config = require("remarks").config
  local branch = git.get_branch() or "unknown"
  local style_override = opts.style

  local lines = {
    "# Editing remark [" .. remark.id .. "] on " .. remark.sha .. " (" .. branch .. ")",
    "# Save and close to update, :q! to cancel",
    "",
    "type: " .. remark.type,
    "",
    "---",
    "",
  }

  -- Add body lines
  for line in remark.body:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  -- Ensure at least one empty line for editing
  if remark.body == "" then
    table.insert(lines, "")
  end

  M.open_buffer({
    title = "Remark [" .. remark.id .. "]",
    lines = lines,
    style = style_override,
    on_save = function(new_lines)
      local new_type, new_body = M.parse_remark_buffer(new_lines)
      if not new_body or new_body == "" then
        vim.notify("Remark body cannot be empty", vim.log.levels.ERROR)
        return false
      end

      -- To edit, we resolve the old and add a new one
      -- This preserves the approach of the CLI
      local resolve_result = git.resolve(remark.id)
      if not resolve_result.success then
        vim.notify("Failed to update remark: " .. (resolve_result.error or "unknown"), vim.log.levels.ERROR)
        return false
      end

      local add_result = git.add(new_body, { type = new_type, commit = remark.sha })
      if add_result.success then
        vim.notify("Updated remark", vim.log.levels.INFO)
        return true
      else
        vim.notify("Failed to update remark: " .. (add_result.error or "unknown"), vim.log.levels.ERROR)
        return false
      end
    end,
  })
end

--- Parse remark buffer content
---@param lines string[] Buffer lines
---@return string|nil type, string|nil body
function M.parse_remark_buffer(lines)
  local remark_type = nil
  local body_lines = {}
  local in_body = false

  for _, line in ipairs(lines) do
    if in_body then
      table.insert(body_lines, line)
    else
      -- Skip comments
      if line:match("^#") then
        goto continue
      end

      -- Check for type line
      local t = line:match("^type:%s*(%w+)")
      if t then
        remark_type = t
        goto continue
      end

      -- Check for separator
      if line:match("^%-%-%-") then
        in_body = true
        goto continue
      end
    end

    ::continue::
  end

  local body = vim.trim(table.concat(body_lines, "\n"))
  return remark_type, body
end

--- Open a buffer for editing
---@param opts { title: string, lines: string[], on_save: function, style: string|nil }
function M.open_buffer(opts)
  local config = require("remarks").config
  local style = opts.style or config.edit.style

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)

  -- Set a buffer name so :w works with BufWriteCmd
  local bufname = "remarks://" .. opts.title:gsub(" ", "_"):gsub("%[", ""):gsub("%]", "")
  vim.api.nvim_buf_set_name(buf, bufname)

  vim.bo[buf].filetype = "yaml"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  vim.bo[buf].modified = false

  local win
  if style == "float" then
    local width = math.floor(vim.o.columns * config.edit.width)
    local height = math.floor(vim.o.lines * config.edit.height)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
      title = " " .. opts.title .. " ",
      title_pos = "center",
    })
  elseif style == "split" then
    vim.cmd("split")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  elseif style == "vsplit" then
    vim.cmd("vsplit")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  elseif style == "tab" then
    vim.cmd("tabnew")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end

  -- Set up save autocmd (BufWriteCmd for :w, keeps buffer open)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local success = opts.on_save(lines)
      if success then
        vim.bo[buf].modified = false
        vim.notify("Remark saved", vim.log.levels.INFO)
      end
      -- Don't close - user can :q or :wq to close
    end,
  })

  -- <Esc> to close buffer (in normal mode)
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Close remark buffer" })

  -- Position cursor at the body
  local body_start = 1
  for i, line in ipairs(opts.lines) do
    if line:match("^%-%-%-") then
      body_start = i + 2
      break
    end
  end
  vim.api.nvim_win_set_cursor(win, { math.min(body_start, #opts.lines), 0 })
end

return M

