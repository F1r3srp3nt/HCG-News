#!/usr/bin/env bash
# HCG News — access verification for the iOS/iPadOS integration.
#
# Run this yourself. It checks, against the live shared HCG project, exactly what
# the app relies on:
#   A. Anonymous (no sign-in): published articles are readable; drafts, scheduled
#      articles, editorial tables, private media and personal data are not.
#   B. Optional, signed in (--account): your HCG News roles as HCG reports them,
#      and that an account without a newsroom role can't read drafts.
#   C. Optional, write checks (--write-tests, staff account only): creates ONE
#      clearly labelled test draft, checks the edit guard, then deletes it.
#      It never publishes, schedules or touches an existing article.
#
# Requirements: bash, curl, python3. Nothing is stored. The password is read
# without echo and passed to curl on stdin (not visible in the process list).
#
# Usage:
#   ./verify-hcg-news-access.sh                      # anonymous checks only
#   ./verify-hcg-news-access.sh --account            # + signed-in checks
#   ./verify-hcg-news-access.sh --account --write-tests
set -euo pipefail

PROJECT="https://qggdyzoydveafkmjgkpq.supabase.co"
WEBSITE="https://beta.hakmicapitalgroup.com"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFnZ2R5em95ZHZlYWZrbWpna3BxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1ODQwODQsImV4cCI6MjA5ODE2MDA4NH0.OLbNhV_hvWwS_BqgYVxwU9TZ9P05lX2Fp-ake-hAJ4M"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ACCOUNT=0; WRITES=0
for a in "$@"; do
  case "$a" in --account) ACCOUNT=1 ;; --write-tests) WRITES=1; ACCOUNT=1 ;; *) echo "unknown option $a"; exit 2 ;; esac
done

PASS=0; FAIL=0; WARN=0
pass() { echo "  PASS  $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
warn() { echo "  NOTE  $*"; WARN=$((WARN+1)); }

# get PATH_AND_QUERY [TOKEN] -> prints "STATUS<TAB>BODY"
get() {
  local token="${2:-$ANON}"
  curl -sS -o /tmp/hcgnews.$$ -w '%{http_code}' -H "apikey: $ANON" -H "Authorization: Bearer $token" \
       -H "Accept: application/json" "$PROJECT$1" > /tmp/hcgnews.code.$$ || echo 000 > /tmp/hcgnews.code.$$
  printf '%s\t%s' "$(cat /tmp/hcgnews.code.$$)" "$(cat /tmp/hcgnews.$$ 2>/dev/null)"
}
count_rows() { python3 -c 'import sys,json
s,b=sys.stdin.read().split("\t",1)
try:
  d=json.loads(b); print(len(d) if isinstance(d,list) else -1)
except Exception: print(-1)'; }
status_of() { cut -f1; }
cleanup() { rm -f /tmp/hcgnews.$$ /tmp/hcgnews.code.$$; }
trap cleanup EXIT

echo "HCG News access verification — $NOW"
echo
echo "A. Anonymous reader (public client key only)"

R="$(get "/rest/v1/news_articles?select=id&status=eq.published&published_at=lte.$NOW&limit=5")"
N="$(printf '%s' "$R" | count_rows)"
if [ "$N" -gt 0 ]; then pass "published articles are readable anonymously ($N on the first page)"
elif [ "$N" -eq 0 ]; then fail "no published articles readable anonymously — the app's Home will be empty (see backend/HCG-NEWS-PUBLIC-READ.md)"
else fail "published read failed: HTTP $(printf '%s' "$R" | status_of)"; fi

R="$(get "/rest/v1/news_articles?select=id,status&status=neq.published&limit=5")"
N="$(printf '%s' "$R" | count_rows)"
[ "$N" -le 0 ] && pass "drafts / in review / approved / archived are NOT readable anonymously" || fail "$N unpublished article(s) readable anonymously"

R="$(get "/rest/v1/news_articles?select=id&status=eq.published&published_at=gt.$NOW&limit=5")"
N="$(printf '%s' "$R" | count_rows)"
[ "$N" -le 0 ] && pass "scheduled (future) articles are NOT readable anonymously" || fail "$N scheduled article(s) readable before publication"

for col in created_by seo_title view_count; do
  R="$(get "/rest/v1/news_articles?select=$col&status=eq.published&limit=1")"
  S="$(printf '%s' "$R" | status_of)"; N="$(printf '%s' "$R" | count_rows)"
  if [ "$N" -gt 0 ]; then warn "editorial column '$col' is readable anonymously (the app never requests it; consider column grants)"
  else pass "editorial column '$col' is not readable anonymously (HTTP $S)"; fi
done

for t in news_article_versions news_audit news_media news_newsletter_subscribers news_site_settings; do
  R="$(get "/rest/v1/$t?select=*&limit=1")"
  S="$(printf '%s' "$R" | status_of)"; N="$(printf '%s' "$R" | count_rows)"
  [ "$N" -le 0 ] && pass "$t is not readable anonymously (HTTP $S)" || fail "$t returns rows to anonymous requests"
done

R="$(get "/rest/v1/news_categories?select=id,slug&is_visible=eq.true&limit=50")"
N="$(printf '%s' "$R" | count_rows)"
[ "$N" -gt 0 ] && pass "visible sections are readable anonymously ($N)" || warn "no sections readable anonymously (section browsing in the app will be empty)"

S="$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
     -H 'Content-Type: application/json' -d '{"prefix":"","limit":1}' "$PROJECT/storage/v1/object/list/hcg-news-media" || echo 000)"
R="$(curl -sS -X POST -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' \
     -d '{"prefix":"","limit":1}' "$PROJECT/storage/v1/object/list/hcg-news-media" 2>/dev/null || true)"
if [ "$S" = "200" ] && [ "$R" != "[]" ]; then fail "the media bucket can be listed anonymously"; else pass "the media bucket can't be listed anonymously (HTTP $S)"; fi

if [ "$ACCOUNT" -eq 1 ]; then
  echo
  echo "B. Signed in with an HCG account"
  read -r -p "  HCG account email: " EMAIL
  read -r -s -p "  Password (not shown): " PASSWORD; echo
  TOKEN_JSON="$(python3 -c 'import json,sys; print(json.dumps({"email":sys.argv[1],"password":sys.stdin.read()}))' "$EMAIL" <<<"$PASSWORD" \
    | curl -sS -X POST -H "apikey: $ANON" -H 'Content-Type: application/json' --data @- "$PROJECT/auth/v1/token?grant_type=password")"
  unset PASSWORD
  TOKEN="$(printf '%s' "$TOKEN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null || true)"
  USER_ID="$(printf '%s' "$TOKEN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("user",{}).get("id",""))' 2>/dev/null || true)"
  if [ -z "$TOKEN" ]; then fail "sign-in failed (wrong email or password, or unconfirmed account)"; exit 1; fi
  pass "signed in (the same password grant the website and HCG ONE use)"

  ROLES=""
  for key in news.administrator news.editor_in_chief news.editor news.journalist news.contributor; do
    V="$(curl -sS -X POST -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
         -d "{\"_user_id\":\"$USER_ID\",\"_feature_key\":\"$key\"}" "$PROJECT/rest/v1/rpc/news_has_feature" || echo error)"
    echo "        $key: $V"
    [ "$V" = "true" ] && ROLES="$ROLES $key"
  done
  [ -n "$ROLES" ] && pass "HCG News roles from HCG:$ROLES" || warn "this account has no HCG News role (expected for an ordinary reader)"

  W="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$WEBSITE/api/public/mobile/workspaces" || echo 000)"
  [ "$W" = "200" ] && pass "HCG workspace directory answers for this account" || warn "workspace directory returned HTTP $W"

  R="$(get "/rest/v1/news_articles?select=id,status&status=eq.draft&limit=5" "$TOKEN")"
  N="$(printf '%s' "$R" | count_rows)"
  if [ -z "$ROLES" ]; then
    [ "$N" -le 0 ] && pass "an account without a newsroom role can't read drafts" || fail "an account without a newsroom role can read $N draft(s)"
    R="$(get "/rest/v1/news_audit?select=id&limit=1" "$TOKEN")"; N="$(printf '%s' "$R" | count_rows)"
    [ "$N" -le 0 ] && pass "an account without a newsroom role can't read the audit log" || fail "audit log readable without a role"
  else
    pass "staff account can list drafts ($N on the first page)"
  fi

  if [ "$WRITES" -eq 1 ]; then
    echo
    echo "C. Write checks (one labelled test draft; never published)"
    if [ -z "$ROLES" ]; then
      S="$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
           -d "{\"title\":\"HCG News iOS verification - test draft, do not publish\",\"slug\":\"draft-verify-$(date +%s)\",\"status\":\"draft\",\"created_by\":\"$USER_ID\"}" \
           "$PROJECT/rest/v1/news_articles")"
      case "$S" in 401|403) pass "an account without a newsroom role can't create articles (HTTP $S)" ;; *) fail "article creation without a role returned HTTP $S — check and remove any 'verification' draft" ;; esac
    else
      ROW="$(curl -sS -X POST -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
           -d "{\"title\":\"HCG News iOS verification - test draft, do not publish\",\"slug\":\"draft-verify-$(date +%s)\",\"status\":\"draft\",\"created_by\":\"$USER_ID\"}" \
           "$PROJECT/rest/v1/news_articles?select=id,updated_at")"
      ID="$(printf '%s' "$ROW" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["id"] if isinstance(d,list) and d else "")' 2>/dev/null || true)"
      REV="$(printf '%s' "$ROW" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["updated_at"] if isinstance(d,list) and d else "")' 2>/dev/null || true)"
      if [ -z "$ID" ]; then fail "test draft not created: $ROW"; else
        pass "test draft created ($ID)"
        ENC="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$REV")"
        N="$(curl -sS -X PATCH -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
             -d '{"title":"HCG News iOS verification - edited test draft"}' "$PROJECT/rest/v1/news_articles?id=eq.$ID&updated_at=eq.$ENC&select=id" \
             | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else -1)')"
        [ "$N" = "1" ] && pass "revision-guarded save works" || fail "revision-guarded save matched $N rows"
        N="$(curl -sS -X PATCH -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
             -d '{"title":"stale write"}' "$PROJECT/rest/v1/news_articles?id=eq.$ID&updated_at=eq.$ENC&select=id" \
             | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else -1)')"
        [ "$N" = "0" ] && pass "a stale save is rejected (conflict detection works: updated_at changes on save)" \
                       || fail "a stale save was applied ($N rows): updated_at is not maintained, so concurrent edits can't be detected"
        S="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" "$PROJECT/rest/v1/news_articles?id=eq.$ID")"
        case "$S" in 200|204) pass "test draft deleted" ;; *) warn "couldn't delete the test draft (HTTP $S): delete '$ID' in the newsroom" ;; esac
      fi
    fi
  fi
  curl -sS -o /dev/null -X POST -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" "$PROJECT/auth/v1/logout?scope=local" || true
  unset TOKEN
fi

echo
echo "Result: $PASS passed, $FAIL failed, $WARN notes."
[ "$FAIL" -eq 0 ]
