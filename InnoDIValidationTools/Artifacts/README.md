# Artifacts

This directory includes a small fail-fast placeholder artifact so the companion
package manifest remains valid in a fresh checkout.

`Tools/prepare-release-artifact.sh` replaces
`InnoDIPrebuiltDAGValidationCoordinator.artifactbundle` with the real
coordinator binary for local acceptance and release packaging. Run the
preparation script before using this companion package as a local prebuilt
plugin dependency.
