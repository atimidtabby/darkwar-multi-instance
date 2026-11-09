$ErrorActionPreference='Stop'
$oldLocal=$env:LOCALAPPDATA;$tmp=Join-Path $env:TEMP ('DarkWarBatchTest-'+[guid]::NewGuid().ToString('N'));$env:LOCALAPPDATA=$tmp
$seed=Get-Random -Minimum 700000 -Maximum 799998;$created=[Collections.Generic.List[object]]::new();$slots=[Collections.Generic.List[string]]::new();$h=$null
try{
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 $game=Join-Path $tmp 'shared-game';New-Item -ItemType Directory -Force -Path (Join-Path $game 'DarkWar_Data'),(Join-Path $game 'config') | Out-Null;$sentinel=Join-Path $game 'DarkWar_Data\do-not-delete.txt';[IO.File]::WriteAllText($sentinel,'shared')
 $entries=[Collections.Generic.List[object]]::new()
 foreach($id in @($seed,($seed+1))){$name="DWSlot$id";if(Get-LocalUser -Name $name -ErrorAction SilentlyContinue){throw 'Random test account already exists'};$pw=New-DarkWarPassword;$user=New-LocalUser -Name $name -Password $pw.Secure -Description "DarkWar isolated instance $id";$created.Add($user);$users=Get-LocalGroup -SID 'S-1-5-32-545';Add-LocalGroupMember -Group $users.Name -Member $name;[IO.File]::WriteAllBytes((Join-Path $tmp "DarkWarMulti\credentials\$name.bin"),$pw.Encrypted);$slot=Join-Path ([Environment]::GetFolderPath('CommonDocuments')) "DarkWarMulti\slot-$id";if(Test-Path -LiteralPath $slot){throw 'Random test slot already exists'};New-Item -ItemType Directory -Path $slot | Out-Null;$slots.Add($slot);New-Item -ItemType Junction -Path (Join-Path $slot "DarkWarSlot${id}_Data") -Target (Join-Path $game 'DarkWar_Data') | Out-Null;New-Item -ItemType Junction -Path (Join-Path $slot 'config') -Target (Join-Path $game 'config') | Out-Null;[IO.File]::WriteAllText((Join-Path $slot '.game-source.txt'),$game);$entries.Add([pscustomobject]@{id=$id;user=$name;sid=$user.SID.Value;remark="备注$id"})}
 $bad=Join-Path $slots[1] 'unknown.txt';[IO.File]::WriteAllText($bad,'protected');$failed=$false;try{$null=Get-DarkWarBatchPlans $entries.ToArray()}catch{$failed=$true};if(!$failed){throw 'Batch preflight did not reject unsafe item'}
 foreach($entry in $entries){if(!(Get-LocalUser -Name $entry.user -ErrorAction SilentlyContinue)){throw 'Preflight removed an account'}};Remove-Item -LiteralPath $bad
 $plans=@(Get-DarkWarBatchPlans $entries.ToArray());if($plans.Count -ne 2){throw 'Batch plans did not include both instances'};$text=Format-DarkWarDeletionList $plans
 foreach($entry in $entries){if(!$text.Contains("备注$($entry.id)")){throw 'Batch confirmation does not include each remark'}}
 foreach($item in $plans){Remove-DarkWarInstance $item.Plan}
 foreach($entry in $entries){if((Get-LocalUser -Name $entry.user -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('CommonDocuments')) "DarkWarMulti\slot-$($entry.id)"))){throw 'Batch removal incomplete'}}
 $missingId=$seed+2;$missingName="DWSlot$missingId";if(Get-LocalUser -Name $missingName -ErrorAction SilentlyContinue){throw 'Random missing-account fixture already exists'}
 $domain=$created[0].SID.AccountDomainSid.Value;$missing=[pscustomobject]@{id=$missingId;user=$missingName;sid=($domain+'-9999999');remark='残留记录'};$missingPlan=Get-DarkWarDeletionPlan $missing
 if($missingPlan.User -or $missingPlan.Profile){throw 'Missing account fixture unexpectedly exists'};Remove-DarkWarInstance $missingPlan
 if(!(Test-Path -LiteralPath $sentinel)){throw 'Batch removal damaged shared resources'}
 $h.Form.Dispose();'Batch preflight, remarks, deletion and shared data preservation: PASS'
}finally{
 foreach($user in $created){$actual=Get-LocalUser -SID $user.SID -ErrorAction SilentlyContinue;if($actual -and $actual.Description -eq $user.Description){Remove-LocalUser -SID $user.SID -ErrorAction SilentlyContinue}}
 foreach($slot in $slots){$slotId=[int]([IO.Path]::GetFileName($slot).Substring(5));foreach($link in @((Join-Path $slot "DarkWarSlot${slotId}_Data"),(Join-Path $slot 'config'))){if(Test-Path -LiteralPath $link){$item=Get-Item -LiteralPath $link -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){[IO.Directory]::Delete($link)}}};foreach($f in @((Join-Path $slot '.game-source.txt'),(Join-Path $slot 'unknown.txt'))){if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f -Force}};if(Test-Path -LiteralPath $slot){Remove-Item -LiteralPath $slot -ErrorAction SilentlyContinue}}
 foreach($user in $created){$f=Join-Path $tmp "DarkWarMulti\credentials\$($user.Name).bin";if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f -Force}}
 $env:LOCALAPPDATA=$oldLocal
 $sentinel=Join-Path $tmp 'shared-game\DarkWar_Data\do-not-delete.txt';if(Test-Path -LiteralPath $sentinel){Remove-Item -LiteralPath $sentinel}
 foreach($dir in @((Join-Path $tmp 'shared-game\DarkWar_Data'),(Join-Path $tmp 'shared-game\config'),(Join-Path $tmp 'shared-game'),(Join-Path $tmp 'DarkWarMulti\credentials'),(Join-Path $tmp 'DarkWarMulti'),$tmp)){if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -ErrorAction SilentlyContinue}}
}
