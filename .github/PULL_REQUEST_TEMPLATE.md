<!--
Thanks for contributing to InnoDI. Please fill in the sections below so the
review can stay focused. Strike through (`~~text~~`) any sections that do not
apply to your change.
-->

## Summary

<!-- 1-3 sentences describing what changed and why. Link the issue or RFC if
     one exists. -->

## Why

<!-- Explain the motivation. What user problem does this solve, or what
     hidden risk does it surface? Avoid restating the diff. -->

## Behavior changes

<!-- Bullet any user-visible behavior change: macro diagnostics, generated
     code shape, build plugin output, schema, public API. Write `none` if
     this is a docs/CI/test-only change. -->

## Test plan

- [ ] `swift test`
- [ ] `swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
- [ ] Macro snapshot updates were intentional (`Tools/record-macro-snapshots.sh`
      diff reviewed) — or **N/A**
- [ ] Extended examples build (`Examples/SwiftUIExample`,
      `Examples/PreviewInjectionExample`) — or **N/A**
- [ ] Manual verification (describe):

## Documentation contract

- [ ] `README.md` updated, and the six localized mirrors
      (`README.{ko,ja,zh-Hans,de,es,ru}.md`) match its structure (the strict
      sync gate runs on PRs)
- [ ] `RELEASING.md` Unreleased section updated when behavior, schema, or
      public API changed
- [ ] `ROADMAP.md` updated when an experimental feature changed phase
- [ ] DocC catalog updated for any public-API change

## Compatibility & risk

<!-- Strict-concurrency impact, ABI/source compatibility, schema versioning
     for build plugin artifacts, App Store / Privacy Manifest impact. Use
     "none" liberally — but say so explicitly. -->

## Reviewer checklist (filled by reviewer)

- [ ] Generated code in macro snapshots is readable and intentional
- [ ] No new `fatalError` in macro-source targets (or allow-list updated)
- [ ] No new Required Reason API usage in `InnoDI` / `InnoDISwiftUI` without
      a corresponding `PrivacyInfo.xcprivacy` entry
- [ ] `validateDAG: false` not introduced casually
