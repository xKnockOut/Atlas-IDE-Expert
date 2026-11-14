unit Atlas.Core.Editor.ExitPoints.Tests;

// Tests der Austrittspunkte im Plugin (#698): Antwort von
// atlas.server.exitPoints lesen, Auslöser am Cursor, Stellen je Zeile, Halten
// und Springen reihum, Farben, Marke und die Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasExitPointsTests = class
  public
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure IgnoresUnknownFormat;
    [Test]
    procedure TriggersOnKeywordsAssignmentsAndHeader;
    [Test]
    procedure HoldsOnPointsAndRoutineName;
    [Test]
    procedure NextWrapsAround;
    [Test]
    procedure RolesAndBadge;
    [Test]
    procedure SettingsDefaultsAndElement;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.ExitPoints,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Settings.Plugin;

const
  cAnswer = '{"query": "routine", "routine": {"name": "TFoo.Wert", "line": 6, "character": 14, "endCharacter": 18},' +
    '"function": true, "exits": 3, "resultMissing": true, "points": [' +
    '{"kind": "exit", "line": 9, "character": 4, "endCharacter": 8, "resultMissing": true, "detail": "",' +
    ' "exception": ""},' +
    '{"kind": "call", "line": 12, "character": 2, "endCharacter": 7, "resultMissing": false, "detail": "Abort",' +
    ' "exception": ""},' +
    '{"kind": "unknown", "line": 13, "character": 0, "endCharacter": 3},' +
    '{"kind": "end", "line": 14, "character": 0, "endCharacter": 3, "resultMissing": false}]}';

function Parsed(const AJson: string): TAtlasExitPointSet;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasExitPointSet.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasExitPointsTests.ReadsServerAnswer;
var
  mFound: TAtlasExitPointSet;
begin
  mFound := Parsed(cAnswer);
  Assert.IsTrue(mFound.Found);
  Assert.AreEqual<TAtlasExitPointQuery>(TAtlasExitPointQuery.Routine, mFound.Query);
  Assert.IsTrue(mFound.HasRoutine);
  Assert.AreEqual('TFoo.Wert', mFound.RoutineName);
  Assert.AreEqual(6, mFound.RoutineLine);
  Assert.AreEqual(14, mFound.RoutineCharacter);
  Assert.AreEqual(18, mFound.RoutineEnd);
  Assert.IsTrue(mFound.IsFunction);
  Assert.AreEqual(3, mFound.Exits);
  Assert.IsTrue(mFound.ResultMissing);
  // Unbekannte Arten fallen weg.
  Assert.AreEqual(3, Integer(Length(mFound.Points)));
  Assert.AreEqual<TAtlasExitPointKind>(TAtlasExitPointKind.ExitCall, mFound.Points[0].Kind);
  Assert.IsTrue(mFound.Points[0].ResultMissing);
  Assert.AreEqual<TAtlasExitPointKind>(TAtlasExitPointKind.RaisingCall, mFound.Points[1].Kind);
  Assert.AreEqual('Abort', mFound.Points[1].Detail);
  Assert.AreEqual<TAtlasExitPointKind>(TAtlasExitPointKind.FallThrough, mFound.Points[2].Kind);
  Assert.AreEqual(1, Integer(Length(mFound.PointsAt(12))));
  Assert.AreEqual(0, Integer(Length(mFound.PointsAt(10))));
  Assert.IsTrue(mFound.HasBadge);
end;

procedure TAtlasExitPointsTests.IgnoresUnknownFormat;
var
  mFound: TAtlasExitPointSet;
begin
  mFound := Parsed('[1, 2]');
  Assert.IsFalse(mFound.Found);
  mFound := Parsed('{"query": "routine", "points": 5}');
  Assert.IsFalse(mFound.Found);
  // Ohne Abfrage zählt auch eine Liste nicht.
  mFound := Parsed('{"query": "", "points": [{"kind": "exit", "line": 1, "character": 0, "endCharacter": 4}]}');
  Assert.IsFalse(mFound.Found);
  mFound := TAtlasExitPointSet.FromJson(nil);
  Assert.IsFalse(mFound.Found);
  Assert.IsFalse(mFound.HasBadge);
end;

procedure TAtlasExitPointsTests.TriggersOnKeywordsAssignmentsAndHeader;
begin
  Assert.IsTrue(TAtlasExitPoints.Triggers('    Exit;', 6));
  // Cursor direkt hinter dem Wort zählt auch.
  Assert.IsTrue(TAtlasExitPoints.Triggers('    Exit;', 8));
  Assert.IsTrue(TAtlasExitPoints.Triggers('  raise;', 3));
  Assert.IsTrue(TAtlasExitPoints.Triggers('  RunError(3);', 4));
  Assert.IsTrue(TAtlasExitPoints.Triggers('  Result := 1;', 3));
  Assert.IsTrue(TAtlasExitPoints.Triggers('  except', 4));
  Assert.IsTrue(TAtlasExitPoints.Triggers('    on E: EFoo do', 5));
  Assert.IsTrue(TAtlasExitPoints.Triggers('      Break;', 8));
  Assert.IsTrue(TAtlasExitPoints.Triggers('      continue;', 8));
  // Funktionsname als Ziel.
  Assert.IsTrue(TAtlasExitPoints.Triggers('  Wert := 5;', 3));
  // Kopf, auch mit Klasse, class und Generika.
  Assert.IsTrue(TAtlasExitPoints.Triggers('function TFoo.Wert(A: Integer): Integer;', 15));
  Assert.IsTrue(TAtlasExitPoints.Triggers('class procedure TFoo<T>.Run;', 25));
  Assert.IsTrue(TAtlasExitPoints.Triggers('procedure Run;', 11));
  // Keine Auslöser.
  Assert.IsFalse(TAtlasExitPoints.Triggers('  Foo(Bar);', 7));
  Assert.IsFalse(TAtlasExitPoints.Triggers('  Foo(Bar);', 0));
  Assert.IsFalse(TAtlasExitPoints.Triggers('    Exit;', 1));
  Assert.IsFalse(TAtlasExitPoints.Triggers('', 0));
  // Parameter im Kopf sind kein Name der Routine.
  Assert.IsFalse(TAtlasExitPoints.Triggers('function TFoo.Wert(A: Integer): Integer;', 19));
end;

procedure TAtlasExitPointsTests.HoldsOnPointsAndRoutineName;
var
  mFound: TAtlasExitPointSet;
begin
  mFound := Parsed(cAnswer);
  Assert.IsTrue(mFound.Holds(9, 4));
  Assert.IsTrue(mFound.Holds(9, 8));
  Assert.IsTrue(mFound.Holds(14, 1));
  Assert.IsTrue(mFound.Holds(6, 16));
  Assert.IsFalse(mFound.Holds(9, 9));
  Assert.IsFalse(mFound.Holds(10, 4));
  Assert.IsFalse(mFound.Holds(6, 10));
  Assert.AreEqual(1, mFound.IndexAt(12, 3));
  Assert.AreEqual(-1, mFound.IndexAt(12, 9));
end;

procedure TAtlasExitPointsTests.NextWrapsAround;
var
  mFound: TAtlasExitPointSet;
  mPoint: TAtlasExitPoint;
begin
  mFound := Parsed(cAnswer);
  // Vom Routinennamen zur ersten Stelle.
  Assert.IsTrue(mFound.Next(6, 15, False, mPoint));
  Assert.AreEqual(9, mPoint.Line);
  // Mitten in einer Stelle zur nächsten, nicht auf sich selbst.
  Assert.IsTrue(mFound.Next(9, 6, False, mPoint));
  Assert.AreEqual(12, mPoint.Line);
  Assert.IsTrue(mFound.Next(14, 0, False, mPoint));
  Assert.AreEqual(9, mPoint.Line, 'reihum zum Anfang');
  Assert.IsTrue(mFound.Next(9, 6, True, mPoint));
  Assert.AreEqual(14, mPoint.Line, 'rueckwaerts reihum zum Ende');
  Assert.IsTrue(mFound.Next(14, 2, True, mPoint));
  Assert.AreEqual(12, mPoint.Line);
  mFound := Default(TAtlasExitPointSet);
  Assert.IsFalse(mFound.Next(0, 0, False, mPoint));
end;

procedure TAtlasExitPointsTests.RolesAndBadge;
var
  mFound: TAtlasExitPointSet;
  mPoint: TAtlasExitPoint;
begin
  mFound := Parsed(cAnswer);
  Assert.AreEqual<TAtlasExitPointRole>(TAtlasExitPointRole.Missing, mFound.Points[0].Role);
  Assert.AreEqual<TAtlasExitPointRole>(TAtlasExitPointRole.Leave, mFound.Points[1].Role);
  mPoint := Default(TAtlasExitPoint);
  mPoint.Kind := TAtlasExitPointKind.ResultAssign;
  Assert.AreEqual<TAtlasExitPointRole>(TAtlasExitPointRole.Assign, mPoint.Role);
  mPoint.Kind := TAtlasExitPointKind.ExceptionSource;
  Assert.AreEqual<TAtlasExitPointRole>(TAtlasExitPointRole.Source, mPoint.Role);
  mPoint.Kind := TAtlasExitPointKind.LoopJump;
  Assert.AreEqual<TAtlasExitPointRole>(TAtlasExitPointRole.Loop, mPoint.Role);
  Assert.AreEqual('3 exits ' + #$00B7 + ' missing', TAtlasExitPoints.BadgeText(mFound, 'one', '%d exits', 'missing'));
  mFound.Exits := 1;
  mFound.ResultMissing := False;
  Assert.AreEqual('one', TAtlasExitPoints.BadgeText(mFound, 'one', '%d exits', 'missing'));
  // Auf Schleifen und Exceptions keine Marke.
  mFound.Query := TAtlasExitPointQuery.Loop;
  Assert.IsFalse(mFound.HasBadge);
  mFound.Query := TAtlasExitPointQuery.ResultValue;
  Assert.IsTrue(mFound.HasBadge);
end;

procedure TAtlasExitPointsTests.SettingsDefaultsAndElement;
var
  mSettings: TAtlasPluginSettings;
  mElement: TAtlasDrawnElement;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ExitPoints, 'editor.exitPoints standardmaessig an');
  Assert.IsTrue(mSettings.ExitPointsExceptions);
  Assert.IsTrue(mSettings.ExitPointsLoops);
  Assert.IsTrue(mSettings.ExitPointsBadge);
  Assert.IsTrue(TAtlasDrawnElements.ForSetting('ExitPoints', mElement));
  Assert.AreEqual<TAtlasDrawnElement>(TAtlasDrawnElement.ExitPoints, mElement);
  Assert.IsTrue(TAtlasDrawnElements.Info(mElement).Overlay);
  Assert.IsFalse(TAtlasDrawnElements.Info(mElement).Gutter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExitPointsTests);

end.
