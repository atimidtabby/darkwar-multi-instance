param([switch]$TestMode,[switch]$HideConsole)
$ErrorActionPreference='Stop'
if($HideConsole){
 Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class DarkWarConsoleWindow { [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command); }'
 $consoleWindow=[DarkWarConsoleWindow]::GetConsoleWindow();if($consoleWindow -ne [IntPtr]::Zero){[void][DarkWarConsoleWindow]::ShowWindow($consoleWindow,0)}
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$systemModules=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
$env:PSModulePath="$systemModules;$env:PSModulePath"
$localAccountsRoot=Join-Path $systemModules 'Microsoft.PowerShell.LocalAccounts'
$localAccountsManifest=Get-ChildItem -LiteralPath $localAccountsRoot -Filter 'Microsoft.PowerShell.LocalAccounts.psd1' -File -Recurse -ErrorAction Stop | Sort-Object FullName -Descending | Select-Object -First 1
if(!$localAccountsManifest){throw '未找到 Windows 本机账号管理模块，请使用 64 位 Windows PowerShell。'}
Import-Module $localAccountsManifest.FullName -ErrorAction Stop
Add-Type -AssemblyName System.Security
$sharedRoot=Join-Path ([Environment]::GetFolderPath('CommonDocuments')) 'DarkWarMulti'
$privateRoot=Join-Path $env:LOCALAPPDATA 'DarkWarMulti'
$stateFile=Join-Path $privateRoot 'instances.json'
$credentialRoot=Join-Path $privateRoot 'credentials'
New-Item -ItemType Directory -Force -Path $sharedRoot,$privateRoot,$credentialRoot | Out-Null
$state=@{Instances=[Collections.ArrayList]::new();GameExe='';TestMode=[bool]$TestMode;TestNextId=0;TestRemark=''}
if(Test-Path -LiteralPath $stateFile){$saved=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json;if($saved.gameExe){$state.GameExe=[string]$saved.gameExe};foreach($entry in @($saved.instances)){if($entry -and $entry.id -and $entry.user){[void]$state.Instances.Add($entry)}}}
$save={ $obj=@{instances=@($state.Instances.ToArray());gameExe=$state.GameExe};[IO.File]::WriteAllText($stateFile,($obj | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true)) }.GetNewClosure()
function Resolve-DarkWarGamePath([string]$path){
 $candidate=[Environment]::ExpandEnvironmentVariables(([string]$path).Trim().Trim('"'))
 if(!$candidate -or ![IO.Path]::IsPathRooted($candidate) -or !(Test-Path -LiteralPath $candidate -PathType Leaf)){throw '请输入或选择现有的游戏程序完整路径。'}
 $file=Get-Item -LiteralPath $candidate -ErrorAction Stop;$folder=$file.DirectoryName
 if($file.Name -ine 'DarkWar.exe' -or !(Test-Path -LiteralPath (Join-Path $folder 'DarkWar_Data') -PathType Container) -or !(Test-Path -LiteralPath (Join-Path $folder 'UnityPlayer.dll') -PathType Leaf)){throw '请选择 Game 文件夹内与 DarkWar_Data 同级的 DarkWar.exe。'}
 return $file.FullName
}
$gameSearchScript={param($options)
 $roots=@($options.Roots);$includeRunning=[bool]$options.IncludeRunning
 $ErrorActionPreference='SilentlyContinue'
 if($includeRunning){foreach($process in @(Get-CimInstance Win32_Process -Filter "Name='DarkWar.exe'")){if($process.ExecutablePath){Write-Output ([string]$process.ExecutablePath)}}}
 $visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($root in $roots){if(!$root -or !(Test-Path -LiteralPath $root -PathType Container)){continue};$pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
  while($pending.Count){$dir=$pending.Pop();if(!$visited.Add($dir)){continue};try{foreach($file in [IO.Directory]::EnumerateFiles($dir,'DarkWar.exe')){Write-Output $file}}catch{}
   try{foreach($child in [IO.Directory]::EnumerateDirectories($dir)){try{$info=[IO.DirectoryInfo]::new($child);if($info.Attributes -band [IO.FileAttributes]::ReparsePoint){continue};if($info.Name -in @('$Recycle.Bin','System Volume Information','Windows','Windows.old','DarkWarMulti')){continue};$pending.Push($child)}catch{}}}catch{}
  }
 }
}
function Start-DarkWarGameSearch([string[]]$roots,[bool]$includeRunning){$options=@{Roots=$roots;IncludeRunning=$includeRunning};return Start-Job -ScriptBlock $gameSearchScript -ArgumentList $options}
function Get-DarkWarProfilePath([string]$userName){
 $user=Get-LocalUser -Name $userName -ErrorAction SilentlyContinue
 if(!$user){return ''};$sid=$user.SID.Value
 $profile=Get-CimInstance Win32_UserProfile -Filter "SID='$sid'" -ErrorAction SilentlyContinue
 if(!$profile -or !$profile.LocalPath){return ''}
 return (Join-Path $profile.LocalPath 'AppData\LocalLow\READYGO\DarkWar')
}
function Prepare-DarkWarSlot([int]$id,[string]$exe){
 if(!$exe -or !(Test-Path -LiteralPath $exe -PathType Leaf)){throw '请先选择 Game 文件夹内的 DarkWar.exe。'}
 $source=Split-Path -Parent (Get-Item -LiteralPath $exe).FullName
 $slot=Join-Path $sharedRoot "slot-$id";$processName="DarkWarSlot$id"
 if(Get-Process -Name $processName -ErrorAction SilentlyContinue){throw '此实例已经在运行。'}
 $files=@('DarkWar.exe','GameAssembly.dll','UnityPlayer.dll','baselib.dll','UnityCrashHandler64.exe')
 $fingerprint=foreach($name in $files){$file=Get-Item -LiteralPath (Join-Path $source $name) -ErrorAction Stop;"$($file.Length)-$($file.LastWriteTimeUtc.Ticks)"}
 $sha=[Security.Cryptography.SHA256]::Create();try{$digest=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($fingerprint -join '|')));$version=([BitConverter]::ToString($digest)).Replace('-','').Substring(0,16)}finally{$sha.Dispose()}
 $master=Join-Path $sharedRoot "shared\$version";New-Item -ItemType Directory -Path $master,$slot -Force | Out-Null
 foreach($name in $files){
  $src=Join-Path $source $name;$cached=Join-Path $master $name;$destName=if($name -eq 'DarkWar.exe'){"$processName.exe"}else{$name};$dest=Join-Path $slot $destName
  if(!(Test-Path -LiteralPath $cached -PathType Leaf)){Copy-Item -LiteralPath $src -Destination $cached}
  $sourceFile=Get-Item -LiteralPath $cached;$destFile=Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue
  if($destFile -and ($destFile.Length -ne $sourceFile.Length -or $destFile.LastWriteTimeUtc -ne $sourceFile.LastWriteTimeUtc)){Remove-Item -LiteralPath $dest -Force;$destFile=$null}
  if(!$destFile){try{New-Item -ItemType HardLink -Path $dest -Target $cached -ErrorAction Stop | Out-Null}catch{Copy-Item -LiteralPath $cached -Destination $dest}}
 }
 $marker=Join-Path $slot '.game-source.txt';$oldSource=if(Test-Path -LiteralPath $marker){[IO.File]::ReadAllText($marker).Trim()}else{''}
 foreach($pair in @(@("${processName}_Data",'DarkWar_Data'),@('config','config'))){$link=Join-Path $slot $pair[0];$target=Join-Path $source $pair[1];if(!(Test-Path -LiteralPath $target -PathType Container)){throw "游戏目录不完整：$target"};if(Test-Path -LiteralPath $link){$item=Get-Item -LiteralPath $link -Force;if(!($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "实例目录存在不匹配的文件夹：$link"};if(@($item.Target) -notcontains $target){$oldTarget=if($oldSource){Join-Path $oldSource $pair[1]}else{''};if(!$oldTarget -or @($item.Target) -notcontains $oldTarget){throw "实例链接不匹配，请检查：$link"};[IO.Directory]::Delete($link);New-Item -ItemType Junction -Path $link -Target $target | Out-Null}}else{New-Item -ItemType Junction -Path $link -Target $target | Out-Null}}
 [IO.File]::WriteAllText($marker,$source,[Text.UTF8Encoding]::new($false))
 return $slot
}
function New-DarkWarPassword {
 $bytes=New-Object byte[] 32;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes)}finally{$rng.Dispose()};$plain=([Convert]::ToBase64String($bytes))+'aA1!';$secure=[Security.SecureString]::new();foreach($char in $plain.ToCharArray()){$secure.AppendChar($char)};$secure.MakeReadOnly();$encoded=[Text.Encoding]::UTF8.GetBytes($plain);try{$encrypted=[Security.Cryptography.ProtectedData]::Protect($encoded,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)}finally{[Array]::Clear($bytes,0,$bytes.Length);[Array]::Clear($encoded,0,$encoded.Length);$plain=$null};return @{Secure=$secure;Encrypted=$encrypted}
}
function Read-DarkWarPassword([string]$path){$protected=[IO.File]::ReadAllBytes($path);$bytes=[Security.Cryptography.ProtectedData]::Unprotect($protected,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser);try{$chars=[Text.Encoding]::UTF8.GetChars($bytes);$secure=[Security.SecureString]::new();foreach($char in $chars){$secure.AppendChar($char)};$secure.MakeReadOnly();return $secure}finally{[Array]::Clear($bytes,0,$bytes.Length);if($chars){[Array]::Clear($chars,0,$chars.Length)}}}
function Get-DarkWarManagedUser($entry){
 $id=[int]$entry.id;$name=[string]$entry.user
 if($id -lt 2 -or $name -cne "DWSlot$id"){throw '实例账号与编号不匹配，已停止操作。'}
 $user=Get-LocalUser -Name $name -ErrorAction SilentlyContinue
 if(!$user){return $null}
 if($user.Description -cne "DarkWar isolated instance $id"){throw '账号标识不匹配，已停止操作。'}
 if($entry.PSObject.Properties['sid'] -and $entry.sid -and $entry.sid -cne $user.SID.Value){throw '账号 SID 已变化，已停止操作。'}
 return $user
}
# Recover only accounts created by this manager and backed by a decryptable credential.
$recovered=0
foreach($candidateUser in @(Get-LocalUser | Where-Object {$_.Name -cmatch '^DWSlot([2-9]|[1-9][0-9]+)$'})){
 $recoveryId=[int]$candidateUser.Name.Substring(6);$known=@($state.Instances | Where-Object {[int]$_.id -eq $recoveryId -or [string]$_.user -eq $candidateUser.Name})
 if($known.Count -or $candidateUser.Description -cne "DarkWar isolated instance $recoveryId"){continue}
 $credential=Join-Path $credentialRoot "$($candidateUser.Name).bin";if(!(Test-Path -LiteralPath $credential -PathType Leaf)){continue}
 try{$proof=Read-DarkWarPassword $credential;if(!$proof.Length){continue};$proof.Dispose()}catch{continue}
 [void]$state.Instances.Add([pscustomobject]@{id=$recoveryId;user=$candidateUser.Name;sid=$candidateUser.SID.Value;remark=''});$recovered++
}
if($recovered){& $save}
function Show-DarkWarRemark([string]$title,[string]$initial){
 $dialog=[Windows.Forms.Form]::new();$dialog.Text=$title;$dialog.StartPosition='CenterParent';$dialog.FormBorderStyle='FixedDialog';$dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false;$dialog.ClientSize=[Drawing.Size]::new(390,120)
 $label=[Windows.Forms.Label]::new();$label.Text='备注（可留空）';$label.Location=[Drawing.Point]::new(12,12);$label.AutoSize=$true;$dialog.Controls.Add($label)
 $text=[Windows.Forms.TextBox]::new();$text.Location=[Drawing.Point]::new(15,38);$text.Width=360;$text.MaxLength=100;$text.Text=$initial;$dialog.Controls.Add($text)
 $ok=[Windows.Forms.Button]::new();$ok.Text='确定';$ok.Location=[Drawing.Point]::new(215,78);$ok.DialogResult='OK';$dialog.Controls.Add($ok);$dialog.AcceptButton=$ok
 $cancel=[Windows.Forms.Button]::new();$cancel.Text='取消';$cancel.Location=[Drawing.Point]::new(300,78);$cancel.DialogResult='Cancel';$dialog.Controls.Add($cancel);$dialog.CancelButton=$cancel
 try{$result=$dialog.ShowDialog($form);return [pscustomobject]@{Accepted=($result -eq [Windows.Forms.DialogResult]::OK);Text=$text.Text.Trim()}}finally{$dialog.Dispose()}
}
function Show-DarkWarGameChooser([string]$initial){
 $dialog=[Windows.Forms.Form]::new();$dialog.Text='选择游戏程序';$dialog.StartPosition='CenterParent';$dialog.ClientSize=[Drawing.Size]::new(520,300);$dialog.MinimumSize=[Drawing.Size]::new(500,320)
 $label=[Windows.Forms.Label]::new();$label.Text='手动选择游戏客户端';$label.AutoSize=$true;$label.Location=[Drawing.Point]::new(15,12);$dialog.Controls.Add($label)
 $path=[Windows.Forms.TextBox]::new();$path.Location=[Drawing.Point]::new(15,36);$path.Size=[Drawing.Size]::new(435,25);$path.Anchor='Top,Left,Right';$path.Text=$initial;$dialog.Controls.Add($path)
 $browse=[Windows.Forms.Button]::new();$browse.Text='📁';$browse.Font=[Drawing.Font]::new('Segoe UI Emoji',10);$browse.Location=[Drawing.Point]::new(460,34);$browse.Size=[Drawing.Size]::new(45,28);$browse.Anchor='Top,Right';$browse.AccessibleName='浏览游戏程序';$dialog.Controls.Add($browse)
 $searchLabel=[Windows.Forms.Label]::new();$searchLabel.Text='自动搜索游戏客户端';$searchLabel.AutoSize=$true;$searchLabel.Location=[Drawing.Point]::new(15,73);$dialog.Controls.Add($searchLabel)
 $search=[Windows.Forms.Button]::new();$search.Text='自动搜索';$search.Location=[Drawing.Point]::new(15,96);$search.AutoSize=$true;$dialog.Controls.Add($search)
 $progress=[Windows.Forms.Label]::new();$progress.Text='搜索运行中的游戏和本机磁盘。';$progress.Location=[Drawing.Point]::new(110,102);$progress.Size=[Drawing.Size]::new(395,23);$progress.Anchor='Top,Left,Right';$progress.AutoEllipsis=$true;$dialog.Controls.Add($progress)
 $results=[Windows.Forms.ListBox]::new();$results.Location=[Drawing.Point]::new(15,130);$results.Size=[Drawing.Size]::new(490,110);$results.Anchor='Top,Bottom,Left,Right';$results.HorizontalScrollbar=$true;$dialog.Controls.Add($results)
 $ok=[Windows.Forms.Button]::new();$ok.Text='确定';$ok.Location=[Drawing.Point]::new(335,255);$ok.Size=[Drawing.Size]::new(80,30);$ok.Anchor='Bottom,Right';$dialog.Controls.Add($ok)
 $cancel=[Windows.Forms.Button]::new();$cancel.Text='关闭';$cancel.Location=[Drawing.Point]::new(425,255);$cancel.Size=[Drawing.Size]::new(80,30);$cancel.Anchor='Bottom,Right';$cancel.DialogResult='Cancel';$dialog.Controls.Add($cancel);$dialog.CancelButton=$cancel
 $scan=@{Job=$null;Paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);Selected=''}
 $timer=[Windows.Forms.Timer]::new();$timer.Interval=300
 $timer.Add_Tick(({if(!$scan.Job){return};foreach($candidate in @(Receive-Job -Job $scan.Job -ErrorAction SilentlyContinue)){try{$valid=Resolve-DarkWarGamePath ([string]$candidate);if($scan.Paths.Add($valid)){[void]$results.Items.Add($valid);$progress.Text="正在搜索，已找到 $($results.Items.Count) 个游戏客户端。"}}catch{}};if($scan.Job.State -in @('Completed','Failed','Stopped')){$failed=$scan.Job.State -eq 'Failed';Remove-Job -Job $scan.Job -Force -ErrorAction SilentlyContinue;$scan.Job=$null;$search.Enabled=$true;if($failed){$progress.Text='搜索未能完成，可手动选择或重新搜索。'}else{$progress.Text="搜索结束，找到 $($results.Items.Count) 个游戏客户端。"}}}).GetNewClosure())
 $browse.Add_Click(({$picker=[Windows.Forms.OpenFileDialog]::new();$picker.Title='选择 Game 文件夹内的 DarkWar.exe';$picker.Filter='DarkWar 游戏程序 (DarkWar.exe)|DarkWar.exe|可执行文件 (*.exe)|*.exe';$picker.CheckFileExists=$true;try{if($picker.ShowDialog($dialog) -eq 'OK'){$path.Text=$picker.FileName}}finally{$picker.Dispose()}}).GetNewClosure())
 $search.Add_Click(({try{if($scan.Job){return};$results.Items.Clear();$scan.Paths.Clear();$search.Enabled=$false;$progress.Text='正在搜索本机磁盘和运行中的游戏…';$roots=@([IO.DriveInfo]::GetDrives() | Where-Object {$_.IsReady -and $_.DriveType -eq [IO.DriveType]::Fixed} | ForEach-Object {$_.RootDirectory.FullName});$scan.Job=Start-DarkWarGameSearch $roots $true;$timer.Start()}catch{$search.Enabled=$true;$progress.Text='无法启动搜索，请手动选择。'}}).GetNewClosure())
 $results.Add_SelectedIndexChanged(({if($results.SelectedItem){$path.Text=[string]$results.SelectedItem}}).GetNewClosure())
 $results.Add_DoubleClick(({if($results.SelectedItem){$ok.PerformClick()}}).GetNewClosure())
 $ok.Add_Click(({try{$scan.Selected=Resolve-DarkWarGamePath $path.Text;$dialog.DialogResult='OK';$dialog.Close()}catch{[Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'选择游戏程序')|Out-Null}}).GetNewClosure())
 try{if($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){return [pscustomobject]@{Accepted=$true;Path=$scan.Selected}};return [pscustomobject]@{Accepted=$false;Path=''}}
 finally{$timer.Stop();$timer.Dispose();if($scan.Job){Stop-Job -Job $scan.Job -ErrorAction SilentlyContinue;Remove-Job -Job $scan.Job -Force -ErrorAction SilentlyContinue};$dialog.Dispose()}
}
function Get-DarkWarDeletionPlan($entry){
 $user=Get-DarkWarManagedUser $entry;$id=[int]$entry.id;$name=[string]$entry.user
 if($user){$sid=$user.SID.Value}else{
  if(!$entry.PSObject.Properties['sid'] -or !$entry.sid){throw '账号已不存在且缺少原始 SID，不能自动删除。'}
  try{$savedSid=[Security.Principal.SecurityIdentifier]::new([string]$entry.sid);$localAccount=@(Get-LocalUser | Where-Object {$_.SID.AccountDomainSid} | Select-Object -First 1);if(!$localAccount.Count -or !$savedSid.AccountDomainSid -or $savedSid.AccountDomainSid.Value -ne $localAccount[0].SID.AccountDomainSid.Value -or $savedSid.Value -notmatch '-[1-9][0-9]{3,}$'){throw 'SID 不属于本机实例账号'};$sid=$savedSid.Value}catch{throw '原始账号 SID 无效，不能自动删除。'}
 }
 if($sid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw '不能删除当前 Windows 用户。'}
 if(Get-Process -Name "DarkWarSlot$id" -ErrorAction SilentlyContinue){throw '实例仍在运行，请先关闭对应的游戏窗口。'}
 $credential=Join-Path $credentialRoot "$name.bin";$hasCredential=Test-Path -LiteralPath $credential -PathType Leaf
 if($hasCredential){try{$proof=Read-DarkWarPassword $credential;if(!$proof.Length){throw '凭据为空'};$proof.Dispose()}catch{throw '隔离实例凭据无法验证，不能自动删除。'}}elseif($user){throw '找不到隔离实例的加密凭据，不能自动删除。'}
 $profile=Get-CimInstance Win32_UserProfile -Filter "SID='$sid'" -ErrorAction Stop
 if(!$user -and $profile -and !$hasCredential){throw '账号已不存在但仍有用户配置文件且缺少凭据，不能自动删除。'}
 $profilePath='';if($profile){
  if($profile.Loaded -or $profile.Special){throw '此 Windows 用户配置文件正在使用或属于系统配置文件，无法删除。'}
  $profilesSetting=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -Name ProfilesDirectory).ProfilesDirectory
  $profilesRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($profilesSetting)).TrimEnd('\')
  $profilesItem=Get-Item -LiteralPath $profilesRoot -Force -ErrorAction Stop;if($profilesItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Windows 用户目录是链接，已停止删除。'}
  $profilePath=[IO.Path]::GetFullPath([string]$profile.LocalPath).TrimEnd('\');$prefix=$profilesRoot+'\'
  if(!$profilePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $profilePath.Substring($prefix.Length).Contains('\')){throw '配置文件路径不在标准用户目录内，已停止删除。'}
  $leaf=[IO.Path]::GetFileName($profilePath);if($leaf -ine $name -and !$leaf.StartsWith($name+'.',[StringComparison]::OrdinalIgnoreCase)){throw '配置文件目录与账号不匹配，已停止删除。'}
  if(Test-Path -LiteralPath $profilePath){$profileItem=Get-Item -LiteralPath $profilePath -Force;if($profileItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '配置文件目录是链接，已停止删除。'}}
 }
 $root=[IO.Path]::GetFullPath($sharedRoot).TrimEnd('\');$slot=[IO.Path]::GetFullPath((Join-Path $root "slot-$id")).TrimEnd('\')
 if(!$slot.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or $slot -ine (Join-Path $root "slot-$id")){throw '实例目录路径不安全，已停止删除。'}
 $files=@("DarkWarSlot$id.exe",'GameAssembly.dll','UnityPlayer.dll','baselib.dll','UnityCrashHandler64.exe','.game-source.txt');$links=@("DarkWarSlot${id}_Data",'config')
 if(Test-Path -LiteralPath $slot){$slotItem=Get-Item -LiteralPath $slot -Force;if($slotItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '实例目录是链接，已停止删除。'};foreach($item in @(Get-ChildItem -LiteralPath $slot -Force)){
  if($links -contains $item.Name){if(!$item.PSIsContainer -or !($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "实例链接异常，已停止删除：$($item.FullName)"}}
  elseif($files -contains $item.Name){if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "实例文件异常，已停止删除：$($item.FullName)"}}
  else{throw "实例目录包含未知文件，请先检查：$($item.FullName)"}
 }}
 return [pscustomobject]@{User=$user;Sid=$sid;Profile=$profile;ProfilePath=$profilePath;Slot=$slot;Credential=$credential;Files=$files;Links=$links}
}
function Remove-DarkWarInstance($plan){
 # Unlink only the known junctions; never recurse into shared game files.
 if(Test-Path -LiteralPath $plan.Slot){foreach($name in $plan.Links){$link=Join-Path $plan.Slot $name;if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link)}};foreach($name in $plan.Files){$file=Join-Path $plan.Slot $name;if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force -ErrorAction Stop}};[IO.Directory]::Delete($plan.Slot)}
 if($plan.Profile){Remove-CimInstance -InputObject $plan.Profile -ErrorAction Stop}
 if($plan.User){Remove-LocalUser -SID $plan.User.SID -ErrorAction Stop}
 if(Test-Path -LiteralPath $plan.Credential -PathType Leaf){Remove-Item -LiteralPath $plan.Credential -Force -ErrorAction Stop}
}
function Get-DarkWarBatchPlans($entries){
 $result=[Collections.Generic.List[object]]::new()
 foreach($entry in $entries){try{$plan=Get-DarkWarDeletionPlan $entry;$result.Add([pscustomobject]@{Entry=$entry;Plan=$plan})}catch{$remark='';if($entry.PSObject.Properties['remark']){$remark=[string]$entry.remark};if(!$remark){$remark='无备注'};throw "实例 $($entry.id)（$remark）：$($_.Exception.Message)"}}
 return $result.ToArray()
}
function Format-DarkWarDeletionList($items){
 $parts=[Collections.Generic.List[string]]::new()
 foreach($item in $items){$entry=$item.Entry;$remark='';if($entry.PSObject.Properties['remark']){$remark=([string]$entry.remark -replace '[\r\n]+',' ').Trim()};if(!$remark){$remark='无备注'};$profile=if($item.Plan.ProfilePath){$item.Plan.ProfilePath}else{'用户配置文件不存在'};$accountSuffix=if($item.Plan.PSObject.Properties['User'] -and !$item.Plan.User){'（账号已不存在）'}else{''};$parts.Add("实例 $($entry.id) — 备注：$remark`r`nWindows 账号：$($entry.user)$accountSuffix`r`n用户配置文件：$profile")}
 return $parts -join "`r`n`r`n"
}
function Show-DarkWarDeleteConfirmation($items){
 $dialog=[Windows.Forms.Form]::new();$dialog.Text='确认删除实例和数据';$dialog.StartPosition='CenterParent';$dialog.Size=[Drawing.Size]::new(760,520);$dialog.MinimumSize=[Drawing.Size]::new(600,400)
 $warning=[Windows.Forms.Label]::new();$warning.Text="将永久删除以下 $($items.Count) 个实例的 Windows 本机账号、完整用户配置文件、实例专用程序链接和凭据。此操作无法撤销。共享游戏安装目录和其他实例不会删除。";$warning.Location=[Drawing.Point]::new(15,15);$warning.Size=[Drawing.Size]::new(710,58);$warning.Anchor='Top,Left,Right';$dialog.Controls.Add($warning)
 $details=[Windows.Forms.TextBox]::new();$details.Multiline=$true;$details.ReadOnly=$true;$details.ScrollBars='Both';$details.WordWrap=$false;$details.Location=[Drawing.Point]::new(18,80);$details.Size=[Drawing.Size]::new(707,342);$details.Anchor='Top,Bottom,Left,Right';$details.Text=Format-DarkWarDeletionList $items;$dialog.Controls.Add($details)
 $ok=[Windows.Forms.Button]::new();$ok.Text='确定删除';$ok.Location=[Drawing.Point]::new(540,435);$ok.Size=[Drawing.Size]::new(90,30);$ok.Anchor='Bottom,Right';$ok.DialogResult='OK';$dialog.Controls.Add($ok)
 $cancel=[Windows.Forms.Button]::new();$cancel.Text='取消';$cancel.Location=[Drawing.Point]::new(635,435);$cancel.Size=[Drawing.Size]::new(90,30);$cancel.Anchor='Bottom,Right';$cancel.DialogResult='Cancel';$dialog.Controls.Add($cancel);$dialog.AcceptButton=$cancel;$dialog.CancelButton=$cancel
 try{return $dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK}finally{$dialog.Dispose()}
}
$form=[Windows.Forms.Form]::new();$form.Text='DarkWar 多开管理器 v1.0.0';$form.StartPosition='CenterScreen';$form.Size=[Drawing.Size]::new(1050,530);$form.MinimumSize=[Drawing.Size]::new(850,400);$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',9)
$top=[Windows.Forms.FlowLayoutPanel]::new();$top.Dock='Top';$top.Height=75;$top.WrapContents=$true
$chooseGame=[Windows.Forms.Button]::new();$chooseGame.Text='选择游戏程序';$chooseGame.AutoSize=$true;$top.Controls.Add($chooseGame)
$gameLabel=[Windows.Forms.Label]::new();$gameLabel.Width=700;$gameLabel.Height=25;$gameLabel.AutoEllipsis=$true;$gameLabel.Text=if($state.GameExe){"游戏：$($state.GameExe)"}else{'请选择 Game 文件夹内的 DarkWar.exe'};$gameLabel.Margin=[Windows.Forms.Padding]::new(5,8,5,0);$top.Controls.Add($gameLabel);$top.SetFlowBreak($gameLabel,$true)
$create=[Windows.Forms.Button]::new();$create.Text='新建隔离实例';$create.AutoSize=$true;$top.Controls.Add($create)
$start=[Windows.Forms.Button]::new();$start.Text='启动选中实例';$start.AutoSize=$true;$top.Controls.Add($start)
$open=[Windows.Forms.Button]::new();$open.Text='打开数据文件夹';$open.AutoSize=$true;$top.Controls.Add($open)
$deleteButton=[Windows.Forms.Button]::new();$deleteButton.Text='删除实例';$deleteButton.AutoSize=$true;$top.Controls.Add($deleteButton)
$refreshButton=[Windows.Forms.Button]::new();$refreshButton.Text='刷新';$refreshButton.AutoSize=$true;$top.Controls.Add($refreshButton)
$view=[Windows.Forms.ListView]::new();$view.Dock='Fill';$view.View='Details';$view.FullRowSelect=$true;$view.MultiSelect=$true;$view.GridLines=$true;$view.HideSelection=$false
foreach($column in @(@('实例',65),@('备注',145),@('Windows 账号',130),@('状态',90),@('游戏数据文件夹',510),@('程序文件夹',350))){[void]$view.Columns.Add([string]$column[0],[int]$column[1])}
$doubleBuffered=$view.GetType().GetProperty('DoubleBuffered',[Reflection.BindingFlags]'Instance,NonPublic');if($doubleBuffered){$doubleBuffered.SetValue($view,$true,$null)}
$context=[Windows.Forms.ContextMenuStrip]::new();$editRemark=[Windows.Forms.ToolStripMenuItem]::new('编辑备注');$deleteMenu=[Windows.Forms.ToolStripMenuItem]::new('删除实例和数据');[void]$context.Items.Add($editRemark);[void]$context.Items.Add($deleteMenu);$view.ContextMenuStrip=$context
$view.Add_MouseDown(({param($sender,$event) if($event.Button -eq [Windows.Forms.MouseButtons]::Right){$hit=$view.GetItemAt($event.X,$event.Y);if($hit){if(!$hit.Selected){$view.SelectedItems.Clear();$hit.Selected=$true};$hit.Focused=$true}else{$view.SelectedItems.Clear()}}}).GetNewClosure())
$context.Add_Opening(({param($sender,$event) if(!$view.SelectedItems.Count){$event.Cancel=$true}else{$editRemark.Enabled=$view.SelectedItems.Count -eq 1}}).GetNewClosure())
$note=[Windows.Forms.Label]::new();$note.Dock='Bottom';$note.Height=65;$note.Text='每个隔离实例使用独立的非管理员 Windows 本机账号。首次启动后，请在游戏窗口登录另一个游戏账号。数据路径在首次启动生成配置文件后显示。';$note.Padding=[Windows.Forms.Padding]::new(5);$note.AutoEllipsis=$true
$form.Controls.Add($view);$form.Controls.Add($note);$form.Controls.Add($top);$form.Controls.SetChildIndex($view,0);$form.Controls.SetChildIndex($note,1);$form.Controls.SetChildIndex($top,2)
$refresh={
 $entries=@($state.Instances | Sort-Object {[int]$_.id});$same=$view.Items.Count -eq $entries.Count
 if($same){for($i=0;$i -lt $entries.Count;$i++){if([int]$view.Items[$i].Tag.id -ne [int]$entries[$i].id){$same=$false;break}}}
 $selectedIds=@{};if(!$same){foreach($selected in $view.SelectedItems){$selectedIds[[int]$selected.Tag.id]=$true}}
 if(!$same){$view.BeginUpdate();$view.Items.Clear()}
 try{for($i=0;$i -lt $entries.Count;$i++){$entry=$entries[$i];$id=[int]$entry.id;$path=Get-DarkWarProfilePath $entry.user;if(!$path){$path='首次启动后生成'};$running=if(Get-Process -Name "DarkWarSlot$id" -ErrorAction SilentlyContinue){'运行中'}else{'未运行'};$remark='';if($entry.PSObject.Properties['remark']){$remark=[string]$entry.remark};$values=@("实例 $id",$remark,[string]$entry.user,$running,$path,(Join-Path $sharedRoot "slot-$id"))
  if($same){$item=$view.Items[$i];$item.Tag=$entry;for($j=0;$j -lt $values.Count;$j++){if($item.SubItems[$j].Text -cne $values[$j]){$item.SubItems[$j].Text=$values[$j]}}}
  else{$item=[Windows.Forms.ListViewItem]::new($values[0]);$item.Tag=$entry;for($j=1;$j -lt $values.Count;$j++){[void]$item.SubItems.Add($values[$j])};[void]$view.Items.Add($item);if($selectedIds.ContainsKey($id)){$item.Selected=$true}}
 }}finally{if(!$same){$view.EndUpdate()}}
}.GetNewClosure()
$chooseGame.Add_Click(({
 try{$answer=Show-DarkWarGameChooser $state.GameExe;if($answer.Accepted){$state.GameExe=$answer.Path;& $save;$gameLabel.Text="游戏：$($state.GameExe)"}}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'DarkWar 多开')|Out-Null}
}).GetNewClosure())
$create.Add_Click(({
 $created=$null
 try{
  $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent());if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '创建隔离账号需要管理员权限，请右键多开管理器.exe，选择以管理员身份运行。'}
  $id=2;if($state.TestMode -and $state.TestNextId){$id=[int]$state.TestNextId};while(($state.Instances | Where-Object {[int]$_.id -eq $id}) -or (Get-LocalUser -Name "DWSlot$id" -ErrorAction SilentlyContinue)){$id++}
  $remark=if($state.TestMode){[pscustomobject]@{Accepted=$true;Text=$state.TestRemark}}else{Show-DarkWarRemark '新建实例备注' ''};if(!$remark.Accepted){return}
  $userName="DWSlot$id";$password=New-DarkWarPassword
  $created=New-LocalUser -Name $userName -Password $password.Secure -PasswordNeverExpires -Description "DarkWar isolated instance $id"
  $users=Get-LocalGroup -SID 'S-1-5-32-545';Add-LocalGroupMember -Group $users.Name -Member $userName
  [IO.File]::WriteAllBytes((Join-Path $credentialRoot "$userName.bin"),$password.Encrypted)
  [void]$state.Instances.Add([pscustomobject]@{id=$id;user=$userName;sid=$created.SID.Value;remark=$remark.Text});& $save;& $refresh
  foreach($item in $view.Items){if([int]$item.Tag.id -eq $id){$item.Selected=$true;$item.Focused=$true}}
  if(!$state.TestMode){[Windows.Forms.MessageBox]::Show("已创建实例 $id 和非管理员 Windows 本机账号 $userName。请选择它并点击启动。",'DarkWar 多开')|Out-Null}
 }catch{$message=$_.Exception.Message;if($created){Remove-LocalUser -SID $created.SID -ErrorAction SilentlyContinue;Remove-Item -LiteralPath (Join-Path $credentialRoot "$userName.bin") -ErrorAction SilentlyContinue;foreach($entry in @($state.Instances)){if([string]$entry.user -eq $userName){[void]$state.Instances.Remove($entry)}}};try{& $save}catch{};& $refresh;if($state.TestMode){throw "创建失败：$message"};[Windows.Forms.MessageBox]::Show("创建失败：$message",'DarkWar 多开')|Out-Null}
}).GetNewClosure())
$editRemark.Add_Click(({
 if($view.SelectedItems.Count -ne 1){return};$entry=$view.SelectedItems[0].Tag;$current='';if($entry.PSObject.Properties['remark']){$current=[string]$entry.remark}
 $answer=if($state.TestMode){[pscustomobject]@{Accepted=$true;Text=$state.TestRemark}}else{Show-DarkWarRemark '编辑实例备注' $current};if(!$answer.Accepted){return}
 if($entry.PSObject.Properties['remark']){$entry.remark=$answer.Text}else{$entry | Add-Member -NotePropertyName remark -NotePropertyValue $answer.Text}
 try{& $save;& $refresh}catch{[Windows.Forms.MessageBox]::Show("保存备注失败：$($_.Exception.Message)",'DarkWar 多开')|Out-Null}
}).GetNewClosure())
$deleteAction={
 if(!$view.SelectedItems.Count){[Windows.Forms.MessageBox]::Show('请先选择一个实例。')|Out-Null;return}
 $entries=@(foreach($item in $view.SelectedItems){$item.Tag});$completed=[Collections.Generic.List[string]]::new()
 try{
  $plans=@(Get-DarkWarBatchPlans $entries);if(!(Show-DarkWarDeleteConfirmation $plans)){return}
  $plans=@(Get-DarkWarBatchPlans $entries)
  foreach($item in $plans){$entry=$item.Entry;try{Remove-DarkWarInstance $item.Plan;[void]$state.Instances.Remove($entry);& $save;$completed.Add("实例 $($entry.id)")}catch{throw "实例 $($entry.id) 删除时出错，部分文件可能已删除：$($_.Exception.Message)"}}
  & $refresh;[Windows.Forms.MessageBox]::Show("已删除 $($completed.Count) 个实例。",'DarkWar 多开')|Out-Null
 }catch{& $refresh;$detail=if($completed.Count){"已完成：$($completed -join '、')。`r`n"}else{''};[Windows.Forms.MessageBox]::Show("${detail}删除未完成：$($_.Exception.Message)",'DarkWar 多开')|Out-Null}
}.GetNewClosure()
$deleteButton.Add_Click($deleteAction);$deleteMenu.Add_Click($deleteAction)
$start.Add_Click(({
 try{
  if($view.SelectedItems.Count -ne 1){[Windows.Forms.MessageBox]::Show('启动时请选择一个实例。')|Out-Null;return};$entry=$view.SelectedItems[0].Tag;$id=[int]$entry.id;$userName=[string]$entry.user
  $credentialFile=Join-Path $credentialRoot "$userName.bin";$legacyCredential=Join-Path $credentialRoot "$userName.txt";if(Test-Path -LiteralPath $credentialFile){$password=Read-DarkWarPassword $credentialFile}elseif(Test-Path -LiteralPath $legacyCredential){$password=Microsoft.PowerShell.Security\ConvertTo-SecureString (Get-Content -LiteralPath $legacyCredential -Raw)}else{throw '找不到此实例的本机账号凭据。'}
  $slot=Prepare-DarkWarSlot $id $state.GameExe
  $stamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();$token=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$stamp|DW"))
  $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $slot "DarkWarSlot$id.exe";$info.WorkingDirectory=$slot;$info.Arguments="--from-launcher=$token";$info.UseShellExecute=$false;$info.UserName=$userName;$info.Domain=$env:COMPUTERNAME;$info.Password=$password;$info.LoadUserProfile=$true
  $process=[Diagnostics.Process]::Start($info);if(!$process){throw '系统未返回游戏进程。'};Start-Sleep -Milliseconds 500;& $refresh
 }catch{[Windows.Forms.MessageBox]::Show("启动失败：$($_.Exception.Message)",'DarkWar 多开')|Out-Null}
}).GetNewClosure())
$open.Add_Click(({if($view.SelectedItems.Count -ne 1){[Windows.Forms.MessageBox]::Show('请先选择一个实例。')|Out-Null;return};$path=Get-DarkWarProfilePath ([string]$view.SelectedItems[0].Tag.user);if(!$path -or !(Test-Path -LiteralPath $path -PathType Container)){[Windows.Forms.MessageBox]::Show('游戏数据目录尚未创建；请先启动该实例。')|Out-Null;return};Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $path)}).GetNewClosure())
$refreshButton.Add_Click($refresh)
$timer=[Windows.Forms.Timer]::new();$timer.Interval=5000;$timer.Add_Tick($refresh);$timer.Start();$form.Add_FormClosed({$timer.Stop();$timer.Dispose()}.GetNewClosure());& $refresh
if($TestMode){$timer.Stop();return @{Form=$form;State=$state;View=$view;Refresh=$refresh;Save=$save;Start=$start;Create=$create;Open=$open;ChooseGame=$chooseGame;GameLabel=$gameLabel;Delete=$deleteButton;EditRemark=$editRemark;DeleteMenu=$deleteMenu;Timer=$timer}}
[void]$form.ShowDialog();$form.Dispose()

# SIG # Begin signature block
# MIIHSAYJKoZIhvcNAQcCoIIHOTCCBzUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDk1W/QECirtyac
# gnldN7C93yTFsYeEQNWE5xi9uwtXY6CCBCwwggQoMIICkKADAgECAhAR46BICY+q
# vUJquCi14ZHrMA0GCSqGSIb3DQEBCwUAMCwxKjAoBgNVBAMMIURhcmtXYXIgTXVs
# dGktSW5zdGFuY2UgTG9jYWwgVGVzdDAeFw0yNjExMDgxNTIwNTVaFw0yODExMDgx
# NTMwNTRaMCwxKjAoBgNVBAMMIURhcmtXYXIgTXVsdGktSW5zdGFuY2UgTG9jYWwg
# VGVzdDCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAMYHDLXdXjUURn/i
# l2YNttQ5mKHBVnNm/WJSsoUBxfPJ584ZSO0KcvDN6QO5tpSDdsZ7vR2ulObLiNGv
# ZAXKgpUQ3H4t3H+iNgAUbzi3+4I505aJnfL8J/9dKoLbmjVGJuyx1mrvGQV8vYvO
# yIwCbtkrmnyzbmYohNZHK/anmP5RLJXtA1bq2ccO2UZALRyQbL4bqVlumh9AYhJb
# nOaiW2KatQIsTYgpd3+Ld27POvYs1wG2v1d5tv1+7k08vAjpoHA6tFWvh/ULnvbr
# VWv8wMVyg25IR3ijI6fdSgl0gNSZnmHW60vkR5yDkEQXCqxPZGy6R6MnIRjgFAIq
# bb9BmiU6xSf0czW8z3WVk2G+/o62At0iTK1FmIyYvL7YrD/7q0QtxJ1MAoUqWK9O
# EJeKfrT5S13YQrnH1XX7WrElvXTSEXUh6R5VZKUsWHUswKnwRh6J8Im/rBEtDG8+
# 8PGPn1D1sbRPgITB9hSgsF54okST+KdoREuYF7JMLY9uPTfq+QIDAQABo0YwRDAO
# BgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFN5+
# tD4bimV05xHrJbLvlu8EpiH6MA0GCSqGSIb3DQEBCwUAA4IBgQAef2jr7eSITE/2
# 6FdcrwpdQUj0AZNibstMAjHQhnRH4ukNjETCYbgYK5uzBe9rRtGxdZ0npxSoY3iz
# xuOeO/ggnKW3jLxaXwDP3R4RNSnpz832Jo29P9s6H3dxlxHsQC6dAiHIbJ4m54P5
# o+3lf5MyraZxQCexOGKx7W0m1Smrw8p2Si2JJwPG6DtcSLE/xWBzInnMXa0TwFXD
# junSXIFUIcRhcOTqu+Tp4rirwnb4AZcFp8MNv9FJg/oXpTUfDHezg5itko/Vsl+t
# IIKcUMM2m4wyuuBtrZTd2TF0cDEkNos6khZ83ACkXbYtQJz3k8UwQYmHX2RNpt9F
# n80dHDbokoV6hnCDZ1EpD3f2W8c3/5JpGjxS654d1xTjJ72CDZPQWjH7DRUUDYIF
# gwFDjHrSMabILnhbv8kAgrsQgD21pXVNbhzSnTvjMPFfeibwLwNdTFb3sd6/LfNa
# tvurOILnCu2nhMICkAA8wF/HwMbqX7/uO7bl0jLLbU1WBD74+m4xggJyMIICbgIB
# ATBAMCwxKjAoBgNVBAMMIURhcmtXYXIgTXVsdGktSW5zdGFuY2UgTG9jYWwgVGVz
# dAIQEeOgSAmPqr1CargoteGR6zANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3
# AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisG
# AQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDaXdrzJ6zB
# tDpz9AYBePb0A0Lhfbk+/YGE4kZHLBU0UjANBgkqhkiG9w0BAQEFAASCAYAVU7dL
# SAcy4Vgo8PPHB0trFQrCVmzh4BEly08cP9g2jxryphQYwkCtHi4QCuhoqplcBvRi
# pOXtyFW67otC1/UkI9IQVK31Pre4XzQJPRcz8VYAwIVgGgEu8tKhAqeuX/zuLkAm
# fZP3YY3E1isQHjbhDsXnCUEJZ9tosWB1v8I83hcr4K+0A6lTHsarmzgRK67zQWD0
# AsNKQlmeGHcJtiUmQ+Ldd5bqNuz2iEaqthBfDloekjpkPqg9oRYJzhJK4kNOIE9l
# ThHSqLvvJV7iqWLdv8pt1ne6jmBpVwgUAaheOjXn9IV/4BFIFA8Ep2ErTOSWSrd+
# 8AviS99DSN39R+KIVfHiIhtLiK1tFetlLF6kRvt5cF3DWLdGAIgDBm8BZ5SW4G5s
# sYZrrkAR6LNByLaWB9zh88/OQz2l9rTAtjJFx35cfg++9cglrWjWUydgdR4VSvpb
# zR+gv2ija4au2n6+W83MZqjnwypTNdxt1iHLZTzLmlmWCuL5ZFWd4F1E2+Q=
# SIG # End signature block
