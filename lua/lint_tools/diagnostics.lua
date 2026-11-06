local M = {}
local namespaces = {}

function M.namespace(name)
  if not namespaces[name] then
    namespaces[name] = vim.api.nvim_create_namespace("lint-tools/" .. name)
  end
  return namespaces[name]
end

function M.clear(buf, name)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.diagnostic.reset(M.namespace(name), buf)
  end
end

function M.publish(job, entries)
  assert(type(entries) == "table" and vim.islist(entries), "parser must return a diagnostic list")
  local result, ignored = {}, 0
  local path = require("lint_tools.context").path
  for _, item in ipairs(entries) do
    local d = vim.deepcopy(item)
    local filename = d.filename
    if filename and not vim.startswith(filename, "/") and not filename:match("^%a:[/\\]") then
      filename = vim.fs.joinpath(job.ctx.cwd, filename)
    end
    if (filename and path(filename) ~= path(job.ctx.filename)) or (d.bufnr and d.bufnr ~= job.ctx.bufnr) then
      -- Buffer checks never load or overwrite diagnostics in included files.
      ignored = ignored + 1
    else
      assert(type(d.message) == "string" and d.message ~= "", "diagnostic requires message")
      assert(type(d.lnum) == "number" and d.lnum >= 0 and d.lnum % 1 == 0, "invalid diagnostic row")
      assert(d.lnum < #job.ctx.lines, "diagnostic outside input snapshot")
      d.col = d.col or 0
      assert(type(d.col) == "number" and d.col >= 0 and d.col % 1 == 0, "invalid diagnostic column")
      assert(d.col <= #job.ctx.lines[d.lnum + 1], "diagnostic column outside input snapshot")
      if d.end_lnum or d.end_col then
        d.end_lnum, d.end_col = d.end_lnum or d.lnum, d.end_col or d.col
        assert(d.end_lnum >= d.lnum and d.end_lnum < #job.ctx.lines, "invalid diagnostic end row")
        assert(d.end_col >= 0 and d.end_col <= #job.ctx.lines[d.end_lnum + 1], "invalid diagnostic end column")
        assert(d.end_lnum > d.lnum or d.end_col >= d.col, "inverted diagnostic range")
      end
      d.source, d.bufnr, d.filename = d.source or job.name, nil, nil
      d.severity = d.severity or vim.diagnostic.severity.WARN
      result[#result + 1] = d
    end
  end
  vim.diagnostic.set(M.namespace(job.name), job.ctx.bufnr, result)
  return #result, ignored
end

return M
