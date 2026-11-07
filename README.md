# lint-tools.nvim

Asynchronous external linters with native Neovim diagnostics.

## Features

- Schedule checks on save and cancel superseded work.
- Publish diagnostics only for the input snapshot that was checked.
- Keep each provider isolated in its own diagnostic namespace.

## Requirements

Neovim **0.11+**. Install linter executables separately. No diagnostic UI or tool installer is required.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/lint-tools.nvim",
  main = "lint_tools",
  opts = { linters_by_ft = { python = { "ruff" } } },
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("lint_tools").setup({ linters_by_ft = { python = { "ruff" } } })
```

## Usage

```vim
:LintToolsRun
:LintToolsInfo
```

## Documentation

- [Complete reference](doc/lint-tools.txt) — `:help lint-tools`.
- Diagnose availability with `:checkhealth lint_tools`.

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.

[License](LICENSE).
