# Lab Creation Methodology

This is the standing prompt/approach used to design, build, and test every lab in this repository. Reuse it verbatim (or adapt the scope section) any time a new lab or a new day of labs needs to be added.

---

## The prompt

> You are building a hands-on lab for the Advanced Kubernetes training course, in the same repository and style as the existing labs. Follow this process exactly:
>
> **1. Design first, list it before writing.** When asked to add a new lab or set of labs, first propose a short numbered list of lab titles/topics and confirm the choice with the user (via a direct question, not by guessing) before writing any content — especially for anything structural like where a new lab slots into the existing numbering, or which specific sub-topic within a broad area (e.g. "GKE cluster architecture" vs. "GKE networking") to build.
>
> **2. Match the existing structure exactly.** Every lab file follows this shape, in this order:
> - `# Lab N — Title`, then a `**Day X · Section name**` line.
> - A one-line blockquote status note: once tested, state plainly that every command was actually run and every screenshot is real, and call out the single most interesting real finding if there is one. Before testing, say so explicitly ("newly designed, not yet live-tested") — never let a lab imply it's been tested when it hasn't.
> - `## What you'll learn` — 3-5 bullets, concrete, naming the actual tools/resources/commands involved, not generic learning-outcome language.
> - `## Time & cost` — a real time estimate and an honest cost line (`$0` for local-only labs; a real dollar-shape estimate for cloud labs, revised after testing to reflect what actually happened).
> - `## Prerequisites` — link to the setup guide, list exactly which tools this specific lab needs, and name any dependency on another lab explicitly.
> - `## N.1 Concepts, briefly` — a short prose explanation of the core mechanism (not a wall of theory), followed by **one Mermaid diagram** (`flowchart`) showing the actual architecture/flow this lab exercises.
> - Numbered sections (`## N.2`, `## N.3`, ...) that walk through real commands, each a fenced code block, each followed by either a screenshot + **Verified result** (once tested) or an **Expected result** (before testing).
> - A `## N.x Clean up` section that actually tears down whatever was created.
> - `## Lab summary` — a table of claim → where it's proven.
> - `## Evidence` — a link to the lab's screenshot folder with an exact image count, once tested.
> - A `**Next:** [Lab N+1 — ...]` link.
>
> **3. Add exactly one Mermaid diagram per lab**, in the Concepts section, showing the specific architecture this lab's hands-on work exercises (not a generic Kubernetes diagram). Validate the syntax carefully before treating it as done: every `subgraph` has a matching `end`, no literal `|` characters inside edge labels (`-->|"..."|` or `["..."]`), and `<`/`>` characters in comparisons are escaped as `&lt;`/`&gt;`.
>
> **4. Design the commands to be genuinely runnable**, not illustrative pseudocode — real image names, real flag syntax, real resource shapes. Cross-check anything you're not certain is current (an image tag, a CRD API version, an install manifest URL) against the actual upstream source before writing it into the lab.
>
> **5. Then — and only when the user asks to proceed to testing, which for this course has always been requested explicitly — actually run every single command against real infrastructure.** This is the part that cannot be skipped or simulated:
> - Local labs: a real `kind` cluster, created and torn down for real.
> - Cloud labs: a real GKE/EKS/AKS cluster under a real project/account, created and torn down for real, with teardown verified by a follow-up `list` command showing empty.
> - Capture screenshots via real automation, not a mockup: open a real Terminal.app window (`osascript ... do script`), send real commands into it (write the command to a temp script file and `send("bash /tmp/cmd.sh")` rather than trying to inline complex quoting through AppleScript), wait for it to actually finish, then `screencapture -x -l<window-id>` that same window. Prefix each capture's command with `clear &&` so the screenshot shows only that step's output, not stale scrollback.
> - **After every capture, actually open the image and read what it shows** before writing a caption or a "Verified result" line for it. Never assume a command "must have" produced the expected output — confirm the pixels.
> - When a command fails, investigate the real root cause (read the actual error, check quotas/logs/events, search upstream issue trackers if it looks like a known bug) before either fixing it and retrying, or accepting it as a genuine dead end. Never blindly retry an identical command that failed for a structural reason, and never paper over a failure by rewriting the doc to describe what *should* have happened instead of what did.
>
> **6. Rewrite the lab doc with what actually happened**, not what was originally planned, wherever the two differ:
> - Replace `Expected result` with `Verified result` and the real captured output, once confirmed.
> - Add a `> **Tested gotcha:** ...` callout for every real bug hit along the way — the exact error text, the root cause, and the fix — even if (especially if) it means changing the lab's own commands from the original design (e.g. swapping a broken image reference for a working one, adding a flag that turned out to be required).
> - If something genuinely cannot be made to work — an upstream bug, a hard account-level quota, an unsupported combination — say so plainly, with the evidence (exact error, what was checked, what was ruled out, a link to an upstream issue if one exists), and point to wherever the equivalent concept *is* proven elsewhere in the course, rather than forcing a fake success or silently dropping the section. This is a first-class, accepted outcome in this course, not a failure of the lab — precedent: Lab 2's KubeFed section, Lab 12's Kubeflow Pipelines backend section, Lab 13's GPU quota wall.
> - Never fabricate or simulate terminal output, even by combining a real "before" state with a live "after" command in one script — every screenshot must come from a single, fully live command sequence.
>
> **7. Propagate real findings outward.** Once a lab is tested:
> - Update `00-setup-environment-guide.md`'s "Known rough edges" section with any gotcha that a newcomer would plausibly hit during initial setup (not lab-specific mechanics).
> - Update `README.md`'s per-lab bullet in "What makes these labs different" with the lab's single most interesting real finding.
> - Remove any "not yet tested" caveat language for that lab/day from both files once every lab in that day is done.
> - Cross-link related findings between labs where they genuinely relate (e.g., a quota wall hit in two different labs should reference each other).
>
> **8. Tear down and verify before considering the work done.** Every piece of real cloud infrastructure created during testing must be deleted, and that deletion verified with a real `list` command showing nothing left — across every cloud provider touched, not just the one the current lab used, since multi-cluster sessions can leave cross-provider resources behind.

---

## Why this exists

The whole value proposition of this course is that every claim is backed by a real, reproducible command run against real infrastructure — "we tried this and here's exactly what happened," not "this should work." That standard is more expensive to build (every lab takes real cloud time, real debugging, real screenshots) but it's the entire point: readers get the actual rough edges (stale image tags, silent flag requirements, quota walls, upstream bugs) that no amount of reading documentation would surface, plus the confidence that anything marked "Verified result" really is one.
