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
    /// <summary>Lesezeichen (#622): Suche nur im Rumpf einer Methode, die nächste Stelle zur erwarteten
    /// Zeile.</summary>
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
  Assert.AreEqual(3, Integer(Length(TAtlasLineAnchors.Lines('a'#13#10'b'#10'c'))));
end;

procedure TAtlasLineAnchorTests.CaptureTakesNeighbours;
var
  mAnchor: TAtlasLineAnchor;
begin
  mAnchor := TAtlasLineAnchors.Capture(Code, 8);
  Assert.AreEqual(8, mAnchor.Line);
  Assert.AreEqual('Result := Round(X * 100) / 100;', mAnchor.Text);
  Assert.AreEqual(2, Integer(Length(mAnchor.Before)));
  Assert.AreEqual('begin', mAnchor.Before[0], 'nächste Zeile zuerst');
  Assert.AreEqual('function Runde(X: Double): Double;', mAnchor.Before[1]);
  Assert.AreEqual('end;', mAnchor.After[0]);
  Assert.AreEqual('', mAnchor.After[1]);
  // Am Rand gibt es weniger Nachbarn.
  mAnchor := TAtlasLineAnchors.Capture(Code, 0);
  Assert.AreEqual(0, Integer(Length(mAnchor.Before)));
  Assert.AreEqual(2, Integer(Length(mAnchor.After)));
  mAnchor := TAtlasLineAnchors.Capture(Code, 11);
  Assert.AreEqual(0, Integer(Length(mAnchor.After)));
  mAnchor := TAtlasLineAnchors.Capture(Code, 99);
  Assert.AreEqual('', mAnchor.Text, 'außerhalb des Textes');
end;

procedure TAtlasLineAnchorTests.StaysWhenNothingChanged;
var
  mLine: Integer;
begin
  Assert.AreEqual(Ord(TAtlasLineMatch.Same),
    Ord(TAtlasLineAnchors.Locate(Code, TAtlasLineAnchors.Capture(Code, 8), mLine)));
  Assert.AreEqual(8, mLine);
end;

procedure TAtlasLineAnchorTests.FollowsLinesInsertedAbove;
var
  mAnchor: TAtlasLineAnchor;
  mChanged: TArray<string>;
  mLine: Integer;
begin
  mAnchor := TAtlasLineAnchors.Capture(Code, 8);
  mChanged := Insert(Code, 4, ['uses', '  System.Math;', '']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(mChanged, mAnchor, mLine)));
  Assert.AreEqual(11, mLine);
  Assert.AreEqual('  Result := Round(X * 100) / 100;', mChanged[mLine]);
  // Auch direkt über der Zeile eingefügt (der nächste Nachbar ändert sich).
  mChanged := Insert(Code, 8, ['  // Rundung', '  X := Abs(X);']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(mChanged, mAnchor, mLine)));
  Assert.AreEqual(10, mLine);
end;

procedure TAtlasLineAnchorTests.FollowsLinesRemovedAbove;
var
  mLine: Integer;
begin
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(Without(Code, 1, 3), TAtlasLineAnchors.Capture(Code, 8), mLine)));
  Assert.AreEqual(5, mLine);
end;

procedure TAtlasLineAnchorTests.IgnoresIndentation;
var
  mChanged: TArray<string>;
  mLine: Integer;
begin
  mChanged := Copy(Code, 0, Length(Code));
  mChanged[8] := #9'Result   :=  Round(X * 100) / 100;';
  Assert.AreEqual(Ord(TAtlasLineMatch.Same),
    Ord(TAtlasLineAnchors.Locate(mChanged, TAtlasLineAnchors.Capture(Code, 8), mLine)));
  Assert.AreEqual(8, mLine);
end;

procedure TAtlasLineAnchorTests.StaysOnEditedLine;
var
  mChanged: TArray<string>;
  mLine: Integer;
begin
  mChanged := Insert(Code, 0, ['// Kopf']);
  mChanged[9] := '  Result := RoundTo(X, -2);';
  Assert.AreEqual(Ord(TAtlasLineMatch.Changed),
    Ord(TAtlasLineAnchors.Locate(mChanged, TAtlasLineAnchors.Capture(Code, 8), mLine)));
  Assert.AreEqual(9, mLine);
end;

procedure TAtlasLineAnchorTests.DeletedLineIsOrphaned;
var
  mLine: Integer;
begin
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(Without(Code, 8, 1), TAtlasLineAnchors.Capture(Code, 8), mLine)));
  Assert.AreEqual(8, mLine, 'behält die letzte Zeile');
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(nil, TAtlasLineAnchors.Capture(Code, 8), mLine)), 'leere Datei');
end;

procedure TAtlasLineAnchorTests.RepeatedLineFollowsNeighbours;
var
  mLines, mChanged: TArray<string>;
  mLine: Integer;
begin
  mLines := ['procedure A;', 'begin', '  Lade;', 'end;', '', 'procedure B;', 'begin', '  Speichere;', 'end;'];
  // Notiz am zweiten „end;“; davor kommt eine neue Routine mit weiterem „end;“.
  mChanged := Insert(mLines, 5, ['procedure C;', 'begin', 'end;', '']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(mChanged, TAtlasLineAnchors.Capture(mLines, 8), mLine)));
  Assert.AreEqual(12, mLine);
  Assert.AreEqual('  Speichere;', mChanged[mLine - 1]);
end;

procedure TAtlasLineAnchorTests.RepeatedLineWithoutNeighboursIsOrphaned;
var
  mAnchor: TAtlasLineAnchor;
  mLine: Integer;
begin
  mAnchor := Default(TAtlasLineAnchor);
  mAnchor.Line := 1;
  mAnchor.Text := 'end;';
  mAnchor.Before := ['  Weg;'];
  mAnchor.After := ['  Auch weg;'];
  // Mehrere „end;“, keiner mit passendem Nachbarn, die bisherige Zeile ist keins: nicht eindeutig.
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(['begin', 'x;', 'end;', 'y;', 'end;'], mAnchor, mLine)));
  // Steht an der bisherigen Zeile noch ein „end;“, bleibt die Notiz dort.
  Assert.AreEqual(Ord(TAtlasLineMatch.Same),
    Ord(TAtlasLineAnchors.Locate(['begin', 'end;', 'y;', 'end;'], mAnchor, mLine)));
  Assert.AreEqual(1, mLine);
  // Nur einmal vorhanden: eindeutig, auch ohne Nachbarn.
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(['a;', 'b;', 'c;', 'end;'], mAnchor, mLine)));
  Assert.AreEqual(3, mLine);
end;

procedure TAtlasLineAnchorTests.EmptyLineNeedsNeighbour;
var
  mAnchor: TAtlasLineAnchor;
  mLine: Integer;
begin
  mAnchor := TAtlasLineAnchors.Capture(['a;', 'b;', '', 'c;', 'd;'], 2);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved),
    Ord(TAtlasLineAnchors.Locate(['x;', 'a;', 'b;', '', 'c;', 'd;'], mAnchor, mLine)));
  Assert.AreEqual(3, mLine);
  // Leere Zeilen gibt es viele; ohne passenden Nachbarn ist keine gemeint.
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasLineAnchors.Locate(['', 'x;', '', 'y;'], mAnchor, mLine)));
end;

procedure TAtlasLineAnchorTests.RangeLimitsSearch;
var
  mLines: TArray<string>;
  mAnchor: TAtlasLineAnchor;
  mLine: Integer;
begin
  mLines := ['procedure A;', 'begin', '  Speichere;', 'end;', '', 'procedure B;', 'begin', '  Lade;', '  Speichere;',
    'end;'];
  mAnchor := TAtlasLineAnchors.Capture(mLines, 8);
  // Ohne Bereich gewinnt die Stelle mit passenden Nachbarn.
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasLineAnchors.Locate(mLines, mAnchor, mLine)));
  Assert.AreEqual(8, mLine);
  // Nur in A gesucht: die einzige Stelle dort, auch ohne passende Nachbarn.
  mAnchor.Line := 2;
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasLineAnchors.Locate(mLines, mAnchor, 0, 3, mLine)));
  Assert.AreEqual(2, mLine);
  // Nur in B, erwartet an Zeile 7: gefunden eine Zeile weiter.
  mAnchor.Line := 7;
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(mLines, mAnchor, 5, 9, mLine)));
  Assert.AreEqual(8, mLine);
  // Außerhalb des Bereichs zählt nichts.
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned), Ord(TAtlasLineAnchors.Locate(mLines, mAnchor, 0, 1, mLine)));
  Assert.AreEqual(7, mLine, 'behält die erwartete Zeile');
  // Bereich über den Text hinaus wird begrenzt.
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasLineAnchors.Locate(mLines, mAnchor, -5, 99, mLine)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineAnchorTests);

end.
