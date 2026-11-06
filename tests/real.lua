local lint = require("lint_tools")
local namespace = require("lint_tools.diagnostics").namespace
local root = vim.fn.tempname() .. " lint project"
vim.fn.mkdir(root, "p")
vim.fn.mkdir(root .. "/.git", "p")
local tested = 0
local function create(name, ft, lines)
  local path = root .. "/" .. name
  vim.fn.writefile(lines, path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = ft
  return buf
end
local function wait(buf)
  assert(
    vim.wait(15000, function()
      local state = lint.status(buf)[1]
      return state and state.status ~= "queued" and state.status ~= "running"
    end, 10),
    "real linter timed out"
  )
  local state = lint.status(buf)[1]
  assert(state.status == "done", vim.inspect(state))
  return vim.diagnostic.get(buf, { namespace = namespace(state.name) })
end
local fixtures = {
  { "bash", "bad.sh", "sh", { "if true; then", " echo hello" } },
  { "fish", "bad.fish", "fish", { "if true", " echo hello" } },
  { "ruff", "bad.py", "python", { '"😀你好"; print(undefined_name)' } },
  { "swiftlint", "bad.swift", "swift", { 'let greeting = "😀你好"; let x = greeting' } },
  { "gdlint", "bad.gd", "gdscript", { "extends Node", "", "func BAD():", "    pass" } },
  { "iverilog", "bad.v", "verilog", { "module bad;", "wire a = ;", "endmodule" } },
  { "codespell", "bad.txt", "text", { "你好 teh word" } },
}
local current = vim.api.nvim_get_current_buf()
for _, fixture in ipairs(fixtures) do
  local name, filename, ft, lines = unpack(fixture)
  if vim.fn.executable(name) == 1 then
    local overrides = name == "swiftlint"
        and { swiftlint = { args = { "lint", "--quiet", "--force-exclude", "--reporter", "json", "--no-cache" } } }
      or {}
    lint.setup({ events = {}, linters_by_ft = { [ft] = { name } }, linters = overrides })
    local buf = create(filename, ft, lines)
    lint.run({ bufnr = buf })
    local entries = wait(buf)
    assert(#entries > 0, name .. " produced no diagnostic")
    if name == "ruff" then
      local first = assert(lines[1]:find("undefined_name", 1, true))
      assert(
        entries[1].col == first - 1 and entries[1].end_col == first - 1 + #"undefined_name",
        "ruff Unicode byte range"
      )
    elseif name == "swiftlint" then
      local found = false
      for _, entry in ipairs(entries) do
        if entry.code == "identifier_name" then
          assert(entry.col == lines[1]:find("x =", 1, true) - 1, "SwiftLint UTF-16 column")
          found = true
        end
      end
      assert(found)
    elseif name == "codespell" then
      assert(entries[1].col == #"你好 ")
    end
    assert(vim.api.nvim_get_current_buf() == current, "background lint changed focus")
    tested = tested + 1
    print("Real " .. name .. ": findings and ranges passed")
  else
    assert(not vim.env.LINT_TOOLS_REQUIRE_REAL, "Missing required tool: " .. name)
    print("Skip unavailable tool: " .. name)
  end
end

if vim.fn.executable("bash") == 1 then
  lint.setup({ linters_by_ft = { sh = { "bash" } } })
  local buf = create("save.sh", "sh", { "if true; then" })
  vim.api.nvim_buf_call(buf, function()
    vim.cmd.write()
  end)
  assert(#wait(buf) > 0, "save did not run linter")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "echo ok" })
  vim.api.nvim_buf_call(buf, function()
    vim.cmd.write()
  end)
  assert(#wait(buf) == 0, "clean result did not clear diagnostics")
end

-- Two projects must discover their own SwiftLint configs without global caching.
if vim.fn.executable("swiftlint") == 1 then
  vim.fn.mkdir(root .. "/first", "p")
  vim.fn.mkdir(root .. "/second", "p")
  vim.fn.writefile({ "disabled_rules:", "  - identifier_name" }, root .. "/first/.swiftlint.yml")
  lint.setup({
    events = {},
    linters_by_ft = { swift = { "swiftlint" } },
    linters = {
      swiftlint = { args = { "lint", "--quiet", "--force-exclude", "--reporter", "json", "--no-cache" } },
    },
  })
  for _, dir in ipairs({ "first", "second" }) do
    local buf = create(dir .. "/sample.swift", "swift", { "let x = 1" })
    lint.run({ bufnr = buf })
    local entries, found = wait(buf), false
    for _, item in ipairs(entries) do
      found = found or item.code == "identifier_name"
    end
    assert(found == (dir == "second"), "SwiftLint config leaked between projects")
  end
  print("Real SwiftLint: independent project configs passed")
end
lint.disable()
vim.fn.delete(root, "rf")
print("Real tool checks passed: " .. tested)
