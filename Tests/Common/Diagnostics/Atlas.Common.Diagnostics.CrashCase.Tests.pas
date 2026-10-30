unit Atlas.Common.Diagnostics.CrashCase.Tests;

// Tests für TCrashCases (#1355): Ordner und Dateien eines Absturzfalls,
// Zugangsdaten entfernt, höchstens MaxCases Fälle, Laden für --replay.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Diagnostics.CrashCase;

type
  [TestFixture]
  TCrashCaseTests = class
  private
    FRoot: string;
    function SampleCase: TCrashCase;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SummaryNamesMethodFileLineAndException;
    [Test]
    procedure SummaryOfTimeoutNamesLimit;
    [Test]
    procedure DocumentOfReadsPositionAndRange;
    [Test]
    procedure WriteCreatesAllFiles;
    [Test]
    procedure WriteUsesNewFolderWhenNameTaken;
    [Test]
    procedure RedactRemovesSecretsAndUserInfo;
    [Test]
    procedure UnreadableSettingsAreLeftOut;
    [Test]
    procedure KeepsAtMostMaxCases;
    [Test]
    procedure LoadReadsWrittenCase;
    [Test]
    procedure LoadRejectsMissingMethod;
    [Test]
    procedure ReplayScriptCallsServerWithReplay;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON;

procedure TCrashCaseTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'AtlasCrashCaseTests_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
end;

procedure TCrashCaseTests.TearDown;
begin
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
  FRoot := '';
end;

function TCrashCaseTests.SampleCase: TCrashCase;
begin
  Result := TCrashCase.Empty;
  Result.Time := EncodeDate(2026, 10, 29) + EncodeTime(21, 15, 30, 0);
  Result.ProcessId := 4711;
  Result.Method := 'textDocument/hover';
  Result.Id := '12';
  Result.Params := '{"textDocument":{"uri":"file:///C:/P/UI.Auftrag.pas"},"position":{"line":811,"character":4}}';
  Result.Uri := 'file:///C:/P/UI.Auftrag.pas';
  Result.FileName := 'C:\P\UI.Auftrag.pas';
  Result.Line := 811;
  Result.Text := 'unit UI.Auftrag;';
  Result.HasText := True;
  Result.Recent := TArray<string>.Create('{"jsonrpc":"2.0","method":"initialized"}', '{"text":"abgeschnitten… (9000 Zeichen)"}');
  Result.Initialize := '{"processId":1,"initializationOptions":{"apiToken":"geheim"}}';
  Result.ExceptionClass := 'EStackOverflow';
  Result.ExceptionMessage := 'Stack overflow';
  Result.Stack := 'UI.Parser.pas Zeile 40';
  Result.AtlasVersion := '1.2.0';
  Result.BuildCompiler := 'Delphi 37.0';
  Result.Client := 'RAD Studio 37.0';
end;

procedure TCrashCaseTests.SummaryNamesMethodFileLineAndException;
begin
  Assert.AreEqual('textDocument/hover in UI.Auftrag.pas:812 löste EStackOverflow aus', SampleCase.Summary);
end;

procedure TCrashCaseTests.SummaryOfTimeoutNamesLimit;
var
  mCase: TCrashCase;
begin
  mCase := TCrashCase.Empty;
  mCase.Kind := TCrashCaseKind.Timeout;
  mCase.Method := 'workspace/symbol';
  mCase.TimeoutMs := 30000;
  Assert.AreEqual('workspace/symbol überschritt das Zeitlimit von 30000 ms', mCase.Summary);
end;

procedure TCrashCaseTests.DocumentOfReadsPositionAndRange;
var
  mParams: TJSONValue;
  mUri: string;
  mLine: Integer;
begin
  mParams := TJSONValue.ParseJSONValue('{"textDocument":{"uri":"file:///a.pas"},"range":{"start":{"line":3}}}');
  try
    Assert.IsTrue(TCrashCases.DocumentOf(mParams, mUri, mLine));
    Assert.AreEqual('file:///a.pas', mUri);
    Assert.AreEqual(3, mLine);
  finally
    mParams.Free;
  end;
  mParams := TJSONValue.ParseJSONValue('{"query":"x"}');
  try
    Assert.IsFalse(TCrashCases.DocumentOf(mParams, mUri, mLine));
    Assert.AreEqual(-1, mLine);
  finally
    mParams.Free;
  end;
end;

procedure TCrashCaseTests.WriteCreatesAllFiles;
var
  mCase: TCrashCase;
  mFolder, mRequest: string;
begin
  mCase := SampleCase;
  mCase.Settings := TArray<TCrashCaseSetting>.Create(TCrashCaseSetting.Create('atlas.json', '{"a":1}'));
  mFolder := TCrashCases.Write(FRoot, mCase);
  Assert.AreEqual('2026-10-29_211530_4711', ExtractFileName(mFolder));
  Assert.IsTrue(TFile.Exists(TPath.Combine(mFolder, 'UI.Auftrag.pas')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(mFolder, 'atlas.json')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(mFolder, TCrashCases.StackName)));
  Assert.IsTrue(TFile.Exists(TPath.Combine(mFolder, TCrashCases.ReplayName)));
  mRequest := TFile.ReadAllText(TPath.Combine(mFolder, TCrashCases.RequestName), TEncoding.UTF8);
  Assert.IsTrue(mRequest.Contains('"textDocument/hover"'));
  Assert.IsTrue(mRequest.Contains('"EStackOverflow"'));
  Assert.IsTrue(mRequest.Contains('abgeschnitten'));
  Assert.IsTrue(TFile.ReadAllText(TPath.Combine(mFolder, TCrashCases.StackName), TEncoding.UTF8)
    .Contains('UI.Parser.pas Zeile 40'));
end;

procedure TCrashCaseTests.WriteUsesNewFolderWhenNameTaken;
var
  mFirst, mSecond: string;
begin
  mFirst := TCrashCases.Write(FRoot, SampleCase);
  mSecond := TCrashCases.Write(FRoot, SampleCase);
  Assert.AreEqual(ExtractFileName(mFirst) + '-2', ExtractFileName(mSecond));
  Assert.AreEqual(2, Integer(Length(TCrashCases.Folders(FRoot))));
end;

procedure TCrashCaseTests.RedactRemovesSecretsAndUserInfo;
var
  mText: string;
begin
  mText := TCrashCases.Redact('{"issueTracker":{"token":"abc123","url":"https://marco:pw@host/x",' +
    '"items":[{"Password":"p"},{"name":"n"}]},"port":5} // Kommentar');
  Assert.IsFalse(mText.Contains('abc123'));
  Assert.IsFalse(mText.Contains('pw@'));
  Assert.IsFalse(mText.Contains('"p"'));
  Assert.IsTrue(mText.Contains('https://host/x'));
  Assert.IsTrue(mText.Contains('"n"'));
  Assert.IsTrue(mText.Contains('5'));
  Assert.IsTrue(TCrashCases.IsSecretKey('apiKey'));
  Assert.IsFalse(TCrashCases.IsSecretKey('uri'));
end;

procedure TCrashCaseTests.UnreadableSettingsAreLeftOut;
var
  mCase: TCrashCase;
  mFolder: string;
begin
  mCase := SampleCase;
  mCase.Settings := TArray<TCrashCaseSetting>.Create(TCrashCaseSetting.Create('atlas.json', '{"token": "x"'));
  mFolder := TCrashCases.Write(FRoot, mCase);
  Assert.IsFalse(TFile.Exists(TPath.Combine(mFolder, 'atlas.json')));
  Assert.AreEqual('', TCrashCases.Redact('kein JSON'));
end;

procedure TCrashCaseTests.KeepsAtMostMaxCases;
var
  mCase: TCrashCase;
  mIndex: Integer;
  mFolders: TArray<string>;
begin
  mCase := SampleCase;
  for mIndex := 0 to TCrashCases.MaxCases + 2 do
  begin
    mCase.Time := SampleCase.Time + mIndex / SecsPerDay;
    TCrashCases.Write(FRoot, mCase);
  end;
  mFolders := TCrashCases.Folders(FRoot);
  Assert.AreEqual(TCrashCases.MaxCases, Integer(Length(mFolders)));
  // Die ältesten drei sind weg.
  Assert.AreEqual(TCrashCases.FolderName(SampleCase.Time + 3 / SecsPerDay, 4711), ExtractFileName(mFolders[0]));
end;

procedure TCrashCaseTests.LoadReadsWrittenCase;
var
  mCase, mLoaded: TCrashCase;
  mFolder, mError: string;
begin
  mCase := SampleCase;
  mCase.Settings := TArray<TCrashCaseSetting>.Create(TCrashCaseSetting.Create('atlas.json', '{"a":1}'));
  mFolder := TCrashCases.Write(FRoot, mCase);
  Assert.IsTrue(TCrashCases.Load(TPath.Combine(mFolder, TCrashCases.RequestName), mLoaded, mError), mError);
  Assert.AreEqual('textDocument/hover', mLoaded.Method);
  Assert.AreEqual('12', mLoaded.Id);
  Assert.AreEqual(811, mLoaded.Line);
  Assert.AreEqual(mCase.Uri, mLoaded.Uri);
  Assert.IsTrue(mLoaded.HasText);
  Assert.AreEqual('unit UI.Auftrag;', mLoaded.Text);
  Assert.AreEqual('EStackOverflow', mLoaded.ExceptionClass);
  Assert.AreEqual(1, Integer(Length(mLoaded.Settings)));
  Assert.AreEqual('atlas.json', mLoaded.Settings[0].Name);
  Assert.IsFalse(mLoaded.Initialize.Contains('geheim'));
end;

procedure TCrashCaseTests.LoadRejectsMissingMethod;
var
  mFile, mError: string;
  mCase: TCrashCase;
begin
  mFile := TPath.Combine(FRoot, 'leer.json');
  TFile.WriteAllText(mFile, '{"kind":"exception"}');
  Assert.IsFalse(TCrashCases.Load(mFile, mCase, mError));
  Assert.IsTrue(mError.Contains('method'));
  Assert.IsFalse(TCrashCases.Load(TPath.Combine(FRoot, 'fehlt.json'), mCase, mError));
end;

procedure TCrashCaseTests.ReplayScriptCallsServerWithReplay;
var
  mCase: TCrashCase;
begin
  mCase := SampleCase;
  mCase.ServerPath := 'C:\Atlas\AtlasServer.exe';
  Assert.IsTrue(TCrashCases.ReplayScript(mCase).Contains('"C:\Atlas\AtlasServer.exe" --replay anfrage.json'));
  mCase.ServerPath := '';
  Assert.IsTrue(TCrashCases.ReplayScript(mCase).Contains('"AtlasServer" --replay'));
end;

initialization
  TDUnitX.RegisterTestFixture(TCrashCaseTests);

end.
