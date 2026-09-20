local M = {}
local api = vim.api
local map = vim.keymap.set
local state = require "floaterm.state"
local volt_redraw = require("volt").redraw
local shell = vim.o.shell

M.convert_buf2term = function(cmd)
  if cmd then
    cmd = type(cmd) == "function" and cmd() or cmd
    cmd = { shell, "-c", cmd .. "; " .. shell }
  else
    cmd = { shell }
  end
  vim.fn.jobstart(cmd, { term = true })
end

M.new_term = function(opts)
  local defaults = {
    buf = api.nvim_create_buf(false, true),
    time = os.date "%H:%M",
    name = "Terminal",
  }

  return vim.tbl_extend("force", defaults, opts or {})
end

M.add_keymap = function(key, buf)
  map("n", tostring(key), function()
    M.switch_buf(buf)
  end, { buffer = state.sidebuf })
end

M.gen_term_bufs = function()
  for i, _ in ipairs(state.terminals) do
    state.terminals[i] = vim.tbl_extend("force", M.new_term(), state.terminals[i])
    local buf = state.terminals[i].buf
    M.add_keymap(i, buf)
  end
end

M.set_termwin_hl = function()
  if state.config.border then
    vim.wo[state.win].winhl = "Normal:normal,floatborder:comment"
  else
    vim.wo[state.win].winhl = "Normal:exdarkbg,floatBorder:exdarkborder"
  end
end

M.save_term_state = function()

  if not state.buf or not state.win or not api.nvim_win_is_valid(state.win) then

    return
  end

  local term = M.get_term_by_key(state.buf)


  if not term or api.nvim_win_get_buf(state.win) ~= state.buf then
    return
  end

  term = term[2]

  term.view = api.nvim_win_call(state.win, function()
    return vim.fn.winsaveview()
  end)

  if api.nvim_get_current_win() == state.win then
    term.mode = vim.fn.mode()
  end
end

M.switch_buf = function(buf)
  if state.buf and state.buf ~= buf then
    M.save_term_state()
  end

  state.buf = buf
  volt_redraw(state.sidebuf, "bufs")
  volt_redraw(state.barbuf, "bar")

  if not api.nvim_win_is_valid(state.win) then
    state.win = api.nvim_open_win(state.buf, true, state.term_win_opts)
    M.set_termwin_hl()
  end

  api.nvim_set_current_win(state.win)
  api.nvim_set_current_buf(buf)

  local details = vim.tbl_filter(function(x)
    return x.buf == buf
  end, state.terminals)

  if vim.bo[buf].buftype ~= "terminal" then
    vim.bo[buf].ft = "Floaterm"
    M.convert_buf2term(details[1].cmd)
    volt_redraw(state.barbuf, "bar")

    map({ "t", "n" }, "<C-h>", function()
      require("floaterm.api").switch_wins()
    end, { buffer = state.buf })

    map({ "n", "t" }, "<C-j>", function()
      require("floaterm.api").cycle_term_bufs "next"
    end, { buffer = state.buf })

    map({ "n", "t" }, "<C-k>", function()
      require("floaterm.api").cycle_term_bufs "prev"
    end, { buffer = state.buf })

    require("volt").mappings {
      bufs = { state.buf, state.sidebuf, state.barbuf },
      after_close = function()
        M.close_timers()
        state.volt_set = false
        state.terminals = nil
        state.buf = nil
        state.sidebuf = nil
        state.barbuf = nil
        api.nvim_del_augroup_by_name "FloatermAu"
      end,
    }

    if state.config.mappings.term then
      state.config.mappings.term(state.buf)
    end
  end

  local term = details[1]

  if term.view then
    vim.fn.winrestview(term.view)
  end

  if term.mode == "t" or (term.mode == nil and state.config.autoinsert) then
    vim.cmd.startinsert()
  else
    vim.cmd.stopinsert()
  end

  if term.view then
    vim.fn.winrestview(term.view)
  end

end

M.get_term_by_key = function(tocompare, name)
  name = name or "buf"

  for i, v in ipairs(state.terminals or {}) do
    if tocompare == v[name] then
      return { i, v }
    end
  end
end

M.get_buf_on_cursor = function()
  local row = vim.api.nvim_win_get_cursor(0)[1]

  if not state.terminals[row] then
    vim.notify("place cursor on the terminal name", vim.log.levels.WARN)
    return
  end

  return row
end

M.close_timers = function()
  state.bar_redraw_timer:stop()
  state.bar_redraw_timer:close()
  state.bar_redraw_timer = nil
end

return M
