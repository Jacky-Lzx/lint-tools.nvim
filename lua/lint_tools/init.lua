local M = {}
local engine
local function current()
  assert(engine, "Call require('lint_tools').setup() first")
  return engine
end
local function buffer(buf)
  return (not buf or buf == 0) and vim.api.nvim_get_current_buf() or buf
end

function M.run(opts)
  opts = opts or {}
  local names = opts.linters
  if type(names) == "string" then
    names = { names }
  end
  if names then
    assert(type(names) == "table" and vim.islist(names), "linters must be a list")
    for _, name in ipairs(names) do
      assert(type(name) == "string" and name:match("^[%w_-]+$"), "invalid linter name")
    end
  end
  current():run(buffer(opts.bufnr), names)
end

function M.cancel(buf)
  if engine then
    engine:cancel(buffer(buf))
  end
end

function M.disable(buf)
  if not engine then
    return
  end
  local e = current()
  if buf then
    buf = buffer(buf)
    e.disabled[buf] = true
  else
    e.enabled = false
  end
  e:cancel(buf, "lint disabled")
end

function M.enable(buf)
  if not engine then
    M.setup()
  end
  local e = current()
  if buf then
    e.disabled[buffer(buf)] = nil
  else
    e.enabled = true
  end
end

function M.status(buf)
  return engine and engine:status(buf == 0 and buffer(0) or buf) or {}
end

function M.config()
  return engine and vim.deepcopy(engine.opts) or nil
end

function M.info(buf)
  local lines = { "lint-tools: " .. (current().enabled and "enabled" or "disabled") }
  if current().disabled[buffer(buf)] then
    lines[#lines + 1] = "Buffer override: disabled"
  end
  local ft = vim.bo[buffer(buf)].filetype
  lines[#lines + 1] = "Selected: " .. table.concat(current().opts.linters_by_ft[ft] or {}, ", ")
  lines[#lines + 1] = "Extra: " .. table.concat(current().opts.extra_linters, ", ")
  for _, item in ipairs(M.status(buffer(buf))) do
    lines[#lines + 1] = ("%s: %s%s"):format(item.name, item.status, item.reason and (" — " .. item.reason) or "")
    if item.command then
      lines[#lines + 1] = "  argv: " .. vim.inspect(item.command)
      lines[#lines + 1] = "  cwd: " .. tostring(item.cwd)
    end
    if item.duration_ms then
      lines[#lines + 1] = ("  %d ms; exit %s; diagnostics %s; other-file results ignored %s"):format(
        item.duration_ms,
        tostring(item.exit_code),
        tostring(item.count or 0),
        tostring(item.ignored_files or 0)
      )
    end
    if item.status == "error" and item.stderr and item.stderr ~= "" then
      lines[#lines + 1] = "  stderr: " .. item.stderr
    end
  end
  local text = table.concat(lines, "\n")
  vim.notify(text, vim.log.levels.INFO, { title = "LintToolsInfo" })
  return text
end

function M.dispose()
  if engine then
    engine:cancel(nil, "disposed")
  end
  engine = nil
  pcall(vim.api.nvim_del_augroup_by_name, "LintTools")
  for _, name in ipairs({ "LintToolsRun", "LintToolsCancel", "LintToolsInfo", "LintToolsEnable", "LintToolsDisable" }) do
    require("lint_tools.user_command").delete(name)
  end
end

function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "lint-tools.nvim: setup expects a table")
  opts = vim.deepcopy(opts or {})
  local normalized = require("lint_tools.config").normalize(opts)
  if engine then
    engine:cancel(nil, "setup replaced")
  end
  engine = require("lint_tools.scheduler").new(normalized)
  local group = vim.api.nvim_create_augroup("LintTools", { clear = true })
  if #normalized.events > 0 then
    vim.api.nvim_create_autocmd(normalized.events, {
      group = group,
      callback = function(ev)
        M.run({ bufnr = ev.buf })
      end,
    })
  end
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "BufFilePost", "FileType" }, {
    group = group,
    callback = function(ev)
      engine:cancel(ev.buf, "buffer changed")
    end,
  })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      engine:cancel(ev.buf, "buffer unloaded")
      engine.states[ev.buf], engine.disabled[ev.buf] = nil, nil
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      engine:cancel(nil, "editor exit")
    end,
  })
  local commands = {
    LintToolsRun = function()
      M.run()
    end,
    LintToolsCancel = function()
      M.cancel()
    end,
    LintToolsEnable = function()
      M.enable()
    end,
    LintToolsDisable = function()
      M.disable()
    end,
    LintToolsInfo = function()
      M.info()
    end,
  }
  for name, fn in pairs(commands) do
    require("lint_tools.user_command").create(name, fn, { desc = name, force = true })
  end
end

return M
