#!/usr/bin/env bash
#
# provision-vps.sh — provision the V1 production VPS on Hetzner Cloud,
# DevOps-owned, executing `docs/deployment-runbook.md` §1 through the API
# instead of the web console (F/CTO chose scripted provisioning 2026-09-09).
#
# WHY THIS EXISTS
#   §1 is written to be executed by a human in the Hetzner console. Doing it
#   by hand once produces a box nobody can reproduce: the region, image,
#   firewall rules and key fingerprint live only in whatever the operator
#   clicked. This script makes the box a function of the file, so a rebuild
#   after a loss is a re-run rather than an archaeology exercise.
#
# WHAT IT REFUSES TO DO
#   It never prints the API token, never writes it anywhere, and never
#   creates anything unless invoked with --apply. The default is a preflight
#   that only reads.
#
# IDEMPOTENCE
#   Every create is preceded by a lookup on the resource's NAME. Re-running
#   after a partial failure adopts what already exists rather than making a
#   second copy. The one thing it will NOT do is mutate a resource that
#   exists but disagrees with this file — it stops and shows the difference,
#   because silently reconciling a live production box is how you delete
#   something you meant to keep.
#
# USAGE
#   scripts/provision-vps.sh              # preflight: read-only, prints the plan
#   scripts/provision-vps.sh --apply      # create what the preflight described
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
APPLY=0; REBUILD=0
for arg in "$@"; do
  case "$arg" in
    --apply)   APPLY=1 ;;
    --rebuild) REBUILD=1 ;;
    *) echo "unknown flag: $arg" >&2
       echo "usage: $0 [--apply] [--rebuild]" >&2; exit 2 ;;
  esac
done

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ---- Token: read from .env, never echoed, never exported to children ------
[[ -f "$REPO_ROOT/.env" ]] || die "no .env at $REPO_ROOT — HETZNER_API_KEY is read from there"
TOKEN="$(grep -m1 '^HETZNER_API_KEY=' "$REPO_ROOT/.env" | cut -d= -f2- | tr -d '"'"'"' \r\n')"
[[ -n "$TOKEN" ]] || die "HETZNER_API_KEY missing or empty in .env"
[[ ${#TOKEN} -eq 64 ]] || die "HETZNER_API_KEY is ${#TOKEN} chars; Hetzner tokens are 64 — wrong value or a stray quote"

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

api GET /servers >/dev/null || die "token rejected by Hetzner (401/403). Check HETZNER_API_KEY has Read & Write."
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

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created. Re-run with --apply to execute.\n'
  exit 0
fi

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

step "Next — runbook §1 verification block"
cat <<'NEXT'
      Run these from your machine, NOT from the box:

        ssh root@<ip> 'nproc; free -h; df -h /; uname -m; lsb_release -ds'
          EXPECT: 4 | ~8Gi | ~80G | aarch64 | Ubuntu 24.04.x LTS
          x86_64 here means the wrong line was ordered — every image in this
          repo is arm64 and will fail to build. Stop and rebuild.

        nmap -Pn -p 22,80,443,8000,8081 <ip>
          EXPECT: 22/80/443 open · 8000 AND 8081 filtered
          8081 open is the CA-4 regression; fix before installing anything.
          8000 open means the firewall did not apply -- the dashboard is
          meant to be unreachable from the internet entirely.

      Coolify dashboard (§3) — over the tunnel, never a public port:

        ssh -L 8000:localhost:8000 root@<ip>
        # leave that open, then browse http://localhost:8000

      Then complete §1's hardening (password auth off, non-root operator user)
      and record the box's IP, key fingerprint and Coolify version in
      docs/records/v1final/standup-log.md before moving to §3.

      DNS (runbook §2): point pfindash.com's A record at the PRIMARY IP above,
      not at whatever address a future rebuild hands out. That is what the
      primary IP is for. Check the CURRENT records before you change them --
      pfindash.com may still resolve to the incumbent box, so this is a
      live-traffic change, not a greenfield write.
NEXT
