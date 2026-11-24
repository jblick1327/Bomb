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

        // --bom-debug-blast S: the host window requests a blast every S seconds, cycling through fixed yard points
        // (where the owner clicked in the 2026-11-24 play session), to reproduce the post-blast slowdown unattended.
        // The server still decides everything; guests' requests are denied as usual.
        public static readonly double BlastEvery = Number(Environment.GetCommandLineArgs(), "--bom-debug-blast");
        static readonly float[] BlastPoints = { -3.6f, 11.0f, -1.4f, 7.5f, 1.6f, 11.3f, 4.3f, 10.8f, -5.5f, 8.2f, 1.1f, 10.2f, -2.0f, 11.6f, 7.7f, 9.1f };
        static double nextBlast;
        static int blastIndex;

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
            int i = blastIndex++ % (BlastPoints.Length / 2);
            x = BlastPoints[2 * i];
            y = BlastPoints[2 * i + 1];
            return true;
        }
    }
}
