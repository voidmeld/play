--!strict

export type Outcome = { ok: boolean, stdout: string, stderr: string }
export type Runner = (argv: { string }) -> Outcome

local LintBatches = {}

LintBatches.BATCH_SIZE = 25
LintBatches.ATTEMPTS = 3
LintBatches.CRASH_SIGNATURES = table.freeze({
	"Cannot resume a non-thread reference",
	"lua_State* L is nullptr",
})

function LintBatches.batches(files: { string }, size: number): { { string } }
	assert(size >= 1 and size % 1 == 0, "batch size must be a positive integer")
	local out: { { string } } = {}
	local current: { string } = {}
	for _, path in files do
		table.insert(current, path)
		if #current == size then
			table.insert(out, current)
			current = {}
		end
	end
	if #current > 0 then
		table.insert(out, current)
	end
	return out
end

function LintBatches.isRuntimeCrash(outcome: Outcome): boolean
	if outcome.ok then
		return false
	end
	local text = outcome.stdout .. "\n" .. outcome.stderr
	for _, signature in LintBatches.CRASH_SIGNATURES do
		if string.find(text, signature, 1, true) ~= nil then
			return true
		end
	end
	return false
end

function LintBatches.run(base: { string }, files: { string }, runner: Runner): (boolean, string)
	local report: { string } = {}
	for index, batch in LintBatches.batches(files, LintBatches.BATCH_SIZE) do
		local argv = table.clone(base)
		for _, path in batch do
			table.insert(argv, path)
		end
		local outcome: Outcome = runner(argv)
		local attempt = 1
		while LintBatches.isRuntimeCrash(outcome) and attempt < LintBatches.ATTEMPTS do
			attempt += 1
			table.insert(report, ("lint batch %d: runtime crash, attempt %d"):format(index, attempt))
			outcome = runner(argv)
		end
		if not outcome.ok then
			local reason = if LintBatches.isRuntimeCrash(outcome)
				then "runtime crash persisted after " .. LintBatches.ATTEMPTS .. " attempts"
				else "lint violations"
			table.insert(report, ("lint batch %d failed: %s"):format(index, reason))
			table.insert(report, outcome.stdout)
			table.insert(report, outcome.stderr)
			return false, table.concat(report, "\n")
		end
	end
	return true, table.concat(report, "\n")
end

return table.freeze(LintBatches)
