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

function Test-Command($name, $arguments) {
  $name = ($name -replace '\\', '/') -replace '^.*/', '' -replace '\.exe$', ''
  $i = 0
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
      if ($sub -eq 'add' -and ($a -cin @('-A', '--all', '--no-ignore-removal', '.', './', ':/') -or $a -cmatch '^-[a-zA-Z]*A')) { return 'Stage explicit paths with git add <path>...; whole-tree staging also includes other work.' }
      if ($sub -ne 'commit') { continue }
      if ($a -eq '--') { break }
      if ($a -in @('--message', '--file', '--reuse-message', '--reedit-message', '--fixup', '--squash', '--author', '--date', '--cleanup', '--trailer', '--pathspec-from-file')) { $i++; continue }
      if ($a -eq '--all') { return 'Stage explicit paths, then git commit without -a.' }
      if ($a -cmatch '^-[A-Za-z]') {
        for ($k = 1; $k -lt $a.Length; $k++) {
          $ch = $a[$k]
          if ($ch -ceq 'a') { return 'Stage explicit paths, then git commit without -a.' }
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
    if ($sub -eq 'apply' -and $force -and -not $target) { return 'Review chezmoi diff <target>, then chezmoi apply --force <target> for each drifted file.' }
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
  $reason = Test-Command $name $arguments
  if ($reason) {
    @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } } | ConvertTo-Json -Depth 4 -Compress
    exit 0
  }
}
