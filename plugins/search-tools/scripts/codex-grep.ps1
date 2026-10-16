# Parse PowerShell; do not treat strings, comments or here-strings as commands.
$ErrorActionPreference = 'Stop'
$event = [Console]::In.ReadToEnd() | ConvertFrom-Json
if ($env:SEARCH_TOOLS_ALLOW_GREP -eq '1') { exit 0 }
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($event.tool_input.command, [ref]$tokens, [ref]$errors)
$edits = @()
foreach ($entry in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
  $name = ($entry.GetCommandName() -replace '\\', '/') -replace '^.*/', '' -replace '\.exe$', ''
  if ($name -eq 'xargs' -and $entry.Extent.Text -match '\bgrep\b') {
    $why = 'Use rg -n <pattern> [path] instead of xargs grep.'; break
  }
  if ($name -ne 'grep') { continue }
  $arguments = @($entry.CommandElements | Select-Object -Skip 1)
  if (-not ($arguments | Where-Object { $_.Extent.Text -cmatch '^(-[A-Za-z]*[rR]|--recursive|--dereference-recursive)' })) { continue }
  # Only literal invocations can be safely rewritten by the Bash BRE/ERE mapper.
  if ($errors.Count -or ($arguments | Where-Object { $_ -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -and ($_ -isnot [System.Management.Automation.Language.CommandParameterAst] -or $_.Argument) })) {
    $why = 'Recursive grep contains PowerShell expressions; use rg explicitly.'; break
  }
  $words = @('grep') + @($arguments | ForEach-Object {
    $value = if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value } else { $_.Extent.Text }
    if ($value -match '^[-A-Za-z0-9_./]+$') { $value } else { "'" + $value.Replace("'", "'\''") + "'" }
  })
  $probe = @{cwd=$event.cwd; tool_input=@{command=($words -join ' ')}} | ConvertTo-Json -Depth 8 -Compress
  $guard = (Join-Path $PSScriptRoot 'grep-guard.sh') -replace '\\', '/'
  $mapped = $probe | & $env:SEARCH_TOOLS_BASH $guard
  if ($LASTEXITCODE -ne 0) { throw 'grep routing failed' }
  if (-not $mapped) { continue }
  $result = $mapped | ConvertFrom-Json
  if ($result.hookSpecificOutput.permissionDecision -eq 'deny') { $why=$result.hookSpecificOutput.permissionDecisionReason; break }
  $replacement = $result.hookSpecificOutput.updatedInput.command
  # Our literal tokens use Bash single-quote encoding. Translate only that exact encoding.
  $replacement = $replacement.Replace("'\''", "''")
  $edits += @{start=$entry.Extent.StartOffset; length=$entry.Extent.EndOffset-$entry.Extent.StartOffset; text=$replacement}
}
if ($why) {
  @{hookSpecificOutput=@{hookEventName='PreToolUse'; permissionDecision='deny'; permissionDecisionReason=$why}} | ConvertTo-Json -Depth 5 -Compress
} elseif ($edits.Count) {
  $command = $event.tool_input.command
  foreach ($edit in ($edits | Sort-Object start -Descending)) { $command=$command.Remove($edit.start,$edit.length).Insert($edit.start,$edit.text) }
  $event.tool_input.command = $command
  @{hookSpecificOutput=@{hookEventName='PreToolUse'; permissionDecision='allow'; updatedInput=$event.tool_input; additionalContext='search-tools rewrote literal recursive grep to rg; use -uu for ignored and hidden files.'}} | ConvertTo-Json -Depth 20 -Compress
}
