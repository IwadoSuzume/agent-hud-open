// The package's marker and the engine's missing-library status (Package).
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class PackageTests
{
    static string Root()
    {
        for (var folder = new DirectoryInfo(AppContext.BaseDirectory); folder is not null; folder = folder.Parent)
            if (File.Exists(Path.Combine(folder.FullName, "scripts", "build-windows.ps1"))) return folder.FullName;
        throw new FileNotFoundException("scripts/build-windows.ps1");
    }

    [TestMethod]
    public void TheMarkerIsTheFileTheBuildScriptWrites()
    {
        var script = File.ReadAllText(Path.Combine(Root(), "scripts", "build-windows.ps1"));
        StringAssert.Contains(script, $"'{Package.MarkerFileName}'");
    }

    [TestMethod]
    public void OnlyAFolderWithTheMarkerIsAPackage()
    {
        var folder = Directory.CreateTempSubdirectory("agenthud-package-test-");
        try
        {
            Assert.IsFalse(Package.IsPackaged(folder.FullName));
            File.WriteAllText(Path.Combine(folder.FullName, Package.MarkerFileName), "{}");
            Assert.IsTrue(Package.IsPackaged(folder.FullName));
        }
        finally { folder.Delete(recursive: true); }
    }

    [TestMethod]
    public void OnlyWindowsDllNotFoundIsAMissingLibrary()
    {
        Assert.IsTrue(Package.IsMissingLibrary(-1073741515));
        Assert.IsFalse(Package.IsMissingLibrary(1));
        Assert.IsFalse(Package.IsMissingLibrary(null));
    }
}
