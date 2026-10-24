unit Atlas.Common.Editing.EnumTables.Tests;

// Aufzählung mit Namenstabelle (#667): Präfix und Texte aus den Namen,
// Tabelle hinter dem Typ, im implementation-Teil und mit resourcestring,
// Ablehnung bei festen Werten und vergebenem Namen; Tabellen nachziehen an
// der richtigen Stelle über Texte, Kommentare und Bezeichner, ein- und
// mehrzeilig, Record-Elemente, geschätzte Stelle, resourcestring-Tabellen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEnumTablesTests = class
  public
    [Test]
    procedure PrefixAndDisplayText;
    [Test]
    procedure CreateAfterType;
    [Test]
    procedure CreateInImplementation;
    [Test]
    procedure CreateWithResourceStrings;
    [Test]
    procedure CreateRefusesFixedValuesAndTakenName;
    [Test]
    procedure TablesAreFound;
    [Test]
    procedure RepairInsertsAtTextPosition;
    [Test]
    procedure RepairRemovesByComment;
    [Test]
    procedure RepairMultiLineInMiddleKeepsComments;
    [Test]
    procedure RepairMultiLineAtEndWithRecords;
    [Test]
    procedure RepairWithoutHintsIsUncertain;
    [Test]
    procedure RepairAddsResourceString;
    [Test]
    procedure RepairNothingToDo;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.EnumTables;

const
  States: array[0..2] of string = ('osNew', 'osPaid', 'osPaymentDue');

function Names: TArray<string>;
begin
  Result := TArray<string>.Create(States[0], States[1], States[2]);
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Tree.Diagnostics = nil;
  finally
    Tree.Free;
  end;
end;

function Created(const ASource, AName: string; APlacement: TEnumTablePlacement; AResource: Boolean): string;
var
  Tree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
  Reason: string;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Assert.IsTrue(TEnumTables.CreateTable(ASource, Tree, TTextPosition.Create(3, 4), AName, APlacement, AResource,
      Edits, Reason), Reason);
    Result := TChangeSignature.ApplyEdits(ASource, Edits);
  finally
    Tree.Free;
  end;
end;

/// <summary>Repariert die erste Tabelle von ASource.</summary>
function Repaired(const ASource: string; const AValues: TEnumTableValues; out ARepair: TEnumTableRepair): string;
var
  Tree: TSyntaxTree;
  Tables: TArray<TEnumTable>;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Tables := TEnumTables.Tables(Tree);
    Assert.IsTrue(Length(Tables) > 0);
    Assert.IsTrue(TEnumTables.Repair(ASource, Tree, Tables[0].Value, Names, AValues, ARepair));
    Result := TChangeSignature.ApplyEdits(ASource, ARepair.Edits);
  finally
    Tree.Free;
  end;
end;

const
  Unit_ =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TOrderState = (osNew, osPaid, osPaymentDue);'#10 +
    '  TOther = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'uses System.SysUtils;'#10 +
    'end.'#10;

procedure TEnumTablesTests.PrefixAndDisplayText;
begin
  Assert.AreEqual('os', TEnumTables.CommonPrefix(Names));
  Assert.AreEqual('Payment due', TEnumTables.DisplayText('osPaymentDue', 'os'));
  Assert.AreEqual('HTTP error', TEnumTables.DisplayText('HTTPError', ''));
  Assert.AreEqual('Red', TEnumTables.DisplayText('red', ''));
  Assert.AreEqual('', TEnumTables.CommonPrefix(TArray<string>.Create('Red', 'Green')));
  Assert.AreEqual('', TEnumTables.CommonPrefix(TArray<string>.Create('open', 'other')));
  Assert.AreEqual('COrderStateNames', TEnumTables.TableName('TOrderState'));
  Assert.AreEqual('SOrderStatePaid', TEnumTables.ResourceName('TOrderState', 'osPaid', 'os'));
end;

procedure TEnumTablesTests.CreateAfterType;
var
  Text: string;
begin
  Text := Created(Unit_, 'COrderStateNames', TEnumTablePlacement.AfterType, False);
  Assert.IsTrue(Pos('  TOrderState = (osNew, osPaid, osPaymentDue);'#10#10'const'#10 +
    '  COrderStateNames: array[TOrderState] of string = (''New'', ''Paid'', ''Payment due'');'#10#10'type'#10 +
    '  TOther = class', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TEnumTablesTests.CreateInImplementation;
var
  Text: string;
begin
  Text := Created(Unit_, 'CNames', TEnumTablePlacement.InImplementation, False);
  Assert.IsTrue(Pos('uses System.SysUtils;'#10#10'const'#10'  CNames: array[TOrderState] of string', Text) > 0,
    Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TEnumTablesTests.CreateWithResourceStrings;
var
  Text: string;
begin
  Text := Created(Unit_, 'COrderStateNames', TEnumTablePlacement.InImplementation, True);
  Assert.IsTrue(Pos('resourcestring'#10'  SOrderStateNew = ''New'';'#10'  SOrderStatePaid = ''Paid'';', Text) > 0,
    Text);
  // Zu lang für eine Zeile: je Eintrag eine.
  Assert.IsTrue(Pos('array[TOrderState] of PResStringRec = ('#10'    @SOrderStateNew,'#10'    @SOrderStatePaid,'#10 +
    '    @SOrderStatePaymentDue);', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TEnumTablesTests.CreateRefusesFixedValuesAndTakenName;
const
  Fixed = 'unit U;'#10'interface'#10'type'#10'  TCode = (cA = 1, cB = 5);'#10'implementation'#10'end.'#10;
var
  Tree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
  Reason: string;
begin
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.IsFalse(TEnumTables.CreateTable(Fixed, Tree, TTextPosition.Create(3, 4), 'CNames',
      TEnumTablePlacement.AfterType, False, Edits, Reason));
    Assert.IsTrue(Pos('festen Werten', Reason) > 0, Reason);
  finally
    Tree.Free;
  end;
  Tree := TPascalParser.Parse(Unit_);
  try
    Assert.IsFalse(TEnumTables.CreateTable(Unit_, Tree, TTextPosition.Create(3, 4), 'TOther',
      TEnumTablePlacement.AfterType, False, Edits, Reason));
    Assert.IsTrue(Pos('schon vergeben', Reason) > 0, Reason);
    Assert.IsFalse(TEnumTables.CreateTable(Unit_, Tree, TTextPosition.Create(3, 4), 'begin',
      TEnumTablePlacement.AfterType, False, Edits, Reason));
  finally
    Tree.Free;
  end;
end;

procedure TEnumTablesTests.TablesAreFound;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TOrderState = (osNew, osPaid, osPaymentDue);'#10 +
    'const'#10'  A: array[TOrderState] of string = (''New'', ''Paid'', ''Payment due'');'#10 +
    '  B: array[0..2] of Integer = (1, 2, 3);'#10'var'#10'  C: array[TOrderState] of Integer = (1, 2, 3);'#10 +
    'implementation'#10'end.'#10;
var
  Tree: TSyntaxTree;
  Tables: TArray<TEnumTable>;
  Table: TEnumTable;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Tables := TEnumTables.Tables(Tree);
    Assert.AreEqual(2, Integer(Length(Tables)));
    Assert.AreEqual('A', Tables[0].Decl.Name);
    Assert.AreEqual('TOrderState', Tables[1].IndexType.Name);
    Assert.IsTrue(TEnumTables.TableAt(Tree, TTextPosition.Create(5, 40), Table));
    Assert.AreEqual('A', Table.Decl.Name);
    Assert.IsFalse(TEnumTables.TableAt(Tree, TTextPosition.Create(6, 10), Table));
    Assert.IsTrue(TEnumTables.ElementOf('String') = TEnumTableElement.Text);
    Assert.IsTrue(TEnumTables.ElementOf('Integer') = TEnumTableElement.Number);
    Assert.IsTrue(TEnumTables.ElementOf('TKunde') = TEnumTableElement.Other);
  finally
    Tree.Free;
  end;
end;

procedure TEnumTablesTests.RepairInsertsAtTextPosition;
const
  Source = 'const'#10'  A: array[TOrderState] of string = (''New'', ''Payment due'');'#10;
var
  Repair: TEnumTableRepair;
  Text: string;
begin
  Text := Repaired(Source, TEnumTableValues.Create(TEnumTableElement.Text, 'string', 'TOrderState'), Repair);
  Assert.IsTrue(Pos('(''New'', ''Paid'', ''Payment due'');', Text) > 0, Text);
  Assert.IsFalse(Repair.Uncertain);
  Assert.AreEqual('Fehlenden Eintrag ergänzen (osPaid)', Repair.Title);
end;

procedure TEnumTablesTests.RepairRemovesByComment;
const
  Source = 'const'#10'  A: array[TOrderState] of Integer = ('#10 +
    '    1, // osNew'#10 +
    '    7, // osOld'#10 +
    '    2, // osPaid'#10 +
    '    3  // osPaymentDue'#10 +
    '  );'#10;
var
  Repair: TEnumTableRepair;
  Text: string;
begin
  Text := Repaired(Source, TEnumTableValues.Create(TEnumTableElement.Number, 'Integer', 'TOrderState'), Repair);
  Assert.AreEqual('const'#10'  A: array[TOrderState] of Integer = ('#10'    1, // osNew'#10'    2, // osPaid'#10 +
    '    3  // osPaymentDue'#10'  );'#10, Text);
  Assert.AreEqual(1, Integer(Length(Repair.Removed)));
  Assert.AreEqual('Überzähligen Eintrag entfernen (7)', Repair.Title);
  Assert.IsFalse(Repair.Uncertain);
end;

procedure TEnumTablesTests.RepairMultiLineInMiddleKeepsComments;
const
  Source = 'const'#10'  A: array[TOrderState] of Boolean = ('#10 +
    '    True,  // osNew'#10 +
    '    False  // osPaymentDue'#10 +
    '  );'#10;
var
  Repair: TEnumTableRepair;
  Text: string;
begin
  Text := Repaired(Source, TEnumTableValues.Create(TEnumTableElement.Boolean_, 'Boolean', 'TOrderState'), Repair);
  Assert.AreEqual('const'#10'  A: array[TOrderState] of Boolean = ('#10'    True,  // osNew'#10 +
    '    False {TODO osPaid}, // osPaid'#10'    False  // osPaymentDue'#10'  );'#10, Text);
  Assert.IsFalse(Repair.Uncertain);
end;

procedure TEnumTablesTests.RepairMultiLineAtEndWithRecords;
const
  Source = 'const'#10'  A: array[TOrderState] of TRec = ('#10 +
    '    (Name: ''New''; Code: 1),'#10 +
    '    (Name: ''Paid''; Code: 2)'#10 +
    '  );'#10;
var
  Repair: TEnumTableRepair;
  Text: string;
begin
  Text := Repaired(Source, TEnumTableValues.Create(TEnumTableElement.Other, 'TRec', 'TOrderState'), Repair);
  Assert.AreEqual('const'#10'  A: array[TOrderState] of TRec = ('#10'    (Name: ''New''; Code: 1),'#10 +
    '    (Name: ''Paid''; Code: 2),'#10'    (Name: ''Paid''; Code: 2) {TODO osPaymentDue}'#10'  );'#10, Text);
  Assert.IsFalse(Repair.Uncertain);
end;

procedure TEnumTablesTests.RepairWithoutHintsIsUncertain;
const
  Source = 'const'#10'  A: array[TOrderState] of Integer = (10, 20);'#10;
var
  Repair: TEnumTableRepair;
  Text: string;
begin
  Text := Repaired(Source, TEnumTableValues.Create(TEnumTableElement.Number, 'Integer', 'TOrderState'), Repair);
  Assert.IsTrue(Pos('(10, 20, 0 {TODO osPaymentDue});', Text) > 0, Text);
  Assert.IsTrue(Repair.Uncertain);
end;

procedure TEnumTablesTests.RepairAddsResourceString;
const
  Source = 'unit U;'#10'interface'#10'implementation'#10'resourcestring'#10'  SOrderStateNew = ''New'';'#10 +
    '  SOrderStatePaymentDue = ''Payment due'';'#10'const'#10 +
    '  A: array[TOrderState] of PResStringRec = (@SOrderStateNew, @SOrderStatePaymentDue);'#10'end.'#10;
var
  Repair: TEnumTableRepair;
  Text: string;
begin
  Text := Repaired(Source, TEnumTableValues.Create(TEnumTableElement.ResourceString_, 'PResStringRec',
    'TOrderState'), Repair);
  Assert.IsTrue(Pos('  SOrderStateNew = ''New'';'#10'  SOrderStatePaid = ''Paid'';'#10, Text) > 0, Text);
  Assert.IsTrue(Pos('(@SOrderStateNew, @SOrderStatePaid, @SOrderStatePaymentDue);', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TEnumTablesTests.RepairNothingToDo;
const
  Source = 'const'#10'  A: array[TOrderState] of string = (''Neu'', ''Bezahlt'', ''Faellig'');'#10;
var
  Tree: TSyntaxTree;
  Repair: TEnumTableRepair;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsFalse(TEnumTables.Repair(Source, Tree, TEnumTables.Tables(Tree)[0].Value, Names,
      TEnumTableValues.Create(TEnumTableElement.Text, 'string', 'TOrderState'), Repair));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEnumTablesTests);

end.
