local parsers = require("lint_tools.parsers")
local ctx = { filename = "/tmp/file.py", lines = { '"😀你好"; print(undefined_name)', "teh teh" } }
local row, col = parsers.position(ctx, 1, 14, "utf-32")
assert(row == 0 and col == 20)
assert(select(2, parsers.position(ctx, 1, 15, "utf-16")) == col)
assert(select(2, parsers.position(ctx, 1, 21, "bytes")) == col)
row, col = parsers.position(ctx, 3, 1)
assert(row == 1 and col == 7, "EOF location")
assert(not pcall(parsers.json, "malformed"))
assert(not pcall(parsers.json, '{"not":"array"}'))
local ruff = require("lint_tools.linters.ruff")
local entries = ruff.parser(
  vim.json.encode({
    {
      code = "F821",
      severity = "error",
      message = "undefined",
      location = { row = 1, column = 14 },
      end_location = { row = 1, column = 28 },
    },
  }),
  ctx
)
assert(entries[1].col == 20 and entries[1].end_col == 34)
local swift = require("lint_tools.linters.swiftlint").parser(
  vim.json.encode({
    {
      file = ctx.filename,
      line = 1,
      character = 15,
      reason = "bad",
      rule_id = "rule",
      severity = "Error",
    },
  }),
  ctx
)
assert(swift[1].col == 20 and swift[1].code == "rule")
local code = require("lint_tools.linters.codespell").parser("2: teh ==> the\n", ctx)
assert(#code == 2 and code[1].col == 0 and code[2].col == 4)
local bash = require("lint_tools.linters.bash").parser("bash: line 3: syntax error: unexpected end of file\n", ctx)
assert(bash[1].lnum == 1 and bash[1].col == 7)
local fish =
  require("lint_tools.linters.fish").parser("/tmp/file.py (line 1): bad\ntext\n  ^^\n", { lines = { "text" } })
assert(fish[1].col == 2)
local gd = require("lint_tools.linters.gdlint").parser("/tmp/file.py:2: Error: Bad name (function-name)\n", ctx)
assert(gd[1].code == "function-name" and gd[1].severity == vim.diagnostic.severity.ERROR)
local iverilog =
  require("lint_tools.linters.iverilog").parser("/tmp/file.py:2: syntax error\n/tmp/file.py:2: warning: example\n", ctx)
assert(#iverilog == 2 and iverilog[2].severity == vim.diagnostic.severity.WARN)
local efm = parsers.errorformat("%f:%l:%c: %m")("/tmp/file.py:1:2: example")
assert(efm[1].lnum == 0 and efm[1].col == 1)

local b = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(b, vim.fn.tempname())
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "abc" })
local diagnostics = require("lint_tools.diagnostics")
local job =
  { name = "fixture", ctx = { bufnr = b, cwd = "/tmp", filename = vim.api.nvim_buf_get_name(b), lines = { "abc" } } }
local count, ignored = diagnostics.publish(job, {
  { lnum = 0, col = 0, message = "local" },
  { filename = "other.py", lnum = 100, message = "included file" },
})
assert(count == 1 and ignored == 1, "foreign-file result must not be attributed to input")
assert(not pcall(diagnostics.publish, job, { { lnum = 0, col = 99, message = "invalid" } }))
print("Adapters: Unicode, EOF, structured/text formats, ranges and foreign-file isolation passed")
