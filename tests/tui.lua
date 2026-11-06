local lint = require("lint_tools")
local directory = assert(vim.env.LINT_TUI_DIR)
local function stage(name)
  vim.fn.writefile({ name }, directory .. "/stage")
end
local function frame()
  local rows = {}
  for row = 1, vim.o.lines do
    local cells = {}
    for col = 1, vim.o.columns do
      cells[#cells + 1] = vim.fn.screenstring(row, col)
    end
    rows[#rows + 1] = table.concat(cells)
  end
  return table.concat(rows, "\n")
end
local steps = {}
local index, started = 1, vim.uv.hrtime()
local function failure(message)
  vim.fn.writefile({ message, frame() }, directory .. "/failure")
  vim.cmd("cquit 1")
end
local function poll()
  local ok, done = pcall(steps[index])
  if not ok then
    failure(tostring(done))
    return
  end
  if done then
    index, started = index + 1, vim.uv.hrtime()
  end
  if index > #steps then
    vim.fn.writefile(
      { "PTY: rendered diagnostics, edit invalidation, burst saves, focus and mode passed" },
      directory .. "/result"
    )
    vim.cmd("qa!")
    return
  end
  if (vim.uv.hrtime() - started) / 1e9 > 10 then
    failure("stage timed out: " .. index)
    return
  end
  vim.defer_fn(poll, 10)
end
vim.o.swapfile, vim.o.shadafile = false, "NONE"
vim.o.laststatus, vim.o.showmode = 0, true
vim.diagnostic.config({ virtual_text = { prefix = "LINT" }, signs = true })
lint.setup({ linters_by_ft = { sh = { "bash" } } })
local filename = directory .. "/sample.sh"
vim.fn.writefile({ "if true; then", "  echo bad" }, filename)
vim.cmd.edit(vim.fn.fnameescape(filename))
vim.bo.filetype = "sh"
local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
steps[1] = function()
  vim.cmd.redraw()
  if not frame():find("if true; then", 1, true) then
    return
  end
  stage("save")
  return true
end
steps[2] = function()
  local state = lint.status(buf)[1]
  if not state or state.status ~= "done" then
    return
  end
  assert(state.count > 0)
  vim.cmd.redraw()
  local text = frame()
  if not text:find("LINT", 1, true) then
    return
  end
  vim.fn.writefile(vim.split(text, "\n"), directory .. "/diagnostic-frame")
  stage("edit")
  return true
end
steps[3] = function()
  if vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= "echo clean" then
    return
  end
  if #vim.diagnostic.get(buf) ~= 0 or vim.api.nvim_get_mode().mode ~= "n" then
    return
  end
  vim.cmd.redraw()
  if frame():find("LINT", 1, true) then
    return
  end
  stage("burst")
  return true
end
steps[4] = function()
  local state = lint.status(buf)[1]
  if not state or state.status ~= "done" or vim.bo.modified then
    return
  end
  assert(state.count == 0 and #vim.diagnostic.get(buf) == 0)
  assert(vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() == win)
  assert(vim.api.nvim_get_mode().mode == "n")
  vim.cmd.redraw()
  local text = frame()
  assert(text:find("echo clean", 1, true) and not text:find("LINT", 1, true))
  vim.fn.writefile(vim.split(text, "\n"), directory .. "/clean-frame")
  return true
end
vim.defer_fn(poll, 10)
