--!strict

local Parser = require("@std/syntax/parser")
local Surface = require("../../.lute/dependencies/verify/src/checks/surface")
local Syntax = require("@std/syntax/types")
local fs = require("@std/fs")

type Functions = { [string]: Syntax.CstExprFunction }
type Location = { read beginLine: number, read beginColumn: number, read endLine: number, read endColumn: number }

local function slice(source: string, location: Location): string
	local lines = string.split(source, "\n")
	local selected: { string } = {}
	for index = location.beginLine, location.endLine do
		local line = lines[index] or ""
		local first = if index == location.beginLine then location.beginColumn else 1
		local last = if index == location.endLine then location.endColumn - 1 else #line
		table.insert(selected, string.sub(line, first, last))
	end
	return table.concat(selected, "\n")
end

local function signature(source: string, func: Syntax.CstExprFunction): string
	local ending = if func.returnAnnotation ~= nil then func.returnAnnotation.location else func.closeParens.location
	return slice(source, {
		beginLine = func.functionKeyword.location.beginLine,
		beginColumn = func.functionKeyword.location.beginColumn,
		endLine = ending.endLine,
		endColumn = ending.endColumn,
	})
end

local function functions(source: string, block: Syntax.CstStatBlock): Functions
	local out: Functions = {}
	for _, stat in block.statements do
		if stat.tag == "function" then
			local name = if stat.name.tag == "indexname"
				then stat.name.index.text
				else slice(source, stat.name.location)
			out[name] = stat.func
		elseif stat.tag == "localfunction" then
			out[stat.name.name.text] = stat.func
		end
	end
	return out
end

local function returnedTable(expr: Syntax.CstExpr): Syntax.CstExprTable?
	if expr.tag == "table" then
		return expr
	elseif expr.tag == "call" and #expr.arguments == 1 then
		return returnedTable(expr.arguments[1])
	end
	return nil
end

local function unwrapped(expr: Syntax.CstExpr): Syntax.CstExpr
	if expr.tag == "call" and #expr.arguments == 1 then
		return unwrapped(expr.arguments[1])
	end
	return expr
end

local function returns(source: string, func: Syntax.CstExprFunction, outer: Functions): { string }
	local scope = table.clone(outer)
	for name, value in functions(source, func.body) do
		scope[name] = value
	end
	local out: { string } = {}
	for _, stat in func.body.statements do
		if stat.tag ~= "return" then
			continue
		end
		for _, expr in stat.expressions do
			local record = returnedTable(expr)
			if record == nil then
				local name = slice(source, unwrapped(expr).location)
				for _, member in func.body.statements do
					if
						member.tag == "function"
						and member.name.tag == "indexname"
						and slice(source, member.name.expression.location) == name
					then
						table.insert(out, member.name.index.text .. " = " .. signature(source, member.func))
					end
				end
				continue
			end
			for _, item in record.entries do
				if item.kind ~= "record" then
					continue
				end
				local value = item.value
				local resolved = if value.tag == "function"
					then value
					elseif value.tag == "local" then scope[value["local"].name.text]
					else nil
				local declaration = if resolved ~= nil
					then signature(source, resolved)
					else slice(source, value.location)
				table.insert(out, item.key.text .. " = " .. declaration)
			end
		end
	end
	return out
end

local function renderSource(input: string, prefix: string, entry: string, exported: { string }): string
	local source = string.gsub(input, "\r\n", "\n")
	local block = Parser.parseBlock(source)
	local declared = functions(source, block)
	for _, stat in block.statements do
		if stat.tag == "return" then
			for _, expr in stat.expressions do
				local record = returnedTable(expr)
				if record ~= nil then
					for _, item in record.entries do
						if item.kind == "record" then
							if item.value.tag == "local" then
								declared[item.key.text] = declared[item.value["local"].name.text]
							elseif item.value.tag == "function" then
								declared[item.key.text] = item.value
							end
						end
					end
				end
			end
		end
	end
	local out = { "## `" .. prefix .. "`", "", "[Source](../" .. entry .. ")", "" }
	for _, stat in block.statements do
		if stat.tag == "local" then
			for _, value in stat.values do
				if value.tag == "call" and slice(source, value.func.location) == "require" then
					table.insert(out, "```luau\n" .. slice(source, stat.location) .. "\n```\n")
				end
			end
		elseif stat.tag == "typealias" and stat.isExported then
			table.insert(out, "### `" .. prefix .. "." .. stat.name.text .. "`\n")
			table.insert(out, "```luau\n" .. slice(source, stat.location) .. "\n```\n")
		end
	end
	local names = table.clone(exported)
	table.sort(names)
	for _, name in names do
		table.insert(out, "### `" .. prefix .. "." .. name .. "`\n")
		local func = declared[name]
		if func ~= nil then
			table.insert(out, "```luau\n" .. signature(source, func) .. "\n```\n")
			local fields = returns(source, func, declared)
			if #fields > 0 then
				table.insert(out, "Returned operations and values (declarations; unannotated results are inferred):\n")
				table.insert(out, "```luau\n" .. table.concat(fields, "\n") .. "\n```\n")
			end
		else
			table.insert(out, "Exported value; see its declaration in [source](../" .. entry .. ").\n")
		end
	end
	return table.concat(out, "\n")
end

local function render(packages: { Surface.Package }): string
	local out = {
		"# Public API",
		"",
		"Generated by `lute run tools/generate-api.luau --write`; do not edit by hand.",
		"The gate checks freshness against parsed exported types, function declarations and returned operations.",
		"Use `src/core/<system>.luau` as the system entry; its API type names each component.",
		"Existing component paths remain compatible. The roblox modules are individual adapter entries.",
		"Test-scene entries are verification fixtures. Internal implementations are excluded.",
		"For behavior, host requirements and examples, see [Systems](systems.md).",
		"",
	}
	for _, package in packages do
		local value = package.load()
		assert(type(value) == "table", package.entry .. " must return a table")
		local names: { string } = {}
		for key in value do
			assert(type(key) == "string", package.entry .. " exports a non-string key")
			table.insert(names, key)
		end
		table.insert(out, renderSource(fs.readFileToString(package.entry), package.prefix, package.entry, names))
	end
	return table.concat(out, "\n")
end

return table.freeze({ render = render, renderSource = renderSource })
