unit Atlas.Core.Lsp.CrashCases.Tests;

// Tests für TAtlasCrashCases und TAtlasCrashSkips (#1355): Benachrichtigungen
// des Servers lesen, Fall aus anfrage.json, Texte für Meldung und Issue,
// Anhänge, Liste der übersprungenen Anfragen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCrashCasesTests = class
  private
    FRoot: string;
    function WriteCase(const AName, ARequest: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesCaseNotification;
    [Test]
    procedure RejectsCaseWithoutFolder;
    [Test]
    procedure ParsesSkipNotification;
    [Test]
    procedure LoadBuildsSummaryLikeServer;
    [Test]
    procedure NewestFindsLatestCaseSince;
    [Test]
    procedure IssueTextHasStackAndVersion;
    [Test]
    procedure AttachFilesWithoutScriptRequestFirst;
    [Test]
    procedure SkipListFollowsBeginAndEnd;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Tracker.Attach,
  Atlas.Core.Lsp.CrashCases;

const
  cRequest = '{"format":1,"kind":"exception","method":"textDocument/hover",' +
    '"file":"C:\\P\\UI.Auftrag.pas","uri":"file:///C:/P/UI.Auftrag.pas","line":811,' +
    '"exception":{"class":"EStackOverflow","message":"Stack overflow"},"atlasVersion":"1.2.0"}';

procedure TAtlasCrashCasesTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'AtlasCrashNotices_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
end;

procedure TAtlasCrashCasesTests.TearDown;
begin
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
  FRoot := '';
end;

function TAtlasCrashCasesTests.WriteCase(const AName, ARequest: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TDirectory.CreateDirectory(Result);
  TFile.WriteAllText(TPath.Combine(Result, TAtlasCrashCases.RequestName), ARequest, TEncoding.UTF8);
end;

procedure TAtlasCrashCasesTests.ParsesCaseNotification;
var
  mParams: TJSONValue;
  mCase: TAtlasCrashCase;
begin
  mParams := TJSONValue.ParseJSONValue('{"summary":"textDocument/hover in UI.Auftrag.pas:812 löste ' +
    'EStackOverflow aus","folder":"C:\\crash\\f","method":"textDocument/hover","kind":"exception",' +
    '"file":"C:\\P\\UI.Auftrag.pas","line":811,"exception":"EStackOverflow","version":"1.2.0","skipping":true}');
  try
    Assert.IsTrue(TAtlasCrashCases.ParseCase(mParams, mCase));
  finally
    mParams.Free;
  end;
  Assert.AreEqual('C:\crash\f', mCase.Folder);
  Assert.AreEqual(811, mCase.Line);
  Assert.IsTrue(mCase.Skipping);
  Assert.AreEqual('textDocument/hover in UI.Auftrag.pas:812 löste EStackOverflow aus (Atlas 1.2.0)',
    TAtlasCrashCases.SummaryText(mCase));
end;

procedure TAtlasCrashCasesTests.RejectsCaseWithoutFolder;
var
  mParams: TJSONValue;
  mCase: TAtlasCrashCase;
begin
  mParams := TJSONValue.ParseJSONValue('{"summary":"x"}');
  try
    Assert.IsFalse(TAtlasCrashCases.ParseCase(mParams, mCase));
  finally
    mParams.Free;
  end;
  Assert.IsFalse(TAtlasCrashCases.ParseCase(nil, mCase));
end;

procedure TAtlasCrashCasesTests.ParsesSkipNotification;
var
  mParams: TJSONValue;
  mSkip: TAtlasCrashSkip;
begin
  mParams := TJSONValue.ParseJSONValue('{"active":true,"method":"textDocument/hover","uri":"file:///a.pas",' +
    '"file":"C:\\a.pas","crashes":2,"exception":"ECrashTest","folder":"f"}');
  try
    Assert.IsTrue(TAtlasCrashCases.ParseSkip(mParams, mSkip));
  finally
    mParams.Free;
  end;
  Assert.IsTrue(mSkip.Active);
  Assert.AreEqual(2, mSkip.Crashes);
  Assert.AreEqual('ECrashTest', mSkip.ExceptionClass);
end;

procedure TAtlasCrashCasesTests.LoadBuildsSummaryLikeServer;
var
  mCase: TAtlasCrashCase;
begin
  Assert.IsTrue(TAtlasCrashCases.Load(WriteCase('2026-10-29_211530_1', cRequest), mCase));
  Assert.AreEqual('textDocument/hover in UI.Auftrag.pas:812 löste EStackOverflow aus', mCase.Summary);
  Assert.AreEqual('1.2.0', mCase.Version);
  Assert.IsFalse(TAtlasCrashCases.Load(WriteCase('kaputt', '{"method":'), mCase));
  Assert.IsTrue(TAtlasCrashCases.Load(WriteCase('zeit', '{"kind":"timeout","method":"workspace/symbol",' +
    '"timeoutMs":30000}'), mCase));
  Assert.AreEqual('workspace/symbol überschritt das Zeitlimit von 30000 ms', mCase.Summary);
end;

procedure TAtlasCrashCasesTests.NewestFindsLatestCaseSince;
var
  mCase: TAtlasCrashCase;
  mStart: TDateTime;
begin
  mStart := Now - 1 / MinsPerDay;
  WriteCase('2026-10-29_211530_1', cRequest);
  WriteCase('2026-10-29_211531_1', StringReplace(cRequest, 'textDocument/hover', 'textDocument/completion', []));
  Assert.IsTrue(TAtlasCrashCases.Newest(FRoot, mStart, mCase));
  Assert.AreEqual('textDocument/completion', mCase.Method);
  Assert.IsFalse(TAtlasCrashCases.Newest(FRoot, Now + 1, mCase), 'nichts nach dem Start');
  Assert.IsFalse(TAtlasCrashCases.Newest(TPath.Combine(FRoot, 'fehlt'), mStart, mCase));
end;

procedure TAtlasCrashCasesTests.IssueTextHasStackAndVersion;
var
  mCase: TAtlasCrashCase;
  mFolder, mText: string;
begin
  mFolder := WriteCase('2026-10-29_211530_1', cRequest);
  TFile.WriteAllText(TPath.Combine(mFolder, TAtlasCrashCases.StackName), 'Aufrufstapel:'#13#10'Parser.pas 40',
    TEncoding.UTF8);
  Assert.IsTrue(TAtlasCrashCases.Load(mFolder, mCase));
  Assert.AreEqual('Absturz: textDocument/hover in UI.Auftrag.pas:812 löste EStackOverflow aus',
    TAtlasCrashCases.IssueTitle(mCase));
  mText := TAtlasCrashCases.IssueDescription(mCase);
  Assert.IsTrue(mText.Contains('Parser.pas 40'), mText);
  Assert.IsTrue(mText.Contains('Atlas-Version: 1.2.0'), mText);
  Assert.IsTrue(mText.Contains('Zeile 812'), mText);
  Assert.IsTrue(mText.Contains('--replay'), mText);
end;

procedure TAtlasCrashCasesTests.AttachFilesWithoutScriptRequestFirst;
var
  mFolder: string;
  mFiles: TArray<TAtlasAttachFile>;
begin
  mFolder := WriteCase('2026-10-29_211530_1', cRequest);
  TFile.WriteAllText(TPath.Combine(mFolder, 'UI.Auftrag.pas'), 'unit UI.Auftrag;', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mFolder, 'atlas.json'), '{}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mFolder, 'wiederholen.cmd'), '@echo off');
  mFiles := TAtlasCrashCases.AttachFiles(mFolder);
  Assert.AreEqual(3, Integer(Length(mFiles)));
  Assert.AreEqual(TAtlasCrashCases.RequestName, mFiles[0].Name);
  Assert.AreEqual('atlas.json', mFiles[1].Name);
  Assert.AreEqual('UI.Auftrag.pas', mFiles[2].Name);
  Assert.AreEqual(0, Integer(Length(TAtlasCrashCases.AttachFiles(TPath.Combine(FRoot, 'fehlt')))));
end;

procedure TAtlasCrashCasesTests.SkipListFollowsBeginAndEnd;
var
  mSkips: TAtlasCrashSkips;
  mSkip: TAtlasCrashSkip;
begin
  mSkips := TAtlasCrashSkips.Create;
  try
    mSkip := Default(TAtlasCrashSkip);
    mSkip.Method := 'textDocument/hover';
    mSkip.Uri := 'file:///a.pas';
    mSkip.Active := True;
    Assert.IsTrue(mSkips.Apply(mSkip));
    Assert.IsTrue(mSkips.Apply(mSkip), 'erneuter Beginn ersetzt');
    Assert.AreEqual(1, mSkips.Count);
    mSkip.Active := False;
    Assert.IsTrue(mSkips.Apply(mSkip));
    Assert.AreEqual(0, mSkips.Count);
    Assert.IsFalse(mSkips.Apply(mSkip), 'Ende ohne Beginn');
  finally
    mSkips.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCrashCasesTests);

end.
