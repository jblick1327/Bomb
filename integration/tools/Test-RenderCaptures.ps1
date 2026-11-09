param([Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$rows=@()
foreach($role in @('primary','guest')){
 foreach($phase in @('menu','sandbox','disconnected')){
  $path=Join-Path $Directory ($role+'-'+$phase+'.png')
  $row=[ordered]@{file=[IO.Path]::GetFileName($path);status='failed';samples=0;nonblack=0;unique_colors=0}
  if(Test-Path -LiteralPath $path){
   $bitmap=[Drawing.Bitmap]::new($path)
   try{
    $colors=[Collections.Generic.HashSet[int]]::new()
    for($y=8;$y -lt $bitmap.Height;$y+=16){for($x=8;$x -lt $bitmap.Width;$x+=16){
     $color=$bitmap.GetPixel($x,$y);$row.samples++;$null=$colors.Add($color.ToArgb())
     if([int]$color.R+[int]$color.G+[int]$color.B -gt 12){$row.nonblack++}
    }}
    $row.unique_colors=$colors.Count
    if($bitmap.Width -eq 1280 -and $bitmap.Height -eq 720 -and $row.nonblack -ge 64 -and $row.unique_colors -ge 16){$row.status='passed'}
   }finally{$bitmap.Dispose()}
  }
  $rows+=$row
 }
}
$passed=@($rows|Where-Object status -ne 'passed').Count -eq 0
$result=[ordered]@{status=$(if($passed){'passed'}else{'failed'});scope='Reject missing, black or effectively blank rendered camera/UI evidence; composition is reviewed separately';captures=$rows}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding utf8
if(!$passed){exit 1}
