param(
    [Parameter(Mandatory=$true)][string]$ExporterPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExporterPath = (Resolve-Path -LiteralPath $ExporterPath).Path
$text = Get-Content -Raw -LiteralPath $ExporterPath

$interactive = @'
        File tomlFile = askFile("Choose output TOML config file", "Save");
        if (tomlFile == null) {
            return;
        }

        File csvFile = askFile("Choose output CSV file", "Save");
        if (csvFile == null) {
            return;
        }
'@

$headless = @'
        String[] scriptArgs = getScriptArgs();
        File tomlFile;
        File csvFile;

        if (scriptArgs != null && scriptArgs.length >= 2) {
            tomlFile = new File(scriptArgs[0]);
            csvFile = new File(scriptArgs[1]);
        } else {
            tomlFile = askFile("Choose output TOML config file", "Save");
            if (tomlFile == null) {
                return;
            }

            csvFile = askFile("Choose output CSV file", "Save");
            if (csvFile == null) {
                return;
            }
        }
'@

if (!$text.Contains($headless)) {
    if (!$text.Contains($interactive)) {
        throw 'Exporter prompt block does not match the pinned PS2Recomp source. Refusing to patch blindly.'
    }
    $text = $text.Replace($interactive,$headless)
    [IO.File]::WriteAllText($ExporterPath,$text,(New-Object Text.UTF8Encoding($false)))
}

$verify = Get-Content -Raw -LiteralPath $ExporterPath
if ($verify -notmatch 'getScriptArgs\(\)' -or
    $verify -notmatch 'scriptArgs\.length >= 2' -or
    $verify -notmatch 'new File\(scriptArgs\[0\]\)' -or
    $verify -notmatch 'new File\(scriptArgs\[1\]\)') {
    throw 'Headless exporter patch verification failed.'
}

Write-Host 'Patched ExportPS2Functions.java for deterministic headless output paths.' -ForegroundColor Green
