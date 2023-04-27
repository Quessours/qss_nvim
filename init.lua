local merge_tb = vim.tbl_deep_extend

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1


mappings = require("qss_nvim.mappings")

function dump_table(o)
	if type(o) == 'table' then
		local s = '{ '
		for k, v in pairs(o) do
			if type(k) ~= 'number' then k = '"' .. k .. '"' end
			s = s .. '[' .. k .. '] = ' .. dump_table(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

for mode, mode_values in pairs(mappings) do
	local default_opts = merge_tb("force", { mode = mode }, mapping_opt or {})
	for keybind, mapping_info in pairs(mode_values) do
		-- merge default + user opts
		local opts = merge_tb("force", default_opts, mapping_info.opts or {})

		mapping_info.opts, opts.mode = nil, nil
		opts.desc = mapping_info[2]
		vim.keymap.set(mode, keybind, mapping_info[1], opts)
	end
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)


require("lazy").setup("plugins")


vim.cmd("set relativenumber")
