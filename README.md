# lint-tools.nvim

External linter execution and diagnostics for Neovim 0.11+.

The plugin owns buffer check scheduling, bounded asynchronous processes and
diagnostic publication. Tool installation stays with your tool manager;
diagnostic rendering stays with `vim.diagnostic`.

Add this checkout to your runtimepath with your plugin manager, then configure:

```lua
require("lint_tools").setup({
  linters_by_ft = { python = { "ruff" }, sh = { "bash" } },
})
```

Checks run on `BufWritePost` by default. A replacement request cancels older
work for that buffer and provider. Results are published only if the input
snapshot still matches the buffer. File-input linters require a saved,
unmodified file. Diagnostics are cleared on cancellation, invalidation, failure
or skipping; one provider never clears another provider's namespace.

Use `:LintToolsRun`, `:LintToolsCancel`, `:LintToolsEnable`, `:LintToolsDisable`
and `:LintToolsInfo`. See `:help lint-tools` for the API and adapter contract.

Built-in adapters: bash, fish, ruff, swiftlint, gdlint, iverilog and codespell.
Install their executables separately. Use `:checkhealth lint-tools` to inspect
availability. `./tests/run.sh` checks asynchronous races, parsers, available real
tools and a rendered terminal save/edit workflow. Set `LINT_TOOLS_REQUIRE_REAL=1`
to require all seven executables.
