local M = {}

function M.json(output)
  local value = vim.json.decode(output)
  assert(type(value) == "table" and vim.islist(value), "expected a JSON array")
  return value
end

-- Tool rows/columns are one based. Convert from the adapter's declared encoding
-- using the captured text, including the EOF location after a missing newline.
function M.position(ctx, row, column, encoding)
  row, column = assert(tonumber(row), "missing row"), tonumber(column) or 1
  if row > #ctx.lines then
    return #ctx.lines - 1, #ctx.lines[#ctx.lines]
  end
  local lnum = math.max(0, row - 1)
  local line = ctx.lines[lnum + 1]
  local index = math.max(0, column - 1)
  if encoding and encoding ~= "bytes" then
    return lnum, vim.str_byteindex(line, encoding, index, false)
  end
  return lnum, math.min(index, #line)
end

function M.with_findings(code, entries)
  return code == 0 or (code > 0 and code < 128 and type(entries) == "table" and #entries > 0)
end

function M.errorformat(format, defaults)
  return function(output)
    local entries = vim.fn.getqflist({ lines = vim.split(output, "\n", { plain = true }), efm = format }).items
    local result = {}
    for _, item in ipairs(entries) do
      if item.valid == 1 then
        local d = vim.tbl_extend("force", defaults or {}, {
          lnum = math.max(0, item.lnum - 1),
          col = math.max(0, item.col - 1),
          message = item.text,
        })
        if item.bufnr > 0 then
          d.filename = vim.api.nvim_buf_get_name(item.bufnr)
        end
        result[#result + 1] = d
      end
    end
    return result
  end
end

return M
