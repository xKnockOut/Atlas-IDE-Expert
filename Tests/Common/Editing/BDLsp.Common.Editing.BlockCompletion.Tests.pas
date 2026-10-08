unit BDLsp.Common.Editing.BlockCompletion.Tests;

// Tests für den Blockabschluss beim Tippen (#179).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBlockCompletionTests = class
  private
    /// <summary>"|" markiert den Cursor; liefert den Text nach dem Edit oder '' ohne Edit.</summary>
    function Enter(const AText: string): string;
  public
    [Test]
    procedure ClosesBegin;
    [Test]
    procedure KeepsIndentOfOpenerLine;
    [Test]
    procedure AddsFinallyAfterTry;
    [Test]
    procedure ClosesCaseRecordAndClass;
    [Test]
    procedure AddsUntilAfterRepeat;
    [Test]
    procedure SkipsClosedBlocks;
    [Test]
    procedure LessIndentedEndBelongsToOuterBlock;
    [Test]
    procedure UnitEndDoesNotCloseBlock;
    [Test]
    procedure SkipsForwardDeclarationsAndClassOf;
    [Test]
    procedure SkipsDisabledKinds;
    [Test]
    procedure KeepsCrLf;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Editing.BlockCompletion;

const
  AllKinds = [Low(TBlockKind)..High(TBlockKind)];

function ApplyAt(const AText: string; ALine, ACharacter: Integer; const AInsert: string): string;
var
  Lines: TArray<string>;
  Line: string;
begin
  Lines := AText.Split([#10]);
  Line := Lines[ALine];
  Insert(AInsert, Line, ACharacter + 1);
  Lines[ALine] := Line;
  Result := string.Join(#10, Lines);
end;

function RunEnter(const AText: string; AKinds: TBlockKinds): string;
var
  Text: string;
  Cursor, Line, Index: Integer;
  Edit: TRuleEdit;
begin
  Cursor := Pos('|', AText);
  Text := StringReplace(AText, '|', '', []);
  Line := 0;
  for Index := 1 to Cursor - 1 do
    if Text[Index] = #10 then
      Inc(Line);
  if TBlockCompletion.AfterEnter(Text, TPascalLexer.Tokenize(Text), TTextPosition.Create(Line, 0), AKinds, Edit) then
    Result := ApplyAt(Text, Edit.Range.StartPos.Line, Edit.Range.StartPos.Character, Edit.NewText)
  else
    Result := '';
end;

function TBlockCompletionTests.Enter(const AText: string): string;
begin
  Result := RunEnter(AText, AllKinds);
end;

procedure TBlockCompletionTests.ClosesBegin;
begin
  Assert.AreEqual('procedure A;'#10'begin'#10'  '#10'end;',
    Enter('procedure A;'#10'begin'#10'|  '));
end;

procedure TBlockCompletionTests.KeepsIndentOfOpenerLine;
begin
  Assert.AreEqual('begin'#10'  if X then begin'#10'    '#10'  end;'#10'end;',
    Enter('begin'#10'  if X then begin'#10'|    '#10'end;'));
end;

procedure TBlockCompletionTests.AddsFinallyAfterTry;
begin
  Assert.AreEqual('begin'#10'  try'#10#10'  finally'#10'  end;'#10'end;',
    Enter('begin'#10'  try'#10'|'#10'end;'));
end;

procedure TBlockCompletionTests.ClosesCaseRecordAndClass;
begin
  Assert.AreEqual('begin'#10'  case X of'#10#10'  end;'#10'end;', Enter('begin'#10'  case X of'#10'|'#10'end;'));
  Assert.AreEqual('type'#10'  TR = packed record'#10#10'  end;', Enter('type'#10'  TR = packed record'#10'|'));
  Assert.AreEqual('type'#10'  TFoo = class(TBasis)'#10#10'  end;', Enter('type'#10'  TFoo = class(TBasis)'#10'|'));
  Assert.AreEqual('type'#10'  IFoo = interface'#10#10'  end;', Enter('type'#10'  IFoo = interface'#10'|'));
end;

procedure TBlockCompletionTests.AddsUntilAfterRepeat;
begin
  Assert.AreEqual('begin'#10'  repeat'#10#10'  until ;'#10'end;', Enter('begin'#10'  repeat'#10'|'#10'end;'));
end;

procedure TBlockCompletionTests.SkipsClosedBlocks;
begin
  Assert.AreEqual('', Enter('procedure A;'#10'begin'#10'|'#10'end;'));
  Assert.AreEqual('', Enter('begin'#10'  repeat'#10'|'#10'  until X;'#10'end;'));
  Assert.AreEqual('', Enter('type'#10'  TR = record'#10'|'#10'    case Integer of'#10'      0: (A: Byte);'#10'  end;'));
  Assert.AreEqual('', Enter('program P;'#10'begin'#10'|'#10'end.'));
end;

procedure TBlockCompletionTests.LessIndentedEndBelongsToOuterBlock;
begin
  Assert.AreEqual('begin'#10'  if X then'#10'  begin'#10#10'  end;'#10'end;',
    Enter('begin'#10'  if X then'#10'  begin'#10'|'#10'end;'));
end;

procedure TBlockCompletionTests.UnitEndDoesNotCloseBlock;
begin
  Assert.AreEqual('implementation'#10'procedure A;'#10'begin'#10#10'end;'#10'end.',
    Enter('implementation'#10'procedure A;'#10'begin'#10'|'#10'end.'));
end;

procedure TBlockCompletionTests.SkipsForwardDeclarationsAndClassOf;
begin
  Assert.AreEqual('', Enter('type'#10'  TFoo = class;'#10'|'));
  Assert.AreEqual('', Enter('type'#10'  TFooClass = class of TFoo;'#10'|'));
  Assert.AreEqual('', Enter('unit A;'#10'interface'#10'|'));
  Assert.AreEqual('', Enter('begin'#10'  X := 1;'#10'|'));
  Assert.AreEqual('', Enter('begin'#10'|  X := 1;'));
end;

procedure TBlockCompletionTests.SkipsDisabledKinds;
begin
  Assert.AreEqual('', RunEnter('begin'#10'|', AllKinds - [TBlockKind.Begin_]));
  Assert.AreNotEqual('', RunEnter('begin'#10'  try'#10'|', AllKinds - [TBlockKind.Begin_]));
end;

procedure TBlockCompletionTests.KeepsCrLf;
var
  Edit: TRuleEdit;
  Text: string;
begin
  Text := 'begin'#13#10'  try'#13#10;
  Assert.IsTrue(TBlockCompletion.AfterEnter(Text, TPascalLexer.Tokenize(Text), TTextPosition.Create(2, 0),
    AllKinds, Edit));
  Assert.AreEqual(#13#10'  finally'#13#10'  end;', Edit.NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TBlockCompletionTests);

end.
