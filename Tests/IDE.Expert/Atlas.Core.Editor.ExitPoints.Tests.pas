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
  Answer = '{"query": "routine", "routine": {"name": "TFoo.Wert", "line": 6, "character": 14, "endCharacter": 18},' +
    '"function": true, "exits": 3, "resultMissing": true, "points": [' +
    '{"kind": "exit", "line": 9, "character": 4, "endCharacter": 8, "resultMissing": true, "detail": "",' +
    ' "exception": ""},' +
    '{"kind": "call", "line": 12, "character": 2, "endCharacter": 7, "resultMissing": false, "detail": "Abort",' +
    ' "exception": ""},' +
    '{"kind": "unknown", "line": 13, "character": 0, "endCharacter": 3},' +
    '{"kind": "end", "line": 14, "character": 0, "endCharacter": 3, "resultMissing": false}]}';

function Parsed(const AJson: string): TAtlasExitPointSet;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasExitPointSet.FromJson(Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasExitPointsTests.ReadsServerAnswer;
var
  Found: TAtlasExitPointSet;
begin
  Found := Parsed(Answer);
  Assert.IsTrue(Found.Found);
  Assert.IsTrue(Found.Query = TAtlasExitPointQuery.Routine);
  Assert.IsTrue(Found.HasRoutine);
  Assert.AreEqual('TFoo.Wert', Found.RoutineName);
  Assert.AreEqual(6, Found.RoutineLine);
  Assert.AreEqual(14, Found.RoutineCharacter);
  Assert.AreEqual(18, Found.RoutineEnd);
  Assert.IsTrue(Found.IsFunction);
  Assert.AreEqual(3, Found.Exits);
  Assert.IsTrue(Found.ResultMissing);
  // Unbekannte Arten fallen weg.
  Assert.AreEqual(3, Integer(Length(Found.Points)));
  Assert.IsTrue(Found.Points[0].Kind = TAtlasExitPointKind.ExitCall);
  Assert.IsTrue(Found.Points[0].ResultMissing);
  Assert.IsTrue(Found.Points[1].Kind = TAtlasExitPointKind.RaisingCall);
  Assert.AreEqual('Abort', Found.Points[1].Detail);
  Assert.IsTrue(Found.Points[2].Kind = TAtlasExitPointKind.FallThrough);
  Assert.AreEqual(1, Integer(Length(Found.PointsAt(12))));
  Assert.AreEqual(0, Integer(Length(Found.PointsAt(10))));
  Assert.IsTrue(Found.HasBadge);
end;

procedure TAtlasExitPointsTests.IgnoresUnknownFormat;
var
  Found: TAtlasExitPointSet;
begin
  Found := Parsed('[1, 2]');
  Assert.IsFalse(Found.Found);
  Found := Parsed('{"query": "routine", "points": 5}');
  Assert.IsFalse(Found.Found);
  // Ohne Abfrage zählt auch eine Liste nicht.
  Found := Parsed('{"query": "", "points": [{"kind": "exit", "line": 1, "character": 0, "endCharacter": 4}]}');
  Assert.IsFalse(Found.Found);
  Found := TAtlasExitPointSet.FromJson(nil);
  Assert.IsFalse(Found.Found);
  Assert.IsFalse(Found.HasBadge);
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
  Found: TAtlasExitPointSet;
begin
  Found := Parsed(Answer);
  Assert.IsTrue(Found.Holds(9, 4));
  Assert.IsTrue(Found.Holds(9, 8));
  Assert.IsTrue(Found.Holds(14, 1));
  Assert.IsTrue(Found.Holds(6, 16));
  Assert.IsFalse(Found.Holds(9, 9));
  Assert.IsFalse(Found.Holds(10, 4));
  Assert.IsFalse(Found.Holds(6, 10));
  Assert.AreEqual(1, Found.IndexAt(12, 3));
  Assert.AreEqual(-1, Found.IndexAt(12, 9));
end;

procedure TAtlasExitPointsTests.NextWrapsAround;
var
  Found: TAtlasExitPointSet;
  Point: TAtlasExitPoint;
begin
  Found := Parsed(Answer);
  // Vom Routinennamen zur ersten Stelle.
  Assert.IsTrue(Found.Next(6, 15, False, Point));
  Assert.AreEqual(9, Point.Line);
  // Mitten in einer Stelle zur nächsten, nicht auf sich selbst.
  Assert.IsTrue(Found.Next(9, 6, False, Point));
  Assert.AreEqual(12, Point.Line);
  Assert.IsTrue(Found.Next(14, 0, False, Point));
  Assert.AreEqual(9, Point.Line, 'reihum zum Anfang');
  Assert.IsTrue(Found.Next(9, 6, True, Point));
  Assert.AreEqual(14, Point.Line, 'rueckwaerts reihum zum Ende');
  Assert.IsTrue(Found.Next(14, 2, True, Point));
  Assert.AreEqual(12, Point.Line);
  Found := Default(TAtlasExitPointSet);
  Assert.IsFalse(Found.Next(0, 0, False, Point));
end;

procedure TAtlasExitPointsTests.RolesAndBadge;
var
  Found: TAtlasExitPointSet;
  Point: TAtlasExitPoint;
begin
  Found := Parsed(Answer);
  Assert.IsTrue(Found.Points[0].Role = TAtlasExitPointRole.Missing);
  Assert.IsTrue(Found.Points[1].Role = TAtlasExitPointRole.Leave);
  Point := Default(TAtlasExitPoint);
  Point.Kind := TAtlasExitPointKind.ResultAssign;
  Assert.IsTrue(Point.Role = TAtlasExitPointRole.Assign);
  Point.Kind := TAtlasExitPointKind.ExceptionSource;
  Assert.IsTrue(Point.Role = TAtlasExitPointRole.Source);
  Point.Kind := TAtlasExitPointKind.LoopJump;
  Assert.IsTrue(Point.Role = TAtlasExitPointRole.Loop);
  Assert.AreEqual('3 exits ' + #$00B7 + ' missing', TAtlasExitPoints.BadgeText(Found, 'one', '%d exits', 'missing'));
  Found.Exits := 1;
  Found.ResultMissing := False;
  Assert.AreEqual('one', TAtlasExitPoints.BadgeText(Found, 'one', '%d exits', 'missing'));
  // Auf Schleifen und Exceptions keine Marke.
  Found.Query := TAtlasExitPointQuery.Loop;
  Assert.IsFalse(Found.HasBadge);
  Found.Query := TAtlasExitPointQuery.ResultValue;
  Assert.IsTrue(Found.HasBadge);
end;

procedure TAtlasExitPointsTests.SettingsDefaultsAndElement;
var
  Settings: TAtlasPluginSettings;
  Element: TAtlasDrawnElement;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ExitPoints, 'editor.exitPoints standardmaessig an');
  Assert.IsTrue(Settings.ExitPointsExceptions);
  Assert.IsTrue(Settings.ExitPointsLoops);
  Assert.IsTrue(Settings.ExitPointsBadge);
  Assert.IsTrue(TAtlasDrawnElements.ForSetting('ExitPoints', Element));
  Assert.IsTrue(Element = TAtlasDrawnElement.ExitPoints);
  Assert.IsTrue(TAtlasDrawnElements.Info(Element).Overlay);
  Assert.IsFalse(TAtlasDrawnElements.Info(Element).Gutter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExitPointsTests);

end.
