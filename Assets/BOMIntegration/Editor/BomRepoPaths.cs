using System;
using System.IO;
using UnityEngine;

// Where the repo's integration folder and the shipped server are, with no machine-specific paths (owner 2026-11-19).
// The project's own integration/ folder is used, so it works in any clone. The gate tools export from a separate
// validation copy of the project; they set BOM_INTEGRATION_ROOT to the repo's integration/ folder.
public static class BomRepoPaths
{
    public static string Integration
    {
        get
        {
            string env = Environment.GetEnvironmentVariable("BOM_INTEGRATION_ROOT");
            string path = !string.IsNullOrEmpty(env)
                ? env
                : Path.Combine(Path.GetDirectoryName(Application.dataPath), "integration");
            if (!Directory.Exists(path))
                throw new InvalidOperationException(
                    "Cannot find the integration folder at " + path + ". Set BOM_INTEGRATION_ROOT to <repo>/integration."
                );
            return Path.GetFullPath(path).Replace('\\', '/');
        }
    }

    // The repo root (the folder that holds integration/, Engine/ and Server/).
    public static string Root => Path.GetDirectoryName(Integration).Replace('\\', '/');

    // BOM_NATIVE_SERVER_EXE if set (the gate tools pass the checkpoint build), otherwise the repo's Server/BOM-server.exe.
    public static string Server
    {
        get
        {
            string env = Environment.GetEnvironmentVariable("BOM_NATIVE_SERVER_EXE");
            return !string.IsNullOrEmpty(env) ? env : Root + "/Server/BOM-server.exe";
        }
    }
}
