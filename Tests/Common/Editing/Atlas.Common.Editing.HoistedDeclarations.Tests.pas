unit Atlas.Common.Editing.HoistedDeclarations.Tests;

// Deklarationen zwischen Methodenrümpfen, die beim Ordnen mit nach vorn
// wandern müssen, weil ein vorrückender Rumpf sie braucht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THoistedDeclarationsTests = class
  public
    [Test]
    procedure NothingWithoutNeed;
    [Test]
    procedure NeededRoutineTakesCodeBefore;
    [Test]
    procedure LocalsAndTrailingCommentsStay;
    [Test]
    procedure HalfDirectiveHoistsNothing;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.HoistedDeclarations;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Split([#10]);
end;

function Span(AFirst, ALast: Integer): TBodySpan;
begin
  Result := TBodySpan.Create(AFirst, ALast);
end;

/// <summary>Gesetzte Zeilen als Liste "4,5,6"; '' ohne.</summary>
function MarkedText(const AMarks: TArray<Boolean>): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := 0 to High(AMarks) do
  begin
    if AMarks[mLine] then
    begin
      Result := Result + IntToStr(mLine) + ',';
    end;
  end;
end;

{ THoistedDeclarationsTests }

procedure THoistedDeclarationsTests.NothingWithoutNeed;
var
  mLines: TArray<string>;
  mSlots: TArray<TBodySpan>;
begin
  mLines := Lines('procedure T.A;'#10'begin'#10'end;'#10#10'procedure Hilfe;'#10'begin'#10'end;'#10#10 +
    'procedure T.B;'#10'begin'#10'end;');
  mSlots := TArray<TBodySpan>.Create(Span(0, 2), Span(8, 10));
  Assert.IsNull(THoistedDeclarations.LinesOf(mLines, mSlots, mSlots, TArray<Integer>.Create(1, 0)));
end;

// B rückt vom dritten auf den ersten Platz und braucht Hilfe; die Konstante davor wandert mit.
procedure THoistedDeclarationsTests.NeededRoutineTakesCodeBefore;
var
  mLines: TArray<string>;
  mSlots: TArray<TBodySpan>;
begin
  mLines := Lines('procedure T.C;'#10'begin'#10'end;'#10#10'const'#10'  cZahl = 2;'#10#10 +
    'procedure T.A;'#10'begin'#10'end;'#10#10'function Hilfe: Integer;'#10'begin'#10'  Result := cZahl;'#10 +
    'end;'#10#10'procedure T.B;'#10'begin'#10'  Hilfe;'#10'end;');
  mSlots := TArray<TBodySpan>.Create(Span(0, 2), Span(7, 9), Span(16, 19));
  Assert.AreEqual('4,5,6,11,12,13,14,15,', MarkedText(THoistedDeclarations.LinesOf(mLines, mSlots, mSlots,
    TArray<Integer>.Create(2, 1, 0))));
end;

// Lokale Variablen einer freien Routine zählen nicht; ein Kommentar am Ende gehört zum Rumpf dahinter.
procedure THoistedDeclarationsTests.LocalsAndTrailingCommentsStay;
var
  mLines: TArray<string>;
  mSlots: TArray<TBodySpan>;
begin
  mLines := Lines('procedure T.A;'#10'begin'#10'end;'#10#10'procedure Hilfe;'#10'var'#10'  mWert: Integer;'#10 +
    'begin'#10'end;'#10'// Zu B.'#10#10'procedure T.B;'#10'var'#10'  mWert: Integer;'#10'begin'#10 +
    '  mWert := 0;'#10'end;');
  mSlots := TArray<TBodySpan>.Create(Span(0, 2), Span(11, 16));
  Assert.IsNull(THoistedDeclarations.LinesOf(mLines, mSlots, mSlots, TArray<Integer>.Create(1, 0)));
  mLines[15] := '  Hilfe;';
  Assert.AreEqual('4,5,6,7,8,', MarkedText(THoistedDeclarations.LinesOf(mLines, mSlots, mSlots,
    TArray<Integer>.Create(1, 0))));
end;

procedure THoistedDeclarationsTests.HalfDirectiveHoistsNothing;
var
  mLines: TArray<string>;
  mSlots: TArray<TBodySpan>;
begin
  mLines := Lines('procedure T.A;'#10'begin'#10'end;'#10#10'{$IFDEF X}'#10'procedure Hilfe;'#10'begin'#10'end;'#10 +
    #10'procedure T.B;'#10'begin'#10'  Hilfe;'#10'end;'#10'{$ENDIF}');
  mSlots := TArray<TBodySpan>.Create(Span(0, 2), Span(9, 12));
  Assert.IsNull(THoistedDeclarations.LinesOf(mLines, mSlots, mSlots, TArray<Integer>.Create(1, 0)));
end;

end.
