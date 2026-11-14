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
    /// <summary>#261: Builds von Claude Code (build_project) tragen requestedBy.</summary>
    [Test]
    procedure KeepsRequestedBy;
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

function Message(const AFile: string; ALine: Integer; ASeverity: TCompilerSeverity;
  const ACode: string): TCompilerMessage;
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
  mBuild: TIdeBuild;
begin
  TMcpBuildTools.FromFileText(TMcpBuildTools.ToFileText(Sample), mBuild);
end;

procedure TMcpBuildToolsTests.NoBuildYet;
begin
  Assert.Contains(TMcpBuildTools.Report(Default(TIdeBuild), 'C:\P', ''), 'Noch kein Build');
end;

procedure TMcpBuildToolsTests.FileRoundTripAndReport;
var
  mBuild: TIdeBuild;
  mReport: TJSONObject;
  mFirst: TJSONObject;
begin
  Assert.IsTrue(TMcpBuildTools.FromFileText(TMcpBuildTools.ToFileText(Sample), mBuild));
  Assert.AreEqual('C:\P\App.dproj', mBuild.Project);
  Assert.AreEqual(3, Integer(Length(mBuild.Messages)));
  Assert.AreEqual(9, mBuild.Messages[0].Line);
  mReport := TJSONObject.ParseJSONValue(TMcpBuildTools.Report(mBuild, '', '')) as TJSONObject;
  try
    Assert.AreEqual('failed', mReport.GetValue<string>('result'));
    Assert.AreEqual('build', mReport.GetValue<string>('kind'));
    Assert.AreEqual(1, mReport.GetValue<Integer>('errors'));
    Assert.AreEqual(1, mReport.GetValue<Integer>('warnings'));
    Assert.AreEqual(1, mReport.GetValue<Integer>('hints'));
    mFirst := mReport.GetValue<TJSONArray>('messages').Items[0] as TJSONObject;
    // 1-basiert wie in der IDE.
    Assert.AreEqual(10, mFirst.GetValue<Integer>('line'));
    Assert.AreEqual(5, mFirst.GetValue<Integer>('column'));
    Assert.AreEqual('E2003', mFirst.GetValue<string>('code'));
    Assert.AreEqual('error', mFirst.GetValue<string>('severity'));
  finally
    mReport.Free;
  end;
end;

procedure TMcpBuildToolsTests.KeepsRequestedBy;
var
  mRequested, mBuild: TIdeBuild;
  mReport: TJSONObject;
begin
  Assert.IsTrue(TMcpBuildTools.FromFileText(TMcpBuildTools.ToFileText(Sample), mBuild));
  Assert.AreEqual('', mBuild.RequestedBy, 'Build des Benutzers');
  mRequested := Sample;
  mRequested.RequestedBy := 'mcp';
  Assert.IsTrue(TMcpBuildTools.FromFileText(TMcpBuildTools.ToFileText(mRequested), mBuild));
  Assert.AreEqual('mcp', mBuild.RequestedBy);
  mReport := TJSONObject.ParseJSONValue(TMcpBuildTools.Report(mBuild, '', '')) as TJSONObject;
  try
    Assert.AreEqual('mcp', mReport.GetValue<string>('requestedBy'));
  finally
    mReport.Free;
  end;
end;

procedure TMcpBuildToolsTests.OmitsFilesOutsideWorkspaceAndFiltersProject;
var
  mReport: TJSONObject;
begin
  mReport := TJSONObject.ParseJSONValue(TMcpBuildTools.Report(Sample, 'C:\P', 'App')) as TJSONObject;
  try
    Assert.AreEqual(2, mReport.GetValue<TJSONArray>('messages').Count);
    Assert.AreEqual(1, mReport.GetValue<Integer>('omittedOutsideWorkspace'));
  finally
    mReport.Free;
  end;
  Assert.Contains(TMcpBuildTools.Report(Sample, 'C:\P', 'Anderes.dproj'), 'nicht Anderes.dproj');
  // ".." führt nicht aus dem Arbeitsordner hinaus.
  mReport := TJSONObject.ParseJSONValue(TMcpBuildTools.Report(Sample, 'C:\P\..\Q', '')) as TJSONObject;
  try
    Assert.AreEqual(0, mReport.GetValue<TJSONArray>('messages').Count);
  finally
    mReport.Free;
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