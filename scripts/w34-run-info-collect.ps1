# W34 run-info single-shot collector.
# Outputs one JSON blob. ASCII-only by design: Chinese string literals get
# truncated by GBK decoding over SSH (TerminatorExpectedAtEndOfString).
# Secrets are never emitted: keys matching the redact pattern report only names.
param([Parameter(Mandatory=$true)][string]$Project)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$UNIFIED_ROOT = 'D:\00-v5-latest-code'
$root         = Join-Path $UNIFIED_ROOT $Project
$REDACT       = 'PASSWORD|SECRET|TOKEN|WEBHOOK|KEY|CREDENTIAL|PASS'

$o = [ordered]@{
  project        = $Project
  unified_root   = $UNIFIED_ROOT
  code_path      = $root
  collected_at   = (Get-Date).ToString('s')
  hostname       = $env:COMPUTERNAME
  in_unified_root = (Test-Path -LiteralPath $root)
}

# ---- machine ----
$os = Get-CimInstance Win32_OperatingSystem
$o.mem_free_gb  = [math]::Round($os.FreePhysicalMemory/1MB,1)
$o.mem_total_gb = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
$d = Get-PSDrive D
if ($d) { $o.disk_free_gb = [math]::Round($d.Free/1GB,1) }

if (-not $o.in_unified_root) {
  $o.verdict = 'NOT_IN_UNIFIED_ROOT'
  $o | ConvertTo-Json -Depth 6
  exit 0
}

# ---- git ----
$g = [ordered]@{}
$gitDir = Join-Path $root '.git'
$g.is_git = (Test-Path -LiteralPath $gitDir)
if ($g.is_git) {
  & git -C $root fetch origin --quiet 2>$null
  $g.branch   = (& git -C $root rev-parse --abbrev-ref HEAD 2>$null)
  $g.upstream = (& git -C $root rev-parse --abbrev-ref '@{u}' 2>$null)
  $g.remote   = (& git -C $root remote get-url origin 2>$null)
  $line = (& git -C $root log -1 --format='%h|%an <%ae>|%ad|%s' --date=iso 2>$null)
  if ($line) {
    $p = $line -split '\|', 4
    $g.head_sha = $p[0]; $g.author = $p[1]; $g.commit_date = $p[2]; $g.subject = $p[3]
  }
  if ($g.upstream) {
    $cnt = (& git -C $root rev-list --left-right --count "$($g.upstream)...HEAD" 2>$null)
    if ($cnt) { $c = $cnt -split '\s+'; $g.behind = [int]$c[0]; $g.ahead = [int]$c[1] }
    $t = (& git -C $root log -1 --format='%h|%ad|%s' --date=short $g.upstream 2>$null)
    if ($t) { $g.upstream_tip = $t }
    $g.behind_files = @(& git -C $root diff --name-only HEAD $g.upstream 2>$null)
  }
  $g.dirty = @(& git -C $root status --porcelain 2>$null)
  $g.dirty_count = $g.dirty.Count
}
$o.git = $g

# ---- runtime: venv may be nested (fio keeps them under repos\*, runtime\*) ----
$r = [ordered]@{}
$venvs = @()
$cand = @(Join-Path $root '.venv\Scripts\python.exe')
foreach ($sub in @('repos','runtime','projects')) {
  $subdir = Join-Path $root $sub
  if (Test-Path -LiteralPath $subdir) {
    Get-ChildItem -LiteralPath $subdir -Directory -Force -ErrorAction SilentlyContinue |
      ForEach-Object { $cand += (Join-Path $_.FullName '.venv\Scripts\python.exe') }
  }
}
foreach ($p in $cand) {
  if (Test-Path -LiteralPath $p) {
    $venvs += [ordered]@{ rel=$p.Substring($root.Length+1); python=((& $p -V 2>&1 | Out-String).Trim()) }
  }
}
$r.venvs = @($venvs)
$r.venv_count = $venvs.Count
$r.venv_exists = ($venvs.Count -gt 0)
$r.has_uv_lock = (Test-Path -LiteralPath (Join-Path $root 'uv.lock'))
$uv = Get-Command uv -ErrorAction SilentlyContinue
$r.uv_on_path = [bool]$uv
if ($uv) { $r.uv_path = $uv.Source }
$o.runtime = $r

# ---- config files (names + mtime + size; no values) ----
# NOTE: Sort-Object -Unique treats ordered dictionaries as all-equal and
# collapses them to one item. Dedup via Group-Object instead.
$cfgFiles = @()
$cfgDirs = @($root, (Join-Path $root 'config'), (Join-Path $root 'config\private'))
foreach ($dir in $cfgDirs) {
  if (-not (Test-Path -LiteralPath $dir)) { continue }
  Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $dir -ne $root -or $_.Name -match '(^\.env|\.env$|\.env\.|\.ini$|\.toml$)' } |
    ForEach-Object { $cfgFiles += [ordered]@{ rel=$_.FullName.Substring($root.Length+1); mtime=$_.LastWriteTime.ToString('s'); size=$_.Length } }
}
$o.config_files = @($cfgFiles | Group-Object { $_.rel } | ForEach-Object { $_.Group[0] })

# ---- env keys: names always; values only when key is not sensitive ----
$envEntries = @()
foreach ($f in @($o.config_files | Where-Object { $_.rel -match '\.env' })) {
  $full = Join-Path $root $f.rel
  foreach ($ln in (Get-Content -LiteralPath $full -ErrorAction SilentlyContinue)) {
    if ($ln -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
      $k = $Matches[1]; $v = $Matches[2].Trim()
      if ($k -match $REDACT) { $v = '<redacted>' }
      $envEntries += [ordered]@{ file=$f.rel; key=$k; value=$v }
    }
  }
}
$o.env_entries = $envEntries

# ---- scheduled tasks referencing this project ----
$tasks = @()
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue)) {
  $acts = ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; '
  if ($acts -match [regex]::Escape($Project) -or $t.TaskName -match [regex]::Escape($Project)) {
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
    $trig = ($t.Triggers | ForEach-Object { $_.StartBoundary }) -join ' , '
    $tasks += [ordered]@{
      name=$t.TaskName; path=$t.TaskPath; state="$($t.State)"; action=$acts; triggers=$trig
      last_run="$($info.LastRunTime)"; last_result="$($info.LastTaskResult)"; next_run="$($info.NextRunTime)"
    }
  }
}
$o.scheduled_tasks = @($tasks)
$o.scheduled_task_count = $tasks.Count

# ---- logs / state / receipts (newest first, capped) ----
foreach ($pair in @(@('logs','logs'), @('state','state'), @('data','data'), @('receipts','receipts'), @('artifacts','artifacts'))) {
  $dir = Join-Path $root $pair[1]
  if (Test-Path -LiteralPath $dir) {
    $items = @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 5 |
      ForEach-Object { [ordered]@{ name=$_.Name; mtime=$_.LastWriteTime.ToString('s'); size=$_.Length } })
    $o["dir_$($pair[0])"] = $items
  }
}

# ---- entry point candidates ----
$o.entry_candidates = @(Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^(run_|main\.py$|.*\.bat$|.*\.ps1$)' } |
  Select-Object -First 12 -ExpandProperty Name)

$o.verdict = 'OK'
$o | ConvertTo-Json -Depth 6
