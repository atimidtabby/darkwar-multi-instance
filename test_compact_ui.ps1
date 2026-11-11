$ErrorActionPreference='Stop'
$old=$env:LOCALAPPDATA;$temp=Join-Path $env:TEMP ('DarkWarCompactTest-'+[guid]::NewGuid().ToString('N'));$env:LOCALAPPDATA=$temp
try {
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 $h.Form.Show();[Windows.Forms.Application]::DoEvents()
 if($h.Form.Width -ne 700 -or $h.Form.Height -ne 355){throw 'Initial window size is incorrect'}
 if($h.ChooseGame.Text -ne '选择游戏程序'){throw 'Empty game selection status incorrect'}
 if($h.View.Columns[3].Width -gt 70 -or $h.View.Columns[4].Width -gt 180){throw 'Table columns not compact'}
 if($h.View.Height -lt 100){throw 'Results area too small'}
 $top=$h.ChooseGame.Parent
 foreach($c in $top.Controls){if($c.Right -gt $top.ClientSize.Width -or $c.Bottom -gt $top.ClientSize.Height){throw ('Control clipped: '+$c.Text)}}
 $h.Form.Width=800;[Windows.Forms.Application]::DoEvents()
 if($h.GameLabel.Right -gt $top.ClientSize.Width){throw 'Path label does not resize'}
 $game=Get-CimInstance Win32_Process -Filter "Name='DarkWar.exe'" | Select-Object -First 1
 if($game -and $game.ExecutablePath){
  $script:gamePath=[string]$game.ExecutablePath;$script:dialogError=''
  $timer=[Windows.Forms.Timer]::new();$timer.Interval=150
  $timer.Add_Tick({$d=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Text -eq '选择游戏程序'}) | Select-Object -First 1;if(!$d){return};$timer.Stop();try{@($d.Controls | Where-Object {$_ -is [Windows.Forms.TextBox]})[0].Text=$script:gamePath;@($d.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq '确定'})[0].PerformClick()}catch{$script:dialogError=$_.Exception.Message;$d.Close()}})
  $timer.Start();$h.ChooseGame.PerformClick();$timer.Dispose()
  if($script:dialogError -or $h.ChooseGame.Text -ne '已选择（更换）'){throw ('Selection state failed: '+$script:dialogError)}
  $h.Form.Dispose()
  $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
  if($h.ChooseGame.Text -ne '已选择（更换）'){throw 'Saved selection state not restored'}
 }
 $h.Form.Dispose()
 'PASS: compact manager sizing, columns, selection, and saved selection'
} finally { $env:LOCALAPPDATA=$old }
