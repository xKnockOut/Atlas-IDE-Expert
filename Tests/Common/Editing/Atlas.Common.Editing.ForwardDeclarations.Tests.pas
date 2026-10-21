unit Atlas.Common.Editing.ForwardDeclarations.Tests;

// Tests für Forward-Deklarationen im type-Abschnitt (#685): Erkennung,
// Forward ergänzen, Blöcke zusammenlegen, Record verschieben, überflüssige
// Forward-Deklaration.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TForwardDeclarationsTests = class
  public
    [Test]
    procedure ClassInSameBlockGetsForward;
    [Test]
    procedure InterfaceGetsInterfaceForward;
    [Test]
    procedure ParameterResultAndPropertyCount;
    [Test]
    procedure MutualClassesNeedOneForward;
    [Test]
    procedure PointerAncestorAndEarlierAreSilent;
    [Test]
    procedure ExistingForwardMovesUp;
    [Test]
    procedure DifferentBlocksAreMerged;
    [Test]
    procedure MergeNeedsConstBetween;
    [Test]
    procedure MergeBlockedByRoutine;
    [Test]
    procedure RecordMovesUp;
    [Test]
    procedure RecordMoveWouldOpenGap;
    [Test]
    procedure UnneededForwardIsRemoved;
    [Test]
    procedure NeededForwardIsSilent;
    [Test]
    procedure ConditionalIsSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ForwardDeclarations;

function Analyze(const AText: string): TArray<TForwardFinding>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TForwardDeclarations.Analyze(Tree, AText);
  finally
    Tree.Free;
  end;
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

/// <summary>Wendet die Edits (nicht überlappend, Zeilen mit #10) von hinten nach vorn an.</summary>
function Apply(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  Lines: TArray<string>;
  Offsets: TArray<Integer>;
  Order: TArray<Integer>;
  Index, Inner, Swap, Start, Stop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  begin
    Result := Offsets[APos.Line] + APos.Character;
  end;

begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  SetLength(Order, Length(AEdits));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  for Index := 0 to High(Order) do
    for Inner := Index + 1 to High(Order) do
      if OffsetOf(AEdits[Order[Index]].Range.StartPos) < OffsetOf(AEdits[Order[Inner]].Range.StartPos) then
      begin
        Swap := Order[Index];
        Order[Index] := Order[Inner];
        Order[Inner] := Swap;
      end;
  Result := AText;
  for Index in Order do
  begin
    Start := OffsetOf(AEdits[Index].Range.StartPos);
    Stop := OffsetOf(AEdits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start) + AEdits[Index].NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function UnitText(const AInterface: string): string;
begin
  Result := 'unit U;'#10'interface'#10 + AInterface + 'implementation'#10'end.';
end;

/// <summary>Einziger Treffer; nach seiner Korrektur parst die Unit fehlerfrei und hat keinen Treffer mehr.</summary>
function FixOnly(const AText: string; AFix: TForwardFix): string;
var
  Findings: TArray<TForwardFinding>;
begin
  Findings := Analyze(AText);
  Assert.AreEqual(1, Integer(Length(Findings)), AText);
  Assert.AreEqual(Ord(AFix), Ord(Findings[0].Fix), Findings[0].Reason);
  Result := Apply(AText, Findings[0].Edits);
  Assert.IsTrue(Parses(Result), Result);
  Assert.AreEqual(0, Integer(Length(Analyze(Result))), Result);
end;

procedure TForwardDeclarationsTests.ClassInSameBlockGetsForward;
var
  Findings: TArray<TForwardFinding>;
  Source: string;
begin
  Source := UnitText('type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10'  TNode = class'#10 +
    '    FTree: TTree;'#10'  end;'#10);
  Findings := Analyze(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Findings[0].Issue = TForwardIssue.UsedBeforeDeclaration);
  Assert.AreEqual('TNode', Findings[0].TypeName);
  Assert.AreEqual('TTree', Findings[0].UserName);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(UnitText('type'#10'  TNode = class;'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10 +
    '  TNode = class'#10'    FTree: TTree;'#10'  end;'#10), FixOnly(Source, TForwardFix.AddForward));
  Assert.AreEqual('Forward-Deklaration ergänzen', TForwardDeclarations.FixTitle(TForwardFix.AddForward));
end;

procedure TForwardDeclarationsTests.InterfaceGetsInterfaceForward;
begin
  Assert.AreEqual(UnitText('type'#10'  IKnoten = interface;'#10'  IBaum = interface'#10 +
    '    function Wurzel: IKnoten;'#10'  end;'#10'  IKnoten = interface'#10'  end;'#10),
    FixOnly(UnitText('type'#10'  IBaum = interface'#10'    function Wurzel: IKnoten;'#10'  end;'#10 +
    '  IKnoten = interface'#10'  end;'#10), TForwardFix.AddForward));
  // Generische Klasse: Forward-Deklaration mit Typparametern.
  Assert.AreEqual(UnitText('type'#10'  TKnoten<T> = class;'#10'  TBaum = class'#10'    FWurzel: TKnoten<Integer>;'#10 +
    '  end;'#10'  TKnoten<T> = class'#10'  end;'#10),
    FixOnly(UnitText('type'#10'  TBaum = class'#10'    FWurzel: TKnoten<Integer>;'#10'  end;'#10 +
    '  TKnoten<T> = class'#10'  end;'#10), TForwardFix.AddForward));
end;

procedure TForwardDeclarationsTests.ParameterResultAndPropertyCount;
var
  Findings: TArray<TForwardFinding>;
begin
  Findings := Analyze(UnitText('type'#10'  TTree = class'#10'    procedure Add(A: TNode);'#10 +
    '    function Find: TNode;'#10'    property Root: TNode read Find;'#10'    FList: TList<TNode>;'#10 +
    '  end;'#10'  TNode = class'#10'  end;'#10));
  Assert.AreEqual(4, Integer(Length(Findings)));
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(7, Findings[3].Range.StartPos.Line);
end;

procedure TForwardDeclarationsTests.MutualClassesNeedOneForward;
begin
  FixOnly(UnitText('type'#10'  TA = class'#10'    FB: TB;'#10'  end;'#10'  TB = class'#10'    FA: TA;'#10 +
    '  end;'#10), TForwardFix.AddForward);
end;

procedure TForwardDeclarationsTests.PointerAncestorAndEarlierAreSilent;
begin
  // Zeiger im selben Block, Vorfahr (braucht die volle Deklaration), Alias und Verwendung im implementation.
  Assert.AreEqual(0, Integer(Length(Analyze('unit U;'#10'interface'#10'type'#10'  PNode = ^TNode;'#10 +
    '  TFoo = class(TBar)'#10'  end;'#10'  TAlias = TBar;'#10'  TNode = record'#10'    Next: PNode;'#10 +
    '  end;'#10'  TBar = class'#10'  end;'#10'implementation'#10'type'#10'  TImpl = class'#10'    F: TNode;'#10 +
    '  end;'#10'end.'))));
  // Qualifiziert oder selbstbezüglich.
  Assert.AreEqual(0, Integer(Length(Analyze(UnitText('type'#10'  TFoo = class'#10'    F: System.TObject;'#10 +
    '    G: TFoo;'#10'  end;'#10)))));
end;

procedure TForwardDeclarationsTests.ExistingForwardMovesUp;
begin
  Assert.AreEqual(UnitText('type'#10'  TNode = class;'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10 +
    '  TNode = class'#10'  end;'#10),
    FixOnly(UnitText('type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10'  TNode = class;'#10 +
    '  TNode = class'#10'  end;'#10), TForwardFix.MoveForward));
end;

procedure TForwardDeclarationsTests.DifferentBlocksAreMerged;
begin
  Assert.AreEqual(UnitText('const'#10'  Max = 3;'#10'type'#10'  TNode = class;'#10'  TTree = class'#10 +
    '    FRoot: TNode;'#10'  end;'#10'  TNode = class'#10'    FTree: TTree;'#10'  end;'#10),
    FixOnly(UnitText('type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10'const'#10'  Max = 3;'#10 +
    'type'#10'  TNode = class'#10'    FTree: TTree;'#10'  end;'#10), TForwardFix.MergeBlocks));
end;

procedure TForwardDeclarationsTests.MergeNeedsConstBetween;
var
  Findings: TArray<TForwardFinding>;
begin
  // Der var-Abschnitt dazwischen braucht TTree und muss danach stehen.
  Findings := Analyze(UnitText('type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10'var'#10 +
    '  Baum: TTree;'#10'type'#10'  TNode = class'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TForwardFix.NoFix), Ord(Findings[0].Fix));
  Assert.Contains(Findings[0].Reason, 'var-Abschnitt');
  Assert.Contains(Findings[0].Reason, 'TTree');
  Assert.AreEqual(0, Integer(Length(Findings[0].Edits)));
  // Eine Konstante, die die Typen brauchen, steht danach weiter vorn und bleibt erreichbar.
  Findings := Analyze(UnitText('type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10'const'#10 +
    '  Max = 3;'#10'type'#10'  TNode = class'#10'    FItems: array[0..Max] of Integer;'#10'  end;'#10));
  Assert.AreEqual(Ord(TForwardFix.MergeBlocks), Ord(Findings[0].Fix), 'Max wandert vor den ersten Block');
end;

procedure TForwardDeclarationsTests.MergeBlockedByRoutine;
var
  Findings: TArray<TForwardFinding>;
begin
  Findings := Analyze('program P;'#10'type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10 +
    'procedure Lauf;'#10'begin'#10'end;'#10'type'#10'  TNode = class'#10'  end;'#10'begin'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TForwardFix.NoFix), Ord(Findings[0].Fix));
  Assert.Contains(Findings[0].Reason, 'const, var oder label');
end;

procedure TForwardDeclarationsTests.RecordMovesUp;
begin
  Assert.AreEqual(UnitText('type'#10'  TPunkt = record'#10'    X, Y: Integer;'#10'  end;'#10'  TLinie = class'#10 +
    '    FStart: TPunkt;'#10'  end;'#10),
    FixOnly(UnitText('type'#10'  TLinie = class'#10'    FStart: TPunkt;'#10'  end;'#10'  TPunkt = record'#10 +
    '    X, Y: Integer;'#10'  end;'#10), TForwardFix.MoveDeclaration));
  // Aus einem eigenen Block: der leere Block entfällt.
  Assert.AreEqual(UnitText('type'#10'  TFarbe = (Rot, Gruen);'#10'  TLampe = class'#10'    FFarbe: TFarbe;'#10 +
    '  end;'#10'const'#10'  Max = 3;'#10),
    FixOnly(UnitText('type'#10'  TLampe = class'#10'    FFarbe: TFarbe;'#10'  end;'#10'const'#10'  Max = 3;'#10 +
    'type'#10'  TFarbe = (Rot, Gruen);'#10), TForwardFix.MoveDeclaration));
end;

procedure TForwardDeclarationsTests.RecordMoveWouldOpenGap;
var
  Findings: TArray<TForwardFinding>;
begin
  Findings := Analyze(UnitText('type'#10'  TLinie = class'#10'    FStart: TPunkt;'#10'  end;'#10 +
    '  TWert = Integer;'#10'  TPunkt = record'#10'    X: TWert;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TForwardFix.NoFix), Ord(Findings[0].Fix));
  Assert.Contains(Findings[0].Reason, 'TWert');
end;

procedure TForwardDeclarationsTests.UnneededForwardIsRemoved;
var
  Findings: TArray<TForwardFinding>;
  Source: string;
begin
  Source := UnitText('type'#10'  TNode = class;'#10'  TTree = class'#10'  end;'#10'  TNode = class'#10'  end;'#10);
  Findings := Analyze(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Findings[0].Issue = TForwardIssue.UnneededForward);
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(UnitText('type'#10'  TTree = class'#10'  end;'#10'  TNode = class'#10'  end;'#10),
    Apply(Source, Findings[0].Edits));
  // In einer Zeile mit anderen Deklarationen: nur sie.
  Source := 'program P;'#10'procedure X;'#10'type TL = class; TL = class end;'#10'begin'#10'end;'#10'begin'#10'end.';
  Findings := Analyze(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('program P;'#10'procedure X;'#10'type TL = class end;'#10'begin'#10'end;'#10'begin'#10'end.',
    Apply(Source, Findings[0].Edits));
end;

procedure TForwardDeclarationsTests.NeededForwardIsSilent;
begin
  // Auch eine Verwendung nur über einen Zeiger braucht die Forward-Deklaration nicht; ein Feld schon.
  Assert.AreEqual(0, Integer(Length(Analyze(UnitText('type'#10'  TNode = class;'#10'  TTree = class'#10 +
    '    FRoot: TNode;'#10'  end;'#10'  TNode = class'#10'  end;'#10)))));
end;

procedure TForwardDeclarationsTests.ConditionalIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Analyze(UnitText('type'#10'  TTree = class'#10'{$IFDEF X}'#10 +
    '    FRoot: TNode;'#10'{$ENDIF}'#10'  end;'#10'  TNode = class'#10'  end;'#10)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TForwardDeclarationsTests);

end.
