--!strict

local Contact = require("./combat/contact")
export type API = { read contact: typeof(Contact) }
local api: API = { contact = Contact }
return table.freeze(api)
