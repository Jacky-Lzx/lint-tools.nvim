local parsers = require("lint_tools.parsers")
return {
  cmd = "gdlint",
  stream = "stderr",
  ok_exit_codes = parsers.with_findings,
  parser = function(output, ctx)
    local result = {}
    for line in output:gmatch("[^\n]+") do
      local file, row, level, message = line:match("^(.*):(%d+): (%a+): (.+)")
      if row then
        local lnum, col = parsers.position(ctx, row)
        local code = message:match("%(([%w-]+)%)$")
        result[#result + 1] = {
          filename = file,
          lnum = lnum,
          col = col,
          message = message,
          code = code,
          severity = level == "Error" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
        }
      end
    end
    return result
  end,
}
