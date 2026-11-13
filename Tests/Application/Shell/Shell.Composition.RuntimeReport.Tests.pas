unit Shell.Composition.RuntimeReport.Tests;

// Befehle atlas.server.runtimeReport und .clear der Komposition (#74): angemeldet und nebenläufig, Datei im
// Projekt über Unit- oder Dateiname, Ausgabedatei zum Hauptquelltext, ohne Projekt ein Bericht ohne Diagnosen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Compiler.Results,
  Shell.Composition.Workspaces,
  Shell.Composition.LeakSetup;

type
  [TestFixture]
  TShellRuntimeReportTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FServices: TShellLeakSetupServices;
    FResults: TCompilerResults;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AttachRegistersConcurrent;
    [Test]
    procedure FileOfByUnitOrFileName;
    [Test]
    procedure ExecutableOfProgramAndPackage;
    [Test]
    procedure NoProjectGivesReportWithoutDiagnostics;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.RuntimeReport,
  Atlas.Common.Logging.Providers.Logger,
  Shell.Composition.RuntimeReport;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

function Native(const APath: string): string;
begin
  Result := StringReplace(APath, '\', PathDelim, [rfReplaceAll]);
end;

procedure TShellRuntimeReportTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FServices := Default(TShellLeakSetupServices);
  FServices.Logger := mRegistry.Logger;
  FServices.Workspaces := FRegistry;
  FServices.ReadText := NoText;
  FResults := TCompilerResults.Create;
end;

procedure TShellRuntimeReportTests.TearDown;
begin
  FServices := Default(TShellLeakSetupServices);
  FreeAndNil(FResults);
  FreeAndNil(FRegistry);
end;

function Services(AResults: TCompilerResults): TShellRuntimeReportServices;
begin
  Result := Default(TShellRuntimeReportServices);
  Result.Results := AResults;
end;

procedure TShellRuntimeReportTests.AttachRegistersConcurrent;
var
  mCommands: TLspCommands;
begin
  mCommands := TLspCommands.Create;
  try
    TShellRuntimeReport.Attach(mCommands, FServices, Services(FResults));
    Assert.IsTrue(mCommands.IsConcurrentCommand(TLspRuntimeReport.cCommand));
    Assert.IsTrue(mCommands.IsConcurrentCommand(TLspRuntimeReport.cClearCommand));
  finally
    mCommands.Free;
  end;
end;

procedure TShellRuntimeReportTests.FileOfByUnitOrFileName;
var
  mFiles: TArray<string>;
begin
  mFiles := TArray<string>.Create(Native('C:\P\Kunden.Liste.pas'), Native('C:\P\Main.pas'),
    Native('C:\P\Main.dfm'));
  Assert.AreEqual(Native('C:\P\Kunden.Liste.pas'), TShellRuntimeReport.FileOf(mFiles, 'kunden.liste', ''));
  Assert.AreEqual(Native('C:\P\Main.pas'), TShellRuntimeReport.FileOf(mFiles, '', 'D:\Build\Src\MAIN.PAS'));
  Assert.AreEqual('', TShellRuntimeReport.FileOf(mFiles, 'System.SysUtils', 'System.SysUtils.pas'));
  Assert.AreEqual('', TShellRuntimeReport.FileOf(nil, 'Main', ''));
end;

procedure TShellRuntimeReportTests.ExecutableOfProgramAndPackage;
begin
  Assert.AreEqual(Native('C:\P\Win32\Debug\') + 'Kunden.exe',
    TShellRuntimeReport.ExecutableOf(Native('C:\P\Win32\Debug'), Native('C:\P\Kunden.dpr')));
  Assert.AreEqual(Native('C:\P\Out\') + 'KundenPkg.bpl',
    TShellRuntimeReport.ExecutableOf(Native('C:\P\Out\'), Native('C:\P\KundenPkg.dpk')));
end;

procedure TShellRuntimeReportTests.NoProjectGivesReportWithoutDiagnostics;
var
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mResult: TJSONValue;
  mText: string;
begin
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    TShellRuntimeReport.Attach(mCommands, FServices, Services(FResults));
    mArguments.Add(TDocumentUris.FromPath(Native('C:\P\App.dproj')));
    mArguments.AddElement(TJSONObject.Create(TJSONPair.Create('text',
      'Access violation at address 00401112 in module ''App.exe''. Read of address 00000000.')));
    mResult := mCommands.Execute(TLspRuntimeReport.cCommand, mArguments);
    try
      mText := mResult.ToJSON([]);
    finally
      mResult.Free;
    end;
  finally
    mArguments.Free;
    mCommands.Free;
  end;
  Assert.IsTrue(mText.Contains('"kind":"crash","source":"Exception"'), mText);
  Assert.IsTrue(mText.Contains('"mapStatus":"none"'), mText);
  Assert.IsTrue(mText.Contains('"diagnostics":0'), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellRuntimeReportTests);

end.
