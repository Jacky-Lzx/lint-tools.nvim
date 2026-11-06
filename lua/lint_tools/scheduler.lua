local M = {}
local context = require("lint_tools.context")
local diagnostics = require("lint_tools.diagnostics")
local runner = require("lint_tools.runner")

function M.new(opts)
  local self = { opts = opts, states = {}, queue = {}, active = 0, disabled = {}, enabled = opts.enabled }

  local function clear(job, status, reason)
    job.status, job.reason = status, reason
    job.count, job.ignored_files = 0, 0
    diagnostics.clear(job.ctx.bufnr, job.name)
  end

  local function cancel(job, status, reason)
    if job.status == "queued" then
      job.ctx.lines, job.ctx.input, job.definition = nil, nil, nil
    end
    if job.status == "running" or job.status == "queued" then
      job.cancelled = true
      if job.process then
        pcall(job.process.kill, job.process, 9)
      end
    end
    clear(job, status or "cancelled", reason)
  end

  local pump
  local function complete(job, exit)
    self.active = self.active - 1
    job.process = nil
    job.duration_ms = math.floor((vim.uv.hrtime() - job.started) / 1e6)
    if not job.cancelled then
      if not context.valid(job.ctx) then
        clear(job, "stale", "buffer changed during check")
      else
        local ok, err = pcall(function()
          assert(not exit.error, exit.error)
          assert(exit.signal == 0, "process terminated by signal " .. tostring(exit.signal))
          local stream = job.definition.stream or "stdout"
          local output = stream == "both" and (exit.stdout .. "\n" .. exit.stderr) or exit[stream]
          local entries = job.definition.parser(output, job.ctx)
          -- User parsers may invoke editor APIs or replace this request.
          if job.cancelled then
            return
          end
          if not context.valid(job.ctx) then
            clear(job, "stale", "buffer changed during parsing")
            return
          end
          local codes = job.definition.ok_exit_codes or { 0 }
          local accepted
          if type(codes) == "function" then
            accepted = codes(exit.code, entries)
          else
            accepted = vim.list_contains(codes, exit.code)
          end
          assert(accepted, "unexpected exit code " .. tostring(exit.code))
          job.count, job.ignored_files = diagnostics.publish(job, entries)
        end)
        job.exit_code = exit.code
        -- Keep failure context bounded and available through :LintToolsInfo.
        job.stderr = exit.stderr:sub(1, 4096)
        if not job.cancelled then
          if not ok then
            clear(job, "error", tostring(err))
          elseif job.status == "running" then
            job.status, job.reason = "done", nil
          end
        end
      end
    end
    -- Input snapshots and adapter closures are needed only while running.
    job.ctx.lines, job.ctx.input, job.definition = nil, nil, nil
    pump()
  end

  pump = function()
    while self.active < opts.concurrency and #self.queue > 0 do
      local job = table.remove(self.queue, 1)
      if not job.cancelled then
        if not context.valid(job.ctx) then
          clear(job, "stale", "buffer changed while queued")
          job.ctx.lines, job.ctx.input, job.definition = nil, nil, nil
        else
          job.status, job.started = "running", vim.uv.hrtime()
          self.active = self.active + 1
          job.process = runner.start(job.command, {
            cwd = job.ctx.cwd,
            env = job.definition.env,
            input = job.definition.stdin and job.ctx.input or nil,
            timeout = job.definition.timeout or opts.timeout,
            max_output = opts.max_output,
          }, function(exit)
            complete(job, exit)
          end)
        end
      end
    end
  end

  function self:cancel(buf, reason)
    for b, jobs in pairs(self.states) do
      if not buf or buf == b then
        for _, job in pairs(jobs) do
          cancel(job, "cancelled", reason or "cancelled by user")
        end
      end
    end
    -- Remove cancelled snapshots immediately; running jobs release on exit.
    local queue = {}
    for _, job in ipairs(self.queue) do
      if not job.cancelled then
        queue[#queue + 1] = job
      end
    end
    self.queue = queue
  end

  function self:run(buf, names)
    local snapshot, reason = context.capture(buf, opts)
    self.states[buf] = self.states[buf] or {}
    if not names then
      names = {}
      local seen = {}
      local ft = vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype or ""
      for _, list in ipairs({ opts.linters_by_ft[ft] or {}, opts.extra_linters }) do
        for _, name in ipairs(list) do
          if not seen[name] then
            seen[name], names[#names + 1] = true, name
          end
        end
      end
      -- Clear providers removed by changed configuration/filetype selection.
      for name, job in pairs(self.states[buf]) do
        if not seen[name] then
          cancel(job, "skipped", "not selected")
        end
      end
    end
    for _, name in ipairs(names) do
      local previous = self.states[buf][name]
      if previous then
        cancel(previous, "cancelled", "superseded")
      end
      local ctx = snapshot and vim.deepcopy(snapshot) or { bufnr = buf }
      local job = { name = name, ctx = ctx, status = "queued" }
      self.states[buf][name] = job
      if not snapshot or not self.enabled or self.disabled[buf] then
        clear(job, "skipped", reason or "lint is disabled")
      else
        local ok, err = pcall(function()
          local builtin_ok, builtin = pcall(require, "lint_tools.linters." .. name)
          local override = opts.linters[name]
          assert(builtin_ok or override, "unknown linter: " .. name)
          local definition = vim.tbl_extend("force", builtin_ok and builtin or {}, override or {})
          if definition.condition and not definition.condition(ctx) then
            clear(job, "skipped", "condition returned false")
            return
          end
          if definition.prepare then
            definition = vim.tbl_extend("force", definition, definition.prepare(ctx))
          end
          assert(type(definition.parser) == "function", "missing parser")
          assert(definition.stdin == nil or type(definition.stdin) == "boolean", "stdin must be boolean")
          assert(
            definition.timeout == nil or (type(definition.timeout) == "number" and definition.timeout > 0),
            "invalid timeout"
          )
          assert(
            definition.stream == nil or vim.list_contains({ "stdout", "stderr", "both" }, definition.stream),
            "invalid stream"
          )
          if not definition.stdin and (ctx.filename == "" or ctx.modified) then
            clear(job, "skipped", "linter requires a saved, unmodified file")
            return
          end
          if not definition.stdin then
            ctx.file_stamp = context.stamp(ctx.filename)
            assert(ctx.file_stamp, "input file is unavailable")
          end
          local function evaluate(value)
            if type(value) == "function" then
              return value(ctx)
            end
            return value
          end
          ctx.cwd = evaluate(definition.cwd) or ctx.root
          assert(type(ctx.cwd) == "string" and ctx.cwd ~= "", "cwd must be a directory string")
          local command = evaluate(definition.cmd)
          assert(type(command) == "string" and command ~= "", "missing command")
          if vim.fn.executable(command) ~= 1 then
            clear(job, "skipped", "executable not found: " .. command)
            return
          end
          job.command = { command }
          local args = evaluate(definition.args) or {}
          assert(type(args) == "table" and vim.islist(args), "args must be a list")
          for _, arg in ipairs(args) do
            local value = evaluate(arg)
            assert(type(value) == "string", "arguments must be strings")
            job.command[#job.command + 1] = value
          end
          if not definition.stdin and definition.append_fname ~= false then
            job.command[#job.command + 1] = ctx.filename
          end
          job.definition = definition
          self.queue[#self.queue + 1] = job
        end)
        if not ok then
          clear(job, "error", tostring(err))
        end
      end
      if job.status ~= "queued" then
        job.ctx.lines, job.ctx.input, job.definition = nil, nil, nil
      end
    end
    -- A burst of saves replaces queued work rather than retaining snapshots.
    local queue = {}
    for _, job in ipairs(self.queue) do
      if not job.cancelled then
        queue[#queue + 1] = job
      end
    end
    self.queue = queue
    pump()
  end

  function self:status(buf)
    local result = {}
    for b, jobs in pairs(self.states) do
      if not buf or buf == b then
        for _, job in pairs(jobs) do
          result[#result + 1] = {
            bufnr = b,
            name = job.name,
            status = job.status,
            reason = job.reason,
            command = vim.deepcopy(job.command),
            cwd = job.ctx.cwd,
            duration_ms = job.duration_ms,
            exit_code = job.exit_code,
            stderr = job.stderr,
            count = job.count,
            ignored_files = job.ignored_files,
          }
        end
      end
    end
    table.sort(result, function(a, b)
      return a.bufnr == b.bufnr and a.name < b.name or a.bufnr < b.bufnr
    end)
    return result
  end

  return self
end

return M
