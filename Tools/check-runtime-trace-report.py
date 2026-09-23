#!/usr/bin/env python3
"""Fail closed on workload evidence before applying unchanged trace budgets."""

import json, math, re, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
if not re.fullmatch(r"[0-9a-f]{40}", report.get("candidateSHA", "")):
    raise SystemExit("runtime trace report needs its exact candidate SHA")
if (type(report.get("sourceTreeClean")) is not bool
        or not isinstance(report.get("compilerVersion"), str) or not report["compilerVersion"].strip()):
    raise SystemExit("runtime trace report needs source cleanliness and compiler provenance")
expected_sha = sys.argv[7] if len(sys.argv) > 7 else ""
if expected_sha and (report["candidateSHA"] != expected_sha or not report["sourceTreeClean"]):
    raise SystemExit("runtime trace report is not from the clean exact release candidate")
for key in ("iterations", "enabledIterations"):
    if type(report.get(key)) is not int or report[key] <= 0:
        raise SystemExit("runtime trace iterations must be positive integers")
disabled = report.get("disabledNetNanosecondsPerResolution")
enabled = report.get("enabledNanosecondsPerEvent")
expected_events = report.get("enabledIterations", 0) * 2
if report.get("schemaVersion") != 2:
    raise SystemExit("runtime trace report schemaVersion must equal 2")
if report.get("recordedEventCount") != expected_events:
    raise SystemExit("runtime trace benchmark lost enabled events")
for name, value in (("disabled", disabled), ("enabled", enabled)):
    if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
        raise SystemExit(f"runtime trace {name} measurement is invalid")
disabled_budget = float(sys.argv[2])
enabled_budget = float(sys.argv[3])
saturated_budget = float(sys.argv[4])
snapshot_budget = float(sys.argv[5])
contended_budget = float(sys.argv[6])
if not all(math.isfinite(budget) and budget > 0 for budget in
           [disabled_budget, enabled_budget, saturated_budget, snapshot_budget, contended_budget]):
    raise SystemExit("runtime trace budgets must be finite positive numbers")
saturated = report.get("saturatedMeasurements")
if not isinstance(saturated, list) or [item.get("capacity") for item in saturated] != [64, 4096, 65536]:
    raise SystemExit("runtime trace benchmark must report every saturated capacity")
for item in saturated:
    capacity = item["capacity"]
    emitted = item.get("emittedEventCount")
    retained = item.get("retainedEventCount")
    dropped = item.get("droppedEventCount")
    record_cost = item.get("nanosecondsPerEvent")
    snapshot_cost = item.get("snapshotNanosecondsPerRetainedEvent")
    if emitted != (capacity + report["enabledIterations"]) * 2:
        raise SystemExit("runtime trace saturated sample changed the enforced event count")
    if retained != capacity or dropped != emitted - capacity:
        raise SystemExit(f"runtime trace capacity {capacity} lost ring-buffer accounting")
    for name, value in (("saturated", record_cost), ("snapshot", snapshot_cost)):
        if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
            raise SystemExit(f"runtime trace {name} measurement is invalid")
    if record_cost > saturated_budget:
        raise SystemExit(f"saturated runtime trace overhead exceeds its budget at capacity {capacity}")
    if snapshot_cost > snapshot_budget:
        raise SystemExit(f"runtime trace snapshot overhead exceeds its budget at capacity {capacity}")

contention = report.get("contentionMeasurements")
if not isinstance(contention, list) or len(contention) != 5:
    raise SystemExit("runtime trace benchmark must report five writer and snapshot contention samples")
for index, item in enumerate(contention, start=1):
    if item.get("writerCount") != 4 or item.get("snapshotCount") != 64:
        raise SystemExit(f"runtime trace contention sample {index} changed the enforced workload")
    if item.get("eventsPerWriter", 0) * item.get("writerCount", 0) != item.get("emittedEventCount"):
        raise SystemExit(f"runtime trace contention sample {index} has inconsistent writer accounting")
    if item.get("eventsPerWriter") != max(64, report["enabledIterations"] // 4) * 2:
        raise SystemExit("runtime trace contention changed the enforced event count")
    if item.get("retainedEventCount") != item.get("capacity"):
        raise SystemExit(f"runtime trace contention sample {index} did not saturate the buffer")
    if item.get("droppedEventCount") != item.get("emittedEventCount") + item.get("prefillEventCount", 0) - item.get("capacity"):
        raise SystemExit(f"runtime trace contention sample {index} lost ring-buffer accounting")
    if item.get("capacity") != 4096 or item.get("prefillEventCount") != 4096:
        raise SystemExit("runtime trace contention requires a separately prefilled full ring")
    observations = item.get("observations")
    if not isinstance(observations, list) or len(observations) != 64:
        raise SystemExit("runtime trace contention requires 64 paced snapshot observations")
    previous_end = 0
    overlaps_by_quarter = [0, 0, 0, 0]
    writer_totals = [0, 0, 0, 0]
    for round_index, observation in enumerate(observations):
        if observation.get("round") != round_index or observation.get("retainedEventCount") != 4096:
            raise SystemExit("runtime trace snapshot did not observe the full ring in every round")
        observed_events = observation.get("observedEmittedEventCount")
        resolutions = item["eventsPerWriter"] // 2
        lower = (resolutions * round_index // 64) * 8
        upper = (resolutions * (round_index + 1) // 64) * 8
        if type(observed_events) is not int or not lower <= observed_events <= upper:
            raise SystemExit("runtime trace snapshot did not observe paced writer progress")
        start, end = observation.get("start"), observation.get("end")
        writers = observation.get("writers", [])
        if len(writers) != 4 or [w.get("writer") for w in writers] != [0, 1, 2, 3]:
            raise SystemExit("runtime trace observation omitted a writer")
        intervals = [(start, end)] + [(w.get("start"), w.get("end")) for w in writers]
        if any(not isinstance(t, int) or isinstance(t, bool) or t <= 0
               for interval in intervals for t in interval):
            raise SystemExit("runtime trace observation timestamps must be positive integers")
        if any(a >= b or a < previous_end for a, b in intervals):
            raise SystemExit("runtime trace rounds must be paced, ordered, nonempty intervals")
        if any(start < w["end"] and w["start"] < end for w in writers):
            overlaps_by_quarter[round_index // 16] += 1
        for writer in writers:
            writer_totals[writer["writer"]] += writer["end"] - writer["start"]
        previous_end = max(b for _, b in intervals)
    # Require measured overlap throughout the run, not an empty-buffer burst
    # or a reader tail. Scheduling may prevent some rounds from overlapping.
    if any(count < 8 for count in overlaps_by_quarter):
        raise SystemExit("runtime trace needs at least eight overlapping snapshots in every quarter")
    expected_cost = max(writer_totals) / item["eventsPerWriter"]
    if not math.isclose(item.get("nanosecondsPerEvent", -1), expected_cost, rel_tol=1e-9):
        raise SystemExit("runtime trace writer timing disagrees with measured intervals")
    value = item.get("nanosecondsPerEvent")
    wall = item.get("wallNanosecondsPerEvent")
    for name, measurement in (("writer", value), ("wall", wall)):
        if not isinstance(measurement, (int, float)) or isinstance(measurement, bool) or not math.isfinite(measurement) or measurement < 0:
            raise SystemExit(f"runtime trace contention sample {index} {name} measurement is invalid")
contended = min(item["nanosecondsPerEvent"] for item in contention)
contended_wall = min(item["wallNanosecondsPerEvent"] for item in contention)
if contended > contended_budget:
    raise SystemExit("contended runtime trace overhead exceeds its budget")
print(
    "Runtime trace performance: "
    f"disabled={disabled:.2f} ns/resolution (budget {disabled_budget:.2f}), "
    f"enabled={enabled:.2f} ns/event (budget {enabled_budget:.2f}), "
    f"saturated-max={max(item['nanosecondsPerEvent'] for item in saturated):.2f} ns/event "
    f"(budget {saturated_budget:.2f}), "
    f"snapshot-max={max(item['snapshotNanosecondsPerRetainedEvent'] for item in saturated):.2f} ns/event "
    f"(budget {snapshot_budget:.2f}), "
    f"contended-min={contended:.2f} ns/event across {len(contention)} samples "
    f"(budget {contended_budget:.2f}), wall-min={contended_wall:.2f} ns/event"
)
if disabled > disabled_budget:
    raise SystemExit("disabled runtime trace overhead exceeds its budget")
if enabled > enabled_budget:
    raise SystemExit("enabled runtime trace overhead exceeds its budget")
