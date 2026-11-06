local M = {}

-- Always deliver once on the main loop, including spawn failures. Output is
-- bounded while reading, rather than after vim.system has collected it all.
function M.start(command, opts, done)
  local output, size, failure = { stdout = {}, stderr = {} }, 0
  local process
  local function read(stream)
    return function(err, data)
      if err then
        failure = failure or tostring(err)
      end
      if not data or failure then
        return
      end
      size = size + #data
      if size > opts.max_output then
        failure = "output exceeds max_output"
        vim.schedule(function()
          if process then
            pcall(process.kill, process, 9)
          end
        end)
      else
        output[stream][#output[stream] + 1] = data
      end
    end
  end
  local ok, result = pcall(vim.system, command, {
    cwd = opts.cwd,
    env = opts.env,
    stdin = opts.input,
    timeout = opts.timeout,
    text = true,
    stdout = read("stdout"),
    stderr = read("stderr"),
  }, function(exit)
    vim.schedule(function()
      done({
        code = exit.code,
        signal = exit.signal,
        stdout = table.concat(output.stdout),
        stderr = table.concat(output.stderr),
        error = failure or (exit.code == 124 and "timeout" or nil),
      })
    end)
  end)
  if not ok then
    vim.schedule(function()
      done({ error = tostring(result), stdout = "", stderr = "" })
    end)
    return nil
  end
  process = result
  return process
end

return M
