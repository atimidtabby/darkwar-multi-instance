$ErrorActionPreference='Stop'
$oldLocal=$env:LOCALAPPDATA;$testPrivate=Join-Path $env:TEMP ('DarkWarAccountTest-'+[guid]::NewGuid().ToString('N'));$env:LOCALAPPDATA=$testPrivate
$name='DWProbe'+[guid]::NewGuid().ToString('N').Substring(0,8);$user=$null;$process=$null
try{
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 $generated=New-DarkWarPassword;$file=Join-Path $testPrivate 'credential.bin';[IO.File]::WriteAllBytes($file,$generated.Encrypted)
 $user=New-LocalUser -Name $name -Password $generated.Secure -PasswordNeverExpires -Description 'Temporary launcher validation'
 $group=Get-LocalGroup -SID 'S-1-5-32-545';Add-LocalGroupMember -Group $group.Name -Member $name
 $restored=Read-DarkWarPassword $file
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $env:SystemRoot 'System32\whoami.exe';$info.WorkingDirectory=[Environment]::GetFolderPath('CommonDocuments');$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true;$info.UserName=$name;$info.Domain=$env:COMPUTERNAME;$info.Password=$restored;$info.LoadUserProfile=$true
 $process=[Diagnostics.Process]::Start($info);$identity=$process.StandardOutput.ReadToEnd();$process.WaitForExit();if($process.ExitCode -ne 0 -or $identity -notmatch [regex]::Escape($name)){throw 'Isolated identity launch failed'}
 $h.Form.Dispose();'Standard account creation, encrypted credential, and isolated process: PASS'
}finally{
 if($process){$process.Dispose()}
 if($user){$sid=$user.SID.Value;Remove-LocalUser -SID $user.SID -ErrorAction SilentlyContinue;Start-Sleep -Seconds 2;$profile=Get-CimInstance Win32_UserProfile -Filter "SID='$sid'" -ErrorAction SilentlyContinue;$expected=Join-Path $env:SystemDrive "Users\$name*";if($profile -and !$profile.Loaded -and $profile.LocalPath -like $expected){Remove-CimInstance -InputObject $profile -ErrorAction SilentlyContinue};if(Get-LocalUser -SID $user.SID -ErrorAction SilentlyContinue){throw 'Temporary test account could not be removed'}}
 $env:LOCALAPPDATA=$oldLocal
 foreach($path in @((Join-Path $testPrivate 'credential.bin'),(Join-Path $testPrivate 'DarkWarMulti\credentials'),(Join-Path $testPrivate 'DarkWarMulti'),$testPrivate)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}}
}
