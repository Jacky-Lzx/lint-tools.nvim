local parsers = require("lint_tools.parsers")
return {
  cmd = "bash",
  stdin = true,
  args = { "-n", "-s" },
  stream = "stderr",
  ok_exit_codes = parsers.with_findings,
  parser = function(output, ctx)
    local result = {}
    for line in output:gmatch("[^\n]+") do
      local row, message = line:match("^bash: line (%d+): (.+)")
      if row then
        local lnum, col = parsers.position(ctx, row)
        result[#result + 1] = { lnum = lnum, col = col, message = message, severity = vim.diagnostic.severity.ERROR }
      end
    end
    return result
  end,
}
