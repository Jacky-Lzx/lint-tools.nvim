local parsers = require("lint_tools.parsers")
return {
  cmd = "iverilog",
  args = { "-g2012", "-Wall", "-y", ".", "-o", "/dev/null" },
  stream = "both",
  ok_exit_codes = parsers.with_findings,
  parser = function(output, ctx)
    local result = {}
    for line in output:gmatch("[^\n]+") do
      local file, row, message = line:match("^(.*):(%d+):%s*(.+)")
      if row then
        local level = message:match("^(%a+):")
        local lnum, col = parsers.position(ctx, row)
        result[#result + 1] = {
          filename = file,
          lnum = lnum,
          col = col,
          message = message,
          severity = level == "warning" and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
        }
      end
    end
    return result
  end,
}
