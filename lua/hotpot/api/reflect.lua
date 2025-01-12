local function split_string(s, by)
  local result = {}
  local from = 1
  local d_from, d_to = string.find(s, by, from)
  while d_from do
    table.insert(result, string.sub(s, from, (d_from - 1)))
    from = (d_from + 1)
    d_from, d_to = string.find(s, by, from)
  end
  table.insert(result, string.sub(s, from))
  return result
end
local M = {}
local api = vim.api
local sessions = {}
local function resolve_buf_id(buf)
  return api.nvim_buf_call(buf, api.nvim_get_current_buf)
end
local function do_eval(str, compiler_options)
  local _let_1_ = require("hotpot.fennel")
  local eval = _let_1_["eval"]
  local _let_2_ = require("hotpot.runtime")
  local traceback = _let_2_["traceback"]
  local _let_3_ = require("hotpot.fennel")
  local view = _let_3_["view"]
  local code = string.format("(do %s)", compiler_options.preprocessor(str, {}))
  local printed = {}
  local env
  local function _4_(...)
    local function _5_(_2410)
      return table.insert(printed, _2410)
    end
    local function _6_(...)
      local s = ""
      for _, v in ipairs({...}) do
        s = (s .. view(v) .. "\9")
      end
      return s
    end
    return _5_(_6_(...))
  end
  env = setmetatable({print = _4_}, {__index = (compiler_options.modules.env or _G)})
  local module_options = vim.tbl_extend("keep", {env = env}, compiler_options.modules)
  local ok_3f, viewed = nil, nil
  do
    local _7_, _8_ = nil, nil
    local function _9_()
      return eval(code, module_options)
    end
    _7_, _8_ = xpcall(_9_, traceback)
    if ((_7_ == true) and (nil ~= _8_)) then
      local val_1 = _8_
      ok_3f, viewed = true, view(val_1)
    elseif ((_7_ == true) and (_8_ == nil)) then
      ok_3f, viewed = true, view(nil)
    elseif ((_7_ == false) and (nil ~= _8_)) then
      local err = _8_
      ok_3f, viewed = false, err
    elseif ((_7_ == false) and (_8_ == nil)) then
      ok_3f, viewed = false, "::reflect caught an error but the error had no text::"
    else
      ok_3f, viewed = nil
    end
  end
  return ok_3f, viewed, printed
end
local function do_compile(str, compiler_options)
  local _let_11_ = require("hotpot.lang.fennel.compiler")
  local compile_string = _let_11_["compile-string"]
  return compile_string(str, compiler_options.modules, compiler_options.macros, compiler_options.preprocessor)
end
local function default_session(buf)
  local ns = api.nvim_create_namespace(("hotpot-session-for-buf#" .. buf))
  local session = {["input-buf"] = nil, ["output-buf"] = buf, mode = "compile", au = nil, ["mark-start"] = nil, ["mark-stop"] = nil, ["extmark-memory"] = nil, id = ns, ns = ns}
  return session
end
local function _set_extmarks(session, start_line, start_col, stop_line, stop_col)
  do
    local _let_12_ = vim.api
    local nvim_buf_set_extmark = _let_12_["nvim_buf_set_extmark"]
    local start = nvim_buf_set_extmark(session["input-buf"], session.ns, start_line, start_col, {id = session["mark-start"], sign_text = "(*", sign_hl_group = "DiagnosticHint", strict = false})
    local stop = nvim_buf_set_extmark(session["input-buf"], session.ns, stop_line, stop_col, {id = session["mark-stop"], virt_text = {{" *)", "DiagnosticHint"}}, virt_text_pos = "eol", strict = false})
    do end (session)["mark-start"] = start
    session["mark-stop"] = stop
    session["extmark-memory"] = {start_line, start_col, stop_line, stop_col}
  end
  return session
end
local function _get_extmarks(session)
  local _local_13_ = require("hotpot.api.get_text")
  local get_range = _local_13_["get-range"]
  local _let_14_ = api.nvim_buf_get_extmark_by_id(session["input-buf"], session.ns, session["mark-start"], {})
  local start_l = _let_14_[1]
  local start_c = _let_14_[2]
  local _let_15_ = api.nvim_buf_get_extmark_by_id(session["input-buf"], session.ns, session["mark-stop"], {})
  local stop_l = _let_15_[1]
  local stop_c = _let_15_[2]
  local positions = {start_l, start_c, stop_l, stop_c}
  local ok_3f, positions0 = nil, nil
  if ((_G.type(positions) == "table") and (nil ~= positions[1]) and (nil ~= positions[2]) and (positions[1] == positions[3]) and (positions[2] == positions[4])) then
    local l = positions[1]
    local c = positions[2]
    local _16_, _17_ = nil, nil
    do
      _16_, _17_ = pcall(_set_extmarks, session, unpack(session["extmark-memory"]))
    end
    if ((_16_ == true) and true) then
      local _ = _17_
      ok_3f, positions0 = true, session["extmark-memory"]
    elseif ((_16_ == false) and (nil ~= _17_)) then
      local err = _17_
      ok_3f, positions0 = false, err
    else
      ok_3f, positions0 = nil
    end
  elseif true then
    local _ = positions
    ok_3f, positions0 = true, positions
  else
    ok_3f, positions0 = nil
  end
  if ok_3f then
    session["extmark-memory"] = positions0
  else
  end
  return ok_3f, positions0
end
local function _get_extmarks_content(session, start_l, start_c, stop_l, stop_c)
  local _21_, _22_ = pcall(api.nvim_buf_get_text, session["input-buf"], start_l, start_c, stop_l, stop_c, {})
  if ((_21_ == true) and (nil ~= _22_)) then
    local text = _22_
    return table.concat(text, "\n")
  elseif ((_21_ == false) and (nil ~= _22_)) then
    local err = _22_
    return err
  else
    return nil
  end
end
local function autocmd_handler(session)
  local function process_eval(source)
    local _let_24_ = session
    local compiler_options = _let_24_["compiler-options"]
    local ok_3f, viewed, printed = do_eval(source, compiler_options)
    local output
    local function _25_(_241)
      if (0 < #_241) then
        return (_241 .. "\n\n" .. viewed)
      else
        return viewed
      end
    end
    local _27_
    do
      local tbl_17_auto = {}
      local i_18_auto = #tbl_17_auto
      for i, p in ipairs((printed or {})) do
        local val_19_auto = (";;=> " .. p)
        if (nil ~= val_19_auto) then
          i_18_auto = (i_18_auto + 1)
          do end (tbl_17_auto)[i_18_auto] = val_19_auto
        else
        end
      end
      _27_ = tbl_17_auto
    end
    output = _25_(table.concat(_27_, "\n"))
    return ok_3f, output
  end
  local function process_compile(source)
    local _let_29_ = session
    local compiler_options = _let_29_["compiler-options"]
    return do_compile(source, compiler_options)
  end
  if (session["mark-start"] and session["mark-stop"]) then
    local positions_3f, positions = _get_extmarks(session)
    local text
    do
      local _30_, _31_ = positions_3f, positions
      if ((_30_ == true) and (_31_ == positions)) then
        text = _get_extmarks_content(session, unpack(positions))
      elseif ((_30_ == false) and (nil ~= _31_)) then
        local err = _31_
        text = ("Range was irrecoverably damaged by the editor, " .. "try re-selecting a range.\n" .. "Error:\n" .. positions)
      else
        text = nil
      end
    end
    local result_ok_3f, result = nil, nil
    if positions_3f then
      local _33_ = session.mode
      if (_33_ == "eval") then
        result_ok_3f, result = process_eval(text)
      elseif (_33_ == "compile") then
        result_ok_3f, result = process_compile(text)
      else
        result_ok_3f, result = nil
      end
    else
      result_ok_3f, result = false, positions
    end
    local lines = {}
    local append
    local function _36_(_241)
      return table.insert(lines, _241)
    end
    append = _36_
    local blank
    local function _37_()
      return table.insert(lines, "")
    end
    blank = _37_
    local commented
    local function _38_(_241)
      local function _39_()
        if (session.mode == "compile") then
          return "-- "
        else
          return ";; "
        end
      end
      return (_39_() .. _241)
    end
    commented = _38_
    if result_ok_3f then
      append(commented((session.mode .. " = OK")))
    else
      append(commented((session.mode .. " = ERROR")))
    end
    blank()
    for _, line in ipairs(split_string(result, "\n")) do
      append(line)
    end
    blank()
    append(commented(("Source (" .. table.concat(positions, ",") .. "):")))
    for _, line in ipairs(split_string(text, "\n")) do
      append(commented(line))
    end
    local function _41_()
      vim.api.nvim_buf_set_lines(session["output-buf"], 0, -1, false, lines)
      if ("eval" == session.mode) then
        return vim.api.nvim_buf_set_option(session["output-buf"], "filetype", "fennel")
      else
        return vim.api.nvim_buf_set_option(session["output-buf"], "filetype", "lua")
      end
    end
    return vim.schedule(_41_)
  else
    return nil
  end
end
local function attach_extmarks(session)
  local _let_44_ = require("hotpot.api.get_text")
  local get_highlight = _let_44_["get-highlight"]
  local _let_45_, _let_46_ = get_highlight()
  local _let_47_ = _let_45_
  local vis_start_l = _let_47_[1]
  local vis_start_c = _let_47_[2]
  local _let_48_ = _let_46_
  local vis_stop_l = _let_48_[1]
  local vis_stop_c = _let_48_[2]
  local ex_start_l = (vis_start_l - 1)
  local ex_start_c = (vis_start_c - 1)
  local ex_stop_l = (vis_stop_l - 1)
  local ex_stop_c = vis_stop_c
  _set_extmarks(session, ex_start_l, ex_start_c, ex_stop_l, ex_stop_c)
  return session
end
local function clear_extmarks(session)
  local _let_49_ = session
  local mark_start = _let_49_["mark-start"]
  local mark_stop = _let_49_["mark-stop"]
  api.nvim_buf_del_extmark(session["input-buf"], session.ns, mark_start)
  api.nvim_buf_del_extmark(session["input-buf"], session.ns, mark_stop)
  do end (session)["mark-start"] = nil
  session["mark-stop"] = nil
  session["extmark-memory"] = nil
  return session
end
local function attach_autocmd(session)
  local au
  local function _50_()
    return autocmd_handler(session)
  end
  au = api.nvim_create_autocmd({"TextChanged", "InsertLeave"}, {buffer = session["input-buf"], desc = ("hotpot-reflect autocmd for buf#" .. session["input-buf"]), callback = _50_})
  do end (session)["au"] = au
  return session
end
local function clear_autocmd(session)
  local _let_51_ = session
  local au = _let_51_["au"]
  api.nvim_del_autocmd(au)
  do end (session)["au"] = nil
  return session
end
local function close_session(session)
  if session["input-buf"] then
    M["detach-input"](session.id)
  else
  end
  sessions[session.id] = nil
  return nil
end
M["attach-output"] = function(given_buf_id)
  local buf = resolve_buf_id(given_buf_id)
  local session = default_session(buf)
  do end (sessions)[session.id] = session
  do
    api.nvim_buf_set_name(buf, ("hotpot-reflect-session#" .. buf))
    api.nvim_buf_set_option(buf, "buftype", "nofile")
    api.nvim_buf_set_option(buf, "swapfile", false)
    api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    api.nvim_buf_set_option(buf, "filetype", "lua")
  end
  local function _53_()
    return close_session(session)
  end
  api.nvim_create_autocmd({"BufWipeout"}, {buffer = buf, once = true, callback = _53_})
  local function _54_(_241)
    return M.attach(session.id, _241)
  end
  local function _55_(_241)
    return M.detach(session.id, _241)
  end
  return session.id, {attach = _54_, detach = _55_}
end
M["detach-input"] = function(session_id)
  local session = sessions[session_id]
  assert(session, string.format("Could not find session with given id %s", tostring(session_id)))
  clear_extmarks(session)
  clear_autocmd(session)
  do end (session)["input-buf"] = nil
  return session.id
end
M["attach-input"] = function(session_id, given_buf_id, _3fcompiler_options)
  local session = sessions[session_id]
  assert(session, string.format("Could not find session with given id %s", tostring(session_id)))
  if session["input-buf"] then
    M["detach-input"](session.id, session["input-buf"])
  else
  end
  local buf = resolve_buf_id(given_buf_id)
  local fname
  do
    local _57_ = api.nvim_buf_get_name(buf)
    if (_57_ == "") then
      fname = nil
    elseif (nil ~= _57_) then
      local name = _57_
      fname = name
    else
      fname = nil
    end
  end
  local real_compiler_options
  if _3fcompiler_options then
    local function _59_(_241)
      return _241
    end
    real_compiler_options = vim.tbl_extend("keep", _3fcompiler_options, {modules = {}, macros = {env = "_COMPILER"}, preprocessor = _59_})
  else
    local _let_60_ = require("hotpot.runtime")
    local config_for_context = _let_60_["config-for-context"]
    local context_loc
    if (fname == nil) then
      context_loc = vim.fn.getcwd()
    elseif (nil ~= fname) then
      local name = fname
      context_loc = name
    else
      context_loc = nil
    end
    real_compiler_options = config_for_context(context_loc).compiler
  end
  local compiler_options = {macros = real_compiler_options.macros, preprocessor = real_compiler_options.preprocessor, modules = vim.tbl_extend("keep", {filename = fname, correlate = false}, real_compiler_options.modules)}
  session["input-buf"] = buf
  session["compiler-options"] = compiler_options
  attach_extmarks(session)
  attach_autocmd(session)
  autocmd_handler(session)
  return session.id
end
M["set-mode"] = function(session_id, mode)
  local session = sessions[session_id]
  assert(session, string.format("Could not find session with given id %s", tostring(session_id)))
  assert(((mode == "compile") or (mode == "eval")), ("mode must be :compile or :eval, got " .. tostring(mode)))
  do end (session)["mode"] = mode
  autocmd_handler(session)
  return session.id
end
return M