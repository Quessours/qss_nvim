-- Where the output of a program you built goes: a plain buffer, one buffer line
-- per output line.
--
-- Overseer's default writes into a terminal buffer. A terminal cuts a long line
-- into rows at the pane width, and at a resize it reflows only the rows on
-- screen, so the scrollback keeps the breaks of the old width. A plain buffer
-- keeps each line whole: 'wrap' follows every resize, and the log level color
-- covers the line from its start to its end.
--
-- Builds keep the terminal, for the colors and progress displays of the tools.

local M = {}

--- A program you run. It keeps a pty, so its stdout stays line buffered and
--- `ssh -t` still allocates a terminal on the device. Overseer strips the color
--- codes and the carriage return at the end of each line.
M.program = { 'jobstart', use_terminal = false, wrap_opts = { pty = true } }

--- A test runner. No pty, so cargo and nextest draw no progress bar, whose
--- carriage returns would stay in a plain buffer.
M.tests = { 'jobstart', use_terminal = false }

return M
