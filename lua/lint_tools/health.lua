local M = {}

function M.check()
  vim.health.start("lint-tools.nvim")
  if vim.fn.has("nvim-0.11") == 0 then
    vim.health.error("Neovim 0.11+ is required", { "Upgrade Neovim" })
    return
  end
  local issues = {}
  local function problem(level, message, advice)
    issues[#issues + 1] = { level = level, message = message, advice = advice }
  end
  local plugin = package.loaded.lint_tools
  local opts = plugin and plugin.config()
  if not opts or opts.enabled == false then
    vim.health.info("Not configured; linter checks skipped.")
    return
  end
  local selected, deferred = {}, false
  for _, names in pairs(opts.linters_by_ft) do
    for _, name in ipairs(names) do
      selected[name] = true
    end
  end
  for _, name in ipairs(opts.extra_linters) do
    selected[name] = true
  end
  for name in pairs(selected) do
    local loaded, builtin = pcall(require, "lint_tools.linters." .. name)
    local definition = vim.tbl_extend("force", loaded and builtin or {}, opts.linters[name] or {})
    local cmd = definition.cmd
    if type(cmd) == "function" or definition.condition then
      deferred = true
    elseif type(cmd) ~= "string" or vim.fn.executable(cmd) == 0 then
      problem(
        "warn",
        name .. ": executable or adapter unavailable (" .. tostring(cmd) .. "); linting may be unavailable.",
        { "Install/configure the linter; inspect :LintToolsInfo in its source buffer" }
      )
    end
  end
  if deferred and #issues == 0 then
    vim.health.info(
      "Static linter checks passed; project-dependent commands require a source buffer. Details: :LintToolsInfo"
    )
    return
  end

  table.sort(issues, function(a, b)
    if a.level ~= b.level then
      return a.level == "error"
    end
    return a.message < b.message
  end)
  for _, issue in ipairs(issues) do
    vim.health[issue.level](issue.message, issue.advice)
  end
  if #issues == 0 then
    vim.health.ok("Configured static linter commands are available.")
  end
  vim.health.info("Details: :LintToolsInfo")
end

return M
