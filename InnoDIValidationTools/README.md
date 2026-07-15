# InnoDIValidationTools

Companion SwiftPM package for consumers that want InnoDI's build-time DAG
validator without compiling the source coordinator tool in every dependency
graph.

The main `InnoDI` package remains the default integration path. Use this
package only when consumer build-cost measurements show that the prebuilt
validator is worth the extra release artifact dependency.

> Important: this directory is currently an unpublished release scaffold. Its
> checked-in artifact is an intentional fail-fast placeholder, not a usable
> validator. Do not add this package as a consumer dependency until an InnoDI
> release explicitly publishes and verifies the real prebuilt artifact.

## Usage

Add both packages at the same tag:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", exact: "<tag>"),
    .package(url: "https://github.com/InnoSquadCorp/InnoDIValidationTools.git", exact: "<tag>"),
]
```

Attach exactly one validation plugin to each target:

```swift
.target(
    name: "YourFeature",
    dependencies: [
        .product(name: "InnoDI", package: "InnoDI"),
    ],
    plugins: [
        .plugin(name: "InnoDIPrebuiltDAGValidationPlugin", package: "InnoDIValidationTools"),
    ]
)
```

Do not attach `InnoDIDAGValidationPlugin` and
`InnoDIPrebuiltDAGValidationPlugin` to the same target. Both plugins run the
same validator and write the same artifact names, so attaching both double-runs
the gate.

## Platform Support

The first prebuilt release supports macOS hosts. Linux, local package
development, and unsupported binary-artifact environments should keep using the
source plugin from the main InnoDI package.

## Local Artifact Preparation

`Package.swift` points at a local artifact bundle by default so release
automation can build and verify the package before publishing:

```sh
Tools/prepare-release-artifact.sh --tag <tag> --source-path ../ --output-dir Artifacts
```

Run the example from inside `InnoDIValidationTools` so `--source-path ../`
points at the repository root; adjust `--source-path` when using a different
working directory.

For a public release, pass `--release-url` and `--update-package` so the
manifest's binary target is updated to use a remote URL with a computed checksum.
