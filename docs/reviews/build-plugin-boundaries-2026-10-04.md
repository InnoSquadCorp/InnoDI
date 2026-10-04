# Build-plugin boundary qualification

Report items: P2-07, P2-09a and P2-09b. Baseline: `d6d0df3` on
`release/7.0.0-preparation`. The supplied report is an allegation; the results
below are separate local reproductions on 2026-10-04.

## SwiftPM reports and environment

`Tools/validate-build-plugin-contract.py` copies the complete production plugin
into a dependency-free SwiftPM package. A small probe executable replaces the
coordinator, emits the same three report names and records only the five
documented controls plus an unrelated test marker. A generated Swift declaration
is required by the Swift target to prove the compilation dependency. A separate
Clang target verifies that no generated Swift input is imposed on C sources.
This is an adapter test, not a substitute for graph-validation tests.

On the unmodified plugin, SwiftPM 6.4 copied the stamp, JSON metrics and Markdown
summary into both target resource bundles: six copied reports in total. Neither
probe command received any of the five controls. An environment-only change
also failed to rerun the Swift validation command. This reproduces the resource
classification and environment forwarding gaps; it does not establish that an
actual Apple application shipped those files.

The corrected plugin declares only its existing generated Swift ordering file
for Swift targets. Reports remain in the sandboxed work directory. Clang
targets use output-free commands; Xcode project targets retain their existing
output-free behavior. Only these values are forwarded, without interpretation:

- `INNODI_LOCK_TIMEOUT`
- `INNODI_STALE_LOCK_AGE`
- `INNODI_ALLOW_UNSAFE_LOCK`
- `INNODI_VALIDATION_VERBOSE`
- `INNODI_VALIDATION_DEBUG`

The coordinator retains validation and defaults. An unset unsafe-filesystem
override is not synthesized, and the filesystem classifier is unchanged.

Final adapter checks passed:

- Swift generated-source compilation and Clang compilation
- No report files copied into either target's resource bundle
- Unchanged Swift and Clang builds retain invocation count one
- A changed control reruns the Swift command and arrives with its exact value
- Explicit unsafe-lock opt-in is preserved; removing controls produces an
  empty observed control environment
- The unrelated marker is not forwarded
- A probe coordinator exiting with status 3 fails both Swift and Clang builds,
  including builds with previous successful outputs; restoring the controls
  lets both builds succeed again

An intermediate probe incorrectly expected every output-free Clang command to
rerun on an unchanged build. Actual SwiftPM behavior disproved that assertion;
the final test checks the observed no-op behavior. No production change was
made to force extra executions.

## Signature-lock owner evidence

The baseline signature-cache path creates `signature.lock` but never persists
its owner, unlike the live-validation lock. A leftover file therefore reaches
the unreadable-metadata age fallback even after its owner exits. The default
stale age and wait window are both 30 seconds; that duration is a policy value,
not a new wall-clock benchmark result.

The correction writes the existing PID, creation-time and boot-ID metadata
immediately after acquisition, under the existing release `defer`. The lock
recovery algorithm, unsafe-filesystem classification, explicit override policy
and fallback behavior are unchanged. Documentation and the timeout advice now
state that stale age applies to missing/unreadable metadata, not a known live
or dead PID.

The internal signature helper accepts the existing `ValidationSyntaxParsing`
boundary for deterministic tests, defaulting to `LiveValidationSyntaxParser`.
Root and validated-manifest collection use the same collector methods,
discovery paths and cache flags as the former convenience wrappers. No new
runtime callback or public API was added.

Four new tests check metadata while the real collector parses, recovery of the
captured bytes with a dead owner without sleeps, retention of an old live owner,
the unreadable-metadata age fallback and release before collection when metadata
encoding fails. With the metadata write removed and the same parser seam
retained for observation, the owner-recording and failure-ordering tests fail;
the live-owner and fallback controls pass. The candidate passed 34 tests in six
suites, including existing boot-ID, environment, filesystem and snapshot tests.

The snapshot race test previously mutated a source through `currentDate`, which
now also runs before signature collection. It instead uses the existing
live-lock recovery hook after planting a known-dead live-run lock. This preserves
the required post-signature mutation point. Against the original pre-snapshot-fix
source-built objects, the revised test still detects cached success for invalid
bytes; the corrected implementation passes.

An earlier FIFO observation fixture also failed against the metadata-writing
candidate and was discarded as an unreliable observation mechanism. Its failed
result is not evidence of a remaining product failure.

## Boundaries

The adapter builds ran with Linux Swift 6.4. The 34-test portable harness uses
source-built SwiftSyntax 604 and the existing test-only Linux `statfs` C-import
shim; it is not a full native package or Apple-platform test run. Xcode adapter
execution, multi-destination ordering and actual application packaging remain
Apple CI qualifications. The shipped ordering source contains only a comment;
the probe's declaration exists solely to test ordering.

Dead-owner recovery is exercised with metadata captured from the production
acquisition path and then restored as a dead owner's file. This is not a claim
that every process-kill point was tested. Interruptions before metadata is
written and during the separate `.recovering` token path remain distinct
limitations of the existing recovery design. No lock-reclamation criteria,
permissions, repository settings or prebuilt distribution were changed.
