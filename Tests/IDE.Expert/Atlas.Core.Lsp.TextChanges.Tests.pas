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
  StartOffset, EndOffset: Integer;
begin
  StartOffset := TLspTextChanges.OffsetOf(AOld, AChange.StartPos);
  EndOffset := TLspTextChanges.OffsetOf(AOld, AChange.EndPos);
  Result := Copy(AOld, 1, StartOffset) + AChange.Text + Copy(AOld, EndOffset + 1, MaxInt);
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
  Change: TLspTextChange;
begin
  // CR bleibt gleich, LF wird zu "X"#10: Der Bereich darf nicht zwischen CR und LF beginnen.
  Change := TLspTextChanges.Between('a'#13#10'b', 'a'#13'X'#10'b');
  Assert.AreEqual('0:1-1:0 "'#13'X'#10'"', RangeText(Change));
  // Vor dem gleichen Ende "\n..." steht im alten Text CR: das LF gehört in den Bereich.
  Change := TLspTextChanges.Between('a'#13#10'b', 'aZ'#10'b');
  Assert.AreEqual('aZ'#10'b', Applied('a'#13#10'b', Change));
  Assert.AreEqual(0, Change.StartPos.Line);
  Assert.AreEqual(1, Change.EndPos.Line);
  // Zwei Emojis mit gleichem hohem Surrogat: nicht in der Mitte eines Paars trennen.
  Change := TLspTextChanges.Between('x'#$D83D#$DE00, 'x'#$D83D#$DE01);
  Assert.AreEqual('0:1-0:3 "'#$D83D#$DE01'"', RangeText(Change));
end;
procedure TLspTextChangesTests.AppliedChangeGivesNewText;
const
  Alphabet = 'ab'#13#10'x';
var
  Round, Index: Integer;
  Old, New_: string;

  function RandomText(ALength: Integer): string;
  var
    Position: Integer;
  begin
    Result := '';
    for Position := 1 to ALength do
    begin
      Result := Result + Alphabet[Random(Length(Alphabet)) + 1];
    end;
  end;

begin
  RandSeed := 395;
  for Round := 1 to 5000 do
  begin
    Old := RandomText(Random(12));
    Index := Random(Length(Old) + 1);
    New_ := Copy(Old, 1, Index) + RandomText(Random(4)) + Copy(Old, Index + Random(3) + 1, MaxInt);
    Assert.AreEqual(New_, Applied(Old, TLspTextChanges.Between(Old, New_)), Format('%d: "%s" -> "%s"', [Round, Old, New_]));
  end;
end;
procedure TLspTextChangesTests.PositionOfInsideCrlf;
var
  Position: TLspTextPosition;
begin
  Position := TLspTextChanges.PositionOf('ab'#13#10'c', 3);
  Assert.AreEqual('0:2', Format('%d:%d', [Position.Line, Position.Character]));
  Position := TLspTextChanges.PositionOf('ab'#13#10'c', 4);
  Assert.AreEqual('1:0', Format('%d:%d', [Position.Line, Position.Character]));
  Assert.AreEqual(5, TLspTextChanges.OffsetOf('ab'#13#10'c', TLspTextPosition.Create(7, 0)),
    'hinter der letzten Zeile');
end;
procedure TLspTextChangesTests.PositionAndOffsetAgree;
const
  Text = 'a'#13#10'bc'#10'd'#13'e';
var
  Offset: Integer;
begin
  for Offset := 0 to Length(Text) do // lsp-ignore: loop-off-by-one -- Offsets zwischen den Zeichen; Text[Offset] nur ab 1
  begin
    if (Offset = 0) or (Text[Offset] <> #13) or (Offset = Length(Text)) or (Text[Offset + 1] <> #10) then
    begin
      Assert.AreEqual(Offset, TLspTextChanges.OffsetOf(Text, TLspTextChanges.PositionOf(Text, Offset)),
        IntToStr(Offset));
    end;
  end;
  Assert.AreEqual(3, TLspTextChanges.OffsetOf(Text, TLspTextPosition.Create(1, 0)));
  Assert.AreEqual(7, TLspTextChanges.OffsetOf(Text, TLspTextPosition.Create(2, 9)), 'geklemmt auf das Zeilenende');
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTextChangesTests);

end.
