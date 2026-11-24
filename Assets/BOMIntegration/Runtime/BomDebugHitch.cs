using System;
using System.Globalization;
using System.Threading;

namespace Bom.Unity
{
    // Debug A/B tool for the native pump thread (ABI 1.7): --bom-debug-hitch-ms N --bom-debug-hitch-every S
    // keeps Unity's main thread busy for N ms every S seconds (a spin, like a real long frame, so the run with and
    // without the pump uses the same CPU; --bom-debug-hitch-sleep sleeps instead, as the first A/B did).
    // --bom-debug-move drives held move right/left every 1.5 s and a jump every 3 s, for players with nobody at
    // the keyboard. All off unless given; when off each is one bool test.
    public static class BomDebugHitch
    {
        static readonly int Milliseconds;
        static readonly double Every;
        static double next;
        public static readonly bool On, Sleeps, Moves;
        static double nextJump;
        public static int Count { get; private set; }

        static BomDebugHitch()
        {
            var args = Environment.GetCommandLineArgs();
            Milliseconds = (int)Number(args, "--bom-debug-hitch-ms");
            Every = Number(args, "--bom-debug-hitch-every");
            On = Milliseconds > 0 && Every > 0;
            Sleeps = Array.IndexOf(args, "--bom-debug-hitch-sleep") >= 0;
            Moves = Array.IndexOf(args, "--bom-debug-move") >= 0;
        }

        static double Number(string[] args, string name)
        {
            int i = Array.IndexOf(args, name);
            return
                i >= 0
                && i + 1 < args.Length
                && double.TryParse(args[i + 1], NumberStyles.Float, CultureInfo.InvariantCulture, out double value)
                && value > 0
                ? value
                : 0;
        }

        public static void Tick(double now)
        {
            if (!On)
                return;
            if (next == 0)
            {
                next = now + Every;
                return;
            }
            if (now < next)
                return;
            next = Math.Max(next + Every, now);
            Count++;
            if (Sleeps)
            {
                Thread.Sleep(Milliseconds);
                return;
            }
            var watch = System.Diagnostics.Stopwatch.StartNew();
            while (watch.Elapsed.TotalMilliseconds < Milliseconds) { }
        }

        public static float Move(double now) => now % 3 < 1.5 ? 1f : -1f;

        public static bool Jump(double now)
        {
            if (now < nextJump)
                return false;
            nextJump = now + 3;
            return true;
        }

        // --bom-debug-blast S: the host window requests a blast every S seconds to load destruction unattended.
        // It cycles eight columns across the yard (the server accepts x -8..9, y -3..12, aimed at empty space) and
        // follows each column's surface down: an accepted blast lowers that column's next aim 0.9 m (wrapping back
        // to the top below y -2.6), one refused for aiming inside solid (rubble refilling the crater) raises it 0.6 m.
        // The server still decides everything; guests' requests are denied as usual.
        public static readonly double BlastEvery = Number(Environment.GetCommandLineArgs(), "--bom-debug-blast");
        static readonly float[] BlastColumns = { -7f, 1f, 8f, -3f, 5f, -5f, 3f, -1f };
        static readonly float[] BlastAim = { 6.4f, 6.4f, 6.4f, 6.4f, 6.4f, 6.4f, 6.4f, 6.4f };
        static double nextBlast;
        static int blastIndex, lastColumn = -1;
        static ulong lastResult;
        public static int BlastsAccepted { get; private set; }
        public static int BlastsRefusedSolid { get; private set; }

        // Request results arrive in order; each is the answer to the most recent debug blast (one per S seconds).
        public static void BlastResult(ulong requestId, uint kind, uint status, uint reason)
        {
            if (BlastEvery <= 0 || kind != 1 || requestId <= lastResult || lastColumn < 0)
                return;
            lastResult = requestId;
            if (status == 1)
            {
                BlastsAccepted++;
                BlastAim[lastColumn] -= 0.9f;
                if (BlastAim[lastColumn] < -2.6f)
                    BlastAim[lastColumn] = 6.4f;
            }
            else if (status == 2 && reason == 5)
            {
                BlastsRefusedSolid++;
                BlastAim[lastColumn] = Math.Min(11.5f, BlastAim[lastColumn] + 0.6f);
            }
        }

        public static bool Blast(double now, out float x, out float y)
        {
            x = y = 0;
            if (BlastEvery <= 0)
                return false;
            if (nextBlast == 0)
                nextBlast = now + 10; // after the level load and first snapshot
            if (now < nextBlast)
                return false;
            nextBlast = now + BlastEvery;
            lastColumn = blastIndex++ % BlastColumns.Length;
            x = BlastColumns[lastColumn];
            y = BlastAim[lastColumn];
            return true;
        }
    }
}
