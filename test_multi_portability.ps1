$ErrorActionPreference='Stop'
$oldLocal=$env:LOCALAPPDATA;$tempBase=Join-Path $env:TEMP ('DWPortableTest-'+[guid]::NewGuid().ToString('N'));$env:LOCALAPPDATA=Join-Path $tempBase 'local'
$slotId=987614;$slot=Join-Path ([Environment]::GetFolderPath('CommonDocuments')) "DarkWarMulti\slot-$slotId";$versions=@()
try{
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 foreach($n in @('first','second')){
  $dir=Join-Path $tempBase $n;New-Item -ItemType Directory -Force -Path $dir,(Join-Path $dir 'DarkWar_Data'),(Join-Path $dir 'config')|Out-Null
  foreach($name in @('DarkWar.exe','GameAssembly.dll','UnityPlayer.dll','baselib.dll','UnityCrashHandler64.exe')){[IO.File]::WriteAllText((Join-Path $dir $name),"$n-$name-$tempBase")}
  $files=@('DarkWar.exe','GameAssembly.dll','UnityPlayer.dll','baselib.dll','UnityCrashHandler64.exe');$fp=foreach($f in $files){$item=Get-Item -LiteralPath (Join-Path $dir $f);"$($item.Length)-$($item.LastWriteTimeUtc.Ticks)"};$sha=[Security.Cryptography.SHA256]::Create();try{$hash=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($fp -join '|')));$version=([BitConverter]::ToString($hash)).Replace('-','').Substring(0,16)}finally{$sha.Dispose()};$versions+=Join-Path ([Environment]::GetFolderPath('CommonDocuments')) "DarkWarMulti\shared\$version"
  $actual=Prepare-DarkWarSlot $slotId (Join-Path $dir 'DarkWar.exe')
  $link=Get-Item -LiteralPath (Join-Path $actual "DarkWarSlot${slotId}_Data") -Force
  $expected=(Get-Item -LiteralPath (Join-Path $dir 'DarkWar_Data')).FullName
  if(@($link.Target) -notcontains $expected){throw 'Game data link points to wrong installation'}
 }
 $h.State.GameExe=Join-Path $tempBase 'second\DarkWar.exe';& $h.Save
 $saved=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'DarkWarMulti\instances.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($saved.gameExe -ne $h.State.GameExe){throw 'Selected game path not saved'}
 $h.Form.Dispose();'Custom game paths, safe link replacement and saved selection: PASS'
}finally{
 $env:LOCALAPPDATA=$oldLocal
 foreach($link in @((Join-Path $slot "DarkWarSlot${slotId}_Data"),(Join-Path $slot 'config'))){if(Test-Path -LiteralPath $link){$item=Get-Item -LiteralPath $link -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){[IO.Directory]::Delete($link)}}}
 foreach($f in @("DarkWarSlot$slotId.exe",'GameAssembly.dll','UnityPlayer.dll','baselib.dll','UnityCrashHandler64.exe','.game-source.txt')){$path=Join-Path $slot $f;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}
 if(Test-Path -LiteralPath $slot){Remove-Item -LiteralPath $slot -ErrorAction SilentlyContinue}
 foreach($version in $versions){foreach($f in @('DarkWar.exe','GameAssembly.dll','UnityPlayer.dll','baselib.dll','UnityCrashHandler64.exe')){$path=Join-Path $version $f;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}};if(Test-Path -LiteralPath $version){Remove-Item -LiteralPath $version -ErrorAction SilentlyContinue}}
 foreach($n in @('first','second')){$dir=Join-Path $tempBase $n;foreach($f in @('DarkWar.exe','GameAssembly.dll','UnityPlayer.dll','baselib.dll','UnityCrashHandler64.exe')){$path=Join-Path $dir $f;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}};foreach($path in @((Join-Path $dir 'DarkWar_Data'),(Join-Path $dir 'config'),$dir)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}}}
 foreach($path in @((Join-Path $tempBase 'local\DarkWarMulti\instances.json'),(Join-Path $tempBase 'local\DarkWarMulti\credentials'),(Join-Path $tempBase 'local\DarkWarMulti'),(Join-Path $tempBase 'local'),$tempBase)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}}
}
