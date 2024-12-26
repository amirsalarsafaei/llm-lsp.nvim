local M = {}

-- Configuration for OpenAI API
local OPENAI_API_KEY = os.getenv("OPENAI_API_KEY") or ""
local OPENAI_API_URL = (os.getenv("OPENAI_API_URL") or "https://api.openai.com/v1/") .. "chat/completions"

-- Logger setup
local LOG_FILE = vim.fn.stdpath("data") .. "/batcow.log"

local function log(message)
	local file = io.open(LOG_FILE, "a")
	if file then
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		file:write(string.format("[%s] %s\n", timestamp, message))
		file:close()
	end
end

-- Utility function to get LSP suggestions at current position
function M.get_lsp_suggestions()
	local params = vim.lsp.util.make_position_params()
	local results = {}

	local response = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 1000)

	if response then
		for _, server_response in pairs(response) do
			if server_response.result and server_response.result.items then
				results = server_response.result.items
				break
			end
		end
	end

	log(string.format("Got %d LSP suggestions", #results))
	return results
end

-- Calculate Levenshtein distance between two strings
local function levenshtein(str1, str2)
	local len1, len2 = #str1, #str2
	local matrix = {}

	for i = 0, len1 do
		matrix[i] = { [0] = i }
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end

	for i = 1, len1 do
		for j = 1, len2 do
			local cost = str1:sub(i, i) == str2:sub(j, j) and 0 or 1
			matrix[i][j] = math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
		end
	end

	return matrix[len1][len2]
end

-- Calculate similarity score (0 to 1)
local function similarity_score(str1, str2)
	local max_len = math.max(#str1, #str2)
	if max_len == 0 then
		return 1
	end
	local distance = levenshtein(str1, str2)
	return 1 - (distance / max_len)
end

function M.combine_probabilities(claude_probs, lsp_items)
	local combined = {}
	local lsp_weight = 0.3 -- Adjust this weight to balance LSP vs Claude
	local similarity_threshold = 0.7 -- Minimum similarity score to consider a match

	-- Create a score map for LSP items (simple linear distribution)
	local lsp_scores = {}
	for i, item in ipairs(lsp_items) do
		lsp_scores[item.label] = 1 - (i / #lsp_items)
	end

	-- Combine probabilities with similarity matching
	for token, prob in pairs(claude_probs) do
		local best_similarity = 0
		local best_lsp_score = 0

		-- Find best matching LSP suggestion
		for lsp_token, lsp_score in pairs(lsp_scores) do
			local sim = similarity_score(token, lsp_token)
			if sim > best_similarity and sim >= similarity_threshold then
				best_similarity = sim
				best_lsp_score = lsp_score
			end
		end

		-- Weight the scores based on similarity
		local final_lsp_score = best_lsp_score * best_similarity
		combined[token] = (prob * (1 - lsp_weight)) + (final_lsp_score * lsp_weight)

		-- Log similarity matching results
		log(string.format("Token '%s' best similarity: %f, LSP score: %f", token, best_similarity, final_lsp_score))
	end

	-- Log the combined probabilities
	for token, prob in pairs(combined) do
		log(string.format("Combined probability for token '%s': %f", token, prob))
	end

	return combined
end

-- Function to get weighted random choice
function M.weighted_choice(choices)
	local total = 0
	for _, prob in pairs(choices) do
		total = total + prob
	end

	local r = math.random() * total
	local sum = 0
	for token, prob in pairs(choices) do
		sum = sum + prob
		if r <= sum then
			return token
		end
	end
	return next(choices) -- fallback
end

-- Function to stream from OpenAI API with real-time updates
function M.stream_openai_response(buf)
	local curl = require("plenary.curl")

	-- Get cursor position
	local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
	local cursor_col = vim.api.nvim_win_get_cursor(0)[2]

	-- Get all buffer content
	local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	-- Create context string with buffer content and cursor position
	local prompt =
		"You need to complete the code from where cursor is you can not move your cursor elsewhere just start outputing what should be typed Buffer content. you will be asked to complete the code part by part. when you are done just output [DONE] without anything extra don't prematurely call the [DONE]:\n"

	for i, line in ipairs(all_lines) do
		if i - 1 == cursor_row then
			-- Mark cursor position with |
			prompt = prompt .. line:sub(1, cursor_col) .. "|<<cursor is here>>|" .. line:sub(cursor_col + 1) .. "\n"
			log("before cursor: " .. line)
		else
			prompt = prompt .. line .. "\n"
		end
	end

	-- Add cursor position information
	prompt = prompt
		.. "\nCursor position(marked by <<cursor is here>>): Line "
		.. (cursor_row + 1)
		.. ", Column "
		.. (cursor_col + 1)

	local lsp_items = M.get_lsp_suggestions()

	local lsp_probs = {}
	for i, item in ipairs(lsp_items) do
		if item.label and item.label:match("%S") then
			lsp_probs[item.label] = 1 - (i / #lsp_items)
		end
	end

	log(string.format("Created probability map with %d LSP items", vim.tbl_count(lsp_probs)))

	vim.schedule(function()
		vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row, false, { "" })
	end)

	local function on_callback(response)
		log("Response received: " .. tostring(response["body"]))
		if response then
			-- Parse the JSON response
			local ok, parsed = pcall(vim.json.decode, response["body"])
			if not ok then
				log("JSON parse error: " .. tostring(parsed))
				return
			end

			if parsed and parsed.choices and parsed.choices[1] then
				local choice = parsed.choices[1]
				local content = ""
				local logprobs = {}

				-- Handle both streaming and non-streaming formats
				if choice.message then
					content = choice.message.content
				elseif choice.text then
					content = choice.text
				end

				-- Check if we're done or need to continue
				if content == "[DONE]" then
					log("Completion finished")
					_G.finished = true
					return
				end

				-- Extract logprobs if available
				if choice.logprobs and choice.logprobs.top_logprobs then
					for _, token_logprobs in ipairs(choice.logprobs.top_logprobs) do
						for token, prob in pairs(token_logprobs) do
							-- Convert log probability to regular probability
							logprobs[token] = math.exp(prob)
						end
					end
					log(string.format("Received logprobs for %d tokens", vim.tbl_count(logprobs)))
				end

				if vim.api.nvim_get_mode().mode ~= "i" then
					vim.cmd("startinsert")
				end

				-- Get current buffer content
				local current_lines = vim.api.nvim_buf_get_lines(buf, cursor_row, cursor_row + 1, false)
				local current_line = current_lines[1] or ""

				if content:match("\n") then
					-- Handle multiline content
					local new_lines = vim.split(current_line .. content, "\n")

					-- Replace current line and add new lines
					vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row + 1, false, new_lines)

					-- If there are additional lines, insert them
					if #new_lines > 1 then
						-- Update cursor position to last line
						cursor_row = cursor_row + #new_lines - 1
						local last_line = new_lines[#new_lines]
						-- Set cursor to end of last line
						vim.api.nvim_win_set_cursor(0, { cursor_row + 1, #last_line })
					end
				else
					-- Handle single line content
					log("Content: " .. content)
					-- Insert content at cursor position
					local new_content = current_line:sub(1, cursor_col) .. content .. current_line:sub(cursor_col + 1)
					vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row + 1, false, { new_content })

					-- Move cursor after inserted content
					vim.api.nvim_win_set_cursor(0, { cursor_row + 1, cursor_col + #content })
				end

				-- Force redraw
				vim.cmd("redraw")
			end
		end
	end

	-- Validate API key
	if OPENAI_API_KEY == "" then
		vim.notify("OpenAI API key not found. Please set OPENAI_API_KEY environment variable.", vim.log.levels.ERROR)
		log("Error: OpenAI API key not found")
		return
	end

	-- Log request details
	log("Making API request with prompt length: " .. #prompt)

	-- Make streaming request
	local success, result = pcall(curl.post, OPENAI_API_URL, {
		headers = {
			["Authorization"] = "Bearer " .. OPENAI_API_KEY,
			["Content-Type"] = "application/json",
			["Accept"] = "application/json",
		},
		body = vim.json.encode({
			model = "gpt-4",
			messages = {
				{
					role = "user",
					content = prompt,
				},
			},
			temperature = 0.8,
			top_p = 0.9,
			max_tokens = 10,
			n = 5,
			logprobs = true, -- Retrieve log probabilities for the top 5 tokens
			stream = false,
		}),
		on_error = function(error)
			local error_msg = "API request failed: " .. (error.message or "Unknown error")
			vim.schedule(function()
				vim.notify(error_msg, vim.log.levels.ERROR)
			end)
			log("Error: " .. error_msg)
		end,
	})

	if not success then
		local error_msg = "Failed to make API request: " .. tostring(result)
		vim.schedule(function()
			vim.notify(error_msg, vim.log.levels.ERROR)
		end)
		log("Error: " .. error_msg)
		return
	end

	return on_callback(result)
end

-- Function to handle AI responses
function M.get_ai_response(buf)
	_G.finished = false
	while not _G.finished do
		M.stream_openai_response(buf)
	end
end

-- Function to create floating window
function M.create_float()
	-- Clear log file when starting new session
	local file = io.open(LOG_FILE, "w")
	if file then
		file:close()
	end

	log("Creating new AI interface window")
	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
	})

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

	return buf, win
end

-- Variables to store original buffer context
local original_buf = nil
local original_cursor = nil

-- Main function to show AI interface
function M.show_ai_interface()
	-- Save current buffer info
	original_buf = vim.api.nvim_get_current_buf()
	original_cursor = vim.api.nvim_win_get_cursor(0)

	local buf, win = M.create_float()

	-- Set buffer content
	local content = {
		"=== Custom AI Assistant ===",
		"",
		"Type your prompt below:",
		"",
	}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

	-- Set cursor position and enter insert mode
	vim.api.nvim_win_set_cursor(win, { 4, 0 })
	vim.cmd("startinsert")

	-- Set up keymaps for this buffer
	local opts = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("n", "q", ":q<CR>", opts)
	vim.keymap.set("n", "<CR>", function()
		vim.api.nvim_win_close(win, true)
		M.get_ai_response(original_buf)

		vim.api.nvim_set_current_buf(original_buf)
		vim.api.nvim_win_set_cursor(0, original_cursor)
		vim.cmd("startinsert")
	end, opts)
end

M.setup = function()
	-- Create user command
	vim.api.nvim_create_user_command("AIAssist", function()
		M.show_ai_interface()
	end, {})
end

return M
