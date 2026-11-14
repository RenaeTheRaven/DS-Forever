/*
 * custom-thor: the stand-in sunshine.exe for DS Forever Desktop on a Linux PC.
 *
 * Desktop runs under Wine/Proton, where the Windows Sunshine cannot capture the screen. Desktop starts THIS program wherever it
 * would start sunshine.exe (DSF_SUNSHINE_DIR points here), with the same arguments:
 *
 *     sunshine.exe "<sunshine.conf>"                      run until ended
 *     sunshine.exe "<sunshine.conf>" --creds user pass    write the API login, then exit
 *
 * It rewrites Desktop's config for Linux (file paths; Windows-only settings dropped) as sunshine.linux.conf and asks the
 * launcher's helper (dsf-sunshine-helper.py, on 127.0.0.1) to run the native Sunshine with it. It lives as long as that Sunshine
 * does and the helper ends Sunshine when this program goes, so Desktop's start / stop / restart work as on Windows.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;

namespace DsfDesktop.Linux
{
    static class Program
    {
        /// <summary>settings whose value is a file path</summary>
        static readonly HashSet<string> PathKeys = new HashSet<string> { "file_state", "credentials_file", "file_apps", "cert", "pkey", "log_path" };

        /// <summary>settings that exist only in the Windows Sunshine, and output_name, whose Windows value (a display device id) means
        /// nothing here: the Linux one comes from the launcher's sunshine-extra.conf</summary>
        static readonly HashSet<string> Dropped = new HashSet<string>
        {
            "dd_configuration_option", "dd_resolution_option", "dd_refresh_rate_option", "dd_config_revert_on_disconnect",
            "install_steam_audio_drivers", "nvenc_opengl_vulkan_on_dxgi", "output_name",
        };

        static int Main(string[] args)
        {
            try { return Run(args); }
            catch (Exception e) { Console.Error.WriteLine("sunshine stand-in: " + e.Message); return 70; }
        }

        static int Run(string[] args)
        {
            string conf = null, user = null, pass = null;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--creds" && i + 2 < args.Length) { user = args[i + 1]; pass = args[i + 2]; i += 2; }
                else if (!args[i].StartsWith("--") && conf == null) conf = args[i];
            }
            if (conf == null || !File.Exists(conf)) { Console.Error.WriteLine("sunshine stand-in: no config file"); return 64; }

            var helper = (Environment.GetEnvironmentVariable("DSF_SUNSHINE_HELPER") ?? "").Split(new[] { ':' }, 2);
            if (helper.Length != 2 || !int.TryParse(helper[0], out int port))
            {
                Console.Error.WriteLine("sunshine stand-in: DSF_SUNSHINE_HELPER is not set (start Desktop with its Linux launcher)");
                return 78;
            }

            var linuxConf = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(conf)), "sunshine.linux.conf");
            File.WriteAllText(linuxConf, Translate(File.ReadAllLines(conf)), new UTF8Encoding(false));

            var request = new StringBuilder("{\"token\":").Append(Quote(helper[1])).Append(",\"conf\":").Append(Quote(UnixPath(linuxConf)));
            if (user != null) request.Append(",\"creds\":[").Append(Quote(user)).Append(',').Append(Quote(pass)).Append(']');
            request.Append("}\n");

            using (var tcp = new TcpClient())
            {
                tcp.Connect("127.0.0.1", port);
                var stream = tcp.GetStream();
                var bytes = Encoding.UTF8.GetBytes(request.ToString());
                stream.Write(bytes, 0, bytes.Length);
                // the helper answers "exit <code>" when Sunshine ends; until then this program is Sunshine, as far as Desktop can tell
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                {
                    string line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        if (line.StartsWith("exit ") && int.TryParse(line.Substring(5).Trim(), out int code)) return code;
                        if (line.StartsWith("error ")) { Console.Error.WriteLine("sunshine stand-in: " + line.Substring(6)); return 69; }
                    }
                }
            }
            return 69;
        }

        static string Translate(string[] lines)
        {
            var sb = new StringBuilder("# Written by DS Forever Desktop's Linux stand-in from sunshine.conf. Edits are replaced at the next start.\n");
            foreach (var raw in lines)
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                var key = line.Substring(0, eq).Trim();
                var value = line.Substring(eq + 1).Trim();
                if (Dropped.Contains(key)) continue;
                if (PathKeys.Contains(key)) value = UnixPath(value);
                sb.Append(key).Append(" = ").Append(value).Append('\n');
            }
            return sb.ToString();
        }

        /// <summary>a Windows path as the Linux path Wine maps it to</summary>
        static string UnixPath(string windowsPath)
        {
            var full = Path.GetFullPath(windowsPath.Replace('/', '\\'));
            try
            {
                var p = wine_get_unix_file_name(full);
                if (p != IntPtr.Zero)
                {
                    int n = 0;
                    while (Marshal.ReadByte(p, n) != 0) n++;
                    var buf = new byte[n];
                    Marshal.Copy(p, buf, 0, n);
                    var unix = Encoding.UTF8.GetString(buf);
                    if (unix.StartsWith("/")) return unix;
                }
            }
            catch (Exception) { }
            // no Wine export: only the Z: drive (the Linux root) can be told
            if (full.Length > 2 && (full[0] == 'Z' || full[0] == 'z') && full[1] == ':') return full.Substring(2).Replace('\\', '/');
            throw new InvalidOperationException("can't tell the Linux path of " + full);
        }

        static string Quote(string s)
        {
            var sb = new StringBuilder("\"");
            foreach (var c in s ?? "")
            {
                if (c == '"' || c == '\\') sb.Append('\\').Append(c);
                else if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                else sb.Append(c);
            }
            return sb.Append('"').ToString();
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr wine_get_unix_file_name(string dosPath);
    }
}
