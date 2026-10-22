unit Atlas.Windows.Documents.PathCanonicalizer.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWindowsPathCanonicalizerTests = class
  private
    FDir: string;
    FFile: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ResolvesCaseAndDots;
    [Test]
    procedure KeepsMissingPathUnchanged;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Windows.Documents.PathCanonicalizer;

{ TWindowsPathCanonicalizerTests }

procedure TWindowsPathCanonicalizerTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasKanonisch' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(TPath.Combine(FDir, 'Sub'));
  FFile := TPath.Combine(FDir, 'Datei.pas');
  TFile.WriteAllText(FFile, 'unit Datei;');
end;

procedure TWindowsPathCanonicalizerTests.TearDown;
begin
  TDirectory.Delete(FDir, True);
  // Sonst gibt erst das nächste Setup die Pfade frei, und der erste Test meldete sie als Leck (Bericht N2).
  FDir := '';
  FFile := '';
end;

procedure TWindowsPathCanonicalizerTests.ResolvesCaseAndDots;
var
  Expected, Actual: string;
begin
  Expected := TWindowsPathCanonicalizer.Canonicalize(FFile);
  Actual := TWindowsPathCanonicalizer.Canonicalize(
    UpperCase(TPath.Combine(TPath.Combine(FDir, 'Sub'), '..\datei.PAS')));
  Assert.AreEqual(Expected, Actual);
  Assert.IsTrue(Actual.EndsWith('\Datei.pas'));
  Assert.AreNotEqual('\\?\', Copy(Actual, 1, 4));
end;

procedure TWindowsPathCanonicalizerTests.KeepsMissingPathUnchanged;
begin
  Assert.AreEqual('C:\gibt\es\nicht.pas', TWindowsPathCanonicalizer.Canonicalize('C:\gibt\es\nicht.pas'));
  Assert.AreEqual('', TWindowsPathCanonicalizer.Canonicalize(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TWindowsPathCanonicalizerTests);

end.
