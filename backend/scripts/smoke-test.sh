#!/usr/bin/env bash
# Smoke test Ichimon backend on Fly.io
# Usage: ./scripts/smoke-test.sh [BASE_URL]
set -u

BASE="${1:-https://ichimon.fly.dev}"
ISSUER="${ISSUER_TOKEN:-demo-1}"
PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
check_code() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then pass "$name ($actual)"; else fail "$name expected=$expected got=$actual"; fi
}

echo "Testing $BASE"
echo

echo "[1] GET /health"
r=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -w "\n%{http_code}" "$BASE/health")
code=$(echo "$r" | tail -n1); body=$(echo "$r" | sed '$d')
check_code "status 200" 200 "$code"
echo "$body" | grep -q '"ok":true' && pass "ok=true" || fail "ok field"
echo

echo "[2] GET /ready"
r=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -w "\n%{http_code}" "$BASE/ready")
code=$(echo "$r" | tail -n1); body=$(echo "$r" | sed '$d')
echo "  body: $body"
if [[ "$code" == "200" ]]; then pass "status 200"
elif [[ "$code" == "503" ]]; then fail "503 — check nonce/sui ping in body above"
else fail "unexpected $code"; fi
echo

echo "[3] GET /api/config"
r=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -w "\n%{http_code}" "$BASE/api/config")
code=$(echo "$r" | tail -n1); body=$(echo "$r" | sed '$d')
check_code "status 200" 200 "$code"
echo "$body" | grep -q '"network":"testnet"' && pass "network=testnet" || fail "network field"
echo "$body" | grep -q '"pkg_id":"0x' && pass "pkg_id 0x..." || fail "pkg_id"
echo "$body" | grep -q '"initial_shared_version":"828957603"' && pass "initial_shared_version" || fail "initial_shared_version"
echo

echo "[4] GET /api/stations"
r=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -w "\n%{http_code}" "$BASE/api/stations")
code=$(echo "$r" | tail -n1); body=$(echo "$r" | sed '$d')
check_code "status 200" 200 "$code"
n=$(echo "$body" | grep -o '"station_id"' | wc -l | tr -d ' ')
[[ "$n" == "3" ]] && pass "3 stations" || fail "stations count=$n"
echo

echo "[5] GET /api/fighter/takeru"
r=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -w "\n%{http_code}" "$BASE/api/fighter/takeru")
code=$(echo "$r" | tail -n1); body=$(echo "$r" | sed '$d')
check_code "status 200" 200 "$code"
echo "$body" | grep -q '"fighter_id":"takeru"' && pass "fighter_id=takeru" || fail "fighter_id"
if echo "$body" | grep -q '"total_fans":[0-9]'; then
  tf=$(echo "$body" | grep -o '"total_fans":[0-9]*' | head -1)
  pass "$tf (chain read OK)"
else
  fail "total_fans missing (sui.getMintRegistrySize failed; check Fly logs)"
fi
echo

echo "[6] GET /api/fighter/unknown → 404"
code=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -o /dev/null -w "%{http_code}" "$BASE/api/fighter/unknown")
check_code "status 404" 404 "$code"
echo

echo "[7] GET /api/moments"
r=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -w "\n%{http_code}" "$BASE/api/moments")
code=$(echo "$r" | tail -n1); body=$(echo "$r" | sed '$d')
check_code "status 200" 200 "$code"
n=$(echo "$body" | grep -o '"moment_id"' | wc -l | tr -d ' ')
[[ "$n" == "3" ]] && pass "3 moments" || fail "moments count=$n"
echo

echo "[8] POST /api/checkin/qr/issue"
r=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -w "\n%{http_code}" -X POST "$BASE/api/checkin/qr/issue" \
  -H 'content-type: application/json' \
  -d "{\"station_id\":\"st-2026-tokyo\",\"fighter_id\":\"takeru\",\"issuer_token\":\"$ISSUER\"}")
code=$(echo "$r" | tail -n1); body=$(echo "$r" | sed '$d')
check_code "status 200" 200 "$code"
QR=$(echo "$body" | sed -n 's/.*"qr_payload":"\([^"]*\)".*/\1/p')
if [[ -n "$QR" && $(echo "$QR" | tr -cd '.' | wc -c | tr -d ' ') == "2" ]]; then
  pass "qr_payload has 3 parts"
else
  fail "qr_payload malformed"
  echo "  body: $body"
fi
echo

echo "[9] POST /api/checkin/qr/verify (first time → 200)"
code=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -o /tmp/verify1.json -w "%{http_code}" -X POST "$BASE/api/checkin/qr/verify" \
  -H 'content-type: application/json' \
  -d "{\"qr_payload\":\"$QR\"}")
check_code "status 200" 200 "$code"
grep -q '"ok":true' /tmp/verify1.json && pass "ok=true" || { fail "ok field"; cat /tmp/verify1.json; }
echo

echo "[10] POST /api/checkin/qr/verify (replay → 409 NONCE_USED) — validates Upstash"
code=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -o /tmp/verify2.json -w "%{http_code}" -X POST "$BASE/api/checkin/qr/verify" \
  -H 'content-type: application/json' \
  -d "{\"qr_payload\":\"$QR\"}")
check_code "status 409" 409 "$code"
grep -q '"code":"NONCE_USED"' /tmp/verify2.json && pass "code=NONCE_USED" || { fail "code field"; cat /tmp/verify2.json; }
echo

echo "[11] POST /api/checkin/qr/issue with bad token → 401"
code=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -o /dev/null -w "%{http_code}" -X POST "$BASE/api/checkin/qr/issue" \
  -H 'content-type: application/json' \
  -d '{"station_id":"x","fighter_id":"takeru","issuer_token":"bogus"}')
check_code "status 401" 401 "$code"
echo

echo "[12] POST /api/checkin/qr/verify with garbage → 400 MALFORMED_QR"
code=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -o /tmp/verify3.json -w "%{http_code}" -X POST "$BASE/api/checkin/qr/verify" \
  -H 'content-type: application/json' \
  -d '{"qr_payload":"not.a.qr"}')
check_code "status 400" 400 "$code"
grep -q 'MALFORMED_QR\|INVALID_SIGNATURE' /tmp/verify3.json && pass "error code present" || fail "error missing"
echo

echo "[13] GET /docs/json (Swagger)"
code=$(curl -s --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 -o /tmp/openapi.json -w "%{http_code}" "$BASE/docs/json")
check_code "status 200" 200 "$code"
grep -q '"openapi"' /tmp/openapi.json && pass "openapi field present" || fail "not openapi json"
echo

echo "────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" == "0" ]] && exit 0 || exit 1
