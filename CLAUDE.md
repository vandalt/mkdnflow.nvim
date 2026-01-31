# CLAUDE.md

Project instructions for Claude Code when working with mkdnflow.nvim.

## Project Overview

Mkdnflow is a Neovim plugin for fluent markdown notebook navigation and management. It provides link handling, buffer navigation, to-do lists, table formatting, folding, and more.

## Project Structure

```
mkdnflow.nvim/
├── lua/
│   ├── mkdnflow.lua          # Main entry point, default config, setup()
│   └── mkdnflow/             # Feature modules
│       ├── bib.lua           # Bibliography/citation handling
│       ├── buffers.lua       # Buffer navigation (back/forward)
│       ├── cmp.lua           # nvim-cmp completion source
│       ├── compat.lua        # Backwards compatibility layer
│       ├── conceal.lua       # Link syntax concealing
│       ├── cursor.lua        # Cursor movement (links, headings)
│       ├── folds.lua         # Section folding
│       ├── foldtext.lua      # Custom foldtext display
│       ├── links.lua         # Link creation, following, destruction
│       ├── lists.lua         # List item management
│       ├── maps.lua          # Keybinding setup
│       ├── paths.lua         # Path resolution and handling
│       ├── tables.lua        # Markdown table formatting
│       ├── to_do/            # To-do list management (submodule)
│       │   ├── init.lua
│       │   ├── core.lua
│       │   └── hl.lua        # To-do highlighting
│       ├── utils.lua         # Shared utilities
│       ├── wrappers.lua      # Command wrapper functions
│       └── yaml.lua          # YAML frontmatter parsing
├── plugin/
│   └── mkdnflow.lua          # Plugin loader (registers commands)
├── doc/
│   └── mkdnflow.txt          # Vim help file (GENERATED - do not edit)
├── scripts/
│   ├── generate_docs.py      # Documentation generator (single source of truth)
│   └── minimal_init.lua      # Test initialization script
├── tests/
│   └── test_*.lua            # Test files (mini.test framework)
├── README.md                  # GitHub readme (GENERATED - do not edit)
├── Makefile                   # `make docs`, `make test`
├── CONTRIBUTING.md
├── CHANGELOG.md
└── LICENSE
```

## Documentation Workflow

**IMPORTANT:** `README.md` and `doc/mkdnflow.txt` are GENERATED files.

- **Source of truth:** `scripts/generate_docs.py`
- **To update docs:** Edit `generate_docs.py`, then run `make docs`
- **CI verifies** docs are in sync via `.github/workflows/docs-check.yml`

Never edit README.md or doc/mkdnflow.txt directly.

## Module Architecture

The plugin uses a modular architecture where features can be enabled/disabled:

```lua
-- In lua/mkdnflow.lua
modules = {
    bib = true,      -- Bibliography support
    buffers = true,  -- Back/forward navigation
    conceal = true,  -- Link concealing
    cursor = true,   -- Cursor movement commands
    folds = true,    -- Section folding
    foldtext = true, -- Custom fold display
    links = true,    -- Link handling
    lists = true,    -- List management
    maps = true,     -- Keybindings
    paths = true,    -- Path resolution
    tables = true,   -- Table formatting
    to_do = true,    -- To-do lists
    yaml = false,    -- YAML parsing (off by default)
    cmp = false,     -- Completion (off by default)
}
```

Modules are loaded conditionally based on config. The main entry point `lua/mkdnflow.lua` contains:
- Default configuration table
- `setup(config)` function that merges user config and initializes modules
- `forceStart()` for manual initialization

## Commands

- **Linting/Formatting:** `stylua` with config in `.stylua.toml`
- **Documentation:** `make docs` regenerates README.md and doc/mkdnflow.txt
- **Testing:** `make test` runs all tests, `make test_file FILE=path` runs one file

## Testing

Tests use [mini.test](https://github.com/echasnovski/mini.test) framework (zero runtime dependencies).

```bash
make deps/mini.nvim   # One-time: download test dependency
make test             # Run all tests
make test_file FILE=tests/test_utils.lua  # Run specific file
```

- Test files go in `tests/` with `test_` prefix
- CI runs tests on Neovim v0.9.5, v0.10.0, and stable
- Pure utility functions in `utils.lua` are good test targets
- For buffer manipulation tests, use `MiniTest.new_child_neovim()`

## Code Style

### Formatting
- Column width: 100 characters
- Indent: 4 spaces
- Quote style: Single quotes preferred
- Configured in `.stylua.toml`

### Naming Conventions
- Module files: `snake_case.lua`
- Functions: `camelCase` (e.g., `getFileType`, `followLink`)
- Variables: `snake_case` (e.g., `start_row`, `link_table`)
- Module tables: `local M = {}`

### Module Pattern
```lua
local M = {}

-- Private functions (local, not in M)
local function helperFunction()
    -- ...
end

-- Public API (attached to M)
M.publicFunction = function(args)
    -- ...
end

return M
```

### Git Commits
- Follow [Conventional Commits](https://conventionalcommits.org): `feat:`, `fix:`, `docs:`, etc.
- Imperative present tense: "Add feature" not "Added feature"
- First line ≤ 72 characters
- Reference issues/PRs after first line

## Error Handling
- Use `vim.api.nvim_echo()` with highlight groups for user messages
- Return `nil` or `false` on failure rather than throwing errors
- Validate inputs at public API boundaries

## Neovim API Patterns

### Key Concepts
- Buffers, windows, tabpages are integer handles
- Buffer = file content, Window = viewport, Tabpage = window collection
- Current buffer: `0` or `vim.api.nvim_get_current_buf()`

### Common Operations
```lua
-- Buffer content
vim.api.nvim_buf_get_lines(bufnr, start, end, strict)
vim.api.nvim_buf_set_lines(bufnr, start, end, strict, lines)

-- Cursor (1-indexed row, 0-indexed col)
vim.api.nvim_win_get_cursor(0)  -- returns {row, col}
vim.api.nvim_win_set_cursor(0, {row, col})

-- Autocommands
vim.api.nvim_create_autocmd(event, { callback = fn, pattern = pat })
```

### Plugin-Specific Practices
- Include buffer ID in operations for multi-buffer safety
- Cache expensive operations, invalidate on buffer changes
- Validate line/column positions before access
- Use `vim.schedule()` for deferred operations when needed
