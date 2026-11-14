unit Atlas.Core.Lsp.TextChanges.Tests;

// Tests der Textänderungen für didChange.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspTextChangesTests = class
  public
    [Test]
    procedure RangeCoversOnlyTheDifference;
    [Test]
    procedure NeverSplitsLineBreaksOrSurrogates;
    [Test]
    procedure AppliedChangeGivesNewText;
    /// <summary>Wie beim Server (TLineTable): ein Index zwischen CR und LF zählt zum Zeilenende.</summary>
    [Test]
    procedure PositionOfInsideCrlf;
    /// <summary>Positionen und Offsets passen für CRLF, LF und CR zueinander.</summary>
    [Test]
    procedure PositionAndOffsetAgree;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges;

{ TLspTextChangesTests }

function Applied(const AOld: string; const AChange: TLspTextChange): string;
var
  mStartOffset, mEndOffset: Integer;
begin
  mStartOffset := TLspTextChanges.OffsetOf(AOld, AChange.StartPos);
  mEndOffset := TLspTextChanges.OffsetOf(AOld, AChange.EndPos);
  Result := Copy(AOld, 1, mStartOffset) + AChange.Text + Copy(AOld, mEndOffset + 1, MaxInt);
end;
function RangeText(const AChange: TLspTextChange): string;
begin
  Result := Format('%d:%d-%d:%d "%s"', [AChange.StartPos.Line, AChange.StartPos.Character, AChange.EndPos.Line,
    AChange.EndPos.Character, AChange.Text]);
end;
procedure TLspTextChangesTests.RangeCoversOnlyTheDifference;
begin
  Assert.AreEqual('0:5-0:5 "X"', RangeText(TLspTextChanges.Between('unit A;', 'unit XA;')));
  Assert.AreEqual('1:1-1:2 ""', RangeText(TLspTextChanges.Between('a'#13#10'bcd', 'a'#13#10'bd')));
  Assert.AreEqual('0:0-0:0 "x"', RangeText(TLspTextChanges.Between('', 'x')));
  Assert.AreEqual('0:3-0:3 ""', RangeText(TLspTextChanges.Between('abc', 'abc')));
  // Lone CR und LF zählen wie beim Server als Zeilenende.
  Assert.AreEqual('2:0-2:1 "Y"', RangeText(TLspTextChanges.Between('a'#13'b'#10'X', 'a'#13'b'#10'Y')));
end;
procedure TLspTextChangesTests.NeverSplitsLineBreaksOrSurrogates;
var
  mChange: TLspTextChange;
begin
  // CR bleibt gleich, LF wird zu "X"#10: Der Bereich darf nicht zwischen CR und LF beginnen.
  mChange := TLspTextChanges.Between('a'#13#10'b', 'a'#13'X'#10'b');
  Assert.AreEqual('0:1-1:0 "'#13'X'#10'"', RangeText(mChange));
  // Vor dem gleichen Ende "\n..." steht im alten Text CR: das LF gehört in den Bereich.
  mChange := TLspTextChanges.Between('a'#13#10'b', 'aZ'#10'b');
  Assert.AreEqual('aZ'#10'b', Applied('a'#13#10'b', mChange));
  Assert.AreEqual(0, mChange.StartPos.Line);
  Assert.AreEqual(1, mChange.EndPos.Line);
  // Zwei Emojis mit gleichem hohem Surrogat: nicht in der Mitte eines Paars trennen.
  mChange := TLspTextChanges.Between('x'#$D83D#$DE00, 'x'#$D83D#$DE01);
  Assert.AreEqual('0:1-0:3 "'#$D83D#$DE01'"', RangeText(mChange));
end;
procedure TLspTextChangesTests.AppliedChangeGivesNewText;
const
  cAlphabet = 'ab'#13#10'x';
var
  mRound, mIndex: Integer;
  mOld, mNew_: string;

  function RandomText(ALength: Integer): string;
  var
    mPosition: Integer;
  begin
    Result := '';
    for mPosition := 1 to ALength do
    begin
      Result := Result + cAlphabet[Random(Length(cAlphabet)) + 1];
    end;
  end;

begin
  RandSeed := 395;
  for mRound := 1 to 5000 do
  begin
    mOld := RandomText(Random(12));
    mIndex := Random(Length(mOld) + 1);
    mNew_ := Copy(mOld, 1, mIndex) + RandomText(Random(4)) + Copy(mOld, mIndex + Random(3) + 1, MaxInt);
    Assert.AreEqual(mNew_, Applied(mOld, TLspTextChanges.Between(mOld, mNew_)), Format('%d: "%s" -> "%s"', [mRound, mOld, mNew_]));
  end;
end;
procedure TLspTextChangesTests.PositionOfInsideCrlf;
var
  mPosition: TLspTextPosition;
begin
  mPosition := TLspTextChanges.PositionOf('ab'#13#10'c', 3);
  Assert.AreEqual('0:2', Format('%d:%d', [mPosition.Line, mPosition.Character]));
  mPosition := TLspTextChanges.PositionOf('ab'#13#10'c', 4);
  Assert.AreEqual('1:0', Format('%d:%d', [mPosition.Line, mPosition.Character]));
  Assert.AreEqual(5, TLspTextChanges.OffsetOf('ab'#13#10'c', TLspTextPosition.Create(7, 0)),
    'hinter der letzten Zeile');
end;
procedure TLspTextChangesTests.PositionAndOffsetAgree;
const
  cText = 'a'#13#10'bc'#10'd'#13'e';
var
  mOffset: Integer;
begin
  // lsp-ignore: loop-off-by-one -- Offsets zwischen den Zeichen; Text[Offset] nur ab 1
  for mOffset := 0 to Length(cText) do
  begin
    if (mOffset = 0) or (cText[mOffset] <> #13) or (mOffset = Length(cText)) or (cText[mOffset + 1] <> #10) then
    begin
      Assert.AreEqual(mOffset, TLspTextChanges.OffsetOf(cText, TLspTextChanges.PositionOf(cText, mOffset)),
        IntToStr(mOffset));
    end;
  end;
  Assert.AreEqual(3, TLspTextChanges.OffsetOf(cText, TLspTextPosition.Create(1, 0)));
  Assert.AreEqual(7, TLspTextChanges.OffsetOf(cText, TLspTextPosition.Create(2, 9)), 'geklemmt auf das Zeilenende');
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTextChangesTests);

end.
