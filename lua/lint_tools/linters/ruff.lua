local parsers = require("lint_tools.parsers")
local severities = { error = vim.diagnostic.severity.ERROR, warning = vim.diagnostic.severity.WARN }
return {
  cmd = "ruff",
  stdin = true,
  args = function(ctx)
    return {
      "check",
      "--force-exclude",
      "--quiet",
      "--stdin-filename",
      ctx.filename ~= "" and ctx.filename or "stdin.py",
      "--no-fix",
      "--output-format",
      "json",
      "-",
    }
  end,
  ok_exit_codes = { 0, 1 },
  parser = function(output, ctx)
    local result = {}
    for _, item in ipairs(parsers.json(output)) do
      local row, col = parsers.position(ctx, item.location.row, item.location.column, "utf-32")
      local end_row, end_col = parsers.position(ctx, item.end_location.row, item.end_location.column, "utf-32")
      result[#result + 1] = {
        lnum = row,
        col = col,
        end_lnum = end_row,
        end_col = end_col,
        message = item.message,
        code = item.code,
        severity = severities[item.severity]
          or (item.code == "F821" or item.code == "E999") and vim.diagnostic.severity.ERROR
          or vim.diagnostic.severity.WARN,
      }
    end
    return result
  end,
}
