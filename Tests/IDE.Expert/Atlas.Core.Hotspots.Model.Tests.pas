unit Atlas.Core.Hotspots.Model.Tests;

// Datenmodell des Fensters „Atlas-Hotspots“ (#1354): Antwort von
// atlas.hotspots lesen (Daten, ausgeschaltet, ohne Versionsverwaltung,
// "pending"), Filter, Blasendiagramm (Lage, Treffer, Farbe, Achsen) und die
// Argumente der Befehle samt Spalte des Methodennamens.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasHotspotModelTests = class
  public
    [Test]
    procedure ParsesAnswer;
    [Test]
    procedure ParsesStates;
    [Test]
    procedure FiltersByName;
    [Test]
    procedure ChartLayoutAndHitTest;
    [Test]
    procedure ScoreColorFromGreenToRed;
    [Test]
    procedure CommandArguments;
    [Test]
    procedure FindsNameColumn;
  end;

/// <summary>Antwort von atlas.hotspots mit drei Units, zwei Methoden und einem Kopplungspaar.</summary>
function SampleHotspotAnswer: string;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Hotspots.Model;

function EntryJson(const AUnit, APath, AMethod: string; ALine, AChanges, AComplexity, ALines: Integer;
  const AScore, ATrend: string): string;
begin
  Result := '{"unit":"' + AUnit + '","path":"' + APath + '"';
  if AMethod <> '' then
    Result := Result + ',"method":"' + AMethod + '"';
  Result := Result + ',"line":' + IntToStr(ALine) + ',"endLine":' + IntToStr(ALine + ALines - 1) + ',"changes":' +
    IntToStr(AChanges) + ',"authors":2,"authorNames":["anna","bernd"],"added":10,"deleted":4,' +
    '"lastChange":"2026-10-20T08:00:00Z","complexity":' + IntToStr(AComplexity) + ',"lines":' + IntToStr(ALines) +
    ',"pastComplexity":-1,"trend":"' + ATrend + '","score":' + AScore + ',"history":[' +
    '{"revision":"0123456789abcdef","author":"anna","date":"2026-10-20T08:00:00Z","summary":"Rechnung","added":3,' +
    '"deleted":1},{"revision":"fedcba9876543210","author":"bernd","date":"2026-10-01T08:00:00Z","summary":"Start",' +
    '"added":-1,"deleted":-1}]}';
end;

function SampleHotspotAnswer: string;
begin
  Result := '{"enabled":true,"vcs":true,"root":"C:\\Projekt","format":"json","data":{"format":1,"title":"Demo",' +
    '"vcs":"git","head":"abc","months":12,"since":"2025-10-29T00:00:00Z","commits":42,"level":"method",' +
    '"units":[' + EntryJson('App.Kern', 'App/Kern.pas', '', 1, 12, 80, 400, '1', 'rising') + ',' +
    EntryJson('App.Daten', 'App/Daten.pas', '', 1, 6, 40, 200, '0.25', 'steady') + ',' +
    EntryJson('App.Form', 'App/Form.pas', '', 1, 2, 10, 50, '0.02', 'unknown') + '],"methods":[' +
    EntryJson('App.Kern', 'App/Kern.pas', 'TKern.Rechne', 120, 7, 25, 60, '1', 'new') + ',' +
    EntryJson('App.Daten', 'App/Daten.pas', 'TDaten.Lade', 40, 3, 10, 20, '0.17', 'falling') + '],"coupling":[' +
    '{"first":{"unit":"App.Daten","path":"App/Daten.pas"},"second":{"unit":"App.Form","path":"App/Form.pas"},' +
    '"shared":6,"firstChanges":6,"secondChanges":7,"ratio":0.9231}]}}';
end;

{ TAtlasHotspotModelTests }

procedure TAtlasHotspotModelTests.ParsesAnswer;
var
  mModel: TAtlasHotspotModel;
  mEnabled, mHasVcs: Boolean;
  mMessage: string;
begin
  Assert.IsTrue(TAtlasHotspotModel.Parse(SampleHotspotAnswer, mModel, mEnabled, mHasVcs, mMessage));
  Assert.IsTrue(mEnabled);
  Assert.IsTrue(mHasVcs);
  Assert.IsFalse(mModel.Pending);
  Assert.AreEqual('Demo', mModel.Title);
  Assert.AreEqual('git', mModel.Vcs);
  Assert.AreEqual(42, mModel.Commits);
  Assert.AreEqual(12, mModel.Months);
  Assert.AreEqual(3, Integer(Length(mModel.Units)));
  Assert.AreEqual(2, Integer(Length(mModel.Methods)));
  Assert.AreEqual('App.Kern', mModel.Units[0].UnitName);
  Assert.AreEqual(IncludeTrailingPathDelimiter('C:\Projekt') + 'App' + PathDelim + 'Kern.pas',
    mModel.Units[0].FileName, 'Pfad mit der Wurzel');
  Assert.AreEqual(12, mModel.Units[0].Changes);
  Assert.AreEqual(2, mModel.Units[0].Authors);
  Assert.AreEqual(80, mModel.Units[0].Complexity);
  Assert.AreEqual('rising', mModel.Units[0].Trend);
  Assert.AreEqual(2, Integer(Length(mModel.Units[0].History)));
  Assert.AreEqual('0123456', mModel.Units[0].History[0].ShortRevision('git'));
  Assert.AreEqual('rfedcba9876543210', mModel.Units[0].History[1].ShortRevision('svn'), 'SVN mit r, ungekürzt');
  Assert.AreEqual(-1, mModel.Units[0].History[1].Added);
  Assert.AreEqual('TKern.Rechne', mModel.Methods[0].Caption);
  Assert.AreEqual('App.Kern', mModel.Units[0].Caption);
  Assert.AreEqual(120, mModel.Methods[0].Line);
  Assert.AreEqual(6, mModel.Coupling[0].Shared);
  Assert.AreEqual('App.Form', mModel.Coupling[0].SecondUnit);
  Assert.AreEqual(0.9231, mModel.Coupling[0].Ratio, 1E-6);
  Assert.AreEqual(2, Integer(Length(mModel.Entries)), 'Ebene method');
  mModel.Level := 'unit';
  Assert.AreEqual(3, Integer(Length(mModel.Entries)));
end;

procedure TAtlasHotspotModelTests.ParsesStates;
var
  mModel: TAtlasHotspotModel;
  mEnabled, mHasVcs: Boolean;
  mMessage: string;
begin
  Assert.IsTrue(TAtlasHotspotModel.Parse('{"enabled":false}', mModel, mEnabled, mHasVcs, mMessage));
  Assert.IsFalse(mEnabled);
  Assert.IsTrue(TAtlasHotspotModel.Parse('{"enabled":true,"vcs":false,"message":"kein Repository"}', mModel,
    mEnabled, mHasVcs, mMessage));
  Assert.IsTrue(mEnabled);
  Assert.IsFalse(mHasVcs);
  Assert.AreEqual('kein Repository', mMessage);
  Assert.IsTrue(TAtlasHotspotModel.Parse('{"enabled":true,"vcs":true,"root":"C:\\P","pending":true}', mModel,
    mEnabled, mHasVcs, mMessage));
  Assert.IsTrue(mModel.Pending, 'Server rechnet noch');
  Assert.AreEqual('C:\P', mModel.Root);
  Assert.IsFalse(TAtlasHotspotModel.Parse('', mModel, mEnabled, mHasVcs, mMessage));
  Assert.IsFalse(TAtlasHotspotModel.Parse('{"enabled":true,"vcs":true,"data":{"format":99}}', mModel, mEnabled,
    mHasVcs, mMessage), 'anderes Format');
end;

procedure TAtlasHotspotModelTests.FiltersByName;
var
  mModel: TAtlasHotspotModel;
  mEnabled, mHasVcs: Boolean;
  mMessage: string;
begin
  TAtlasHotspotModel.Parse(SampleHotspotAnswer, mModel, mEnabled, mHasVcs, mMessage);
  Assert.AreEqual(2, Integer(Length(mModel.Filter(''))));
  Assert.AreEqual(1, Integer(Length(mModel.Filter('rechne'))), 'Methodenname');
  Assert.AreEqual(1, Integer(Length(mModel.Filter('DATEN'))), 'Unit-Name');
  mModel.Level := 'unit';
  Assert.AreEqual(3, Integer(Length(mModel.Filter('  '))));
  Assert.AreEqual(1, Integer(Length(mModel.FilterCoupling('form'))));
  Assert.AreEqual(0, Integer(Length(mModel.FilterCoupling('kern'))));
end;

procedure TAtlasHotspotModelTests.ChartLayoutAndHitTest;
var
  mModel: TAtlasHotspotModel;
  mEnabled, mHasVcs: Boolean;
  mMessage: string;
  mBubbles: TArray<TAtlasHotspotBubble>;
  mMaxChanges, mMaxComplexity: Integer;
  mKern: TAtlasHotspotBubble;
  mBubble: TAtlasHotspotBubble;
begin
  TAtlasHotspotModel.Parse(SampleHotspotAnswer, mModel, mEnabled, mHasVcs, mMessage);
  mModel.Level := 'unit';
  TAtlasHotspotChart.Extent(mModel.Units, mModel.Filter(''), mMaxChanges, mMaxComplexity);
  Assert.AreEqual(12, mMaxChanges);
  Assert.AreEqual(80, mMaxComplexity);
  mBubbles := TAtlasHotspotChart.Layout(mModel.Units, mModel.Filter(''), 400, 300, 1);
  Assert.AreEqual(3, Integer(Length(mBubbles)));
  Assert.AreEqual(0, mBubbles[0].Entry, 'größte zuerst');
  Assert.AreEqual(TAtlasHotspotChart.MaxRadius, mBubbles[0].Radius);
  mKern := mBubbles[0];
  Assert.AreEqual(400 - TAtlasHotspotChart.MarginRight, mKern.X, 'meiste Änderungen ganz rechts');
  Assert.AreEqual(TAtlasHotspotChart.MarginTop, mKern.Y, 'höchste Komplexität ganz oben');
  Assert.AreEqual(0, TAtlasHotspotChart.HitTest(mBubbles, mKern.X, mKern.Y));
  Assert.AreEqual(-1, TAtlasHotspotChart.HitTest(mBubbles, 0, 0));
  // Kleine Blase in einer großen: die kleine gewinnt.
  mBubble := mBubbles[2];
  Assert.AreEqual(mBubble.Entry, TAtlasHotspotChart.HitTest(TArray<TAtlasHotspotBubble>.Create(mKern,
    mBubble), mBubble.X, mBubble.Y));
  Assert.AreEqual(0, Integer(Length(TAtlasHotspotChart.Layout(mModel.Units, mModel.Filter(''), 0, 300, 1))));
  Assert.AreEqual(2 * TAtlasHotspotChart.MaxRadius, TAtlasHotspotChart.Layout(mModel.Units, mModel.Filter(''), 800,
    600, 2)[0].Radius, 'hohe Auflösung');
end;

procedure TAtlasHotspotModelTests.ScoreColorFromGreenToRed;
begin
  Assert.AreEqual(Cardinal($0028AA00), TAtlasHotspotChart.ScoreColor(0), 'grün');
  Assert.AreEqual(Cardinal($0028AAC8), TAtlasHotspotChart.ScoreColor(0.5), 'gelb');
  Assert.AreEqual(Cardinal($002800C8), TAtlasHotspotChart.ScoreColor(1), 'rot');
  Assert.AreEqual(TAtlasHotspotChart.ScoreColor(1), TAtlasHotspotChart.ScoreColor(7), 'begrenzt');
end;

procedure TAtlasHotspotModelTests.CommandArguments;
var
  mValue: TJSONValue;
  mOptions: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasHotspotCommands.Arguments('file:///C:/P/A.dproj', 'method', True));
  try
    Assert.AreEqual('file:///C:/P/A.dproj', TJSONArray(mValue).Items[0].Value);
    mOptions := TJSONArray(mValue).Items[1] as TJSONObject;
    Assert.AreEqual('method', mOptions.GetValue('level').Value);
    Assert.AreEqual('json', mOptions.GetValue('format').Value);
    Assert.IsTrue(TJSONBool(mOptions.GetValue('refresh')).AsBoolean);
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue(TAtlasHotspotCommands.Arguments('file:///C:/P/A.dproj', 'unit', False));
  try
    Assert.IsNull((TJSONArray(mValue).Items[1] as TJSONObject).GetValue('refresh'));
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue(TAtlasHotspotCommands.SaveArguments('file:///C:/P/A.dproj', 'C:\B.html',
    'unit'));
  try
    Assert.AreEqual('C:\B.html', TJSONArray(mValue).Items[1].Value);
  finally
    mValue.Free;
  end;
  Assert.AreEqual('C:\B.html', TAtlasHotspotCommands.SavedFile('{"file":"C:\\B.html","units":3}'));
  Assert.AreEqual('', TAtlasHotspotCommands.SavedFile(''));
  Assert.IsTrue(TAtlasHotspotCommands.IsPending('{"pending":true}'));
  Assert.IsFalse(TAtlasHotspotCommands.IsPending('{"file":"x"}'));
end;

procedure TAtlasHotspotModelTests.FindsNameColumn;
begin
  Assert.AreEqual(16, TAtlasHotspotCommands.NameColumn('procedure TKern.Rechne(A: Integer);', 'TKern.Rechne'));
  Assert.AreEqual(9, TAtlasHotspotCommands.NameColumn('function Rechnen: Integer;', 'Rechnen'));
  Assert.AreEqual(18, TAtlasHotspotCommands.NameColumn('procedure TRechne.rechne;', 'TRechne.Rechne'),
    'ganzes Wort, nicht im Klassennamen');
  Assert.AreEqual(11, TAtlasHotspotCommands.NameColumn('unit Atlas.Kern;', 'Atlas.Kern'));
  Assert.AreEqual(-1, TAtlasHotspotCommands.NameColumn('begin', 'TKern.Rechne'));
  Assert.AreEqual(-1, TAtlasHotspotCommands.NameColumn('procedure X;', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHotspotModelTests);

end.
