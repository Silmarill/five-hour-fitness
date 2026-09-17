---
name: five-hour-fitness
description: Project fitness ledger. Track substantive Codex sessions against the five-hour window, convert usage into exercise, and add a compact Fitness line to the final response when the skill is enabled in the project.
---

# Five-hour fitness

Apply this skill only when it is enabled for the current project, normally by a short block in that project's `AGENTS.md` (the package includes a ready-to-merge block). Starting from the current folder, search upward for `SPEC/project.json` or the nearest `AGENTS.md` containing `five-hour-fitness`; use that directory as the project root. If `SPEC/project.json` exists, read its optional `logsDir`; otherwise use `Логи` below the discovered root. A caller may always provide explicit ledger paths. Do not infer or require any particular domain, course, repository type or subject area. Treat short clarifications about an assignment as part of the current session.

## Session gate

Use `five-hour-fitness.json` in the project's log directory as the machine-readable ledger, `five-hour-fitness-log.md` as the data table, and `five-hour-fitness-notes.md` for optional notes. The directory is `logsDir` from `SPEC/project.json` when available, or `Логи` by default.

Before work:

1. Read the ledger with scripts/fitness_ledger.ps1 -Action status.
2. If pendingConfirmation is true, require an explicit statement that exercise has started, such as «приступил», «начал выполнять» or an equally clear formulation.
3. For a substantive work session, confirmation is required before work begins. If it is absent, do not start the session or call task tools.
4. A short clarification, status check, ledger correction or other quick maintenance action may run provisionally without the word «приступил». Start and finish such a session with the script's `-Provisional` switch. Measure it anyway. If the resulting usage delta is zero, record the session with zero exercises and preserve any earlier pending assignment. If the delta is positive, record the assignment and require confirmation before the next substantive session.
5. If confirmation is present, run the confirm action and continue.

Confirmation concerns the start of exercise, not completion. If the user reports pain, injury, a medical limitation or unsuitable equipment, offer a safe substitute instead of insisting on the original movement.

## Usage measurement

At the beginning, read the current Codex limits and record the five-hour usedPercent. Start the ledger session and record model and reasoning level when known. Do not infer the model from a fallback-model field. Remind the user to state the new model and reasoning level whenever either setting changes; otherwise preserve the last explicitly confirmed setting only when the current task context supports it, and use unknown when it does not.

At the end, read the same value and run the finish action. Whole percentage points are an approximate comparable unit, not a token count. Decimal values are allowed if a future interface exposes them. If usage has not changed, record zero and do not invent an assignment.

If the window resets and ending usage is lower than starting usage, use the ending value as a conservative lower bound. If the interface confirms that the old window reached its limit, add the known remainder, 100 minus startPercent, through ConsumedBeforeResetPercent.

## Elapsed time

Capture the start timestamp in the first tool call after the request. Before closing, prepare the final response except for usage figures, read ending usage, run finish as the final tool action, and send the response immediately. Do not perform task work or other tool calls after finish unless the ledger operation failed.

The ledger records only the interval it can measure from start to finish. Never add a guessed, average, calibrated or fixed tail for response rendering, transmission or interface display.

The Codex interface value shown as «Выполнено за…» is authoritative. When the user supplies it, run correct-duration for the most recent completed session. Preserve Started, Finished, usage, exercises and calories. Store the reported value separately as uiDurationMinutes and uiDurationSeconds. Do not replace the automatic duration. When no UI value is supplied, leave UI time empty and remind the user that it can be added later.

## Log format and encoding

The Markdown log is a compact data table. Keep all headings, labels and generated values in English. Do not place narrative comments, explanations, arrows, percent signs or approximation symbols in the table.

Use these columns in this order: ID, Date, Started, Finished, Auto time, UI time, Model, Reasoning, Start, End, Used, Sol eq., Push-ups, Squats, Abs, Arms, kcal.

- Give every logged row a stable ID such as S001.
- Store Started and Finished in separate cells using HH:mm:ss.
- Auto time is the internally measured interval from start to finish, formatted as HH:mm:ss.
- UI time is the duration reported from the Codex interface, formatted as HH:mm:ss, and may remain empty.
- Store usage as plain numbers without percent signs or arrows.
- Round calories to the nearest whole number and store them without an approximation symbol.
- Keep optional notes in `five-hour-fitness-notes.md` under the matching row ID. Never append narrative text to the data table.
- For every new session, add a compact calibration marker to `five-hour-fitness-notes.md` under the matching row ID. Include `Benchmark`, `Benchmark version`, `Benchmark snapshot`, `Factor method`, `Reference configuration`, `Applied factor`, `Model`, and `Reasoning`. This makes the coefficient auditable without changing the compact log table.
- Write ledger, log and notes as UTF-8 without BOM using Text.UTF8Encoding with BOM disabled. Do not rely on PowerShell -Encoding utf8 because its BOM behavior differs between editions.
- After changing the writer, rebuild the log from the JSON ledger and verify that the result contains no replacement characters or mojibake.

## Conversion

The exercise scale uses a benchmark-derived model factor rather than a hard-coded API price ratio. The current calibration is based on DeepSWE v1.1, snapshot 2026-09-03, which reports PASS@1 and average cost for 113 long-horizon engineering tasks. The benchmark source is the [leaderboard](https://deepswe.datacurve.ai/) and its [machine-readable artifact](https://deepswe.datacurve.ai/artifacts/v1.1/leaderboard-live.json).

The selected method is **best-configuration cost per successful result**:

```text
cost_per_success(model) = average_cost(model, best_effort) / PASS@1(model, best_effort)
model_factor(model) = cost_per_success(Sol, max) / cost_per_success(model, best_effort)
```

The current displayed values are approximately Sol max: $6.46 / 0.73 and Luna max: $0.61 / 0.67, giving a Luna factor of **9.7**. This is a relative benchmark coefficient, not an account-billing or Codex-quota conversion. OpenAI's subscription credit accounting and API prices may change independently of the benchmark.

For exercise conversion, keep the model factor stable across effort levels. The selected effort is still recorded and affects the actual UI usage percentage; applying a second effort multiplier would count the same difference twice. The complete reference matrix is retained below so that a future recalibration can be audited.

| Model | Effort | DeepSWE PASS@1 | Artifact mean cost, USD | Raw cost ratio vs Sol medium | Applied exercise factor |
|---|---|---:|---:|---:|---:|
| GPT-5.6 Sol | low | 45.4 | 1.074 | 0.58 | 1.00 |
| GPT-5.6 Sol | medium | 61.1 | 1.862 | 1.00 | 1.00 |
| GPT-5.6 Sol | high | 69.4 | 3.470 | 1.86 | 1.00 |
| GPT-5.6 Sol | xhigh | 70.7 | 4.704 | 2.53 | 1.00 |
| GPT-5.6 Sol | max | 72.7 | 8.386 | 4.50 | 1.00 |
| GPT-5.6 Luna | low | 1.5 | 0.072 | 0.04 | 9.70 |
| GPT-5.6 Luna | medium | 11.3 | 0.216 | 0.12 | 9.70 |
| GPT-5.6 Luna | high | 44.2 | 0.778 | 0.42 | 9.70 |
| GPT-5.6 Luna | xhigh | 56.9 | 1.536 | 0.82 | 9.70 |
| GPT-5.6 Luna | max | 67.2 | 3.028 | 1.63 | 9.70 |

The artifact cost column uses the benchmark's recorded cost basis and is retained for traceability. It is not mixed with current subscription percentages. The rendered leaderboard currently shows a separately repriced cost view; when updating the coefficient, use one cost basis consistently.

Baseline and formula for a session:

```text
exerciseEquivalentPercent = rawDeltaPercent × applied exercise factor
```

The baseline is GPT-5.6 Sol at 1.0. GPT-5.6 Luna is 9.7 for all currently supported effort labels. Preserve both `rawDeltaPercent` and `exerciseEquivalentPercent`, together with the model, reasoning, benchmark version, snapshot date, factor method and applied factor.

The new calibration applies only to sessions completed after this rule is adopted. Historical sessions retain their stored factors and exercise assignments, even when the global default is updated.

One complete Sol-equivalent five-hour allowance equals 100 push-up-equivalent strength points, divided equally:

- 25 push-ups;
- 50 squats;
- 50 abdominal repetitions;
- 25 dumbbell curls with each arm.

Calculate cumulative targets and assign only the difference from earlier sessions. Cumulative rounding prevents small sessions from inflating or losing repetitions.

Estimated calories are only a comparison between sessions. Round the session result to the nearest whole number:

- push-up: 0.5 kcal;
- squat: 0.4 kcal;
- abdominal repetition: 0.3 kcal;
- dumbbell curl with each arm: 0.3 kcal for the pair.

Do not present this as a physiological measurement.

## End-of-session response

After work:

1. Report raw five-hour usage and Sol-equivalent usage when the factor differs from 1.0.
2. List only movements with new repetitions.
3. Report the calorie estimate, internal measured time, model and reasoning when available.
4. Use the short Russian label «руки» for dumbbell curls.
5. Remind the user that the «Выполнено за…» value may be supplied later for UI time.
6. Remind the user to include the model and reasoning level with the next «Приступил» message if either setting changes.
7. State that the next work session begins after explicit confirmation that exercise has started.
8. Leave pendingConfirmation set when at least one repetition was assigned.
9. Always include a compact fitness line in the final response, including when usage is zero: `Fitness: 0% usage, no exercises assigned`.
10. For a provisional maintenance action with zero usage, state that no confirmation was needed and no exercises were assigned. For a provisional action with positive usage, state that confirmation is required before the next substantive session.

Keep wording concise. Do not translate usage into tokens.


## TODO

Add empirically calibrated local UI multipliers only when the user explicitly requests recalibration. Until then, use the benchmark-derived model factors above and do not invent a reasoning multiplier.

## Updating benchmark coefficients (only on explicit user request)

Do not change coefficients merely because a benchmark page has changed. When the user explicitly asks to update them:

1. Confirm the requested benchmark version, model identifiers, effort labels and snapshot date.
2. Read the official DeepSWE leaderboard and machine-readable artifact. Record the exact URLs, retrieval date and cost basis.
3. Select the best effort configuration for each model and calculate `average_cost / PASS@1`.
4. Divide Sol's cost per successful result by the other model's value. Round the applied factor to two decimal places for the skill table, while retaining the unrounded calculation in the note.
5. Update the coefficient table, the script defaults and the ledger's current `modelConversionFactors` map. Do not rewrite `modelFactor`, `exerciseEquivalentPercent` or exercises in completed sessions.
6. Add a calibration note describing the old factor, new factor, source, formula and effective date.
7. If a requested model or effort is absent from the benchmark, leave its factor as `unknown`/`1.0` fallback and state that no benchmark-supported coefficient is available; never infer one from a different model.
## Model-factor references

Recheck official model pages before changing the factor:

- https://developers.openai.com/api/docs/models/gpt-5.6-sol
- https://developers.openai.com/api/docs/models/gpt-5.6-luna
