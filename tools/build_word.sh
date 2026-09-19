#!/usr/bin/env bash
# Builds the Word (.docx) version of every course document from its markdown
# source. Requires pandoc. Output goes to word/. Markdown stays the source of
# truth -- re-run this after editing any .md file.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p word build

build_one() {
  local src="$1" title="$2" out="word/${1%.md}.docx"
  python3 tools/md_for_word.py "$src" "build/$src" >/dev/null
  pandoc "build/$src" \
    --from gfm --to docx \
    --resource-path=".:artifacts" \
    --toc --toc-depth=2 \
    --reference-doc=build/reference-styled.docx \
    --metadata title="$title" \
    --metadata author="DataCouch — Advanced Terraform" \
    -o "$out"
  printf "  %-52s %8s bytes  %s images\n" \
    "$(basename "$out")" "$(wc -c < "$out" | tr -d ' ')" "$(unzip -l "$out" | grep -c 'word/media/' || true)"
}

build_one 00-shared-setup.md                          "Advanced Terraform — Shared Setup"
build_one lab-01-cli-mastery.md                       "Lab 01 — Core Concepts Review & CLI Mastery"
build_one lab-01b-hcl-migration.md                    "Lab 01B — HCL Syntax Migration: Pre-0.12 to Post-0.12"
build_one lab-02-module-decomposition.md              "Lab 02 — Designing a Multi-Module Architecture"
build_one lab-02b-remote-state-composition.md         "Lab 02B — Multi-Project & Hybrid Platform Integration"
build_one lab-03-dry-modules-versioning.md            "Lab 03 — DRY Modules, Versioning & Null Label"
build_one lab-03b-multi-region-providers.md           "Lab 03B — Multi-Region / Multi-Provider Scenarios"
build_one lab-04-makefile-automation.md               "Lab 04 — Automating Workflows with Make + Makefile"
build_one lab-05-state-migration-import.md            "Lab 05 — Advanced State Management, Migration & Import"
build_one lab-06-advanced-hcl.md                      "Lab 06 — Advanced HCL: Meta-Arguments & For Expressions"
build_one lab-07-hardening-security.md                "Lab 07 — Hardening Terraform Security"
build_one lab-07b-red-team.md                         "Lab 07B — Red-Team Exercise: Terraform Security Gaps"
build_one lab-08-testing-drift.md                     "Lab 08 — Testing & Automated Drift Mitigation"
build_one lab-09-cicd-gitops.md                       "Lab 09 — Terraform in CI/CD Pipelines (GitOps)"
build_one lab-09b-terraform-cloud-policy.md           "Lab 09B — Terraform Cloud & Policy-as-Code"
build_one lab-09c-spinnaker.md                        "Lab 09C — Terraform via a Spinnaker Pipeline Stage"
build_one lab-10-capstone-aws-case-study.md           "Lab 10 (Capstone) — Complex AWS Infrastructure Case Study"
