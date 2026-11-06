local lint = require("lint_tools")
local diag = require("lint_tools.diagnostics")
local function wait(fn, label)
  assert(vim.wait(5000, fn, 5), label or "timed out")
end
local function buf(text, name)
  local b = vim.api.nvim_create_buf(true, false)
  if name then
    vim.api.nvim_buf_set_name(b, name)
  end
  vim.bo[b].filetype = "lua"
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { text or "abc" })
  return b
end
local a, b = buf(), buf()
local pending, starts = {}, {}
local original = require("lint_tools.runner").start
require("lint_tools.runner").start = function(command, opts, done)
  starts[#starts + 1] = { command = command, opts = opts }
  pending[#pending + 1] = done
  return { kill = function() end }
end
local parsed = 0
local function definition(message)
  return {
    cmd = "nvim",
    stdin = true,
    parser = function(_, ctx)
      parsed = parsed + 1
      return { { lnum = 0, col = 0, message = message or ctx.input } }
    end,
  }
end
local function setup(extra)
  local options = { events = {}, linters_by_ft = { lua = { "one" } }, linters = { one = definition() } }
  lint.setup(vim.tbl_extend("force", options, extra or {}))
  pending, starts = {}, {}
end
local function finish(index, output)
  pending[index](output or { code = 0, signal = 0, stdout = "", stderr = "" })
end
local function diagnostics(buffer, name)
  return vim.diagnostic.get(buffer, { namespace = diag.namespace(name or "one") })
end

setup({
  linters = {
    one = vim.tbl_extend("force", definition(), {
      cwd = function()
        return nil
      end,
      args = function()
        return nil
      end,
    }),
  },
})
lint.run({ bufnr = a })
assert(type(starts[1].opts.cwd) == "string" and #starts[1].command == 1)
finish(1)

setup({
  linters = {
    one = vim.tbl_extend("force", definition(), {
      parser = function(_, ctx)
        vim.api.nvim_buf_set_lines(ctx.bufnr, 0, -1, false, { "changed by parser" })
        return { { lnum = 0, message = "outdated" } }
      end,
    }),
  },
})
lint.run({ bufnr = a })
finish(1)
assert(lint.status(a)[1].status == "stale" and #diagnostics(a) == 0)
vim.api.nvim_buf_set_lines(a, 0, -1, false, { "abc" })

setup()
lint.run({ bufnr = a })
lint.run({ bufnr = a })
finish(2)
assert(#diagnostics(a) == 1)
local count = parsed
finish(1) -- cancellation is deliberately ignored by the fake process
assert(parsed == count and #diagnostics(a) == 1, "old reply overwrote new result")
assert(starts[1].opts.input == "abc\n")

setup()
lint.run({ bufnr = a })
vim.api.nvim_buf_set_lines(a, 0, -1, false, { "new" })
finish(1)
assert(lint.status(a)[1].status == "stale" and #diagnostics(a) == 0)

setup({ concurrency = 1 })
lint.run({ bufnr = a })
for _ = 1, 50 do
  lint.run({ bufnr = b })
end
assert(#starts == 1)
finish(1)
assert(#starts == 2, "queued save requests were not coalesced")
finish(2)
assert(lint.status(b)[1].status == "done")

setup({ concurrency = 1 })
lint.run({ bufnr = a })
lint.run({ bufnr = b })
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "changed in queue" })
finish(1)
assert(#starts == 1 and lint.status(b)[1].status == "stale")

setup({ linters_by_ft = { lua = { "one", "two" } }, linters = { one = definition("one"), two = definition("two") } })
lint.run({ bufnr = a })
finish(1)
finish(2)
assert(#diagnostics(a, "one") == 1 and #diagnostics(a, "two") == 1)
lint.run({ bufnr = a, linters = { "one" } })
finish(3, { code = 2, signal = 0, stdout = "", stderr = "bad config" })
assert(lint.status(a)[1].status == "error")
assert(#diagnostics(a, "one") == 0 and #diagnostics(a, "two") == 1)
lint.disable(a)
assert(#diagnostics(a, "two") == 0)
lint.run({ bufnr = a })
assert(lint.status(a)[1].status == "skipped")
lint.enable(a)
lint.run({ bufnr = a })
finish(4)
finish(5)

setup({ linters = { one = {
  cmd = "nvim",
  stdin = true,
  condition = function()
    return false
  end,
} } })
lint.run({ bufnr = a })
assert(#starts == 0 and lint.status(a)[1].reason == "condition returned false")
setup({ linters = { one = {
  cmd = "/no/such/linter",
  stdin = true,
  parser = function()
    return {}
  end,
} } })
lint.run({ bufnr = a })
assert(#starts == 0 and lint.status(a)[1].reason:find("executable not found"))
setup({ linters = { one = {
  cmd = "nvim",
  stdin = false,
  parser = function()
    return {}
  end,
} } })
lint.run({ bufnr = a })
assert(#starts == 0 and lint.status(a)[1].status == "skipped")

setup()
lint.run({ bufnr = a })
lint.setup({ events = {} })
finish(1)
assert(#diagnostics(a) == 0, "setup leaked previous generation")

setup()
local dir = vim.fn.tempname() .. " project"
vim.fn.mkdir(dir .. "/nested", "p")
vim.fn.mkdir(dir .. "/.git", "p")
local file = buf("abc", dir .. "/nested/test.lua")
lint.run({ bufnr = file })
assert(require("lint_tools.context").path(starts[1].opts.cwd) == require("lint_tools.context").path(dir))
vim.api.nvim_buf_set_name(file, dir .. "/renamed.lua")
finish(1)
assert(#diagnostics(file) == 0)
lint.run({ bufnr = file })
vim.api.nvim_buf_delete(file, { force = true })
finish(2)
assert(#lint.status(file) == 0)

setup({ linters = { one = vim.tbl_extend("force", definition(), { stdin = false }) } })
local saved_path = dir .. "/disk.lua"
vim.fn.writefile({ "abc" }, saved_path)
local saved = vim.fn.bufadd(saved_path)
vim.fn.bufload(saved)
vim.bo[saved].filetype = "lua"
lint.run({ bufnr = saved })
vim.fn.writefile({ "changed externally" }, saved_path)
finish(1)
assert(lint.status(saved)[1].status == "stale", "external file changes must invalidate file-input runs")

setup({
  linters = {
    one = {
      cmd = "nvim",
      stdin = true,
      parser = function()
        error("malformed output")
      end,
    },
  },
})
lint.run({ bufnr = a })
finish(1)
assert(lint.status(a)[1].status == "error" and lint.status(a)[1].reason:find("malformed output"))

local guarded = buf(string.rep("x", 100))
setup({ max_file_size = 10 })
lint.run({ bufnr = guarded })
assert(#starts == 0 and lint.status(guarded)[1].reason:find("max_file_size"))
local special = vim.api.nvim_create_buf(false, true)
lint.run({ bufnr = special, linters = "one" })
assert(#starts == 0)
assert(not pcall(lint.setup, { concurrency = 0 }))
assert(not pcall(lint.setup, { events = "BufWritePost" }))

-- Actual process boundaries: timeout, bounded output, spawn failure, and success.
require("lint_tools.runner").start = original
local function process(args, options)
  local result
  original(args, vim.tbl_extend("force", { timeout = 1000, max_output = 4096 }, options or {}), function(exit)
    result = exit
  end)
  wait(function()
    return result ~= nil
  end, "process completion")
  return result
end
local exit = process({ "sh", "-c", "printf ok" })
assert(exit.stdout == "ok" and exit.code == 0)
assert(process({ "sh", "-c", "sleep 1" }, { timeout = 30 }).error == "timeout")
assert(
  process({ "sh", "-c", "while :; do printf abcdefghijklmnop; done" }, { max_output = 100 }).error:find("max_output")
)
assert(process({ "/no/such/linter" }).error)

vim.fn.delete(dir, "rf")
print("Core: cancellation, races, queue, namespaces, lifecycle, guards and real process boundaries passed")
