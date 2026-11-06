local M = {}
M.defaults = {
  enabled = true,
  events = { "BufWritePost" },
  concurrency = 2,
  timeout = 10000,
  max_file_size = 1024 * 1024,
  max_output = 1024 * 1024,
  root_markers = { ".git", "pyproject.toml", "Package.swift", "project.godot", "Cargo.toml" },
  linters_by_ft = {},
  linters = {},
  extra_linters = {},
}

local function names(value, label)
  assert(type(value) == "table" and vim.islist(value), label .. " must be a list")
  for _, name in ipairs(value) do
    assert(type(name) == "string" and name:match("^[%w_-]+$"), label .. ": invalid name")
  end
end

function M.normalize(opts)
  opts = opts or {}
  for key in pairs(opts) do
    assert(M.defaults[key] ~= nil, "Unknown lint-tools option: " .. key)
  end
  local result = vim.deepcopy(M.defaults)
  -- Lists replace defaults, including an explicitly empty event list.
  for key, value in pairs(opts) do
    result[key] = vim.deepcopy(value)
  end
  assert(type(result.enabled) == "boolean", "enabled must be boolean")
  for _, key in ipairs({ "concurrency", "timeout", "max_file_size", "max_output" }) do
    assert(
      type(result[key]) == "number" and result[key] > 0 and result[key] % 1 == 0,
      key .. " must be positive integer"
    )
  end
  names(result.extra_linters, "extra_linters")
  for _, key in ipairs({ "events", "root_markers" }) do
    assert(type(result[key]) == "table" and vim.islist(result[key]), key .. " must be a list")
    for _, value in ipairs(result[key]) do
      assert(type(value) == "string" and value ~= "", key .. " must contain strings")
    end
  end
  assert(type(result.linters_by_ft) == "table", "linters_by_ft must be a table")
  for ft, list in pairs(result.linters_by_ft) do
    assert(type(ft) == "string", "filetype must be a string")
    names(list, "linters_by_ft." .. ft)
  end
  assert(type(result.linters) == "table", "linters must be a table")
  for name, definition in pairs(result.linters) do
    names({ name }, "linters")
    assert(type(definition) == "table", "linter definition must be a table: " .. name)
  end
  return result
end

return M
