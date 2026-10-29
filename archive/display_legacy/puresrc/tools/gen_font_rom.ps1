#
# Generate a 16x16 GB2312 bitmap font ROM for osd_overlay.v.
#
# Layout (must match font_16x16_rom.v):
#   index 0           : blank glyph (used for unmapped codes)
#   index 1 .. 94     : GB2312 zone 3 (0xA3A1..0xA3FE, full-width ASCII)
#   index 95 .. N     : GB2312 level-1 prefix (N = MaxGlyphs-1)
#
# EG4S20 has 64 x 9Kb BRAMs, which hold at most 2048 16x16 glyphs.  The
# default 2000-glyph image leaves headroom; increase MaxGlyphs only if the
# font is moved to the 32Kb BRAMs (or external memory).
#
# Output: one 4-hex-digit word per scan line, 16 lines per glyph, row 0 first.
# Bit 15 of each word is the leftmost pixel.
#
param(
    [string]$FontName  = "SimHei",
    [int]$PixelSize    = 15,
    [string]$OutFile   = "src/font_gb2312.hex",
    [int]$MaxGlyphs    = 2000
)

Add-Type -AssemblyName System.Drawing

$enc  = [System.Text.Encoding]::GetEncoding(936)
$bmp  = New-Object System.Drawing.Bitmap 16, 16
$gfx  = [System.Drawing.Graphics]::FromImage($bmp)
$font = New-Object System.Drawing.Font($FontName, $PixelSize,
            [System.Drawing.FontStyle]::Regular,
            [System.Drawing.GraphicsUnit]::Pixel)
$sf   = New-Object System.Drawing.StringFormat
$sf.Alignment     = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$rect = New-Object System.Drawing.RectangleF 0, 0, 16, 16

$gfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit

$lines = New-Object System.Collections.Generic.List[string]
$glyphs = 0

function Emit-Glyph([string]$ch) {
    $script:gfx.Clear([System.Drawing.Color]::White)
    if ($ch) {
        $script:gfx.DrawString($ch, $script:font,
            [System.Drawing.Brushes]::Black, $script:rect, $script:sf)
    }
    $d = $script:bmp.LockBits((New-Object System.Drawing.Rectangle 0,0,16,16),
             [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
             [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $bytes = New-Object byte[] ($d.Stride * 16)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $bytes, 0, $bytes.Length)
    $script:bmp.UnlockBits($d)

    for ($row = 0; $row -lt 16; $row++) {
        $word = 0
        for ($col = 0; $col -lt 16; $col++) {
            $o = $row * $d.Stride + $col * 3
            $lum = ([int]$bytes[$o+2] + [int]$bytes[$o+1] + [int]$bytes[$o]) / 3
            if ($lum -lt 128) { $word = $word -bor (1 -shl (15 - $col)) }
        }
        $script:lines.Add(("{0:X4}" -f $word))
    }
    $script:glyphs++
}

# index 0: blank glyph (invalid / unimplemented code points)
Emit-Glyph ""

# zone 3: full-width ASCII / punctuation
for ($wei = 1; $wei -le 94; $wei++) {
    if ($glyphs -ge $MaxGlyphs) { break }
    try   { $ch = $enc.GetString([byte[]]@([byte]0xA3, [byte]($wei + 0xA0))) }
    catch { $ch = "" }
    Emit-Glyph $ch
}

# GB2312 level-1: zones 16..55, positions 1..94
for ($qu = 16; $qu -le 55; $qu++) {
    for ($wei = 1; $wei -le 94; $wei++) {
        if ($glyphs -ge $MaxGlyphs) { break }
        try {
            $ch = $enc.GetString([byte[]]@([byte]($qu + 0xA0), [byte]($wei + 0xA0)))
        } catch { $ch = "" }
        Emit-Glyph $ch
    }
}

$gfx.Dispose(); $bmp.Dispose(); $font.Dispose()

[System.IO.File]::WriteAllLines((Resolve-Path -LiteralPath (Split-Path -Parent $OutFile)).Path + "\" +
    (Split-Path -Leaf $OutFile), $lines, [System.Text.Encoding]::ASCII)

# Also emit 16 bank files (2048 x 16-bit words each) for EG_LOGIC_BRAM INIT_FILE.
$outDir = (Resolve-Path -LiteralPath (Split-Path -Parent $OutFile)).Path
for ($bank = 0; $bank -lt 16; $bank++) {
    $words = New-Object System.Collections.Generic.List[string]
    $start = $bank * 2048
    for ($k = 0; $k -lt 2048; $k++) {
        $i = $start + $k
        if ($i -lt $lines.Count) { $words.Add($lines[$i]) } else { $words.Add("0000") }
    }
    $name = "font_bank_{0:D2}.dath" -f $bank
    [System.IO.File]::WriteAllLines($outDir + "\" + $name, $words, [System.Text.Encoding]::ASCII)
}

Write-Output ("glyphs={0} lines={1} font={2} size={3}" -f $glyphs, $lines.Count, $FontName, $PixelSize)
