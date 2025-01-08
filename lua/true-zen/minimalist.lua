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
local minimum_writing_area = {
	width = 70,
	height = 100,
}

local wo = vim.wo

local padding = {
	left = 52,
	right = 52,
	top = 0,
	bottom = 0,
}

local original_opts = {}

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

api.nvim_create_augroup("TrueZenMinimalist", {
	clear = true,
})

local win = {}
local CARDINAL_POINTS = { left = "width", right = "width", top = "height", bottom = "height" }

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

local function pad_win(new, props, move)
	cmd(new)

	local win_id = api.nvim_get_current_win()

	if props.width ~= nil then
		api.nvim_win_set_width(0, props.width)
	else
		api.nvim_win_set_height(0, props.height)
	end

	wo.winhighlight = "Normal:TZBackground"

	for opt_type, _ in pairs(opts) do
		for opt, val in pairs(opts[opt_type]) do
			vim[opt_type][opt] = val
		end
	end

	w.tz_pad_win = true

	cmd(move)
	return win_id
end

local function fix_padding(orientation, dimension, mod)
	mod = mod or 0
	local window_dimension = (api.nvim_list_uis()[1][dimension] - mod) -- width or height
	local mwa = minimum_writing_area[dimension]

	if mwa >= window_dimension then
		return 1
	else
		local wanted_available_size = (
			dimension == "width" and padding.left + padding.right + mwa or padding.top + padding.bottom + mwa
		)
		if wanted_available_size > window_dimension then
			local available_space = window_dimension - mwa -- available space for padding on each side (e.g. left and right)
			return (available_space % 2 > 0 and ((available_space - 1) / 2) or available_space / 2)
		else
			return padding[orientation]
		end
	end
end

local function layout(action)
	if action == "generate" then
		local splitbelow, splitright = o.splitbelow, o.splitright
		o.splitbelow, o.splitright = true, true

		local left_padding = fix_padding("left", "width")
		local right_padding = fix_padding("right", "width")
		local top_padding = fix_padding("top", "height")
		local bottom_padding = fix_padding("bottom", "height")

		win.main = api.nvim_get_current_win()

		win.left = pad_win("leftabove vnew", { width = left_padding }, "wincmd l") -- left buffer
		win.right = pad_win("vnew", { width = right_padding }, "wincmd h") -- right buffer
		win.top = pad_win("leftabove new", { height = top_padding }, "wincmd j") -- top buffer
		win.bottom = pad_win("rightbelow new", { height = bottom_padding }, "wincmd k") -- bottom buffer

		o.splitbelow, o.splitright = splitbelow, splitright
	else -- resize
		local pad_sizes = {}
		pad_sizes.left = fix_padding("left", "width")
		pad_sizes.right = fix_padding("right", "width")
		pad_sizes.top = fix_padding("top", "height")
		pad_sizes.bottom = fix_padding("bottom", "height")

		for point, dimension in pairs(CARDINAL_POINTS) do
			if api.nvim_win_is_valid(win[point]) then
				if dimension == "width" then
					api.nvim_win_set_width(win[point], pad_sizes[point])
				else
					api.nvim_win_set_height(win[point], pad_sizes[point])
				end
			end
		end
	end
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

	layout("generate")

	M.running = true
	data.do_callback("minimalist", "open", "pos")
end

function M.off()
	data.do_callback("minimalist", "close", "pre")

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
