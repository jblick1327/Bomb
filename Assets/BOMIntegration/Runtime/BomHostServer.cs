using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using Debug = UnityEngine.Debug;

namespace Bom.Unity
{
    // C5: the native BOM-server.exe a hosting player starts from the main menu. Odin stays the only authority; this class
    // only starts, watches and stops the process. Every server is put in one Windows job object with kill-on-close, so the
    // OS kills it when this player exits for any reason (quit, crash, Task Manager). Quit and return-to-menu also stop it.
    public sealed class BomHostServer : IDisposable
    {
        public const string ListeningText = "BOM staging server listening";
        const string BindFailedText = "Could not bind UDP port";
        public readonly Process Process;
        public readonly uint Port;
        public readonly string Bind,
            LogPath;
        readonly object gate = new object();
        StreamWriter log;
        volatile bool listening,
            bindFailed;
        public bool Listening => listening;
        public bool BindFailed => bindFailed;
        public bool Exited
        {
            get
            {
                try { return Process.HasExited; }
                catch (InvalidOperationException) { return true; }
            }
        }
        public int Pid { get; }

        // Package layout (decided in C5; F4 packages it): BOM-server.exe sits in a "Server" folder next to the game exe,
        // and level layouts in "Server/levels/<file>". The current BOM-Windows package keeps Server/ and yard.json one
        // folder above the player (Mono/, IL2CPP/), so that is the fallback. --bom-server and --bom-levels override both.
        public static string GameFolder => Path.GetDirectoryName(UnityEngine.Application.dataPath);

        public static string FindServer()
        {
            string arg = Arg("--bom-server");
            if (!string.IsNullOrEmpty(arg))
                return File.Exists(arg) ? Path.GetFullPath(arg) : null;
            foreach (string folder in new[] { GameFolder, Path.GetDirectoryName(GameFolder) })
            {
                if (string.IsNullOrEmpty(folder))
                    continue;
                string path = Path.Combine(folder, "Server", "BOM-server.exe");
                if (File.Exists(path))
                    return path;
            }
            return null;
        }

        public static string FindLayout(string file)
        {
            string arg = Arg("--bom-levels");
            if (!string.IsNullOrEmpty(arg))
                return File.Exists(Path.Combine(arg, file)) ? Path.GetFullPath(Path.Combine(arg, file)) : null;
            string parent = Path.GetDirectoryName(GameFolder);
            foreach (
                string path in new[]
                {
                    Path.Combine(GameFolder, "Server", "levels", file),
                    string.IsNullOrEmpty(parent) ? null : Path.Combine(parent, "Server", "levels", file),
                    string.IsNullOrEmpty(parent) ? null : Path.Combine(parent, file),
                }
            )
                if (path != null && File.Exists(path))
                    return path;
            return null;
        }

        static string Arg(string key)
        {
            var args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, key);
            return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
        }

        // 24 random bytes as base64: 32 characters, inside the server's 16..128 limit. Kept in memory only.
        public static string NewHostToken()
        {
            var bytes = new byte[24];
            using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create())
                rng.GetBytes(bytes);
            return Convert.ToBase64String(bytes);
        }

        // Conservative probe: an exclusive wildcard bind fails if anything holds the UDP port on any address. The server's
        // own bind result is still checked (BindFailed), because another program can take the port between the two.
        public static bool UdpPortFree(uint port)
        {
            try
            {
                using (var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
                {
                    socket.ExclusiveAddressUse = true;
                    socket.Bind(new IPEndPoint(IPAddress.Any, (int)port));
                }
                return true;
            }
            catch (SocketException)
            {
                return false;
            }
        }

        BomHostServer(string exe, string layout, string bind, uint port, string token, string logPath)
        {
            Port = port;
            Bind = bind;
            LogPath = logPath;
            Directory.CreateDirectory(Path.GetDirectoryName(logPath));
            log = new StreamWriter(logPath, false) { AutoFlush = true };
            log.WriteLine(
                "BOM FRONTDOOR server=" + exe + " bind=" + bind + " port=" + port + " layout=" + layout + " host-token=[in memory]"
            );
            var info = new ProcessStartInfo
            {
                FileName = exe,
                Arguments = "--bind " + bind + " --port " + port + " --layout \"" + layout + "\" --host-token " + token,
                WorkingDirectory = Path.GetDirectoryName(exe),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            Process = new Process { StartInfo = info, EnableRaisingEvents = true };
            Process.OutputDataReceived += (_, e) => Line(e.Data);
            Process.ErrorDataReceived += (_, e) => Line(e.Data);
            Process.Start();
            Pid = Process.Id;
            BomKillOnCloseJob.Assign(Process);
            Process.BeginOutputReadLine();
            Process.BeginErrorReadLine();
        }

        public static BomHostServer Start(string exe, string layout, string bind, uint port, string token, string logPath) =>
            new BomHostServer(exe, layout, bind, port, token, logPath);

        void Line(string line)
        {
            if (line == null)
                return;
            if (line.Contains(ListeningText))
                listening = true;
            if (line.Contains(BindFailedText))
                bindFailed = true;
            lock (gate)
                log?.WriteLine(line);
        }

        // Kills the server if it is still running and waits for it. Returns true if it had already exited.
        public bool Stop(string reason, int waitMs = 3000)
        {
            bool already = Exited;
            if (!already)
            {
                try { Process.Kill(); }
                catch (Exception error) { Debug.LogWarning("BOM FRONTDOOR SERVER kill failed pid=" + Pid + ": " + error.Message); }
            }
            bool gone = false;
            try { gone = Process.WaitForExit(waitMs); }
            catch (Exception) { gone = Exited; }
            string code = "?";
            try { if (gone) code = Process.ExitCode.ToString(); }
            catch (Exception) { }
            Debug.Log(
                "BOM FRONTDOOR SERVER stopped pid=" + Pid + " reason=" + reason + " exited_itself=" + already + " gone=" + gone + " exit=" + code
            );
            Dispose();
            return already;
        }

        public void Dispose()
        {
            lock (gate)
            {
                log?.Dispose();
                log = null;
            }
        }
    }

    // One job object per player process. JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: when the last handle closes (the player
    // exits or crashes), Windows kills every process in the job. The handle is never closed on purpose.
    static class BomKillOnCloseJob
    {
        static IntPtr job;
        static bool failed;

        public static void Assign(Process process)
        {
            try
            {
                if (job == IntPtr.Zero && !failed)
                {
                    job = CreateJobObject(IntPtr.Zero, null);
                    if (job == IntPtr.Zero)
                        throw new InvalidOperationException("CreateJobObject failed: " + Marshal.GetLastWin32Error());
                    var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                    info.BasicLimitInformation.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                    int size = Marshal.SizeOf<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>();
                    if (!SetInformationJobObject(job, 9, ref info, (uint)size)) // JobObjectExtendedLimitInformation
                        throw new InvalidOperationException("SetInformationJobObject failed: " + Marshal.GetLastWin32Error());
                }
                if (job == IntPtr.Zero)
                    return;
                if (!AssignProcessToJobObject(job, process.Handle))
                    throw new InvalidOperationException("AssignProcessToJobObject failed: " + Marshal.GetLastWin32Error());
                Debug.Log("BOM FRONTDOOR SERVER job kill_on_close=1 pid=" + process.Id);
            }
            catch (Exception error)
            {
                failed = true;
                // Quit and return-to-menu still stop the server; only a crash of this player could leave it running.
                Debug.LogWarning("BOM FRONTDOOR SERVER job unavailable: " + error.Message);
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct IO_COUNTERS
        {
            public ulong ReadOperationCount,
                WriteOperationCount,
                OtherOperationCount,
                ReadTransferCount,
                WriteTransferCount,
                OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateJobObject(IntPtr attributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint length);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    }
}
