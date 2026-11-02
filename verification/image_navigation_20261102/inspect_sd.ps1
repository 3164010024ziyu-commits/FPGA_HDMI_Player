param(
    [string]$Root = 'E:\',
    [string]$ImagePath = '',
    [string]$Output = (Join-Path $PSScriptRoot 'sd_card_report.json')
)
# Read-only FAT32/root/BMP-header audit. Reports are written beside this script,
# never to the card. Mounted-volume access can require an elevated PowerShell.
$ErrorActionPreference = 'Stop'
function U16([byte[]]$b,[int]$o) { [BitConverter]::ToUInt16($b,$o) }
function U32([byte[]]$b,[int]$o) { [BitConverter]::ToUInt32($b,$o) }
function I32([byte[]]$b,[int]$o) { [BitConverter]::ToInt32($b,$o) }
function Sector([long]$lba) {
    if($lba -lt 0) { throw 'Negative LBA' }
    $null=$stream.Seek($lba*512,[IO.SeekOrigin]::Begin)
    $data=New-Object byte[] 512
    $n=0
    while($n -lt 512) { $got=$stream.Read($data,$n,512-$n);if($got -eq 0){throw 'Short sector read'};$n+=$got }
    return ,$data
}
function Inspect-Bmp([byte[]]$entry,[int]$number) {
    $base=[Text.Encoding]::ASCII.GetString($entry,0,8).TrimEnd()
    $ext=[Text.Encoding]::ASCII.GetString($entry,8,3).TrimEnd()
    $cluster=([long](U16 $entry 20))*65536+(U16 $entry 26)
    $length=[long](U32 $entry 28)
    $item=[ordered]@{Index=$number;ShortName="$base.$ext";FileBytes=$length;Cluster=$cluster;Supported=$false;ExpectedError='';Width=0;Height=0;Bits=0;Compression=0;Reason=''}
    if($length -lt 54 -or $length -gt 16777216 -or $cluster -lt 2 -or $cluster -gt $clusterCount+1) {
        $item.ExpectedError='37';$item.Reason='Invalid directory size/first cluster';return [pscustomobject]$item
    }
    $hdr=Sector ($dataBase+($cluster-2)*$spc)
    $w=I32 $hdr 18;$h=I32 $hdr 22;$bits=U16 $hdr 28;$compression=U32 $hdr 30
    $dib=U32 $hdr 14;$off=U32 $hdr 10;$declared=U32 $hdr 2
    $item.Width=$w;$item.Height=$h;$item.Bits=$bits;$item.Compression=$compression
    if($hdr[0] -ne 66 -or $hdr[1] -ne 77) {$item.ExpectedError='20';$item.Reason='Not a BMP payload'}
    elseif($dib -lt 40 -or $off -lt ([long]$dib+14) -or (U16 $hdr 26) -ne 1 -or $compression -ne 0 -or ($bits -ne 24 -and $bits -ne 32)) {
        $item.ExpectedError='21';$item.Reason='Requires BI_RGB (compression 0), 24/32 bit, DIB >=40'
    }
    elseif($w -le 0 -or $w -gt 640 -or [math]::Abs([long]$h) -eq 0 -or [math]::Abs([long]$h) -gt 480) {
        $item.ExpectedError='22';$item.Reason='Dimensions outside 1..640 x 1..480'
    }
    else {
        $stride=[long]([math]::Floor((([long]$w*$bits)+31)/32))*4
        $required=[long]$off+$stride*[math]::Abs([long]$h)
        if($required -gt $length -or $declared -gt $length -or ($declared -ne 0 -and $declared -lt $required)) {
            $item.ExpectedError='23';$item.Reason='File size/pixel payload bounds mismatch'
        }
        elseif($w%4 -ne 0) {$item.ExpectedError='E1';$item.Reason='Memory requires width divisible by four'}
        else {$item.Supported=$true;$item.Reason='Header accepted by current image path'}
    }
    return [pscustomobject]$item
}
$stream=$null
try {
    if($ImagePath) {$source=[IO.Path]::GetFullPath($ImagePath)}
    else {
        if($Root -notmatch '^([A-Za-z]):[\\/]?$') {throw 'Root must be a drive root, e.g. E:\'}
        $letter=$Matches[1].ToUpper();$source='\\.\'+$letter+':'
    }
    # Explicit FileAccess.Read: this script cannot modify sectors.
    $stream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $boot=Sector 0
    if((U16 $boot 510) -ne 43605 -or (U16 $boot 11) -ne 512 -or (U16 $boot 17) -ne 0 -or (U16 $boot 22) -ne 0) {throw 'Mounted volume is not supported FAT32/512-byte format'}
    $spc=[int]$boot[13];$reserved=[long](U16 $boot 14);$copies=[int]$boot[16];$fatSize=[long](U32 $boot 36);$total=[long](U32 $boot 32)
    if($spc -le 0 -or ($spc -band ($spc-1)) -ne 0 -or $copies -lt 1 -or $copies -gt 2 -or $fatSize -le 0) {throw 'Invalid FAT32 geometry'}
    $dataBase=$reserved+$copies*$fatSize;$clusterCount=[long][math]::Floor(($total-$dataBase)/$spc)
    $flags=U16 $boot 40;$active=0
    if(($flags -band 128) -ne 0) {$active=$flags -band 15}
    if($active -ge $copies) {throw 'Invalid active FAT'}
    $fatBase=$reserved+$active*$fatSize;$cluster=(U32 $boot 44) -band 268435455
    $seen=New-Object 'System.Collections.Generic.HashSet[long]'
    $items=New-Object 'System.Collections.Generic.List[object]';$end=$false
    while(-not $end) {
        if($cluster -lt 2 -or $cluster -gt $clusterCount+1 -or -not $seen.Add([long]$cluster) -or $seen.Count -gt 1024) {throw 'Invalid/looping/excessive root directory chain'}
        for($sectorIndex=0;$sectorIndex -lt $spc -and -not $end;$sectorIndex++) {
            $bytes=Sector ($dataBase+($cluster-2)*$spc+$sectorIndex)
            for($offset=0;$offset -lt 512;$offset+=32) {
                if($bytes[$offset] -eq 0) {$end=$true;break}
                $attr=$bytes[$offset+11]
                if($bytes[$offset] -eq 229 -or ($attr -band 24) -ne 0 -or $attr -eq 15) {continue}
                if([Text.Encoding]::ASCII.GetString($bytes,$offset+8,3).ToUpper() -ne 'BMP') {continue}
                $entry=New-Object byte[] 32;[Array]::Copy($bytes,$offset,$entry,0,32)
                $items.Add((Inspect-Bmp $entry $items.Count))
            }
        }
        if(-not $end) {
            $fatSector=Sector ($fatBase+[long][math]::Floor($cluster/128))
            $next=(U32 $fatSector ([int]($cluster%128)*4)) -band 268435455
            if($next -ge 268435448) {$end=$true}else{$cluster=$next}
        }
    }
    $report=[ordered]@{Source=$source;ReadOnly=$true;Scope='FAT32 root enumeration and BMP headers; pixel contents and full file chains not verified';RootClusters=$seen.Count;BmpEntries=$items.Count;SupportedHeaders=@($items|Where-Object Supported).Count;Images=$items.ToArray()}
    $report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output -Encoding UTF8
    $items|Format-Table Index,ShortName,Width,Height,Bits,Compression,Supported,ExpectedError -AutoSize
    Write-Output "BMP entries: $($items.Count). Report: $Output"
}
catch {Write-Error "Read-only inspection failed: $($_.Exception.Message). Mounted-volume access may require administrator rights.";exit 1}
finally {if($null -ne $stream){$stream.Dispose()}}
