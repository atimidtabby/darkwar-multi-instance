$ErrorActionPreference='Stop'
$oldLocal=$env:LOCALAPPDATA;$tmp=Join-Path $env:TEMP ('DarkWarSearchTest-'+[guid]::NewGuid().ToString('N'));$env:LOCALAPPDATA=Join-Path $tmp 'local';$job=$null
try{
 $h=. (Join-Path $PSScriptRoot 'MultiInstanceManager.ps1') -TestMode
 if($h.State.GameExe){throw 'New configuration must not use a fixed game path'}
 $game=Join-Path $tmp 'disk-a\不同位置\Game';$other=Join-Path $tmp 'disk-b\DarkWar\Game';$bogus=Join-Path $tmp 'disk-b\launcher'
 foreach($dir in @($game,$other)){New-Item -ItemType Directory -Path $dir,(Join-Path $dir 'DarkWar_Data') -Force | Out-Null;[IO.File]::WriteAllText((Join-Path $dir 'DarkWar.exe'),'test');[IO.File]::WriteAllText((Join-Path $dir 'UnityPlayer.dll'),'test')}
 New-Item -ItemType Directory -Path $bogus -Force | Out-Null;[IO.File]::WriteAllText((Join-Path $bogus 'DarkWar.exe'),'launcher')
 $canonical=(Get-Item -LiteralPath (Join-Path $game 'DarkWar.exe')).FullName
 if((Resolve-DarkWarGamePath ('"'+$canonical+'"')) -ne $canonical){throw 'Manual path validation failed'}
 $failed=$false;try{$null=Resolve-DarkWarGamePath (Join-Path $bogus 'DarkWar.exe')}catch{$failed=$true};if(!$failed){throw 'Launcher incorrectly accepted as game'}
 $job=Start-DarkWarGameSearch @((Join-Path $tmp 'disk-a'),(Join-Path $tmp 'disk-b')) $false
 if(!(Wait-Job -Job $job -Timeout 20)){throw 'Background search timed out'}
 $found=@(Receive-Job -Job $job | ForEach-Object {try{Resolve-DarkWarGamePath $_}catch{}})
 $canonicalOther=(Get-Item -LiteralPath (Join-Path $other 'DarkWar.exe')).FullName
 if($found.Count -ne 2 -or $found -notcontains $canonical -or $found -notcontains $canonicalOther){throw ('Background search returned incorrect results: '+($found -join ','))}
 $h.Form.Show();[Windows.Forms.Application]::DoEvents()
 $probe=@{Tries=0;Error=''};$uiTimer=[Windows.Forms.Timer]::new();$uiTimer.Interval=150
 $uiTimer.Add_Tick(({try{$probe.Tries++;$dialog=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Text -eq '选择游戏程序'}) | Select-Object -First 1;if(!$dialog){return};if($dialog.ClientSize.Width -gt 540 -or $dialog.ClientSize.Height -gt 320){throw 'Chooser is too large'};foreach($control in $dialog.Controls){if($control.Right -gt $dialog.ClientSize.Width -or $control.Bottom -gt $dialog.ClientSize.Height){throw ('Chooser control is outside the window: '+$control.Text)}};$pathBox=@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.TextBox]}) | Select-Object -First 1;$browse=@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.AccessibleName -eq '浏览游戏程序'});$searchButton=@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq '自动搜索'});$list=@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.ListBox]});if(!$pathBox -or !$browse.Count -or !$searchButton.Count -or !$list.Count){throw 'Chooser controls missing'};$pathBox.Text=$canonical;@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq '确定'})[0].PerformClick();$uiTimer.Stop()}catch{$probe.Error=$_.Exception.Message;$uiTimer.Stop();if($dialog){$dialog.Close()}}}).GetNewClosure())
 $uiTimer.Start();$answer=Show-DarkWarGameChooser '';if($probe.Error -or !$answer.Accepted -or $answer.Path -ne $canonical){throw ('Manual chooser failed: '+$probe.Error)};$uiTimer.Dispose()
 function Start-DarkWarGameSearch([string[]]$roots,[bool]$includeRunning){$options=@{Roots=@((Join-Path $script:tmp 'disk-a'));IncludeRunning=$false};return Start-Job -ScriptBlock $script:gameSearchScript -ArgumentList $options}
 $probe=@{Started=$false;Tries=0;Error=''};$uiTimer=[Windows.Forms.Timer]::new();$uiTimer.Interval=150
 $uiTimer.Add_Tick(({try{$probe.Tries++;$dialog=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Text -eq '选择游戏程序'}) | Select-Object -First 1;if(!$dialog){return};if($probe.Tries -gt 100){throw 'Automatic search did not show results'};$searchButton=@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq '自动搜索'})[0];$list=@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.ListBox]})[0];if(!$probe.Started){$probe.Started=$true;$searchButton.PerformClick();return};for($i=0;$i -lt $list.Items.Count;$i++){if([string]$list.Items[$i] -eq $canonical){$list.SelectedIndex=$i;@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq '确定'})[0].PerformClick();$uiTimer.Stop();return}}}catch{$probe.Error=$_.Exception.Message;$uiTimer.Stop();if($dialog){$dialog.Close()}}}).GetNewClosure())
 $uiTimer.Start();$answer=Show-DarkWarGameChooser '';if($probe.Error -or !$answer.Accepted -or $answer.Path -ne $canonical){throw ('Automatic chooser failed: '+$probe.Error)};$uiTimer.Dispose()
 $probe=@{Tries=0;Error=''};$uiTimer=[Windows.Forms.Timer]::new();$uiTimer.Interval=150
 $uiTimer.Add_Tick(({try{$probe.Tries++;$dialog=@([Windows.Forms.Application]::OpenForms | Where-Object {$_.Text -eq '选择游戏程序'}) | Select-Object -First 1;if(!$dialog){return};@($dialog.Controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq '关闭'})[0].PerformClick();$uiTimer.Stop()}catch{$probe.Error=$_.Exception.Message;$uiTimer.Stop();if($dialog){$dialog.Close()}}}).GetNewClosure())
 $uiTimer.Start();$answer=Show-DarkWarGameChooser $canonical;if($probe.Error -or $answer.Accepted){throw ('Closing chooser failed: '+$probe.Error)};$uiTimer.Dispose()
 $h.Form.Dispose();'Manual path, validation and asynchronous multi-drive search: PASS'
}finally{
 if($job){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
 $env:LOCALAPPDATA=$oldLocal
 foreach($dir in @((Join-Path $tmp 'disk-a\不同位置\Game'),(Join-Path $tmp 'disk-b\DarkWar\Game'))){foreach($name in @('DarkWar.exe','UnityPlayer.dll')){$file=Join-Path $dir $name;if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}};$data=Join-Path $dir 'DarkWar_Data';if(Test-Path -LiteralPath $data){Remove-Item -LiteralPath $data};if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir}}
 $launcher=Join-Path $tmp 'disk-b\launcher\DarkWar.exe';if(Test-Path -LiteralPath $launcher){Remove-Item -LiteralPath $launcher}
 foreach($dir in @((Join-Path $tmp 'disk-b\launcher'),(Join-Path $tmp 'disk-a\不同位置'),(Join-Path $tmp 'disk-a'),(Join-Path $tmp 'disk-b\DarkWar'),(Join-Path $tmp 'disk-b'),(Join-Path $tmp 'local\DarkWarMulti\credentials'),(Join-Path $tmp 'local\DarkWarMulti'),(Join-Path $tmp 'local'),$tmp)){if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -ErrorAction SilentlyContinue}}
}
