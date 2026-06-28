---
design_depth: deep
task_complexity: complex
---

# Design Document: Batch Pipeline Execution

## 1. Problem Statement
The user has an inbox (`data/pipeline.md`) with over 100 job URLs pending evaluation. Processing these synchronously blocks the terminal and is vulnerable to transient network or API timeouts, which would halt the entire batch. The goal is to implement a robust, unattended batch processing pipeline that can sequentially evaluate all pending URLs, generate evaluation reports and PDFs, and stage tracker updates (`batch/tracker-additions/`). The system must resiliently handle individual URL failures by skipping and logging them for later review, ensuring the overall batch completes. It must also provide a clear audit trail via file-based logging, freeing up the user's interactive session.

## 2. Requirements
**Functional Requirements:**
- **[REQ-1]** Parse `data/pipeline.md` to extract all pending URLs.
- **[REQ-2]** Invoke the `career-ops batch` command headlessly for each extracted URL.
- **[REQ-3]** Output individual evaluation results as TSV files in `batch/tracker-additions/` for later merging.
- **[REQ-4]** Handle URL processing failures by logging the error to a dedicated retry log and skipping to the next item.

**Non-Functional Requirements:**
- **[REQ-5]** Reliability: Execute asynchronously in the background, surviving terminal closures or session disconnects.
- **[REQ-6]** Observability: Output all progress and errors to file-based logs (`batch/logs/batch-run.log`) for `tail` monitoring.

**Constraints:**
- **[REQ-7]** Utilize the existing CLI automation tools rather than re-inventing the evaluation logic.
- **[REQ-8]** Run sequentially to implicitly manage rate limiting and avoid aggressive IP bans from ATS platforms.

## 3. Approach

**Selected Approach: Sequential Background Script**
We will orchestrate the batch processing using the existing `batch/batch-runner.sh` script running in a background process.

**Key Decisions:**
- Use `batch/batch-runner.sh` — *[Leverages existing tested infrastructure rather than building a new runner from scratch. Traces To: REQ-7]* *(considered: Custom Maestro Native Parallel — rejected because it blocks the session and limits reliability on massive runs; considered: Concurrent Queue — rejected because it increases the risk of ATS rate limits. Traces To: REQ-5, REQ-8)*
- Sequential Loop Execution — *[Ensures we do not overload ATS endpoints and keeps API resource usage flat. Traces To: REQ-8]*
- Skip-and-Log Error Strategy — *[Prevents a single bad URL or transient timeout from aborting the remaining queue. Traces To: REQ-4]*
- Redirection to `batch/logs/batch-run.log` — *[Frees the interactive terminal session while providing an audit trail. Traces To: REQ-6]*

**Decision Matrix:**
| Criterion | Wt | Sequential Script | Concurrent Queue | Native Parallel |
|---|---|---|---|---|
| Unattended Reliability | 40% | 5: Runs independently, highly resilient | 3: Prone to IP bans/rate limits | 2: Blocks session, brittle at 100+ scale |
| Throughput | 30% | 2: Slow (one by one) | 5: Very fast | 4: Fast but potentially rate-limited |
| Implementation | 30% | 5: Reuses existing `batch-runner.sh` | 3: Requires new concurrent logic | 4: Supported natively by Maestro |
| **Weighted Total** | | **4.1** | **3.6** | **3.2** |

## 4. Architecture
**Data Flow:**
1. **Initialization:** The background process parses `data/pipeline.md` and extracts all pending URLs via regex. — *[Traces To: REQ-1]*
2. **Execution Loop:** For each URL, the script invokes the CLI (`gemini -p "career-ops batch {URL}"`). — *[Traces To: REQ-2]*
3. **Artifact Generation:** Upon success, the CLI outputs a detailed markdown report in `reports/` and writes a TSV summary line to `batch/tracker-additions/`. — *[Traces To: REQ-3]*
4. **Error Handling:** If the CLI execution fails (e.g., timeout), the script catches the non-zero exit code, logs the URL to `batch/logs/failed.log`, and continues to the next URL. — *[Traces To: REQ-4]*

## 5. Agent Team
Since we are utilizing the built-in `career-ops` skill, the actual evaluation is handled by the `generalist` (or configured CLI equivalent) launched as a separate process by the background script. Maestro's role in this session is simply to trigger the background shell process and stage the environment.

## 6. Risk Assessment
- **Risk:** ATS platforms (Greenhouse, Lever) may impose rate limits or IP bans due to 100+ requests.
  - **Mitigation:** Enforce strictly sequential execution with an optional small `sleep` delay between iterations in the runner script. — *[Traces To: REQ-8]*
- **Risk:** Silent evaluation failures (e.g., context limit exceeded) where the script assumes success.
  - **Mitigation:** Ensure the script strictly checks the CLI exit code and verifies TSV generation before marking a URL as successful. — *[Traces To: REQ-4]*
- **Risk:** Duplicate applications/tracker entries.
  - **Mitigation:** Defer file modifications; use `batch/tracker-additions/` and rely on the idempotent `merge-tracker.mjs` script after the batch completes.

## 7. Success Criteria
- The background script successfully initiates and correctly extracts the queue from `data/pipeline.md`.
- TSV output files sequentially populate in `batch/tracker-additions/` as evaluations complete.
- Any failed evaluations are documented in a failure log, and the overall loop continues uninterrupted until the queue is exhausted.