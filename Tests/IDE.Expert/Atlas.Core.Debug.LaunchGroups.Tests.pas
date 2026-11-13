unit Atlas.Core.Debug.LaunchGroups.Tests;

// Tests für Startverbünde (#867): Lesen und Schreiben, Reihenfolge, Wartebedingungen, Halt nach Fehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasLaunchGroupsTests = class
  public
    /// <summary>Verbund mit zwei Projekten, Wartebedingung Port und Vorgaben.</summary>
    [Test]
    procedure ReadsGroups;
    /// <summary>Absolute Pfade, Pfade nach außen und unbekannte Wartebedingungen entfallen mit Meldung.</summary>
    [Test]
    procedure SkipsInvalidItems;
    /// <summary>Schreiben und wieder lesen ergibt dasselbe.</summary>
    [Test]
    procedure WritesAndReadsBack;
    /// <summary>Sekunden, Port, Fenster, Ablauf der Wartezeit.</summary>
    [Test]
    procedure EvaluatesWaits;
    /// <summary>Lauf: Reihenfolge, Warten vor dem nächsten, Text der Leiste.</summary>
    [Test]
    procedure RunsInOrder;
    /// <summary>Abgelaufene Wartezeit hält an; „Trotzdem weiter“ bzw. „Alle beenden“.</summary>
    [Test]
    procedure HaltsOnTimeout;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.LaunchGroups;

const
  cJson = '[{"name": "Server + Client", "items": [' +
    '{"project": "Server\\Server.dproj", "profile": "Lokal", "wait": "port", "value": 8080, "timeout": 20},' +
    '{"project": "Client/Client.dproj", "debug": false}]}]';

function Texts: TAtlasLaunchTexts;
begin
  Result.Done := 'OK';
  Result.Failed := 'X';
  Result.Starting := 'startet';
  Result.Waiting := 'wartet';
end;

procedure TAtlasLaunchGroupsTests.ReadsGroups;
var
  mGroups: TAtlasLaunchGroupList;
  mProblems: TArray<string>;
begin
  mGroups := TAtlasLaunchGroups.Parse(cJson, mProblems);
  Assert.AreEqual(Integer(0), Integer(Length(mProblems)));
  Assert.AreEqual(Integer(1), Integer(Length(mGroups)));
  Assert.AreEqual('Server + Client', mGroups[0].Name);
  Assert.AreEqual(Integer(2), Integer(Length(mGroups[0].Items)));
  Assert.AreEqual('Server', mGroups[0].Items[0].Caption);
  Assert.AreEqual('Lokal', mGroups[0].Items[0].Profile);
  Assert.IsTrue(mGroups[0].Items[0].Debug, 'Vorgabe mit Debugger');
  Assert.AreEqual(Ord(TAtlasLaunchWaitKind.Port), Ord(mGroups[0].Items[0].Wait));
  Assert.AreEqual(Integer(8080), mGroups[0].Items[0].Value);
  Assert.AreEqual(Integer(20), mGroups[0].Items[0].TimeoutSeconds);
  Assert.AreEqual('Client', mGroups[0].Items[1].Caption);
  Assert.IsFalse(mGroups[0].Items[1].Debug);
  Assert.AreEqual(Ord(TAtlasLaunchWaitKind.None), Ord(mGroups[0].Items[1].Wait));
  Assert.AreEqual(Integer(TAtlasLaunchGroups.cDefaultTimeout), mGroups[0].Items[1].TimeoutSeconds);
  Assert.AreEqual(Integer(0), TAtlasLaunchGroups.IndexOf(mGroups, 'server + client'));
  Assert.AreEqual(Integer(-1), TAtlasLaunchGroups.IndexOf(mGroups, 'Andere'));
end;

procedure TAtlasLaunchGroupsTests.SkipsInvalidItems;
var
  mGroups: TAtlasLaunchGroupList;
  mProblems: TArray<string>;
begin
  mGroups := TAtlasLaunchGroups.Parse('[{"name": "A", "items": [{"project": "C:\\X.dproj"}, ' +
    '{"project": "..\\Y.dproj"}, {"project": "Z.dproj", "wait": "bald"}, {"project": "Z.dproj", "wait": "port"}, ' +
    '{"project": "Ok\\Ok.dproj", "wait": "seconds", "value": 2}]}, {"items": []}]', mProblems);
  Assert.AreEqual(Integer(1), Integer(Length(mGroups)));
  Assert.AreEqual(Integer(1), Integer(Length(mGroups[0].Items)));
  Assert.AreEqual('launchGroups[0].items[0],launchGroups[0].items[1],launchGroups[0].items[2],' +
    'launchGroups[0].items[3],launchGroups[1].name', string.Join(',', mProblems));
  Assert.IsTrue(TAtlasLaunchGroups.IsInside('A\..\B.dproj'));
  Assert.IsFalse(TAtlasLaunchGroups.IsInside('A\..\..\B.dproj'));
  Assert.IsFalse(TAtlasLaunchGroups.IsInside('\\server\B.dproj'));
  TAtlasLaunchGroups.Parse('{"name": "kein Array"}', mProblems);
  Assert.AreEqual('launchGroups', string.Join(',', mProblems));
end;

procedure TAtlasLaunchGroupsTests.WritesAndReadsBack;
var
  mGroups, mAgain: TAtlasLaunchGroupList;
  mProblems: TArray<string>;
begin
  mGroups := TAtlasLaunchGroups.Parse(cJson, mProblems);
  mAgain := TAtlasLaunchGroups.Parse(TAtlasLaunchGroups.ToJson(mGroups), mProblems);
  Assert.AreEqual(TAtlasLaunchGroups.ToJson(mGroups), TAtlasLaunchGroups.ToJson(mAgain));
  Assert.AreEqual(Integer(8080), mAgain[0].Items[0].Value);
  Assert.IsFalse(mAgain[0].Items[1].Debug);
  Assert.IsFalse(TAtlasLaunchGroups.ToJson(mGroups).Contains('"timeout":30'), 'Vorgabe weggelassen');
end;

procedure TAtlasLaunchGroupsTests.EvaluatesWaits;
var
  mItem: TAtlasLaunchItem;
begin
  mItem := Default(TAtlasLaunchItem);
  mItem.TimeoutSeconds := 5;
  Assert.AreEqual(Ord(TAtlasLaunchWaitState.Ready), Ord(TAtlasLaunchGroups.Evaluate(mItem, 0, False, False)));
  mItem.Wait := TAtlasLaunchWaitKind.Seconds;
  mItem.Value := 2;
  Assert.AreEqual(Ord(TAtlasLaunchWaitState.Waiting), Ord(TAtlasLaunchGroups.Evaluate(mItem, 1999, False, False)));
  Assert.AreEqual(Ord(TAtlasLaunchWaitState.Ready), Ord(TAtlasLaunchGroups.Evaluate(mItem, 2000, False, False)));
  mItem.Wait := TAtlasLaunchWaitKind.Port;
  Assert.AreEqual(Ord(TAtlasLaunchWaitState.Waiting), Ord(TAtlasLaunchGroups.Evaluate(mItem, 4999, False, True)));
  Assert.AreEqual(Ord(TAtlasLaunchWaitState.Ready), Ord(TAtlasLaunchGroups.Evaluate(mItem, 100, True, False)));
  Assert.AreEqual(Ord(TAtlasLaunchWaitState.TimedOut), Ord(TAtlasLaunchGroups.Evaluate(mItem, 5000, False, False)));
  mItem.Wait := TAtlasLaunchWaitKind.Window;
  Assert.AreEqual(Ord(TAtlasLaunchWaitState.Ready), Ord(TAtlasLaunchGroups.Evaluate(mItem, 100, False, True)));
end;

procedure TAtlasLaunchGroupsTests.RunsInOrder;
var
  mGroups: TAtlasLaunchGroupList;
  mProblems: TArray<string>;
  mRun: TAtlasLaunchRun;
  mIndex: Integer;
begin
  mGroups := TAtlasLaunchGroups.Parse(cJson, mProblems);
  mRun := TAtlasLaunchRun.Create(mGroups[0]);
  try
    Assert.IsTrue(mRun.Advance(0, mIndex));
    Assert.AreEqual(Integer(0), mIndex);
    Assert.AreEqual('Server startet', mRun.Text(Texts));
    Assert.IsFalse(mRun.Advance(10, mIndex), 'erst nach dem Warten');
    mRun.Launched(100);
    Assert.IsFalse(mRun.Check(500, False, False));
    Assert.AreEqual('Server wartet', mRun.Text(Texts));
    Assert.IsTrue(mRun.Check(900, True, False), 'Port offen');
    Assert.IsTrue(mRun.Advance(1000, mIndex));
    Assert.AreEqual(Integer(1), mIndex);
    mRun.Launched(1100);
    Assert.IsTrue(mRun.Check(1100, False, False), 'ohne Bedingung gleich fertig');
    Assert.IsTrue(mRun.Finished);
    Assert.AreEqual('Server OK · Client OK', mRun.Text(Texts));
  finally
    mRun.Free;
  end;
end;

procedure TAtlasLaunchGroupsTests.HaltsOnTimeout;
var
  mGroups: TAtlasLaunchGroupList;
  mProblems: TArray<string>;
  mRun: TAtlasLaunchRun;
  mIndex: Integer;
begin
  mGroups := TAtlasLaunchGroups.Parse(cJson, mProblems);
  mRun := TAtlasLaunchRun.Create(mGroups[0]);
  try
    mRun.Advance(0, mIndex);
    mRun.Launched(0);
    Assert.IsFalse(mRun.Check(20000, False, False));
    Assert.IsTrue(mRun.Halted, 'Wartezeit abgelaufen');
    Assert.AreEqual(Ord(TAtlasLaunchItemState.Failed), Ord(mRun.State(0)));
    Assert.IsFalse(mRun.Advance(20001, mIndex), 'Client startet nicht von selbst');
    mRun.Proceed;
    Assert.IsTrue(mRun.Advance(20002, mIndex));
    Assert.AreEqual(Integer(1), mIndex);
  finally
    mRun.Free;
  end;
  mRun := TAtlasLaunchRun.Create(mGroups[0]);
  try
    mRun.Advance(0, mIndex);
    mRun.Fail;
    mRun.Cancel;
    Assert.IsTrue(mRun.Finished);
    Assert.AreEqual(Ord(TAtlasLaunchItemState.Skipped), Ord(mRun.State(1)));
    Assert.AreEqual('Server X', mRun.Text(Texts));
  finally
    mRun.Free;
  end;
end;

end.
