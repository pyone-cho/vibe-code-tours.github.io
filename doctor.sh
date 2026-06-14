#!/usr/bin/env bash
# Vibe Code Tours — chapter doctor / self-check.
#
# Single chapter-aware script. Replaces old ch-0 doctor.sh and check-ch1.sh.
#
# Usage:
#   bash doctor.sh                  # default ch-0 (pre-class setup)
#   bash doctor.sh ch-0             # explicit ch-0
#   bash doctor.sh ch-1             # ch-1 homework (profile repo + PR)
#
# Stages (all chapters):
#   1. detect platform (mac | wsl | linux)
#   2. detect claude install (linux | windows | both | none) — ch-0 prompts on conflict
#   3. version checks (node, npm, python, git, gh, claude)
#   4. gh auth + user + read probe
#   5. proxy probe (claude -p OR curl VIBE_PROXY)
#
# Chapter-specific:
#   ch-0: SVG badge card → drop PNG in #ch-0-intro → instructor ✅ → ch-0-done
#   ch-1: +profile repo +PR check → posts gist → submit via /ch1 <gist-url>
#
# Flags:
#   --non-interactive  default REPLACE on windows-claude conflict (ch-0)
#   --keep|--replace   force conflict resolution (ch-0)
#   --no-claude        skip claude-rendered card (ch-0)
#   --no-post          save report.md only, no gist post (ch-1)
#   --out DIR          output dir (default ~/.vibecode/doctor)
#
# Exit codes:
#   0  all green     1  hard fail     2  soft fail (proxy down)

set -u

# ---------- args ----------
CHAPTER="ch-0"
if [ $# -gt 0 ] && [[ "$1" =~ ^ch-[0-9]+$ ]]; then CHAPTER="$1"; shift; fi
NONINT=0; KEEP=0; REPLACE=0; OUTDIR="${HOME}/.vibecode/doctor"; NO_CLAUDE=0; NO_POST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) NONINT=1 ;;
    --keep)            KEEP=1 ;;
    --replace)         REPLACE=1 ;;
    --no-claude)       NO_CLAUDE=1 ;;
    --no-post)         NO_POST=1 ;;
    --chapter)         CHAPTER="$2"; shift ;;
    --out)             OUTDIR="$2"; shift ;;
    -h|--help)         sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "$OUTDIR"
TS="$(date +%Y%m%d-%H%M%S)"
JSON="$OUTDIR/${CHAPTER}-results-$TS.json"
MD="$OUTDIR/${CHAPTER}-report-$TS.md"
SVG="$OUTDIR/${CHAPTER}-report-$TS.svg"
PNG="$OUTDIR/${CHAPTER}-report-$TS.png"
TXT="$OUTDIR/${CHAPTER}-report-$TS.txt"
WEBSITE_REPO="vibe-code-tours/vibe-code-tours.github.io"
KEYFILE="${VIBE_KEYFILE:-vibe-key.env}"

# ---------- ui ----------
c_reset=$'\033[0m'; c_dim=$'\033[2m'
c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_bold=$'\033[1m'
ok()   { printf '  %s✅%s %s\n' "$c_ok"   "$c_reset" "$*"; }
warn() { printf '  %s⚠ %s%s\n'  "$c_warn" "$c_reset" "$*"; }
fail() { printf '  %s❌%s %s\n' "$c_err"  "$c_reset" "$*"; }
hr()   { printf '%s──────────────────────────────────────────────%s\n' "$c_dim" "$c_reset"; }
say()  { printf '%s%s%s\n' "$c_bold" "$*" "$c_reset"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------- load vibe-key.env (for proxy curl fallback) ----------
# shellcheck source=/dev/null
if [ -f "$KEYFILE" ]; then set -a; . "$KEYFILE" 2>/dev/null; set +a; fi
VIBE_PROXY="${VIBE_PROXY:-}"; VIBE_KEY="${VIBE_KEY:-}"

# ---------- 1. platform ----------
PLATFORM=linux
if [ "$(uname -s)" = "Darwin" ]; then PLATFORM=mac
elif grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then PLATFORM=wsl
fi
say "Vibe Code Doctor — $CHAPTER"; hr
echo "  platform: $PLATFORM"

# ---------- 2. claude location ----------
CLAUDE_LINUX=""; CLAUDE_WIN=""; CLAUDE_LOC=none
if have claude; then
  bin="$(command -v claude)"
  case "$bin" in
    /mnt/c/*|*/AppData/*|*.exe|*.cmd) CLAUDE_WIN="$bin"; CLAUDE_LOC=windows ;;
    *)                                CLAUDE_LINUX="$bin"; CLAUDE_LOC=linux ;;
  esac
fi
if [ "$PLATFORM" = "wsl" ]; then
  for p in "/mnt/c/Users/$USER/AppData/Roaming/npm/claude.cmd" \
           "/mnt/c/Program Files/nodejs/claude.cmd" \
           "$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')\\AppData\\Roaming\\npm\\claude.cmd" 2>/dev/null)"; do
    [ -n "$p" ] && [ -f "$p" ] && { CLAUDE_WIN="$p"; break; }
  done
  if [ -n "$CLAUDE_LINUX" ] && [ -n "$CLAUDE_WIN" ]; then CLAUDE_LOC=both
  elif [ -n "$CLAUDE_WIN" ] && [ -z "$CLAUDE_LINUX" ]; then CLAUDE_LOC=windows
  fi
fi
echo "  claude:   $CLAUDE_LOC${CLAUDE_LINUX:+  linux=$CLAUDE_LINUX}${CLAUDE_WIN:+  win=$CLAUDE_WIN}"
hr

# ---------- 2b. conflict resolution (ch-0 only) ----------
CHOICE=skip
if [ "$CHAPTER" = "ch-0" ] && [ "$CLAUDE_LOC" = "both" ]; then
  warn "windows-native AND wsl claude both installed — config drift risk"
  echo "    cohort recommends WSL-native only"
  if [ "$REPLACE" = "1" ] || [ "$NONINT" = "1" ]; then CHOICE=replace
  elif [ "$KEEP" = "1" ]; then CHOICE=keep
  else
    echo
    echo "    [R] REPLACE — uninstall windows, install in WSL (recommended)"
    echo "    [K] KEEP    — leave windows, route proxy to Windows .claude/"
    echo "    [S] SKIP    — keep both, accept risk"
    printf "    pick [R/K/S] (default R): "
    read -r ans
    case "${ans:-R}" in r|R) CHOICE=replace ;; k|K) CHOICE=keep ;; *) CHOICE=skip ;; esac
  fi
  echo "    choice: $CHOICE"
  case "$CHOICE" in
    replace)
      echo "    uninstalling windows-native claude…"
      if have powershell.exe; then
        powershell.exe -NoProfile -Command "npm uninstall -g @anthropic-ai/claude-code" 2>/dev/null || warn "uninstall returned non-zero"
      elif have cmd.exe; then
        cmd.exe /c "npm uninstall -g @anthropic-ai/claude-code" 2>/dev/null || warn "uninstall returned non-zero"
      else
        warn "no powershell/cmd — uninstall windows claude manually:"
        echo "      (in Windows) npm uninstall -g @anthropic-ai/claude-code"
      fi
      CLAUDE_WIN=""; CLAUDE_LOC=linux ;;
    keep) ok "keeping windows claude (proxy config will target Windows .claude/)" ;;
    skip) warn "skip — both installs left in place" ;;
  esac
fi

# ---------- 3. versions ----------
say "Versions"; hr
checks_pass=0; checks_total=0
record_check() {
  local name="$1" cmd="$2" want="$3"
  local out
  if out="$($cmd 2>&1)" && echo "$out" | grep -qE "$want"; then
    printf '  \033[32m✅\033[0m %s: %s\n' "$name" "$(echo "$out" | head -1)" >&2
    echo "ok"
  else
    printf '  \033[31m❌\033[0m %s: %s\n' "$name" "${out:-<missing>}" >&2
    echo "fail"
  fi
}
score_check() { checks_total=$((checks_total+1)); [ "$1" = "ok" ] && checks_pass=$((checks_pass+1)); }

NODE_R=$(record_check "node"   "node --version"     "^v(22|23|24)\.");           score_check "$NODE_R"
NPM_R=$(record_check  "npm"    "npm --version"      "^(1[0-9]|2[0-9])\.");        score_check "$NPM_R"
PY_R=$(record_check   "python" "python3 --version"  "^Python 3\.(12|13|14)\.");  score_check "$PY_R"
GIT_R=$(record_check  "git"    "git --version"      "git version 2\.");           score_check "$GIT_R"
GH_R=$(record_check   "gh"     "gh --version"       "gh version (2\.[4-9][0-9]|[3-9])"); score_check "$GH_R"
CL_R=$(record_check   "claude" "claude --version"   "^[0-9]");                     score_check "$CL_R"

# ---------- 4. github ----------
say "GitHub"; hr
GH_USER=""; GH_AUTH=fail; GH_PR=fail
if have gh && gh auth status >/dev/null 2>&1; then
  GH_AUTH=ok
  GH_USER="$(gh api user --jq .login 2>/dev/null || true)"
  if [ -n "$GH_USER" ]; then ok "auth: $GH_USER"; else warn "auth ok but /user empty"; fi
  if gh pr list --repo cli/cli --limit 1 >/dev/null 2>&1; then GH_PR=ok; ok "pr read probe (cli/cli)"
  else fail "pr read probe — token may lack repo scope"
  fi
else
  fail "gh not logged in (run: gh auth login)"
fi

# ---------- 5. proxy / claude api ----------
say "Proxy / Claude API"; hr
CL_API=fail; CL_REPLY=""; PROXY_HTTP=""
if have claude; then
  if CL_REPLY="$(claude -p "ping in one word" --output-format text 2>&1)" && [ -n "$CL_REPLY" ] && ! echo "$CL_REPLY" | grep -qiE "error|401|403|fetch failed|ENOTFOUND"; then
    CL_API=ok; ok "claude -p ping: $(echo "$CL_REPLY" | head -1 | cut -c1-60)"
  else
    fail "claude -p: $(echo "$CL_REPLY" | head -1 | cut -c1-100)"
  fi
fi
# curl fallback (also primary when claude missing)
if [ "$CL_API" != "ok" ] && [ -n "$VIBE_PROXY" ] && [ -n "$VIBE_KEY" ]; then
  PROXY_HTTP=$(curl -s -o /tmp/doctor_api.json -w '%{http_code}' --max-time 30 \
    "${VIBE_PROXY%/}/v1/chat/completions" \
    -H "Authorization: Bearer $VIBE_KEY" -H "Content-Type: application/json" \
    -d '{"model":"mimo-v2.5","messages":[{"role":"user","content":"say ok"}],"max_tokens":5}' 2>/dev/null)
  if [ "$PROXY_HTTP" = "200" ]; then
    CL_API=ok; ok "proxy curl: HTTP 200"
  else
    fail "proxy curl: HTTP ${PROXY_HTTP:-no-response} (check VIBE_PROXY/VIBE_KEY)"
  fi
elif [ "$CL_API" != "ok" ]; then
  fail "no proxy creds — set VIBE_PROXY+VIBE_KEY in $KEYFILE"
fi

# ---------- 6. chapter-specific ----------
CH1_PROFILE=fail; CH1_PR=""; CH1_PR_STATE=fail
if [ "$CHAPTER" = "ch-1" ]; then
  say "Chapter 1 — homework"; hr
  if [ -n "$GH_USER" ]; then
    if gh api "repos/$GH_USER/$GH_USER" >/dev/null 2>&1; then
      CH1_PROFILE=ok; ok "profile repo: github.com/$GH_USER/$GH_USER"
    else
      fail "profile repo $GH_USER/$GH_USER not found — create with a README"
    fi
    CH1_PR=$(gh pr list --repo "$WEBSITE_REPO" --author "$GH_USER" --state all --json url --jq '.[0].url' 2>/dev/null)
    if [ -n "$CH1_PR" ]; then
      CH1_PR_STATE=ok; ok "website PR: $CH1_PR"
    else
      fail "no PR to $WEBSITE_REPO by @$GH_USER"
    fi
  else
    fail "skipping profile/PR — gh not authed"
  fi
fi

# ---------- 7. results JSON ----------
# ch1 block only when actually run (ch-1); keeps it off the ch-0 card
CH1_JSON=""
if [ "$CHAPTER" = "ch-1" ]; then
  CH1_JSON="  \"ch1\": { \"profile\": \"$CH1_PROFILE\", \"pr_url\": \"$CH1_PR\", \"pr_state\": \"$CH1_PR_STATE\" },
"
fi
cat > "$JSON" <<EOF
{
  "ts": "$TS",
  "chapter": "$CHAPTER",
  "platform": "$PLATFORM",
  "claude_loc": "$CLAUDE_LOC",
  "claude_choice": "$CHOICE",
  "gh_user": "$GH_USER",
  "checks": {
    "node": "$NODE_R", "npm": "$NPM_R", "python": "$PY_R",
    "git": "$GIT_R", "gh": "$GH_R", "claude": "$CL_R"
  },
  "gh": { "auth": "$GH_AUTH", "pr_probe": "$GH_PR" },
  "proxy_api": "$CL_API",
${CH1_JSON}  "score": "$checks_pass/$checks_total"
}
EOF
ok "results json: $JSON"

# ---------- 8. card by chapter ----------
if [ "$CHAPTER" = "ch-0" ]; then
  render_static_svg() {
    local user="${GH_USER:-anonymous}" score="$checks_pass/$checks_total"
    local cl_badge="✅"; [ "$CL_API" = "fail" ] && cl_badge="❌"
    local gh_badge="✅"; [ "$GH_AUTH" = "fail" ] && gh_badge="❌"
    cat > "$SVG" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="800" height="450" viewBox="0 0 800 450">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#fef3e2"/><stop offset="1" stop-color="#fde2c4"/>
  </linearGradient></defs>
  <rect width="800" height="450" fill="url(#bg)"/>
  <rect x="20" y="20" width="760" height="410" fill="none" stroke="#d97706" stroke-width="3" rx="18"/>
  <text x="50" y="80" font-family="ui-monospace,monospace" font-size="32" font-weight="700" fill="#7c2d12">🎓 Vibe Code Doctor</text>
  <text x="50" y="120" font-family="ui-monospace,monospace" font-size="20" fill="#9a3412">@${user}</text>
  <text x="50" y="170" font-family="ui-monospace,monospace" font-size="18" fill="#1f2937">platform: ${PLATFORM}   claude: ${CLAUDE_LOC}</text>
  <text x="50" y="210" font-family="ui-monospace,monospace" font-size="18" fill="#1f2937">node ${NODE_R}   npm ${NPM_R}   python ${PY_R}</text>
  <text x="50" y="240" font-family="ui-monospace,monospace" font-size="18" fill="#1f2937">git ${GIT_R}   gh ${GH_R}   claude ${CL_R}</text>
  <text x="50" y="290" font-family="ui-monospace,monospace" font-size="22" fill="#7c2d12">${gh_badge} github: ${GH_USER:-not-authed}</text>
  <text x="50" y="320" font-family="ui-monospace,monospace" font-size="22" fill="#7c2d12">${cl_badge} proxy api: ${CL_API}</text>
  <text x="50" y="380" font-family="ui-monospace,monospace" font-size="28" font-weight="700" fill="#9a3412">score ${score} — $([ "$checks_pass" = "$checks_total" ] && echo 'ready ch-1 🚀' || echo 'see #help')</text>
  <text x="50" y="415" font-family="ui-monospace,monospace" font-size="14" fill="#a16207">vibecode.tours  ·  #ch-0  ·  ${TS}</text>
</svg>
SVG
  }
  render_claude_svg() {
    [ "$NO_CLAUDE" = "1" ] && return 1
    [ "$CL_API" = "fail" ] && return 1
    local prompt out
    prompt="Render this JSON as a single SVG badge card, 800x450, warm-amber palette (bg #fef3e2→#fde2c4, accents #d97706 #7c2d12 #9a3412), monospace, vibecode.tours footer. Render ONLY the fields present in the JSON — do not add sections or rows for data that is absent. Do NOT compute or invent any pass/fail tally; if you show a score, use the JSON \"score\" value exactly as given. Output SVG only — no markdown, no fences. JSON:
$(cat "$JSON")"
    if out="$(claude -p "$prompt" --output-format text 2>/dev/null)" && [ -n "$out" ] && echo "$out" | grep -q "<svg"; then
      echo "$out" | sed -n '/<svg/,/<\/svg>/p' > "$SVG"
      [ -s "$SVG" ] && return 0
    fi
    return 1
  }
  say "Card"; hr
  if render_claude_svg; then ok "claude rendered svg: $SVG"
  else render_static_svg; ok "static svg: $SVG"
  fi
  make_png() {
    if have rsvg-convert; then rsvg-convert "$SVG" -o "$PNG" 2>/dev/null && return 0; fi
    if have convert;       then convert "$SVG" "$PNG" 2>/dev/null && return 0; fi
    if have chromium;      then chromium --headless --no-sandbox --disable-gpu --screenshot="$PNG" --window-size=800,450 "file://$SVG" >/dev/null 2>&1 && return 0; fi
    if have google-chrome; then google-chrome --headless --no-sandbox --disable-gpu --screenshot="$PNG" --window-size=800,450 "file://$SVG" >/dev/null 2>&1 && return 0; fi
    return 1
  }
  if make_png; then ok "png: $PNG"
  else warn "no svg→png tool (install: librsvg2-bin OR imagemagick)"
  fi
  {
    echo "┌─ Vibe Code Doctor ──────────────┐"
    echo "│ user:     ${GH_USER:-anonymous}"
    echo "│ platform: $PLATFORM"
    echo "│ claude:   $CLAUDE_LOC ($CHOICE)"
    echo "│ checks:   ${NODE_R}/node ${NPM_R}/npm ${PY_R}/py ${GIT_R}/git ${GH_R}/gh ${CL_R}/claude"
    echo "│ proxy:    $CL_API"
    echo "│ score:    $checks_pass/$checks_total"
    echo "└──────────────────────────────────┘"
  } > "$TXT"
  echo
  say "Drop one of these in #ch-0-intro"; hr
  [ -f "$PNG" ] && echo "  image: $PNG"
  [ -f "$SVG" ] && echo "  svg:   $SVG  (fallback if no PNG)"
  echo "  text:  $TXT  (copy/paste fallback)"
  echo "  json:  $JSON"
  echo
  echo "  Wait for instructor ✅ → ch-0-done role → #ch-1 unlocks."

elif [ "$CHAPTER" = "ch-1" ]; then
  ch1_fail=0
  [ "$CL_API"       != "ok" ] && ch1_fail=1
  [ "$GH_AUTH"      != "ok" ] && ch1_fail=1
  [ "$CH1_PROFILE"  != "ok" ] && ch1_fail=1
  [ "$CH1_PR_STATE" != "ok" ] && ch1_fail=1
  {
    echo "# Chapter 1 check — $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo
    echo "- proxy api: $CL_API"
    echo "- gh auth: $GH_AUTH ($GH_USER)"
    echo "- profile repo: $CH1_PROFILE"
    echo "- website pr: ${CH1_PR:-none}"
    echo
    echo "---"
    echo "github_username: ${GH_USER:-none}"
    echo "website_pr: ${CH1_PR:-none}"
    echo "result: $([ "$ch1_fail" -eq 0 ] && echo PASS || echo INCOMPLETE)"
  } > "$MD"
  say "Chapter 1 report"; hr
  echo "  md: $MD"
  if [ "$ch1_fail" -ne 0 ]; then
    warn "checks failed — fix the ❌ rows above and re-run. Gist not posted."
    exit 1
  fi
  if [ "$NO_POST" = "1" ]; then
    echo "  --no-post — skipping gist. Manual: gh gist create --public $MD"
  elif have gh && gh auth status >/dev/null 2>&1; then
    url=$(gh gist create --public -d "Vibe Code Tours — Chapter 1 — @$GH_USER" "$MD" 2>/dev/null | tail -1)
    if [ -n "$url" ]; then
      ok "gist posted: $url"
      echo
      say "Submit it now (Discord or Telegram):"; hr
      echo "    /ch1 $url"
    else
      warn "gist post failed. Manual: gh gist create --public $MD"
    fi
  else
    echo "  gh not authed — manual gist: gh gist create --public $MD"
  fi
else
  warn "chapter $CHAPTER has no checker yet. Post evidence in #${CHAPTER} → instructor ✅."
fi

# ---------- 9. recovery on proxy fail ----------
if [ "$CL_API" = "fail" ]; then
  echo
  say "Proxy/API failed — recovery options:"; hr
  echo "  1. gemini  — free tier (gemini.google.com or 'gemini' CLI)"
  echo "  2. ollama  — offline (ollama run qwen2.5-coder:7b)"
  echo "  3. #help   — tag @instructor for manual /unlock"
  exit 2
fi

[ "$checks_pass" = "$checks_total" ] && exit 0 || exit 2
