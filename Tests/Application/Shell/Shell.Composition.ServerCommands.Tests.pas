unit Shell.Composition.ServerCommands.Tests;

// Befehle am Server selbst: Anmelden, Kompilieren ohne Compiler, Projektwahl ohne Projekte, Neuprüfen und erneut
// versuchen mit der URI aus dem Argument.

interface

uses
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.Compiler.Backend,
  Shell.Workspace,
  Shell.Composition.ServerCommands;

type
  [TestFixture]
  TShellServerCommandsTests = class
  private
    FLog: TArray<string>;
    FCompiled: TArray<string>;
    FRetried: string;
    FRechecks: Integer;
    function NewServices: TShellServerCommandServices;
    function Execute(const ACommand: string; AArguments: TJSONArray): TJSONValue;
    procedure Logged(const AText: string);
    function Compile(const AFileName: string; out AChoice: TCompilerBackendChoice): Boolean;
    function NoWorkspaces(const AUri: string): TArray<TShellWorkspace>;
    function Retry(const AUri: string): Integer;
    procedure Recheck;
  public
    [TearDown]
    procedure TearDown;
    /// <summary>Lese-, Aktions- und Umwandlungsbefehle zusammen melden alle Befehle am Server an.</summary>
    [Test]
    procedure RegistersAllCommands;
    /// <summary>Ohne nutzbaren Compiler meldet Kompilieren einen Fehler, mit URI geht der Pfad an den Compiler.
    /// </summary>
    [Test]
    procedure CompileWithoutBackendFails;
    /// <summary>Ohne Arbeitsbereiche liefert die Projektwahl eine leere Liste, der Index baut für keinen Ordner
    /// neu auf, und Prozesse am Index-Cache gibt es keine.</summary>
    [Test]
    procedure WithoutWorkspacesNothingHappens;
    /// <summary>Erneut versuchen gibt die URI weiter, Neuprüfen stößt eine neue Generation an und schreibt ins Log.
    /// </summary>
    [Test]
    procedure RetryAndRecheck;
  end;

implementation

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.Processes,
  Atlas.Common.Lsp.SettingsCommands,
  Atlas.Common.Lsp.PullDiagnostics,
  Atlas.Common.Lsp.FormFiles,
  Shell.CrashCases;

type
  TLogLineProc = reference to procedure(const AText: string);

  /// <summary>Sammelt Logzeilen über eine Methodenreferenz.</summary>
  TCollectingLogger = class(TInterfacedObject, ILogger)
  private
    FSink: TLogLineProc;
  public
    constructor Create(const ASink: TLogLineProc);
    procedure Log(ALevel: TLogLevel; const AText: string);
    procedure Debug(const AText: string);
    procedure Info(const AText: string);
    procedure Warning(const AText: string);
    procedure Error(const AText: string);
  end;

constructor TCollectingLogger.Create(const ASink: TLogLineProc);
begin
  inherited Create;
  FSink := ASink;
end;

procedure TCollectingLogger.Log(ALevel: TLogLevel; const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Debug(const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Info(const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Warning(const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Error(const AText: string);
begin
  FSink(AText);
end;

procedure TShellServerCommandsTests.TearDown;
begin
  FLog := nil;
  FCompiled := nil;
  FRetried := '';
end;

procedure TShellServerCommandsTests.Logged(const AText: string);
begin
  FLog := FLog + [AText];
end;

function TShellServerCommandsTests.Compile(const AFileName: string; out AChoice: TCompilerBackendChoice): Boolean;
begin
  FCompiled := FCompiled + [AFileName];
  AChoice := TCompilerBackendChoice.Unavailable('Kein Compiler', 'Delphi installieren');
  Result := False;
end;

function TShellServerCommandsTests.NoWorkspaces(const AUri: string): TArray<TShellWorkspace>;
begin
  Result := nil;
end;

function TShellServerCommandsTests.Retry(const AUri: string): Integer;
begin
  FRetried := AUri;
  Result := 1;
end;

procedure TShellServerCommandsTests.Recheck;
begin
  Inc(FRechecks);
end;

function TShellServerCommandsTests.NewServices: TShellServerCommandServices;
begin
  Result := Default(TShellServerCommandServices);
  Result.Logger := TCollectingLogger.Create(Logged);
  Result.Compile := Compile;
  Result.Workspaces := NoWorkspaces;
  Result.RetryCrashCase := Retry;
  Result.Recheck := Recheck;
  Result.ActiveProject :=
    function: string
    begin
      Result := '';
    end;
end;

function TShellServerCommandsTests.Execute(const ACommand: string; AArguments: TJSONArray): TJSONValue;
var
  mServerCommands: TShellServerCommands;
  mCommands: TLspCommands;
begin
  // Gibt AArguments in jedem Fall frei.
  mServerCommands := TShellServerCommands.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mServerCommands.RegisterReadCommands(mCommands);
    mServerCommands.RegisterActionCommands(mCommands);
    Result := mCommands.Execute(ACommand, AArguments);
  finally
    AArguments.Free;
    mCommands.Free;
    mServerCommands.Free;
  end;
end;

procedure TShellServerCommandsTests.RegistersAllCommands;
var
  mServerCommands: TShellServerCommands;
  mCommands: TLspCommands;
  mCapability: TJSONObject;
  mText: string;
  mName: string;
begin
  mServerCommands := TShellServerCommands.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mServerCommands.RegisterReadCommands(mCommands);
    mServerCommands.RegisterActionCommands(mCommands);
    mServerCommands.RegisterConvertCommand(mCommands);
    mCapability := mCommands.Capability;
    try
      mText := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
    for mName in TArray<string>.Create(cStatusCommand, cProcessesCommand, TLspSettingsCommands.cCheckCommand,
      TLspSettingsCommands.cCatalogCommand, TShellServerCommands.cCompileCommand,
      TShellServerCommands.cRebuildIndexCommand, cClearIndexCommand, TShellCrashCases.cRetryCommand,
      TLspPullDiagnostics.cRecheckCommand, TShellServerCommands.cSelectBuildCommand,
      TShellServerCommands.cSelectProjectCommand, TLspFormFiles.cConvertCommand) do
    begin
      Assert.IsTrue(Pos('"' + mName + '"', mText) > 0, mName);
    end;
  finally
    mCommands.Free;
    mServerCommands.Free;
  end;
end;

procedure TShellServerCommandsTests.CompileWithoutBackendFails;
var
  mArguments: TJSONArray;
begin
  Assert.WillRaise(
    procedure
    begin
      Execute(TShellServerCommands.cCompileCommand, TJSONArray.Create).Free;
    end, EJsonRpcError);
  mArguments := TJSONArray.Create;
  mArguments.Add('file:///tmp/Projekt.dpr');
  Assert.WillRaise(
    procedure
    begin
      Execute(TShellServerCommands.cCompileCommand, mArguments).Free;
    end, EJsonRpcError);
  Assert.AreEqual(2, Integer(Length(FCompiled)));
  Assert.AreEqual('', FCompiled[0]);
  Assert.AreEqual(TDocumentUris.ToPath('file:///tmp/Projekt.dpr'), FCompiled[1]);
end;

procedure TShellServerCommandsTests.WithoutWorkspacesNothingHappens;
var
  mAnswer: TJSONValue;
begin
  mAnswer := Execute(TShellServerCommands.cSelectProjectCommand, TJSONArray.Create);
  try
    Assert.IsTrue(mAnswer is TJSONObject);
  finally
    mAnswer.Free;
  end;
  Execute(TShellServerCommands.cRebuildIndexCommand, TJSONArray.Create).Free;
  Assert.AreEqual(1, Integer(Length(FLog)));
  Assert.AreEqual('Index wird für 0 Ordner neu aufgebaut', FLog[0]);
  mAnswer := Execute(cProcessesCommand, TJSONArray.Create);
  try
    Assert.IsNotNull(mAnswer);
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual(2, Integer(Length(FLog)));
end;

procedure TShellServerCommandsTests.RetryAndRecheck;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONArray.Create;
  mArguments.Add('file:///tmp/A.pas');
  mAnswer := Execute(TShellCrashCases.cRetryCommand, mArguments);
  try
    Assert.AreEqual('1', mAnswer.Value);
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual('file:///tmp/A.pas', FRetried);
  Execute(TLspPullDiagnostics.cRecheckCommand, TJSONArray.Create).Free;
  Assert.AreEqual(1, FRechecks);
  Assert.AreEqual('Alle Dateien werden neu geprüft', FLog[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellServerCommandsTests);

end.
