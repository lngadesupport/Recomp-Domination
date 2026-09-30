# Shared by the launcher and CI. Missing sources are an error, never a download.
function Get-OfflineCmakeArgs {
    param([Parameter(Mandatory=$true)][string]$SourceRoot)
    $result = @('-DFETCHCONTENT_FULLY_DISCONNECTED=ON', '-DFETCHCONTENT_UPDATES_DISCONNECTED=ON')
    foreach ($name in @('elfio','toml11','fmt','libdwarf','rabbitizer','nlohmann_json','raylib')) {
        $path = Join-Path $SourceRoot ('deps/' + $name)
        if (!(Test-Path -LiteralPath $path -PathType Container)) { throw "Dependência offline ausente: $name. Extraia o pacote completo." }
        $result += ('-DFETCHCONTENT_SOURCE_DIR_' + $name.ToUpperInvariant() + '=' + (Resolve-Path -LiteralPath $path).Path.Replace('\','/'))
    }
    return $result
}
