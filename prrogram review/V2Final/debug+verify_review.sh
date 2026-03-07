#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json
import subprocess
from pathlib import Path
from datetime import datetime, timezone

root = Path('.').resolve()
results = []

def run(cmd, cwd=None):
    p = subprocess.run(cmd, shell=True, cwd=cwd, text=True, capture_output=True)
    return {
        'cmd': cmd,
        'cwd': str(Path(cwd).resolve()) if cwd else str(root),
        'exit_code': p.returncode,
        'stdout_tail': p.stdout.strip()[-1200:],
        'stderr_tail': p.stderr.strip()[-1200:],
    }

def add(check_id, severity, assertion, confirmed, evidence=None):
    results.append({
        'id': check_id,
        'severity': severity,
        'assertion': assertion,
        'status': 'pass' if confirmed else 'fail',
        'confirmed': bool(confirmed),
        'evidence': evidence or {},
    })

launcher = root / 'Managed_Stack_Data' / 'Axiom-Launcher.ps1'
install_nexus = root / 'Managed_Stack_Data' / 'INSTALL-NEXUS.ps1'
launcher_text = launcher.read_text(encoding='utf-8', errors='ignore') if launcher.exists() else ''
add('AXN-001','critical','Launcher references INSTALL-NEXUS.ps1 while target file is missing', '.\\INSTALL-NEXUS.ps1' in launcher_text and not install_nexus.exists(), {
    'launcher_file': str(launcher.relative_to(root)) if launcher.exists() else 'missing',
    'missing_path': str(install_nexus.relative_to(root)),
    'target_exists': install_nexus.exists(),
})

gui = root / 'Managed_Stack_Data' / 'INSTALL-GUI.ps1'
eng = root / 'Managed_Stack_Data' / 'INSTALL-AXIOM-ENGINE.ps1'
tgz = root / 'Managed_Stack_Data' / 'n8n-nodes-local-ai-manager-0.1.0.tgz'
gui_ref = 'n8n-nodes-local-ai-manager-0.1.0.tgz' in gui.read_text(encoding='utf-8', errors='ignore') if gui.exists() else False
eng_ref = 'n8n-nodes-local-ai-manager-0.1.0.tgz' in eng.read_text(encoding='utf-8', errors='ignore') if eng.exists() else False
add('AXN-002','medium','Installer flow depends on a local .tgz package name/path', gui_ref or eng_ref, {
    'references_present': bool(gui_ref or eng_ref),
    'artifact_path': str(tgz.relative_to(root)),
    'artifact_exists_now': tgz.exists(),
})

pkg = root / 'n8n-nodes-local-ai-manager' / 'package.json'
pkg_text = pkg.read_text(encoding='utf-8', errors='ignore') if pkg.exists() else ''
uses_ps = 'powershell -Command' in pkg_text
build_win = run('npm run build', cwd=root / 'n8n-nodes-local-ai-manager') if (root / 'n8n-nodes-local-ai-manager').exists() else {'exit_code': 999}
add('AXN-003','high','Custom node build script is PowerShell-specific (portability risk)', uses_ps, {
    'build_script_contains_powershell': uses_ps,
    'windows_build_exit': build_win.get('exit_code'),
})

node_file = root / 'n8n-nodes-local-ai-manager' / 'src' / 'nodes' / 'LocalAiManager' / 'LocalAiManager.node.ts'
node_text = node_file.read_text(encoding='utf-8', errors='ignore') if node_file.exists() else ''
add('AXN-004','medium',"Remote baseUrl default is 'http://' placeholder", "default: 'http://'" in node_text, {'node_file': str(node_file.relative_to(root)) if node_file.exists() else 'missing'})

nstart = root / 'Managed_Stack_Data' / 'Nexus-Start.ps1'
nst = nstart.read_text(encoding='utf-8', errors='ignore') if nstart.exists() else ''
add('AXN-005','medium','N8N settings permission enforcement disabled at startup', 'N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "false"' in nst, {'startup_file': str(nstart.relative_to(root)) if nstart.exists() else 'missing'})

app = root / 'Managed_Stack_Data' / 'Axiom-Hub' / 'src' / 'App.jsx'
app_text = app.read_text(encoding='utf-8', errors='ignore') if app.exists() else ''
add('AXN-006','low','Axiom Hub UI still scaffold/default', ('Vite + React' in app_text) or ('count is {count}' in app_text), {'ui_file': str(app.relative_to(root)) if app.exists() else 'missing'})

lint = run('npm run lint', cwd=root / 'Managed_Stack_Data' / 'Axiom-Hub') if (root / 'Managed_Stack_Data' / 'Axiom-Hub').exists() else {'exit_code': 999}
add('HEALTH-AXH-LINT','info','Axiom-Hub lint passes', lint.get('exit_code') == 0, {'exit_code': lint.get('exit_code')})

build = run('npm run build', cwd=root / 'Managed_Stack_Data' / 'Axiom-Hub') if (root / 'Managed_Stack_Data' / 'Axiom-Hub').exists() else {'exit_code': 999}
add('HEALTH-AXH-BUILD','info','Axiom-Hub build passes', build.get('exit_code') == 0, {'exit_code': build.get('exit_code')})

node_build = run('npm run build', cwd=root / 'n8n-nodes-local-ai-manager') if (root / 'n8n-nodes-local-ai-manager').exists() else {'exit_code': 999}
add('HEALTH-NODE-BUILD-WIN','info','Custom node build passes on current Windows host', node_build.get('exit_code') == 0, {'exit_code': node_build.get('exit_code')})

critical_confirmed = [r['id'] for r in results if r['severity'] == 'critical' and r['confirmed']]
high_confirmed = [r['id'] for r in results if r['severity'] == 'high' and r['confirmed']]

release = {
    'windows_local_preview': 'go_after_AXN-001_fix' if 'AXN-001' in critical_confirmed else 'go',
    'portable_release': 'blocked' if (critical_confirmed or high_confirmed) else 'go',
    'primary_blockers': critical_confirmed + high_confirmed,
}

out = {
    'generated_by': 'debug+verify_review.sh',
    'generated_at_utc': datetime.now(timezone.utc).isoformat(),
    'verification_mode': 'fact_confirmation_with_health_checks',
    'release_assessment': release,
    'summary': {
        'total_checks': len(results),
        'passed': sum(1 for r in results if r['status'] == 'pass'),
        'failed': sum(1 for r in results if r['status'] == 'fail'),
    },
    'results': results,
}

out_path = root / 'debug+review_verification.json'
out_path.write_text(json.dumps(out, indent=2), encoding='utf-8')
print(json.dumps(out['summary'], indent=2))
print(json.dumps(release, indent=2))
PY
