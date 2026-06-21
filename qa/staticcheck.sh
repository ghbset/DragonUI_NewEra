#!/usr/bin/env bash
# DragonUI_NewEra/qa/staticcheck.sh  (owner: QA/Harness Engineer)  — CONTRACTS.md §5
#
# Static gate run every sprint (agents cannot run the game). It:
#   1. luac -p (Lua 5.1) every .lua under the addon, if luac exists.
#   2. Verifies every file listed in DragonUI_NewEra.toc exists on disk.
#   3. Greps the .lua for known 3.3.5a runtime traps and reports file:line:
#        - SetShown(
#        - :SetMask(
#        - ScrollBox
#        - CreateFrame(... "FauxScrollFrameTemplate" ...) WITHOUT a name argument
#        - C_<Namespace>. usages cross-checked against compat/COVERAGE.md
#   4. Exits non-zero with a FAIL banner if a TOC file is missing or luac fails;
#      otherwise prints PASS. Trap hits are advisory (warnings), not fatal,
#      EXCEPT they do not flip the exit code by themselves.
#
# Runnable from anywhere: it cds to the addon dir based on this script's location.

set -u

# --- locate the addon root (parent of this script's qa/ dir) -----------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ADDON_DIR}" || { echo "FATAL: cannot cd to addon dir ${ADDON_DIR}"; exit 2; }

TOC="DragonUI_NewEra.toc"
COVERAGE="compat/COVERAGE.md"

# --- colors (disabled if not a tty) ------------------------------------------
if [ -t 1 ]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
    RED=''; GRN=''; YEL=''; CYN=''; BLD=''; RST=''
fi

FAIL=0          # flips to 1 on any fatal condition (missing TOC file / luac error)
WARN_COUNT=0

section() { printf '%s\n' "${CYN}${BLD}== $* ==${RST}"; }
warn()    { printf '%s\n' "${YEL}WARN:${RST} $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
err()     { printf '%s\n' "${RED}FAIL:${RST} $*"; FAIL=1; }
ok()      { printf '%s\n' "${GRN}ok:${RST} $*"; }

printf '%s\n' "${BLD}DragonUI_NewEra static check${RST}  (addon: ${ADDON_DIR})"
echo

# Collect all .lua files in the addon (portable; no mapfile dependency).
LUA_FILES=()
while IFS= read -r f; do
    LUA_FILES+=("$f")
done < <(find . -type f -name '*.lua' | sed 's|^\./||' | sort)

# =============================================================================
# 1. luac -p syntax pass
# =============================================================================
section "1. Lua 5.1 syntax (luac -p)"
LUAC=""
for cand in luac5.1 luac; do
    if command -v "$cand" >/dev/null 2>&1; then LUAC="$cand"; break; fi
done

if [ -z "$LUAC" ]; then
    printf '%s\n' "${YEL}luac not found — skipping syntax pass.${RST}"
else
    LUAC_VER="$("$LUAC" -v 2>&1 | head -1)"
    printf 'using %s (%s)\n' "$LUAC" "$LUAC_VER"
    if [ "${#LUA_FILES[@]}" -eq 0 ]; then
        warn "no .lua files found to compile"
    else
        for f in "${LUA_FILES[@]}"; do
            if "$LUAC" -p "$f" >/tmp/dne_luac.$$ 2>&1; then
                ok "$f"
            else
                err "$f"
                sed 's/^/      /' /tmp/dne_luac.$$
            fi
        done
        rm -f /tmp/dne_luac.$$
    fi
fi
echo

# =============================================================================
# 2. TOC file existence
# =============================================================================
section "2. TOC file manifest"
if [ ! -f "$TOC" ]; then
    err "TOC not found: $TOC"
else
    # TOC lists files with backslash separators; ignore blank/comment/metadata lines.
    while IFS= read -r raw; do
        line="${raw%%$'\r'}"                       # strip CR
        line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;                       # comment
            \#\#*) continue ;;                     # metadata (also starts with #)
        esac
        # Only treat lines that look like file references (have an extension).
        case "$line" in
            *.lua|*.xml|*.toc) ;;
            *) continue ;;
        esac
        rel="${line//\\//}"                        # backslash -> forward slash
        if [ -f "$rel" ]; then
            ok "$rel"
        else
            err "TOC lists missing file: $rel"
        fi
    done < "$TOC"
fi
echo

# =============================================================================
# 3. Known 3.3.5a runtime traps
# =============================================================================
section "3. 3.3.5a runtime trap grep"

trap_grep() {
    # $1 = human label, $2 = grep -E pattern
    local label="$1" pat="$2" hits
    if [ "${#LUA_FILES[@]}" -eq 0 ]; then return; fi
    hits="$(grep -RnE "$pat" --include='*.lua' . 2>/dev/null | sed 's|^\./||')"
    if [ -n "$hits" ]; then
        printf '%s\n' "${YEL}${label}:${RST}"
        printf '%s\n' "$hits" | sed 's/^/    /'
        # count lines
        local c
        c="$(printf '%s\n' "$hits" | grep -c .)"
        WARN_COUNT=$((WARN_COUNT + c))
    else
        ok "no ${label} hits"
    fi
}

trap_grep "SetShown("        'SetShown[[:space:]]*\('
trap_grep ":SetMask("        ':SetMask[[:space:]]*\('
trap_grep "ScrollBox"        'ScrollBox'

# --- Unnamed FauxScrollFrameTemplate CreateFrame calls -----------------------
# A correct 3.3.5 call passes a name: CreateFrame("ScrollFrame", "MyName", parent, "FauxScrollFrameTemplate")
# The trap is a nil name: CreateFrame("ScrollFrame", nil, parent, "FauxScrollFrameTemplate")
# We flag any CreateFrame(...) line mentioning FauxScrollFrameTemplate whose 2nd arg is nil or empty.
section_faux() {
    local hits c
    hits="$(grep -RnE 'CreateFrame[[:space:]]*\(' --include='*.lua' . 2>/dev/null \
            | grep -E 'FauxScrollFrameTemplate' \
            | grep -E 'CreateFrame[[:space:]]*\([^,]*,[[:space:]]*(nil|""|'\'\'')[[:space:]]*,' \
            | sed 's|^\./||')"
    if [ -n "$hits" ]; then
        printf '%s\n' "${YEL}unnamed FauxScrollFrameTemplate CreateFrame (must be NAMED):${RST}"
        printf '%s\n' "$hits" | sed 's/^/    /'
        c="$(printf '%s\n' "$hits" | grep -c .)"
        WARN_COUNT=$((WARN_COUNT + c))
    else
        ok "no unnamed FauxScrollFrameTemplate CreateFrame"
    fi
}
section_faux
echo

# =============================================================================
# 3b. C_* usage vs compat/COVERAGE.md
# =============================================================================
section "3b. C_* symbols vs ${COVERAGE}"
if [ "${#LUA_FILES[@]}" -eq 0 ]; then
    warn "no .lua files to scan for C_* symbols"
else
    # Extract distinct C_Namespace tokens (the part before the dot), excluding the qa harness's
    # own commentary by scanning code lines only is hard in bash; we report all and de-dup.
    C_SYMBOLS="$(grep -RhoE 'C_[A-Za-z]+\.' --include='*.lua' . 2>/dev/null \
                 | sed 's/\.$//' | sort -u)"
    if [ -z "$C_SYMBOLS" ]; then
        ok "no C_* usages found"
    elif [ ! -f "$COVERAGE" ]; then
        warn "${COVERAGE} not present yet — cannot cross-check. C_* namespaces in use:"
        printf '%s\n' "$C_SYMBOLS" | sed 's/^/    /'
    else
        printf 'cross-checking against %s ...\n' "$COVERAGE"
        while IFS= read -r sym; do
            [ -z "$sym" ] && continue
            if grep -qF "$sym" "$COVERAGE"; then
                ok "$sym (covered)"
            else
                warn "C_ symbol NOT in COVERAGE.md: $sym"
            fi
        done <<< "$C_SYMBOLS"
    fi
fi
echo

# =============================================================================
# Final banner
# =============================================================================
echo "------------------------------------------------------------"
if [ "$FAIL" -ne 0 ]; then
    printf '%s\n' "${RED}${BLD}#### STATIC CHECK: FAIL ####${RST}  (missing TOC file or luac error above)"
    [ "$WARN_COUNT" -gt 0 ] && printf '%s\n' "${YEL}(${WARN_COUNT} advisory warning(s) also reported)${RST}"
    exit 1
else
    if [ "$WARN_COUNT" -gt 0 ]; then
        printf '%s\n' "${GRN}${BLD}#### STATIC CHECK: PASS ####${RST}  ${YEL}with ${WARN_COUNT} advisory warning(s)${RST}"
    else
        printf '%s\n' "${GRN}${BLD}#### STATIC CHECK: PASS ####${RST}  (clean)"
    fi
    exit 0
fi
