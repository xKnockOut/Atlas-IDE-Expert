unit Shell.Mcp.RefactorSources.Tests;

// Dateioperationen für refactor im MCP-Modus (#2150): neue Units als UTF-8 mit BOM und CRLF samt Ordner, Löschen
// mit Grund statt Ausnahme. Die Dienste des Hosts prüft Shell.Mcp.RefactorHost.Tests über die echten Umbauten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpRefactorSourcesTests = class
  public
    [Test]
    procedure CreatesUnitWithBomCrLfAndFolder;
    [Test]
    procedure DeleteReportsMissingFile;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Mcp.EditTools,
  Shell.Mcp.RefactorSources;

function NewFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'atlas-refactor-dateien-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
end;

{ TMcpRefactorSourcesTests }

procedure TMcpRefactorSourcesTests.CreatesUnitWithBomCrLfAndFolder;
var
  mFolder, mFile, mError: string;
  mBytes: TBytes;
  mOperations: TMcpFileOperations;
begin
  mFolder := NewFolder;
  try
    mFile := TPath.Combine(TPath.Combine(mFolder, 'Neu'), 'Probe.Neu.pas');
    mOperations := TMcpRefactorSources.FileOperations;
    mOperations.CreateFile(mFile, 'unit Probe.Neu;'#10#10'end.'#10);
    mBytes := TFile.ReadAllBytes(mFile);
    Assert.IsTrue((Length(mBytes) > 3) and (mBytes[0] = $EF) and (mBytes[1] = $BB) and (mBytes[2] = $BF), 'BOM');
    Assert.Contains(TFile.ReadAllText(mFile, TEncoding.UTF8), 'unit Probe.Neu;'#13#10#13#10'end.');
    Assert.IsTrue(mOperations.DeleteFile(mFile, mError), mError);
    Assert.IsFalse(TFile.Exists(mFile));
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

procedure TMcpRefactorSourcesTests.DeleteReportsMissingFile;
var
  mError: string;
  mOperations: TMcpFileOperations;
begin
  mOperations := TMcpRefactorSources.FileOperations;
  Assert.IsFalse(mOperations.DeleteFile(TPath.Combine(NewFolder, 'Fehlt.pas'), mError));
  Assert.AreNotEqual('', mError, 'Grund des Fehlers');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpRefactorSourcesTests);

end.
