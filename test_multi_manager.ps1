$ErrorActionPreference='Stop'
$testPrivate=Join-Path $env:TEMP ('DarkWarManagerTest-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA;$env:LOCALAPPDATA=$testPrivate
try{
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 if($h.Form.Text -ne 'DarkWar 多开管理器 v1.0.0' -or $h.View.Columns.Count -ne 6 -or !$h.Delete -or !$h.EditRemark){throw 'Manager UI missing'}
 [void]$h.State.Instances.Add([pscustomobject]@{id=98761;user='DWTestAbsent98761';remark='我的小号'});& $h.Refresh
 if($h.View.Items.Count -ne 1 -or $h.View.Items[0].SubItems[4].Text -ne '首次启动后生成' -or $h.View.Items[0].SubItems[1].Text -ne '我的小号'){throw 'Profile placeholder or remark missing'}
 $item=$h.View.Items[0];& $h.Refresh;if(![object]::ReferenceEquals($item,$h.View.Items[0])){throw 'Unchanged refresh rebuilt the list'}
 $h.Form.Show();[Windows.Forms.Application]::DoEvents();$h.View.Items[0].Selected=$true;$h.State.TestRemark='修改后备注';$h.EditRemark.PerformClick()
 if($h.View.Items[0].SubItems[1].Text -ne '修改后备注'){throw 'Editing remark did not update the row'}
 & $h.Save
 $config=Get-Content -LiteralPath (Join-Path $testPrivate 'DarkWarMulti\instances.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if(@($config.instances).Count -ne 1 -or $config.instances[0].user -ne 'DWTestAbsent98761' -or $config.instances[0].remark -ne '修改后备注'){throw 'Configuration persistence failed'}
 if(!$h.View.MultiSelect){throw 'Batch selection disabled'}
 [void]$h.State.Instances.Add([pscustomobject]@{id=98762;user='DWTestAbsent98762';remark='第二个账号'});& $h.Refresh
 $h.View.Items[0].Selected=$true;$h.View.Items[1].Selected=$true
 if($h.View.SelectedItems.Count -ne 2){throw 'Multiple rows cannot be selected'}
 [void]$h.State.Instances.Add([pscustomobject]@{id=98763;user='DWTestAbsent98763';remark='第三个账号'});& $h.Refresh
 if($h.View.SelectedItems.Count -ne 2){throw 'Structural refresh lost multi-selection'}
 $items=@([pscustomobject]@{Entry=$h.State.Instances[0];Plan=[pscustomobject]@{ProfilePath='C:\Users\ExampleA'}},[pscustomobject]@{Entry=$h.State.Instances[1];Plan=[pscustomobject]@{ProfilePath='C:\Users\ExampleB'}})
 $details=Format-DarkWarDeletionList $items
 if($details -notmatch '实例 98761 — 备注：修改后备注' -or $details -notmatch '实例 98762 — 备注：第二个账号' -or $details -notmatch "`r`n`r`n"){throw 'Batch confirmation omitted instance, remark or blank line'}
 $probe=@{Error=''};$uiTimer=[Windows.Forms.Timer]::new();$uiTimer.Interval=150
 $uiTimer.Add_Tick(({try{$dialog=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Text -eq '确认删除实例和数据'}) | Select-Object -First 1;if(!$dialog){return};$detailBox=@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.TextBox]}) | Select-Object -First 1;if(!$detailBox -or !$detailBox.ReadOnly -or !$detailBox.Text.Contains('修改后备注') -or !$detailBox.Text.Contains('第二个账号')){throw 'Confirmation dialog details incorrect'};@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq '取消'})[0].PerformClick();$uiTimer.Stop()}catch{$probe.Error=$_.Exception.Message;$uiTimer.Stop();if($dialog){$dialog.Close()}}}).GetNewClosure())
 $uiTimer.Start();$confirmed=Show-DarkWarDeleteConfirmation $items;$uiTimer.Dispose();if($probe.Error -or $confirmed){throw ('Cancel deletion dialog failed: '+$probe.Error)}
 if(!$h.ChooseGame -or !$h.GameLabel){throw 'Game chooser missing'}
 $password=New-DarkWarPassword;$secureFile=Join-Path $testPrivate 'password.bin';[IO.File]::WriteAllBytes($secureFile,$password.Encrypted);$roundtrip=Read-DarkWarPassword $secureFile
 $a=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($password.Secure);$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($roundtrip);try{if([Runtime.InteropServices.Marshal]::PtrToStringBSTR($a) -ne [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)){throw 'Credential round trip failed'}}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($a);[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b);Remove-Item -LiteralPath $secureFile}
 if(!(Get-Process -Name 'DarkWarSlot2' -ErrorAction SilentlyContinue)){
  $slot=Prepare-DarkWarSlot 2 'D:\DarkWar\Game\DarkWar.exe'
  if(!(Test-Path -LiteralPath (Join-Path $slot 'DarkWarSlot2.exe')) -or !(Test-Path -LiteralPath (Join-Path $slot 'DarkWarSlot2_Data') -PathType Container)){throw 'Game slot is incomplete'}
  $again=Prepare-DarkWarSlot 2 'D:\DarkWar\Game\DarkWar.exe';if($again -ne $slot){throw 'Repeated preparation failed'}
 }
 $h.Form.Dispose()
 'Multi-instance manager layout, persistence, and slot preparation: PASS'
}finally{
 $env:LOCALAPPDATA=$oldLocal
 $testConfig=Join-Path $testPrivate 'DarkWarMulti\instances.json';if(Test-Path -LiteralPath $testConfig){Remove-Item -LiteralPath $testConfig}
 foreach($path in @((Join-Path $testPrivate 'DarkWarMulti\credentials'),(Join-Path $testPrivate 'DarkWarMulti'),$testPrivate)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}}
}
