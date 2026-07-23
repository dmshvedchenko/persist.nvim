# persist.nvim

> A lightweight session persistence plugin for Neovim with interactive scratch buffer recovery.

Unlike the built-in `:mksession`, **persist.nvim** preserves the contents of unnamed (`[No Name]`) buffers and provides an interactive recovery workflow.

This means you can safely close Neovim without losing temporary notes, drafts, or command output stored in scratch buffers.

---

## ✨ Features

- 📑 Restore tabs, windows, and split layouts
- 📝 Persist unnamed (`[No Name]`) scratch buffers
- 👀 Preview scratch buffers before restoring
- ✅ Restore only the tabs you want
- 🗑️ Permanently discard unwanted scratch notes
- 🚫 Automatically ignore empty tabs
- 💾 JSON-based session storage
- ⚡ Lightweight with no external dependencies

---

## 📸 Preview

> **GIF coming soon**

---

## 📦 Installation

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
use {
    "dmshvedchenko/persist.nvim",
    config = function()
        require("persist").setup()
    end,
}
```

---

## 🚀 Quick Start

Once installed, **persist.nvim** works automatically.

When Neovim exits, it saves:

- tabs
- windows
- split layouts
- unnamed scratch buffers

The next time Neovim starts, the plugin restores your previous session.

If scratch buffers are found, you'll be prompted to:

- restore all notes;
- review notes one by one;
- permanently discard unwanted notes;
- postpone restoration until later.

No additional configuration is required.

---

## 🤔 Why not `:mksession`?

The built-in `:mksession` command restores files and window layouts, but it does **not** preserve the contents of unnamed (`[No Name]`) buffers.

`persist.nvim` solves this problem by storing scratch buffers separately and restoring them through an interactive workflow.

Instead of blindly restoring everything, you can:

- preview every scratch buffer;
- restore only the important ones;
- permanently delete unwanted notes;
- automatically forget empty tabs.

---

## 🛠 Commands

| Command | Description |
|----------|-------------|
| `:PersistSave` | Save the current session |
| `:PersistRestore` | Restore the last saved session |

---

## 📂 Storage

Session metadata is stored in:

```text
stdpath("state")/persist/session.json
```

Scratch buffers are stored in:

```text
stdpath("state")/persist/scratch/
```

---

## 📋 Requirements

- Neovim **0.10** or newer

---

## 🗺 Roadmap

Planned improvements include:

- native `:help persist` documentation
- configurable behaviour
- restore hooks
- optional automatic restore
- CI and automated tests

Suggestions and feature requests are always welcome.

---

## 🤝 Contributing

Bug reports, feature requests, and pull requests are welcome.

If you discover a bug or have an idea that could improve the plugin, please open an issue.

---

## 📄 License

MIT
