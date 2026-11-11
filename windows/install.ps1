# Installe GlassPermission pour Windows et l'ajoute aux hooks de Claude Code.
#   install.ps1             -> installe + branche le hook
#   install.ps1 -Uninstall  -> retire le hook et les fichiers
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$dest = Join-Path $HOME '.claude\glass-permission'
$settings = Join-Path $HOME '.claude\settings.json'
$target = Join-Path $dest 'GlassPermission.ps1'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cmd = 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' + ($target -replace '\\', '/') + '"'

function Update-Settings([bool]$add) {
    New-Item -ItemType Directory -Force (Split-Path $settings) | Out-Null
    $data = $null
    if ((Test-Path $settings) -and (Get-Item $settings).Length -gt 0) {
        Copy-Item $settings "$settings.bak" -Force
        $data = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    if (-not $data) { $data = [pscustomobject]@{} }
    if (-not $data.PSObject.Properties['hooks']) {
        $data | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }

    # Garde les autres hooks, retire les anciennes entrées de GlassPermission
    $groups = @()
    if ($data.hooks.PSObject.Properties['PermissionRequest']) {
        $groups = @($data.hooks.PermissionRequest | Where-Object {
            -not (@($_.hooks) | Where-Object { "$($_.command)" -like '*GlassPermission.ps1*' })
        })
    }
    if ($add) {
        $groups += [pscustomobject]@{
            matcher = '*'
            hooks   = @([pscustomobject]@{ type = 'command'; command = $cmd; timeout = 120 })
        }
    }

    $data.hooks.PSObject.Properties.Remove('PermissionRequest')
    if ($groups.Count -gt 0) {
        $data.hooks | Add-Member -NotePropertyName PermissionRequest -NotePropertyValue $groups
    }
    if (@($data.hooks.PSObject.Properties).Count -eq 0) { $data.PSObject.Properties.Remove('hooks') }

    $json = ConvertTo-Json -InputObject $data -Depth 32
    [IO.File]::WriteAllText($settings, $json, (New-Object System.Text.UTF8Encoding $false))
}

if ($Uninstall) {
    Update-Settings $false
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Write-Host "✅ GlassPermission désinstallé (sauvegarde : $settings.bak)"
    exit 0
}

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $here 'GlassPermission.ps1') $target -Force

Write-Host "🪝 Ajout du hook PermissionRequest dans $settings"
Update-Settings $true

Write-Host "✅ Installé. Redémarre Claude Code, puis teste avec demo.cmd"
