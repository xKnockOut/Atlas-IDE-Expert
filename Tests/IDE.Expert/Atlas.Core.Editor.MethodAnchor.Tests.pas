unit Atlas.Core.Editor.MethodAnchor.Tests;

// Tests der Verankerung an einer Methode (Lesezeichen #622, Haltepunkt-Sätze
// #586, wandernde Haltepunkte #841): eingefügte Zeilen über der Methode,
// verschobene Methode, Überladungen, doppelte Zeilentexte in anderen
// Methoden, entfernte Zeile und Methode, JSON hin und zurück.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMethodAnchorTests = class
  public
    [Test]
    procedure CaptureNamesMethodAndOffset;
    /// <summary>Akzeptanzkriterium #586: zehn Zeilen über der Routine eingefügt.</summary>
    [Test]
    procedure FollowsTenLinesInsertedAbove;
    [Test]
    procedure FollowsMovedMethod;
    [Test]
    procedure SameTextInOtherMethodIsIgnored;
    [Test]
    procedure PrefersSameOverload;
    [Test]
    procedure RemovedLineAndMethodAreOrphaned;
    [Test]
    procedure OutsideMethodUsesWholeFile;
    [Test]
    procedure JsonRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Editor.MethodAnchor;

const
  cUnit =
    'unit Kunden;' + #10 +
    'interface' + #10 +
    'type' + #10 +
    '  TKunde = class' + #10 +
    '    procedure Speichere;' + #10 +
    '    procedure Lade(A: Integer); overload;' + #10 +
    '    procedure Lade(const S: string); overload;' + #10 +
    '  end;' + #10 +
    'implementation' + #10 +
    '' + #10 +
    'procedure TKunde.Speichere;' + #10 +
    'begin' + #10 +
    '  Pruefe;' + #10 +
    '  Schreibe;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'procedure TKunde.Lade(A: Integer);' + #10 +
    'begin' + #10 +
    '  Schreibe;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'procedure TKunde.Lade(const S: string);' + #10 +
    'begin' + #10 +
    '  Schreibe;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'end.' + #10;
  // Zeilen (0-basiert): Speichere 10, "Schreibe" in Speichere 13; Lade(Integer) 16, Rumpf 18; Lade(string) 21,
  // Rumpf 23.

function Src: string;
begin
  Result := cUnit;
end;

function TenLines: string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to 10 do
  begin
    Result := Result + '// Zeile ' + IntToStr(mIndex) + #10;
  end;
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := TAtlasLineAnchors.Lines(AText);
end;

{ TAtlasMethodAnchorTests }

procedure TAtlasMethodAnchorTests.CaptureNamesMethodAndOffset;
var
  mAnchor: TAtlasMethodAnchor;
begin
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 13);
  Assert.AreEqual('TKunde.Speichere', mAnchor.Method);
  Assert.AreEqual(3, mAnchor.Offset);
  Assert.AreEqual('Schreibe;', mAnchor.Anchor.Text);
  Assert.AreEqual(13, mAnchor.Line);
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 4);
  Assert.AreEqual('', mAnchor.Method, 'Deklaration ist kein Rumpf');
end;

procedure TAtlasMethodAnchorTests.FollowsTenLinesInsertedAbove;
var
  mAnchor: TAtlasMethodAnchor;
  mText: string;
  mLine: Integer;
begin
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 13);
  mText := Src.Replace('implementation' + #10, 'implementation' + #10 + TenLines);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasMethodAnchors.Find(mText, mAnchor, mLine)));
  Assert.AreEqual(23, mLine);
  Assert.AreEqual('  Schreibe;', Lines(mText)[mLine]);
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasMethodAnchors.Find(cUnit, mAnchor, mLine)));
  Assert.AreEqual(13, mLine);
end;

procedure TAtlasMethodAnchorTests.FollowsMovedMethod;
var
  mAnchor: TAtlasMethodAnchor;
  mBody, mText: string;
  mLine: Integer;
begin
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 13);
  // Speichere ans Ende verschoben.
  mBody := 'procedure TKunde.Speichere;' + #10 + 'begin' + #10 + '  Pruefe;' + #10 + '  Schreibe;' + #10 + 'end;' +
    #10 + #10;
  mText := Src.Replace(mBody, '').Replace('end.' + #10, mBody + 'end.' + #10);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasMethodAnchors.Find(mText, mAnchor, mLine)));
  Assert.AreEqual('TKunde.Speichere', TAtlasMethodAnchors.Capture(mText, mLine).Method);
  Assert.AreEqual('  Schreibe;', Lines(mText)[mLine]);
end;

procedure TAtlasMethodAnchorTests.SameTextInOtherMethodIsIgnored;
var
  mAnchor: TAtlasMethodAnchor;
  mText: string;
  mLine: Integer;
begin
  // "Schreibe;" steht in allen drei Methoden; der Anker aus Lade(Integer) bleibt dort.
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 18);
  mText := TenLines + cUnit;
  TAtlasMethodAnchors.Find(mText, mAnchor, mLine);
  Assert.AreEqual(28, mLine);
  Assert.AreEqual('TKunde.Lade', TAtlasMethodAnchors.Capture(mText, mLine).Method);
end;

procedure TAtlasMethodAnchorTests.PrefersSameOverload;
var
  mAnchor: TAtlasMethodAnchor;
  mLine: Integer;
begin
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 23);
  Assert.AreEqual('TKunde.Lade', mAnchor.Method);
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasMethodAnchors.Find(cUnit, mAnchor, mLine)));
  Assert.AreEqual(23, mLine, 'Lade(string), nicht die nähere Überladung');
end;

procedure TAtlasMethodAnchorTests.RemovedLineAndMethodAreOrphaned;
var
  mAnchor: TAtlasMethodAnchor;
  mLine: Integer;
begin
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 12);
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasMethodAnchors.Find(Src.Replace('  Pruefe;' + #10, ''), mAnchor, mLine)));
  Assert.AreEqual(12, mLine, 'behält die letzte Zeile');
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned),
    Ord(TAtlasMethodAnchors.Find(Src.Replace('TKunde.Speichere;' + #10 + 'begin', 'TKunde.Sichere;' + #10 + 'begin'),
    mAnchor, mLine)), 'Methode umbenannt');
end;

procedure TAtlasMethodAnchorTests.OutsideMethodUsesWholeFile;
var
  mAnchor: TAtlasMethodAnchor;
  mLine: Integer;
begin
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 4);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasMethodAnchors.Find(TenLines + cUnit, mAnchor, mLine)));
  Assert.AreEqual(14, mLine);
end;

procedure TAtlasMethodAnchorTests.JsonRoundTrip;
var
  mAnchor, mRead: TAtlasMethodAnchor;
  mObject: TJSONObject;
begin
  mAnchor := TAtlasMethodAnchors.Capture(cUnit, 23);
  mObject := TJSONObject.Create;
  try
    TAtlasMethodAnchors.AddTo(mObject, mAnchor);
    Assert.AreEqual(24, TJsonRead.IntOr(mObject, 'line', 0), 'Zeile ab 1');
    mRead := TAtlasMethodAnchors.ReadFrom(mObject);
  finally
    mObject.Free;
  end;
  Assert.IsTrue(mRead.SameAs(mAnchor));
  mRead := TAtlasMethodAnchors.ReadFrom(nil);
  Assert.AreEqual('', mRead.Method);
end;

end.
