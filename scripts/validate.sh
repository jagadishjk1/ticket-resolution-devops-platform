#!/usr/bin/env bash
# Offline static checks that need no cloud account and no Docker daemon.
# Optional tools (terraform, shellcheck, yamllint, hadolint) are used when installed.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=1; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; }

echo "== YAML syntax"
if python3 -c 'import yaml' 2>/dev/null; then
  while IFS= read -r f; do
    if python3 -c 'import sys,yaml; list(yaml.safe_load_all(open(sys.argv[1])))' "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
  done < <(find . -path ./app -prune -o \( -name '*.yml' -o -name '*.yaml' \) -type f -print | grep -v node_modules)
else skip "python3 + PyYAML not available"; fi

echo "== JSON syntax"
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r f; do
    if jq -e . "$f" >/dev/null 2>&1; then ok "$f"; else bad "$f"; fi
  done < <(find observability -name '*.json' -type f)
else skip "jq not installed"; fi

echo "== Shell syntax"
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
done < <(find scripts docker -name '*.sh' -type f)
# Rendered bootstrap templates (substitute the two Terraform variables)
for t in terraform/templates/*.tftpl; do
  if sed -e 's/\${region}/eu-west-1/g' -e 's#\${ssm_prefix}#/p/e/swarm#g' "$t" | bash -n 2>/dev/null; then ok "$t (rendered)"; else bad "$t (rendered)"; fi
done

echo "== Stack file references"
python3 - <<'PY' || fail=1
import os, sys, yaml
d = yaml.safe_load(open("docker-stack.yml"))
errs = 0
for name, cfg in d.get("configs", {}).items():
    if not os.path.isfile(cfg["file"]):
        print(f"  \033[31mFAIL\033[0m config {name}: missing file {cfg['file']}"); errs += 1
used = {c["source"] if isinstance(c, dict) else c for s in d["services"].values() for c in s.get("configs", [])}
for u in used - set(d["configs"]):
    print(f"  \033[31mFAIL\033[0m service uses undefined config {u}"); errs += 1
for u in set(d["configs"]) - used:
    print(f"  \033[33mWARN\033[0m  config {u} is defined but unused")
secrets_used = {s for sv in d["services"].values() for s in sv.get("secrets", [])}
for u in secrets_used - set(d.get("secrets", {})):
    print(f"  \033[31mFAIL\033[0m service uses undefined secret {u}"); errs += 1
nets = set(d.get("networks", {}))
for n, s in d["services"].items():
    for net in s.get("networks", []):
        if net not in nets:
            print(f"  \033[31mFAIL\033[0m {n}: undefined network {net}"); errs += 1
if not errs:
    print(f"  \033[32mOK\033[0m   {len(d['services'])} services, {len(d['configs'])} configs, all references resolve")
sys.exit(1 if errs else 0)
PY

echo "== Prometheus <-> stack consistency"
python3 - <<'PY' || fail=1
import re, sys, yaml
stack = yaml.safe_load(open("docker-stack.yml"))["services"]
prom = yaml.safe_load(open("observability/prometheus/prometheus.yml"))
errs = 0
for job in prom["scrape_configs"]:
    for dns in job.get("dns_sd_configs", []):
        for n in dns["names"]:
            svc = n.replace("tasks.", "")
            if svc not in stack:
                print(f"  \033[31mFAIL\033[0m job {job['job_name']}: unknown service {svc}"); errs += 1
    for rl in job.get("relabel_configs", []):
        rep = rl.get("replacement", "")
        m = re.match(r"^([a-z-]+):\d+$", rep)
        if rl.get("target_label") == "__address__" and m and m.group(1) not in stack:
            print(f"  \033[31mFAIL\033[0m job {job['job_name']}: unknown exporter {m.group(1)}"); errs += 1
if not errs: print("  \033[32mOK\033[0m   all scrape targets map to services in the stack")
sys.exit(1 if errs else 0)
PY

echo "== Terraform"
if command -v terraform >/dev/null 2>&1; then
  ( cd terraform && terraform fmt -check -recursive >/dev/null && ok "terraform fmt" || bad "terraform fmt (run: terraform fmt -recursive)" )
  ( cd terraform && terraform init -backend=false -input=false >/dev/null 2>&1 \
      && terraform validate >/dev/null 2>&1 && ok "terraform validate" || bad "terraform validate" )
else skip "terraform not installed"; fi

echo "== Optional linters"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x scripts/*.sh docker/entrypoint.sh && ok "shellcheck" || bad "shellcheck (see output above)"
else skip "shellcheck not installed"; fi
if command -v yamllint >/dev/null 2>&1; then
  yamllint -c .yamllint . && ok "yamllint" || bad "yamllint (see output above)"
else skip "yamllint not installed"; fi
if command -v hadolint >/dev/null 2>&1; then
  hadolint docker/Dockerfile && ok "hadolint" || bad "hadolint (see output above)"
else skip "hadolint not installed"; fi

echo
[ "$fail" -eq 0 ] && echo "Validation passed." || { echo "Validation FAILED."; exit 1; }
