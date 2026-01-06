local M = {}

local git = require("remarks.git")

--- Get file path relative to git root
---@param bufnr number Buffer number
---@return string|nil
local function get_file_path(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then
    return nil
  end

  -- Get git root
  local git_root_result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if git_root_result.code ~= 0 then
    -- Not in a git repo, return relative to cwd
    return vim.fn.fnamemodify(file, ":.")
  end

  local git_root = vim.trim(git_root_result.stdout)
  local abs_file = vim.fn.fnamemodify(file, ":p")

  -- Make path relative to git root
  if abs_file:sub(1, #git_root) == git_root then
    local rel_path = abs_file:sub(#git_root + 2) -- +2 to skip the trailing /
    return rel_path
  end

  return vim.fn.fnamemodify(file, ":.")
end

--- Get line range from visual selection marks
---@param bufnr number Buffer number
---@return number|nil start_line, number|nil end_line
local function get_visual_selection_range(bufnr)
  -- Try multiple methods to get visual selection marks
  
  -- Method 1: Use vim.fn.line() - simplest approach
  local ok1, start_line1 = pcall(vim.fn.line, "'<")
  local ok2, end_line1 = pcall(vim.fn.line, "'>")
  
  if ok1 and ok2 and start_line1 and end_line1 and start_line1 > 0 and end_line1 > 0 then
    local start = start_line1
    local end_line = end_line1
    if start > end_line then
      start, end_line = end_line, start
    end
    return start, end_line
  end
  
  -- Method 2: Use getpos as fallback
  local ok3, start_pos = pcall(vim.fn.getpos, "'<")
  local ok4, end_pos = pcall(vim.fn.getpos, "'>")
  
  if ok3 and ok4 and start_pos and end_pos and #start_pos >= 2 and #end_pos >= 2 then
    local start = start_pos[2]
    local end_line = end_pos[2]
    if start > 0 and end_line > 0 then
      if start > end_line then
        start, end_line = end_line, start
      end
      return start, end_line
    end
  end

  return nil, nil
end

--- Format file context string
---@param file_path string|nil File path
---@param start_line number|nil Start line number
---@param end_line number|nil End line number
---@return string|nil
local function format_file_context(file_path, start_line, end_line)
  if not file_path then
    return nil
  end

  if not start_line then
    return nil
  end

  if end_line and end_line ~= start_line then
    return string.format("file: %s:%d-%d", file_path, start_line, end_line)
  else
    return string.format("file: %s:%d", file_path, start_line)
  end
end

--- Get file context from visual selection
---@param bufnr number|nil Buffer number (optional, will use buffer from marks if not provided)
---@return string|nil
local function get_file_context_from_selection(bufnr)
  -- Get the buffer number from visual selection marks
  local mark_bufnr = bufnr
  local start_line, end_line = nil, nil
  
  -- Try to get buffer number and line numbers from marks
  local ok1, start_pos = pcall(vim.fn.getpos, "'<")
  local ok2, end_pos = pcall(vim.fn.getpos, "'>")
  
  if ok1 and ok2 and start_pos and end_pos and #start_pos >= 4 and #end_pos >= 4 then
    -- getpos returns [bufnum, lnum, col, off]
    mark_bufnr = start_pos[1]  -- Buffer number where mark is set
    start_line = start_pos[2]   -- Line number
    end_line = end_pos[2]      -- Line number
    
    if start_line > 0 and end_line > 0 then
      if start_line > end_line then
        start_line, end_line = end_line, start_line
      end
    else
      return nil
    end
  else
    -- Fallback to using provided bufnr and line() function
    if not bufnr then
      return nil
    end
    start_line, end_line = get_visual_selection_range(bufnr)
    if not start_line then
      return nil
    end
    mark_bufnr = bufnr
  end
  
  -- Get file path from the buffer that has the marks
  local file_path = get_file_path(mark_bufnr)
  if not file_path then
    return nil
  end

  return format_file_context(file_path, start_line, end_line)
end

--- Quick add a remark via vim.ui.input
---@param remark_type string|nil Remark type (default from config)
function M.quick_add(remark_type)
  local config = require("remarks").config
  remark_type = remark_type or config.default_type

  local bufnr = vim.api.nvim_get_current_buf()
  local file_context = get_file_context_from_selection(bufnr)

  vim.ui.input({
    prompt = "Remark (" .. remark_type .. "): ",
  }, function(input)
    if not input or input == "" then
      return
    end

    local body = input
    if file_context then
      body = file_context .. "\n" .. body
    end

    local result = git.add(body, { type = remark_type })
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

  local bufnr = vim.api.nvim_get_current_buf()
  local file_context = get_file_context_from_selection(bufnr)

  local template = {
    "# New remark on " .. head .. " (" .. branch .. ")",
    "# Save and close to add, :q! to cancel",
    "",
    "type: " .. config.default_type,
    "",
    "---",
    "",
  }

  -- Add file context if visual selection exists
  if file_context then
    table.insert(template, file_context)
    table.insert(template, "")
  else
    table.insert(template, "")
  end

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
---@param opts { style: string|nil, include_visual_context: boolean|nil }|nil Options (style overrides config, include_visual_context captures visual selection)
function M.edit_remark(remark, opts)
  opts = opts or {}
  local config = require("remarks").config
  local branch = git.get_branch() or "unknown"
  local style_override = opts.style
  local include_visual_context = opts.include_visual_context or false

  -- Capture visual selection context only when explicitly requested
  local file_context = nil
  if include_visual_context then
    file_context = get_file_context_from_selection()
    if not file_context then
      vim.notify("No visual selection found", vim.log.levels.WARN)
    end
  end

  local header_comment = "# Editing remark [" .. remark.id .. "] on " .. remark.sha .. " (" .. branch .. ")"
  if file_context then
    header_comment = header_comment .. "\n# Visual selection detected - file context added below"
  end
  header_comment = header_comment .. "\n# Save and close to update, :q! to cancel"

  local lines = {}
  for line in header_comment:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  table.insert(lines, "")
  table.insert(lines, "type: " .. remark.type)
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")

  -- Add body lines (existing content - preserved)
  local body_lines = vim.split(remark.body, "\n", { plain = true })
  for _, line in ipairs(body_lines) do
    table.insert(lines, line)
  end

  -- Add file context at the bottom if visual selection exists
  if file_context then
    -- Add spacing and explanation before the new file context
    if remark.body ~= "" and not remark.body:match("\n%s*$") then
      table.insert(lines, "")
    end
    table.insert(lines, file_context)
    table.insert(lines, "")
  else
    -- Ensure at least one empty line for editing if no file context
    if remark.body == "" then
      table.insert(lines, "")
    end
  end

  M.open_buffer({
    title = "Remark [" .. remark.id .. "]",
    lines = lines,
    style = style_override,
    start_in_insert = include_visual_context,
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

  -- Remove leading empty lines
  while #body_lines > 0 and body_lines[1] == "" do
    table.remove(body_lines, 1)
  end
  -- Remove trailing empty lines
  while #body_lines > 0 and body_lines[#body_lines] == "" do
    table.remove(body_lines, #body_lines)
  end
  
  -- Join lines, preserving internal empty lines
  local body = table.concat(body_lines, "\n")
  return remark_type, body
end

--- Open a buffer for editing
---@param opts { title: string, lines: string[], on_save: function, style: string|nil, start_in_insert: boolean|nil }
function M.open_buffer(opts)
  local config = require("remarks").config
  local style = opts.style or config.edit.style
  local start_in_insert = opts.start_in_insert or false

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

  -- Position cursor
  local cursor_line
  if start_in_insert then
    -- When starting in insert mode, position at the end (where new comments go)
    cursor_line = #opts.lines
  else
    -- Normal mode: position at the body start
    local body_start = 1
    for i, line in ipairs(opts.lines) do
      if line:match("^%-%-%-") then
        body_start = i + 2
        break
      end
    end
    cursor_line = math.min(body_start, #opts.lines)
  end
  vim.api.nvim_win_set_cursor(win, { cursor_line, 0 })

  -- Enter insert mode if requested (use schedule to ensure window is ready)
  if start_in_insert then
    vim.schedule(function()
      vim.cmd("startinsert")
    end)
  end
end

return M

