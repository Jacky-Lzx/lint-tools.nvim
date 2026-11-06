local M = {}

function M.path(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

function M.stamp(filename)
  local stat = vim.uv.fs_stat(filename)
  return stat and table.concat({ stat.size, stat.mtime.sec, stat.mtime.nsec, stat.ctime.sec, stat.ctime.nsec }, ":")
end

function M.capture(buf, opts)
  if not vim.api.nvim_buf_is_loaded(buf) then
    return nil, "buffer is not loaded"
  end
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "" then
    return nil, "special buffer or empty filetype"
  end
  local size = vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
  if size > opts.max_file_size then
    return nil, "file exceeds max_file_size"
  end
  local filename = vim.api.nvim_buf_get_name(buf)
  local dir = filename ~= "" and vim.fs.dirname(filename) or vim.uv.cwd()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return {
    bufnr = buf,
    filename = filename,
    filetype = vim.bo[buf].filetype,
    changedtick = vim.api.nvim_buf_get_changedtick(buf),
    modified = vim.bo[buf].modified,
    lines = lines,
    input = table.concat(lines, "\n") .. (vim.bo[buf].endofline and "\n" or ""),
    root = vim.fs.root(dir, opts.root_markers) or dir,
  }
end

function M.valid(ctx)
  return vim.api.nvim_buf_is_loaded(ctx.bufnr)
    and vim.api.nvim_buf_get_changedtick(ctx.bufnr) == ctx.changedtick
    and vim.api.nvim_buf_get_name(ctx.bufnr) == ctx.filename
    and vim.bo[ctx.bufnr].filetype == ctx.filetype
    and (not ctx.file_stamp or M.stamp(ctx.filename) == ctx.file_stamp)
end

return M
