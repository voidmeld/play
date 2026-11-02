--!strict

local Mailbox = require("./mail/mailbox")

export type MailboxInventory = Mailbox.Inventory
export type MailboxAccount = Mailbox.Account
export type MailboxStack = Mailbox.Stack
export type MailboxAttachments = Mailbox.Attachments
export type MailboxPhase = Mailbox.Phase
export type MailboxEnvelope = Mailbox.Envelope
export type MailboxPointer = Mailbox.Pointer
export type MailboxConfig<T> = Mailbox.Config<T>
export type MailboxMailbox<T> = Mailbox.Mailbox<T>

export type API = {
	read mailbox: typeof(Mailbox),
}

local api: API = {
	mailbox = Mailbox,
}

return table.freeze(api)
