-- TODO: remove extmark when test pass
-- iterate over all tests and check if they are passing
-- remove extmark "failed test" if now they pass
-- add to diagnostic failed tests
-- nvim_buf_del_extmark
local ns = vim.api.nvim_create_namespace("jest")

local parse_test_output = function(data)
	local failed_tests_names = {}
	for _, v in pairs(data) do
		local obj = vim.json.decode(v)
		if obj then
			for _, test_result in pairs(obj.testResults) do
				for _, assert_res in pairs(test_result.assertionResults)  do
					print(vim.inspect(assert_res))
					if assert_res.status == 'failed' then
						table.insert(failed_tests_names, assert_res.fullName)
					end
				end
			end
		end
	end

	return failed_tests_names
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


vim.api.nvim_create_autocmd({"BufWritePost", "BufRead"}, {
	pattern="*",
	callback = function ()
		local calls = get_function_calls()

		local path = vim.fn.expand('%:p:h:s?' .. vim.fn.getcwd() .. '/?./?' .. ':')
		local filename = vim.fn.expand('%:t')
		local relative_path = vim.fn.fnamemodify(path .. '/' .. filename, ':.')

		vim.fn.jobstart(
			'npx jest --json ' .. relative_path,
			{
				on_stdout = function(_, data)
					pcall(function ()
						local failed_tests_names = parse_test_output(data)

						for _, failed_test_name in ipairs(failed_tests_names) do
							local text = {"failed test", "error"}

							vim.api.nvim_buf_set_extmark(0, ns, calls[failed_test_name], 0, {
								virt_text = { text }
							})
						end
					end)
				end,
		})
	end
})

