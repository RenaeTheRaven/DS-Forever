#!/usr/bin/env python3
# custom-thor: runs the native Linux Sunshine for DS Forever Desktop's stand-in sunshine.exe (see README.md).
#
# Desktop runs under Wine/Proton inside a container; this helper runs outside it, started by the launcher. The stand-in connects
# on 127.0.0.1, proves the launcher's token and names the config file; the helper runs Sunshine with it and ends Sunshine when the
# stand-in goes away (Desktop stopped or restarted it). Only the launcher's own Sunshine is ever run, only with a file named
# sunshine.linux.conf, and only for a caller holding the token.
#
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import hmac
import json
import os
import select
import signal
import socketserver
import subprocess
import sys
import threading
import time

ARGS = None
TOKEN = ""
LOG_LOCK = threading.Lock()
RUNNING = set()   # every Sunshine this helper started and has not seen end


def log(msg):
    with LOG_LOCK:
        sys.stderr.write(time.strftime("%m-%d %H:%M:%S ") + msg + "\n")
        sys.stderr.flush()


def extra_settings():
    """name=value lines of the user's sunshine-extra.conf, as Sunshine's command-line overrides"""
    out = []
    try:
        with open(ARGS.extra, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                name, value = line.split("=", 1)
                out.append(name.strip() + "=" + value.strip())
    except FileNotFoundError:
        pass
    return out


def signal_group(proc, sig):
    try:
        os.killpg(proc.pid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def stop(proc):
    """ends Sunshine: AppRun is a script with the real sunshine as its child, so the whole process group is ended"""
    signal_group(proc, signal.SIGTERM)
    try:
        proc.wait(8)
    except subprocess.TimeoutExpired:
        pass
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            os.killpg(proc.pid, 0)
        except (ProcessLookupError, PermissionError):
            return
        time.sleep(0.2)
    signal_group(proc, signal.SIGKILL)
    proc.wait()


class Handler(socketserver.StreamRequestHandler):
    def reply(self, text):
        try:
            self.wfile.write((text + "\n").encode())
            self.wfile.flush()
        except OSError:
            pass

    def handle(self):
        try:
            req = json.loads(self.rfile.readline(65536).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return self.reply("error bad request")
        if not isinstance(req, dict) or not hmac.compare_digest(str(req.get("token", "")), TOKEN):
            return self.reply("error wrong token")
        conf = str(req.get("conf", ""))
        if os.path.basename(conf) != "sunshine.linux.conf" or not os.path.isfile(conf):
            return self.reply("error no such config")
        cmd = [ARGS.sunshine, conf]
        creds = req.get("creds")
        if creds is not None:
            if not (isinstance(creds, list) and len(creds) == 2 and all(isinstance(c, str) for c in creds)):
                return self.reply("error bad creds")
            cmd += ["--creds", creds[0], creds[1]]
        else:
            cmd += extra_settings()
        log("starting Sunshine" + (" (setting its login)" if creds is not None else ": " + " ".join(cmd[1:])))
        with open(ARGS.log, "ab") as out:
            proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=out, stderr=out, cwd=os.path.dirname(conf),
                                    start_new_session=True)
        RUNNING.add(proc)
        try:
            while proc.poll() is None:
                # the stand-in sends nothing more: readable means it has gone, and Sunshine goes with it
                readable, _, _ = select.select([self.connection], [], [], 0.5)
                if readable and not self.connection.recv(4096):
                    log("the stand-in has gone: stopping Sunshine")
                    stop(proc)
                    return
        finally:
            stop(proc)
            RUNNING.discard(proc)
        log("Sunshine ended with code %s" % proc.returncode)
        self.reply("exit %d" % (proc.returncode if proc.returncode is not None and proc.returncode >= 0 else 1))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    global ARGS, TOKEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--sunshine", required=True, help="the native Sunshine to run (the extracted AppImage's AppRun)")
    ap.add_argument("--extra", required=True, help="the user's extra Sunshine settings (name = value lines)")
    ap.add_argument("--log", required=True, help="where Sunshine's own console output goes")
    ARGS = ap.parse_args()
    TOKEN = os.environ.pop("DSF_SUNSHINE_HELPER_TOKEN", "")
    if len(TOKEN) < 16:
        sys.exit("DSF_SUNSHINE_HELPER_TOKEN is not set")
    with Server(("127.0.0.1", ARGS.port), Handler) as srv:
        signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=srv.shutdown, daemon=True).start())
        log("helper listening on 127.0.0.1:%d" % ARGS.port)
        try:
            srv.serve_forever()
        finally:
            # the launcher is closing: no Sunshine of ours stays behind
            for proc in list(RUNNING):
                stop(proc)


if __name__ == "__main__":
    main()
