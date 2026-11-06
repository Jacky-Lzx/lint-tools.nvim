local M = {}

function M.check()
  vim.health.start("lint-tools")
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim 0.11+ available")
  else
    vim.health.error("Neovim 0.11+ required")
  end
  local ok, opts = pcall(require("lint_tools").config)
  if not ok then
    vim.health.warn("setup() has not been called")
    return
  end
  local selected = {}
  for _, names in pairs(opts.linters_by_ft) do
    for _, name in ipairs(names) do
      selected[name] = true
    end
  end
  for _, name in ipairs(opts.extra_linters) do
    selected[name] = true
  end
  for _, name in ipairs(vim.tbl_keys(selected)) do
    local loaded, builtin = pcall(require, "lint_tools.linters." .. name)
    local definition = vim.tbl_extend("force", loaded and builtin or {}, opts.linters[name] or {})
    local cmd = definition.cmd
    if type(cmd) == "function" then
      vim.health.info(name .. ": dynamic command; inspect :LintToolsInfo after running")
    elseif type(cmd) == "string" and vim.fn.executable(cmd) == 1 then
      vim.health.ok(name .. ": " .. vim.fn.exepath(cmd))
    else
      vim.health.warn(name .. ": executable or adapter unavailable (" .. tostring(cmd) .. ")")
    end
  end
  for _, item in ipairs(require("lint_tools").status()) do
    if item.status == "error" then
      vim.health.warn(item.name .. " in buffer " .. item.bufnr .. ": " .. item.reason)
    end
  end
end

return M
