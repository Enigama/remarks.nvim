local M = {}

--- Execute a git-remarks command
---@param args string[] Command arguments
---@return { success: boolean, output: string, error: string|nil }
local function execute(args)
  local cmd = { "git-remarks" }
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  local result = vim.system(cmd, { text = true }):wait()

  if result.code == 0 then
    return {
      success = true,
      output = vim.trim(result.stdout or ""),
      error = nil,
    }
  else
    return {
      success = false,
      output = "",
      error = vim.trim(result.stderr or result.stdout or "Unknown error"),
    }
  end
end

--- List all active remarks on current branch
---@return { success: boolean, remarks: table[], error: string|nil }
function M.list()
  local result = execute({ "list" })
  if not result.success then
    return { success = false, remarks = {}, error = result.error }
  end

  local remarks = M.parse_list_output(result.output)
  return { success = true, remarks = remarks, error = nil }
end

--- Add a remark
---@param body string Remark body text
---@param opts { type: string|nil, commit: string|nil }|nil Options
---@return { success: boolean, output: string, error: string|nil }
function M.add(body, opts)
  opts = opts or {}
  local args = { "add" }

  if opts.type then
    table.insert(args, "--type")
    table.insert(args, opts.type)
  end

  if opts.commit then
    table.insert(args, opts.commit)
  end

  table.insert(args, body)

  return execute(args)
end

--- Resolve (delete) a remark
---@param id string Remark ID
---@return { success: boolean, output: string, error: string|nil }
function M.resolve(id)
  return execute({ "resolve", id })
end

--- Initialize git-remarks hooks
---@return { success: boolean, output: string, error: string|nil }
function M.init()
  return execute({ "init" })
end

--- Get current branch name
---@return string|nil
function M.get_branch()
  local result = vim.system({ "git", "symbolic-ref", "--short", "HEAD" }, { text = true }):wait()
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

--- Get current HEAD commit (short SHA)
---@return string|nil
function M.get_head()
  local result = vim.system({ "git", "rev-parse", "--short", "HEAD" }, { text = true }):wait()
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

--- Parse the list command output into structured data
---@param output string Raw output from git remarks list
---@return table[] List of remark objects
function M.parse_list_output(output)
  local remarks = {}

  if output == "" or output:match("no active remarks") then
    return remarks
  end

  -- Parse format: [id] type · age · sha (HEAD)?
  --   body text
  local current_remark = nil

  -- Split by newlines to preserve empty lines
  local lines = vim.split(output, "\n", { plain = true })
  for _, line in ipairs(lines) do
    -- Check for remark header line: [a1b2c3d4] thought · 2h ago · abc1234 (HEAD)
    local id, rtype, age, sha = line:match("^%[(%w+)%]%s+(%w+)%s+·%s+(.-)%s+·%s+(%w+)")
    if id then
      if current_remark then
        table.insert(remarks, current_remark)
      end
      current_remark = {
        id = id,
        type = rtype,
        age = age,
        sha = sha,
        is_head = line:match("%(HEAD%)") ~= nil,
        body = "",
      }
    elseif current_remark then
      -- Body line (starts with two spaces) or empty line in body
      local body_line = line:match("^%s%s(.+)")
      if body_line then
        -- Non-empty body line (has content after 2 spaces)
        if current_remark.body ~= "" then
          current_remark.body = current_remark.body .. "\n"
        end
        current_remark.body = current_remark.body .. body_line
      elseif line == "" or line:match("^%s?%s?$") then
        -- Empty line or line with 0-2 spaces only - preserve as empty line in body
        if current_remark.body ~= "" then
          current_remark.body = current_remark.body .. "\n"
        end
        -- Empty line is represented by empty string, which is already handled by the \n above
      end
    end
  end

  if current_remark then
    table.insert(remarks, current_remark)
  end

  return remarks
end

return M

