unit Atlas.Common.Editing.Modernizer.Tests;

// Tests für die Modernisierungen hinter /modern (#303).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TModernizerTests = class
  public
    [Test]
    procedure ForLoopBecomesForIn;
    [Test]
    procedure ForLoopWithOtherIndexUseStays;
    [Test]
    procedure ForLoopWritingOrChangingListStays;
    [Test]
    procedure DeclarationBecomesInlineVar;
    [Test]
    procedure NestedFirstUseStays;
    [Test]
    procedure FreeAndNilJoined;
    [Test]
    procedure KindsCanBeSwitchedOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.Modernizer;

function Run(const AText: string; AKinds: TModernizations; out ACount: Integer): string;
var
  Lines: TArray<string>;
  Line: string;
  Start, Index: Integer;
begin
  Lines := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = #10) then
    begin
      Lines := Lines + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
  Result := '';
  for Line in TModernizer.Apply(Lines, AKinds, ACount) do
    Result := Result + Line + #10;
  // Wie die Eingabe: ohne angehängtes Zeilenende.
  Result := Copy(Result, 1, Length(Result) - 1);
end;

function All(const AText: string): string;
var
  Count: Integer;
begin
  Result := Run(AText, [TModernization.ForIn, TModernization.InlineVar, TModernization.FreeAndNilCall], Count);
end;

procedure TModernizerTests.ForLoopBecomesForIn;
begin
  Assert.AreEqual('procedure P(L: TStringList);'#10'begin'#10'  for var Item in L do'#10'    Log(Item);'#10'end;',
    All('procedure P(L: TStringList);'#10'var'#10'  I: Integer;'#10'begin'#10'  for I := 0 to L.Count - 1 do'#10 +
    '    Log(L[I]);'#10'end;'));
  Assert.AreEqual('procedure P;'#10'begin'#10'  for var Item in Werte do'#10'  begin'#10'    Summe(Item);'#10 +
    '  end;'#10'end;', All('procedure P;'#10'begin'#10'  for I := 0 to High(Werte) do'#10'  begin'#10 +
    '    Summe(Werte[I]);'#10'  end;'#10'end;'));
end;

procedure TModernizerTests.ForLoopWithOtherIndexUseStays;
const
  Source = 'procedure P(L: TStringList);'#10'var'#10'  I: Integer;'#10'begin'#10'  for I := 0 to L.Count - 1 do'#10 +
    '    Log(IntToStr(I) + L[I]);'#10'end;'#10;
begin
  Assert.AreEqual(Source, All(Source));
end;

procedure TModernizerTests.ForLoopWritingOrChangingListStays;
const
  Writing = 'procedure P;'#10'begin'#10'  for I := 0 to High(A) do'#10'    A[I] := 0;'#10'end;'#10;
  Changing = 'procedure P;'#10'begin'#10'  for I := 0 to L.Count - 1 do'#10'  begin'#10'    Log(L[I]);'#10 +
    '    L.Delete(0);'#10'  end;'#10'end;'#10;
begin
  Assert.AreEqual(Writing, All(Writing));
  Assert.AreEqual(Changing, All(Changing));
end;

procedure TModernizerTests.DeclarationBecomesInlineVar;
var
  Count: Integer;
begin
  Assert.AreEqual('procedure P;'#10'var'#10'  B: Integer;'#10'begin'#10'  var A: string := Name;'#10'  Log(A);'#10 +
    '  if X then'#10'    B := 1;'#10'end;', Run('procedure P;'#10'var'#10'  A: string;'#10'  B: Integer;'#10'begin'#10 +
    '  A := Name;'#10'  Log(A);'#10'  if X then'#10'    B := 1;'#10'end;', [TModernization.InlineVar], Count));
  Assert.AreEqual(1, Count);
end;

procedure TModernizerTests.NestedFirstUseStays;
const
  Source = 'procedure P;'#10'var'#10'  A: Integer;'#10'begin'#10'  Log(A);'#10'  A := 1;'#10'end;'#10;
  SelfUse = 'procedure P;'#10'var'#10'  A: Integer;'#10'begin'#10'  A := A + 1;'#10'end;'#10;
begin
  Assert.AreEqual(Source, All(Source));
  Assert.AreEqual(SelfUse, All(SelfUse));
end;

procedure TModernizerTests.FreeAndNilJoined;
begin
  Assert.AreEqual('procedure P;'#10'begin'#10'  FreeAndNil(FListe);'#10'end;',
    All('procedure P;'#10'begin'#10'  FListe.Free;'#10'  FListe := nil;'#10'end;'));
end;

procedure TModernizerTests.KindsCanBeSwitchedOff;
const
  Source = 'procedure P;'#10'var'#10'  A: string;'#10'begin'#10'  A := Name;'#10'  FListe.Free;'#10 +
    '  FListe := nil;'#10'end;'#10;
var
  Count: Integer;
  Text: string;
begin
  Assert.AreEqual(Source, Run(Source, [], Count));
  Assert.AreEqual(0, Count);
  Text := Run(Source, [TModernization.FreeAndNilCall], Count);
  Assert.Contains(Text, '  A := Name;'#10'  FreeAndNil(FListe);');
end;

initialization
  TDUnitX.RegisterTestFixture(TModernizerTests);

end.
