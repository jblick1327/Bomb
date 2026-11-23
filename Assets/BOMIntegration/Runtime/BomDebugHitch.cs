using System;
using System.Globalization;
using System.Threading;

namespace Bom.Unity
{
    // Debug A/B tool for the native pump thread (ABI 1.7): --bom-debug-hitch-ms N --bom-debug-hitch-every S
    // makes Unity's main thread sleep N ms every S seconds. Off unless both are given; when off it is one bool test.
    public static class BomDebugHitch
    {
        static readonly int Milliseconds;
        static readonly double Every;
        static double next;
        public static readonly bool On;
        public static int Count { get; private set; }

        static BomDebugHitch()
        {
            var args = Environment.GetCommandLineArgs();
            Milliseconds = (int)Number(args, "--bom-debug-hitch-ms");
            Every = Number(args, "--bom-debug-hitch-every");
            On = Milliseconds > 0 && Every > 0;
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
            Thread.Sleep(Milliseconds);
        }
    }
}
