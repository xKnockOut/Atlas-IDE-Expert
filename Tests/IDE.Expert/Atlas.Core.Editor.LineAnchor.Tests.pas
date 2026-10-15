unit Atlas.Core.Editor.LineAnchor.Tests;

// Tests der Verankerung an einer Codezeile (gemeinsam für Notizen #545 und
// Lesezeichen #622): folgt eingefügten und gelöschten Zeilen, Einrückung
// egal, geänderte Zeile bleibt, gelöschte Zeile verwaist; Suche nur in einem
// Bereich (Rumpf einer Methode, #622).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLineAnchorTests = class
  public
    [Test]
    procedure NormalizeCollapsesWhitespace;
    [Test]
    procedure CaptureTakesNeighbours;
    [Test]
    procedure StaysWhenNothingChanged;
    /// <summary>Akzeptanzkriterium: Die Notiz bleibt nach Einfügen von Zeilen oberhalb an ihrer Codezeile.</summary>
    [Test]
    procedure FollowsLinesInsertedAbove;
    [Test]
    procedure FollowsLinesRemovedAbove;
    [Test]
    procedure IgnoresIndentation;
    [Test]
    procedure StaysOnEditedLine;
    [Test]
    procedure DeletedLineIsOrphaned;
    [Test]
    procedure RepeatedLineFollowsNeighbours;
    [Test]
    procedure RepeatedLineWithoutNeighboursIsOrphaned;
    [Test]
    procedure EmptyLineNeedsNeighbour;
    /// <summary>Lesezeichen (#622): Suche nur im Rumpf einer Methode, die nächste Stelle zur erwarteten Zeile.</summary>
    [Test]
    procedure RangeLimitsSearch;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.LineAnchor;

function Code: TArray<string>;
begin
  Result := ['unit Kunde;', '', 'interface', '', 'implementation', '', 'function Runde(X: Double): Double;',
    'begin', '  Result := Round(X * 100) / 100;', 'end;', '', 'end.'];
end;

function Insert(const ALines: TArray<string>; AAt: Integer; const ANew: TArray<string>): TArray<string>;
begin
  Result := Copy(ALines, 0, AAt) + ANew + Copy(ALines, AAt, Length(ALines) - AAt);
end;

function Without(const ALines: TArray<string>; AAt, ACount: Integer): TArray<string>;
begin
  Result := Copy(ALines, 0, AAt) + Copy(ALines, AAt + ACount, Length(ALines) - AAt - ACount);
end;

{ TAtlasLineAnchorTests }

procedure TAtlasLineAnchorTests.NormalizeCollapsesWhitespace;
begin
  Assert.AreEqual('Result := Round(X);', TAtlasLineAnchors.Normalize(#9'  Result  :='#9'Round(X);  '));
  Assert.AreEqual('', TAtlasLineAnchors.Normalize('   '#9));
  Assert.AreEqual(3, Length(TAtlasLineAnchors.Lines('a'#13#10'b'#10'c')));
end;

procedure TAtlasLineAnchorTests.CaptureTakesNeighbours;
var
  Anchor: TAtlasLineAnchor;
begin
  Anchor := TAtlasLineAnchors.Capture(Code, 8);
  Assert.AreEqual(8, Anchor.Line);
  Assert.AreEqual('Result := Round(X * 100) / 100;', Anchor.Text);
  Assert.AreEqual(2, Length(Anchor.Before));
  Assert.AreEqual('begin', Anchor.Before[0], 'nächste Zeile zuerst');
  Assert.AreEqual('function Runde(X: Double): Double;', Anchor.Before[1]);
  Assert.AreEqual('end;', Anchor.After[0]);
  Assert.AreEqual('', Anchor.After[1]);
  // Am Rand gibt es weniger Nachbarn.
  Anchor := TAtlasLineAnchors.Capture(Code, 0);
  Assert.AreEqual(0, Length(Anchor.Before));
  Assert.AreEqual(2, Length(Anchor.After));
  Anchor := TAtlasLineAnchors.Capture(Code, 11);
  Assert.AreEqual(0, Length(Anchor.After));
  Anchor := TAtlasLineAnchors.Capture(Code, 99);
  Assert.AreEqual('', Anchor.Text, 'außerhalb des Textes');
end;

procedure TAtlasLineAnchorTests.StaysWhenNothingChanged;
var
  Line: Integer;
begin
  Assert.AreEqual(Ord(TAtlasLineMatch.Same),
    Ord(TAtlasLineAnchors.Locate(Code, TAtlasLineAnchors.Capture(Code, 8), Line)));
  Assert.AreEqual(8, Line);
end;

procedure TAtlasLineAnchorTests.FollowsLinesInsertedAbove;
var
  Anchor: TAtlasLineAnchor;
  Changed: TArray<string>;
  Line: Integer;
begin
  Anchor := TAtlasLineAnchors.Capture(Code, 8);
  Changed := Insert(Code, 4, ['uses', '  System.Math;', '']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(Changed, Anchor, Line)));
  Assert.AreEqual(11, Line);
  Assert.AreEqual('  Result := Round(X * 100) / 100;', Changed[Line]);
  // Auch direkt über der Zeile eingefügt (der nächste Nachbar ändert sich).
  Changed := Insert(Code, 8, ['  // Rundung', '  X := Abs(X);']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(Changed, Anchor, Line)));
  Assert.AreEqual(10, Line);
end;

procedure TAtlasLineAnchorTests.FollowsLinesRemovedAbove;
var
  Line: Integer;
begin
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(Without(Code, 1, 3), TAtlasLineAnchors.Capture(Code, 8), Line)));
  Assert.AreEqual(5, Line);
end;

procedure TAtlasLineAnchorTests.IgnoresIndentation;
var
  Changed: TArray<string>;
  Line: Integer;
begin
  Changed := Copy(Code, 0, Length(Code));
  Changed[8] := #9'Result   :=  Round(X * 100) / 100;';
  Assert.AreEqual(Ord(TAtlasLineMatch.Same),
    Ord(TAtlasLineAnchors.Locate(Changed, TAtlasLineAnchors.Capture(Code, 8), Line)));
  Assert.AreEqual(8, Line);
end;

procedure TAtlasLineAnchorTests.StaysOnEditedLine;
var
  Changed: TArray<string>;
  Line: Integer;
begin
  Changed := Insert(Code, 0, ['// Kopf']);
  Changed[9] := '  Result := RoundTo(X, -2);';
  Assert.AreEqual(Ord(TAtlasLineMatch.Changed),
    Ord(TAtlasLineAnchors.Locate(Changed, TAtlasLineAnchors.Capture(Code, 8), Line)));
  Assert.AreEqual(9, Line);
end;

procedure TAtlasLineAnchorTests.DeletedLineIsOrphaned;
var
  Line: Integer;
begin
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(Without(Code, 8, 1), TAtlasLineAnchors.Capture(Code, 8), Line)));
  Assert.AreEqual(8, Line, 'behält die letzte Zeile');
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(nil, TAtlasLineAnchors.Capture(Code, 8), Line)), 'leere Datei');
end;

procedure TAtlasLineAnchorTests.RepeatedLineFollowsNeighbours;
var
  Lines, Changed: TArray<string>;
  Line: Integer;
begin
  Lines := ['procedure A;', 'begin', '  Lade;', 'end;', '', 'procedure B;', 'begin', '  Speichere;', 'end;'];
  // Notiz am zweiten „end;“; davor kommt eine neue Routine mit weiterem „end;“.
  Changed := Insert(Lines, 5, ['procedure C;', 'begin', 'end;', '']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(Changed, TAtlasLineAnchors.Capture(Lines, 8), Line)));
  Assert.AreEqual(12, Line);
  Assert.AreEqual('  Speichere;', Changed[Line - 1]);
end;

procedure TAtlasLineAnchorTests.RepeatedLineWithoutNeighboursIsOrphaned;
var
  Anchor: TAtlasLineAnchor;
  Line: Integer;
begin
  Anchor := Default(TAtlasLineAnchor);
  Anchor.Line := 1;
  Anchor.Text := 'end;';
  Anchor.Before := ['  Weg;'];
  Anchor.After := ['  Auch weg;'];
  // Mehrere „end;“, keiner mit passendem Nachbarn, die bisherige Zeile ist keins: nicht eindeutig.
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(['begin', 'x;', 'end;', 'y;', 'end;'], Anchor, Line)));
  // Steht an der bisherigen Zeile noch ein „end;“, bleibt die Notiz dort.
  Assert.AreEqual(Ord(TAtlasLineMatch.Same),
    Ord(TAtlasLineAnchors.Locate(['begin', 'end;', 'y;', 'end;'], Anchor, Line)));
  Assert.AreEqual(1, Line);
  // Nur einmal vorhanden: eindeutig, auch ohne Nachbarn.
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(['a;', 'b;', 'c;', 'end;'], Anchor, Line)));
  Assert.AreEqual(3, Line);
end;

procedure TAtlasLineAnchorTests.EmptyLineNeedsNeighbour;
var
  Anchor: TAtlasLineAnchor;
  Line: Integer;
begin
  Anchor := TAtlasLineAnchors.Capture(['a;', 'b;', '', 'c;', 'd;'], 2);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(['x;', 'a;', 'b;', '', 'c;', 'd;'], Anchor, Line)));
  Assert.AreEqual(3, Line);
  // Leere Zeilen gibt es viele; ohne passenden Nachbarn ist keine gemeint.
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(['', 'x;', '', 'y;'], Anchor, Line)));
end;

procedure TAtlasLineAnchorTests.RangeLimitsSearch;
var
  Lines: TArray<string>;
  Anchor: TAtlasLineAnchor;
  Line: Integer;
begin
  Lines := ['procedure A;', 'begin', '  Speichere;', 'end;', '', 'procedure B;', 'begin', '  Lade;', '  Speichere;',
    'end;'];
  Anchor := TAtlasLineAnchors.Capture(Lines, 8);
  // Ohne Bereich gewinnt die Stelle mit passenden Nachbarn.
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasLineAnchors.Locate(Lines, Anchor, Line)));
  Assert.AreEqual(8, Line);
  // Nur in A gesucht: die einzige Stelle dort, auch ohne passende Nachbarn.
  Anchor.Line := 2;
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasLineAnchors.Locate(Lines, Anchor, 0, 3, Line)));
  Assert.AreEqual(2, Line);
  // Nur in B, erwartet an Zeile 7: gefunden eine Zeile weiter.
  Anchor.Line := 7;
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(Lines, Anchor, 5, 9, Line)));
  Assert.AreEqual(8, Line);
  // Außerhalb des Bereichs zählt nichts.
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned), Ord(TAtlasLineAnchors.Locate(Lines, Anchor, 0, 1, Line)));
  Assert.AreEqual(7, Line, 'behält die erwartete Zeile');
  // Bereich über den Text hinaus wird begrenzt.
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(Lines, Anchor, -5, 99, Line)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineAnchorTests);

end.
