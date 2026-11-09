$ErrorActionPreference='Stop'
$oldLocal=$env:LOCALAPPDATA;$tmp=Join-Path $env:TEMP ('DarkWarCreateTest-'+[guid]::NewGuid().ToString('N'));$env:LOCALAPPDATA=$tmp
$id=Get-Random -Minimum 800000 -Maximum 999999;$name="DWSlot$id";$wasAbsent=$false
try{
 if(Get-LocalUser -Name $name -ErrorAction SilentlyContinue){throw 'Test account already exists'}
 $wasAbsent=$true
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 $h.State.TestNextId=$id;$h.State.TestRemark='测试备注';$h.Form.Show();[Windows.Forms.Application]::DoEvents();$h.Create.PerformClick()
 $user=Get-LocalUser -Name $name -ErrorAction SilentlyContinue
 if(!$user -or $h.State.Instances.Count -ne 1 -or $h.State.Instances[0].remark -ne '测试备注'){throw 'Create action did not retain account and remark'}
 $file=Join-Path $tmp 'DarkWarMulti\instances.json';$saved=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
 if(@($saved.instances).Count -ne 1 -or $saved.instances[0].user -ne $name -or $saved.instances[0].remark -ne '测试备注'){throw 'Create action did not persist instance'}
 if(!(Test-Path -LiteralPath (Join-Path $tmp "DarkWarMulti\credentials\$name.bin"))){throw 'Credential missing'}
 $h.Form.Dispose();[IO.File]::WriteAllText($file,'{"instances":[]}',[Text.UTF8Encoding]::new($true))
 $restored=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 if($restored.State.Instances.Count -ne 1 -or $restored.State.Instances[0].user -ne $name -or $restored.State.Instances[0].sid -ne $user.SID.Value){throw 'Managed instance recovery failed'}
 $restored.Form.Dispose();'Create action, remark, persistence and managed instance recovery: PASS'
}finally{
 if($wasAbsent){$user=Get-LocalUser -Name $name -ErrorAction SilentlyContinue;if($user -and $user.Description -ceq "DarkWar isolated instance $id"){Remove-LocalUser -SID $user.SID -ErrorAction SilentlyContinue}}
 $env:LOCALAPPDATA=$oldLocal
 foreach($path in @((Join-Path $tmp "DarkWarMulti\credentials\$name.bin"),(Join-Path $tmp 'DarkWarMulti\instances.json'),(Join-Path $tmp 'DarkWarMulti\credentials'),(Join-Path $tmp 'DarkWarMulti'),$tmp)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}}
}
