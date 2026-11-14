unit Atlas.Common.Editing.TypeComments.Tests;

// Kommentar über dem Abschnitt eines Typs (#1835): Formen erkennen und
// schreiben, Typnamen beim Umbenennen finden (#1838).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeCommentsTests = class
  public
    [Test]
    procedure StyleNames;
    [Test]
    procedure WritesAllStyles;
    [Test]
    procedure FindsAllStyles;
    [Test]
    procedure IgnoresOtherComments;
    [Test]
    procedure ReadsSummary;
    [Test]
    procedure RenamesHeaderLine;
    [Test]
    procedure NameSpotsOverBodies;
    [Test]
    procedure NameSpotsOfNestedType;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.TypeComments;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Split([#10]);
end;

procedure TTypeCommentsTests.StyleNames;
var
  mStyle: TTypeCommentStyle;
begin
  for mStyle := Low(TTypeCommentStyle) to High(TTypeCommentStyle) do
  begin
    Assert.AreEqual(Ord(mStyle), Ord(TTypeComments.StyleOf(TTypeComments.StyleName(mStyle))));
  end;
  Assert.AreEqual(Ord(TTypeCommentStyle.Brace), Ord(TTypeComments.StyleOf('')), 'Vorgabe wie die IDE');
  Assert.AreEqual(Ord(TTypeCommentStyle.Brace), Ord(TTypeComments.StyleOf('kasten')));
end;

procedure TTypeCommentsTests.WritesAllStyles;
var
  mHeader: TArray<string>;
begin
  Assert.AreEqual('{ TKunde }', TTypeComments.Header(TTypeCommentStyle.Brace, 'TKunde', '', 0)[0]);
  mHeader := TTypeComments.Header(TTypeCommentStyle.Line, 'TKunde', '', 40);
  Assert.AreEqual(3, Integer(Length(mHeader)));
  Assert.AreEqual(40, Integer(Length(mHeader[0])), 'Breite nach maxLineLength');
  Assert.AreEqual('// TKunde', mHeader[1]);
  Assert.AreEqual(TTypeComments.cDefaultLineLength,
    Integer(Length(TTypeComments.Header(TTypeCommentStyle.Line, 'TKunde', '', 0)[2])), 'ohne Vorgabe 80');
  Assert.AreEqual('{ TKunde: Kunde mit Adresse. }',
    TTypeComments.Header(TTypeCommentStyle.Summary, 'TKunde', 'Kunde mit Adresse.', 0)[0]);
  Assert.AreEqual('{ TKunde }', TTypeComments.Header(TTypeCommentStyle.Summary, 'TKunde', '', 0)[0],
    'ohne Doku wie brace');
  Assert.AreEqual('{$REGION ''TKunde''}', TTypeComments.Header(TTypeCommentStyle.Region, 'TKunde', '', 0)[0]);
  Assert.AreEqual(0, Integer(Length(TTypeComments.Header(TTypeCommentStyle.Off, 'TKunde', '', 0))));
end;

procedure TTypeCommentsTests.FindsAllStyles;
var
  mFound: TTypeComment;
  mText: TArray<string>;
begin
  mText := Lines('implementation'#10'{ TKunde }'#10#10'procedure TKunde.A;'#10'begin'#10'end;');
  mFound := TTypeComments.Find(mText, 3, 5, 'TKunde');
  Assert.IsTrue(mFound.Found, 'Leerzeile dazwischen erlaubt');
  Assert.AreEqual(1, mFound.First);
  Assert.AreEqual(Ord(TTypeCommentStyle.Brace), Ord(mFound.Style));
  mText := Lines('//----------'#10'// TKunde'#10'//----------'#10'procedure TKunde.A;');
  mFound := TTypeComments.Find(mText, 3, 3, 'TKunde');
  Assert.AreEqual(Ord(TTypeCommentStyle.Line), Ord(mFound.Style));
  Assert.AreEqual(0, mFound.First);
  Assert.AreEqual(2, mFound.Last);
  mText := Lines('{ TKunde: Text }'#10'procedure TKunde.A;');
  Assert.AreEqual(Ord(TTypeCommentStyle.Summary), Ord(TTypeComments.Find(mText, 1, 1, 'TKunde').Style));
  mText := Lines('(* TKunde *)'#10'procedure TKunde.A;');
  Assert.IsTrue(TTypeComments.Find(mText, 1, 1, 'TKunde').Found);
  mText := Lines('{$REGION ''TKunde''}'#10'procedure TKunde.A;'#10'begin'#10'end;'#10'{$ENDREGION}');
  mFound := TTypeComments.Find(mText, 1, 3, 'TKunde');
  Assert.AreEqual(Ord(TTypeCommentStyle.Region), Ord(mFound.Style));
  Assert.AreEqual(4, mFound.RegionEnd);
  Assert.IsTrue(mFound.Covers(4));
  Assert.IsFalse(mFound.Covers(2));
end;

procedure TTypeCommentsTests.IgnoresOtherComments;
var
  mText: TArray<string>;
begin
  mText := Lines('{ TKundeX }'#10'procedure TKunde.A;');
  Assert.IsFalse(TTypeComments.Find(mText, 1, 1, 'TKunde').Found);
  mText := Lines('{$DEFINE TKunde}'#10'procedure TKunde.A;');
  Assert.IsFalse(TTypeComments.Find(mText, 1, 1, 'TKunde').Found, 'Direktive');
  mText := Lines('{$REGION ''TKunde''}'#10'procedure TKunde.A;'#10'end;'#10'procedure X;');
  Assert.IsFalse(TTypeComments.Find(mText, 1, 2, 'TKunde').Found, 'Region ohne Ende hinter den Rümpfen');
end;

procedure TTypeCommentsTests.ReadsSummary;
var
  mText: TArray<string>;
begin
  mText := Lines('type'#10'  /// <summary>Kunde mit Adresse.</summary>'#10'  TKunde = class');
  Assert.AreEqual('Kunde mit Adresse.', TTypeComments.SummaryAbove(mText, 2));
  mText := Lines('type'#10'  /// <summary>'#10'  /// Kunde mit Adresse.'#10'  /// </summary>'#10'  TKunde = class');
  Assert.AreEqual('Kunde mit Adresse.', TTypeComments.SummaryAbove(mText, 4), 'Text in der nächsten Zeile');
  Assert.AreEqual('', TTypeComments.SummaryAbove(Lines('type'#10'  TKunde = class'), 1));
end;

procedure TTypeCommentsTests.RenamesHeaderLine;
var
  mLine: string;
begin
  Assert.IsTrue(TTypeComments.Renamed('{ TKunde }', 'TKunde', 'TCustomer', mLine));
  Assert.AreEqual('{ TCustomer }', mLine);
  Assert.IsTrue(TTypeComments.Renamed('{$REGION ''TKunde''}', 'tkunde', 'TCustomer', mLine));
  Assert.AreEqual('{$REGION ''TCustomer''}', mLine);
  Assert.IsFalse(TTypeComments.Renamed('// TKunde ist gemeint', 'TKunde', 'TCustomer', mLine));
  Assert.AreEqual('// TKunde ist gemeint', mLine);
end;

procedure TTypeCommentsTests.NameSpotsOverBodies;
var
  mSpots: TArray<TTypeNameSpot>;
begin
  mSpots := TTypeComments.NameSpots(Lines(
    '{ TKunde }'#10 +              // 0
    #10 +                          // 1
    'procedure TKunde.A;'#10 +     // 2
    '// TKunde'#10 +               // 3
    'procedure Frei;'#10 +         // 4
    '{$REGION ''TKunde''}'#10 +    // 5
    '/// Doku'#10 +                // 6
    'class function TKunde.B: Integer;'#10 + // 7
    '  { TKunde: Text }'#10 +      // 8
    'constructor TKunde.Create;'), 'TKunde');
  Assert.AreEqual(3, Integer(Length(mSpots)));
  Assert.AreEqual(0, mSpots[0].Line);
  Assert.AreEqual(2, mSpots[0].Character);
  Assert.AreEqual(5, mSpots[1].Line);
  Assert.AreEqual(10, mSpots[1].Character);
  Assert.AreEqual(8, mSpots[2].Line);
  Assert.AreEqual(4, mSpots[2].Character);
end;

procedure TTypeCommentsTests.NameSpotsOfNestedType;
var
  mText: TArray<string>;
  mSpots: TArray<TTypeNameSpot>;
begin
  mText := Lines('{ TAussen.TInnen }'#10'procedure TAussen.TInnen.Lauf;'#10'{ TAussen }'#10 +
    'procedure TAussen.Machen;'#10'{ TListe<T> }'#10'procedure TListe<T>.Add;');
  mSpots := TTypeComments.NameSpots(mText, 'TInnen');
  Assert.AreEqual(1, Integer(Length(mSpots)));
  Assert.AreEqual(10, mSpots[0].Character, 'innerer Typ hinter dem Punkt');
  mSpots := TTypeComments.NameSpots(mText, 'TAussen');
  Assert.AreEqual(2, Integer(Length(mSpots)), 'äußerer Typ in beiden Kommentaren');
  Assert.AreEqual(2, mSpots[0].Character);
  Assert.AreEqual(2, mSpots[1].Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeCommentsTests);

end.
