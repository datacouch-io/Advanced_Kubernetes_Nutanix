
The standing prompt and working practice behind every lab in this repository. Reuse the prompt
verbatim; adapt only the scope paragraph at the top.

Updated 2026-09-28 to match the structure the labs actually use. The earlier version of this file
described an older `## N.1 / Verified result` shape that no lab follows any more.

---

## The prompt

> You are building a hands-on lab for the Advanced Kubernetes (Nutanix) course, in the same
> repository and voice as the existing labs. Follow this process exactly.
>
> ### 1. Agree the scope before writing
>
> Propose a short numbered list of candidate labs or steps and confirm the choice before writing
> content — especially anything structural: which module of the client outline it serves, which day
> folder it belongs in, whether it extends an existing lab or becomes a new one. Do not guess where
> something slots in.
>
> Check the outline coverage first. Every lab exists to close a specific bullet in the client
> outline's *Hands-on* line. If you cannot name that bullet, the lab does not have a reason to exist
> yet.
>
> ### 2. Match the existing document shape exactly
>
> ```
> # Lab N — Plain-language title (Technical subject in parentheses)
> **Day X · Section name**
>
> > YES — **Tested end-to-end** on <exact platform, versions>. <What the reader gets.>
>
> ## What you'll learn        3–6 bullets, naming real tools, resources and failure modes
> ## What you'll do           one paragraph, the narrative arc of the lab
> ## Time & cost              real minutes; $0 for kind, a real estimate for cloud
> ## Before you start         where you'll work · tools you need · cluster · prior labs
>                             plus a > **Nutanix note.** mapping the concept onto NKE
> ## The idea in 60 seconds   short prose + exactly ONE mermaid flowchart
> ## Step 1 — Imperative title
>     **Goal:** one sentence.
>     numbered actions, each a real fenced command block
>     **What you should see:** followed by a ```console block of real output
>     ![caption](../artifacts/lab-NN/screenshots/NN-name.png)
>     **What this means.** the teaching point, in plain language
>     > ⚠️ **Gotcha — <the trap>.** what happens, why, and what to do instead
> ## Step N — Clean up        actually tears down everything the lab created
> ## What you learned         table: | You saw… | in Step | proof |
> ## Evidence                 links to artifacts/lab-NN/screenshots/ and .../evidence/*.txt
> **Next:** [Lab N+1 — …](lab-N+1-….md)
> ```
>
> Titles are what the reader gets, not the technology: *"Give On-Prem Services a Real IP"*, not
> *"MetalLB Lab"*. Step titles are imperative: *"Break a manifest, and read the failure"*.
>
> ### 3. Write commands that actually run
>
> Real image tags, real flag syntax, real API versions. Verify anything you are not certain is
> current against upstream before it goes in the file. A lab that fails at step one because an image
> moved is worse than no lab.
>
> ### 4. Run every command against real infrastructure
>
> This is the part that cannot be skipped or simulated.
>
> - `kind` for anything that does not genuinely need a cloud. It is free, fast and disposable.
> - A real GKE/EKS/AKS cluster only where the cloud is the point (real disks, real snapshots, real
>   load balancers). Delete it afterwards and verify with a `list` showing empty.
> - Save a plain-text transcript of the real session to `artifacts/lab-NN/evidence/<name>.txt`, with
>   a header naming the cluster, the component versions and the capture date. This is the
>   authoritative record; screenshots illustrate it.
>
> ### 5. Capture screenshots safely, and look at every one
>
> Use `tools/screenshots/` — never an ad-hoc `screencapture`. The tool resolves the target window
> fresh on every shot, requires the owning application to be `Terminal` with a matching pid and
> geometry, requires exactly one match, re-verifies ownership after the capture, and checks the PNG
> dimensions against the window bounds. It deletes the file and fails on any mismatch.
>
> This matters because window ids are recycled by macOS. An earlier workflow cached one in a file;
> when it went stale it silently captured whatever window had inherited it, and put private content
> into three frames.
>
> - Drive the capture window through `run.sh`, which clears first so the command line is visible and
>   detects completion with a zsh `precmd` counter rather than polling.
> - Long or awkward commands go in a `/tmp/*.sh` and the screenshot shows `bash /tmp/x.sh`. Do not
>   fight AppleScript quoting.
> - **Open every image and read it before writing its caption.** Truncated output, a stray `zsh: no
>   matches found`, a Docker promo line, a command that silently did nothing — you will only catch
>   these by looking.
>
> ### 6. Rewrite the lab to match what actually happened
>
> Where reality and the plan differ, reality wins and the document changes:
>
> - Replace planned output with the captured output, including revisions, MAC addresses, timings and
>   counts. If a screenshot shows `769a9c39`, the prose does not say `cca67164`.
> - Add a `> ⚠️ **Gotcha — …**` for every real trap: the exact error, the cause, the fix.
> - If something cannot be made to work — an upstream bug, a withdrawn image, a hard quota — say so
>   plainly with the evidence, and point at where the concept is proven elsewhere. This is an
>   accepted outcome, not a failed lab.
> - Never fabricate output, and never stitch a real "before" to a live "after". One live sequence per
>   capture.
>
> ### 7. Be exact about provenance
>
> The banner says where the work was done. If a lab was tested on GKE and you later add captures from
> `kind`, the banner must say which steps came from which platform and when. "Every screenshot is a
> real capture" is only honest if it is not also implying a platform the images did not come from.
>
> ### 8. Finish the surrounding work
>
> - Rebuild the `.docx` with `tools/lab2docx.sh <path>.md`. Kroki throws transient 500s — if the
>   mermaid warning appears, just run it again.
> - Update the day `README.md` module table and `COURSE-MAP.md` if the lab's place changed.
> - Add any newcomer-facing trap to `00-setup-environment-guide.md` under "Known rough edges".
> - Check every relative link resolves, and that every file in `artifacts/lab-NN/screenshots/` is
>   referenced by the lab.
> - Tear down every cluster and verify nothing is left running, on every provider touched.

---

## The standard this protects

Every claim in this course is backed by a command that was actually run, against real
infrastructure, with the output captured. Not "this should work" — "we ran this, here is what
happened, including the parts that went wrong."

That is more expensive to produce. It is also the entire product: readers get the stale image tags,
the silently-required flags, the messages that changed between Kubernetes versions and the quota
walls that no amount of reading the documentation would surface — plus the confidence that anything
marked tested really was.

Concrete examples of the standard doing its job, all from real runs:

| What the lab originally said | What running it showed |
|---|---|
| Lab 12 installs MinIO | Every MinIO image is withdrawn; the lab now uses SeaweedFS |
| Lab 26 defrag reclaims 53% | Nothing is reclaimable until `compact` runs first |
| Lab 6 HPA reports `ScalingActive True` | On kind it reports `False`; the loop is identical anyway |
| Lab 14 needs the Loki push API on kind | Promtail works fine; the earlier note was a config error |
| Lab 13 LB-IPAM gives a working address | It allocates but does not announce — `curl` returns `000` |
