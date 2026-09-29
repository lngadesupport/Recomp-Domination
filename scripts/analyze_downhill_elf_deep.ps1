param(
    [string]$Elf = "",
    [string]$Out = "",
    [string]$FunctionCsv = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(!$Elf){
    $parent = Split-Path $RepoRoot -Parent
    if(Test-Path -LiteralPath (Join-Path $parent 'SCUS_971.77')){$Elf=Join-Path $parent 'SCUS_971.77'}
    else{$Elf='D:\Recomp Domination\SCUS_971.77'}
}
$Elf=(Resolve-Path -LiteralPath $Elf).Path
if(!$Out){$Out=Join-Path $RepoRoot 'analysis\local\SCUS_971.77.deep.json'}
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent)|Out-Null

[byte[]]$b=[IO.File]::ReadAllBytes($Elf)
function U16([int]$o){[BitConverter]::ToUInt16($b,$o)}
function U32([int]$o){[BitConverter]::ToUInt32($b,$o)}
function Hex32Text([uint32]$v){'0x{0:X8}' -f $v}

if($b.Length -lt 84){throw 'ELF too small'}
if($b[0]-ne 0x7F-or$b[1]-ne 0x45-or$b[2]-ne 0x4C-or$b[3]-ne 0x46){throw 'Invalid ELF magic'}
$entry=[uint32](U32 24)
$phoff=[uint32](U32 28)
$phentsize=[uint16](U16 42)
$phnum=[uint16](U16 44)

$segments=@()
for($i=0;$i-lt$phnum;$i++){
    $o=[int]($phoff+$i*$phentsize)
    $segments += [pscustomobject]@{
        type=[uint32](U32 ($o+0)); offset=[uint32](U32 ($o+4)); vaddr=[uint32](U32 ($o+8));
        filesz=[uint32](U32 ($o+16)); memsz=[uint32](U32 ($o+20)); flags=[uint32](U32 ($o+24))
    }
}
$exec=@($segments|Where-Object{$_.type-eq 1-and($_.flags-band 1)-ne 0-and$_.filesz-gt 0})
if($exec.Count-eq 0){throw 'No executable PT_LOAD segment'}

$scanMode='pt-load-fallback'
$functionCsvPath=$null
$functionCsvRecords=0
$scanRanges=New-Object System.Collections.Generic.List[object]

if(!$FunctionCsv){
    $candidate=Join-Path $RepoRoot 'analysis\SCUS_971.77.functions.csv'
    if(Test-Path -LiteralPath $candidate){$FunctionCsv=$candidate}
}

if($FunctionCsv -and (Test-Path -LiteralPath $FunctionCsv)){
    $functionCsvPath=(Resolve-Path -LiteralPath $FunctionCsv).Path
    $rawRanges=New-Object System.Collections.Generic.List[object]

    foreach($row in @(Import-Csv -LiteralPath $functionCsvPath)){
        try{
            $startText=[string]$row.Start
            $endText=[string]$row.End
            if([string]::IsNullOrWhiteSpace($startText)-or[string]::IsNullOrWhiteSpace($endText)){continue}

            [uint64]$start=if($startText.StartsWith('0x',[StringComparison]::OrdinalIgnoreCase)){
                [Convert]::ToUInt32($startText.Substring(2),16)
            }else{[uint32]::Parse($startText)}

            [uint64]$end=if($endText.StartsWith('0x',[StringComparison]::OrdinalIgnoreCase)){
                [Convert]::ToUInt32($endText.Substring(2),16)
            }else{[uint32]::Parse($endText)}

            if($end-le$start){continue}
            $rawRanges.Add([pscustomobject]@{start=$start;end=$end})
            $functionCsvRecords++
        }catch{
            Write-Warning ('Ignoring malformed Ghidra CSV row: '+($_|ConvertTo-Json -Compress))
        }
    }

    if($rawRanges.Count-gt 0){
        $merged=New-Object System.Collections.Generic.List[object]
        foreach($range in @($rawRanges|Sort-Object start,end)){
            if($merged.Count-eq 0){
                $merged.Add([pscustomobject]@{start=[uint64]$range.start;end=[uint64]$range.end})
                continue
            }

            $last=$merged[$merged.Count-1]
            if([uint64]$range.start-le[uint64]$last.end){
                if([uint64]$range.end-gt[uint64]$last.end){$last.end=[uint64]$range.end}
            }else{
                $merged.Add([pscustomobject]@{start=[uint64]$range.start;end=[uint64]$range.end})
            }
        }

        foreach($range in $merged){
            foreach($s in $exec){
                [uint64]$segStart=$s.vaddr
                [uint64]$segEnd=[uint64]$s.vaddr+[uint64]$s.filesz
                [uint64]$start=[uint64]$range.start
                [uint64]$end=[uint64]$range.end
                if($segStart-gt$start){$start=$segStart}
                if($segEnd-lt$end){$end=$segEnd}

                # R5900 instructions are 4-byte aligned. Trim Ghidra label/body
                # edges instead of counting partial words.
                $start=$start+[uint64]3
                $start=$start-($start%[uint64]4)
                $end=$end-($end%[uint64]4)

                if($start-lt$end){
                    $scanRanges.Add([pscustomobject]@{start=$start;end=$end;segment=$s})
                }
            }
        }

        if($scanRanges.Count-gt 0){$scanMode='ghidra-functions'}
    }
}

if($scanRanges.Count-eq 0){
    foreach($s in $exec){
        [uint64]$start=$s.vaddr
        [uint64]$end=[uint64]$s.vaddr+[uint64]$s.filesz
        $end=$end-($end%[uint64]4)
        if($start-lt$end){$scanRanges.Add([pscustomobject]@{start=$start;end=$end;segment=$s})}
    }
}

$opNames=@{
  0='SPECIAL';1='REGIMM';2='J';3='JAL';4='BEQ';5='BNE';6='BLEZ';7='BGTZ';
  8='ADDI';9='ADDIU';10='SLTI';11='SLTIU';12='ANDI';13='ORI';14='XORI';15='LUI';
  16='COP0';17='COP1';18='COP2';20='BEQL';21='BNEL';22='BLEZL';23='BGTZL';
  24='DADDI';25='DADDIU';26='LDL';27='LDR';28='MMI';30='LQ';31='SQ';
  32='LB';33='LH';34='LWL';35='LW';36='LBU';37='LHU';38='LWR';39='LWU';
  40='SB';41='SH';42='SWL';43='SW';44='SDL';45='SDR';46='SWR';47='CACHE';
  48='LL';49='LWC1';50='LWC2';52='LLD';53='LDC1';54='LQC2';55='LD';
  56='SC';57='SWC1';58='SWC2';60='SCD';61='SDC1';62='SQC2';63='SD'
}
$specialNames=@{
  0='SLL';2='SRL';3='SRA';4='SLLV';6='SRLV';7='SRAV';8='JR';9='JALR';
  12='SYSCALL';13='BREAK';15='SYNC';16='MFHI';17='MTHI';18='MFLO';19='MTLO';
  24='MULT';25='MULTU';26='DIV';27='DIVU';32='ADD';33='ADDU';34='SUB';35='SUBU';
  36='AND';37='OR';38='XOR';39='NOR';42='SLT';43='SLTU';44='DADD';45='DADDU';46='DSUB';47='DSUBU'
}
$opCounts=@{};$specialCounts=@{};$jal=@{};$jump=@{};$branchCount=0
$cop0=0;$cop1=0;$cop2=0;$mmi=0;$syscalls=0;$breaks=0;$jr=0;$jalr=0;$words=0

foreach($range in $scanRanges){
  $s=$range.segment
  for([uint64]$pc64=[uint64]$range.start;$pc64+4-le[uint64]$range.end;$pc64+=4){
    [uint64]$file64=[uint64]$s.offset+($pc64-[uint64]$s.vaddr)
    if($file64+4-gt[uint64]$b.Length){break}
    $fo=[int]$file64
    [uint32]$w=[BitConverter]::ToUInt32($b,$fo)
    [uint32]$pc=[uint32]$pc64
    $op=[int](($w-shr 26)-band 0x3F)
    $name=if($opNames.ContainsKey($op)){$opNames[$op]}else{('OP_{0:X2}'-f$op)}
    if(!$opCounts.ContainsKey($name)){$opCounts[$name]=0};$opCounts[$name]++;$words++
    if($op-eq 0){
      $fn=[int]($w-band 0x3F)
      $sn=if($specialNames.ContainsKey($fn)){$specialNames[$fn]}else{('SPECIAL_{0:X2}'-f$fn)}
      if(!$specialCounts.ContainsKey($sn)){$specialCounts[$sn]=0};$specialCounts[$sn]++
      if($fn-eq 12){$syscalls++};if($fn-eq 13){$breaks++};if($fn-eq 8){$jr++};if($fn-eq 9){$jalr++}
    }
    if($op-eq 16){$cop0++};if($op-eq 17){$cop1++};if($op-eq 18){$cop2++};if($op-eq 28){$mmi++}
    if($op-eq 3-or$op-eq 2){
      [uint32]$target=[uint32]((($pc+4)-band 0xF0000000)-bor(($w-band 0x03FFFFFF)-shl 2))
      $key=Hex32Text $target
      $dict=if($op-eq 3){$jal}else{$jump}
      if(!$dict.ContainsKey($key)){$dict[$key]=0};$dict[$key]++
    }
    if(($op-ge 4-and$op-le 7)-or($op-ge 20-and$op-le 23)-or$op-eq 1){$branchCount++}
  }
}

function SortedCounts($h){
  @($h.GetEnumerator()|Sort-Object Value -Descending|ForEach-Object{[pscustomobject]@{name=[string]$_.Key;count=[int64]$_.Value}})
}
function TopTargets($h,[int]$n){
  @($h.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First $n|ForEach-Object{[pscustomobject]@{target=[string]$_.Key;calls=[int64]$_.Value}})
}

# Extract printable ASCII strings from file-backed executable/load data, then
# keep SDK/runtime-relevant strings only. Cap output to keep the report small.
$relevant=New-Object System.Collections.Generic.List[string]
$seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$sb=New-Object Text.StringBuilder
function Flush-Ascii {
  if($sb.Length-ge 4){
    $str=$sb.ToString()
    if($str-match '(?i)(sce|sif|iop|vif|vu0|vu1|gif|gs|pad|cdvd|cdrom|host:|mc0:|spu|mpeg|rpc|dma|libc)'){
      if($seen.Add($str)-and$relevant.Count-lt 1200){$relevant.Add($str)}
    }
  }
  [void]$sb.Clear()
}
foreach($s in @($segments|Where-Object{$_.type-eq 1-and$_.filesz-gt 0})){
  $start=[int]$s.offset;$end=[int][Math]::Min([uint64]$b.Length,[uint64]$s.offset+$s.filesz)
  for($i=$start;$i-lt$end;$i++){
    $x=$b[$i]
    if($x-ge 0x20-and$x-le 0x7E){[void]$sb.Append([char]$x)}else{Flush-Ascii}
    if($sb.Length-gt 512){Flush-Ascii}
  }
  Flush-Ascii
}

$known=[ordered]@{}
foreach($addr in @([uint32]0x0010A008,[uint32]0x001FB6C0,[uint32]0x00254050,[uint32]0x0025C440)){
  $found=$false
  foreach($s in $segments){
    if($s.type-ne 1){continue}
    if($addr-ge$s.vaddr-and([uint64]$addr+4)-le([uint64]$s.vaddr+$s.filesz)){
      $fo=[int]([uint64]$s.offset+([uint64]$addr-$s.vaddr))
      $known[(Hex32Text $addr)]=('0x{0:X8}'-f[BitConverter]::ToUInt32($b,$fo));$found=$true;break
    }
  }
  if(!$found){$known[(Hex32Text $addr)]=$null}
}

$report=[ordered]@{
  generated=(Get-Date -Format o); file=[IO.Path]::GetFileName($Elf); size_bytes=$b.Length; entry=Hex32Text $entry;
  executable_segments=@($exec|ForEach-Object{[pscustomobject]@{vaddr=Hex32Text $_.vaddr;offset=Hex32Text $_.offset;filesz=Hex32Text $_.filesz;memsz=Hex32Text $_.memsz;flags=Hex32Text $_.flags}});
  scan_mode=$scanMode;
  function_csv=$functionCsvPath;
  function_csv_records=$functionCsvRecords;
  scan_ranges=@($scanRanges|ForEach-Object{[pscustomobject]@{start=H ([uint32]$_.start);end_exclusive=H ([uint32]$_.end)}});
  instruction_words=$words;
  opcode_counts=SortedCounts $opCounts;
  special_counts=SortedCounts $specialCounts;
  families=[ordered]@{cop0=$cop0;cop1=$cop1;cop2_vu0_macro=$cop2;mmi=$mmi;branches=$branchCount;jr=$jr;jalr=$jalr;syscall=$syscalls;break=$breaks;unique_jal_targets=$jal.Count;unique_jump_targets=$jump.Count};
  top_jal_targets=TopTargets $jal 150;
  top_jump_targets=TopTargets $jump 80;
  known_entry_words=$known;
  relevant_strings=@($relevant);
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out),($report|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

Write-Host 'Deep ELF census complete.' -ForegroundColor Green
Write-Host ('Scan mode:     ' + $scanMode)
if($functionCsvPath){Write-Host ('Function CSV:  ' + $functionCsvPath)}
Write-Host ('Words scanned: ' + $words)
Write-Host ('JAL targets:    ' + $jal.Count)
Write-Host ('COP1 words:     ' + $cop1)
Write-Host ('COP2/VU0:       ' + $cop2)
Write-Host ('MMI words:      ' + $mmi)
Write-Host ('Relevant strings: ' + $relevant.Count)
Write-Host ('Report: ' + [IO.Path]::GetFullPath($Out))
