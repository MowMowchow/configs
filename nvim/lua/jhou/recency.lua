local M = {}

-- In-memory storage: { [filepath] = timestamp }
M.visited = {}
M.max_entries = 50

function M.record_visit(filepath)
  -- Skip empty, terminal, and special buffers
  if filepath == "" or filepath:match("^term://") or filepath:match("^fugitive://") then
    return
  end
  M.visited[filepath] = os.time()
  M.prune()
end

function M.prune()
  local entries = {}
  for path, time in pairs(M.visited) do
    table.insert(entries, { path = path, time = time })
  end
  table.sort(entries, function(a, b) return a.time > b.time end)

  if #entries > M.max_entries then
    M.visited = {}
    for i = 1, M.max_entries do
      M.visited[entries[i].path] = entries[i].time
    end
  end
end

function M.get_sorted()
  local entries = {}
  for path, time in pairs(M.visited) do
    if vim.fn.filereadable(path) == 1 then
      table.insert(entries, { value = path, time = time })
    end
  end
  table.sort(entries, function(a, b) return a.time > b.time end)
  return entries
end

return M
