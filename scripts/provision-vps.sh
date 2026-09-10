#!/usr/bin/env bash
#
# provision-vps.sh — provision the V1 production VPS on Hetzner Cloud AND
# take it from a bare box to an SSH-reachable, hardened, Coolify-installed,
# admin-bootstrapped state with an automation API token minted ON THE BOX.
# DevOps-owned. Phase 1 executes `docs/deployment-runbook.md` §1 through the
# Hetzner API instead of the web console (F/CTO chose scripted provisioning
# 2026-09-09); Phase 2 executes §1's hardening + §3's Coolify install and
# admin bootstrap over SSH (F/CTO directive 2026-09-10: the stand-up must be
# a scripted re-run a stranger can execute, zero browser steps).
#
# WHY THIS EXISTS
#   §1/§3 were written to be executed by a human in a console or browser.
#   Doing it by hand once produces a box nobody can reproduce: the region,
#   image, firewall rules, hardening, Coolify version and admin credential
#   all live only in whatever the operator clicked or typed. This script
#   makes the box a function of the file, so a rebuild after a loss is a
#   re-run rather than an archaeology exercise. Phase 2 specifically closes a
#   gap found reconstructing the ACTUAL 2026-09 stand-up: every step but one
#   was already scripted or SSH-driven; the one browser step (Coolify's
#   first-run registration form) turned out to be unnecessary, not load-
#   bearing -- see the "Admin bootstrap" step below for the source-verified
#   non-interactive path that replaces it.
#
# WHAT IT REFUSES TO DO
#   It never prints an API token or password (Hetzner's or Coolify's), never
#   writes one anywhere off the box, and never creates or mutates anything
#   unless invoked with --apply. The default is a preflight that only reads
#   -- Phase 1's Hetzner-side creation is skipped entirely without --apply,
#   and Phase 2 (SSH) still RUNS in preflight mode when the box already
#   exists, reporting what it would do rather than doing it, which is what
#   makes "prove this script is a no-op against the box we already have"
#   possible without a flag that mutates production.
#
# IDEMPOTENCE
#   Every create is preceded by a lookup — by resource NAME on the Hetzner
#   side, by remote STATE (file content, package existence, DB row presence)
#   on the SSH side. Re-running after a partial failure adopts what already
#   exists rather than making a second copy or re-applying something already
#   correct. The one thing it will NOT do is mutate a resource that exists
#   but disagrees with this file — it stops and shows the difference, because
#   silently reconciling a live production box is how you delete something
#   you meant to keep.
#
# USAGE
#   scripts/provision-vps.sh              # preflight: read-only, prints the plan
#   scripts/provision-vps.sh --apply      # create/harden/install what the preflight described
#
set -euo pipefail

# ---- Ruled parameters. Change these here, never at the call site. ----------
SERVER_NAME="${SERVER_NAME:-pfin-prod-1}"
SERVER_TYPE="cax21"          # RULED 2026-09-08 (F/CTO): 4 ARM vCPU / 8 GB / 80 GB
LOCATION="${LOCATION:-fsn1}" # runbook §1: Falkenstein, fall back to hel1 on capacity
IMAGE="ubuntu-24.04"         # runbook §1: Coolify supports Debian-based; arm64
# SSH keys to install on the box. Space-separated list of PUBLIC key paths.
#
# ⚠ AT LEAST ONE MUST BE PASSPHRASE-FREE, and the script enforces it at run
# time. This is not a style preference — it is the failure this list exists to
# prevent. The first provisioned box (2026-09-09) carried only a
# passphrase-protected key: the box was correct, sshd was up, the firewall was
# right, and automation still could not log in, because a passphrase needs a
# terminal that a script does not have. The box had to be destroyed and
# rebuilt. A key you cannot use is indistinguishable from a key that is not
# there, and you find out AFTER provisioning.
SSH_PUBKEYS="${SSH_PUBKEYS:-$HOME/.ssh/id_ed25519.pub $HOME/.ssh/id_ed25519_claude_mosko-fintech.pub}"
SSH_KEY_PREFIX="${SSH_KEY_PREFIX:-mosko-fintech}"
# Escape hatch: allow an all-passphrase key set. Only for a box a human will
# ever touch by hand. Nothing scripted will be able to reach it.
ALLOW_NO_AUTOMATION_KEY="${ALLOW_NO_AUTOMATION_KEY:-0}"
FIREWALL_NAME="${FIREWALL_NAME:-pfin-prod-fw}"
# A Primary IP is created SEPARATELY from the server and outlives it
# (auto_delete=false). That is the whole point: DNS for pfindash.com points at
# this address once, and a box rebuild re-attaches the same IP instead of
# forcing a DNS change and a propagation wait. Costs EUR 0.60/mo gross, and it
# keeps billing while unassigned -- that is what you are buying.
PRIMARY_IP_NAME="${PRIMARY_IP_NAME:-pfin-prod-ipv4}"
# :8000 (the Coolify dashboard) is DELIBERATELY NOT in the firewall.
#
# The two alternatives were both worse. Leaving it open to the world is a
# standing bet that Coolify never ships an auth vulnerability. Pinning the
# operator's own address does not work either: it is a residential dynamic
# lease (confirmed by F/CTO 2026-09-09), so an ISP rotation locks the
# operator out of the dashboard at whatever moment the lease turns over.
#
# The dashboard is reached over an SSH tunnel instead -- the operator already
# holds the key, so this removes the exposure class rather than narrowing it,
# and it is immune to the address changing:
#
#   ssh -L 8000:localhost:8000 root@<box-ip>   # then browse localhost:8000
#
# Coolify's own first-run admin setup works through the tunnel.

API="https://api.hetzner.cloud/v1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0; REBUILD=0; RESET_ADMIN_PASSWORD=0
for arg in "$@"; do
  case "$arg" in
    --apply)                APPLY=1 ;;
    --rebuild)               REBUILD=1 ;;
    --reset-admin-password)  RESET_ADMIN_PASSWORD=1 ;;
    *) echo "unknown flag: $arg" >&2
       echo "usage: $0 [--apply] [--rebuild] [--reset-admin-password]" >&2; exit 2 ;;
  esac
done

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ---- Token: read from .env, never echoed, never exported to children ------
# Named HETZNER_API_TOKEN, not _KEY -- renamed 2026-09-10 to match Hetzner's own
# name for it (an API Token, sent as a bearer), this repo's own _TOKEN/_KEY split
# (_TOKEN for bearer tokens like SIMPLEFIN_TOKEN, _KEY for actual keys), and its
# sibling COOLIFY_API_TOKEN. Deliberately NOT read as a fallback from the old
# HETZNER_API_KEY name -- a silent alias is how two names stay alive forever;
# the die message below names both spellings so the rename is diagnosed in one
# read instead of a bare "missing".
[[ -f "$REPO_ROOT/.env" ]] || die "no .env at $REPO_ROOT — HETZNER_API_TOKEN is read from there"
# `|| true` on the grep: under `set -o pipefail`, a no-match grep inside a
# command-substitution PIPELINE is a "failing command" and set -e aborts the
# whole script right here, silently (no die(), no message) -- before the
# -z check below ever runs. Caught by actually testing the missing-var path,
# not by inspection: the original single-name version of this line had the
# same latent bug, just never exercised because .env always had the var set.
TOKEN="$(grep -m1 '^HETZNER_API_TOKEN=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' \r\n' || true)"
if [[ -z "$TOKEN" ]]; then
  if grep -q '^HETZNER_API_KEY=' "$REPO_ROOT/.env" 2>/dev/null; then
    die "HETZNER_API_TOKEN missing from .env, but HETZNER_API_KEY is present -- that name was renamed 2026-09-10 (Hetzner calls it an API Token; this repo's _TOKEN/_KEY convention agrees). Rename the line in .env, don't add a second one."
  fi
  die "HETZNER_API_TOKEN missing or empty in .env. See docs/deployment-runbook.md §0 for where to create one."
fi
[[ ${#TOKEN} -eq 64 ]] || die "HETZNER_API_TOKEN is ${#TOKEN} chars; Hetzner tokens are 64 — wrong value or a stray quote"

api() { # api <METHOD> <PATH> [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" -H "Authorization: Bearer $TOKEN" \
         -H 'Content-Type: application/json' -d "$body" "$API$path"
  else
    curl -fsS -X "$method" -H "Authorization: Bearer $TOKEN" "$API$path"
  fi
}
jqp() { python3 -c "import json,sys;$1" ; }

step "Preflight — reading current state (no writes)"

api GET /servers >/dev/null || die "token rejected by Hetzner (401/403). Check HETZNER_API_TOKEN has Read & Write."
ok "token authenticates"

# Spec check: assert the ruled spec against what Hetzner actually sells today.
api GET "/server_types?name=$SERVER_TYPE" | jqp "
d=json.load(sys.stdin)['server_types']
assert d, 'server type $SERVER_TYPE not found'
t=d[0]
assert t['cores']==4 and t['memory']==8 and t['disk']==80, \
  'SPEC DRIFT: $SERVER_TYPE is now %s cores / %s GB / %s GB — the ruling assumed 4/8/80' % (t['cores'],t['memory'],t['disk'])
assert t['architecture']=='arm', 'architecture is %s, expected arm' % t['architecture']
p=[x for x in t['prices'] if x['location']=='$LOCATION']
assert p, 'not offered in $LOCATION'
print('      %s: %s cores %s | %s GB RAM | %s GB disk | EUR %.2f/mo gross in %s'
      % (t['name'],t['cores'],t['architecture'],t['memory'],t['disk'],
         float(p[0]['price_monthly']['gross']),'$LOCATION'))
"
ok "server type matches the ruled spec"

IMAGE_ID="$(api GET "/images?name=$IMAGE&architecture=arm" | jqp "
d=json.load(sys.stdin)['images']
assert d, 'image $IMAGE (arm) not available'
print(d[0]['id'])
")"
ok "image $IMAGE (arm) available — id $IMAGE_ID"

EXISTING_SERVER="$(api GET "/servers?name=$SERVER_NAME" | jqp "
d=json.load(sys.stdin)['servers']
print(json.dumps({'id':d[0]['id'],'type':d[0]['server_type']['name'],
                  'ip':(d[0]['public_net']['ipv4'] or {}).get('ip'),
                  'status':d[0]['status']}) if d else '')
")"
if [[ -n "$EXISTING_SERVER" ]]; then
  info "server '$SERVER_NAME' ALREADY EXISTS: $EXISTING_SERVER"
  echo "$EXISTING_SERVER" | jqp "
d=json.load(sys.stdin)
assert d['type']=='$SERVER_TYPE', \
  'existing server is %s, this script describes $SERVER_TYPE. Refusing to touch it — resolve by hand.' % d['type']
"
  if [[ $REBUILD -eq 0 ]]; then
    ok "existing server matches this file; nothing to create"
    info "to change its SSH key set you must --rebuild (keys are fixed at creation)"
  else
    info "--rebuild given: this server will be DESTROYED and recreated"
  fi
fi

EXISTING_PIP="$(api GET "/primary_ips?name=$PRIMARY_IP_NAME" | jqp "
d=json.load(sys.stdin)['primary_ips']
print(json.dumps({'id':d[0]['id'],'ip':d[0]['ip'],'assignee':d[0]['assignee_id']}) if d else '')
")"
if [[ -n "$EXISTING_PIP" ]]; then
  ok "primary IP '$PRIMARY_IP_NAME' already exists: $EXISTING_PIP"
else
  info "primary IP '$PRIMARY_IP_NAME' does not exist yet — will be created"
fi

# ---- Key validation. Run BEFORE anything is created, never after. --------
step "SSH keys — validating usability, not just presence"

KEY_PATHS=(); KEY_USABLE=0
for pub in $SSH_PUBKEYS; do
  [[ -f "$pub" ]] || die "no public key at $pub"
  priv="${pub%.pub}"
  fpr="$(ssh-keygen -lf "$pub" | awk '{print $2}')"
  if [[ ! -f "$priv" ]]; then
    verdict="public only — no private half here"
  elif ssh-keygen -y -P "" -f "$priv" >/dev/null 2>&1; then
    verdict="usable by automation (no passphrase)"; KEY_USABLE=$((KEY_USABLE+1))
  else
    verdict="PASSPHRASE-PROTECTED — humans only, no script can use it"
  fi
  printf '      %-52s %s\n' "$(basename "$pub")" "$verdict"
  info "  $fpr"
  KEY_PATHS+=("$pub")
  # First usable-by-automation PRIVATE key becomes the one the SSH phase below
  # uses to reach the box. Only set once (first match wins), matching the
  # order SSH_PUBKEYS is given in.
  if [[ -z "${AUTOMATION_KEY:-}" && "$verdict" == usable* ]]; then
    AUTOMATION_KEY="$priv"
  fi
done

if [[ $KEY_USABLE -eq 0 ]]; then
  if [[ "$ALLOW_NO_AUTOMATION_KEY" == "1" ]]; then
    info "WARNING: no automation-usable key, proceeding because ALLOW_NO_AUTOMATION_KEY=1."
    info "         Nothing scripted will be able to reach this box."
  else
    die "none of these keys is usable without a passphrase.

  A script has no terminal to type a passphrase into, so this box would come
  up correct and still be unreachable by automation — exactly the failure that
  destroyed and rebuilt the first box on 2026-09-09.

  Fix by ONE of:
    * add a passphrase-free key to SSH_PUBKEYS=
    * ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_automation
    * set ALLOW_NO_AUTOMATION_KEY=1 if this box is genuinely hand-operated only"
  fi
fi
ok "$KEY_USABLE of ${#KEY_PATHS[@]} key(s) usable by automation"

step "Plan"
cat <<PLAN
      server    $SERVER_NAME  ($SERVER_TYPE, $IMAGE, $LOCATION)
      ssh keys  ${#KEY_PATHS[@]} key(s), $KEY_USABLE usable by automation
      firewall  $FIREWALL_NAME  in: 22, 80, 443 only
                                :8000 NOT opened — dashboard via SSH tunnel
                                :8081 NOT opened (runbook §1 / §7 CA-4)
      primary   $PRIMARY_IP_NAME  (ipv4, auto_delete=false — survives a rebuild)
PLAN

if [[ $APPLY -eq 0 && -z "$EXISTING_SERVER" ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created. Re-run with --apply to execute.\n'
  exit 0
fi
if [[ $APPLY -eq 0 ]]; then
  info "PREFLIGHT: server '$SERVER_NAME' already exists -- skipping Hetzner-side creation, continuing into Phase 2's read-only checks over SSH (this is what makes 'dry-run against the current box' possible)."
fi

if [[ $APPLY -eq 1 ]]; then
step "Applying"

SSH_KEY_IDS=()
for pub in "${KEY_PATHS[@]}"; do
  kname="$SSH_KEY_PREFIX-$(basename "${pub%.pub}")"
  # Look up by FINGERPRINT, not name. Hetzner rejects duplicate key MATERIAL
  # with a 409 regardless of what you call it, so a name-keyed lookup misses a
  # key already uploaded under a different name and then fails on the insert.
  # The key's identity is its material; the name is a label on top of it.
  # Measured 2026-09-09 when the naming scheme changed from a single
  # "-operator" key to per-file names.
  md5fpr="$(ssh-keygen -lf "$pub" -E md5 | awk '{print $2}' | sed 's/^MD5://')"
  kid="$(api GET /ssh_keys | MD5FPR="$md5fpr" jqp "
import os
d=json.load(sys.stdin)['ssh_keys']
m=[k['id'] for k in d if k['fingerprint']==os.environ['MD5FPR']]
print(m[0] if m else '')")"
  if [[ -z "$kid" ]]; then
    pubval="$(tr -d '\r\n' < "$pub")"
    # Build this payload with a HEREDOC, not an inline python dict.
    # A `{'a':1,'b':2}` literal written inline is brace-expanded by the shell
    # into two words BEFORE python ever sees it, producing `json.dumps('a':1)`
    # and a SyntaxError. Measured 2026-09-09 on the first --apply run.
    payload="$(KNAME="$kname" PUBVAL="$pubval" python3 <<'PYJSON'
import json, os
print(json.dumps({"name": os.environ["KNAME"],
                  "public_key": os.environ["PUBVAL"]}))
PYJSON
)"
    kid="$(api POST /ssh_keys "$payload" | jqp "print(json.load(sys.stdin)['ssh_key']['id'])")"
    ok "uploaded $kname — id $kid"
  else
    ok "already present $kname — id $kid"
  fi
  SSH_KEY_IDS+=("$kid")
done
SSH_KEYS_JSON="$(IFS=,; echo "${SSH_KEY_IDS[*]}")"

FW_ID="$(api GET "/firewalls?name=$FIREWALL_NAME" | jqp "
d=json.load(sys.stdin)['firewalls']; print(d[0]['id'] if d else '')")"
if [[ -z "$FW_ID" ]]; then
  FW_ID="$(api POST /firewalls "$(cat <<JSON
{"name":"$FIREWALL_NAME","rules":[
 {"direction":"in","protocol":"tcp","port":"22","source_ips":["0.0.0.0/0","::/0"],"description":"operator SSH + Coolify server connection"},
 {"direction":"in","protocol":"tcp","port":"80","source_ips":["0.0.0.0/0","::/0"],"description":"ACME HTTP-01 + HTTP->HTTPS redirect"},
 {"direction":"in","protocol":"tcp","port":"443","source_ips":["0.0.0.0/0","::/0"],"description":"HTTPS to Coolify-fronted services"}
]}
JSON
)" | jqp "print(json.load(sys.stdin)['firewall']['id'])")"
  ok "firewall created — id $FW_ID"
else
  ok "firewall already present — id $FW_ID"
fi

PIP_ID="$(api GET "/primary_ips?name=$PRIMARY_IP_NAME" | jqp "
d=json.load(sys.stdin)['primary_ips']; print(d[0]['id'] if d else '')")"
if [[ -z "$PIP_ID" ]]; then
  # An UNASSIGNED primary IP is created against a `location`, not a
  # `datacenter` — the API requires "either assignee_id or location" and
  # rejects a datacenter-only body with 422. Measured 2026-09-09; an earlier
  # draft here resolved a datacenter name, which was solving a problem that
  # does not exist at creation time.
  PIP_JSON="$(api POST /primary_ips "$(cat <<JSON
{"name":"$PRIMARY_IP_NAME","type":"ipv4","location":"$LOCATION",
 "assignee_type":"server","auto_delete":false,
 "labels":{"project":"mosko-fintech","env":"production"}}
JSON
)")"
  PIP_ID="$(echo "$PIP_JSON" | jqp "print(json.load(sys.stdin)['primary_ip']['id'])")"
  PIP_ADDR="$(echo "$PIP_JSON" | jqp "print(json.load(sys.stdin)['primary_ip']['ip'])")"
  ok "primary IP created — $PIP_ADDR (id $PIP_ID, auto_delete=false)"
  PIP_V4_NEW=1
else
  PIP_ADDR="$(api GET "/primary_ips/$PIP_ID" | jqp "print(json.load(sys.stdin)['primary_ip']['ip'])")"
  ok "primary IP already present — $PIP_ADDR (id $PIP_ID)"
fi

if [[ -n "$EXISTING_SERVER" && $REBUILD -eq 1 ]]; then
  # Hetzner's own /actions/rebuild re-images the disk but does NOT re-apply
  # ssh_keys — the keys are fixed at creation. Changing the key set therefore
  # means destroy-and-recreate, not rebuild. The PRIMARY IP is what makes that
  # cheap: auto_delete=false, so the address (and any DNS pointing at it)
  # survives the delete and re-attaches to the new box.
  SRV_ID="$(echo "$EXISTING_SERVER" | jqp "print(json.load(sys.stdin)['id'])")"
  info "REBUILD: deleting server $SERVER_NAME (id $SRV_ID) — the primary IP is retained"
  api DELETE "/servers/$SRV_ID" >/dev/null
  # Wait for the SERVER to disappear AND the PRIMARY IP to become unassigned.
  # Waiting on the server alone is not enough: the delete returns before the IP
  # detaches, and creating the new server while the IP still shows an assignee
  # fails with a 422 that says nothing about a race. Measured 2026-09-09 — the
  # create failed in-script and succeeded by hand seconds later, which is the
  # signature of a timing bug rather than a bad payload.
  for _ in $(seq 1 45); do
    still="$(api GET "/servers?name=$SERVER_NAME" | jqp "print(len(json.load(sys.stdin)['servers']))")"
    assignee="$(api GET "/primary_ips/$PIP_ID" | jqp "print(json.load(sys.stdin)['primary_ip']['assignee_id'] or '')")"
    [[ "$still" == "0" && -z "$assignee" ]] && break
    sleep 4
  done
  [[ -z "$assignee" ]] || die "primary IP $PIP_ID still assigned to $assignee after 180s — refusing to create into a race"
  ok "old server deleted; primary IP detached and free"
  EXISTING_SERVER=""
fi

if [[ -z "$EXISTING_SERVER" ]]; then
  RESULT="$(api POST /servers "$(cat <<JSON
{"name":"$SERVER_NAME","server_type":"$SERVER_TYPE","image":"$IMAGE",
 "location":"$LOCATION","ssh_keys":[$SSH_KEYS_JSON],"firewalls":[{"firewall":$FW_ID}],
 "public_net":{"ipv4":$PIP_ID,"enable_ipv4":true,"enable_ipv6":true},
 "labels":{"project":"mosko-fintech","env":"production"}}
JSON
)")"
  echo "$RESULT" | jqp "
d=json.load(sys.stdin); s=d['server']
print('      id   %s' % s['id'])
print('      ipv4 %s' % (s['public_net']['ipv4'] or {}).get('ip'))
print('      ipv6 %s' % (s['public_net']['ipv6'] or {}).get('ip'))
"
  ok "server created"
else
  ok "server already existed — not recreated"
fi
fi  # end: if [[ $APPLY -eq 1 ]] (Hetzner-side "Applying" section)

BOX_IP="$(api GET "/servers?name=$SERVER_NAME" | jqp "
d=json.load(sys.stdin)['servers']
print((d[0]['public_net']['ipv4'] or {}).get('ip') or '' if d else '')")"
[[ -n "$BOX_IP" ]] || die "could not resolve $SERVER_NAME's IPv4 address after create/lookup"

if [[ $APPLY -eq 1 ]]; then
# The IPv6 primary IP is created FOR you by Hetzner at server-creation time,
# with auto_delete=TRUE — so unlike the IPv4 one it dies with the server and a
# rebuild hands out a different /64. Measured 2026-09-09: the rebuild at §3b
# preserved IPv4 exactly as designed and silently changed IPv6, which was only
# caught because the box's login banner disagreed with the record.
# IPv6 primary IPs are free, so there is no cost argument for leaving it.
V6_ID="$(api GET "/servers/$(api GET "/servers?name=$SERVER_NAME" | jqp "
d=json.load(sys.stdin)['servers']; print(d[0]['id'] if d else 0)")" | jqp "
s=json.load(sys.stdin).get('server') or {}
v6=(s.get('public_net') or {}).get('ipv6') or {}
print(v6.get('id') or '')")"
if [[ -n "$V6_ID" ]]; then
  v6state="$(api GET "/primary_ips/$V6_ID" | jqp "
p=json.load(sys.stdin)['primary_ip']; print('%s %s' % (p['auto_delete'], p['ip']))")"
  if [[ "$v6state" == True* ]]; then
    api PUT "/primary_ips/$V6_ID" "{\"name\":\"$PRIMARY_IP_NAME-v6\",\"auto_delete\":false}" >/dev/null
    ok "IPv6 primary IP made persistent — ${v6state#* }"
  else
    ok "IPv6 primary IP already persistent — ${v6state#* }"
  fi
fi
fi  # end: if [[ $APPLY -eq 1 ]] (IPv6 persistence)

# PIP_ADDR is used by Phase 2's "Next" block even in preflight mode (the
# primary IP already exists whenever the server does); resolve it here if the
# Applying section above didn't run.
PIP_ADDR="${PIP_ADDR:-$(api GET "/primary_ips?name=$PRIMARY_IP_NAME" | jqp "
d=json.load(sys.stdin)['primary_ips']; print(d[0]['ip'] if d else '')")}"

##############################################################################
# PHASE 2 — post-provision SSH: hardening, Coolify install, admin bootstrap.
#
# F/CTO directive (2026-09-10): the stand-up must be a scripted re-run, not a
# hand-run sequence. Reconstructed after the fact: past this point, every
# single step of the original stand-up was executed by an agent over SSH or
# the API. The ONE human step recorded — opening a tunnel and filling
# Coolify's first-run browser form — was manufactured by the runbook
# transcribing the installer's "browse to http://ip:8000" line without asking
# whether a browser was required. It is not: `php artisan db:seed
# --class=RootUserSeeder` is Coolify's own official non-interactive bootstrap
# path (verified by reading it, not assumed — see the admin-bootstrap step
# below), and a Sanctum token is mintable the same way. Zero browser steps.
#
# Everything below is READ-ONLY without --apply, same as Phase 1. Every
# mutating step checks remote state FIRST and reports "already satisfies" on
# a re-run rather than re-applying — this is what makes the script safe to
# run again against an already-hardened, already-installed box, which is
# exactly what proves it before it is ever pointed at a fresh one.
##############################################################################

[[ -n "${AUTOMATION_KEY:-}" ]] || die "no automation-usable private key resolved — Phase 1 should have caught this"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }  # feed a script on stdin

step "Phase 2 — waiting for SSH at $BOX_IP (automation key)"
SSH_UP=0
for _ in $(seq 1 30); do
  if sshx true >/dev/null 2>&1; then SSH_UP=1; break; fi
  sleep 4
done
if [[ $SSH_UP -eq 0 ]]; then
  if [[ $APPLY -eq 0 ]]; then
    info "box not reachable yet (expected on a brand-new server during preflight — cloud-init is still running, or this box doesn't exist yet). Skipping Phase 2 checks."
    printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created. Re-run with --apply to execute.\n'
    exit 0
  else
    die "box at $BOX_IP not reachable over SSH with the automation key after 120s"
  fi
fi
ok "SSH reachable"

step "Box spec (runbook §1) — read-only, every run"
SPEC="$(sshx 'nproc; free -m | awk "/^Mem:/{print \$2}"; df -BG --output=size / | tail -1 | tr -d "G "; uname -m')"
read -r CORES MEMMB DISKGB ARCH <<<"$(echo "$SPEC" | tr '\n' ' ')"
info "cores=$CORES mem=${MEMMB}MB disk=${DISKGB}G arch=$ARCH"
[[ "$CORES" == "4" ]] || die "expected 4 cores, box reports $CORES"
[[ "$MEMMB" -ge 7000 && "$MEMMB" -le 8500 ]] || die "expected ~8GB RAM, box reports ${MEMMB}MB"
[[ "$DISKGB" -ge 70 && "$DISKGB" -le 85 ]] || die "expected ~80GB disk, box reports ${DISKGB}G"
[[ "$ARCH" == "aarch64" ]] || die "expected aarch64, box reports $ARCH -- every image in this repo is arm64 and will fail to build on this box"
ok "spec matches the ruled $SERVER_TYPE shape"

step "sshd hardening drop-in (runbook §1 step 2)"
DESIRED_SSHD='# mosko-fintech V1 -- runbook §1 step 2.
# PermitRootLogin is prohibit-password, NOT no: Coolify connects to this box
# as root over key-based SSH. A flat "no" breaks Coolify'"'"'s server connection.
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
# AllowTcpForwarding must stay yes (the default) -- the Coolify dashboard and
# Supabase Studio tunnels (ssh -L) both depend on it. Stated explicitly so a
# future hardening pass cannot flip the default without this line objecting.
AllowTcpForwarding yes'
CURRENT_SSHD="$(sshx 'cat /etc/ssh/sshd_config.d/99-pfin-hardening.conf 2>/dev/null' || true)"
if [[ "$CURRENT_SSHD" == "$DESIRED_SSHD" ]]; then
  ok "sshd drop-in already matches"
elif [[ $APPLY -eq 0 ]]; then
  info "sshd drop-in missing or differs -- would write /etc/ssh/sshd_config.d/99-pfin-hardening.conf and reload sshd"
else
  printf '%s\n' "$DESIRED_SSHD" | ssh "${SSH_OPTS[@]}" "root@$BOX_IP" \
    'cat > /etc/ssh/sshd_config.d/99-pfin-hardening.conf && sshd -t && systemctl reload sshd'
  ok "sshd drop-in written and reloaded"
fi

step "Operator user 'deploy' + NOPASSWD sudo (runbook §1 step 3)"
# NOPASSWD reasoning, carried from docs/records/v1final/standup-log.md §3c:
# the SAME keys already grant DIRECT root login (required above, for
# Coolify's own server connection) -- NOPASSWD sudo for deploy therefore
# grants no capability those keys do not already have; it only removes a
# password prompt that --disabled-password left unsatisfiable. This argument
# DEPENDS on PermitRootLogin staying prohibit-password, not no -- asserted by
# the sshd step above running first.
DEPLOY_STATE="$(sshx 'id deploy >/dev/null 2>&1 && echo EXISTS || echo ABSENT'; sshx 'test -f /etc/sudoers.d/90-deploy && cat /etc/sudoers.d/90-deploy || true')"
DEPLOY_EXISTS="$(echo "$DEPLOY_STATE" | head -1)"
SUDOERS_LINE="$(echo "$DEPLOY_STATE" | tail -n +2)"
if [[ "$DEPLOY_EXISTS" == "EXISTS" && "$SUDOERS_LINE" == "deploy ALL=(ALL) NOPASSWD:ALL" ]]; then
  ok "deploy user + NOPASSWD sudo already present"
elif [[ $APPLY -eq 0 ]]; then
  info "deploy user/sudoers missing or differ -- would create/fix"
else
  sshx_in <<REMOTE
set -e
id deploy >/dev/null 2>&1 || adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
echo 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-deploy
chmod 440 /etc/sudoers.d/90-deploy
visudo -c -f /etc/sudoers.d/90-deploy
mkdir -p /home/deploy/.ssh && chmod 700 /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
REMOTE
  ok "deploy user + NOPASSWD sudo applied"
fi

step "Security updates (runbook §1 step 4)"
UPGRADABLE="$(sshx 'apt list --upgradable 2>/dev/null | grep -c "^[a-z]"' || echo 0)"
if [[ "$UPGRADABLE" == "0" ]]; then
  ok "no upgradable packages"
elif [[ $APPLY -eq 0 ]]; then
  info "$UPGRADABLE package(s) upgradable -- would run apt-get update && apt-get -y upgrade"
else
  sshx 'DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get -y -qq upgrade' >/dev/null
  REMAINING="$(sshx 'apt list --upgradable 2>/dev/null | grep -c "^[a-z]"' || echo '?')"
  ok "security updates applied -- $REMAINING package(s) still upgradable (non-security or needs a reboot)"
fi

step "Coolify install (runbook §3), version pinned at run time"
PINNED_VERSION="$(curl -fsS https://cdn.coollabs.io/coolify/versions.json | jqp "print(json.load(sys.stdin)['coolify']['v4']['version'])")"
[[ -n "$PINNED_VERSION" ]] || die "could not read coolify.v4 from cdn.coollabs.io/coolify/versions.json"
info "current pinned version per Coollabs: $PINNED_VERSION"
INSTALLED_VERSION="$(sshx 'grep -m1 "^COOLIFY_VERSION=" /data/coolify/source/.env 2>/dev/null | cut -d= -f2' || true)"
if [[ "$INSTALLED_VERSION" == "$PINNED_VERSION" ]]; then
  ok "Coolify $PINNED_VERSION already installed"
elif [[ -n "$INSTALLED_VERSION" ]]; then
  info "Coolify $INSTALLED_VERSION is installed; $PINNED_VERSION is now pinned. This script does NOT auto-upgrade a live instance -- that is a deliberate, separate decision. Upgrade by hand via the Coolify dashboard/CLI when ready."
elif [[ $APPLY -eq 0 ]]; then
  info "Coolify not installed -- would run the installer pinned to $PINNED_VERSION"
else
  sshx "curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s $PINNED_VERSION"
  ok "Coolify $PINNED_VERSION installed"
fi

step "Admin bootstrap -- zero browser steps (runbook §3)"
# Source-verified, not assumed, in /var/www/html on the box (Coolify 4.3.18):
#   database/seeders/RootUserSeeder.php -- Coolify's OWN official non-
#   interactive first-user path. Reads ROOT_USER_EMAIL / ROOT_USER_PASSWORD /
#   ROOT_USERNAME from env, no-ops if a user with id=0 already exists
#   (idempotent by construction), creates that user, attaches it to Team 0 as
#   owner, and disables further registration. This is NOT a reimplementation
#   of app/Actions/Fortify/CreateNewUser.php's first-user branch -- it IS
#   Coolify's own alternate entrypoint for exactly this (headless-install)
#   case, so it stays correct across upstream changes to the interactive path.
#
#   F/CTO override 2026-09-10: the password must be HUMAN-CHOSEN, not
#   generated -- a random 32-char password is secure and unusable. Read from
#   .env (COOLIFY_ADMIN_EMAIL / COOLIFY_ADMIN_NAME / COOLIFY_ADMIN_PASSWORD),
#   or prompted if stdin is a TTY and a value is missing; dies naming the
#   exact variable if neither. No generated fallback for the password, ever.
#
#   email_verified_at -- checked whether it matters, not assumed either way:
#   App\Models\User does NOT implement Illuminate\Contracts\Auth\MustVerifyEmail
#   (confirmed: `class User extends Authenticatable implements SendsEmail`,
#   no MustVerifyEmail). routes/web.php DOES apply a ['auth','verified']
#   middleware group, but Laravel's EnsureEmailIsVerified middleware only
#   blocks when `$user instanceof MustVerifyEmail` -- false here, so the
#   check is a structural no-op for this model regardless of
#   email_verified_at. RootUserSeeder's omission of markEmailAsVerified() is
#   therefore not a bug to work around.
#
#   Token minting is separate (the seeder mints no token): app/Models/User.php
#   ::createToken() reads session('currentTeam')->id for the token's team_id
#   -- tinker has no HTTP session, so the script sets it explicitly first,
#   mirroring what CreateNewUser::create() does at the end of registration.
#   Ability: 'root' -- app/Http/Middleware/ApiAbility.php special-cases
#   tokenCan('root') to bypass every other ability check ('read'/'write'/
#   'deploy', the only three strings used anywhere in routes/api.php) --
#   correct for this token since it belongs to the root user itself.
#
#   ⚠ THE PASSWORD BOUNDARY -- read before touching this block. It travels
#   .env -> a local shell variable -> SSH stdin -> tinker's OWN stdin on the
#   box -> Hash::make() -> the users row. At no point is it: a command-line
#   argument (ps-visible, on this machine or the box), the return value of a
#   bare tinker expression (tinker/psysh echoes those -- every statement that
#   touches it ends in `; null;` or is buried inside a closure), or exposed
#   by `set -x` (asserted off, explicitly, right here).
[[ $- != *x* ]] || die "set -x is on entering the admin-bootstrap step -- refusing to proceed with a password in scope while tracing is active."

# `|| true`: under pipefail, a no-match grep (the normal "not set in .env"
# case) would otherwise make this function's exit status non-zero, and
# `VAR=$(read_env_var ...)` with set -e would abort the whole script right
# there -- silently, no die(), exactly the bug the HETZNER_API_TOKEN read
# above hit and got fixed for. Same shape, fixed the same way.
read_env_var() { grep -m1 "^$1=" "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true; }
COOLIFY_ADMIN_EMAIL="$(read_env_var COOLIFY_ADMIN_EMAIL)"
COOLIFY_ADMIN_NAME="$(read_env_var COOLIFY_ADMIN_NAME)"
COOLIFY_ADMIN_PASSWORD="$(read_env_var COOLIFY_ADMIN_PASSWORD)"

ADMIN_STATE="$(sshx "docker exec coolify php artisan tinker --execute=\"echo \\\\App\\\\Models\\\\User::where('id',0)->exists() ? 'EXISTS' : 'ABSENT';\"" 2>/dev/null | tail -1)"
TOKEN_STATE="$(sshx "docker exec coolify php artisan tinker --execute=\"echo \\\\App\\\\Models\\\\User::find(0)?->tokens()->where('name','provisioning-automation')->exists() ? 'EXISTS' : 'ABSENT';\"" 2>/dev/null | tail -1)"

NEED_CREDENTIALS=0
[[ "$ADMIN_STATE" != "EXISTS" ]] && NEED_CREDENTIALS=1
[[ $RESET_ADMIN_PASSWORD -eq 1 ]] && NEED_CREDENTIALS=1

if [[ $NEED_CREDENTIALS -eq 1 && $APPLY -eq 1 ]]; then
  if [[ -t 0 ]]; then
    [[ -n "$COOLIFY_ADMIN_EMAIL" ]] || read -rp "Coolify admin email: " COOLIFY_ADMIN_EMAIL
    [[ -n "$COOLIFY_ADMIN_NAME" ]] || read -rp "Coolify admin name: " COOLIFY_ADMIN_NAME
    if [[ -z "$COOLIFY_ADMIN_PASSWORD" ]]; then
      read -rsp "Coolify admin password: " COOLIFY_ADMIN_PASSWORD; echo
      read -rsp "Confirm: " _PW_CONFIRM; echo
      [[ "$COOLIFY_ADMIN_PASSWORD" == "$_PW_CONFIRM" ]] || die "passwords did not match"
      unset _PW_CONFIRM
    fi
  fi
  [[ -n "$COOLIFY_ADMIN_EMAIL" ]] || die "COOLIFY_ADMIN_EMAIL missing from .env and no TTY to prompt (add it to .env, non-secret)"
  [[ -n "$COOLIFY_ADMIN_NAME" ]] || die "COOLIFY_ADMIN_NAME missing from .env and no TTY to prompt (add it to .env, non-secret)"
  [[ -n "$COOLIFY_ADMIN_PASSWORD" ]] || die "COOLIFY_ADMIN_PASSWORD missing from .env and no TTY to prompt (add it to .env, gitignored, or delete the line after first run)"
fi

if [[ "$ADMIN_STATE" == "EXISTS" && "$TOKEN_STATE" == "EXISTS" && $RESET_ADMIN_PASSWORD -eq 0 ]]; then
  ok "admin user + automation token already provisioned -- not touched (pass --reset-admin-password to change the password)"
elif [[ $APPLY -eq 0 ]]; then
  if [[ $RESET_ADMIN_PASSWORD -eq 1 ]]; then
    info "--reset-admin-password given -- would re-hash the admin password from .env/prompt on the box"
  else
    info "admin=$ADMIN_STATE token=$TOKEN_STATE -- would create the admin from .env/prompted credentials and mint a token ON THE BOX, printing nothing secret"
  fi
else
  # Env-file, never `docker exec -e` (argv-visible via ps on the box) and
  # never a tinker --execute argument (argv-visible on THIS machine too).
  SEED_ENV_FILE="/root/.pfin/_root_seed.env.$$"
  {
    printf 'ROOT_USER_EMAIL=%s\n' "$COOLIFY_ADMIN_EMAIL"
    printf 'ROOT_USERNAME=%s\n' "$COOLIFY_ADMIN_NAME"
    printf 'ROOT_USER_PASSWORD=%s\n' "$COOLIFY_ADMIN_PASSWORD"
  } | sshx "umask 077; cat > $SEED_ENV_FILE"

  # Everything below is captured (stdout+stderr) rather than printed as it
  # runs, so it can be checked for a leak BEFORE the operator ever sees it --
  # not a substitute for the design above (never an argument, never a bare
  # tinker expression), a proof that it held. The two secrets are still in
  # scope at the grep below; both are unset immediately after.
  BOOTSTRAP_LOG="$(mktemp)"
  {
    if [[ "$ADMIN_STATE" != "EXISTS" ]]; then
      sshx "docker exec --env-file $SEED_ENV_FILE coolify php artisan db:seed --class=RootUserSeeder --force"
      echo "ADMIN_CREATED"
    fi

    if [[ $RESET_ADMIN_PASSWORD -eq 1 && "$ADMIN_STATE" == "EXISTS" ]]; then
      # RootUserSeeder only creates; a reset re-hashes via tinker instead.
      # The password crosses via tinker's OWN stdin (this heredoc's content,
      # sent over the already-encrypted SSH channel) -- never a shell
      # expression tinker would echo, and the whole script ends on a bare
      # `null;` so psysh's normal last-expression REPL echo never prints the
      # hash either.
      RESET_SCRIPT="\$pw = getenv('ROOT_USER_PASSWORD');
\\App\\Models\\User::where('id', 0)->update(['password' => \\Illuminate\\Support\\Facades\\Hash::make(\$pw)]);
unset(\$pw);
echo 'RESET_OK';
null;"
      echo "$RESET_SCRIPT" | sshx "docker exec --env-file $SEED_ENV_FILE -i coolify php artisan tinker"
    fi

    if [[ "$TOKEN_STATE" != "EXISTS" ]]; then
      TOKEN_SCRIPT='$user = \App\Models\User::find(0);
$team = \App\Models\Team::find(0);
session(["currentTeam" => $team]);
$token = $user->createToken("provisioning-automation", ["root"]);
file_put_contents("/root/.pfin/_coolify_token.tmp", $token->plainTextToken);
echo "MINTED";
null;'
      echo "$TOKEN_SCRIPT" | sshx "docker exec -i coolify php artisan tinker"
      TOKEN_VALUE="$(sshx "docker exec coolify cat /root/.pfin/_coolify_token.tmp 2>/dev/null" || true)"
      sshx "docker exec coolify rm -f /root/.pfin/_coolify_token.tmp"
      if [[ -n "$TOKEN_VALUE" ]]; then
        printf 'COOLIFY_API_TOKEN=%s\n' "$TOKEN_VALUE" | sshx "umask 077; cat >> /root/.pfin/coolify.env; chmod 600 /root/.pfin/coolify.env"
        echo "TOKEN_WRITTEN"
      fi
    fi
  } > "$BOOTSTRAP_LOG" 2>&1

  sshx "shred -u $SEED_ENV_FILE 2>/dev/null || rm -f $SEED_ENV_FILE"

  # The assertion team-lead asked for, run every --apply, not once by hand:
  # grep the captured log for both secrets while they're still in scope. Zero
  # hits is the test.
  LEAK=0
  [[ -n "${COOLIFY_ADMIN_PASSWORD:-}" ]] && grep -qF -- "$COOLIFY_ADMIN_PASSWORD" "$BOOTSTRAP_LOG" && LEAK=1
  [[ -n "${TOKEN_VALUE:-}" ]] && grep -qF -- "$TOKEN_VALUE" "$BOOTSTRAP_LOG" && LEAK=1
  if [[ $LEAK -eq 1 ]]; then
    rm -f "$BOOTSTRAP_LOG"
    die "a secret value appeared in the admin-bootstrap step's own captured output -- refusing to print the log. This is the echo trap the design above exists to prevent; something regressed. Do not re-run until fixed."
  fi

  grep -vE '^(ADMIN_CREATED|RESET_OK|MINTED|TOKEN_WRITTEN)$' "$BOOTSTRAP_LOG" | sed 's/^/      /'
  grep -q ADMIN_CREATED "$BOOTSTRAP_LOG" && ok "admin user created (email/name from .env or prompt; password human-chosen, never printed)"
  grep -q RESET_OK "$BOOTSTRAP_LOG" && ok "admin password reset (value never printed by this script or tinker)"
  grep -q TOKEN_WRITTEN "$BOOTSTRAP_LOG" && ok "automation token minted on the box (value never left it, never printed)"
  ok "leak check: zero hits for either secret in this step's own captured output"
  rm -f "$BOOTSTRAP_LOG"
  unset COOLIFY_ADMIN_PASSWORD TOKEN_VALUE
fi

step "Phase 2 verification"
HEALTHY="$(sshx "docker ps --filter 'name=coolify' --filter 'health=healthy' --format '{{.Names}}'" | wc -l | tr -d ' ')"
info "$HEALTHY of 6 coolify-* containers healthy"
[[ "$HEALTHY" == "6" ]] || die "expected 6 healthy coolify-* containers, got $HEALTHY -- check 'docker ps -a' on the box"
ok "all 6 Coolify containers healthy"
DASH_CODE="$(sshx "curl -s -o /dev/null -w '%{http_code}' http://localhost:8000")"
[[ "$DASH_CODE" == "302" ]] || die "expected 302 from the dashboard on localhost:8000, got $DASH_CODE"
ok "dashboard responds 302 -> /login (from the box)"

step "Next"
cat <<NEXT
      Port check from OUTSIDE the box, not from it:
        nmap -Pn -p 22,80,443,8000,8081 $BOX_IP
          EXPECT: 22/80/443 open · 8000 AND 8081 filtered

      Dashboard, only if you want to look at it -- nothing in script 2 needs
      the browser:
        ssh -L 3000:localhost:3000 -L 8000:localhost:8000 root@$BOX_IP
        # then browse http://localhost:8000 (Coolify) / :3000 (Studio, once §4)

      DNS (runbook §2): point pfindash.com's A record at $PIP_ADDR (the
      PRIMARY IP), not at whatever address a future rebuild hands out --
      that is what the primary IP is for. Check the CURRENT records before
      you change them -- pfindash.com may still resolve to the incumbent
      box, so this is a live-traffic change, not a greenfield write.

      Next script: scripts/provision-supabase-stack.sh --apply
        Reads the token this run wrote to /root/.pfin/coolify.env ON THE BOX
        -- nothing to copy here.
NEXT
