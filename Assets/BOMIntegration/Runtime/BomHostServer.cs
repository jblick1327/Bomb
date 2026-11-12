using System;
using System.Text;
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
        public readonly uint Port;
        public readonly string Bind,
            LogPath;
        // F4: Unity's IL2CPP backend has no working System.Diagnostics.Process, so the server is started with CreateProcessW
        // for both backends. Output goes straight into the server log (an inheritable append handle); Listening and
        // BindFailed are read by tailing that file.
        IntPtr process,
            thread;
        string tailText = "";
        long tailOffset;
        bool listening,
            bindFailed;
        public bool Listening
        {
            get { Tail(); return listening; }
        }
        public bool BindFailed
        {
            get { Tail(); return bindFailed; }
        }
        public bool Exited => process == IntPtr.Zero || WaitForSingleObject(process, 0) == 0;
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
            File.WriteAllText(
                logPath,
                "BOM FRONTDOOR server=" + exe + " bind=" + bind + " port=" + port + " layout=" + layout + " host-token=[in memory]" + Environment.NewLine
            );
            IntPtr output = IntPtr.Zero;
            try
            {
                var attributes = new SECURITY_ATTRIBUTES { nLength = (uint)Marshal.SizeOf<SECURITY_ATTRIBUTES>(), bInheritHandle = 1 };
                // FILE_APPEND_DATA, share read+write, OPEN_EXISTING (the header line above is already there).
                output = CreateFileW(logPath, 0x4, 0x3, ref attributes, 3, 0x80, IntPtr.Zero);
                if (output == INVALID_HANDLE_VALUE)
                    throw new InvalidOperationException("Could not open the server log " + logPath + ": error " + Marshal.GetLastWin32Error());
                var startup = new STARTUPINFOW
                {
                    cb = (uint)Marshal.SizeOf<STARTUPINFOW>(),
                    dwFlags = 0x100, // STARTF_USESTDHANDLES
                    hStdOutput = output,
                    hStdError = output,
                };
                string command = "\"" + exe + "\" --bind " + bind + " --port " + port + " --layout \"" + layout + "\" --host-token " + token;
                // CREATE_SUSPENDED | CREATE_NO_WINDOW: the job object gets the process before its first instruction runs.
                if (!CreateProcessW(exe, command, IntPtr.Zero, IntPtr.Zero, true, 0x4 | 0x8000000, IntPtr.Zero, Path.GetDirectoryName(exe), ref startup, out var info))
                    throw new InvalidOperationException("CreateProcess failed for " + exe + ": error " + Marshal.GetLastWin32Error());
                process = info.hProcess;
                thread = info.hThread;
                Pid = (int)info.dwProcessId;
                BomKillOnCloseJob.Assign(process, Pid);
                if (ResumeThread(thread) == 0xFFFFFFFF)
                {
                    TerminateProcess(process, 1);
                    throw new InvalidOperationException("ResumeThread failed: error " + Marshal.GetLastWin32Error());
                }
            }
            catch
            {
                Dispose();
                throw;
            }
            finally
            {
                if (output != IntPtr.Zero && output != INVALID_HANDLE_VALUE)
                    CloseHandle(output); // the child holds its own copy
            }
        }

        void Tail()
        {
            try
            {
                using (var stream = new FileStream(LogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (stream.Length <= tailOffset)
                        return;
                    stream.Seek(tailOffset, SeekOrigin.Begin);
                    var bytes = new byte[stream.Length - tailOffset];
                    int read = stream.Read(bytes, 0, bytes.Length);
                    tailOffset += read;
                    tailText += Encoding.UTF8.GetString(bytes, 0, read);
                    if (tailText.Contains(ListeningText))
                        listening = true;
                    if (tailText.Contains(BindFailedText))
                        bindFailed = true;
                    if (tailText.Length > 4096)
                        tailText = tailText.Substring(tailText.Length - 256);
                }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }

        public static BomHostServer Start(string exe, string layout, string bind, uint port, string token, string logPath) =>
            new BomHostServer(exe, layout, bind, port, token, logPath);

        // Kills the server if it is still running and waits for it. Returns true if it had already exited.
        public bool Stop(string reason, int waitMs = 3000)
        {
            bool already = Exited;
            if (!already && !TerminateProcess(process, 1))
                Debug.LogWarning("BOM FRONTDOOR SERVER kill failed pid=" + Pid + ": error " + Marshal.GetLastWin32Error());
            bool gone = process == IntPtr.Zero || WaitForSingleObject(process, (uint)waitMs) == 0;
            string code = "?";
            if (gone && process != IntPtr.Zero && GetExitCodeProcess(process, out uint exit))
                code = exit.ToString();
            Tail();
            Debug.Log(
                "BOM FRONTDOOR SERVER stopped pid=" + Pid + " reason=" + reason + " exited_itself=" + already + " gone=" + gone + " exit=" + code
            );
            Dispose();
            return already;
        }

        public void Dispose()
        {
            if (thread != IntPtr.Zero) { CloseHandle(thread); thread = IntPtr.Zero; }
            if (process != IntPtr.Zero) { CloseHandle(process); process = IntPtr.Zero; }
        }

        static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        struct SECURITY_ATTRIBUTES
        {
            public uint nLength;
            public IntPtr lpSecurityDescriptor;
            public int bInheritHandle;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct STARTUPINFOW
        {
            public uint cb;
            public IntPtr lpReserved,
                lpDesktop,
                lpTitle;
            public uint dwX,
                dwY,
                dwXSize,
                dwYSize,
                dwXCountChars,
                dwYCountChars,
                dwFillAttribute,
                dwFlags;
            public ushort wShowWindow,
                cbReserved2;
            public IntPtr lpReserved2,
                hStdInput,
                hStdOutput,
                hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION
        {
            public IntPtr hProcess,
                hThread;
            public uint dwProcessId,
                dwThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateFileW(string name, uint access, uint share, ref SECURITY_ATTRIBUTES attributes, uint disposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcessW(
            string application,
            string commandLine,
            IntPtr processAttributes,
            IntPtr threadAttributes,
            bool inheritHandles,
            uint flags,
            IntPtr environment,
            string directory,
            ref STARTUPINFOW startup,
            out PROCESS_INFORMATION info
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr handle);
    }

    // One job object per player process. JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: when the last handle closes (the player
    // exits or crashes), Windows kills every process in the job. The handle is never closed on purpose.
    static class BomKillOnCloseJob
    {
        static IntPtr job;
        static bool failed;

        public static void Assign(IntPtr process, int pid)
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
                if (!AssignProcessToJobObject(job, process))
                    throw new InvalidOperationException("AssignProcessToJobObject failed: " + Marshal.GetLastWin32Error());
                Debug.Log("BOM FRONTDOOR SERVER job kill_on_close=1 pid=" + pid);
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
