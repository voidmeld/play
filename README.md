# Play

Play supplies strict Luau state transitions, transaction recovery and host coordination.
Consumers supply configuration, content, authority, clocks, storage and native operations.
Core rules stay independent of an engine. Native adapters use injected ports.

First, run one fixture with the [quickstart](docs/quickstart.md).

## Documentation

| Task | Document |
| --- | --- |
| Run the first fixture | [Quickstart](docs/quickstart.md) |
| Find public calls, returns and failures | [API reference](docs/api.md) |
| Bind storage, clocks and native resources | [Host operations](docs/api.md#host-operations) |
| Choose a reusable boundary and pin a consumer | [Adoption](docs/adoption.md) |
| Understand library boundaries | [Architecture](docs/architecture.md) |
| Set up tools or diagnose checks | [Validation](docs/validation.md) |
| Change this repository | [Maintainer guide](AGENTS.md) and [contributing](CONTRIBUTING.md) |

## Packages

| Surface | Purpose |
| --- | --- |
| `src/kernel` | Shared values, results, codecs, leases and atomic store contracts. |
| `src/core/<family>` | Configured rules and engine-independent coordinators. Each entry exports an `API` type and component aliases. |
| `src/roblox/<adapter>` | Typed native adapters over supplied operations. |
| `src/test-scene` | Deterministic fixtures for verification. Exclude this surface from shipped runtime trees. |

Import only the selected public entries. Preserve relative paths between runtime surfaces.
Keep authoritative state transitions under the consumer's server authority boundary.

## Pin and consume

Select an immutable commit of `https://github.com/voidmeld/play.git` and its exact tree.
Record both in the consumer's dependency lock. Private access uses the operator's existing Git setup.
The library's [lock](dependencies.lock.luau) pins development dependencies; it is not a consumer installer.
Run the affected consumer specifications after a pin change.

## Compatibility

The supported unit is an exact commit and tree. There is no semantic-version release promise.
Exported declarations, refusal meanings and saved schemas are contracts.
Change a contract with its consumers. Keep policy, migration evidence and native acceptance in those consumers.
Internal helpers and verification fixtures are not supported runtime APIs.

## License

Play is MIT licensed. Access to this repository is private.
See [LICENSE](LICENSE) and the pinned [dependencies](dependencies.lock.luau).
