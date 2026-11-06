local parsers = require("lint_tools.parsers")
return {
  cmd = "fish",
  args = { "--no-execute" },
  stream = "stderr",
  ok_exit_codes = parsers.with_findings,
  parser = function(output, ctx)
    local result = {}
    local lines = vim.split(output, "\n", { plain = true })
    for index, line in ipairs(lines) do
      local file, row, message = line:match("^(.*) %(line (%d+)%)%: (.+)")
      -- Older fish versions use "file (line N):" as well as "file (N):".
      if not row then
        file, row, message = line:match("^(.*) %((%d+)%)%: (.+)")
      end
      if row then
        local caret = (lines[index + 2] or ""):find("^", 1, true)
        local lnum, col = parsers.position(ctx, row, caret, "utf-32")
        result[#result + 1] =
          { filename = file, lnum = lnum, col = col, message = message, severity = vim.diagnostic.severity.ERROR }
      end
    end
    return result
  end,
}
