# Parse PowerShell without executing it. Strings and here-strings remain data.
$ErrorActionPreference = 'Stop'
$event = [Console]::In.ReadToEnd() | ConvertFrom-Json
$command = $event.tool_input.command
if (-not $command) { exit 0 }
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$errors)
if ($errors.Count) {
  # A Windows Codex session can explicitly run Bash syntax too.
  $event | ConvertTo-Json -Depth 30 -Compress | bash (Join-Path $PSScriptRoot 'bash-guard.sh')
  exit $LASTEXITCODE
}

# The verdict is a key of rules.json, the rule text the Bash guards and the session context share.
function Test-Command($name, $arguments) {
  $name = (($name -replace '\\', '/') -replace '^.*/', '' -replace '\.exe$', '').ToLowerInvariant()
  $i = 0
  if ($name -in @('pkill', 'killall')) { return 'kill' }
  if ($name -eq 'taskkill' -and @($arguments | Where-Object { $_ -match '^[/-]im$' }).Count) { return 'kill' }
  if ($name -in @('stop-process', 'spps', 'kill')) {
    foreach ($a in $arguments) {
      $p = ($a -replace ':.*$', '').ToLowerInvariant()
      # a prefix of -Name or -ProcessName, as PowerShell accepts it (-P alone is ambiguous with -PassThru)
      if (($p.Length -ge 2 -and '-name'.StartsWith($p)) -or ($p.Length -ge 3 -and '-processname'.StartsWith($p))) { return 'kill' }
    }
  }
  if ($name -eq 'git') {
    while ($i -lt $arguments.Count) {
      $a = $arguments[$i]
      if ($a -cmatch '^(-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--attr-source)$') { $i += 2; continue }
      if ($a.StartsWith('-')) { $i++; continue }
      break
    }
    if ($i -ge $arguments.Count) { return }
    $sub = $arguments[$i++]
    for (; $i -lt $arguments.Count; $i++) {
      $a = $arguments[$i]
      if ($sub -eq 'add' -and ($a -cin @('-A', '--all', '--no-ignore-removal', '.', './', ':/') -or $a -cmatch '^-[a-zA-Z]*A')) { return 'add' }
      if ($sub -ne 'commit') { continue }
      if ($a -eq '--') { break }
      if ($a -in @('--message', '--file', '--reuse-message', '--reedit-message', '--fixup', '--squash', '--author', '--date', '--cleanup', '--trailer', '--pathspec-from-file')) { $i++; continue }
      if ($a -eq '--all') { return 'commit' }
      if ($a -cmatch '^-[A-Za-z]') {
        for ($k = 1; $k -lt $a.Length; $k++) {
          $ch = $a[$k]
          if ($ch -ceq 'a') { return 'commit' }
          if ($ch -cmatch '[mCcFt]') { if ($k -eq $a.Length - 1) { $i++ }; break }
          if ($ch -cmatch '[Su]') { break }
        }
      }
    }
  }
  if ($name -eq 'chezmoi') {
    $sub = ''; $force = $false; $target = $false
    for (; $i -lt $arguments.Count; $i++) {
      $a = $arguments[$i]
      if ($a -in @('-n', '--dry-run') -or $a -cmatch '^-[A-Za-z]*n[A-Za-z]*$') { return }
      if ($a -eq '--force') { $force = $true }
      elseif ($a -cmatch '^(-[xicDoSW]|--(exclude|include|cache|color|config|config-format|destination|mode|output|override-data|override-data-file|persistent-state|progress|source|working-tree|age-recipient|age-recipient-file|use-builtin-age|use-builtin-git))$') { $i++ }
      elseif ($a.StartsWith('-')) { continue }
      elseif (-not $sub) { $sub = $a }
      else { $target = $true }
    }
    if ($sub -eq 'apply' -and $force -and -not $target) { return 'chezmoi' }
  }
}

$commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
foreach ($entry in $commands) {
  $name = $entry.GetCommandName()
  if (-not $name) { continue }
  $arguments = @($entry.CommandElements | Select-Object -Skip 1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value }
    else { $_.Extent.Text }
  })
  $verdict = Test-Command $name $arguments
  if ($verdict) {
    $rule = (Get-Content -Raw -Encoding utf8 (Join-Path $PSScriptRoot 'rules.json') | ConvertFrom-Json).$verdict
    $reason = @($rule.do, $rule.how, $rule.why | Where-Object { $_ }) -join ' '
    @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } } | ConvertTo-Json -Depth 4 -Compress
    exit 0
  }
}
