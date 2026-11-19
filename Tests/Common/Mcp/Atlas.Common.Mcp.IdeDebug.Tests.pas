unit Atlas.Common.Mcp.IdeDebug.Tests;

// Tests für die Debug-Werkzeuge über die laufende IDE (#1874): Argumente prüfen, Auftrag bauen, Antwort des Plugins
// lesen. Die Rolle des Plugins spielt der Warte-Rückruf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIdeDebugTests = class
  private
    FInbox: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ListsEightTools;
    [Test]
    procedure BuildsStartRequestWithProjectAndClient;
    [Test]
    procedure BuildsBreakpointWithResolvedFile;
    [Test]
    procedure RefusesBreakpointWithoutLine;
    [Test]
    procedure RemoveNeedsIdOrAll;
    [Test]
    procedure StepToLineNeedsPlace;
    [Test]
    procedure StepDefaultsToOver;
    [Test]
    procedure StateDefaultsAndLimits;
    [Test]
    procedure EvaluateNeedsExpression;
    [Test]
    procedure RefusesUnknownTool;
    [Test]
    procedure WaitsLongerForLongerWait;
    [Test]
    procedure ReportsResultOfThePlugin;
    [Test]
    procedure ReportsRefusalOfThePlugin;
    [Test]
    procedure ExplainsWhenNobodyTakesTheRequest;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Mcp.IdeInbox,
  Atlas.Common.Mcp.IdeDebug,
  Atlas.Common.Mcp.IdeInbox.Tests;

var
  GNow: Int64;

function Clock: Int64;
begin
  Result := GNow;
end;

/// <summary>Wie das Plugin: ersten Auftrag übernehmen und mit AAnswer beantworten.</summary>
procedure Plugin(const AInbox, AAnswer: string);
var
  mRequest: string;
begin
  if not TDirectory.Exists(AInbox) then
  begin
    Exit;
  end;
  for mRequest in TDirectory.GetFiles(AInbox, '*.json') do
  begin
    if not mRequest.EndsWith('.result.json') then
    begin
      TFile.Move(mRequest, ChangeFileExt(mRequest, '.taken'));
      TFile.WriteAllText(ChangeFileExt(mRequest, '') + '.result.json', AAnswer, TEncoding.UTF8);
      Exit;
    end;
  end;
end;

function Resolve: TMcpIdeDebugResolve;
begin
  Result :=
    function(AFile: string): string
    begin
      Result := 'C:\P\' + AFile;
    end;
end;

/// <summary>Auftrag zu ATool mit den Argumenten AArguments (JSON-Text); False mit Grund in AReason.</summary>
function Build(const ATool, AArguments: string; out ARequest: TJSONObject; out AReason: string): Boolean;
var
  mArguments: TJSONValue;
  mText: string;
begin
  ARequest := nil;
  mArguments := TJSONObject.ParseJSONValue(AArguments);
  try
    Result := TMcpIdeDebug.RequestText(TMcpIdeDebugCall.Make(ATool, 'Agent', 'C:\P\App.dproj'),
      mArguments as TJSONObject, Resolve(), mText, AReason);
  finally
    mArguments.Free;
  end;
  if Result then
  begin
    ARequest := TJSONObject.ParseJSONValue(mText) as TJSONObject;
  end;
end;

{ TMcpIdeDebugTests }

procedure TMcpIdeDebugTests.Setup;
begin
  FInbox := TMcpIdeDebug.InboxOf(TPath.Combine(TPath.GetTempPath, 'Atlas-IdeDebug-' + IntToStr(Random(MaxInt))), 7);
  GNow := 0;
end;

procedure TMcpIdeDebugTests.TearDown;
begin
  RemoveTestInbox(FInbox);
end;

procedure TMcpIdeDebugTests.ListsEightTools;
var
  mTools: TArray<string>;
begin
  mTools := TMcpIdeDebug.Tools;
  Assert.AreEqual(8, Integer(Length(mTools)));
  Assert.AreEqual('debug_start', mTools[0]);
  Assert.AreEqual('debug_evaluate', mTools[7]);
  Assert.IsTrue(FInbox.Contains('ide-debug'), FInbox);
  Assert.IsTrue(TMcpIdeDebug.NoIdeReason.Contains('IDE'), TMcpIdeDebug.NoIdeReason);
end;

procedure TMcpIdeDebugTests.BuildsStartRequestWithProjectAndClient;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsTrue(Build('debug_start', '{"test":"U.TFix.Methode","configuration":"Debug"}', mRequest, mReason),
    mReason);
  try
    Assert.AreEqual('debug_start', mRequest.GetValue<string>('command'));
    Assert.AreEqual('Agent', mRequest.GetValue<string>('client'));
    Assert.AreEqual('C:\P\App.dproj', mRequest.GetValue<string>('project'));
    Assert.AreEqual('U.TFix.Methode', mRequest.GetValue<string>('test'));
    Assert.AreEqual('Debug', mRequest.GetValue<string>('configuration'));
    Assert.AreEqual(TMcpIdeDebug.cWaitDefault, mRequest.GetValue<Integer>('waitSeconds'));
  finally
    mRequest.Free;
  end;
  Assert.IsFalse(Build('debug_start', '{"waitSeconds":301}', mRequest, mReason));
  Assert.IsTrue(mReason.Contains('waitSeconds'), mReason);
end;

procedure TMcpIdeDebugTests.BuildsBreakpointWithResolvedFile;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsTrue(Build('set_breakpoint', '{"file":"Main.pas","line":12,"condition":"I > 3","passCount":2}',
    mRequest, mReason), mReason);
  try
    Assert.AreEqual('C:\P\Main.pas', mRequest.GetValue<string>('file'));
    Assert.AreEqual(12, mRequest.GetValue<Integer>('line'));
    Assert.AreEqual('I > 3', mRequest.GetValue<string>('condition'));
    Assert.AreEqual(2, mRequest.GetValue<Integer>('passCount'));
  finally
    mRequest.Free;
  end;
end;

procedure TMcpIdeDebugTests.RefusesBreakpointWithoutLine;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsFalse(Build('set_breakpoint', '{"file":"Main.pas"}', mRequest, mReason));
  Assert.IsTrue(mReason.Contains('line'), mReason);
  Assert.IsFalse(Build('set_breakpoint', '{"file":"Main.pas","line":0}', mRequest, mReason));
  Assert.IsFalse(Build('set_breakpoint', '{"line":3}', mRequest, mReason), 'ohne Datei');
  Assert.IsFalse(Build('set_breakpoint', '{"file":"Main.pas","line":3,"passCount":-1}', mRequest, mReason));
  Assert.IsNull(mRequest);
end;

procedure TMcpIdeDebugTests.RemoveNeedsIdOrAll;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsFalse(Build('remove_breakpoint', '{}', mRequest, mReason));
  Assert.IsFalse(Build('remove_breakpoint', '{"id":2,"all":true}', mRequest, mReason), 'beides');
  Assert.IsTrue(Build('remove_breakpoint', '{"all":true}', mRequest, mReason), mReason);
  try
    Assert.IsTrue(mRequest.GetValue<Boolean>('all'));
    Assert.AreEqual(0, mRequest.GetValue<Integer>('id'));
  finally
    mRequest.Free;
  end;
  Assert.IsTrue(Build('remove_breakpoint', '{"id":4}', mRequest, mReason), mReason);
  try
    Assert.AreEqual(4, mRequest.GetValue<Integer>('id'));
    Assert.IsFalse(mRequest.GetValue<Boolean>('all'));
  finally
    mRequest.Free;
  end;
end;

procedure TMcpIdeDebugTests.StepToLineNeedsPlace;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsFalse(Build('debug_step', '{"kind":"toLine"}', mRequest, mReason));
  Assert.IsFalse(Build('debug_step', '{"kind":"sideways"}', mRequest, mReason));
  Assert.IsTrue(mReason.Contains('toLine'), mReason);
  Assert.IsTrue(Build('debug_step', '{"kind":"TOLINE","file":"Main.pas","line":40,"waitSeconds":0}', mRequest,
    mReason), mReason);
  try
    Assert.AreEqual('toLine', mRequest.GetValue<string>('kind'));
    Assert.AreEqual('C:\P\Main.pas', mRequest.GetValue<string>('file'));
    Assert.AreEqual(40, mRequest.GetValue<Integer>('line'));
    Assert.AreEqual(0, mRequest.GetValue<Integer>('waitSeconds'));
  finally
    mRequest.Free;
  end;
end;

procedure TMcpIdeDebugTests.StepDefaultsToOver;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsTrue(Build('debug_step', '{}', mRequest, mReason), mReason);
  try
    Assert.AreEqual('over', mRequest.GetValue<string>('kind'));
    Assert.IsNull(mRequest.GetValue('file'), 'ohne Stelle');
  finally
    mRequest.Free;
  end;
  Assert.IsTrue(Build('debug_step', '{"kind":"Into"}', mRequest, mReason), mReason);
  try
    Assert.AreEqual('into', mRequest.GetValue<string>('kind'));
  finally
    mRequest.Free;
  end;
end;

procedure TMcpIdeDebugTests.StateDefaultsAndLimits;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsTrue(Build('debug_state', '{}', mRequest, mReason), mReason);
  try
    Assert.AreEqual(TMcpIdeDebug.cFramesDefault, mRequest.GetValue<Integer>('frames'));
    Assert.IsTrue(mRequest.GetValue<Boolean>('locals'));
  finally
    mRequest.Free;
  end;
  Assert.IsTrue(Build('debug_state', '{"frames":5,"locals":false}', mRequest, mReason), mReason);
  try
    Assert.AreEqual(5, mRequest.GetValue<Integer>('frames'));
    Assert.IsFalse(mRequest.GetValue<Boolean>('locals'));
  finally
    mRequest.Free;
  end;
  Assert.IsFalse(Build('debug_state', '{"frames":0}', mRequest, mReason));
  Assert.IsFalse(Build('debug_state', '{"frames":"viele"}', mRequest, mReason), 'kein Zahlwert');
end;

procedure TMcpIdeDebugTests.EvaluateNeedsExpression;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsFalse(Build('debug_evaluate', '{"expression":"  "}', mRequest, mReason));
  Assert.IsTrue(mReason.Contains('expression'), mReason);
  Assert.IsTrue(Build('debug_evaluate', '{"expression":"Liste.Count"}', mRequest, mReason), mReason);
  try
    Assert.AreEqual('Liste.Count', mRequest.GetValue<string>('expression'));
    Assert.IsFalse(mRequest.GetValue<Boolean>('sideEffects'), 'Vorgabe ohne Nebenwirkungen');
  finally
    mRequest.Free;
  end;
end;

procedure TMcpIdeDebugTests.RefusesUnknownTool;
var
  mRequest: TJSONObject;
  mReason: string;
begin
  Assert.IsFalse(Build('debug_dance', '{}', mRequest, mReason));
  Assert.IsTrue(mReason.Contains('debug_dance'), mReason);
  Assert.IsTrue(Build('debug_stop', '{}', mRequest, mReason), mReason);
  mRequest.Free;
end;

procedure TMcpIdeDebugTests.WaitsLongerForLongerWait;
var
  mArguments: TJSONObject;
begin
  Assert.AreEqual(Int64(TMcpIdeDebug.cAnswerMs + TMcpIdeDebug.cWaitDefault * 1000), TMcpIdeDebug.AnswerMs(nil));
  mArguments := TJSONObject.ParseJSONValue('{"waitSeconds":120}') as TJSONObject;
  try
    Assert.AreEqual(Int64(TMcpIdeDebug.cAnswerMs + 120000), TMcpIdeDebug.AnswerMs(mArguments));
  finally
    mArguments.Free;
  end;
end;

procedure TMcpIdeDebugTests.ReportsResultOfThePlugin;
var
  mResult, mReason, mInbox: string;
  mJson: TJSONValue;
begin
  mInbox := FInbox;
  Assert.AreEqual(Ord(TMcpIdeDebugOutcome.Done), Ord(TMcpIdeDebug.Send(mInbox, '{"command":"debug_state"}',
    TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(GNow, 100);
      Plugin(mInbox, '{"ok":true,"result":{"state":"stopped","location":{"file":"C:\\P\\Main.pas","line":12}}}');
    end, Clock, 5000, 5000), mResult, mReason)), mReason);
  mJson := TJSONObject.ParseJSONValue(mResult);
  try
    Assert.AreEqual('stopped', mJson.GetValue<string>('state'));
    Assert.AreEqual(12, mJson.GetValue<Integer>('location.line'));
  finally
    mJson.Free;
  end;
end;

procedure TMcpIdeDebugTests.ReportsRefusalOfThePlugin;
var
  mResult, mReason, mInbox: string;
begin
  mInbox := FInbox;
  Assert.AreEqual(Ord(TMcpIdeDebugOutcome.Refused), Ord(TMcpIdeDebug.Send(mInbox, '{"command":"debug_evaluate"}',
    TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(GNow, 100);
      Plugin(mInbox, '{"ok":false,"reason":"Aufrufe sind nicht erlaubt"}');
    end, Clock, 5000, 5000), mResult, mReason)));
  Assert.AreEqual('Aufrufe sind nicht erlaubt', mReason);
  Assert.AreEqual('', mResult);
  // Ohne Ergebnis gilt eine Zusage als Ablehnung.
  Assert.AreEqual(Ord(TMcpIdeDebugOutcome.Refused), Ord(TMcpIdeDebug.Send(mInbox, '{"command":"debug_state"}',
    TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(GNow, 100);
      Plugin(mInbox, '{"ok":true}');
    end, Clock, 5000, 5000), mResult, mReason)));
  Assert.IsNotEmpty(mReason);
end;

procedure TMcpIdeDebugTests.ExplainsWhenNobodyTakesTheRequest;
var
  mResult, mReason: string;
begin
  Assert.AreEqual(Ord(TMcpIdeDebugOutcome.NotTaken), Ord(TMcpIdeDebug.Send(FInbox, '{"command":"debug_state"}',
    TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(GNow, 100);
    end, Clock, 5000, 5000), mResult, mReason)));
  Assert.IsNotEmpty(mReason);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeDebugTests);

end.
