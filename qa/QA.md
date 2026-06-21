# DragonUI_NewEra — QA (Sprint 0)

How we catch problems each sprint without being able to run the game: a **static gate**
(`staticcheck.sh`, runs offline) and an **in-game harness** (`Harness.lua`, slash `/dnetest`).
Both live under `qa/` and only ever read/append the public contracts (`NE.qa.modules`,
`NE.qa.errors`), never base DragonUI.

---

## 1. Static check (offline, run by any agent / CI)

```sh
bash qa/staticcheck.sh        # runnable from anywhere; it cds to the addon dir itself
```

What it does (CONTRACTS.md §5):

1. **`luac -p` (Lua 5.1)** on every `.lua` under the addon. If `luac`/`luac5.1` is absent it prints
   `luac not found — skipping syntax pass` and continues (non-fatal). On this box `luac 5.1.5` is
   present, so the syntax pass runs.
2. **TOC manifest** — every file referenced in `DragonUI_NewEra.toc` (backslash paths normalised)
   must exist on disk. A missing file is **fatal** (FAIL + non-zero exit).
3. **3.3.5a runtime-trap grep** — reports `file:line` for each hit of: `SetShown(`, `:SetMask(`,
   `ScrollBox`, and `CreateFrame(...)` using `FauxScrollFrameTemplate` with a `nil`/empty name
   (must be NAMED on 3.3.5a). These are **advisory warnings** — they do not fail the build by
   themselves (so an in-progress file isn't blocked), but they must be cleared before a sprint ships.
4. **`C_*` coverage** — lists every `C_Namespace.` used and cross-checks each against
   `compat/COVERAGE.md`. Any `C_*` symbol not listed there is flagged as a warning. If
   `COVERAGE.md` doesn't exist yet, it prints the in-use namespaces so the API Bridge agent can
   author it.

**Exit code:** non-zero (with a `#### STATIC CHECK: FAIL ####` banner) only if a TOC-listed file is
missing or `luac` fails on any file. Otherwise `#### STATIC CHECK: PASS ####` (clean, or "with N
advisory warning(s)").

### Sprint-0 PASS looks like

- Every TOC-listed file present → all `ok:` under section 2.
- Every `.lua` compiles → all `ok:` under section 1.
- Trap grep: ideally no hits. (If a panel legitimately needs a Faux scroll frame, it must be NAMED,
  so the unnamed-Faux check stays clean.)
- `C_*` check: once `compat/COVERAGE.md` lands, every `C_*` namespace NewEra uses is listed there.
- Final line: `#### STATIC CHECK: PASS ####`, exit `0`.

While other agents' files are still landing it is normal to see `FAIL: TOC lists missing file: …`
for not-yet-written files and a `COVERAGE.md not present` warning. That's expected mid-sprint; the
gate is "green" for Sprint-0 DoD once all §1–§5 owners have committed their files.

---

## 2. In-game harness (`/dnetest`)

Loaded via the TOC (`qa\Harness.lua`). It installs a **session error capture** at load time by
wrapping the current `geterrorhandler()` (cooperates with BugSack/Blizzard — it chains to the prior
handler) and records the last 50 errors into `NE.qa.errors`.

Run in-game:

```
/dnetest
```

For each entry in `NE.qa.modules` (panels append `{ name, frame, open, close }`) it prints:

- whether `module.frame` is non-nil (`frame:ok` / `frame:nil` — nil is a soft warning, not a fail),
- `module.open()` run under `pcall` → `open:ok` or `open:ERR(<msg>)`,
- `module.close()` run under `pcall` → `close:ok` or `close:ERR(<msg>)`,

then a `[PASS]`/`[FAIL]` per module (FAIL only when an open/close errored), a tally header
(`N pass / M fail`), and finally the **count of captured session Lua errors** with the last few
messages.

It is fully defensive: an empty `NE.qa.modules` prints `no modules registered yet` and **PASSES**.
Output uses `DEFAULT_CHAT_FRAME:AddMessage` with color codes; no `SetShown`.

### Sprint-0 expected output

After Core's `_HelloDemo.lua` has appended itself to `NE.qa.modules`, `/dnetest` should report:

```
===== DragonUI_NewEra /dnetest =====
[PASS] HelloDemo  frame:ok open:ok close:ok
PASS  1 pass / 0 fail  (1 modules)
session Lua errors captured: 0
====================================
```

---

## 3. Manual visual-QA checklist (architect / user — agents can't run the client)

Static + harness can't see pixels. After a clean `staticcheck.sh` PASS and a clean `/dnetest`,
do this by eye in the 3.3.5a client:

1. **Load clean.** `/console reloadui`. No red Lua error on login. `/dnetest` → `session Lua errors
   captured: 0`.
2. **Hello chrome renders.** Run `/dnehello`. Confirm a DF **portrait-frame** appears: nineslice
   metal border with crisp corners, a circular portrait inset top-left, a title, and a reskinned
   close button.
3. **Atlas coords correct, no stretching.** The frame-metal corners/edges are sharp and seamless
   (the registered atlas from `Textures/Assets.lua` maps to the right UVs) — no blurred, doubled,
   or stretched border art; the background rock fills without tiling seams.
4. **Harness agrees.** `/dnetest` → `HelloDemo  frame:ok open:ok close:ok` and a `PASS` banner.
5. **Open/close behaves.** The demo frame Shows on `/dnehello` and Hides via its close button /
   `module.close`; no flicker, no taint warning in chat.
6. **Options tab.** With `DragonUI_Options` open, a **"New Era"** tab is present with the Hello-demo
   toggle; flipping it enables/disables the demo cleanly.
7. **No global leak.** `/run print(_G.NE)` prints `nil` (the namespace is local everywhere; only
   `_G.DragonUI_NewEra` exists).

If any of 2–7 fail, capture the chat error text and the failing module name from `/dnetest`.
