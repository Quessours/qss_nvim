# Rust setup review

A review of the Rust part of this configuration, done on 2026-09-08.

Files in scope:

- `lua/plugins/rustacean-nvim.lua`
- `lua/qss_nvim/rustacean-nvim/settings.lua`
- `lua/qss_nvim/rustacean-nvim/mappings.lua`
- `lua/qss_nvim/nvim-dap/adapters/rust.lua`
- `lua/qss_nvim/custom_inlay_hints_handler/rust.lua`

Every claim below was checked against the installed plugin sources under
`~/.local/share/nvim/lazy/`, not from memory. The relevant files are
`rustaceanvim/lua/rustaceanvim/config/check.lua` (the option validator) and
`rustaceanvim/lua/rustaceanvim/config/internal.lua` (the defaults).

Summary: most of `settings.lua` is dead. It mixes options from the old
`rust-tools` plugin with one Tailwind option. rustaceanvim v6 ignores unknown
keys without a warning, so the file looks configured but is not.

## 1. Dead configuration

### `tools.inlay_hints` does not exist

`settings.lua:17-42`. The v6 validator has no entry for `tools.inlay_hints`.
Inlay hints come from `vim.lsp.inlay_hint` and from your `nvim-lsp-endhints`
formatter instead.

The same table is copied a second time in
`custom_inlay_hints_handler/rust.lua:1-36`, where the fields `auto`,
`only_current_line`, `max_len_align`, `right_align` and `highlight` are read
by nothing.

Delete both blocks. Keep only the fields that
`custom_inlay_hints_handler/rust.lua` actually reads in `formatInlayHints`.

### `tools.hover_actions` accepts one field

`settings.lua:56-66`. In v6 that table holds `replace_builtin_hover` alone.
`max_width`, `max_height` and `auto_focus` are ignored.

Move focus control to `tools.float_win_config.auto_focus = true`. Delete
`max_width` and `max_height`.

### `enable_nextest` is in the wrong place

`settings.lua:151`. The option lives at `tools.enable_nextest`, so the
top-level copy does nothing. The default is already
`vim.fn.executable('cargo-nextest') == 1`, which means you can delete the line
if nextest is installed.

### `init_options` belongs to Tailwind

`settings.lua:152-156`. `init_options.userLanguages = { rust = "html" }` is a
`tailwindcss-language-server` option. It was copied from
`lua/plugins/nvim-lspconfig.lua:23`, where it is correct. rust-analyzer never
receives it.

Delete it.

### Unused codelldb paths

`settings.lua:1-3` and `settings.lua:157-164`. The three path variables feed
only the commented-out `dap` block. Line 2 also misses a path separator, so it
builds `.../extensionadapter/codelldb`.

Delete lines 1-3 and the commented block.

## 2. Bugs

### The Rustacean guard is always true

`mappings.lua:3-5`:

```lua
local isRustaceanEnabled = function()
    return vim.cmd.RustLsp ~= nil
end
```

`vim.cmd` is a table with an `__index` metamethod that returns a callable for
any name. Indexing it never returns `nil`. I confirmed this headlessly:
`vim.cmd.ThisCommandDoesNotExist ~= nil` evaluates to `true`.

All four guards in the file are therefore dead, and the `vim.notify` branches
never run. Replace the check with:

```lua
local isRustaceanEnabled = function()
    return vim.fn.exists(':RustLsp') == 2
end
```

### Rust mappings leak into every buffer

`settings.lua:144-149`. `on_attach = function(_)` drops the second argument,
and `apply_mappings` in `lua/qss_nvim/utils/init.lua:30` sets no `buffer`
option. So `<leader>h`, `<leader>oc`, `<leader>cag` and `<leader>snd` become
global after the first Rust file attaches, and they are set again on every
later attach.

Take the buffer number and pass it through:

```lua
on_attach = function(_, bufnr)
    local apply_mappings = require("qss_nvim.utils").apply_mappings
    local mappings = require("qss_nvim.rustacean-nvim.mappings")
    for _, mode_values in pairs(mappings) do
        for _, mapping_info in pairs(mode_values) do
            mapping_info.opts = vim.tbl_extend("keep",
                mapping_info.opts or {}, { buffer = bufnr })
        end
    end
    apply_mappings(mappings)
end
```

### `preLaunchTask` does nothing, so the debugger runs a stale binary

`nvim-dap/adapters/rust.lua:6`, `:23` and `:50`. `preLaunchTask` is a Visual
Studio Code `launch.json` key. A grep over `nvim-dap/lua/` returns zero
matches for it, so `nvim-dap` drops it without a message. `cargo build` never
runs, and `require('dap').continue()` on a Rust file debugs whatever binary
was built last.

The whole file is also redundant. rustaceanvim sets
`dap.autoload_configurations = true` by default, discovers the codelldb
adapter through Mason, and asks cargo for the artifact path.

There is a second, worse effect. `rustaceanvim/lua/rustaceanvim/dap.lua:375`
reads the **first** entry of `dap.configurations.rust` as a template:

```lua
local _, dap_config = next(dap.configurations.rust or {})
```

Your first entry computes `program` with
`find target/debug -name $(basename $(pwd))`. That guess breaks on a workspace
with several binaries, because `execute_and_capture_output` joins the matches
with a space into one broken path.

Delete `lua/qss_nvim/nvim-dap/adapters/rust.lua` and the `require` at
`lua/qss_nvim/nvim-dap/adapters/init.lua:5`. Use `:RustLsp debuggables`. To
keep the backtrace variable, set it in `settings.lua`:

```lua
dap = {
    configuration = {
        type = 'codelldb',
        request = 'launch',
        name = 'Launch',
        env = { RUST_BACKTRACE = '1' },
        sourceLanguages = { 'rust' },
    },
},
```

### A global leaks

`mappings.lua:7`. `M = {` misses `local`.

### The hover call is duplicated

`mappings.lua:34-35` calls `vim.cmd.RustLsp { 'hover', 'actions' }` twice. That
is a workaround to focus the float window. Delete the second call and set
`tools.float_win_config.auto_focus = true`.

### One mapping has no description

`mappings.lua:39-46`. The `<leader>snd` entry gives no second table element,
so `apply_mappings` sets `opts.desc` to `nil` and which-key shows the entry
without a label.

Add a description, for example `"Cycle rendered diagnostic"`.

## 3. Missing pieces

### No rust-analyzer settings

`settings.lua` has no `server.default_settings['rust-analyzer']` table, so
every rust-analyzer option keeps its own default. Clippy is already on,
because `tools.enable_clippy` defaults to `true`.

Use `default_settings`, not `settings`. `settings` is a function by default,
and it loads `rust-analyzer.json` and `.vscode/settings.json` from the
project. Overwriting it turns that loading off.

```lua
server = {
    default_settings = {
        ['rust-analyzer'] = {
            cargo = { allFeatures = true },
            checkOnSave = true,
        },
    },
},
```

### No format on save

Every other server in this configuration sets `format_on_save = true`. See
`lua/lsp/configs/clangd.lua:67` and `lua/lsp/configs/qmlls.lua:97`. Rust has
no equivalent, so rustfmt never runs on write.

rustaceanvim passes the whole `server` table to the LSP client, and the hook in
`lua/qss_nvim/nvim-lspconfig/init.lua:92` reads `client.config.format_on_save`.
So one field inside `server` is enough:

```lua
server = {
    format_on_save = true,
    -- ...
},
```

### The `cond` blocks startup and misfires

`rustacean-nvim.lua:7-16`. The condition calls
`require("qss_nvim.utils").scan_dir()`, which runs
`io.popen('find -maxdepth 1 ...')`. That spawns a shell on every start, and it
only looks at the current directory. Open a file with
`nvim src/foo/bar.rs` from a parent directory and the plugin stays off, so you
get no LSP at all.

rustaceanvim already gates itself twice. Its `ftplugin/rust.lua` runs for Rust
buffers alone, and `server.auto_attach` checks that the `rust-analyzer`
executable exists.

Delete the `cond` block.

### The options are set too late

`rustacean-nvim.lua:17-20`:

```lua
config = function()
    require("rustaceanvim")
    vim.g.rustaceanvim = opts
end,
```

Set `vim.g.rustaceanvim` in `init`, which runs before the plugin loads. Drop
the bare `require`, because it returns nothing you use.

```lua
init = function()
    vim.g.rustaceanvim = opts
end,
```

### Nothing handles `Cargo.toml`

Add `saecki/crates.nvim` for dependency version completion, upgrade hints and
inline latest-version virtual text.

### Mason installs nothing for Rust

`lua/plugins/mason.lua:3` calls `require("mason").setup()` with no
`ensure_installed` list. `codelldb` and `rust-analyzer` must be installed by
hand. rustaceanvim finds codelldb through Mason when it is present, so listing
it makes the debug path work on a fresh machine.

## 4. What is already right

- No `rust_analyzer` entry in `lua/lsp/lsp_init.lua`. rustaceanvim warns about
  that conflict in `config/check.lua`, and this configuration avoids it.
- `lua/qss_nvim/overseer/init.lua:10` keeps cargo tasks out of Overseer, with a
  comment that says why.
- `lua/qss_nvim/nvim-dap/init.lua:147` sets `rust_panic` as a fallback
  exception breakpoint.
- `rust` is in the treesitter `ensure_installed` list.
