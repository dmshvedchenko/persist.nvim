-- persist/init.lua
-- Entry point: autocommands and user commands.
--   session layer (tabs/windows/order) — persist.session
--   scratch layer ([No Name] text)    — persist.scratch
--
-- Add this to your configuration init.lua:
--   require("persist").setup()

local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("persist_nvim", { clear = true })
  local stdin = false
  local active = false

  vim.api.nvim_create_autocmd("StdinReadPre", {
    group = group,
    callback = function()
      stdin = true
    end,
  })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    nested = true,
    callback = function()
      -- The "main" instance is Neovim started without arguments or stdin.
      -- Only this instance restores and later overwrites the persisted state,
      -- so `nvim file.txt` does not overwrite saved notes.
      active = vim.fn.argc() == 0 and not stdin
      if active then
        vim.schedule(function()
          require("persist.session").restore()
        end)
      end
    end,
  })

  -- Use VimLeavePre rather than ExitPre: it runs exactly once during any
  -- normal exit (including :qa!), while tabs and windows still exist.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if active then
        require("persist.session").save()
      end
    end,
  })

  vim.api.nvim_create_user_command("PersistSave", function()
    require("persist.session").save()
  end, { desc = "Persist: manually save the layout and scratch notes" })

  vim.api.nvim_create_user_command("PersistRestore", function()
    require("persist.session").restore()
  end, { desc = "Persist: restore the saved state" })
end

return M
