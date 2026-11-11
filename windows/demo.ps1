# Affiche la notification avec une fausse demande, sans passer par Claude Code.
$script = Join-Path $HOME '.claude\glass-permission\GlassPermission.ps1'
if (-not (Test-Path $script)) { $script = Join-Path $PSScriptRoot 'GlassPermission.ps1' }

$json = @{
    hook_event_name = 'PermissionRequest'
    cwd             = (Get-Location).Path
    tool_name       = 'Bash'
    tool_input      = @{
        command     = 'npm install && npm run build'
        description = 'Installer les dépendances puis compiler le projet'
    }
} | ConvertTo-Json -Compress

$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$env:GLASS_TIMEOUT = 30
$answer = $json | powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $script

if ($answer) { Write-Host "Réponse envoyée à Claude : $answer" }
else { Write-Host "Pas de réponse : Claude poserait la question dans le terminal." }
