local parsers = require("lint_tools.parsers")
return {
  cmd = "swiftlint",
  -- File input lets SwiftLint resolve nested configs and exclusions correctly.
  args = { "lint", "--quiet", "--force-exclude", "--reporter", "json" },
  ok_exit_codes = { 0, 2 },
  parser = function(output, ctx)
    local result = {}
    for _, item in ipairs(parsers.json(output)) do
      local lnum, col = parsers.position(ctx, item.line, item.character, "utf-16")
      result[#result + 1] = {
        filename = item.file,
        lnum = lnum,
        col = col,
        message = item.reason,
        code = item.rule_id,
        severity = item.severity == "Error" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
      }
    end
    return result
  end,
}
