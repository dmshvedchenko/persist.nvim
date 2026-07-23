-- persist/session.lua
-- Session/layout layer: handles tabs, windows, and their arrangement.
--
-- Uses a custom JSON manifest instead of mksession because
-- mksession cannot restore the contents of [No Name] buffers.
--
-- Storage:
--   stdpath("state")/persist/session.json
--
-- Scratch-buffer text is stored by persist.scratch.

local api = vim.api
local scratch = require("persist.scratch")

local M = {}

local restored = false
local save_blocked = false

----------------------------------------------------------------------
-- Paths
----------------------------------------------------------------------

local function state_dir()
  local directory = vim.fs.joinpath(
    vim.fn.stdpath("state"),
    "persist"
  )

  vim.fn.mkdir(directory, "p")

  return directory
end

local function manifest_path()
  return vim.fs.joinpath(
    state_dir(),
    "session.json"
  )
end

----------------------------------------------------------------------
-- Manifest
----------------------------------------------------------------------

local function write_manifest(manifest)
  local encode_ok, json = pcall(
    vim.json.encode,
    manifest
  )

  if not encode_ok then
    vim.notify(
      "persist: failed to serialize session.json",
      vim.log.levels.ERROR
    )

    return false
  end

  local path = manifest_path()
  local temporary_path = path .. ".tmp"
  local file = io.open(temporary_path, "w")

  if not file then
    vim.notify(
      "persist: failed to open the temporary session.json",
      vim.log.levels.ERROR
    )

    return false
  end

  file:write(json)
  file:close()

  local renamed, rename_error = os.rename(
    temporary_path,
    path
  )

  if not renamed then
    os.remove(temporary_path)

    vim.notify(
      "persist: failed to replace session.json: "
        .. tostring(rename_error),
      vim.log.levels.ERROR
    )

    return false
  end

  return true
end

local function quarantine_manifest(path)
  local damaged_path = path
    .. ".corrupt."
    .. os.time()

  os.rename(
    path,
    damaged_path
  )

  vim.notify(
    "persist: corrupt session.json moved to "
      .. damaged_path,
    vim.log.levels.WARN
  )
end

----------------------------------------------------------------------
-- Save
----------------------------------------------------------------------

local function leaf_ref(win, keep)
  local buf = api.nvim_win_get_buf(win)

  if not api.nvim_buf_is_valid(buf) then
    return {
      kind = "empty",
    }
  end

  if vim.bo[buf].buftype ~= "" then
    return {
      kind = "empty",
    }
  end

  local name = api.nvim_buf_get_name(buf)

  if name ~= "" then
    return {
      kind = "file",
      path = name,
    }
  end

  local id = scratch.save(buf)

  if id then
    keep[id] = true

    return {
      kind = "scratch",
      id = id,
    }
  end

  return {
    kind = "empty",
  }
end

local function convert_layout(node, keep)
  if type(node) ~= "table" then
    return {
      "leaf",
      {
        kind = "empty",
      },
    }
  end

  if node[1] == "leaf" then
    return {
      "leaf",
      leaf_ref(node[2], keep),
    }
  end

  local children = {}

  for _, child in ipairs(node[2] or {}) do
    children[#children + 1] = convert_layout(
      child,
      keep
    )
  end

  return {
    node[1],
    children,
  }
end

-- Checks whether the layout contains anything useful to restore.
-- Empty leaf nodes do not count as tab content.
local function layout_has_persistable_content(node)
  if type(node) ~= "table" then
    return false
  end

  if node[1] == "leaf" then
    local ref = node[2]

    return type(ref) == "table"
      and (
        ref.kind == "file"
        or ref.kind == "scratch"
      )
  end

  local children = node[2]

  if type(children) ~= "table" then
    return false
  end

  for _, child in ipairs(children) do
    if layout_has_persistable_content(child) then
      return true
    end
  end

  return false
end

function M.save()
  if save_blocked then
    vim.notify(
      "persist: saving is disabled because restoration "
        .. "of the previous session was postponed",
      vim.log.levels.WARN
    )

    return false
  end

  local keep = {}
  local tabs = {}

  local all_tabpages = api.nvim_list_tabpages()
  local current_tabpage = api.nvim_get_current_tabpage()
  local current_original_index = 1

  for index, tabpage in ipairs(all_tabpages) do
    if tabpage == current_tabpage then
      current_original_index = index
      break
    end
  end

  local removed_before_current = 0
  local saved_current_index = nil

  for original_index, tabpage in ipairs(all_tabpages) do
    local tab_number = api.nvim_tabpage_get_number(tabpage)

    local layout = convert_layout(
      vim.fn.winlayout(tab_number),
      keep
    )

    -- Do not save completely empty tabs.
    if layout_has_persistable_content(layout) then
      tabs[#tabs + 1] = {
        layout = layout,
      }

      if tabpage == current_tabpage then
        saved_current_index = #tabs
      end
    elseif original_index < current_original_index then
      removed_before_current = removed_before_current + 1
    end
  end

  local current = 1

  if #tabs > 0 then
    if saved_current_index then
      current = saved_current_index
    else
      -- If the current tab was empty, select the nearest non-empty tab.
      local candidate =
        current_original_index
        - removed_before_current

      current = math.min(
        math.max(candidate, 1),
        #tabs
      )
    end
  end

  local manifest = {
    version = 1,
    current = current,
    tabs = tabs,
  }

  if not write_manifest(manifest) then
    return false
  end

  scratch.cleanup(keep)

  return true
end

----------------------------------------------------------------------
-- Restore layout
----------------------------------------------------------------------

local function open_leaf(ref)
  if type(ref) ~= "table" then
    return
  end

  if ref.kind == "file"
    and type(ref.path) == "string"
  then
    local buf = vim.fn.bufadd(ref.path)

    vim.bo[buf].buflisted = true

    pcall(
      api.nvim_win_set_buf,
      0,
      buf
    )

    return
  end

  if ref.kind == "scratch"
    and type(ref.id) == "string"
  then
    local buf = scratch.load(ref.id)

    pcall(
      api.nvim_win_set_buf,
      0,
      buf
    )
  end
end

local function apply_layout(node)
  if type(node) ~= "table" then
    return
  end

  if node[1] == "leaf" then
    open_leaf(node[2])
    return
  end

  local children = node[2]

  if type(children) ~= "table"
    or #children == 0
  then
    return
  end

  local windows = {
    api.nvim_get_current_win(),
  }

  for _ = 2, #children do
    if node[1] == "row" then
      vim.cmd("rightbelow vsplit")
    else
      vim.cmd("rightbelow split")
    end

    windows[#windows + 1] =
      api.nvim_get_current_win()
  end

  for index, child in ipairs(children) do
    local win = windows[index]

    if win and api.nvim_win_is_valid(win) then
      api.nvim_set_current_win(win)
      apply_layout(child)
    end
  end
end

local function drop_empty_leftover_buffers()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local has_windows =
      #vim.fn.win_findbuf(buf) > 0

    if api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buflisted
      and vim.bo[buf].buftype == ""
      and api.nvim_buf_get_name(buf) == ""
      and not vim.bo[buf].modified
      and vim.b[buf].persist_id == nil
      and not has_windows
    then
      pcall(
        api.nvim_buf_delete,
        buf,
        {
          force = true,
        }
      )
    end
  end
end

local function restore_manifest(manifest)
  local tabs = manifest.tabs or {}

  if #tabs == 0 then
    return
  end

  -- Restore the first saved tab over the initial startup tab.
  -- Create subsequent tabs with :tabnew.
  for index, tab in ipairs(tabs) do
    if index > 1 then
      vim.cmd("$tabnew")
    end

    if type(tab) == "table" then
      local restore_ok, restore_error = pcall(
        apply_layout,
        tab.layout
      )

      if not restore_ok then
        vim.notify(
          "persist: failed to restore layout: "
            .. tostring(restore_error),
          vim.log.levels.WARN
        )
      end
    end
  end

  local current =
    tonumber(manifest.current) or 1

  current = math.min(
    math.max(current, 1),
    #tabs
  )

  pcall(
    vim.cmd,
    current .. "tabnext"
  )

  drop_empty_leftover_buffers()
end

----------------------------------------------------------------------
-- Scratch discovery
----------------------------------------------------------------------

local function collect_scratch_ids_from_layout(
  node,
  result,
  seen
)
  if type(node) ~= "table" then
    return
  end

  if node[1] == "leaf" then
    local ref = node[2]

    if type(ref) == "table"
      and ref.kind == "scratch"
      and type(ref.id) == "string"
      and not seen[ref.id]
    then
      seen[ref.id] = true
      result[#result + 1] = ref.id
    end

    return
  end

  for _, child in ipairs(node[2] or {}) do
    collect_scratch_ids_from_layout(
      child,
      result,
      seen
    )
  end
end

local function collect_scratches(manifest)
  local result = {}
  local seen = {}

  for tab_index, tab in ipairs(
    manifest.tabs or {}
  ) do
    if type(tab) == "table" then
      local ids = {}

      collect_scratch_ids_from_layout(
        tab.layout,
        ids,
        seen
      )

      for _, id in ipairs(ids) do
        result[#result + 1] = {
          id = id,
          tab_index = tab_index,
          preview = scratch.preview(id),
        }
      end
    end
  end

  return result
end

local function collect_all_scratch_ids_from_tab(tab)
  local result = {}
  local seen = {}

  if type(tab) == "table" then
    collect_scratch_ids_from_layout(
      tab.layout,
      result,
      seen
    )
  end

  return result
end

----------------------------------------------------------------------
-- Empty-tab cleanup
----------------------------------------------------------------------

-- Removes tabs from an existing session.json
-- when they contain neither a file nor a scratch note.
local function remove_empty_tabs_from_manifest(manifest)
  local old_tabs = manifest.tabs or {}
  local old_current =
    tonumber(manifest.current) or 1

  local new_tabs = {}

  local removed_before_current = 0
  local current_survived = false
  local surviving_current = nil

  for old_index, tab in ipairs(old_tabs) do
    local keep_tab =
      type(tab) == "table"
      and layout_has_persistable_content(
        tab.layout
      )

    if keep_tab then
      new_tabs[#new_tabs + 1] =
        vim.deepcopy(tab)

      if old_index == old_current then
        current_survived = true
        surviving_current = #new_tabs
      end
    elseif old_index < old_current then
      removed_before_current =
        removed_before_current + 1
    end
  end

  manifest.tabs = new_tabs

  if #new_tabs == 0 then
    manifest.current = 1
    return
  end

  if current_survived then
    manifest.current = surviving_current
    return
  end

  local candidate =
    old_current - removed_before_current

  manifest.current = math.min(
    math.max(candidate, 1),
    #new_tabs
  )
end

----------------------------------------------------------------------
-- Delete complete tabs
----------------------------------------------------------------------

local function remove_discarded_tabs(
  manifest,
  discarded_tab_indexes
)
  local old_tabs = manifest.tabs or {}
  local old_current =
    tonumber(manifest.current) or 1

  local new_tabs = {}

  local removed_before_current = 0
  local current_tab_removed = false

  for old_index, tab in ipairs(old_tabs) do
    if discarded_tab_indexes[old_index] then
      if old_index < old_current then
        removed_before_current =
          removed_before_current + 1
      elseif old_index == old_current then
        current_tab_removed = true
      end
    else
      new_tabs[#new_tabs + 1] =
        vim.deepcopy(tab)
    end
  end

  manifest.tabs = new_tabs

  if #new_tabs == 0 then
    -- If all saved tabs were removed, restore nothing.
    -- Neovim will keep its normal initial tabpage.
    manifest.current = 1
    return
  end

  if current_tab_removed then
    local candidate =
      old_current - removed_before_current

    manifest.current = math.min(
      math.max(candidate, 1),
      #new_tabs
    )

    return
  end

  manifest.current = math.min(
    math.max(
      old_current - removed_before_current,
      1
    ),
    #new_tabs
  )
end

local function delete_scratch_files_from_tabs(
  manifest,
  discarded_tab_indexes
)
  local deleted_ids = {}

  for tab_index in pairs(
    discarded_tab_indexes
  ) do
    local tab =
      manifest.tabs
      and manifest.tabs[tab_index]

    for _, id in ipairs(
      collect_all_scratch_ids_from_tab(tab)
    ) do
      if not deleted_ids[id] then
        deleted_ids[id] = true
        scratch.delete(id)
      end
    end
  end
end

----------------------------------------------------------------------
-- Preview window
----------------------------------------------------------------------

local function close_scratch_preview(preview)
  if not preview then
    return
  end

  if preview.win
    and api.nvim_win_is_valid(preview.win)
  then
    pcall(
      api.nvim_win_close,
      preview.win,
      true
    )
  end

  if preview.buf
    and api.nvim_buf_is_valid(preview.buf)
  then
    pcall(
      api.nvim_buf_delete,
      preview.buf,
      {
        force = true,
      }
    )
  end
end

local function open_scratch_preview(
  item,
  index,
  total
)
  local lines = scratch.read(item.id)

  if not lines then
    lines = {
      "",
      "Failed to read snapshot:",
      item.id,
      "",
    }
  elseif #lines == 0 then
    lines = {
      "",
      "(empty note)",
      "",
    }
  end

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  local width = math.min(
    math.max(
      60,
      math.floor(editor_width * 0.72)
    ),
    math.max(
      20,
      editor_width - 4
    )
  )

  local height = math.min(
    math.max(
      12,
      math.floor(editor_height * 0.62)
    ),
    math.max(
      6,
      editor_height - 6
    )
  )

  local row = math.max(
    0,
    math.floor(
      (editor_height - height) / 2
    ) - 1
  )

  local col = math.max(
    0,
    math.floor(
      (editor_width - width) / 2
    )
  )

  local buf =
    api.nvim_create_buf(false, true)

  api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    lines
  )

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "text"

  local win = api.nvim_open_win(
    buf,
    false,
    {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",

      title = string.format(
        " Note %d of %d — tab %d ",
        index,
        total,
        item.tab_index
      ),

      title_pos = "center",
      zindex = 40,
    }
  )

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = false
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"

  return {
    buf = buf,
    win = win,
  }
end

----------------------------------------------------------------------
-- Review
----------------------------------------------------------------------

local function review_scratches(
  items,
  index,
  discarded_tab_indexes,
  callback
)
  if index > #items then
    callback(discarded_tab_indexes)
    return
  end

  local item = items[index]

  -- If a previous note already caused this tab to be discarded,
  -- skip all remaining notes from the same tab.
  if discarded_tab_indexes[item.tab_index] then
    review_scratches(
      items,
      index + 1,
      discarded_tab_indexes,
      callback
    )

    return
  end

  local preview = open_scratch_preview(
    item,
    index,
    #items
  )

  local choices = {
    {
      action = "restore",
      label = "Restore this tab",
    },
    {
      action = "discard_tab",
      label = "Delete the note and discard this entire tab",
    },
    {
      action = "abort",
      label = "Stop restoration",
    },
  }

  vim.schedule(function()
    vim.ui.select(
      choices,
      {
        prompt = string.format(
          "Note %d of %d, tab %d",
          index,
          #items,
          item.tab_index
        ),

        format_item = function(choice)
          return choice.label
        end,
      },
      function(choice)
        close_scratch_preview(preview)

        if not choice
          or choice.action == "abort"
        then
          callback(nil)
          return
        end

        if choice.action == "discard_tab" then
          discarded_tab_indexes[
            item.tab_index
          ] = true
        end

        vim.schedule(function()
          review_scratches(
            items,
            index + 1,
            discarded_tab_indexes,
            callback
          )
        end)
      end
    )
  end)
end

----------------------------------------------------------------------
-- Finish restore
----------------------------------------------------------------------

local function finish_restore(manifest)
  save_blocked = false
  restored = true

  restore_manifest(manifest)
end

local function discard_tabs_and_restore(
  manifest,
  discarded_tab_indexes
)
  -- Delete scratch files first, while the old tab indexes
  -- still match the original manifest.
  delete_scratch_files_from_tabs(
    manifest,
    discarded_tab_indexes
  )

  -- Then remove the selected tabs entirely from the manifest.
  remove_discarded_tabs(
    manifest,
    discarded_tab_indexes
  )

  write_manifest(manifest)
  finish_restore(manifest)
end

----------------------------------------------------------------------
-- Public restore
----------------------------------------------------------------------

function M.restore()
  if restored then
    return
  end

  local path = manifest_path()

  if vim.fn.filereadable(path) ~= 1 then
    restored = true
    save_blocked = false
    return
  end

  local file = io.open(path, "r")

  if not file then
    restored = true
    return
  end

  local raw = file:read("*a")
  file:close()

  local decode_ok, manifest = pcall(
    vim.json.decode,
    raw
  )

  if not decode_ok
    or type(manifest) ~= "table"
    or type(manifest.tabs) ~= "table"
  then
    restored = true
    quarantine_manifest(path)
    return
  end

  -- Empty tabs are not restored and are forgotten immediately,
  -- including tabs saved by an older version of the module.
  remove_empty_tabs_from_manifest(manifest)

  if not write_manifest(manifest) then
    restored = true
    return
  end

  -- If no useful tabs remain, keep Neovim's normal
  -- initial startup tabpage.
  if #manifest.tabs == 0 then
    restored = true
    save_blocked = false
    return
  end

  local items = collect_scratches(manifest)

  if #items == 0 then
    finish_restore(manifest)
    return
  end

  local choices = {
    {
      action = "restore_all",
      label = "Restore all",
    },
    {
      action = "review",
      label = "Review one by one",
    },
    {
      action = "discard_all_tabs",
      label = "Discard all tabs containing notes",
    },
    {
      action = "later",
      label = "Do not restore now",
    },
  }

  vim.ui.select(
    choices,
    {
      prompt = string.format(
        "Unsaved notes found: %d",
        #items
      ),

      format_item = function(choice)
        return choice.label
      end,
    },
    function(choice)
      if not choice
        or choice.action == "later"
      then
        save_blocked = true
        restored = false

        vim.notify(
          "persist: restoration postponed; "
            .. "automatic saving is disabled for this session",
          vim.log.levels.INFO
        )

        return
      end

      if choice.action == "restore_all" then
        finish_restore(manifest)
        return
      end

      if choice.action == "discard_all_tabs" then
        local discarded_tab_indexes = {}

        for _, item in ipairs(items) do
          discarded_tab_indexes[
            item.tab_index
          ] = true
        end

        discard_tabs_and_restore(
          manifest,
          discarded_tab_indexes
        )

        return
      end

      review_scratches(
        items,
        1,
        {},
        function(discarded_tab_indexes)
          if not discarded_tab_indexes then
            save_blocked = true
            restored = false

            vim.notify(
              "persist: restoration stopped; "
                .. "automatic saving is disabled for this session",
              vim.log.levels.INFO
            )

            return
          end

          discard_tabs_and_restore(
            manifest,
            discarded_tab_indexes
          )
        end
      )
    end
  )
end

return M
