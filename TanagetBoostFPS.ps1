# =====================================================================
#   TANAGET BOOST FPS  v5.1  -  Purple FiveM Edition (Clay + GTA Tuning + Fixes)
#   - ปรับแต่ง Windows ให้เฟรมนิ่ง (เหมาะกับคอมสเปคอ่อน)
#   - Snapshot: เก็บค่าเดิมก่อนรัน แล้วย้อนกลับได้ตรงเป๊ะ
#   - RAM Cleaner: บีบแรมโปรเซสที่ไม่ได้ใช้ + ล้าง Standby (ไม่แตะเกมที่เล่นอยู่)
#   ใส่รูปพื้นหลังเองได้: วางไฟล์ bg.png หรือ bg.jpg ไว้โฟลเดอร์เดียวกับสคริปต์
# =====================================================================

# ---------- ลิงก์ Raw ของสคริปต์นี้ (ใส่ตอนอัปโหลดขึ้น Gist/GitHub เพื่อใช้กับ iex) ----------
$ScriptUrl = 'https://raw.githubusercontent.com/tanaget061-oss/tanaget-boost-fps/main/TanagetBoostFPS.ps1'   # ตัวอย่าง: 'https://gist.githubusercontent.com/USER/ID/raw/TanagetBoostFPS.ps1'

# ---------- ขอสิทธิ์ Admin อัตโนมัติ (รองรับทั้งรันจากไฟล์ และรันผ่าน iex) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($PSCommandPath) {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } elseif ($ScriptUrl) {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$ScriptUrl')`""
    } else {
        Write-Host 'กรุณาเปิด PowerShell แบบ Run as administrator แล้วรันคำสั่งใหม่ (หรือใส่ค่า $ScriptUrl ในสคริปต์)' -ForegroundColor Yellow
        Read-Host 'กด Enter เพื่อปิด'
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- แก้ปัญหาจอ Scale/DPI ทำให้ติ๊ก checkbox แล้วไม่ขึ้น ----------
try {
    Add-Type -Namespace TBF -Name Dpi -MemberDefinition '
        [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    ' -ErrorAction SilentlyContinue
    try { [void][TBF.Dpi]::SetProcessDpiAwareness(2) } catch { try { [void][TBF.Dpi]::SetProcessDPIAware() } catch {} }
} catch {}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

try {

# ---------- โค้ดเนทีฟ (ล้างแรม / อ่านแรม / ซ่อนคอนโซล) ----------
Add-Type -Language CSharp -ReferencedAssemblies 'System.Windows.Forms' -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class TbfNative
{
    [DllImport("psapi.dll")] static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int infoClass, IntPtr info, int length);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, int access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string host, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokPriv tp, int len, IntPtr prev, IntPtr retLen);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GlobalMemoryStatusEx(ref MemStatus s);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct TokPriv { public int Count; public long Luid; public int Attr; }

    [StructLayout(LayoutKind.Sequential)]
    struct MemStatus
    {
        public uint Length; public uint Load;
        public ulong TotalPhys; public ulong AvailPhys;
        public ulong TotalPage; public ulong AvailPage;
        public ulong TotalVirt; public ulong AvailVirt; public ulong AvailExt;
    }

    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    static long pIdle, pKernel, pUser;

    public static int Cpu()
    {
        long i, k, u;
        if (!GetSystemTimes(out i, out k, out u)) return 0;
        long di = i - pIdle, dk = k - pKernel, du = u - pUser;
        pIdle = i; pKernel = k; pUser = u;
        long total = dk + du;
        if (total <= 0) return 0;
        long pct = 100 - (di * 100 / total);
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        return (int)pct;
    }

    public static void HideConsole()
    {
        IntPtr h = GetConsoleWindow();
        if (h != IntPtr.Zero) ShowWindow(h, 0);
    }

    public static ulong[] Mem()
    {
        MemStatus s = new MemStatus();
        s.Length = (uint)Marshal.SizeOf(typeof(MemStatus));
        GlobalMemoryStatusEx(ref s);
        return new ulong[] { s.TotalPhys, s.AvailPhys };
    }

    public static int ForegroundPid()
    {
        int pid;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid;
    }

    static bool EnablePriv(string name)
    {
        IntPtr tok;
        if (!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x28, out tok)) return false;
        TokPriv tp = new TokPriv();
        tp.Count = 1;
        tp.Attr = 2;
        if (!LookupPrivilegeValue(null, name, out tp.Luid)) { CloseHandle(tok); return false; }
        bool r = AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        CloseHandle(tok);
        return r;
    }

    public static int Trim(int pid)
    {
        IntPtr h = OpenProcess(0x0500, false, pid);
        if (h == IntPtr.Zero) return 0;
        bool ok = EmptyWorkingSet(h);
        CloseHandle(h);
        return ok ? 1 : 0;
    }

    static int MemCmd(int cmd)
    {
        IntPtr p = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(p, cmd);
        int r = NtSetSystemInformation(80, p, 4);
        Marshal.FreeHGlobal(p);
        return r;
    }

    public static int FlushModified() { EnablePriv("SeProfileSingleProcessPrivilege"); return MemCmd(3); }
    public static int PurgeStandby()  { EnablePriv("SeProfileSingleProcessPrivilege"); return MemCmd(4); }
}

// ปุ่มลัดทั้งระบบ Ctrl+Alt+R (ใช้ล้างแรมตอนเล่นเกมอยู่)
public class TbfHotkey : NativeWindow, IDisposable
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event EventHandler Pressed;
    public bool Ok;

    public TbfHotkey()
    {
        CreateHandle(new CreateParams());
        Ok = RegisterHotKey(this.Handle, 1, 0x3, 0x52);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty);
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        UnregisterHotKey(this.Handle, 1);
        DestroyHandle();
    }
}
'@

# ---------- ตัวแปรหลัก ----------
$script:Here      = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Join-Path $env:APPDATA 'TanagetBoostFPS' }
$script:SnapDir   = Join-Path $env:APPDATA 'TanagetBoostFPS'
$script:SnapFile  = Join-Path $script:SnapDir 'snapshot.json'
$script:SetFile   = Join-Path $script:SnapDir 'settings.json'
$script:LastClean = [datetime]::MinValue

function Col($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
$script:cText  = Col '#EDE7FF'
$script:cDim   = Col '#A695D6'
$script:cAcc   = Col '#8B3DFF'
$script:cAcc2  = Col '#B983FF'
$script:cInput = Col '#0F0819'

# ---------- Registry helpers ----------
function Set-Reg($path, $name, $value, $type = 'DWord') {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}
function Remove-RegValue($path, $name) {
    if (Test-Path -LiteralPath $path) { Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue }
}
function Get-RegState($p, $n) {
    $k = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if ($k -and ($k.GetValueNames() -contains $n)) {
        return @{ P = $p; N = $n; Exists = $true; V = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames'); T = $k.GetValueKind($n).ToString() }
    }
    return @{ P = $p; N = $n; Exists = $false; V = $null; T = $null }
}
function Restore-RegState($e) {
    if ($e.Exists) {
        $v = $e.V
        if ($e.T -eq 'Binary') { $v = [byte[]]@($v) }
        elseif ($e.T -eq 'DWord') { $v = [int]$v }
        elseif ($e.T -eq 'QWord') { $v = [int64]$v }
        Set-Reg $e.P $e.N $v $e.T
    } else {
        Remove-RegValue $e.P $e.N
    }
}
function Has-Exe($e) { return [bool]($e -and (Test-Path -LiteralPath $e -PathType Leaf)) }

# ---------- Service helpers ----------
function Get-SvcState($name) {
    $s = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    $d = $false
    $k = Get-Item -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -ErrorAction SilentlyContinue
    if ($k -and ($k.GetValue('DelayedAutostart') -eq 1)) { $d = $true }
    return @{ Name = $name; Mode = $s.StartMode; Delayed = $d; Running = ($s.State -eq 'Running') }
}
function Set-SvcMode($name, $mode, $delayed) {
    $m = 'demand'
    if ($mode -eq 'Auto') { if ($delayed) { $m = 'delayed-auto' } else { $m = 'auto' } }
    elseif ($mode -eq 'Disabled') { $m = 'disabled' }
    sc.exe config $name start= $m | Out-Null
}

# ---------- Snapshot (เก็บค่าก่อนรัน) ----------
function Load-Snap {
    $s = @{ Time = $null; Regs = @(); Services = @(); Power = $null }
    if (Test-Path -LiteralPath $script:SnapFile) {
        try {
            $j = Get-Content -LiteralPath $script:SnapFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $s.Time = $j.Time
            foreach ($r in @($j.Regs)) { if ($r) { $s.Regs += @{ P = $r.P; N = $r.N; Exists = [bool]$r.Exists; V = $r.V; T = $r.T } } }
            foreach ($v in @($j.Services)) { if ($v) { $s.Services += @{ Name = $v.Name; Mode = $v.Mode; Delayed = [bool]$v.Delayed; Running = [bool]$v.Running } } }
            if ($j.Power) { $s.Power = @{ Guid = $j.Power.Guid } }
        } catch { }
    }
    return $s
}
function Save-Snap($s) {
    if (-not (Test-Path -LiteralPath $script:SnapDir)) { New-Item -ItemType Directory -Path $script:SnapDir -Force | Out-Null }
    $obj = @{ Time = $s.Time; Regs = @($s.Regs); Services = @($s.Services); Power = $s.Power }
    ConvertTo-Json -InputObject $obj -Depth 6 | Set-Content -LiteralPath $script:SnapFile -Encoding UTF8
}

# ---------- อ่านสเปคเครื่อง ----------
try {
    $cpuName = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
    $gpuName = (Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join ' + '
    $ramGB   = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
} catch { $cpuName = 'Unknown CPU'; $gpuName = 'Unknown GPU'; $ramGB = 8 }
$cpuShort = (($cpuName -replace '\(R\)|\(TM\)|\(tm\)|CPU', '') -replace '\s+', ' ').Trim()

function Get-Mem {
    $m = [TbfNative]::Mem()
    $t = [double]$m[0]; $a = [double]$m[1]
    [pscustomobject]@{ TotalGB = $t / 1GB; AvailGB = $a / 1GB; UsedGB = ($t - $a) / 1GB; Pct = [int][math]::Round((($t - $a) / $t) * 100) }
}
$script:mem = Get-Mem

# =====================================================================
#   รายการ Tweak
#   Regs  = ค่า Registry ที่จะตั้ง (V) และค่าเริ่มต้นของ Windows (D; $null = ลบค่าทิ้ง)
# =====================================================================
$tweaks = @(
    @{
        Key = 'power'; Kind = 'power'
        Name = 'Power Plan สูงสุด + CPU 100% (เฟรมนิ่ง)'
        Default = $true; Aggressive = $false; NeedsExe = $false
    },
    @{
        Key = 'gamemode'
        Name = 'เปิด Game Mode'
        Default = $true; Aggressive = $false; NeedsExe = $false
        Regs = { param($exe)
            @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AllowAutoGameMode';   V = 1; D = 1; T = 'DWord' }
            @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled'; V = 1; D = 1; T = 'DWord' }
        }
    },
    @{
        Key = 'dvr'
        Name = 'ปิด Game DVR / Game Bar (ลดโหลดพื้นหลัง)'
        Default = $true; Aggressive = $false; NeedsExe = $false
        Regs = { param($exe)
            @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_Enabled'; V = 0; D = 1; T = 'DWord' }
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'AppCaptureEnabled'; V = 0; D = 1; T = 'DWord' }
        }
    },
    @{
        Key = 'bgapps'
        Name = 'ปิดแอปแอบรันพื้นหลัง (ประหยัด RAM)'
        Default = $true; Aggressive = $false; NeedsExe = $false
        Regs = { param($exe)
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; N = 'GlobalUserDisabled'; V = 1; D = 0; T = 'DWord' }
        }
    },
    @{
        Key = 'transp'
        Name = 'ปิดเอฟเฟกต์โปร่งใสของ Windows (ประหยัด GPU)'
        Default = $true; Aggressive = $false; NeedsExe = $false
        Regs = { param($exe)
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'EnableTransparency'; V = 0; D = 1; T = 'DWord' }
        }
    },
    @{
        Key = 'visualfx'
        Name = 'Visual Effects ประหยัดสุด (ต้อง Sign out)'
        Default = $false; Aggressive = $true; NeedsExe = $false
        Regs = { param($exe)
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; N = 'VisualFXSetting'; V = 2; D = 0; T = 'DWord' }
            @{ P = 'HKCU:\Control Panel\Desktop'; N = 'UserPreferencesMask'; V = [byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00); D = [byte[]](0x9E,0x1E,0x07,0x80,0x12,0x00,0x00,0x00); T = 'Binary' }
            @{ P = 'HKCU:\Control Panel\Desktop\WindowMetrics'; N = 'MinAnimate'; V = '0'; D = '1'; T = 'String' }
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'TaskbarAnimations'; V = 0; D = 1; T = 'DWord' }
        }
    },
    @{
        Key = 'wsearch'
        Name = 'ปิด Search Indexing (ลดดิสก์/RAM)'
        Default = $false; Aggressive = $true; NeedsExe = $false
        Services = @('WSearch'); SvcDefault = @{ Mode = 'Auto'; Delayed = $true }
    },
    @{
        Key = 'sysmain'
        Name = 'ปิด SysMain/Superfetch (ใช้ HDD ไม่แนะนำ)'
        Default = $false; Aggressive = $true; NeedsExe = $false
        Services = @('SysMain'); SvcDefault = @{ Mode = 'Auto'; Delayed = $false }
    },
    @{
        Key = 'prio'
        Name = 'เกม: CPU Priority = High'
        Default = $true; Aggressive = $false; NeedsExe = $true
        Regs = { param($exe)
            $n = Split-Path $exe -Leaf
            @{ P = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$n\PerfOptions"; N = 'CpuPriorityClass'; V = 3; D = $null; T = 'DWord' }
        }
    },
    @{
        Key = 'gpu'
        Name = 'เกม: บังคับใช้ GPU แรงสุด'
        Default = $true; Aggressive = $false; NeedsExe = $true
        Regs = { param($exe)
            @{ P = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; N = $exe; V = 'GpuPreference=2;'; D = $null; T = 'String' }
        }
    },
    @{
        Key = 'fso'
        Name = 'เกม: ปิด Fullscreen Optimizations'
        Default = $false; Aggressive = $false; NeedsExe = $true
        Regs = { param($exe)
            $pp = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
            $flag = 'DISABLEDXMAXIMIZEDWINDOWEDMODE'
            $cur = Get-RegState $pp $exe
            $old = "$($cur.V)".Trim()
            if ($cur.Exists -and $old -match $flag) { $v = $old }
            elseif ($cur.Exists -and $old) { $v = "$old $flag"; if (-not $v.StartsWith('~')) { $v = "~ $v" } }
            else { $v = "~ $flag" }
            @{ P = $pp; N = $exe; V = $v; D = $null; T = 'String' }
        }
    }
)

function Apply-Power {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $o = powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        if ($o -match '([0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})') { powercfg /setactive $matches[1] | Out-Null }
    }
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
}

function Capture-Tweak($t, $exe, $snap) {
    if ($t.Regs) {
        foreach ($r in @(& $t.Regs $exe)) {
            $key = "$($r.P)|$($r.N)"
            $have = @($snap.Regs | Where-Object { "$($_.P)|$($_.N)" -eq $key })
            if ($have.Count -eq 0) { $snap.Regs += (Get-RegState $r.P $r.N) }
        }
    }
    foreach ($sv in @($t.Services)) {
        if ($sv) {
            $have = @($snap.Services | Where-Object { $_.Name -eq $sv })
            if ($have.Count -eq 0) { $st = Get-SvcState $sv; if ($st) { $snap.Services += $st } }
        }
    }
    if ($t.Kind -eq 'power' -and -not $snap.Power) {
        $o = powercfg /getactivescheme
        if ($o -match '([0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})') { $snap.Power = @{ Guid = $matches[1] } }
    }
}

function Apply-Tweak($t, $exe) {
    if ($t.Kind -eq 'power') { Apply-Power }
    if ($t.Regs) { foreach ($r in @(& $t.Regs $exe)) { Set-Reg $r.P $r.N $r.V $r.T } }
    foreach ($sv in @($t.Services)) {
        if ($sv) { Stop-Service $sv -Force -ErrorAction SilentlyContinue; sc.exe config $sv start= disabled | Out-Null }
    }
}

function Restore-Snapshot {
    $snap = Load-Snap
    foreach ($e in $snap.Regs) { try { Restore-RegState $e } catch { Log "คืนค่า Registry ไม่ได้: $($e.N)" } }
    foreach ($sv in $snap.Services) {
        try {
            Set-SvcMode $sv.Name $sv.Mode $sv.Delayed
            if ($sv.Running) { Start-Service $sv.Name -ErrorAction SilentlyContinue }
        } catch { Log "คืนค่า Service ไม่ได้: $($sv.Name)" }
    }
    if ($snap.Power) { powercfg /setactive $snap.Power.Guid | Out-Null }
    Remove-Item -LiteralPath $script:SnapFile -Force -ErrorAction SilentlyContinue
}

function Restore-Defaults($exe) {
    foreach ($t in $tweaks) {
        if ($t.Kind -eq 'power') { powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null }
        if ($t.Regs -and -not ($t.NeedsExe -and -not (Has-Exe $exe))) {
            foreach ($r in @(& $t.Regs $exe)) {
                if ($null -eq $r.D) { Remove-RegValue $r.P $r.N } else { Set-Reg $r.P $r.N $r.D $r.T }
            }
        }
        foreach ($sv in @($t.Services)) {
            if ($sv) { Set-SvcMode $sv $t.SvcDefault.Mode $t.SvcDefault.Delayed; Start-Service $sv -ErrorAction SilentlyContinue }
        }
    }
}

# =====================================================================
#   GTA V: ลด Distance Scaling / Population (แก้ settings.xml โดยตรง)
# =====================================================================
$script:GtaBackup = Join-Path $script:SnapDir 'gta_settings_backup.xml'

function Get-GtaSettingsPath {
    $docs = $null
    try { $docs = [Environment]::GetFolderPath('MyDocuments') } catch { }
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }
    $cands = @(
        (Join-Path $docs 'Rockstar Games\GTA V\settings.xml'),
        (Join-Path $env:USERPROFILE 'Documents\Rockstar Games\GTA V\settings.xml')
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

function Get-XmlTagValue($content, $tag) {
    $pattern = '<' + $tag + '\s+value="([^"]*)"\s*/>'
    if ($content -match $pattern) { return $matches[1] }
    return $null
}

function Set-XmlTagValue($content, $tag, $val) {
    $pattern = '(<' + $tag + '\s+value=")[^"]*("\s*/>)'
    if ($content -match $pattern) { return [regex]::Replace($content, $pattern, ('$1' + $val + '$2')) }
    return $content
}

function Confirm-GameClosed {
    $running = @(Get-Process -Name 'GTA5' -ErrorAction SilentlyContinue) +
               @(Get-Process -Name 'FiveM' -ErrorAction SilentlyContinue) +
               @(Get-Process | Where-Object { $_.ProcessName -like '*GTAProcess*' })
    if ($running.Count -gt 0) {
        $ans = [Windows.Forms.MessageBox]::Show("ตรวจพบว่าเกมกำลังเปิดอยู่`nถ้าบันทึกตอนนี้ เกมอาจเขียนทับค่ากลับตอนออกจากเกม แนะนำให้ปิดเกมก่อน`n`nดำเนินการต่อเลยไหม?", 'คำเตือน', 'YesNo', 'Warning')
        return ($ans -eq 'Yes')
    }
    return $true
}

function Apply-GtaReduce {
    $path = Get-GtaSettingsPath
    if (-not $path) { Log 'ไม่พบ settings.xml ของ GTA V (ต้องเปิดเกมอย่างน้อย 1 ครั้งก่อน เพื่อให้เกมสร้างไฟล์นี้)'; return }
    if (-not (Confirm-GameClosed)) { Log 'ยกเลิก - ปิดเกมก่อนแล้วลองใหม่'; return }
    try {
        if (-not (Test-Path -LiteralPath $script:SnapDir)) { New-Item -ItemType Directory -Path $script:SnapDir -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $script:GtaBackup)) {
            Copy-Item -LiteralPath $path -Destination $script:GtaBackup -Force
            Log 'สำรอง settings.xml ของ GTA V ไว้แล้ว (ใช้ปุ่ม คืนค่าเดิม (GTA V) ย้อนกลับได้)'
        }
        $content = [IO.File]::ReadAllText($path)
        $b = @{
            L = Get-XmlTagValue $content 'LodScale'
            X = Get-XmlTagValue $content 'MaxLodScale'
            D = Get-XmlTagValue $content 'CityDensity'
            P = Get-XmlTagValue $content 'PedVarietyMultiplier'
            V = Get-XmlTagValue $content 'VehicleVarietyMultiplier'
        }
        $content = Set-XmlTagValue $content 'LodScale' '0.000000'
        $content = Set-XmlTagValue $content 'MaxLodScale' '0.000000'
        $content = Set-XmlTagValue $content 'CityDensity' '0.500000'
        $content = Set-XmlTagValue $content 'PedVarietyMultiplier' '0.500000'
        $content = Set-XmlTagValue $content 'VehicleVarietyMultiplier' '0.500000'
        $enc = New-Object Text.UTF8Encoding($true)
        [IO.File]::WriteAllText($path, $content, $enc)
        Log ("ลดค่าแล้ว - Distance Scaling {0}->0%, Extended Distance {1}->0%, Population Density {2}->50%, Ped/Vehicle Variety {3}/{4}->50%" -f $b.L, $b.X, $b.D, $b.P, $b.V)
        Log 'อย่าเข้าเมนู Settings กราฟิกในเกมแล้วกด Apply ซ้ำ ไม่งั้นค่าที่ลดไว้จะถูกเขียนทับ'
    } catch {
        Log "แก้ settings.xml ไม่ได้: $($_.Exception.Message)"
    }
}

function Restore-GtaSettings {
    $path = Get-GtaSettingsPath
    if (-not $path) { Log 'ไม่พบ settings.xml ของ GTA V'; return }
    if (-not (Test-Path -LiteralPath $script:GtaBackup)) { Log 'ยังไม่มีการสำรองไว้ (ยังไม่เคยกด ลด Distance Scaling/Population)'; return }
    if (-not (Confirm-GameClosed)) { Log 'ยกเลิก - ปิดเกมก่อนแล้วลองใหม่'; return }
    try {
        Copy-Item -LiteralPath $script:GtaBackup -Destination $path -Force
        Log 'คืนค่า Distance Scaling/Population ของ GTA V เป็นค่าเดิมแล้ว'
    } catch {
        Log "คืนค่าไม่ได้: $($_.Exception.Message)"
    }
}


# =====================================================================
#   ล้างแรม
# =====================================================================
function Clear-Ram {
    $before = [double][TbfNative]::Mem()[1]
    $fg = [TbfNative]::ForegroundPid()
    $skip = @('Idle','System','Registry','smss','csrss','wininit','services','lsass','winlogon','dwm','fontdrvhost','MemCompression','audiodg')
    $gameName = ''
    if ($txtExe.Text.Trim()) { $gameName = [IO.Path]::GetFileNameWithoutExtension($txtExe.Text.Trim()) }
    $pats = @()
    foreach ($pf in $script:profiles) { $pats += (Get-ProfileMatch $pf.Exe) }
    $count = 0
    foreach ($p in Get-Process) {
        if ($p.Id -le 4 -or $p.Id -eq $PID -or $p.Id -eq $fg) { continue }
        $n = $p.ProcessName
        if ($skip -contains $n) { continue }
        if ($n -like 'FiveM*' -or $n -like 'GTA5*' -or $n -like '*GTAProcess*') { continue }
        if ($gameName -and $n -eq $gameName) { continue }
        $hit = $false
        foreach ($pt in $pats) { if ($n -like $pt) { $hit = $true; break } }
        if ($hit) { continue }
        $count += [TbfNative]::Trim($p.Id)
    }
    [void][TbfNative]::FlushModified()
    [void][TbfNative]::PurgeStandby()
    Start-Sleep -Milliseconds 400
    $after = [double][TbfNative]::Mem()[1]
    $freed = ($after - $before) / 1MB
    if ($freed -lt 0) { $freed = 0 }
    [pscustomobject]@{ FreedMB = $freed; Count = $count }
}

function Do-Clean($mode) {
    $form.Cursor = [Windows.Forms.Cursors]::WaitCursor
    try {
        $r = Clear-Ram
        $script:LastClean = Get-Date
        $script:mem = Get-Mem
        $meter.Invalidate()
        $tag = ''
        if ($mode -eq 'auto') { $tag = '[AUTO] ' } elseif ($mode -eq 'hotkey') { $tag = '[HOTKEY] ' } elseif ($mode -eq 'autoboost') { $tag = '[AUTO-BOOST] ' }
        Log ("{0}ล้างแรมแล้ว: ว่างเพิ่ม {1:N0} MB (บีบ {2} โปรเซส)" -f $tag, $r.FreedMB, $r.Count)
    } catch {
        Log "ล้างแรมไม่สำเร็จ: $($_.Exception.Message)"
    } finally {
        $form.Cursor = [Windows.Forms.Cursors]::Default
    }
}

# =====================================================================
#   วาดพื้นหลัง / โลโก้สไตล์ FiveM (วาดเองด้วย GDI+ ไม่ใช่โลโก้ทางการ)
# =====================================================================
function New-RoundRect($x, $y, $w, $h, $r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [single]($r * 2)
    $x = [single]$x; $y = [single]$y; $w = [single]$w; $h = [single]$h
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Draw-Lambda($g, [single]$x, [single]$y, [single]$s, [int]$alpha) {
    $q = @(@(0.06,0.92), @(0.36,0.08), @(0.55,0.08), @(0.86,0.92), @(0.65,0.92), @(0.455,0.38), @(0.27,0.92))
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    foreach ($pt in $q) {
        $px = [single]($x + $pt[0] * $s)
        $py = [single]($y + $pt[1] * $s)
        $pts.Add((New-Object Drawing.PointF($px, $py)))
    }
    $arr = $pts.ToArray()
    $ga = [int]($alpha / 7)
    foreach ($wd in 18, 12, 7) {
        $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb($ga, 182, 110, 255), [single]$wd)
        $pen.LineJoin = 'Round'
        $g.DrawPolygon($pen, $arr)
        $pen.Dispose()
    }
    $rf = New-Object Drawing.RectangleF($x, $y, $s, $s)
    $c1 = [Drawing.Color]::FromArgb($alpha, 226, 200, 255)
    $c2 = [Drawing.Color]::FromArgb($alpha, 124, 58, 237)
    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($rf, $c1, $c2, [Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillPolygon($br, $arr)
    $br.Dispose()
}

function Draw-ClayLambda($g, [single]$x, [single]$y, [single]$s, [int]$alpha) {
    $q = @(@(0.06,0.92), @(0.36,0.08), @(0.55,0.08), @(0.86,0.92), @(0.65,0.92), @(0.455,0.38), @(0.27,0.92))
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    foreach ($pt in $q) {
        $px = [single]($x + $pt[0] * $s)
        $py = [single]($y + $pt[1] * $s)
        $pts.Add((New-Object Drawing.PointF($px, $py)))
    }
    $arr = $pts.ToArray()

    # เงานุ่ม ๆ ใต้ตัวโลโก้ดินน้ำมัน
    for ($i = 3; $i -ge 1; $i--) {
        $off = [single]($i * 3)
        $a = [int](($alpha * 0.35) / $i)
        $shArr = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
        foreach ($pt in $arr) { $shArr.Add((New-Object Drawing.PointF(($pt.X + $off), ($pt.Y + $off + 2)))) }
        $sb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, 5, 2, 10))
        $g.FillPolygon($sb, $shArr.ToArray())
        $sb.Dispose()
    }

    # เนื้อดินน้ำมันไล่เฉดด้าน
    $rf = New-Object Drawing.RectangleF($x, $y, $s, $s)
    $c1 = [Drawing.Color]::FromArgb($alpha, 214, 160, 230)
    $c2 = [Drawing.Color]::FromArgb($alpha, 90, 40, 120)
    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($rf, $c1, $c2, [single]55)
    $g.FillPolygon($br, $arr)
    $br.Dispose()

    # แสงมันนวลมุมบน (โดนคลึงเป็นเงา)
    $shapePath = New-Object Drawing.Drawing2D.GraphicsPath
    $shapePath.AddPolygon($arr)
    $hlRect = New-Object Drawing.RectangleF(($x + $s * 0.18), ($y + $s * 0.05), ($s * 0.5), ($s * 0.35))
    $hgp = New-Object Drawing.Drawing2D.GraphicsPath
    $hgp.AddEllipse($hlRect)
    $hpg = New-Object Drawing.Drawing2D.PathGradientBrush($hgp)
    $ha = [int]($alpha * 0.9)
    $hpg.CenterColor = [Drawing.Color]::FromArgb($ha, 255, 240, 250)
    $hpg.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 255, 240, 250))
    $oldClip = $g.Clip
    $g.SetClip($shapePath)
    $g.FillPath($hpg, $hgp)
    $g.Clip = $oldClip
    $hpg.Dispose(); $hgp.Dispose(); $shapePath.Dispose()

    # ร่องขอบแบบดินถูกกดบุ๋ม + ริมสว่างบาง ๆ
    $ga2 = [int]($alpha * 0.8)
    $gpen = New-Object Drawing.Pen([Drawing.Color]::FromArgb($ga2, 40, 14, 55), [single]4)
    $gpen.LineJoin = 'Round'
    $g.DrawPolygon($gpen, $arr)
    $gpen.Dispose()
    $rpen = New-Object Drawing.Pen([Drawing.Color]::FromArgb($ga2, 236, 196, 255), [single]1.3)
    $rpen.LineJoin = 'Round'
    $g.DrawPolygon($rpen, $arr)
    $rpen.Dispose()

    # รอยนิ้วกดเล็ก ๆ เพิ่มสัมผัสความเป็นดินน้ำมันปั้นมือ
    foreach ($d in @(@(0.30,0.62,0.05), @(0.55,0.55,0.04), @(0.42,0.75,0.035))) {
        $dx = $x + $s * $d[0]; $dy = $y + $s * $d[1]; $dr = $s * $d[2]
        $dgp = New-Object Drawing.Drawing2D.GraphicsPath
        $dgp.AddEllipse(($dx - $dr), ($dy - $dr), ($dr * 2), ($dr * 2))
        $dpg = New-Object Drawing.Drawing2D.PathGradientBrush($dgp)
        $da = [int]($alpha * 0.5)
        $dpg.CenterColor = [Drawing.Color]::FromArgb($da, 30, 10, 40)
        $dpg.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 30, 10, 40))
        $g.FillPath($dpg, $dgp)
        $dpg.Dispose(); $dgp.Dispose()
    }
}

function Draw-ClayCard($g, $x, $y, $w, $h, $r) {
    # เงาแบบดินน้ำมัน (เบลอลวงตาด้วยการซ้อนหลายชั้น)
    for ($i = 3; $i -ge 1; $i--) {
        $off = $i * 2
        $a = [int](50 / $i)
        $sp = New-RoundRect ($x + $off) ($y + $off + 2) $w $h $r
        $sb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, 8, 3, 16))
        $g.FillPath($sb, $sp)
        $sb.Dispose(); $sp.Dispose()
    }
    # เนื้อดินน้ำมัน (ไล่เฉดด้าน ไม่มัน)
    $mp = New-RoundRect $x $y $w $h $r
    $rf = New-Object Drawing.Rectangle([int]$x, [int]$y, [int]$w, [int]$h)
    $mb = New-Object Drawing.Drawing2D.LinearGradientBrush($rf, (Col '#7A4470'), (Col '#33173C'), [single]55)
    $g.FillPath($mb, $mp)
    $mb.Dispose()
    # แสงสะท้อนนุ่ม ๆ มุมบนซ้าย (คลึงดินแล้วมีรอยมันเล็กน้อย)
    $hlRect = New-Object Drawing.RectangleF(($x + $w * 0.06), ($y + $h * 0.06), ($w * 0.55), ($h * 0.38))
    $hgp = New-Object Drawing.Drawing2D.GraphicsPath
    $hgp.AddEllipse($hlRect)
    $hpg = New-Object Drawing.Drawing2D.PathGradientBrush($hgp)
    $hpg.CenterColor = [Drawing.Color]::FromArgb(55, 255, 232, 248)
    $hpg.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 255, 232, 248))
    $oldClip = $g.Clip
    $g.SetClip($mp)
    $g.FillPath($hpg, $hgp)
    $g.Clip = $oldClip
    $hpg.Dispose(); $hgp.Dispose()
    # รอยกดขอบด้านในแบบดินถูกบุ๋ม
    $ip = New-RoundRect ($x + 2) ($y + 2) ($w - 4) ($h - 4) ([Math]::Max(2, $r - 3))
    $ipen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(85, 18, 7, 24), [single]2)
    $g.DrawPath($ipen, $ip)
    $ipen.Dispose(); $ip.Dispose()
    # ขอบนอกสีอ่อนแบบผิวดินน้ำมันโดนแสง
    $rpen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(150, 236, 196, 255), [single]1.4)
    $g.DrawPath($rpen, $mp)
    $rpen.Dispose()
    return $mp
}

function Draw-Badge($g, $x, $y, $size) {
    $bp = Draw-ClayCard $g $x $y $size $size ($size * 0.26)
    $bp.Dispose()
    $pad = $size * 0.20
    Draw-Lambda $g ($x + $pad) ($y + $pad) ($size - 2 * $pad) 255
}

$script:pageCards = @{
    1 = @(
        @(20, 110, 520, 345, 'TWEAKS'),
        @(556, 110, 364, 345, 'RAM CLEANER'),
        @(20, 467, 520, 160, 'GAME'),
        @(556, 467, 364, 160, 'ACTIONS')
    )
    2 = @(
        @(20, 110, 440, 200, 'LIVE MONITOR'),
        @(480, 110, 440, 200, 'AUTO-BOOST'),
        @(20, 320, 440, 305, 'GAME PROFILES'),
        @(480, 320, 440, 305, 'CACHE CLEANER')
    )
}

function Draw-Bar($g, $x, $y, $w, $h, $pct) {
    $tp = New-RoundRect $x $y $w $h ($h / 2)
    $tb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(160, 44, 24, 88))
    $g.FillPath($tb, $tp)
    $tb.Dispose(); $tp.Dispose()
    $fw = [int][math]::Round($w * [math]::Min(100, [math]::Max(0, $pct)) / 100)
    if ($fw -ge $h) {
        $fp = New-RoundRect $x $y $fw $h ($h / 2)
        if ($pct -ge 85) { $c1 = Col '#FF4DA6'; $c2 = Col '#FF9AD0' } else { $c1 = Col '#7C3AED'; $c2 = Col '#D8B4FE' }
        $fr = New-Object Drawing.Rectangle([int]$x, [int]$y, $fw, [int]$h)
        $fb = New-Object Drawing.Drawing2D.LinearGradientBrush($fr, $c1, $c2, [single]0)
        $g.FillPath($fb, $fp)
        $fb.Dispose(); $fp.Dispose()
    }
}

function Draw-Stat($g, $x, $y, $w, $label, $valText, $pct) {
    $g.DrawString($label, $script:fLab, $script:brAcc, $x, $y)
    $g.DrawString($valText, $script:fTiny, $script:brText, ($x + 52), ($y + 2))
    Draw-Bar $g $x ($y + 22) $w 10 $pct
}

function New-Background($W, $H, $cards) {
    $bmp = New-Object Drawing.Bitmap($W, $H)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $rect = New-Object Drawing.Rectangle(0, 0, $W, $H)
    $usedCustom = $false

    foreach ($n in 'bg.png', 'bg.jpg', 'bg.jpeg', 'background.png', 'background.jpg') {
        $pp = Join-Path $script:Here $n
        if (Test-Path -LiteralPath $pp) {
            try {
                $img = [Drawing.Image]::FromFile($pp)
                $g.DrawImage($img, $rect)
                $img.Dispose()
                $ov = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(150, 20, 6, 45))
                $g.FillRectangle($ov, $rect)
                $ov.Dispose()
                $usedCustom = $true
            } catch { }
            break
        }
    }

    if (-not $usedCustom) {
        $lg = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, (Col '#0A0512'), (Col '#2E1060'), [single]40)
        $g.FillRectangle($lg, $rect)
        $lg.Dispose()

        foreach ($gl in @(@(600, -160, 560, '#8B3DFF', 120), @(-200, 380, 520, '#5B21B6', 110), @(300, 420, 420, '#C97FA8', 45))) {
            $gp = New-Object Drawing.Drawing2D.GraphicsPath
            $gp.AddEllipse([single]$gl[0], [single]$gl[1], [single]$gl[2], [single]$gl[2])
            $pg = New-Object Drawing.Drawing2D.PathGradientBrush($gp)
            $c = Col $gl[3]
            $pg.CenterColor = [Drawing.Color]::FromArgb([int]$gl[4], $c.R, $c.G, $c.B)
            $pg.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, $c.R, $c.G, $c.B))
            $g.FillPath($pg, $gp)
            $pg.Dispose(); $gp.Dispose()
        }

        $gridPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(14, 190, 140, 255), [single]1)
        for ($i = 0; $i -lt $W; $i += 40) { $g.DrawLine($gridPen, $i, 0, $i, $H) }
        for ($j = 0; $j -lt $H; $j += 40) { $g.DrawLine($gridPen, 0, $j, $W, $j) }
        $gridPen.Dispose()

        # ลายเฉียงมุมขวาบน
        $sp = New-Object Drawing.Pen([Drawing.Color]::FromArgb(45, 178, 110, 255), [single]3)
        for ($i = 0; $i -lt 7; $i++) { $g.DrawLine($sp, (690 + $i * 30), 0, (650 + $i * 30), 98) }
        $sp.Dispose()

        # โลโก้ดินน้ำมันตรงกลางพื้นหลัง (ภาพสวยๆ กลางจอ สไตล์ Clay)
        Draw-ClayLambda $g 190 70 560 38
    }

    # การ์ดสไตล์ดินน้ำมัน (Clay UI)
    $accBr   = New-Object Drawing.SolidBrush($script:cAcc)
    $titBr   = New-Object Drawing.SolidBrush($script:cAcc2)
    $titFont = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
    foreach ($c in $cards) {
        $pth = Draw-ClayCard $g $c[0] $c[1] $c[2] $c[3] 16
        $pth.Dispose()
        $g.FillRectangle($accBr, ($c[0] + 16), ($c[1] + 12), 4, 16)
        $g.DrawString($c[4], $titFont, $titBr, ($c[0] + 26), ($c[1] + 10))
    }

    # Header
    Draw-Badge $g 24 14 72

    $ft = New-Object Drawing.Font('Segoe UI Black', 23)
    $tr = New-Object Drawing.RectangleF(108, 10, 420, 40)
    $tbr = New-Object Drawing.Drawing2D.LinearGradientBrush($tr, (Col '#FFFFFF'), (Col '#B983FF'), [Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.DrawString('TANAGET BOOST FPS', $ft, $tbr, 108, 10)

    $subF = New-Object Drawing.Font('Segoe UI Semibold', 9)
    $subB = New-Object Drawing.SolidBrush($script:cAcc2)
    $g.DrawString('FIVEM EDITION   //   LOW-SPEC OPTIMIZER', $subF, $subB, 110, 54)

    $sf = New-Object Drawing.StringFormat
    $sf.Trimming = 'EllipsisCharacter'
    $sf.FormatFlags = 'NoWrap'
    $specF = New-Object Drawing.Font('Segoe UI', 8.5)
    $specB = New-Object Drawing.SolidBrush($script:cDim)
    $specR = New-Object Drawing.RectangleF(110, 73, 640, 18)
    $g.DrawString("$cpuShort   |   $gpuName   |   RAM $ramGB GB", $specF, $specB, $specR, $sf)

    $pill = New-RoundRect 828 26 92 26 13
    $pillB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(140, 139, 61, 255))
    $g.FillPath($pillB, $pill)
    $pillF = New-Object Drawing.Font('Segoe UI Semibold', 8.5)
    $g.DrawString('v5.1  CLAY PURPLE', $pillF, (New-Object Drawing.SolidBrush([Drawing.Color]::White)), 837, 31)

    $lineR = New-Object Drawing.Rectangle(20, 97, 900, 2)
    $lineB = New-Object Drawing.Drawing2D.LinearGradientBrush($lineR, [Drawing.Color]::FromArgb(230, 139, 61, 255), [Drawing.Color]::FromArgb(0, 139, 61, 255), [Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.FillRectangle($lineB, $lineR)

    $g.Dispose()
    return $bmp
}

# =====================================================================
#   สร้างหน้าต่าง
# =====================================================================
$W = 940; $H = 700
$form = New-Object Windows.Forms.Form
$form.Text = 'Tanaget Boost FPS'
$form.AutoScaleMode = 'None'
$form.ClientSize = New-Object Drawing.Size($W, $H)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = Col '#0A0512'
$form.ForeColor = $script:cText
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$script:bgs = @{}
$script:bgs[1] = New-Background $W $H $script:pageCards[1]
$script:bgs[2] = New-Background $W $H $script:pageCards[2]
$form.BackgroundImage = $script:bgs[1]
$form.BackgroundImageLayout = 'None'
$form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($form, $true, $null)

# ไอคอนหน้าต่าง
try {
    $icoBmp = New-Object Drawing.Bitmap(64, 64)
    $ig = [Drawing.Graphics]::FromImage($icoBmp)
    $ig.SmoothingMode = 'AntiAlias'
    Draw-Badge $ig 2 2 60
    $ig.Dispose()
    $form.Icon = [Drawing.Icon]::FromHandle($icoBmp.GetHicon())
} catch { }

$tip = New-Object Windows.Forms.ToolTip
$tip.AutoPopDelay = 12000

# ---------- ตัวช่วยสร้าง UI ----------
$script:curPage = 0
$script:page = 1
$script:pages = @{ 1 = @(); 2 = @() }

function Track($c) {
    if ($script:curPage -gt 0) { $script:pages[$script:curPage] += $c }
    $form.Controls.Add($c)
    if ($c -is [Windows.Forms.CheckBox]) {
        $cbRef = $c
        $cbRef.Add_CheckedChanged({ $form.Invalidate($cbRef.Bounds, $true); $form.Update() }.GetNewClosure())
        $cbRef.Add_Click({ $form.Invalidate($cbRef.Bounds, $true); $form.Update() }.GetNewClosure())
    }
}

function Style-Btn($b, $primary) {
    if ($primary) {
        $b.BackColor = $script:cAcc
        $b.ForeColor = [Drawing.Color]::White
        $b.FlatAppearance.BorderColor = $script:cAcc2
        $b.FlatAppearance.MouseOverBackColor = Col '#A468FF'
        $b.FlatAppearance.MouseDownBackColor = Col '#6F2BE0'
    } else {
        $b.BackColor = Col '#22133F'
        $b.ForeColor = $script:cText
        $b.FlatAppearance.BorderColor = Col '#5A35A8'
        $b.FlatAppearance.MouseOverBackColor = Col '#34205F'
        $b.FlatAppearance.MouseDownBackColor = Col '#1A0F33'
    }
}

# ---------- แก้บั๊ก: ติ๊ก checkbox แล้วพื้นหลังกลายเป็นสีดำ ----------
# สาเหตุ: ฟอร์มเปิด DoubleBuffered ไว้ (กันภาพพื้นหลังกระพริบ) แต่ checkbox ใช้ BackColor=Transparent
# ของจริง (ให้ฟอร์มวาดพื้นหลังทะลุมาให้) ซึ่งสองอย่างนี้ชนกัน พอ Invalidate เฉพาะจุด (เช่นตอนติ๊ก)
# มันเลยวาดพื้นที่ตรงนั้นเป็นสีดำแทนที่จะเป็นพื้นหลังจริง
# วิธีแก้: "ตัดภาพพื้นหลัง" ตรงตำแหน่ง/ขนาดของ control มาใส่เป็น BackgroundImage ของ control เอง
# (โปร่งใสปลอม แต่ไม่ชนกับ DoubleBuffered เพราะไม่ต้องพึ่งฟอร์มวาดทะลุมาให้อีกต่อไป)
function Set-CtrlBg($ctrl) {
    try {
        $srcBg = $null
        if ($script:bgs -and $script:bgs.ContainsKey($script:curPage)) { $srcBg = $script:bgs[$script:curPage] }
        elseif ($form.BackgroundImage) { $srcBg = $form.BackgroundImage }
        if (-not $srcBg) { return }
        $r = $ctrl.Bounds
        if ($r.Width -le 0 -or $r.Height -le 0) { return }
        $rx = [Math]::Max(0, [Math]::Min([int]$r.X, $srcBg.Width  - 1))
        $ry = [Math]::Max(0, [Math]::Min([int]$r.Y, $srcBg.Height - 1))
        $rw = [Math]::Min([int]$r.Width,  $srcBg.Width  - $rx)
        $rh = [Math]::Min([int]$r.Height, $srcBg.Height - $ry)
        if ($rw -le 0 -or $rh -le 0) { return }
        $crop = New-Object Drawing.Bitmap $rw, $rh
        $g2 = [Drawing.Graphics]::FromImage($crop)
        $g2.DrawImage($srcBg, (New-Object Drawing.Rectangle(0, 0, $rw, $rh)), (New-Object Drawing.Rectangle($rx, $ry, $rw, $rh)), [Drawing.GraphicsUnit]::Pixel)
        $g2.Dispose()
        if ($ctrl.BackgroundImage) { $ctrl.BackgroundImage.Dispose() }
        $ctrl.BackColor = $script:cInput
        $ctrl.BackgroundImage = $crop
        $ctrl.BackgroundImageLayout = 'None'
    } catch {}
}

function New-Chk($text, $x, $y, $w, $h, $checked) {
    $cb = New-Object Windows.Forms.CheckBox
    $cb.Text = $text
    $cb.Checked = [bool]$checked
    $cb.Location = New-Object Drawing.Point($x, $y)
    $cb.Size = New-Object Drawing.Size($w, $h)
    $cb.ForeColor = $script:cText
    $cb.FlatStyle = 'Flat'
    $cb.FlatAppearance.BorderColor = $script:cAcc2
    $cb.FlatAppearance.BorderSize = 1
    $cb.FlatAppearance.CheckedBackColor = $script:cAcc
    $cb.FlatAppearance.MouseOverBackColor = Col '#2B1A57'
    Set-CtrlBg $cb
    Track $cb
    return $cb
}

function New-Lbl($text, $x, $y, $w, $h, $size, $color, $bold) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object Drawing.Point($x, $y)
    $l.Size = New-Object Drawing.Size($w, $h)
    $l.BackColor = [Drawing.Color]::Transparent
    $l.ForeColor = $color
    $style = [Drawing.FontStyle]::Regular
    if ($bold) { $style = [Drawing.FontStyle]::Bold }
    $l.Font = New-Object Drawing.Font('Segoe UI', [single]$size, $style)
    Track $l
    return $l
}

function New-Btn($text, $x, $y, $w, $h, $primary) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, $y)
    $b.Size = New-Object Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
    $b.FlatAppearance.BorderSize = 1
    Style-Btn $b $primary
    Track $b
    return $b
}

function New-Txt($x, $y, $w, $h) {
    $t = New-Object Windows.Forms.TextBox
    $t.Location = New-Object Drawing.Point($x, $y)
    $t.Size = New-Object Drawing.Size($w, $h)
    $t.BorderStyle = 'FixedSingle'
    $t.BackColor = $script:cInput
    $t.ForeColor = $script:cText
    Track $t
    return $t
}

# ---------- ปุ่มสลับหน้า (อยู่ที่ Header ทุกหน้า) ----------
$script:curPage = 0
$btnNav1 = New-Btn 'หน้าหลัก' 596 22 100 32 $true
$btnNav2 = New-Btn 'เครื่องมือ' 704 22 110 32 $false
$script:curPage = 1

# ---------- การ์ดซ้าย: TWEAKS ----------
$script:checks = @()
$y = 144
foreach ($t in $tweaks) {
    $cb = New-Object Windows.Forms.CheckBox
    $cb.Text = $t.Name
    $cb.Checked = $t.Default
    $cb.Tag = $t
    $cb.Location = New-Object Drawing.Point(34, $y)
    $cb.Size = New-Object Drawing.Size(490, 22)
    $cb.ForeColor = $script:cText
    $cb.FlatStyle = 'Flat'
    $cb.FlatAppearance.BorderColor = $script:cAcc2
    $cb.FlatAppearance.BorderSize = 1
    $cb.FlatAppearance.CheckedBackColor = $script:cAcc
    $cb.FlatAppearance.MouseOverBackColor = Col '#2B1A57'
    Set-CtrlBg $cb
    Track $cb
    $script:checks += $cb
    $y += 24
}

$chkAggro = New-Object Windows.Forms.CheckBox
$chkAggro.Text = 'โหมดเครื่องอ่อนสุด (ติ๊กกลุ่ม Tweak ที่แรงขึ้นให้อัตโนมัติ)'
$chkAggro.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
$chkAggro.Location = New-Object Drawing.Point(34, 418)
$chkAggro.Size = New-Object Drawing.Size(490, 26)
$chkAggro.ForeColor = $script:cAcc2
$chkAggro.FlatStyle = 'Flat'
$chkAggro.FlatAppearance.BorderColor = $script:cAcc2
$chkAggro.FlatAppearance.CheckedBackColor = $script:cAcc
Set-CtrlBg $chkAggro
Track $chkAggro

# ---------- การ์ดขวา: RAM CLEANER ----------
$meter = New-Object Windows.Forms.Panel
$meter.Location = New-Object Drawing.Point(574, 148)
$meter.Size = New-Object Drawing.Size(328, 84)
$meter.BackColor = [Drawing.Color]::Transparent
$meter.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($meter, $true, $null)
Track $meter

$script:fBig = New-Object Drawing.Font('Segoe UI Black', 26)
$script:fSm  = New-Object Drawing.Font('Segoe UI', 9.5)
$script:brText = New-Object Drawing.SolidBrush($script:cText)
$script:brDim  = New-Object Drawing.SolidBrush($script:cDim)

$meter.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'ClearTypeGridFit'
    $m = $script:mem
    $g.DrawString(("{0}%" -f $m.Pct), $script:fBig, $script:brText, 0, 0)
    $g.DrawString(("ใช้ {0:N1} / {1:N1} GB" -f $m.UsedGB, $m.TotalGB), $script:fSm, $script:brText, 120, 10)
    $g.DrawString(("ว่าง {0:N1} GB" -f $m.AvailGB), $script:fSm, $script:brDim, 120, 30)
    $bw = 328; $by = 62; $bh = 14
    $tp = New-RoundRect 0 $by $bw $bh 7
    $tb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(160, 44, 24, 88))
    $g.FillPath($tb, $tp)
    $tb.Dispose(); $tp.Dispose()
    $fw = [int][math]::Round($bw * $m.Pct / 100)
    if ($fw -ge 14) {
        $fp = New-RoundRect 0 $by $fw $bh 7
        if ($m.Pct -ge 85) { $c1 = Col '#FF4DA6'; $c2 = Col '#FF9AD0' } else { $c1 = Col '#7C3AED'; $c2 = Col '#D8B4FE' }
        $frect = New-Object Drawing.Rectangle(0, $by, $fw, $bh)
        $fb = New-Object Drawing.Drawing2D.LinearGradientBrush($frect, $c1, $c2, [single]0)
        $g.FillPath($fb, $fp)
        $fb.Dispose(); $fp.Dispose()
    }
})

$btnClean = New-Btn 'ล้างแรมที่ไม่ได้ใช้งานตอนนี้' 574 240 328 42 $true
$tip.SetToolTip($btnClean, "บีบหน่วยความจำของโปรเซสที่ไม่ได้ใช้งานอยู่ + ล้างแคช Standby ของ Windows`nไม่แตะเกมที่กำลังเล่น (FiveM/GTA5/ไฟล์เกมที่เลือก) และหน้าต่างที่เปิดอยู่ตอนนั้น`nแรมว่างจะเพิ่มทันที แต่ Windows จะดึงข้อมูลกลับมาเองบางส่วนเมื่อจำเป็น")

$chkAuto = New-Object Windows.Forms.CheckBox
$chkAuto.Text = 'ล้างอัตโนมัติเมื่อ RAM ใช้เกิน'
$chkAuto.Location = New-Object Drawing.Point(574, 292)
$chkAuto.Size = New-Object Drawing.Size(328, 24)
$chkAuto.ForeColor = $script:cText
$chkAuto.FlatStyle = 'Flat'
$chkAuto.FlatAppearance.BorderColor = $script:cAcc2
$chkAuto.FlatAppearance.CheckedBackColor = $script:cAcc
Set-CtrlBg $chkAuto
Track $chkAuto

$numTh = New-Object Windows.Forms.NumericUpDown
$numTh.Location = New-Object Drawing.Point(576, 320)
$numTh.Size = New-Object Drawing.Size(64, 24)
$numTh.Minimum = 50; $numTh.Maximum = 95; $numTh.Value = 80
$numTh.BackColor = $script:cInput
$numTh.ForeColor = $script:cText
$numTh.BorderStyle = 'FixedSingle'
Track $numTh
[void](New-Lbl '%   •   ปุ่มลัด Ctrl+Alt+R = ล้างแรมทันที' 646 323 262 20 8.5 $script:cDim $false)
$tip.SetToolTip($numTh, "โหมดอัตโนมัติเช็กทุก 2 วินาที และเว้นระยะอย่างน้อย 45 วินาทีระหว่างการล้าง\nปุ่มลัด Ctrl+Alt+R ใช้ได้ทั้งระบบ แม้กำลังเล่นเกม (ไม่ปิดเกม ไม่แตะเกมที่เปิดอยู่)")

$btnBoost = New-Btn 'ปิดแอปเบื้องหลัง + ล้าง Temp' 574 356 160 36 $false
$btnStartup = New-Btn 'แอปเปิดตอนบูต' 742 356 160 36 $false
$lblSnap = New-Lbl '' 574 400 328 48 8.5 $script:cDim $false

# ---------- การ์ดล่างซ้าย: GAME ----------
[void](New-Lbl 'ไฟล์เกม (.exe)' 34 490 300 18 8.5 $script:cDim $false)
$txtExe = New-Txt 34 510 338 24
$btnBrowse = New-Btn 'เลือก...' 378 508 70 28 $false
$btnFive = New-Btn 'FiveM' 452 508 74 28 $false
$tip.SetToolTip($btnFive, 'ตรวจหาไฟล์เกมของ FiveM (FiveM_bXXXX_GTAProcess.exe) ให้อัตโนมัติ')
[void](New-Lbl 'ปิดโปรแกรมเหล่านี้ตอนกด Boost (ชื่อโปรเซส คั่นด้วย ,)' 34 537 490 18 8.5 $script:cDim $false)
$txtKill = New-Txt 34 556 492 22
$txtKill.Text = 'OneDrive,Teams,Skype,GoogleUpdate,MicrosoftEdgeUpdate'
$btnGtaReduce = New-Btn 'ลด Distance Scaling/Population (GTA V)' 34 588 330 30 $true
$btnGtaRestore = New-Btn 'คืนค่าเดิม (GTA V)' 372 588 154 30 $false
$tip.SetToolTip($btnGtaReduce, "แก้ settings.xml ของ GTA V โดยตรง: Distance Scaling -> 0%, Extended Distance Scaling -> 0%,`nPopulation Density/Variety -> 50% ต้องปิดเกมก่อนถึงจะเซฟติด ไม่งั้นเกมจะเขียนทับตอนออกจากเกม")
$tip.SetToolTip($btnGtaRestore, 'คืนค่า settings.xml ของ GTA V กลับเป็นค่าก่อนกด ลด Distance Scaling/Population')

# ---------- การ์ดล่างขวา: ACTIONS ----------
$btnApply = New-Btn 'ใช้ Tweak ที่เลือก' 572 494 332 40 $true
$btnRestore = New-Btn 'คืนค่าก่อนรัน' 572 542 162 32 $false
$btnDefault = New-Btn 'คืนค่า Windows' 742 542 162 32 $false
$tip.SetToolTip($btnRestore, 'ย้อนกลับเป็นค่าที่เครื่องมีอยู่ก่อนกด "ใช้ Tweak" ครั้งแรกเป๊ะ ๆ')
$tip.SetToolTip($btnDefault, 'รีเซ็ตทุก Tweak เป็นค่าเริ่มต้นของ Windows (ไม่ใช่ค่าก่อนรัน)')

# =====================================================================
#   ฟังก์ชันของหน้าเครื่องมือ
# =====================================================================
# --- Monitor ---
$script:smi = $null
foreach ($cand in @("$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe", "$env:WINDIR\System32\nvidia-smi.exe")) {
    if (Test-Path -LiteralPath $cand) { $script:smi = $cand; break }
}
if (-not $script:smi) {
    $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($cmd) { $script:smi = $cmd.Source }
}
function ToInt($v) { $r = 0; if ([int]::TryParse(("$v").Trim(), [ref]$r)) { return $r } else { return 0 } }
function Get-GpuInfo {
    if (-not $script:smi) { return $null }
    try {
        $o = & $script:smi '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.gr' '--format=csv,noheader,nounits' 2>$null
        if ($o) {
            $f = (@($o)[0]) -split ',\s*'
            if ($f.Count -ge 5) {
                return @{ Util = (ToInt $f[0]); Temp = (ToInt $f[1]); MemUsed = (ToInt $f[2]); MemTotal = (ToInt $f[3]); Clock = (ToInt $f[4]) }
            }
        }
    } catch { }
    return $null
}
function Get-TopProcs {
    @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object { @{ N = $_.ProcessName; MB = [int]($_.WorkingSet64 / 1MB) } })
}

# --- Profiles ---
$script:profiles = @()
function Get-ProfileMatch($exe) {
    $b = [IO.Path]::GetFileNameWithoutExtension("$exe")
    if ($b -like 'FiveM*GTAProcess*') { return 'FiveM*GTAProcess*' }
    return $b
}
function Find-FiveMExe {
    $dir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    if (Test-Path -LiteralPath $dir) {
        $f = Get-ChildItem -LiteralPath $dir -Filter '*GTAProcess.exe' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}
function Refresh-Profiles {
    $lstProf.Items.Clear()
    foreach ($p in $script:profiles) { [void]$lstProf.Items.Add(("{0}   |   {1}" -f $p.Name, $p.Exe)) }
}
function Load-Profile($i) {
    if ($i -ge 0 -and $i -lt $script:profiles.Count) {
        $txtExe.Text = $script:profiles[$i].Exe
        Log "โหลดโปรไฟล์: $($script:profiles[$i].Name)"
        Show-Page 1
    }
}

# --- Cache ---
function Get-PathSize($paths) {
    $sum = 0.0
    foreach ($p in @($paths)) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            $m = Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
            if ($m.Sum) { $sum += [double]$m.Sum }
        }
    }
    return $sum
}
function Clear-Paths($paths) {
    # คืนค่า = จำนวนไฟล์/โฟลเดอร์ที่ลบไม่ได้ (โดนล็อกอยู่ เช่น โปรแกรมเปิดค้างไว้)
    $locked = 0
    foreach ($p in @($paths)) {
        if ($p -and $p.Length -gt 12 -and (Test-Path -LiteralPath $p)) {
            # เอา attribute ReadOnly/System/Hidden ออกก่อน ไม่งั้นลบไม่ได้ (แคช FiveM บางไฟล์ถูกตั้งเป็น ReadOnly)
            Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    if ($_.Attributes -band ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::Hidden)) {
                        $_.Attributes = [IO.FileAttributes]::Normal
                    }
                } catch {}
            }
            # ลบรอบแรก
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            # ไล่ลบสิ่งที่เหลือทีละรายการ (เรียงพาธยาวสุด/ลึกสุดก่อน กันปัญหาโฟลเดอร์แม่ลบไม่ได้เพราะลูกยังค้าง)
            $left = @(Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
            foreach ($item in $left) {
                try { Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop }
                catch { $locked++ }
            }
        }
    }
    return $locked
}

function Test-FiveMRunning {
    $running = @(Get-Process -Name 'FiveM' -ErrorAction SilentlyContinue) +
               @(Get-Process -Name 'FiveM_GTAProcess' -ErrorAction SilentlyContinue) +
               @(Get-Process | Where-Object { $_.ProcessName -like '*GTAProcess*' })
    return ($running.Count -gt 0)
}

function Update-CacheSizes {
    if (-not $script:cacheChecks) { return }
    $form.Cursor = [Windows.Forms.Cursors]::WaitCursor
    try {
        foreach ($c in $script:cacheChecks) {
            $it = $c.Tag
            if ($it.Special) { continue }
            $mb = (Get-PathSize $it.Paths) / 1MB
            $c.Text = ("{0}  [{1:N0} MB]" -f $it.Name, $mb)
        }
    } finally { $form.Cursor = [Windows.Forms.Cursors]::Default }
}

# --- Auto-Boost ---
$script:abRunning = $false
$script:abPending = $false
$script:abStart = [datetime]::MinValue
function Get-RunningGame {
    foreach ($pf in $script:profiles) {
        $pat = Get-ProfileMatch $pf.Exe
        $pr = @(Get-Process -Name $pat -ErrorAction SilentlyContinue)
        if ($pr.Count -gt 0) { return @{ Name = $pf.Name; Proc = $pr[0] } }
    }
    return $null
}

# --- ใช้ Tweak (รองรับหลายไฟล์เกม) ---
function Do-Apply($exes) {
    $sel = @($script:checks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($sel.Count -eq 0) { Log 'ยังไม่ได้เลือก Tweak'; return }
    $exes = @(@($exes) | Where-Object { Has-Exe $_ })

    $snap = Load-Snap
    if (-not $snap.Time) {
        try {
            Checkpoint-Computer -Description 'TanagetBoostFPS' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Log 'สร้าง Restore Point ของ Windows แล้ว'
        } catch { Log 'ข้าม Restore Point (ระบบอาจปิดไว้ หรือเพิ่งสร้างภายใน 24 ชม.)' }
    }

    $jobs = @()
    foreach ($t in $sel) {
        if ($t.NeedsExe) {
            if ($exes.Count -eq 0) { Log "ข้าม: $($t.Name) (ยังไม่ได้เลือกไฟล์เกม)"; continue }
            foreach ($e in $exes) { $jobs += @{ T = $t; Exe = $e } }
        } else {
            $jobs += @{ T = $t; Exe = '' }
        }
    }
    foreach ($j in $jobs) {
        try { Capture-Tweak $j.T $j.Exe $snap } catch { Log "เก็บค่าเดิมไม่ได้: $($j.T.Name)" }
    }
    if (-not $snap.Time) { $snap.Time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
    Save-Snap $snap

    foreach ($j in $jobs) {
        try {
            Apply-Tweak $j.T $j.Exe
            $lab = $j.T.Name
            if ($j.Exe) { $lab = "$lab [" + (Split-Path $j.Exe -Leaf) + "]" }
            Log "OK  : $lab"
        } catch { Log "ผิดพลาด: $($j.T.Name) -> $($_.Exception.Message)" }
    }
    Save-Settings
    Update-SnapLabel
    Log 'เสร็จแล้ว - รีสตาร์ทเครื่อง 1 ครั้งเพื่อให้ครบทุกอย่าง'
}

function Show-Page($n) {
    $script:page = $n
    foreach ($k in 1, 2) {
        foreach ($c in $script:pages[$k]) { $c.Visible = ($k -eq $n) }
    }
    $form.BackgroundImage = $script:bgs[$n]
    Style-Btn $btnNav1 ($n -eq 1)
    Style-Btn $btnNav2 ($n -eq 2)
    if ($n -eq 2) { try { Update-CacheSizes } catch {} }
    $form.Invalidate($true)
}

# =====================================================================
#   หน้า 2 : เครื่องมือ
# =====================================================================
$script:curPage = 2

# ---------- LIVE MONITOR ----------
$script:mon = @{ Cpu = 0; Gpu = $null; Top = @() }
$script:fTiny = New-Object Drawing.Font('Segoe UI', 8.5)
$script:fLab  = New-Object Drawing.Font('Segoe UI Semibold', 9)
$script:brAcc = New-Object Drawing.SolidBrush($script:cAcc2)

$monPanel = New-Object Windows.Forms.Panel
$monPanel.Location = New-Object Drawing.Point(36, 144)
$monPanel.Size = New-Object Drawing.Size(408, 156)
$monPanel.BackColor = [Drawing.Color]::Transparent
$monPanel.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($monPanel, $true, $null)
Track $monPanel

$monPanel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'ClearTypeGridFit'
    $m = $script:mon
    Draw-Stat $g 0 0 236 'CPU' ("{0}%" -f $m.Cpu) $m.Cpu
    if ($m.Gpu) {
        $gp = $m.Gpu
        Draw-Stat $g 0 40 236 'GPU' ("{0}%" -f $gp.Util) $gp.Util
        $vp = 0
        if ($gp.MemTotal -gt 0) { $vp = [int](100 * $gp.MemUsed / $gp.MemTotal) }
        Draw-Stat $g 0 80 236 'VRAM' ("{0:N1} / {1:N1} GB" -f ($gp.MemUsed / 1024), ($gp.MemTotal / 1024)) $vp
        $g.DrawString(("GPU Temp {0} °C     Clock {1} MHz" -f $gp.Temp, $gp.Clock), $script:fTiny, $script:brText, 0, 124)
    } else {
        $g.DrawString('ไม่พบ nvidia-smi (ต้องมีไดรเวอร์การ์ดจอ NVIDIA)', $script:fTiny, $script:brDim, 0, 44)
        $g.DrawString('CPU Temp: ต้องใช้โปรแกรมอื่น เช่น HWiNFO', $script:fTiny, $script:brDim, 0, 64)
    }
    $g.DrawString('TOP RAM', $script:fLab, $script:brAcc, 256, 0)
    $yy = 24
    foreach ($t in $m.Top) {
        $nm = "$($t.N)"
        if ($nm.Length -gt 13) { $nm = $nm.Substring(0, 13) }
        $g.DrawString(("{0}  {1} MB" -f $nm, $t.MB), $script:fTiny, $script:brText, 256, $yy)
        $yy += 22
    }
})

# ---------- AUTO-BOOST ----------
$chkAB = New-Chk 'เปิด Auto-Boost (ตรวจจับเกมในโปรไฟล์)' 496 140 408 24 $false
$chkAB.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
$chkABram  = New-Chk 'ล้างแรมให้ (รอ 30 วินาทีให้เกมโหลดก่อน)' 514 168 390 22 $true
$chkABprio = New-Chk 'ตั้ง Priority = High ให้โปรเซสเกมตอนเปิด' 514 192 390 22 $true
$chkABkill = New-Chk 'ปิดแอปในรายการ Boost อัตโนมัติ (ไม่ถามซ้ำ)' 514 216 390 22 $false
$lblAB = New-Lbl 'สถานะ: ปิดอยู่' 496 246 408 44 9 $script:cDim $false

# ---------- GAME PROFILES ----------
$lstProf = New-Object Windows.Forms.ListBox
$lstProf.Location = New-Object Drawing.Point(36, 350)
$lstProf.Size = New-Object Drawing.Size(408, 150)
$lstProf.BorderStyle = 'FixedSingle'
$lstProf.BackColor = $script:cInput
$lstProf.ForeColor = $script:cText
$lstProf.HorizontalScrollbar = $true
$lstProf.Font = New-Object Drawing.Font('Segoe UI', 9)
Track $lstProf
$btnProfAdd  = New-Btn 'เพิ่มจากไฟล์เกมที่เลือก' 36 508 200 32 $false
$btnProfDel  = New-Btn 'ลบที่เลือก' 244 508 80 32 $false
$btnProfLoad = New-Btn 'โหลดไปหน้าหลัก' 332 508 112 32 $false
$btnProfAll  = New-Btn 'ใช้ Tweak กับทุกเกมในโปรไฟล์' 36 546 408 30 $true
$tip.SetToolTip($btnProfAdd, 'เพิ่มไฟล์เกมที่ระบุในหน้าหลักเข้าโปรไฟล์ (ใช้กับ Auto-Boost และล้างแรมจะไม่แตะเกมเหล่านี้)')

# ---------- CACHE CLEANER ----------
$script:cacheItems = @(
    @{ Name = 'ไฟล์ Temp ของผู้ใช้ + Windows'; Paths = @("$env:TEMP", "$env:WINDIR\Temp"); Default = $true },
    @{ Name = 'Windows Shader Cache (D3DSCache)'; Paths = @("$env:LOCALAPPDATA\D3DSCache"); Default = $true },
    @{ Name = 'NVIDIA Shader Cache (DXCache/GLCache)'; Paths = @("$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache", "$env:ProgramData\NVIDIA Corporation\NV_Cache"); Default = $false },
    @{ Name = 'แคชเซิร์ฟเวอร์ FiveM (server-cache)'; Paths = @("$env:LOCALAPPDATA\FiveM\FiveM.app\data\server-cache", "$env:LOCALAPPDATA\FiveM\FiveM.app\data\server-cache-priv"); Default = $false },
    @{ Name = 'Crash dump / Error report'; Paths = @("$env:LOCALAPPDATA\CrashDumps", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"); Default = $false },
    @{ Name = 'ถังขยะ (Recycle Bin)'; Special = 'recycle'; Paths = @(); Default = $false }
)
$script:cacheChecks = @()
$cy = 348
foreach ($it in $script:cacheItems) {
    $cb = New-Chk $it.Name 496 $cy 408 24 $it.Default
    $cb.Tag = $it
    $script:cacheChecks += $cb
    $cy += 26
}
$btnScan  = New-Btn 'สแกนขนาด' 496 520 196 34 $false
$btnCache = New-Btn 'ล้างที่เลือก' 700 520 204 34 $true
[void](New-Lbl 'Shader Cache: เกมอาจกระตุกรอบแรก  |  แคช FiveM: โหลดใหม่ตอนเข้าเซิร์ฟ' 496 558 410 18 8 $script:cDim $false)

$script:curPage = 0

# ---------- Log ----------
$log = New-Object Windows.Forms.TextBox
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.Location = New-Object Drawing.Point(20, 637)
$log.Size = New-Object Drawing.Size(900, 52)
$log.BorderStyle = 'FixedSingle'
$log.BackColor = $script:cInput
$log.ForeColor = Col '#CDB8FF'
$log.Font = New-Object Drawing.Font('Consolas', 8.5)
Track $log

function Log($m) { $log.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $m)) }

function Update-SnapLabel {
    if (Test-Path -LiteralPath $script:SnapFile) {
        $s = Load-Snap
        $lblSnap.Text = "Snapshot ก่อนรัน: บันทึกไว้เมื่อ $($s.Time)`nกด 'คืนค่าก่อนรัน' เพื่อย้อนกลับได้เลย"
        $lblSnap.ForeColor = $script:cAcc2
    } else {
        $lblSnap.Text = "ยังไม่มี Snapshot`n(จะบันทึกค่าเดิมให้อัตโนมัติตอนกด 'ใช้ Tweak' ครั้งแรก)"
        $lblSnap.ForeColor = $script:cDim
    }
}

# ---------- บันทึก/โหลดการตั้งค่า ----------
function Save-Settings {
    try {
        if (-not (Test-Path -LiteralPath $script:SnapDir)) { New-Item -ItemType Directory -Path $script:SnapDir -Force | Out-Null }
        $o = @{
            Exe = $txtExe.Text; Kill = $txtKill.Text; Auto = [bool]$chkAuto.Checked; Th = [int]$numTh.Value
            AB = [bool]$chkAB.Checked; ABram = [bool]$chkABram.Checked; ABprio = [bool]$chkABprio.Checked; ABkill = [bool]$chkABkill.Checked
            Profiles = @($script:profiles | ForEach-Object { @{ Name = $_.Name; Exe = $_.Exe } })
        }
        ConvertTo-Json -InputObject $o -Depth 4 | Set-Content -LiteralPath $script:SetFile -Encoding UTF8
    } catch { }
}
function Load-Settings {
    try {
        if (Test-Path -LiteralPath $script:SetFile) {
            $o = Get-Content -LiteralPath $script:SetFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($o.Exe) { $txtExe.Text = $o.Exe }
            if ($o.Kill) { $txtKill.Text = $o.Kill }
            if ($o.Th) { $numTh.Value = [math]::Min(95, [math]::Max(50, [int]$o.Th)) }
            $chkAuto.Checked = [bool]$o.Auto
            if ($null -ne $o.AB) { $chkAB.Checked = [bool]$o.AB }
            if ($null -ne $o.ABram) { $chkABram.Checked = [bool]$o.ABram }
            if ($null -ne $o.ABprio) { $chkABprio.Checked = [bool]$o.ABprio }
            if ($null -ne $o.ABkill) { $chkABkill.Checked = [bool]$o.ABkill }
            foreach ($p in @($o.Profiles)) {
                if ($p -and $p.Exe) { $script:profiles += @{ Name = "$($p.Name)"; Exe = "$($p.Exe)" } }
            }
        }
    } catch { }
}

# =====================================================================
#   เหตุการณ์ของปุ่ม
# =====================================================================
$chkAggro.Add_CheckedChanged({
    foreach ($c in $script:checks) {
        if ($c.Tag.Aggressive) { $c.Checked = $chkAggro.Checked }
    }
})

$btnBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Game executable (*.exe)|*.exe'
    if ($dlg.ShowDialog() -eq 'OK') { $txtExe.Text = $dlg.FileName }
})

$btnFive.Add_Click({
    $f = Find-FiveMExe
    if ($f) {
        $txtExe.Text = $f
        Log "พบ FiveM: $(Split-Path $f -Leaf)"
    } else {
        $fm = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.exe'
        if (Test-Path -LiteralPath $fm) { $txtExe.Text = $fm; Log 'ไม่พบ GTAProcess ใช้ FiveM.exe แทน' }
        else { Log 'ไม่พบ FiveM ในเครื่อง (ลองกด เลือก... แล้วชี้ไฟล์เอง)' }
    }
})

$btnStartup.Add_Click({
    try { Start-Process taskmgr.exe; Log 'เปิด Task Manager แล้ว -> แท็บ Startup apps -> Disable ตัวที่ไม่ใช้' }
    catch { Log "เปิด Task Manager ไม่ได้: $($_.Exception.Message)" }
})

$btnClean.Add_Click({ Do-Clean 'manual' })

$btnApply.Add_Click({ Do-Apply @($txtExe.Text.Trim()) })
$btnGtaReduce.Add_Click({ Apply-GtaReduce })
$btnGtaRestore.Add_Click({ Restore-GtaSettings })

$btnRestore.Add_Click({
    if (-not (Test-Path -LiteralPath $script:SnapFile)) {
        [void][Windows.Forms.MessageBox]::Show("ยังไม่มี Snapshot ครับ (ยังไม่เคยกด 'ใช้ Tweak' ผ่านเวอร์ชันนี้)`nถ้าเคยรันเวอร์ชันเก่ามาแล้ว ให้ใช้ปุ่ม 'คืนค่า Windows' แทน", 'Tanaget Boost FPS', 'OK', 'Information')
        return
    }
    Restore-Snapshot
    Update-SnapLabel
    Log 'คืนค่าเป็นค่าก่อนรันเรียบร้อย - รีสตาร์ทเครื่อง/Sign out เพื่อให้ครบ'
})

$btnDefault.Add_Click({
    $ans = [Windows.Forms.MessageBox]::Show("จะรีเซ็ตทุก Tweak ของโปรแกรมนี้เป็นค่าเริ่มต้นของ Windows`n(ไม่ใช่ค่าก่อนรัน) ต้องการดำเนินการต่อ?", 'ยืนยัน', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    try { Restore-Defaults $txtExe.Text.Trim(); Log 'คืนค่าเริ่มต้นของ Windows แล้ว - รีสตาร์ทเครื่อง/Sign out เพื่อให้ครบ' }
    catch { Log "ผิดพลาด: $($_.Exception.Message)" }
})

$btnBoost.Add_Click({
    $names = @($txtKill.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $running = @()
    foreach ($n in $names) { $running += @(Get-Process -Name $n -ErrorAction SilentlyContinue) }
    if ($running.Count -gt 0) {
        $list = ($running | Select-Object -ExpandProperty Name -Unique) -join ', '
        $ans = [Windows.Forms.MessageBox]::Show("จะปิดโปรแกรมเหล่านี้:`n$list`n`nงานที่ยังไม่ได้เซฟอาจหาย ต้องการดำเนินการต่อ?", 'ยืนยัน', 'YesNo', 'Warning')
        if ($ans -eq 'Yes') {
            $running | Stop-Process -Force -ErrorAction SilentlyContinue
            Log "ปิดแล้ว: $list"
        } else { Log 'ยกเลิกการปิดแอป' }
    } else { Log 'ไม่มีโปรแกรมในรายการที่กำลังรันอยู่' }

    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:WINDIR\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Log 'ล้างไฟล์ Temp แล้ว'
    Do-Clean 'manual'
})

# ---------- Timer: อัปเดตมิเตอร์ + ล้างอัตโนมัติ ----------
# ---------- ปุ่มสลับหน้า ----------
$btnNav1.Add_Click({ Show-Page 1 })
$btnNav2.Add_Click({ Show-Page 2 })

# ---------- โปรไฟล์เกม ----------
$btnProfAdd.Add_Click({
    $exe = $txtExe.Text.Trim()
    if (-not (Has-Exe $exe)) { Log 'ไปเลือกไฟล์เกมที่หน้าหลักก่อน (ปุ่ม เลือก... หรือ FiveM)'; return }
    $dup = @($script:profiles | Where-Object { $_.Exe -eq $exe })
    if ($dup.Count -gt 0) { Log 'มีโปรไฟล์นี้อยู่แล้ว'; return }
    $nm = [IO.Path]::GetFileNameWithoutExtension($exe)
    if ($nm -like 'FiveM*GTAProcess*') { $nm = 'FiveM' }
    $script:profiles += @{ Name = $nm; Exe = $exe }
    Refresh-Profiles
    Save-Settings
    Log "เพิ่มโปรไฟล์: $nm"
})

$btnProfDel.Add_Click({
    $i = $lstProf.SelectedIndex
    if ($i -lt 0) { Log 'เลือกโปรไฟล์ในรายการก่อน'; return }
    $new = @()
    for ($k = 0; $k -lt $script:profiles.Count; $k++) { if ($k -ne $i) { $new += $script:profiles[$k] } }
    $script:profiles = $new
    Refresh-Profiles
    Save-Settings
    Log 'ลบโปรไฟล์แล้ว'
})

$btnProfLoad.Add_Click({ Load-Profile $lstProf.SelectedIndex })
$lstProf.Add_DoubleClick({ Load-Profile $lstProf.SelectedIndex })

$btnProfAll.Add_Click({
    $ex = @($script:profiles | ForEach-Object { $_.Exe })
    if ($ex.Count -eq 0) { Log 'ยังไม่มีโปรไฟล์เกม'; return }
    Do-Apply $ex
})

# ---------- ล้างแคช ----------
$btnScan.Add_Click({
    Update-CacheSizes
    Log 'สแกนขนาดแคชแล้ว'
})

$btnCache.Add_Click({
    $sel = @($script:cacheChecks | Where-Object { $_.Checked })
    if ($sel.Count -eq 0) { Log 'ยังไม่ได้เลือกรายการแคช'; return }
    $names = ($sel | ForEach-Object { $_.Tag.Name }) -join "`n- "
    $ans = [Windows.Forms.MessageBox]::Show("จะล้าง:`n- $names`n`nไฟล์ที่กำลังใช้งานอยู่จะถูกข้าม ต้องการดำเนินการต่อ?", 'ยืนยัน', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { Log 'ยกเลิกการล้างแคช'; return }

    $wantsFiveM = @($sel | Where-Object { $_.Tag.Name -like '*FiveM*' }).Count -gt 0
    if ($wantsFiveM -and (Test-FiveMRunning)) {
        $ans2 = [Windows.Forms.MessageBox]::Show("ตรวจพบว่า FiveM/GTA5 กำลังเปิดอยู่`nไฟล์แคชที่เกมล็อกไว้จะลบไม่ได้ แนะนำให้ปิดเกมก่อนแล้วค่อยล้างแคช`n`nดำเนินการต่อเลยไหม? (ไฟล์ที่ล็อกอยู่จะถูกข้าม)", 'FiveM กำลังเปิดอยู่', 'YesNo', 'Warning')
        if ($ans2 -ne 'Yes') { Log 'ยกเลิกการล้างแคช (ปิด FiveM ก่อนแล้วลองใหม่)'; return }
    }

    $form.Cursor = [Windows.Forms.Cursors]::WaitCursor
    try {
        $total = 0.0
        $totalLocked = 0
        foreach ($c in $sel) {
            $it = $c.Tag
            if ($it.Special -eq 'recycle') {
                try { Clear-RecycleBin -Force -ErrorAction Stop; Log 'ล้างถังขยะแล้ว' } catch { Log 'ถังขยะว่างอยู่แล้ว/ล้างไม่ได้' }
                continue
            }
            $before = Get-PathSize $it.Paths
            $locked = Clear-Paths $it.Paths
            $after = Get-PathSize $it.Paths
            $freed = [math]::Max(0, ($before - $after))
            $total += $freed
            $totalLocked += $locked
            if ($locked -gt 0) {
                Log ("ล้าง {0}: {1:N0} MB (มีไฟล์ล็อกอยู่ {2} รายการ ลบไม่ได้ - ปิดโปรแกรมที่ใช้ไฟล์นั้นแล้วลองใหม่)" -f $it.Name, ($freed / 1MB), $locked)
            } else {
                Log ("ล้าง {0}: {1:N0} MB" -f $it.Name, ($freed / 1MB))
            }
        }
        Log ("รวมพื้นที่ที่ล้างได้ {0:N0} MB" -f ($total / 1MB))
        if ($totalLocked -gt 0) { Log 'หมายเหตุ: มีไฟล์แคชบางรายการลบไม่ได้เพราะถูกโปรแกรมอื่นล็อกอยู่ (เช่น FiveM ยังเปิดอยู่) ปิดโปรแกรมแล้วกด "ล้างที่เลือก" ซ้ำอีกครั้ง' }
        Update-CacheSizes
    } finally { $form.Cursor = [Windows.Forms.Cursors]::Default }
})

# ---------- Timer: มิเตอร์ + ล้างแรมอัตโนมัติ + มอนิเตอร์ ----------
$script:tick = 0
[void][TbfNative]::Cpu()
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    $script:mem = Get-Mem
    $meter.Invalidate()
    $script:mon.Cpu = [TbfNative]::Cpu()
    if ($script:page -eq 2 -and $form.WindowState -ne 'Minimized') {
        $script:tick++
        if ($script:tick % 2 -eq 1) {
            $script:mon.Gpu = Get-GpuInfo
            $script:mon.Top = Get-TopProcs
        }
        $monPanel.Invalidate()
    }
    if ($chkAuto.Checked -and $script:mem.Pct -ge $numTh.Value -and ((Get-Date) - $script:LastClean).TotalSeconds -ge 45) {
        Do-Clean 'auto'
    }
})
$timer.Start()

# ---------- Timer: Auto-Boost ----------
$abTimer = New-Object Windows.Forms.Timer
$abTimer.Interval = 3000
$abTimer.Add_Tick({
    if (-not $chkAB.Checked) { $lblAB.Text = 'สถานะ: ปิดอยู่'; $script:abRunning = $false; return }
    if ($script:profiles.Count -eq 0) { $lblAB.Text = 'สถานะ: ยังไม่มีโปรไฟล์เกม - เพิ่มที่ช่อง GAME PROFILES'; return }
    $gm = Get-RunningGame
    if ($gm) {
        if (-not $script:abRunning) {
            $script:abRunning = $true
            $script:abPending = $true
            $script:abStart = Get-Date
            Log "[AUTO-BOOST] ตรวจพบเกม: $($gm.Name)"
            if ($chkABprio.Checked) {
                try { $gm.Proc.PriorityClass = [Diagnostics.ProcessPriorityClass]::High; Log '[AUTO-BOOST] ตั้ง Priority = High แล้ว' }
                catch { Log '[AUTO-BOOST] ตั้ง Priority ไม่ได้' }
            }
            if ($chkABkill.Checked) {
                $names = @($txtKill.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $killed = @()
                foreach ($n in $names) {
                    foreach ($pr in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
                        try { $pr | Stop-Process -Force -ErrorAction Stop; $killed += $pr.ProcessName } catch { }
                    }
                }
                if ($killed.Count -gt 0) { Log ("[AUTO-BOOST] ปิดแล้ว: " + ((@($killed) | Select-Object -Unique) -join ', ')) }
            }
        }
        $lblAB.Text = "สถานะ: กำลังเล่น $($gm.Name)"
        if ($script:abPending -and $chkABram.Checked -and ((Get-Date) - $script:abStart).TotalSeconds -ge 30) {
            $script:abPending = $false
            Do-Clean 'autoboost'
        }
    } else {
        if ($script:abRunning) {
            $script:abRunning = $false
            $script:abPending = $false
            Log '[AUTO-BOOST] เกมปิดแล้ว'
        }
        $lblAB.Text = 'สถานะ: รอเกมเปิด...'
    }
})
$abTimer.Start()

$form.Add_FormClosing({ $timer.Stop(); $abTimer.Stop(); Save-Settings; if ($script:hk) { $script:hk.Dispose() } })

# ---------- เริ่มต้น ----------
Load-Settings

# ให้โปรไฟล์/ช่องไฟล์เกมของ FiveM ชี้ไฟล์เวอร์ชันล่าสุด (ชื่อไฟล์เปลี่ยนตามบิลด์)
for ($k = 0; $k -lt $script:profiles.Count; $k++) {
    $pf = $script:profiles[$k]
    if ((Get-ProfileMatch $pf.Exe) -eq 'FiveM*GTAProcess*' -and -not (Has-Exe $pf.Exe)) {
        $nf = Find-FiveMExe
        if ($nf) { $script:profiles[$k].Exe = $nf; Log "อัปเดตโปรไฟล์ FiveM -> $(Split-Path $nf -Leaf)" }
    }
}
if ($txtExe.Text -and -not (Has-Exe $txtExe.Text) -and ((Get-ProfileMatch $txtExe.Text) -eq 'FiveM*GTAProcess*')) {
    $nf = Find-FiveMExe
    if ($nf) { $txtExe.Text = $nf; Log "อัปเดตไฟล์เกม FiveM -> $(Split-Path $nf -Leaf)" }
}
Refresh-Profiles
Update-SnapLabel
Show-Page 1
Log 'พร้อมใช้งาน - เลือกไฟล์เกม (หรือกดปุ่ม FiveM) แล้วกด ใช้ Tweak ที่เลือก | หน้า เครื่องมือ: มอนิเตอร์/Auto-Boost/โปรไฟล์/ล้างแคช'
if ($ramGB -le 4.5) {
    $chkAggro.Checked = $true
    Log "RAM น้อย ($ramGB GB) -> เปิด 'โหมดเครื่องอ่อนสุด' ให้อัตโนมัติ"
}

$script:hk = New-Object TbfHotkey
if ($script:hk.Ok) {
    $script:hk.add_Pressed({ Do-Clean 'hotkey'; [Media.SystemSounds]::Asterisk.Play() })
    Log 'ปุ่มลัด Ctrl+Alt+R พร้อมใช้ - กดตอนเล่นเกมเพื่อล้างแรม (ไม่ปิดเกม)'
} else {
    Log 'ลงทะเบียนปุ่มลัด Ctrl+Alt+R ไม่ได้ (อาจมีโปรแกรมอื่นใช้ปุ่มนี้อยู่)'
}

[TbfNative]::HideConsole()
[void]$form.ShowDialog()

} catch {
    [void][Windows.Forms.MessageBox]::Show(($_ | Out-String), 'Tanaget Boost FPS - Error', 'OK', 'Error')
}
