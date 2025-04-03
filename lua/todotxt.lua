---
--- A lua version of the [`todotxt.vim`](https://github.com/freitass/todo.txt-vim) plugin for Neovim.
---
--- MIT License Copyright (c) 2024 Pedro Mendes
---
--- ==============================================================================
--- @module 'todotxt'
local todotxt = {}
local config = {}

--- @class Setup
--- @field todotxt string: Path to the todo.txt file
--- @field donetxt string: Path to the done.txt file

--- Reads the lines from a file.
--- @param filepath string
--- @return string[]
local read_lines = function(filepath)
	return vim.fn.readfile(filepath)
end

--- Writes the lines to a file and updates any corresponding buffer.
--- @param filepath string
--- @param lines table
--- @return nil
local write_lines = function(filepath, lines)
	-- First, check if this file is open in any buffer
	local buf_exists = false
	local buf_num = -1

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local bufname = vim.api.nvim_buf_get_name(buf)
		if bufname == filepath and vim.api.nvim_buf_is_loaded(buf) then
			buf_exists = true
			buf_num = buf
			break
		end
	end

	if buf_exists then
		-- Update the buffer directly instead of writing to disk
		vim.api.nvim_buf_set_lines(buf_num, 0, -1, false, lines)

		-- Mark the buffer as "saved" to avoid the reload prompt
		vim.api.nvim_buf_call(buf_num, function()
			vim.cmd("set nomodified")
		end)
	else
		-- File isn't open in any buffer, safe to write directly
		vim.fn.writefile(lines, filepath)
	end
end

--- Sorts the tasks in the open buffer by a given function.
--- @param sort_func function
--- @return nil
local sort_tasks_by = function(sort_func)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- Create a table with the original indices
	local indexed_lines = {}
	for i, line in ipairs(lines) do
		indexed_lines[i] = { line = line, original_index = i }
	end

	-- Perform stable sort by using original indices as tiebreaker
	table.sort(indexed_lines, function(a, b)
		local result = sort_func(a.line, b.line)
		if result then
			return true
		elseif sort_func(b.line, a.line) then
			return false
		else
			-- If neither a comes before b nor b comes before a, they're equal
			-- Use original indices to maintain stable order
			return a.original_index < b.original_index
		end
	end)

	-- Extract just the lines again
	local sorted_lines = {}
	for i, item in ipairs(indexed_lines) do
		sorted_lines[i] = item.line
	end

	vim.api.nvim_buf_set_lines(0, 0, -1, false, sorted_lines)
end

--- Toggles the todo state of the current line in a todo.txt file.
--- If the line starts with "x YYYY-MM-DD ", it removes it to mark as not done.
--- Otherwise, it adds "x YYYY-MM-DD " at the beginning to mark as done.
--- @return nil
todotxt.toggle_todo_state = function()
	local node = vim.treesitter.get_node()

	if not node then
		return
	end

	local start_row, _ = node:range()
	local line = vim.fn.getline(start_row + 1)
	local pattern = "^x %d%d%d%d%-%d%d%-%d%d "

	if line:match(pattern) then
		line = line:gsub(pattern, "")
	else
		local date = os.date("%Y-%m-%d")
		line = "x " .. date .. " " .. line
	end

	vim.fn.setline(start_row + 1, line)
end

--- Opens the todo.txt file in a new split.
--- @return nil
todotxt.open_todo_file = function()
	vim.cmd("split " .. config.todotxt)
end

--- Sorts the tasks in the open buffer by priority.
--- @return nil
todotxt.sort_tasks_by_priority = function()
	sort_tasks_by(function(a, b)
		local priority_a = a:match("^%((%a)%)") or "Z"
		local priority_b = b:match("^%((%a)%)") or "Z"
		return priority_a < priority_b
	end)
end

--- Sorts the tasks in the open buffer by date.
--- @return nil
todotxt.sort_tasks = function()
	sort_tasks_by(function(a, b)
		local date_a = a:match("^x (%d%d%d%d%-%d%d%-%d%d)") or a:match("^(%d%d%d%d%-%d%d%-%d%d)")
		local date_b = b:match("^x (%d%d%d%d%-%d%d%-%d%d)") or b:match("^(%d%d%d%d%-%d%d%-%d%d)")

		if date_a and date_b then
			return date_a > date_b
		elseif date_a then
			return false
		elseif date_b then
			return true
		else
			return a > b
		end
	end)
end

--- Sorts the tasks in the open buffer by project.
--- @return nil
todotxt.sort_tasks_by_project = function()
	sort_tasks_by(function(a, b)
		local project_a = a:match("%+%w+") or ""
		local project_b = b:match("%+%w+") or ""
		return project_a < project_b
	end)
end

--- Sorts the tasks in the open buffer by context.
--- @return nil
todotxt.sort_tasks_by_context = function()
	sort_tasks_by(function(a, b)
		local context_a = a:match("@%w+") or ""
		local context_b = b:match("@%w+") or ""
		return context_a < context_b
	end)
end

--- Sorts the tasks in the open buffer by due date.
--- @return nil
todotxt.sort_tasks_by_due_date = function()
	sort_tasks_by(function(a, b)
		local due_date_a = a:match("due:(%d%d%d%d%-%d%d%-%d%d)")
		local due_date_b = b:match("due:(%d%d%d%d%-%d%d%-%d%d)")

		if due_date_a and due_date_b then
			return due_date_a < due_date_b
		elseif due_date_a then
			return true
		elseif due_date_b then
			return false
		else
			return a < b
		end
	end)
end

--- Sorts tasks with the same project as the current line to the top.
--- @return nil
todotxt.sort_by_current_project = function()
	local current_buf = vim.api.nvim_get_current_buf()
	local current_line = vim.api.nvim_get_current_line()

	-- Extract project from current line
	local current_project = current_line:match("%+([%w%.%-]+)")

	-- If no project is found, notify the user and return
	if not current_project then
		vim.notify("No project found in the current line", vim.log.levels.INFO)
		return
	end

	-- Sort tasks by matching the project of the current line
	sort_tasks_by(function(a, b)
		local a_has_project = a:match("%+" .. current_project .. "%W") or a:match("%+" .. current_project .. "$")
		local b_has_project = b:match("%+" .. current_project .. "%W") or b:match("%+" .. current_project .. "$")

		-- Project match takes precedence
		if a_has_project and not b_has_project then
			return true -- a goes first
		elseif not a_has_project and b_has_project then
			return false -- b goes first
		else
			-- Both match or both don't match - maintain original order within these groups
			return nil
		end
	end)

	vim.notify("Sorted by project: +" .. current_project, vim.log.levels.INFO)
end

--- Sorts tasks with the same project as the current line to the top.
--- @return nil
todotxt.sort_by_current_context = function()
	local current_line = vim.api.nvim_get_current_line()

	-- Extract context from current line
	local current_context = current_line:match("@(%w+)")

	-- If no context is found, notify the user and return
	if not current_context then
		vim.notify("No project found in the current line", vim.log.levels.INFO)
		return
	end

	-- Sort tasks by matching the project of the current line
	sort_tasks_by(function(a, b)
		local a_has_context = a:match("@" .. current_context .. "%W") or a:match("@" .. current_context .. "$")
		local b_has_context = b:match("@" .. current_context .. "%W") or b:match("@" .. current_context .. "$")

		-- context match takes precedence
		if a_has_context and not b_has_context then
			return true -- a goes first
		elseif not a_has_context and b_has_context then
			return false -- b goes first
		else
			-- Both match or both don't match - maintain original order within these groups
			return nil
		end
	end)

	vim.notify("Sorted by context: @" .. current_context, vim.log.levels.INFO)
end

--- Cycles the priority of the current task between A, B, C, and no priority.
--- @return nil
todotxt.cycle_priority = function()
	local node = vim.treesitter.get_node()
	if not node then
		return
	end

	local start_row, _ = node:range()
	local line = vim.fn.getline(start_row + 1)

	local current_priority = line:match("^%((%a)%)")
	local new_priority

	if current_priority == "A" then
		new_priority = "(B) "
	elseif current_priority == "B" then
		new_priority = "(C) "
	elseif current_priority == "C" then
		new_priority = ""
	else
		new_priority = "(A)"
	end

	if current_priority then
		line = line:gsub("^%(%a%)%s*", new_priority)
	else
		line = new_priority .. " " .. line
	end

	vim.fn.setline(start_row + 1, line)
end

--- Captures a new todo entry with the current date.
--- @return nil
todotxt.capture_todo = function()
	vim.ui.input({ prompt = "New Todo: " }, function(input)
		if input then
			local date = os.date("%Y-%m-%d")
			local new_todo = date .. " " .. input
			local bufname = vim.api.nvim_buf_get_name(0)
			if bufname == config.todotxt then
				local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
				table.insert(lines, new_todo)
				vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			else
				local lines = read_lines(config.todotxt)
				table.insert(lines, new_todo)
				write_lines(config.todotxt, lines)
			end
		end
	end)
end

--- Moves all done tasks from the todo.txt file to the done.txt file.
--- @return nil
todotxt.move_done_tasks = function()
	local todo_lines = read_lines(config.todotxt)
	local done_lines = read_lines(config.donetxt)
	local remaining_todo_lines = {}

	for _, line in ipairs(todo_lines) do
		if line:match("^x ") then
			table.insert(done_lines, line)
		else
			table.insert(remaining_todo_lines, line)
		end
	end

	write_lines(config.todotxt, remaining_todo_lines)
	write_lines(config.donetxt, done_lines)
end

--- Setup function
--- @param opts Setup
todotxt.setup = function(opts)
	opts = opts or {}
	config.todotxt = opts.todotxt or vim.env.HOME .. "/Documents/todo.txt"
	config.donetxt = opts.donetxt or vim.env.HOME .. "/Documents/done.txt"

	--- Creates files if they do not exist
	if vim.fn.filereadable(config.todotxt) == 0 then
		vim.fn.writefile({}, config.todotxt)
	end
	if vim.fn.filereadable(config.donetxt) == 0 then
		vim.fn.writefile({}, config.donetxt)
	end
end

return todotxt
