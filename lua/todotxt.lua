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

--- Writes the lines to a file.
--- @param filepath string
--- @param lines table
--- @return nil
local write_lines = function(filepath, lines)
	vim.fn.writefile(lines, filepath)
end

--- Updates the buffer if it is open.
--- @param filepath string
--- @param lines string[]
--- @return nil
local update_buffer_if_open = function(filepath, lines)
	local current_buf = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(current_buf)

	if bufname == filepath then
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
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
	local current_project = current_line:match("%+(%w+)")

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

	update_buffer_if_open(config.todotxt, remaining_todo_lines)
end

--- Use Telescope to filter and navigate tasks with completion functionality
--- @return nil
todotxt.telescope_tasks = function()
	local has_telescope, telescope = pcall(require, "telescope")
	if not has_telescope then
		vim.notify("Telescope is not installed", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	-- Get tasks from todo.txt file
	local lines = {}
	local is_todo_file = vim.api.nvim_buf_get_name(0) == config.todotxt

	if is_todo_file then
		lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	else
		lines = read_lines(config.todotxt)
	end

	pickers
		.new({}, {
			prompt_title = "Todo Tasks",
			finder = finders.new_table({
				results = lines,
				entry_maker = function(entry)
					-- Check if task is completed
					local completed = entry:match("^x %d%d%d%d%-%d%d%-%d%d") ~= nil

					-- Extract other useful information
					local priority = entry:match("^%((%a)%)") or ""
					local project = entry:match("%+(%w+)") or ""
					local context = entry:match("@(%w+)") or ""

					-- Create display with completion status indicator
					local display = (completed and "[✓] " or "[ ] ") .. entry

					return {
						value = entry,
						display = display,
						ordinal = entry,
						completed = completed,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				-- Complete/uncomplete task with <C-space>
				map("i", "<C-space>", function()
					local selection = action_state.get_selected_entry()
					local line = selection.value
					local updated_line

					-- Toggle completion status
					if line:match("^x %d%d%d%d%-%d%d%-%d%d ") then
						-- Task is completed - uncomplete it
						updated_line = line:gsub("^x %d%d%d%d%-%d%d%-%d%d ", "")
						selection.completed = false
					else
						-- Task is not completed - complete it
						local date = os.date("%Y-%m-%d")
						updated_line = "x " .. date .. " " .. line
						selection.completed = true
					end

					-- Update the task in both Telescope and the buffer/file
					selection.value = updated_line
					selection.display = (selection.completed and "[✓] " or "[ ] ") .. updated_line
					selection.ordinal = updated_line

					-- Refresh the Telescope view
					action_state.set_selected_entry(selection)

					-- Find and update the task in the original lines list
					for i, l in ipairs(lines) do
						if l == line then
							lines[i] = updated_line
							break
						end
					end

					-- Update buffer if we're in the todo file, otherwise update the file directly
					if is_todo_file then
						vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
					else
						write_lines(config.todotxt, lines)
					end

					return true -- Keep Telescope open
				end)

				-- Jump to the task when selected
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					-- If we're not already in the todo file, open it
					if not is_todo_file then
						vim.cmd("split " .. config.todotxt)
					end

					-- Find and jump to the selected line
					local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
					for i, line in ipairs(current_lines) do
						if line == selection.value then
							vim.api.nvim_win_set_cursor(0, { i, 0 })
							break
						end
					end
				end)

				-- Add <C-a> to archive completed tasks
				map("i", "<C-a>", function()
					-- Move completed tasks to done.txt
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

					-- Update buffer if needed and refresh Telescope with remaining tasks
					if is_todo_file then
						vim.api.nvim_buf_set_lines(0, 0, -1, false, remaining_todo_lines)
					end

					-- Close and reopen Telescope to show updated task list
					actions.close(prompt_bufnr)
					todotxt.telescope_tasks()

					vim.notify("Completed tasks archived to done.txt", vim.log.levels.INFO)
					return true
				end)

				return true
			end,
		})
		:find()
end

--- Use Telescope to filter by project
--- @return nil
todotxt.telescope_projects = function()
	local has_telescope, telescope = pcall(require, "telescope")
	if not has_telescope then
		vim.notify("Telescope is not installed", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	-- Get tasks from todo.txt file
	local lines = {}
	local is_todo_file = vim.api.nvim_buf_get_name(0) == config.todotxt

	if is_todo_file then
		lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	else
		lines = read_lines(config.todotxt)
	end

	-- Extract unique projects
	local projects = {}
	for _, line in ipairs(lines) do
		for project in line:gmatch("%+(%w+)") do
			projects[project] = true
		end
	end

	local project_list = {}
	for project, _ in pairs(projects) do
		table.insert(project_list, project)
	end
	table.sort(project_list)

	pickers
		.new({}, {
			prompt_title = "Todo Projects",
			finder = finders.new_table({
				results = project_list,
				entry_maker = function(entry)
					return {
						value = entry,
						display = "+" .. entry,
						ordinal = entry,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					-- Filter by the selected project
					todotxt.telescope_filter_by_project(selection.value)
				end)

				return true
			end,
		})
		:find()
end

--- Use Telescope to filter tasks by a specific project
--- @param project string: The project to filter by
--- @return nil
todotxt.telescope_filter_by_project = function(project)
	local has_telescope, telescope = pcall(require, "telescope")
	if not has_telescope then
		vim.notify("Telescope is not installed", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	-- Get tasks from todo.txt file
	local lines = {}
	local is_todo_file = vim.api.nvim_buf_get_name(0) == config.todotxt

	if is_todo_file then
		lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	else
		lines = read_lines(config.todotxt)
	end

	-- Filter tasks that have the specified project
	local filtered_lines = {}
	for i, line in ipairs(lines) do
		if line:match("%+" .. project) then
			table.insert(filtered_lines, { line = line, index = i })
		end
	end

	pickers
		.new({}, {
			prompt_title = "Tasks for Project +" .. project,
			finder = finders.new_table({
				results = filtered_lines,
				entry_maker = function(entry)
					-- Check if task is completed
					local completed = entry.line:match("^x %d%d%d%d%-%d%d%-%d%d") ~= nil
					-- Create display with completion status indicator
					local display = (completed and "[✓] " or "[ ] ") .. entry.line

					return {
						value = entry.line,
						display = display,
						ordinal = entry.line,
						lnum = entry.index,
						completed = completed,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				-- Complete/uncomplete task with <C-space>
				map("i", "<C-space>", function()
					local selection = action_state.get_selected_entry()
					local line = selection.value
					local updated_line

					-- Toggle completion status
					if line:match("^x %d%d%d%d%-%d%d%-%d%d ") then
						-- Task is completed - uncomplete it
						updated_line = line:gsub("^x %d%d%d%d%-%d%d%-%d%d ", "")
						selection.completed = false
					else
						-- Task is not completed - complete it
						local date = os.date("%Y-%m-%d")
						updated_line = "x " .. date .. " " .. line
						selection.completed = true
					end

					-- Update the task in both Telescope and the file
					selection.value = updated_line
					selection.display = (selection.completed and "[✓] " or "[ ] ") .. updated_line
					selection.ordinal = updated_line

					-- Refresh the Telescope view
					action_state.set_selected_entry(selection)

					-- Update the file
					local todo_lines = read_lines(config.todotxt)
					for i, l in ipairs(todo_lines) do
						if l == line then
							todo_lines[i] = updated_line
							break
						end
					end

					write_lines(config.todotxt, todo_lines)

					-- Update buffer if we're in the todo file
					if is_todo_file then
						vim.api.nvim_buf_set_lines(0, 0, -1, false, todo_lines)
					end

					return true -- Keep Telescope open
				end)

				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					-- If we're not already in the todo file, open it
					if not is_todo_file then
						vim.cmd("split " .. config.todotxt)
					end

					-- Jump to the line
					if selection.lnum then
						vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
					end
				end)

				return true
			end,
		})
		:find()
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
