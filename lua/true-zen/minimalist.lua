local M = {}

M.running = false
local colors = require("true-zen.utils.colors")
local data = require("true-zen.utils.data")
local cnf = require("true-zen.config").options
local o = vim.o
local cmd = vim.cmd
local fn = vim.fn
local w = vim.w
local api = vim.api
local IGNORED_BUF_TYPES = data.set_of(cnf.modes.minimalist.ignored_buf_types)
local gwidth = cnf.modes.minimalist.minimum_writing_area.width

local original_opts = {}

api.nvim_create_augroup("TrueZenMinimalist", {
	clear = true,
})

-- reference: https://vim.fandom.com/wiki/Run_a_command_in_multiple_buffers
local function alldo(run)
	local tab = fn.tabpagenr()
	local winnr = fn.winnr()
	local buffer = fn.bufnr("%")

	for _, command in pairs(run) do
		-- tapped together solution, but works! :)
		cmd(
			[[windo if &modifiable == 1 && &buflisted == 1 && &bufhidden == "" | exe "let g:my_buf = bufnr(\"%\") | exe \"bufdo ]]
				.. command
				.. [[\" | exe \"buffer \" . g:my_buf" | endif]]
		)
	end

	w.tz_buffer = nil

	cmd("tabn " .. tab)
	cmd(winnr .. " wincmd w")
	cmd("buffer " .. buffer)
end

local function save_opts()
	-- check if current window's buffer type matches any of IGNORED_BUF_TYPES, if so look for one that doesn't
	local suitable_window = fn.winnr()
	local currtab = fn.tabpagenr()
	if IGNORED_BUF_TYPES[fn.gettabwinvar(currtab, suitable_window, "&buftype")] ~= nil then
		for i = 1, fn.winnr("$") do
			if IGNORED_BUF_TYPES[fn.gettabwinvar(currtab, i, "&buftype")] == nil then
				suitable_window = i
				goto continue
			end
		end
	end
	::continue::

	-- get the options from suitable_window
	for user_opt, val in pairs(cnf.modes.minimalist.options) do
		local opt = fn.gettabwinvar(currtab, suitable_window, "&" .. user_opt)
		if
			type(opt) == "string"
			or user_opt == "showtabline"
			or user_opt == "cmdheight"
			or user_opt == "laststatus"
			or user_opt == "numberwidth"
		then
			original_opts[user_opt] = opt
		else
			original_opts[user_opt] = opt == 1
		end
		o[user_opt] = val
	end

	original_opts.highlights = {
		StatusLine = colors.get_hl("StatusLine"),
		StatusLineNC = colors.get_hl("StatusLineNC"),
		TabLine = colors.get_hl("TabLine"),
		TabLineFill = colors.get_hl("TabLineFill"),
	}
end

local win = {}
local opts = {
	bo = {
		buftype = "nofile",
		bufhidden = "hide",
		modifiable = false,
		buflisted = false,
		swapfile = false,
	},
	wo = {
		cursorline = false,
		cursorcolumn = false,
		number = false,
		relativenumber = false,
		foldenable = false,
		list = false,
	},
}

-- 添加新的padding窗口创建函数
local function pad_win(new, props, move)
	cmd(new)
	local win_id = api.nvim_get_current_win()

	if props.width ~= nil then
		api.nvim_win_set_width(0, props.width)
	end

	for opt_type, _ in pairs(opts) do
		for opt, val in pairs(opts[opt_type]) do
			vim[opt_type][opt] = val
		end
	end

	w.tz_pad_win = true
	cmd(move)
	return win_id
end

-- 添加居中布局函数
local function create_center_layout()
	local ui = api.nvim_list_uis()[1]
	local main_width = gwidth
	local side_width = math.floor((ui.width - main_width) / 2)

	-- 保存分割设置
	local splitright = o.splitright
	o.splitright = true

	-- 保存当前窗口为主窗口
	win.main = api.nvim_get_current_win()

	-- 创建左右padding窗口
	win.left = pad_win("leftabove vnew", { width = side_width + 30 }, "wincmd l")
	win.right = pad_win("vnew", { width = side_width - 30 }, "wincmd h")

	-- 设置主窗口宽度
	api.nvim_win_set_width(win.main, main_width)

	-- 恢复分割设置
	o.splitright = splitright
end

function M.on()
	data.do_callback("minimalist", "open", "pre")

	save_opts()

	if cnf.modes.minimalist.options.number == false then
		alldo({ "set nonumber" })
	end

	if cnf.modes.minimalist.options.relativenumber == false then
		alldo({ "set norelativenumber" })
	end

	-- fully hide statusline and tabline
	local base = colors.get_hl("Normal")["background"] or "NONE"
	for hi_group, _ in pairs(original_opts["highlights"]) do
		colors.highlight(hi_group, { bg = base, fg = base }, true)
	end

	if cnf.integrations.tmux == true then
		require("true-zen.integrations.tmux").on()
	end

	create_center_layout()
	require("lualine").hide()

	-- 添加窗口大小调整事件
	api.nvim_create_autocmd({ "VimResized" }, {
		callback = function()
			if M.running then
				local ui = api.nvim_list_uis()[1]
				local side_width = math.floor((ui.width - gwidth) / 2)
				if api.nvim_win_is_valid(win.left) then
					api.nvim_win_set_width(win.left, side_width + 30)
				end
				if api.nvim_win_is_valid(win.right) then
					api.nvim_win_set_width(win.right, side_width - 30)
				end
			end
		end,
		group = "TrueZenMinimalist",
	})

	M.running = true
	data.do_callback("minimalist", "open", "pos")
end

function M.off()
	data.do_callback("minimalist", "close", "pre")

	-- 清除所有padding窗口
	if win.main and api.nvim_win_is_valid(win.main) then
		api.nvim_set_current_win(win.main)
	end
	cmd("only")

	api.nvim_create_augroup("TrueZenMinimalist", {
		clear = true,
	})

	if original_opts.number == true then
		alldo({ "set number" })
	end

	if original_opts.relativenumber == true then
		alldo({ "set relativenumber" })
	end

	original_opts.number = nil
	original_opts.relativenumber = nil

	for k, v in pairs(original_opts) do
		if k ~= "highlights" then
			o[k] = v
		end
	end

	for hi_group, props in pairs(original_opts["highlights"]) do
		colors.highlight(hi_group, { fg = props.foreground, bg = props.background }, true)
	end

	if cnf.integrations.tmux == true then
		require("true-zen.integrations.tmux").off()
	end

	win = {}
	require("lualine").hide({ unhide = true })
	M.running = false
	data.do_callback("minimalist", "close", "pos")
end

function M.toggle()
	if M.running then
		M.off()
	else
		M.on()
	end
end

return M
