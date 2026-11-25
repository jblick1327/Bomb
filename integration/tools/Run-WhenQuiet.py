"""Wait until the machine is on AC and the user has been idle, then run one command; watch both during the run.

The P4b Prediction gate needs a quiet, plugged-in machine (P4a: failures track machine stalls). This waits for
--idle-minutes of no keyboard/mouse input on AC power, runs the command, samples AC and input every 30 s, and
writes a JSON record saying whether the run stayed quiet. It never changes power settings.
Usage: python Run-WhenQuiet.py --out <dir> [--idle-minutes 10] [--give-up-hour 9] -- <command...>
"""
import argparse, ctypes, datetime, json, pathlib, subprocess, sys, threading, time


class _Power(ctypes.Structure):
    _fields_ = [('ACLineStatus', ctypes.c_ubyte), ('BatteryFlag', ctypes.c_ubyte), ('BatteryLifePercent', ctypes.c_ubyte),
                ('SystemStatusFlag', ctypes.c_ubyte), ('BatteryLifeTime', ctypes.c_ulong), ('BatteryFullLifeTime', ctypes.c_ulong)]


class _LastInput(ctypes.Structure):
    _fields_ = [('cbSize', ctypes.c_uint), ('dwTime', ctypes.c_uint)]


def on_ac():
    s = _Power()
    return bool(ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(s))) and s.ACLineStatus == 1


def idle_seconds():
    info = _LastInput(ctypes.sizeof(_LastInput), 0)
    ctypes.windll.user32.GetLastInputInfo(ctypes.byref(info))
    return ((ctypes.windll.kernel32.GetTickCount() - info.dwTime) & 0xFFFFFFFF) / 1000.0


def now():
    return datetime.datetime.now().isoformat(timespec='seconds')


p = argparse.ArgumentParser()
p.add_argument('--out', required=True)
p.add_argument('--idle-minutes', type=float, default=10)
p.add_argument('--give-up-hour', type=int, default=9, help='local hour after which it stops waiting (next morning)')
p.add_argument('command', nargs=argparse.REMAINDER)
a = p.parse_args()
command = a.command[1:] if a.command[:1] == ['--'] else a.command
out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
record = {'waiting_since': now(), 'idle_minutes': a.idle_minutes, 'command': command}
start_day = datetime.date.today()


def save():
    (out / 'quiet-run.json').write_text(json.dumps(record, indent=1), encoding='utf-8')


save()
while True:
    t = datetime.datetime.now()
    if t.date() > start_day and t.hour >= a.give_up_hour:
        record['outcome'] = 'gave up waiting'; record['gave_up_at'] = now(); save(); sys.exit(3)
    if on_ac() and idle_seconds() >= a.idle_minutes * 60:
        break
    time.sleep(30)

record['started'] = now(); save()
samples, quiet = [], {'ac_all': True, 'input_during_run': False}
done = threading.Event()


def watch():
    last_idle = idle_seconds()
    while not done.wait(30):
        ac, idle = on_ac(), idle_seconds()
        touched = idle < last_idle  # idle time went down: someone used the machine
        last_idle = idle
        samples.append({'t': now(), 'ac': ac, 'idle_s': round(idle), 'input': touched})
        quiet['ac_all'] &= ac
        quiet['input_during_run'] |= touched


watcher = threading.Thread(target=watch, daemon=True); watcher.start()
with open(out / 'command.log', 'w', encoding='utf-8') as log:
    code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
done.set(); watcher.join(timeout=5)
record.update(finished=now(), exit_code=code, quiet=quiet, samples=samples,
              outcome='quiet run' if quiet['ac_all'] and not quiet['input_during_run'] else 'NOT quiet: see samples')
save()
sys.exit(code)
