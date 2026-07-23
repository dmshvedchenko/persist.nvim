-- persist/scratch.lua
-- Scratch persistence layer: handles ONLY the text of [No Name] buffers.
-- Saves their contents to disk and loads them back. It knows nothing
-- about tabs, windows, or layouts; those belong to persist.session.
--
-- Storage: stdpath("state")/persist/scratch/<id>.txt
-- The id is stored in the buffer-local variable b:persist_id.

local api = vim.api

local M = {}

local counter = 0
local loaded = {} -- id -> bufnr; prevents duplicates on repeated loads

local function dir()
  local d = vim.fs.joinpath(vim.fn.stdpath("state"), "persist", "scratch")
  vim.fn.mkdir(d, "p")
  return d
end

local function path_for(id)
  return vim.fs.joinpath(dir(), id .. ".txt")
end

local function new_id()
  counter = counter + 1
  return string.format("%d-%d", os.time(), counter)
end

-- Is this a regular listed unnamed buffer (not help/qf/terminal)?
local function is_scratch(buf)
  return api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buflisted
    and vim.bo[buf].buftype == ""
    and api.nvim_buf_get_name(buf) == ""
end

local function has_content(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, "\n"):find("%S") ~= nil
end

-- Persist only modified [No Name] buffers with non-empty text,
-- as well as previously restored buffers (which already have b:persist_id).
function M.should_persist(buf)
  return is_scratch(buf)
    and (vim.bo[buf].modified or vim.b[buf].persist_id ~= nil)
    and has_content(buf)
end

-- Save the buffer text to disk.
---@return string|nil id nil if the buffer should not be persisted or saving failed
function M.save(buf)
  if not M.should_persist(buf) then
    return nil
  end

  local id = vim.b[buf].persist_id or new_id()
  vim.b[buf].persist_id = id

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.fn.writefile(lines, path_for(id)) ~= 0 then
    vim.notify("persist: failed to write scratch " .. id, vim.log.levels.WARN)
    return nil
  end

  return id
end

-- Create (or return an existing) buffer containing the note text.
-- If the file is missing (metadata mismatch), an empty buffer with the
-- same id is returned: the layout remains intact, but the text is empty.
---@return integer bufnr
function M.load(id)
  local cached = loaded[id]
  if cached and api.nvim_buf_is_valid(cached) then
    return cached -- one id maps to one buffer, even across multiple windows
  end

  local buf = api.nvim_create_buf(true, false)
  local file = path_for(id)

  if vim.fn.filereadable(file) == 1 then
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok then
      api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end
  end

  vim.b[buf].persist_id = id
  vim.bo[buf].modified = false
  loaded[id] = buf

  return buf
end

-- Read a snapshot without creating a Neovim buffer.
-- Used for the full preview shown before restoration.
---@param id string
---@return string[]|nil lines
function M.read(id)
  local file = path_for(id)

  if vim.fn.filereadable(file) ~= 1 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or type(lines) ~= "table" then
    return nil
  end

  return lines
end

-- Short note description for the initial menu.
---@param id string
---@param max_chars? integer
---@return string
function M.preview(id, max_chars)
  max_chars = max_chars or 90

  local lines = M.read(id)
  if not lines then
    return "(snapshot is missing)"
  end

  local parts = {}

  for _, line in ipairs(lines) do
    local cleaned = line:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned ~= "" then
      parts[#parts + 1] = cleaned
    end
    if #parts >= 3 then
      break
    end
  end

  local text = table.concat(parts, "  ·  ")

  if text == "" then
    return "(empty note)"
  end

  text = text:gsub("%s+", " ")

  if #text > max_chars then
    text = text:sub(1, max_chars - 3) .. "..."
  end

  return text
end

-- Permanently delete a snapshot.
---@param id string
---@return boolean
function M.delete(id)
  loaded[id] = nil

  local file = path_for(id)
  if vim.fn.filereadable(file) ~= 1 then
    return true
  end

  local ok, err = os.remove(file)
  if not ok then
    vim.notify(
      "persist: failed to delete scratch " .. id .. ": " .. tostring(err),
      vim.log.levels.WARN
    )
    return false
  end

  return true
end

-- Delete notes from disk that are absent from the latest manifest
-- (for example, a buffer closed with :bd during the session).
---@param keep table<string, boolean>
function M.cleanup(keep)
  for name, t in vim.fs.dir(dir()) do
    if t == "file" then
      local id = name:match("^(.+)%.txt$")
      if id and not keep[id] then
        os.remove(path_for(id))
      end
    end
  end
end

return M
