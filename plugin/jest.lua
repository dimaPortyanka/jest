local ns = vim.api.nvim_create_namespace("jest")

local parse_test_output = function(data)
	local test_results = {}

	for _, v in pairs(data) do
		local obj = vim.json.decode(v)
		if obj then
			for _, test_result in pairs(obj.testResults) do
				for _, assert_res in pairs(test_result.assertionResults)  do
					table.insert(
						test_results,
						{
							status = assert_res.status,
							fullName = assert_res.fullName
						}
					)
				end
			end
		end
	end

	return test_results
end

local get_function_calls = function()
	local uri = vim.uri_from_bufnr(0)
	local request = {
		textDocument = { uri = uri }
	}

	vim.wait(1000, function ()
		return vim.lsp.buf.server_ready()
	end)

	local response = vim.lsp.buf_request_sync(0, 'textDocument/documentSymbol', request)

	-- Extract function calls from the response
	if response == nil then
		return
	end

	local function_calls = {}
	for _, symbol in ipairs(response[1].result) do
		if symbol.kind == vim.lsp.protocol.SymbolKind.Function then
			local name = symbol.name
			local line = symbol.range.start.line

			-- pattern matches extracting text inside e.g test('text to extract') callback
			local pattern = '^test%([\'\"](.+)[\'\"]%) callback'
			local test_name = string.match(name, pattern)

			if test_name ~= nil then
				function_calls[test_name] = line
			end
		end
	end

	return function_calls
end

local extra_marks = {}

vim.api.nvim_create_autocmd({"BufWritePost", "BufRead"}, {
	pattern="*",
	callback = function ()
		local calls = get_function_calls()

		local path = vim.fn.expand('%:p:h:s?' .. vim.fn.getcwd() .. '/?./?' .. ':')
		local filename = vim.fn.expand('%:t')
		local relative_path = vim.fn.fnamemodify(path .. '/' .. filename, ':.')

		for _, extra_mark_id in ipairs(extra_marks) do
			vim.api.nvim_buf_del_extmark(0, ns, extra_mark_id)
		end

		vim.fn.jobstart(
			'npx jest --json ' .. relative_path,
			{
				on_stdout = function(_, data)
					pcall(function ()
						local test_results = parse_test_output(data)

						for _, test_result in ipairs(test_results) do
							local text
							if test_result.status == 'passed' then
								text = {"passed test", "info"}
							elseif test_result.status == 'failed' then
								print('failed'..' '..test_result.fullName)
								text = {"failed test", "error"}
							end

							table.insert(
								extra_marks,
								vim.api.nvim_buf_set_extmark(0, ns, calls[test_result.fullName], 0, {
									virt_text = { text }
								})
							)

						end
					end)
				end,
		})
	end
})

