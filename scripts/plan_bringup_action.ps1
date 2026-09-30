param(
    [Parameter(Mandatory=$true)][string]$Triage,
    [switch]$FfmpegEnabled,
    [string]$Out = ''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$Triage=(Resolve-Path -LiteralPath $Triage).Path
if(!$Out){$Out=Join-Path (Split-Path $Triage -Parent) 'bringup_action.json'}
$data=Get-Content -Raw -LiteralPath $Triage | ConvertFrom-Json
$primary=[string]$data.primary_classification

$action='stop'
$reason='manual-investigation-required'
$automatic=$false

switch($primary){
    'missing-function' {
        $action='entry-points'
        $reason='bounded-entry-point-growth'
        $automatic=$true
    }
    'mpeg-no-ffmpeg' {
        if(!$FfmpegEnabled){
            $action='enable-ffmpeg'
            $reason='runtime-mpeg-needs-decoder'
            $automatic=$true
        } else {
            $reason='mpeg-blocker-persists-with-ffmpeg'
        }
    }
    default {
        $reason='triage-'+$primary+'-requires-targeted-fix'
    }
}

$result=[pscustomobject][ordered]@{
    generated=(Get-Date -Format o)
    triage=$Triage
    primary_classification=$primary
    ffmpeg_enabled=[bool]$FfmpegEnabled
    action=$action
    automatic=$automatic
    reason=$reason
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),($result|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
Write-Host ('Bring-up action: primary={0} action={1} reason={2}' -f $primary,$action,$reason)
if($automatic){exit 0}
exit 3
