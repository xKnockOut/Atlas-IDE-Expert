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
  mLines: TArray<string>;
  mLine: string;
  mStart, mIndex: Integer;
begin
  mLines := nil;
  mStart := 1;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or (AText[mIndex] = #10) then
    begin
      mLines := mLines + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  Result := '';
  for mLine in TModernizer.Apply(mLines, AKinds, ACount) do
  begin
    Result := Result + mLine + #10;
  end;
  // Wie die Eingabe: ohne angehängtes Zeilenende.
  Result := Copy(Result, 1, Length(Result) - 1);
end;

function All(const AText: string): string;
var
  mCount: Integer;
begin
  Result := Run(AText, [TModernization.ForIn, TModernization.InlineVar, TModernization.FreeAndNilCall], mCount);
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
  cSource = 'procedure P(L: TStringList);'#10'var'#10'  I: Integer;'#10'begin'#10'  for I := 0 to L.Count - 1 do'#10 +
    '    Log(IntToStr(I) + L[I]);'#10'end;'#10;
begin
  Assert.AreEqual(cSource, All(cSource));
end;

procedure TModernizerTests.ForLoopWritingOrChangingListStays;
const
  cWriting = 'procedure P;'#10'begin'#10'  for I := 0 to High(A) do'#10'    A[I] := 0;'#10'end;'#10;
  cChanging = 'procedure P;'#10'begin'#10'  for I := 0 to L.Count - 1 do'#10'  begin'#10'    Log(L[I]);'#10 +
    '    L.Delete(0);'#10'  end;'#10'end;'#10;
begin
  Assert.AreEqual(cWriting, All(cWriting));
  Assert.AreEqual(cChanging, All(cChanging));
end;

procedure TModernizerTests.DeclarationBecomesInlineVar;
var
  mCount: Integer;
begin
  Assert.AreEqual('procedure P;'#10'var'#10'  B: Integer;'#10'begin'#10'  var A: string := Name;'#10'  Log(A);'#10 +
    '  if X then'#10'    B := 1;'#10'end;', Run('procedure P;'#10'var'#10'  A: string;'#10'  B: Integer;'#10'begin'#10 +
    '  A := Name;'#10'  Log(A);'#10'  if X then'#10'    B := 1;'#10'end;', [TModernization.InlineVar], mCount));
  Assert.AreEqual(1, mCount);
end;

procedure TModernizerTests.NestedFirstUseStays;
const
  cSource = 'procedure P;'#10'var'#10'  A: Integer;'#10'begin'#10'  Log(A);'#10'  A := 1;'#10'end;'#10;
  cSelfUse = 'procedure P;'#10'var'#10'  A: Integer;'#10'begin'#10'  A := A + 1;'#10'end;'#10;
begin
  Assert.AreEqual(cSource, All(cSource));
  Assert.AreEqual(cSelfUse, All(cSelfUse));
end;

procedure TModernizerTests.FreeAndNilJoined;
begin
  Assert.AreEqual('procedure P;'#10'begin'#10'  FreeAndNil(FListe);'#10'end;',
    All('procedure P;'#10'begin'#10'  FListe.Free;'#10'  FListe := nil;'#10'end;'));
end;

procedure TModernizerTests.KindsCanBeSwitchedOff;
const
  cSource = 'procedure P;'#10'var'#10'  A: string;'#10'begin'#10'  A := Name;'#10'  FListe.Free;'#10 +
    '  FListe := nil;'#10'end;'#10;
var
  mCount: Integer;
  mText: string;
begin
  Assert.AreEqual(cSource, Run(cSource, [], mCount));
  Assert.AreEqual(0, mCount);
  mText := Run(cSource, [TModernization.FreeAndNilCall], mCount);
  Assert.Contains(mText, '  A := Name;'#10'  FreeAndNil(FListe);');
end;

initialization
  TDUnitX.RegisterTestFixture(TModernizerTests);

end.
