$ErrorActionPreference='Stop'
$oldLocal=$env:LOCALAPPDATA;$testPrivate=Join-Path $env:TEMP ('DarkWarDeleteTest-'+[guid]::NewGuid().ToString('N'));$env:LOCALAPPDATA=$testPrivate
$user=$null;$process=$null;$slot='';$name=''
try{
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 $user=$null;$id=Get-Random -Minimum 800000 -Maximum 999999;$name="DWSlot$id";$slot=Join-Path ([Environment]::GetFolderPath('CommonDocuments')) "DarkWarMulti\slot-$id"
 if(Get-LocalUser -Name $name -ErrorAction SilentlyContinue){throw 'Random test user already exists'}
 $password=New-DarkWarPassword;$user=New-LocalUser -Name $name -Password $password.Secure -PasswordNeverExpires -Description "DarkWar isolated instance $id"
 $group=Get-LocalGroup -SID 'S-1-5-32-545';Add-LocalGroupMember -Group $group.Name -Member $name
 $cred=Join-Path $testPrivate "DarkWarMulti\credentials\$name.bin";[IO.File]::WriteAllBytes($cred,$password.Encrypted)
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $env:SystemRoot 'System32\whoami.exe';$info.WorkingDirectory=[Environment]::GetFolderPath('CommonDocuments');$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.CreateNoWindow=$true;$info.UserName=$name;$info.Domain=$env:COMPUTERNAME;$info.Password=$password.Secure;$info.LoadUserProfile=$true
 $process=[Diagnostics.Process]::Start($info);$null=$process.StandardOutput.ReadToEnd();$process.WaitForExit();if($process.ExitCode -ne 0){throw 'Test user could not load profile'};$process.Dispose();$process=$null
 Start-Sleep -Seconds 2
 $game=Join-Path $testPrivate 'game';New-Item -ItemType Directory -Force -Path (Join-Path $game 'DarkWar_Data'),(Join-Path $game 'config'),$slot | Out-Null
 $sentinel=Join-Path $game 'DarkWar_Data\must-survive.txt';[IO.File]::WriteAllText($sentinel,'shared')
 New-Item -ItemType Junction -Path (Join-Path $slot "DarkWarSlot${id}_Data") -Target (Join-Path $game 'DarkWar_Data') | Out-Null
 New-Item -ItemType Junction -Path (Join-Path $slot 'config') -Target (Join-Path $game 'config') | Out-Null
 [IO.File]::WriteAllText((Join-Path $slot '.game-source.txt'),$game);[IO.File]::WriteAllText((Join-Path $slot "DarkWarSlot$id.exe"),'instance')
 $entry=[pscustomobject]@{id=$id;user=$name;sid=$user.SID.Value;remark='测试'}
 $bad=[pscustomobject]@{id=$id;user=$name;sid='S-1-5-21-1-1-1-1'};$failed=$false;try{$null=Get-DarkWarDeletionPlan $bad}catch{$failed=$true};if(!$failed){throw 'Incorrect SID was accepted'}
 $extra=Join-Path $slot 'unknown.txt';[IO.File]::WriteAllText($extra,'do not delete');$failed=$false;try{$null=Get-DarkWarDeletionPlan $entry}catch{$failed=$true};if(!$failed){throw 'Unknown file was accepted'};Remove-Item -LiteralPath $extra
 $plan=Get-DarkWarDeletionPlan $entry;if(!$plan.ProfilePath -or $plan.Profile.Loaded){throw 'Test profile missing or loaded'}
 Remove-DarkWarInstance $plan
 if((Get-LocalUser -Name $name -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $cred) -or (Test-Path -LiteralPath $slot) -or (Test-Path -LiteralPath $plan.ProfilePath)){throw 'Instance cleanup incomplete'}
 if(!(Test-Path -LiteralPath $sentinel)){throw 'Shared game data was deleted'}
 $user=$null;$h.Form.Dispose();'Delete plan, identity checks, isolated profile and shared resource preservation: PASS'
}finally{
 if($process){if(!$process.HasExited){$process.Kill();$process.WaitForExit()};$process.Dispose()}
 if($user){$sid=$user.SID.Value;Remove-LocalUser -SID $user.SID -ErrorAction SilentlyContinue;$profile=Get-CimInstance Win32_UserProfile -Filter "SID='$sid'" -ErrorAction SilentlyContinue;$base=[Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -Name ProfilesDirectory).ProfilesDirectory);$expected=Join-Path $base "$name*";if($profile -and !$profile.Loaded -and $profile.LocalPath -like $expected){Remove-CimInstance -InputObject $profile -ErrorAction SilentlyContinue}}
 $env:LOCALAPPDATA=$oldLocal
 if($slot){foreach($link in @((Join-Path $slot "DarkWarSlot${id}_Data"),(Join-Path $slot 'config'))){if(Test-Path -LiteralPath $link){$item=Get-Item -LiteralPath $link -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){[IO.Directory]::Delete($link)}}};foreach($file in @((Join-Path $slot '.game-source.txt'),(Join-Path $slot "DarkWarSlot$id.exe"),(Join-Path $slot 'unknown.txt'))){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}};if(Test-Path -LiteralPath $slot){Remove-Item -LiteralPath $slot -ErrorAction SilentlyContinue}}
 foreach($file in @((Join-Path $testPrivate 'game\DarkWar_Data\must-survive.txt'),(Join-Path $testPrivate "DarkWarMulti\credentials\$name.bin"))){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}}
 foreach($dir in @((Join-Path $testPrivate 'game\DarkWar_Data'),(Join-Path $testPrivate 'game\config'),(Join-Path $testPrivate 'game'),(Join-Path $testPrivate 'DarkWarMulti\credentials'),(Join-Path $testPrivate 'DarkWarMulti'),$testPrivate)){if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -ErrorAction SilentlyContinue}}
}
