# persist.nvim

A lightweight Neovim session persistence plugin with support for unsaved
`[No Name]` buffers.

Unlike Neovim's built-in `:mksession`, `persist.nvim` stores the contents of
unnamed scratch buffers and lets you review, restore, or discard them when
Neovim starts.

## Features

- Restores tabs, windows, and split layouts
- Persists modified `[No Name]` buffers with non-empty content
- Shows a full preview of saved scratch notes before restoration
- Restores all notes or reviews them one by one
- Discards an unwanted note together with its tab
- Automatically ignores and forgets empty tabs
- Avoids overwriting the saved session when Neovim is started with file arguments or stdin
- Stores all state under `stdpath("state")`
- Provides manual save and restore commands

## Requirements

- Neovim 0.10 or newer

## Installation

### lazy.nvim

```lua
{
  "dmshvedchenko/persist.nvim",
  config = function()
    require("persist").setup()
  end,
}
```


### packer.nvim

```lua
use({
  "dmshvedchenko/persist.nvim",
  config = function()
    require("persist").setup()
  end,
})
```

### Native packages

```bash
git clone https://github.com/dmshvedchenko/persist.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/persist.nvim
```

Then add this to your Neovim configuration:

```lua
require("persist").setup()
```

## Setup

The plugin currently requires no configuration options:

```lua
require("persist").setup()
```

Call `setup()` only once.

## Commands

| Command | Description |
|---|---|
| `:PersistSave` | Manually save the current layout and scratch notes |
| `:PersistRestore` | Manually restore the saved state |

## Automatic behavior

When Neovim starts without file arguments and without stdin, `persist.nvim`
checks for a saved session and restores it.

When Neovim exits normally, the plugin saves the current session.

Starting Neovim with a file does not overwrite the saved main session:

```bash
nvim file.txt
```

The same protection applies when input is read from stdin.

## Scratch-buffer recovery

A scratch buffer is persisted when all of the following are true:

- it is a listed unnamed buffer;
- its `buftype` is empty;
- it contains non-whitespace text;
- it is modified or was previously restored by `persist.nvim`.

When saved scratch notes are found during startup, the plugin offers these
actions:

- **Restore all** — restore every saved tab and note
- **Review one by one** — preview each note before deciding
- **Delete all tabs containing notes** — permanently discard all saved scratch-note tabs
- **Do not restore now** — postpone restoration and disable automatic saving for that Neovim instance

While reviewing notes individually, you can:

- restore the tab;
- permanently delete the note and its entire tab;
- stop the restoration process.

## Empty tabs

Completely empty tabs are not written to the session manifest.

Empty tabs left by an older manifest are removed automatically during the next
restore. They are neither shown in the recovery menu nor restored.

## Storage

The session manifest is stored at:

```text
stdpath("state")/persist/session.json
```

Scratch-buffer snapshots are stored at:

```text
stdpath("state")/persist/scratch/<id>.txt
```

On common systems, `stdpath("state")` usually resolves to a location similar
to:

```text
~/.local/state/nvim
```

Do not rely on that exact path in scripts; use `:lua print(vim.fn.stdpath("state"))`
to inspect the path used by your Neovim installation.

## How it works

The plugin has two internal layers:

- `persist.session` stores tabs, windows, split layouts, file paths, and references to scratch snapshots.
- `persist.scratch` stores and restores the text of unnamed buffers.

The layout is serialized as JSON rather than through `:mksession`, because
`:mksession` does not preserve the contents of unnamed buffers.

## Limitations

- The plugin persists regular file buffers and unnamed scratch buffers.
- Special buffers such as help, quickfix, terminal, and plugin-specific buffers are ignored.
- Window sizes are not currently persisted; split structure and ordering are restored.
- The recovery interface uses `vim.ui.select()`. Its appearance depends on your Neovim UI or selector plugin.
- If every saved tab is discarded, Neovim keeps its required initial empty tab.

## Troubleshooting

### Check the state directory

```vim
:lua print(vim.fn.stdpath("state"))
```

### Save manually

```vim
:PersistSave
```

### Restore manually

```vim
:PersistRestore
```

### Check which module is loaded

```vim
:lua print(debug.getinfo(require("persist.session").restore).source)
```

### Reset saved state

Close Neovim and remove the plugin state directory:

```bash
rm -rf "$(nvim --headless +'lua io.write(vim.fn.stdpath("state"))' +qa)/persist"
```

This permanently deletes the saved manifest and all scratch snapshots.

## Development

Clone the repository into a local directory:

```bash
git clone git@github.com:dmshvedchenko/persist.nvim.git
cd persist.nvim
```

For local testing with `lazy.nvim`:

```lua
{
  dir = "/absolute/path/to/persist.nvim",
  config = function()
    require("persist").setup()
  end,
}
```

Run a basic headless module-load check:

```bash
nvim --headless \
  --cmd "set runtimepath^=$(pwd)" \
  +'lua require("persist").setup()' \
  +qa
```

## Repository structure

```text
persist.nvim/
├── LICENSE
├── README.md
└── lua/
    └── persist/
        ├── init.lua
        ├── scratch.lua
        └── session.lua
```

## Contributing

Bug reports and pull requests are welcome. When reporting a bug, include:

- your Neovim version;
- your operating system;
- your plugin manager;
- exact reproduction steps;
- relevant messages from `:messages`;
- a minimal configuration when possible.

## License

MIT
