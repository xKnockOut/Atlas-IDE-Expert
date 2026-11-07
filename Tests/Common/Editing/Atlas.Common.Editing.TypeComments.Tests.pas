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
  Style: TTypeCommentStyle;
begin
  for Style := Low(TTypeCommentStyle) to High(TTypeCommentStyle) do
  begin
    Assert.AreEqual(Ord(Style), Ord(TTypeComments.StyleOf(TTypeComments.StyleName(Style))));
  end;
  Assert.AreEqual(Ord(TTypeCommentStyle.Brace), Ord(TTypeComments.StyleOf('')), 'Vorgabe wie die IDE');
  Assert.AreEqual(Ord(TTypeCommentStyle.Brace), Ord(TTypeComments.StyleOf('kasten')));
end;

procedure TTypeCommentsTests.WritesAllStyles;
var
  Header: TArray<string>;
begin
  Assert.AreEqual('{ TKunde }', TTypeComments.Header(TTypeCommentStyle.Brace, 'TKunde', '', 0)[0]);
  Header := TTypeComments.Header(TTypeCommentStyle.Line, 'TKunde', '', 40);
  Assert.AreEqual(3, Integer(Length(Header)));
  Assert.AreEqual(40, Integer(Length(Header[0])), 'Breite nach maxLineLength');
  Assert.AreEqual('// TKunde', Header[1]);
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
  Found: TTypeComment;
  Text: TArray<string>;
begin
  Text := Lines('implementation'#10'{ TKunde }'#10#10'procedure TKunde.A;'#10'begin'#10'end;');
  Found := TTypeComments.Find(Text, 3, 5, 'TKunde');
  Assert.IsTrue(Found.Found, 'Leerzeile dazwischen erlaubt');
  Assert.AreEqual(1, Found.First);
  Assert.AreEqual(Ord(TTypeCommentStyle.Brace), Ord(Found.Style));
  Text := Lines('//----------'#10'// TKunde'#10'//----------'#10'procedure TKunde.A;');
  Found := TTypeComments.Find(Text, 3, 3, 'TKunde');
  Assert.AreEqual(Ord(TTypeCommentStyle.Line), Ord(Found.Style));
  Assert.AreEqual(0, Found.First);
  Assert.AreEqual(2, Found.Last);
  Text := Lines('{ TKunde: Text }'#10'procedure TKunde.A;');
  Assert.AreEqual(Ord(TTypeCommentStyle.Summary), Ord(TTypeComments.Find(Text, 1, 1, 'TKunde').Style));
  Text := Lines('(* TKunde *)'#10'procedure TKunde.A;');
  Assert.IsTrue(TTypeComments.Find(Text, 1, 1, 'TKunde').Found);
  Text := Lines('{$REGION ''TKunde''}'#10'procedure TKunde.A;'#10'begin'#10'end;'#10'{$ENDREGION}');
  Found := TTypeComments.Find(Text, 1, 3, 'TKunde');
  Assert.AreEqual(Ord(TTypeCommentStyle.Region), Ord(Found.Style));
  Assert.AreEqual(4, Found.RegionEnd);
  Assert.IsTrue(Found.Covers(4));
  Assert.IsFalse(Found.Covers(2));
end;

procedure TTypeCommentsTests.IgnoresOtherComments;
var
  Text: TArray<string>;
begin
  Text := Lines('{ TKundeX }'#10'procedure TKunde.A;');
  Assert.IsFalse(TTypeComments.Find(Text, 1, 1, 'TKunde').Found);
  Text := Lines('{$DEFINE TKunde}'#10'procedure TKunde.A;');
  Assert.IsFalse(TTypeComments.Find(Text, 1, 1, 'TKunde').Found, 'Direktive');
  Text := Lines('{$REGION ''TKunde''}'#10'procedure TKunde.A;'#10'end;'#10'procedure X;');
  Assert.IsFalse(TTypeComments.Find(Text, 1, 2, 'TKunde').Found, 'Region ohne Ende hinter den Rümpfen');
end;

procedure TTypeCommentsTests.ReadsSummary;
var
  Text: TArray<string>;
begin
  Text := Lines('type'#10'  /// <summary>Kunde mit Adresse.</summary>'#10'  TKunde = class');
  Assert.AreEqual('Kunde mit Adresse.', TTypeComments.SummaryAbove(Text, 2));
  Text := Lines('type'#10'  /// <summary>'#10'  /// Kunde mit Adresse.'#10'  /// </summary>'#10'  TKunde = class');
  Assert.AreEqual('Kunde mit Adresse.', TTypeComments.SummaryAbove(Text, 4), 'Text in der nächsten Zeile');
  Assert.AreEqual('', TTypeComments.SummaryAbove(Lines('type'#10'  TKunde = class'), 1));
end;

procedure TTypeCommentsTests.RenamesHeaderLine;
var
  Line: string;
begin
  Assert.IsTrue(TTypeComments.Renamed('{ TKunde }', 'TKunde', 'TCustomer', Line));
  Assert.AreEqual('{ TCustomer }', Line);
  Assert.IsTrue(TTypeComments.Renamed('{$REGION ''TKunde''}', 'tkunde', 'TCustomer', Line));
  Assert.AreEqual('{$REGION ''TCustomer''}', Line);
  Assert.IsFalse(TTypeComments.Renamed('// TKunde ist gemeint', 'TKunde', 'TCustomer', Line));
  Assert.AreEqual('// TKunde ist gemeint', Line);
end;

procedure TTypeCommentsTests.NameSpotsOverBodies;
var
  Spots: TArray<TTypeNameSpot>;
begin
  Spots := TTypeComments.NameSpots(Lines(
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
  Assert.AreEqual(3, Integer(Length(Spots)));
  Assert.AreEqual(0, Spots[0].Line);
  Assert.AreEqual(2, Spots[0].Character);
  Assert.AreEqual(5, Spots[1].Line);
  Assert.AreEqual(10, Spots[1].Character);
  Assert.AreEqual(8, Spots[2].Line);
  Assert.AreEqual(4, Spots[2].Character);
end;

procedure TTypeCommentsTests.NameSpotsOfNestedType;
var
  Text: TArray<string>;
  Spots: TArray<TTypeNameSpot>;
begin
  Text := Lines('{ TAussen.TInnen }'#10'procedure TAussen.TInnen.Lauf;'#10'{ TAussen }'#10 +
    'procedure TAussen.Machen;'#10'{ TListe<T> }'#10'procedure TListe<T>.Add;');
  Spots := TTypeComments.NameSpots(Text, 'TInnen');
  Assert.AreEqual(1, Integer(Length(Spots)));
  Assert.AreEqual(10, Spots[0].Character, 'innerer Typ hinter dem Punkt');
  Spots := TTypeComments.NameSpots(Text, 'TAussen');
  Assert.AreEqual(2, Integer(Length(Spots)), 'äußerer Typ in beiden Kommentaren');
  Assert.AreEqual(2, Spots[0].Character);
  Assert.AreEqual(2, Spots[1].Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeCommentsTests);

end.
