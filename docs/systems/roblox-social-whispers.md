# Whisper session host

[System catalog](../systems.md) · [Chat transport](roblox-chat.md)

Coordinate platform-owned direct-chat channels and session projections.
Import [roblox/social-whispers](../../src/roblox/social-whispers.luau), configure a symmetric pair
name and display fallback, then call `create` with realm, channel-open/close and name ports.

## State shape

The coordinator holds symmetric per-subject channel views and a per-pair pending flag. It stores no
message text. Native channels, filtering and communication permissions belong to the host platform.

## Operations and required host operations

`open` admits distinct subjects in the same realm, serializes concurrent opens for the pair and
revalidates both realm identities after the host returns. `projection` provides sorted recipient
views. `close` removes both cached sides and closes native channels, returning affected subjects.
The host must enforce current platform direct-chat permission, create/mark/seat channels, return
refusals and dispose channels when requested. The game owns namespace, display policy and native lifetime.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-messaging.verify.luau
```

The [fixture](../../src/roblox/social-messaging.verify.luau) checks reentrant open exclusion,
symmetric views/disposal and a realm change during the asynchronous host operation.

## Invariants

- Each pair has at most one in-flight open attempt.
- Presence and the admitted realm are rechecked after channel creation.
- A stale successful open is disposed without adding cached views.
- Pending exclusion is cleared even when the platform callback throws.
- Closing a subject removes its peer views; platform message handling remains external.
