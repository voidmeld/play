--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Contexts = require("./input-contexts")
local Verify = require("../../.lute/dependencies/verify/src/core")
type Node = { name: string, kind: string, children: { [string]: Node } }

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("input contexts", function()
		it(
			"shares a deadline across context and action readiness and rejects missing or wrong-class actions",
			function()
				local action: Node = { name = "Action", kind = "action", children = {} }
				local context: Node = { name = "Context", kind = "context", children = { Action = action } }
				local root: Node = { name = "Root", kind = "folder", children = { Context = context } }
				local now = 0
				local budgets: { number } = {}
				local input = Contexts.create({
					find = function(node: Node, name: string): Node?
						return node.children[name]
					end,
					wait = function(node: Node, name: string, seconds: number): Node?
						table.insert(budgets, seconds)
						now += 1
						return node.children[name]
					end,
					clock = function()
						return now
					end,
					minimumWait = 0.25,
					isContext = function(node: Node)
						return node.kind == "context"
					end,
					asAction = function(node: Node): Node?
						return if node.kind == "action" then node else nil
					end,
					name = function(node: Node)
						return node.name
					end,
				})
				expect(input.context(root, { "Context" }, { "Action" }, 3)):toBe(context)
				expect(budgets):toEqual({ 3, 2 })
				expect(input.action(context, "Action")):toBe(action)
				expect(function()
					input.action(context, "missing")
				end):toThrow("missing authored InputAction")
				action.kind = "folder"
				expect(function()
					input.action(context, "Action")
				end):toThrow("missing authored InputAction")
			end
		)
		it("reuses existing server contexts and fails closed when their query throws", function()
			local adopted = 0
			local present: unknown = nil
			local phases = { mounted = "mounted", refused = "refused" }
			local plan = { { folder = "Inputs", name = "Context" } }
			local surfaces = {
				existing = function(_name: string): unknown?
					return present
				end,
				template = function(_folder: string, _name: string): unknown?
					return "template"
				end,
				adopt = function(_template: unknown, _name: string): unknown?
					adopted += 1
					present = "mounted"
					return present
				end,
			}
			local mounted = Contexts.mount(plan, surfaces, phases)
			expect(mounted.phase):toBe("mounted")
			expect(table.isfrozen(mounted.names)):toBe(true)
			expect(Contexts.mount(plan, surfaces, phases).phase):toBe("mounted")
			expect(adopted):toBe(1)
			surfaces.existing = function(_name: string): unknown?
				error("query failed")
			end
			expect(Contexts.mount(plan, surfaces, phases).reason):toBe("existing_failed:Context")
			expect(table.isfrozen(Contexts.mount(plan, surfaces, phases).names)):toBe(true)
			expect(adopted):toBe(1)
		end)
	end)
end
