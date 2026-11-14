using System;
using System.Runtime.InteropServices;

namespace DsfDesktop
{
    /// <summary>
    /// custom-thor: Desktop on a Linux PC. It runs under Wine/Proton in the game's own prefix (so the WoW and Battle.net windows are
    /// ordinary windows to it), and the streaming host is a native Linux Sunshine that desktop/linux's stand-in sunshine.exe starts.
    /// </summary>
    public static class Host
    {
        static bool? wine;

        /// <summary>running under Wine (DSF_LINUX_HOST=1 forces it, =0 denies it)</summary>
        public static bool Wine
        {
            get
            {
                if (wine == null) wine = Detect();
                return wine.Value;
            }
        }

        static bool Detect()
        {
            var env = Environment.GetEnvironmentVariable("DSF_LINUX_HOST");
            if (env == "1") return true;
            if (env == "0") return false;
            try
            {
                var ntdll = GetModuleHandle("ntdll.dll");
                return ntdll != IntPtr.Zero && GetProcAddress(ntdll, "wine_get_version") != IntPtr.Zero;
            }
            catch (Exception) { return false; }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);
    }
}
