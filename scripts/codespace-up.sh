#!/usr/bin/env bash
# One-shot: create (or reuse) a codespace for this repo, make ports 8000 and 11434
# public, and print the playground URL.
#
# Token: classic PAT with `codespace` scope (repo scope alone returns 403):
#   https://github.com/settings/tokens/new?scopes=codespace&description=any-model-playground
#
#   GH_TOKEN=ghp_xxx bash scripts/codespace-up.sh
#   GH_TOKEN=ghp_xxx MACHINE=standardLinux32gb bash scripts/codespace-up.sh
set -uo pipefail

REPO="bittubuilds/any-model-playground"
REPO_ID="1441638900"
MACHINE="${MACHINE:-basicLinux32gb}"   # basicLinux32gb = 2c/8GB | standardLinux32gb = 4c/16GB
NAME="${NAME:-any-model}"

if [ -z "${GH_TOKEN:-}" ]; then
  echo "GH_TOKEN missing. Banao: https://github.com/settings/tokens/new?scopes=codespace&description=any-model-playground"
  exit 1
fi

api() { curl -s -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }
jget() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }

echo "==> token check"
who=$(api https://api.github.com/user | jget "d.get('login') or 'ERROR: ' + str(d.get('message'))")
echo "    user: $who"
case "$who" in ERROR*) echo "    token galat hai ya expire ho gaya"; exit 1;; esac

echo "==> existing codespace dhoond raha hoon"
CS=$(api "https://api.github.com/user/codespaces?per_page=100" | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
if 'message' in d:
    print('__ERR__' + d['message']); raise SystemExit
for c in d.get('codespaces',[]):
    if (c.get('repository') or {}).get('full_name') == '$REPO':
        print(c['name']); break
")

case "$CS" in
  __ERR__*)
    echo "    list failed: ${CS#__ERR__}"
    echo "    -> token me 'codespace' scope add karo"
    exit 1;;
esac

if [ -n "$CS" ]; then
  echo "    reuse: $CS"
else
  echo "==> create ($MACHINE)"
  CS=$(api -X POST https://api.github.com/user/codespaces -d "{
    \"repository_id\": $REPO_ID,
    \"machine\": \"$MACHINE\",
    \"ref\": \"main\",
    \"devcontainer_path\": \".devcontainer/devcontainer.json\",
    \"display_name\": \"$NAME\",
    \"idle_timeout_minutes\": 30,
    \"retention_period_minutes\": 10080
  }" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('name') or ('__ERR__' + str(d.get('message'))))
")
  case "$CS" in
    __ERR__*) echo "    create failed: ${CS#__ERR__}"; exit 1;;
  esac
  echo "    created: $CS"
fi

echo "==> provisioning (model pull pehli baar me 3-5 min leta hai)"
for _ in $(seq 1 90); do
  state=$(api "https://api.github.com/user/codespaces/$CS" | jget "d.get('state','')")
  echo "    state: $state"
  case "$state" in
    Available) break;;
    Failed|Unavailable) echo "    codespace $state"; exit 1;;
  esac
  sleep 10
done

echo "==> ports public kar raha hoon (service start hone tak retry)"
for _ in $(seq 1 20); do
  ok=1
  for port in 8000 11434; do
    code=$(api -o /dev/null -w "%{http_code}" -X PATCH \
      "https://api.github.com/user/codespaces/$CS/ports/$port" -d '{"visibility":"public"}')
    [ "$code" = "200" ] || ok=0
  done
  [ "$ok" = "1" ] && break
  sleep 15
done

echo "==> ports"
api "https://api.github.com/user/codespaces/$CS/ports" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ports={p['port']:p for p in d.get('ports',[])}
for n in (8000,11434):
    p=ports.get(n)
    print('   ', n, p['visibility'] if p else 'not forwarded yet', (p or {}).get('url',''))
base=None
if 8000 in ports and ports[8000].get('url'):
    base=ports[8000]['url'].rsplit('-',1)
import re
if 8000 in ports:
    u=ports[8000].get('url','')
    m=re.match(r'(https://.+)-8000\.(.+)$', u)
    if m: print('\nPLAYGROUND:', u)
"

echo
echo "Playground kholo (Ports -> 8000 ya upar ka URL). Ollama URL khud detect ho jayega."
echo "Stop karna ho to: curl -X POST -H \"Authorization: Bearer \$GH_TOKEN\" https://api.github.com/user/codespaces/$CS/stop"
