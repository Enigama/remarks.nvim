# remarks.nvim

Neovim plugin for [git-remarks](https://github.com/Enigama/git-remarks) — personal developer notes attached to Git commits.

## Features

- **Bring your own picker** — Use telescope, fzf-lua, mini.pick, snacks.nvim, or any picker you prefer
- **Quick add** — Add remarks via input prompt
- **Full add** — Add remarks with YAML template in a buffer
- **Visual selection context** — Automatically add file context from visual selection when editing remarks
- **Configurable** — Float, split, vsplit, or tab for edit buffers
- **Zero dependencies** — Falls back to `vim.ui.select()` when no picker is configured

## Requirements

- Neovim 0.9+
- [git-remarks](https://github.com/Enigama/git-remarks) CLI installed and in PATH

## Installation
Before install the plugin make sure that you have installed [git-remarks](https://github.com/Enigama/git-remarks)

### lazy.nvim

```lua
{
  "Enigama/remarks.nvim",
  config = function()
    require("remarks").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "Enigama/remarks.nvim",
  config = function()
    require("remarks").setup()
  end,
}
```

## Configuration

```lua
require("remarks").setup({
  edit = {
    style = "float",    -- "float" | "split" | "vsplit" | "tab"
    width = 0.6,        -- float width (0-1 = percentage)
    height = 0.4,       -- float height
  },
  default_type = "thought", -- default remark type
  picker = nil, -- function(remarks, opts) | nil for vim.ui.select fallback
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:Remarks` | Open picker with all active remarks |
| `:RemarksAdd [type]` | Quick add a remark (thought, doubt, todo, decision) |
| `:RemarksAddFull` | Add a remark via buffer with full template |
| `:RemarksShow` | Show remarks on current commit |
| `:RemarksInit` | Initialize git-remarks hooks in repository |

## Picker Configuration

By default, remarks.nvim uses `vim.ui.select()` which works out of the box and can be enhanced with [dressing.nvim](https://github.com/stevearc/dressing.nvim).

To use a custom picker, provide a function that receives:
- `remarks` — List of remark objects with fields: `id`, `type`, `age`, `sha`, `is_head`, `body`
- `opts` — Options table (e.g., `{ commit = "HEAD" }` when filtering by commit)

### Recommended Keybindings

| Key | Action |
|-----|--------|
| `<CR>` | Edit selected remark |
| `<C-e>` | Edit remark with visual selection context |
| `d` / `x` / `<C-d>` | Resolve (delete) selected remark |
| `a` / `<C-a>` | Add new remark |
| `<C-t>` | Edit selected remark in new tab |

### Telescope

```lua
{
  "Enigama/remarks.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")

    local function telescope_picker(remarks, opts)
      pickers.new({}, {
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
                  local result = require("remarks.git").resolve(remark.id)
                  if result.success then
                    vim.notify("Resolved [" .. remark.id .. "]", vim.log.levels.INFO)
                    actions.close(prompt_bufnr)
                    vim.schedule(function()
                      require("remarks.picker").pick_remarks(opts)
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

          -- <C-e> - Edit with visual selection context
          local edit_with_context = function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              require("remarks.buffer").edit_remark(selection.value, { include_visual_context = true })
            end
          end

          map("i", "<C-e>", edit_with_context)
          map("n", "<C-e>", edit_with_context)

          return true
        end,
      }):find()
    end

    require("remarks").setup({
      picker = telescope_picker,
    })
  end,
}
```

### fzf-lua

```lua
{
  "Enigama/remarks.nvim",
  dependencies = { "ibhagwan/fzf-lua" },
  config = function()
    local function fzf_picker(remarks, opts)
      local fzf = require("fzf-lua")
      local builtin = require("fzf-lua.previewer.builtin")

      local entries = {}
      local remark_map = {}
      for _, remark in ipairs(remarks) do
        local display = string.format(
          "[%s] %s · %s · %s%s",
          remark.id,
          remark.type,
          remark.age,
          remark.sha,
          remark.is_head and " (HEAD)" or ""
        )
        table.insert(entries, display)
        remark_map[display] = remark
      end

      -- Custom previewer using fzf-lua's builtin base
      local RemarksPreviewer = builtin.base:extend()

      function RemarksPreviewer:new(o, fzf_opts, fzf_win)
        RemarksPreviewer.super.new(self, o, fzf_opts, fzf_win)
        setmetatable(self, RemarksPreviewer)
        return self
      end

      function RemarksPreviewer:populate_preview_buf(entry_str)
        local remark = remark_map[entry_str]
        if not remark then
          return
        end

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

        local bufnr = self:get_tmp_buffer()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.bo[bufnr].filetype = "yaml"
        self:set_preview_buf(bufnr)
        if self.win and self.win.update_scrollbar then
          self.win:update_scrollbar()
        end
      end

      fzf.fzf_exec(entries, {
        prompt = "Remarks> ",
        previewer = RemarksPreviewer,
        actions = {
          ["default"] = function(selected)
            if selected[1] then
              local remark = remark_map[selected[1]]
              require("remarks.buffer").edit_remark(remark)
            end
          end,
          ["ctrl-d"] = function(selected)
            if selected[1] then
              local remark = remark_map[selected[1]]
              local result = require("remarks.git").resolve(remark.id)
              if result.success then
                vim.notify("Resolved [" .. remark.id .. "]", vim.log.levels.INFO)
                vim.schedule(function()
                  require("remarks.picker").pick_remarks(opts)
                end)
              end
            end
          end,
          ["ctrl-e"] = function(selected)
            if selected[1] then
              local remark = remark_map[selected[1]]
              require("remarks.buffer").edit_remark(remark, { include_visual_context = true })
            end
          end,
        },
      })
    end

    require("remarks").setup({
      picker = fzf_picker,
    })
  end,
}
```

### mini.pick

```lua
{
  "Enigama/remarks.nvim",
  dependencies = { "echasnovski/mini.pick" },
  config = function()
    local function mini_picker(remarks, opts)
      local MiniPick = require("mini.pick")

      local items = vim.tbl_map(function(remark)
        return {
          text = string.format(
            "[%s] %s · %s · %s%s",
            remark.id,
            remark.type,
            remark.age,
            remark.sha,
            remark.is_head and " (HEAD)" or ""
          ),
          remark = remark,
        }
      end, remarks)

      MiniPick.start({
        source = {
          items = items,
          name = "Remarks",
          choose = function(item)
            if item then
              vim.schedule(function()
                require("remarks.buffer").edit_remark(item.remark)
              end)
            end
          end,
        },
        mappings = {
          edit_context = {
            char = "<C-e>",
            func = function()
              local item = MiniPick.get_picker_matches().current
              if item then
                MiniPick.stop()
                vim.schedule(function()
                  require("remarks.buffer").edit_remark(item.remark, { include_visual_context = true })
                end)
              end
            end,
          },
        },
      })
    end

    require("remarks").setup({
      picker = mini_picker,
    })
  end,
}
```

### snacks.nvim

```lua
{
  "Enigama/remarks.nvim",
  dependencies = { "folke/snacks.nvim" },
  config = function()
    local function snacks_picker(remarks, opts)
      local items = vim.tbl_map(function(remark)
        return {
          text = string.format(
            "[%s] %s · %s · %s%s",
            remark.id,
            remark.type,
            remark.age,
            remark.sha,
            remark.is_head and " (HEAD)" or ""
          ),
          remark = remark,
        }
      end, remarks)

      require("snacks").picker({
        items = items,
        title = "Remarks",
        format = function(item)
          return { { item.text } }
        end,
        preview = function(ctx)
          local remark = ctx.item.remark
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
          vim.bo[ctx.buf].modifiable = true
          vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
          vim.bo[ctx.buf].filetype = "yaml"
        end,
        confirm = function(picker, item)
          picker:close()
          if item then
            require("remarks.buffer").edit_remark(item.remark)
          end
        end,
        actions = {
          edit_context = function(picker)
            local item = picker:current()
            picker:close()
            if item then
              require("remarks.buffer").edit_remark(item.remark, { include_visual_context = true })
            end
          end,
        },
        win = {
          input = {
            keys = {
              ["<C-e>"] = { "edit_context", mode = { "i", "n" } },
            },
          },
        },
      })
    end

    require("remarks").setup({
      picker = snacks_picker,
    })
  end,
}
```

## Example Workflow

```vim
" Initialize hooks in your repo (once)
:RemarksInit

" Quick add a thought
:RemarksAdd
> Remark (thought): Not sure about this approach

" Add with specific type
:RemarksAdd todo
> Remark (todo): Refactor before merge

" Full add with template
:RemarksAddFull
" Opens buffer:
" # New remark on abc1234 (feature/auth)
" type: thought
" ---
" Your detailed note here...

" Browse all remarks
:Remarks

" Show remarks on current commit
:RemarksShow

" Edit remark with visual selection context
" 1. Make a visual selection in your file (e.g., lines 25-35)
" 2. Open :Remarks picker
" 3. Press <C-e> on a remark
" 4. File context (file: path/to/file.ts:25-35) is automatically added
" 5. Start typing your comment immediately (already in insert mode)
```

## License

MIT

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
