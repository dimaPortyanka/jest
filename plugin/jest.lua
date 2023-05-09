local ns = vim.api.nvim_create_namespace("jest")

local function parse_test_output(data)
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
							title = assert_res.title
						}
					)
				end
			end
		end
	end

	return test_results
end

local function get_test_names_lines(ast_node, hash_test_name_line)
	if ast_node.kind ~= vim.lsp.protocol.SymbolKind.Function then
		return
	end

	local name = ast_node.name
	local line = ast_node.range.start.line

	local pattern = '^test%([\'\"](.+)[\'\"]%) callback'
	local test_name = string.match(name, pattern)
	if test_name ~= nil then
		hash_test_name_line[test_name] = line
		return
	end

	for _, child in ipairs(ast_node.children) do
		get_test_names_lines(child, hash_test_name_line)
	end
end

local function get_function_calls()
	local uri = vim.uri_from_bufnr(0)
	local request = {
		textDocument = { uri = uri }
	}

	vim.wait(1000, function ()
		return vim.lsp.buf.server_ready()
	end)

	local response = vim.lsp.buf_request_sync(0, 'textDocument/documentSymbol', request)

	local function_calls = {}

	for _, single_response in ipairs(response) do
		for _, child in ipairs(single_response.result) do
			get_test_names_lines(child, function_calls)
		end
	end

	return function_calls
end

local extra_marks = {}

vim.api.nvim_create_autocmd({"BufWritePost", "BufEnter"}, {
	pattern = {
		'*.spec.tsx',
		'*.test.tsx',
		'*.test.jsx',
		'*.spec.jsx',
		'*.test.js',
		'*.test.ts',
		'*.spec.ts',
		'*.spec.js'
	},
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
								text = {"failed test", "error"}
							end

							table.insert(
								extra_marks,
								vim.api.nvim_buf_set_extmark(0, ns, calls[test_result.title], 0, {
									virt_text = { text }
								})
							)

						end
					end)
				end,
		})
	end
})

