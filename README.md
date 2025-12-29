# remarks.nvim

Neovim plugin for [git-remarks](https://github.com/Enigama/git-remarks) — personal developer notes attached to Git commits.

## Features

- **Telescope integration** — Browse, edit, and resolve remarks with fuzzy finding
- **Quick add** — Add remarks via input prompt
- **Full add** — Add remarks with YAML template in a buffer
- **Configurable** — Float, split, vsplit, or tab for edit buffers

## Requirements

- Neovim 0.9+
- [git-remarks](https://github.com/Enigama/git-remarks) CLI installed and in PATH
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

## Installation

### lazy.nvim

```lua
{
  "Enigama/remarks.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("remarks").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "Enigama/remarks.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
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
  telescope = {
    theme = nil,        -- "dropdown" | "ivy" | "cursor" | nil
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:Remarks` | Open Telescope picker with all active remarks |
| `:RemarksAdd [type]` | Quick add a remark (thought, doubt, todo, decision) |
| `:RemarksAddFull` | Add a remark via buffer with full template |
| `:RemarksShow` | Show remarks on current commit |
| `:RemarksInit` | Initialize git-remarks hooks in repository |

## Telescope Keymaps

When in the Remarks picker:

| Key | Action |
|-----|--------|
| `<CR>` | Edit selected remark |
| `d` / `x` / `<C-d>` | Resolve (delete) selected remark |
| `a` / `<C-a>` | Add new remark |

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
```

## License

MIT

