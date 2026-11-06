local parsers = require("lint_tools.parsers")
return {
  cmd = "codespell",
  stdin = true,
  args = { "--stdin-single-line", "-" },
  ok_exit_codes = parsers.with_findings,
  parser = function(output, ctx)
    local result = {}
    for line in output:gmatch("[^\n]+") do
      local row, word, suggestion = line:match("^(%d+): (.-) ==> (.+)")
      if row then
        local lnum = tonumber(row) - 1
        local text = assert(ctx.lines[lnum + 1], "codespell row outside input")
        local start = 1
        while start <= #text do
          local first, last = text:find(word, start, true)
          if not first then
            break
          end
          result[#result + 1] = {
            lnum = lnum,
            col = first - 1,
            end_col = last,
            message = word .. " ==> " .. suggestion,
            severity = vim.diagnostic.severity.INFO,
          }
          start = last + 1
        end
      end
    end
    return result
  end,
}
