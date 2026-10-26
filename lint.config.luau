--!strict

return {
	lute = {
		lint = {
			ignores = { ".lute/**" },
			globals = {},
			rulepaths = {
				"tools/lint-rules/global_table_usage.luau",
				"tools/lint-rules/type_check_inside_call.luau",
				"tools/lint-rules/bad_string_escape.luau",
			},
			ruleconfigs = {
				global_function_in_scope = { off = true },
				unused_variable = { off = true },
			},
		},
	},
}
