# Caddy Domain And Path Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support both separate-domain and same-domain path based Caddy entries for s-ui and Nezha while preserving the 80/8443 gateway and 443-for-Reality strategy.

**Architecture:** Keep `/etc/caddy/apps.d/*.caddy` as the import surface, but render VPS Tools managed entries as one Caddy site file per domain. Each app keeps its own state record, and the renderer groups state records by domain so `sui.example.com` and `nezha.example.com` remain independent while `example.com/app/` and `example.com/nezha/` share one site block.

**Tech Stack:** Bash, Caddyfile, systemd Caddy service, existing VPS Tools state files.

---

### Task 1: Add Modes And State

**Files:**
- Modify: `modules/install/caddy.sh`

- [x] Add Cloudflare mode selection: `orange-cloud-http01` and `gray-cloud-direct`.
- [x] Add entry mode selection: separate domain or same-domain path.
- [x] Persist `EntryMode`, `PublicPath`, and `CloudflareMode` in app state.

### Task 2: Render Managed Sites By Domain

**Files:**
- Modify: `modules/install/caddy.sh`

- [x] Add a renderer that reads app state records, deletes old VPS Tools managed site files, and writes one `_vps-tools-<domain>.caddy` file per domain.
- [x] Keep legacy per-app files from state-managed entries from conflicting by removing `$app_name.caddy` when regenerating.
- [x] Generate s-ui `/app/`, optional subscription prefix, Nezha `/nezha/`, and Nezha `/proto.NezhaService/*` routes.

### Task 3: Update UX And Docs

**Files:**
- Modify: `modules/install/caddy.sh`
- Modify: `docs/COMMAND-REFERENCE.md`

- [x] Print separate-domain and same-domain URLs.
- [x] Print Nezha Agent settings with `NZ_SERVER=<domain>:8443` and `NZ_TLS=true`.
- [x] Document orange-cloud and gray-cloud behavior.

### Task 4: Verify

**Files:**
- Verify: `modules/install/caddy.sh`

- [x] Run `bash -n modules/install/caddy.sh`.
- [x] Run the project-required `npm format`, `check`, and `ci`; record if unavailable.
