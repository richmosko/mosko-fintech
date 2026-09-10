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
SSH_KEY_NAME="${SSH_KEY_NAME:-mosko-fintech-operator}"
SSH_PUBKEY_PATH="${SSH_PUBKEY_PATH:-$HOME/.ssh/id_ed25519.pub}"
FIREWALL_NAME="${FIREWALL_NAME:-pfin-prod-fw}"
# A Primary IP is created SEPARATELY from the server and outlives it
# (auto_delete=false). That is the whole point: DNS for pfindash.com points at
# this address once, and a box rebuild re-attaches the same IP instead of
# forcing a DNS change and a propagation wait. Costs EUR 0.60/mo gross, and it
# keeps billing while unassigned -- that is what you are buying.
PRIMARY_IP_NAME="${PRIMARY_IP_NAME:-pfin-prod-ipv4}"
# Source-restrict the Coolify dashboard (:8000). Empty = open to the world,
# which the runbook calls acceptable-but-weaker. Set to your own IP/32.
ADMIN_CIDR="${ADMIN_CIDR:-}"

API="https://api.hetzner.cloud/v1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

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
  ok "existing server matches this file; nothing to create"
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

[[ -f "$SSH_PUBKEY_PATH" ]] || die "no public key at $SSH_PUBKEY_PATH (set SSH_PUBKEY_PATH=)"
PUBKEY="$(tr -d '\r\n' < "$SSH_PUBKEY_PATH")"
FPR="$(ssh-keygen -lf "$SSH_PUBKEY_PATH" | awk '{print $2}')"
ok "operator key $SSH_PUBKEY_PATH — $FPR"

step "Plan"
cat <<PLAN
      server    $SERVER_NAME  ($SERVER_TYPE, $IMAGE, $LOCATION)
      ssh key   $SSH_KEY_NAME  <- $SSH_PUBKEY_PATH
      firewall  $FIREWALL_NAME  in: 22, 80, 443, 8000${ADMIN_CIDR:+ (8000 restricted to $ADMIN_CIDR)}
                                :8081 deliberately NOT opened (runbook §1 / §7 CA-4)
      primary   $PRIMARY_IP_NAME  (ipv4, auto_delete=false — survives a rebuild)
PLAN
[[ -z "$ADMIN_CIDR" ]] && info "NOTE: ADMIN_CIDR unset — :8000 will be open to the world. Weaker; runbook §1 allows it."

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created. Re-run with --apply to execute.\n'
  exit 0
fi

step "Applying"

SSH_KEY_ID="$(api GET "/ssh_keys?name=$SSH_KEY_NAME" | jqp "
d=json.load(sys.stdin)['ssh_keys']; print(d[0]['id'] if d else '')")"
if [[ -z "$SSH_KEY_ID" ]]; then
  SSH_KEY_ID="$(api POST /ssh_keys "$(python3 -c "
import json,sys; print(json.dumps({'name':'$SSH_KEY_NAME','public_key':sys.argv[1]}))" "$PUBKEY")" \
    | jqp "print(json.load(sys.stdin)['ssh_key']['id'])")"
  ok "ssh key uploaded — id $SSH_KEY_ID"
else
  ok "ssh key already present — id $SSH_KEY_ID"
fi

FW_ID="$(api GET "/firewalls?name=$FIREWALL_NAME" | jqp "
d=json.load(sys.stdin)['firewalls']; print(d[0]['id'] if d else '')")"
if [[ -z "$FW_ID" ]]; then
  ADMIN_SRC='["0.0.0.0/0","::/0"]'
  [[ -n "$ADMIN_CIDR" ]] && ADMIN_SRC="[\"$ADMIN_CIDR\"]"
  FW_ID="$(api POST /firewalls "$(cat <<JSON
{"name":"$FIREWALL_NAME","rules":[
 {"direction":"in","protocol":"tcp","port":"22","source_ips":["0.0.0.0/0","::/0"],"description":"operator SSH + Coolify server connection"},
 {"direction":"in","protocol":"tcp","port":"80","source_ips":["0.0.0.0/0","::/0"],"description":"ACME HTTP-01 + HTTP->HTTPS redirect"},
 {"direction":"in","protocol":"tcp","port":"443","source_ips":["0.0.0.0/0","::/0"],"description":"HTTPS to Coolify-fronted services"},
 {"direction":"in","protocol":"tcp","port":"8000","source_ips":$ADMIN_SRC,"description":"Coolify dashboard"}
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
  # Resolve the datacenter from the location — the suffix is NOT uniform
  # (fsn1-dc14, hel1-dc2, nbg1-dc3), so it must be looked up, never built
  # by string concatenation. A wrong datacenter here creates the IP somewhere
  # the server cannot use it.
  DC_NAME="$(api GET /datacenters | jqp "
d=json.load(sys.stdin)['datacenters']
m=[x['name'] for x in d if x['location']['name']=='$LOCATION']
assert m, 'no datacenter found for location $LOCATION'
print(m[0])
")"
  info "datacenter for $LOCATION resolved as $DC_NAME"
  PIP_JSON="$(api POST /primary_ips "$(cat <<JSON
{"name":"$PRIMARY_IP_NAME","type":"ipv4","datacenter":"$DC_NAME",
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

if [[ -z "$EXISTING_SERVER" ]]; then
  RESULT="$(api POST /servers "$(cat <<JSON
{"name":"$SERVER_NAME","server_type":"$SERVER_TYPE","image":"$IMAGE",
 "location":"$LOCATION","ssh_keys":[$SSH_KEY_ID],"firewalls":[{"firewall":$FW_ID}],
 "public_net":{"enable_ipv4":$PIP_ID,"enable_ipv6":true},
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
          EXPECT: 22/80/443 open · 8081 filtered
          8081 open is the CA-4 regression; fix before installing anything.

      Then complete §1's hardening (password auth off, non-root operator user)
      and record the box's IP, key fingerprint and Coolify version in
      docs/records/v1final/standup-log.md before moving to §3.

      DNS (runbook §2): point pfindash.com's A record at the PRIMARY IP above,
      not at whatever address a future rebuild hands out. That is what the
      primary IP is for. Check the CURRENT records before you change them --
      pfindash.com may still resolve to the incumbent box, so this is a
      live-traffic change, not a greenfield write.
NEXT
