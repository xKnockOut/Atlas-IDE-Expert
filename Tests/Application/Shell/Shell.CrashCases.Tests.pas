unit Shell.CrashCases.Tests;

// Tests für TShellCrashCases (#1355): Fall bei Ausnahme und Zeitüberschreitung,
// Überspringen ab dem zweiten Absturz, Ende bei Änderung und „Erneut versuchen“,
// Einstellungen server.crashCases/crashSkip, keine Zugangsdaten im Fall.

interface

uses
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.RecentMessages,
  Shell.CrashCases;

type
  [TestFixture]
  TShellCrashCasesTests = class
  private
    FRoot: string;
    FDocuments: IDocumentStore;
    FRecent: IJsonRpcRecentMessages;
    FCases: TShellCrashCases;
    FSent: TArray<string>;
    procedure CreateCases;
    procedure Crash;
    function HoverParams: TJSONValue;
    function GuardRejects: Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CrashWritesCaseAndNotifies;
    [Test]
    procedure SecondCrashSkipsUntilChange;
    [Test]
    procedure RetryEndsSkipping;
    [Test]
    procedure SkipSurvivesRestart;
    [Test]
    procedure DisabledWritesNothing;
    [Test]
    procedure SkipDisabledNeverSkips;
    [Test]
    procedure TimeoutWritesCaseWithRecentParams;
    [Test]
    procedure CaseHasNoCredentials;
    [Test]
    procedure TestSwitchCrashesMethod;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Diagnostics.CrashCase;

const
  cUri = 'file:///C:/P/UI.Auftrag.pas';
  cHover = 'textDocument/hover';

procedure TShellCrashCasesTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'AtlasShellCrashTests_' + TGUID.NewGuid.ToString);
  FDocuments := TDocumentStore.Create;
  FDocuments.Open(cUri, 'pascal', 1, 'unit UI.Auftrag;');
  FRecent := TJsonRpcRecentMessages.Create;
  FSent := nil;
  CreateCases;
end;

procedure TShellCrashCasesTests.TearDown;
begin
  FreeAndNil(FCases);
  FDocuments := nil;
  FRecent := nil;
  FSent := nil;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
  FRoot := '';
end;

procedure TShellCrashCasesTests.CreateCases;
begin
  FreeAndNil(FCases);
  FCases := TShellCrashCases.Create(FRoot, TLogger.Create, FDocuments, FRecent);
  FCases.TestMethod := '';
  FCases.AtlasVersion := '1.2.0';
  FCases.Notify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      FSent := FSent + [AMethod + ' ' + AParams.ToJSON];
      AParams.Free;
    end;
end;

function TShellCrashCasesTests.HoverParams: TJSONValue;
begin
  Result := TJSONValue.ParseJSONValue('{"textDocument":{"uri":"' + cUri + '"},"position":{"line":4,"character":2}}');
end;

procedure TShellCrashCasesTests.Crash;
var
  mParams: TJSONValue;
  mError: Exception;
begin
  mParams := HoverParams;
  mError := ECrashTest.Create('kaputt');
  try
    FCases.RequestFailed(cHover, mParams, mError, 'Stapel');
  finally
    mError.Free;
    mParams.Free;
  end;
end;

function TShellCrashCasesTests.GuardRejects: Boolean;
var
  mParams: TJSONValue;
begin
  Result := False;
  mParams := HoverParams;
  try
    try
      FCases.Guard(cHover, mParams);
    except
      on E: EJsonRpcError do
        Result := E.Message.StartsWith(TShellCrashCases.SkipMessage);
    end;
  finally
    mParams.Free;
  end;
end;

procedure TShellCrashCasesTests.CrashWritesCaseAndNotifies;
var
  mFolders: TArray<string>;
  mCase: TCrashCase;
  mError: string;
begin
  Crash;
  mFolders := TCrashCases.Folders(FRoot);
  Assert.AreEqual(1, Integer(Length(mFolders)));
  Assert.IsTrue(TCrashCases.Load(TPath.Combine(mFolders[0], TCrashCases.RequestName), mCase, mError), mError);
  Assert.AreEqual(cHover, mCase.Method);
  Assert.AreEqual(4, mCase.Line);
  Assert.AreEqual('unit UI.Auftrag;', mCase.Text);
  Assert.AreEqual('ECrashTest', mCase.ExceptionClass);
  Assert.AreEqual(1, Integer(Length(FSent)));
  Assert.IsTrue(FSent[0].StartsWith(TShellCrashCases.CaseNotification));
  Assert.IsTrue(FSent[0].Contains('"skipping":false'));
  Assert.IsFalse(GuardRejects);
end;

procedure TShellCrashCasesTests.SecondCrashSkipsUntilChange;
begin
  Crash;
  Crash;
  Assert.AreEqual(1, Integer(Length(FCases.Skipped)));
  // atlas/crashSkip vor dem zweiten atlas/crashCase.
  Assert.AreEqual(3, Integer(Length(FSent)));
  Assert.IsTrue(FSent[1].StartsWith(TShellCrashCases.SkipNotification));
  Assert.IsTrue(FSent[1].Contains('"active":true'));
  Assert.IsTrue(FSent[2].Contains('"skipping":true'));
  Assert.IsTrue(GuardRejects);
  FDocuments.Change(cUri, 2, TArray<TTextChange>.Create(TTextChange.Full('unit UI.Auftrag; // neu')));
  FCases.DocumentChanged(cUri, 'unit UI.Auftrag; // neu');
  Assert.AreEqual(0, Integer(Length(FCases.Skipped)));
  Assert.IsTrue(FSent[High(FSent)].Contains('"active":false'));
  Assert.IsFalse(GuardRejects);
end;

procedure TShellCrashCasesTests.RetryEndsSkipping;
begin
  Crash;
  Crash;
  Assert.AreEqual(1, FCases.Retry(cUri));
  Assert.IsFalse(GuardRejects);
  Assert.AreEqual(0, FCases.Retry(''));
end;

procedure TShellCrashCasesTests.SkipSurvivesRestart;
begin
  Crash;
  Crash;
  Assert.IsTrue(TFile.Exists(TPath.Combine(FRoot, TShellCrashCases.SkipsFileName)));
  CreateCases;
  Assert.IsTrue(GuardRejects);
  FCases.Announce;
  Assert.IsTrue(FSent[High(FSent)].StartsWith(TShellCrashCases.SkipNotification));
end;

procedure TShellCrashCasesTests.DisabledWritesNothing;
begin
  FCases.Enabled := False;
  Crash;
  Assert.AreEqual(0, Integer(Length(TCrashCases.Folders(FRoot))));
  // Das Sicherheitsnetz zählt weiter, auch ohne Fälle.
  Crash;
  Assert.IsTrue(GuardRejects);
end;

procedure TShellCrashCasesTests.SkipDisabledNeverSkips;
begin
  FCases.SkipEnabled := False;
  Crash;
  Crash;
  Assert.IsFalse(GuardRejects);
  Assert.AreEqual(2, Integer(Length(TCrashCases.Folders(FRoot))));
end;

procedure TShellCrashCasesTests.TimeoutWritesCaseWithRecentParams;
var
  mMessage: TJSONObject;
  mFolders: TArray<string>;
  mCase: TCrashCase;
  mError: string;
begin
  mMessage := TJSONObject(TJSONValue.ParseJSONValue('{"jsonrpc":"2.0","id":9,"method":"' + cHover +
    '","params":{"textDocument":{"uri":"' + cUri + '"},"position":{"line":1,"character":0}}}'));
  try
    FRecent.Add(mMessage);
  finally
    mMessage.Free;
  end;
  FCases.TimedOut('9', cHover, 5000);
  mFolders := TCrashCases.Folders(FRoot);
  Assert.AreEqual(1, Integer(Length(mFolders)));
  Assert.IsTrue(TCrashCases.Load(TPath.Combine(mFolders[0], TCrashCases.RequestName), mCase, mError), mError);
  Assert.IsTrue(mCase.Kind = TCrashCaseKind.Timeout);
  Assert.AreEqual(1, mCase.Line);
  Assert.AreEqual(Cardinal(5000), mCase.TimeoutMs);
  // Zeitüberschreitungen zählen nicht fürs Überspringen.
  FCases.TimedOut('9', cHover, 5000);
  Assert.IsFalse(GuardRejects);
end;

procedure TShellCrashCasesTests.CaseHasNoCredentials;
var
  mSettings: string;
  mFolders, mFiles: TArray<string>;
  mFile: string;
begin
  mSettings := TPath.Combine(FRoot, 'settings.json');
  TDirectory.CreateDirectory(FRoot);
  TFile.WriteAllText(mSettings, '{"issueTracker":{"token":"geheim-123","url":"https://marco:kennwort@host"}}');
  FCases.SettingsFiles :=
    function(const AUri: string): TArray<string>
    begin
      Result := TArray<string>.Create(mSettings);
    end;
  FCases.Initialize :=
    function: string
    begin
      Result := '{"initializationOptions":{"password":"geheim-123"}}';
    end;
  Crash;
  mFolders := TCrashCases.Folders(FRoot);
  Assert.AreEqual(1, Integer(Length(mFolders)));
  mFiles := TDirectory.GetFiles(mFolders[0]);
  Assert.IsTrue(TFile.Exists(TPath.Combine(mFolders[0], 'settings.json')));
  for mFile in mFiles do
  begin
    Assert.IsFalse(TFile.ReadAllText(mFile).Contains('geheim-123'), mFile);
    Assert.IsFalse(TFile.ReadAllText(mFile).Contains('kennwort'), mFile);
  end;
end;

procedure TShellCrashCasesTests.TestSwitchCrashesMethod;
var
  mParams: TJSONValue;
begin
  FCases.TestMethod := cHover;
  mParams := HoverParams;
  try
    Assert.WillRaise(
      procedure
      begin
        FCases.Guard(cHover, mParams);
      end, ECrashTest);
    Assert.WillNotRaise(
      procedure
      begin
        FCases.Guard('textDocument/completion', mParams);
      end);
  finally
    mParams.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCrashCasesTests);

end.
