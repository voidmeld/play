# Changelog

Play follows [semantic versioning](https://semver.org). While the version is `0.x`, a minor
release may change a public contract.

## 0.1.0

- First versioned release. Play is a `lute pkg` package: `pkg.luau` declares the package and
  its development dependencies, and consumers install it with `lute pkg install --vendor`.
- The package publishes a consumer skill (`.agents/skills/play`).
- The world example carries its own simulated network (`examples/world/network.luau`).
- Requires Lute `1.0.1-nightly.20261120` or newer.
