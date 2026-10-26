--!strict

local Benchmark = require("../.lute/dependencies/verify/src/benchmark")
local create = require("./war-workload")

local phases: { Benchmark.Phase } = {}
for _, phase in create() do
	table.insert(phases, {
		name = phase.name,
		run = function(_state: unknown, _sampler: Benchmark.Sampler)
			phase.run()
		end,
	})
end

local spec: Benchmark.Spec = {
	name = "war-200",
	unit = "milliseconds",
	warmup = 100,
	samples = 1000,
	phases = phases,
	environment = { observed = "Lute interpreter; synthetic 200-player war tick" },
}

return spec
