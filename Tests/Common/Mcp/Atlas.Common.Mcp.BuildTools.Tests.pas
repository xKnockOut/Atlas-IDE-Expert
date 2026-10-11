unit Atlas.Common.Mcp.BuildTools.Tests;

// Tests für get_last_build (#556) mit gespeicherten Build-Daten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpBuildToolsTests = class
  public
    /// <summary>Zeitzone und ISO-8601-Umrechnung legen beim ersten Aufruf einmalige Daten an.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure NoBuildYet;
    [Test]
    procedure FileRoundTripAndReport;
    [Test]
    procedure OmitsFilesOutsideWorkspaceAndFiltersProject;
    [Test]
    procedure BuildFileSameForBothProcesses;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Mcp.BuildTools;

function Message(const AFile: string; ALine: Integer; ASeverity: TCompilerSeverity; const ACode: string): TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.FileName := AFile;
  Result.Line := ALine;
  Result.Column := 4;
  Result.Severity := ASeverity;
  Result.Code := ACode;
  Result.Text := 'Text ' + ACode;
end;

function Sample: TIdeBuild;
begin
  Result := Default(TIdeBuild);
  Result.Known := True;
  Result.Project := 'C:\P\App.dproj';
  Result.Kind := 'build';
  Result.Configuration := 'Debug';
  Result.Platform := 'Win32';
  Result.Success := False;
  Result.DurationMs := 4200;
  Result.FinishedAt := EncodeDate(2026, 10, 10) + EncodeTime(10, 30, 0, 0);
  Result.Messages := [Message('C:\P\Main.pas', 9, TCompilerSeverity.Error, 'E2003'),
    Message('C:\P\Main.pas', 2, TCompilerSeverity.Hint, 'H2164'),
    Message('C:\Lib\Fremd.pas', 0, TCompilerSeverity.Warning, 'W1000')];
end;

procedure TMcpBuildToolsTests.WarmUp;
var
  Build: TIdeBuild;
begin
  TMcpBuildTools.FromFileText(TMcpBuildTools.ToFileText(Sample), Build);
end;

procedure TMcpBuildToolsTests.NoBuildYet;
begin
  Assert.Contains(TMcpBuildTools.Report(Default(TIdeBuild), 'C:\P', ''), 'Noch kein Build');
end;

procedure TMcpBuildToolsTests.FileRoundTripAndReport;
var
  Build: TIdeBuild;
  Report: TJSONObject;
  First: TJSONObject;
begin
  Assert.IsTrue(TMcpBuildTools.FromFileText(TMcpBuildTools.ToFileText(Sample), Build));
  Assert.AreEqual('C:\P\App.dproj', Build.Project);
  Assert.AreEqual(3, Integer(Length(Build.Messages)));
  Assert.AreEqual(9, Build.Messages[0].Line);
  Report := TJSONObject.ParseJSONValue(TMcpBuildTools.Report(Build, '', '')) as TJSONObject;
  try
    Assert.AreEqual('failed', Report.GetValue<string>('result'));
    Assert.AreEqual('build', Report.GetValue<string>('kind'));
    Assert.AreEqual(1, Report.GetValue<Integer>('errors'));
    Assert.AreEqual(1, Report.GetValue<Integer>('warnings'));
    Assert.AreEqual(1, Report.GetValue<Integer>('hints'));
    First := Report.GetValue<TJSONArray>('messages').Items[0] as TJSONObject;
    // 1-basiert wie in der IDE.
    Assert.AreEqual(10, First.GetValue<Integer>('line'));
    Assert.AreEqual(5, First.GetValue<Integer>('column'));
    Assert.AreEqual('E2003', First.GetValue<string>('code'));
    Assert.AreEqual('error', First.GetValue<string>('severity'));
  finally
    Report.Free;
  end;
end;

procedure TMcpBuildToolsTests.OmitsFilesOutsideWorkspaceAndFiltersProject;
var
  Report: TJSONObject;
begin
  Report := TJSONObject.ParseJSONValue(TMcpBuildTools.Report(Sample, 'C:\P', 'App')) as TJSONObject;
  try
    Assert.AreEqual(2, Report.GetValue<TJSONArray>('messages').Count);
    Assert.AreEqual(1, Report.GetValue<Integer>('omittedOutsideWorkspace'));
  finally
    Report.Free;
  end;
  Assert.Contains(TMcpBuildTools.Report(Sample, 'C:\P', 'Anderes.dproj'), 'nicht Anderes.dproj');
  // ".." führt nicht aus dem Arbeitsordner hinaus.
  Report := TJSONObject.ParseJSONValue(TMcpBuildTools.Report(Sample, 'C:\P\..\Q', '')) as TJSONObject;
  try
    Assert.AreEqual(0, Report.GetValue<TJSONArray>('messages').Count);
  finally
    Report.Free;
  end;
end;

procedure TMcpBuildToolsTests.BuildFileSameForBothProcesses;
begin
  // LSP kennt den Ordner aus der URI, MCP aus --root: Schreibweise und Trenner am Ende egal.
  Assert.AreEqual(TIndexCacheDirectory.BuildFileFor('C:\Cache', 'C:\Projekte\App'),
    TIndexCacheDirectory.BuildFileFor('C:\Cache', 'c:\projekte\app\'));
  Assert.Contains(TIndexCacheDirectory.BuildFileFor('C:\Cache', 'C:\Projekte\App'), 'build-');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpBuildToolsTests);

end.