local options = {
	clipboard      = "unnamed,unnamedplus", --- Copy-paste between vim and everything else
	cmdheight      = 0,                --- Give more space for displaying messages
	completeopt    = "menu,menuone,noselect", --- Better autocompletion
	cursorline     = true,             --- Highlight of current line
	emoji          = false,            --- Fix emoji display
	expandtab      = true,             --- Use spaces instead of tabs
	--foldcolumn     = "0",
	--foldnestmax    = 0,
	--foldlevel      = 99,                      --- Using ufo provider need a large value
	--foldlevelstart = 99,           --- Expand all folds by default
	ignorecase     = true,        --- Needed for smartcase
	laststatus     = 3,           --- Have a global statusline at the bottom instead of one for each window
	-- lazyredraw     = true,                    --- Makes macros faster & prevent errors in complicated mappings
	mouse          = "a",         --- Enable mouse
	number         = true,        --- Shows current line number
	pumheight      = 10,          --- Max num of items in completion menu
	relativenumber = true,        --- Enables relative number
	scrolloff      = 12,          --- Always keep space when scrolling to bottom/top edge
	shiftwidth     = 4,           --- Change a number of space characters inserted for indentation
	showtabline    = 2,           --- Always show tabs
	signcolumn     = "yes:2",     --- Add extra sign column next to line number
	smartcase      = true,        --- Uses case in search
	smartindent    = true,        --- Makes indenting smart
	smarttab       = true,        --- Makes tabbing smarter will realize you have 2 vs 4
	softtabstop    = 4,           --- Insert 4 spaces for a tab
	splitright     = true,        --- Vertical splits will automatically be to the right
	swapfile       = false,       --- Swap not needed
	tabstop        = 4,           --- Insert 2 spaces for a tab
	termguicolors  = true,        --- Correct terminal colors
	timeoutlen     = 200,         --- Faster completion (cannot be lower than 200 because then commenting doesn't work)
	undofile       = true,        --- Sets undo to file
	updatetime     = 100,         --- Faster completion
	viminfo        = "'1000",     --- Increase the size of file history
	wrap           = false,       --- Display long lines as just one line
	writebackup    = false,       --- Not needed
	-- Neovim defaults
	autoindent     = true,        --- Good auto indent
	backspace      = "indent,eol,start", --- Making sure backspace works
	conceallevel   = 0,           --- Show `` in markdown files
	encoding       = "utf-8",     --- The encoding displayed
	errorbells     = false,       --- Disables sound effect for errors
	fileencoding   = "utf-8",     --- The encoding written to file
	incsearch      = true,        --- Start searching before pressing enter
	showmode       = false,       --- Don't show things like -- INSERT -- anymore
}

return options
