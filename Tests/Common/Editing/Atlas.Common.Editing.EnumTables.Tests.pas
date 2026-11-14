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
  cStates: array[0..2] of string = ('osNew', 'osPaid', 'osPaymentDue');

function Names: TArray<string>;
begin
  Result := TArray<string>.Create(cStates[0], cStates[1], cStates[2]);
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := mTree.Diagnostics = nil;
  finally
    mTree.Free;
  end;
end;

function Created(const ASource, AName: string; APlacement: TEnumTablePlacement; AResource: Boolean): string;
var
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
  mReason: string;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    Assert.IsTrue(TEnumTables.CreateTable(ASource, mTree, TTextPosition.Create(3, 4),
      TEnumTableRequest.Create(AName, APlacement, AResource), mEdits, mReason), mReason);
    Result := TChangeSignature.ApplyEdits(ASource, mEdits);
  finally
    mTree.Free;
  end;
end;

/// <summary>Repariert die erste Tabelle von ASource.</summary>
function Repaired(const ASource: string; const AValues: TEnumTableValues; out ARepair: TEnumTableRepair): string;
var
  mTree: TSyntaxTree;
  mTables: TArray<TEnumTable>;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    mTables := TEnumTables.Tables(mTree);
    Assert.IsTrue(Length(mTables) > 0);
    Assert.IsTrue(TEnumTables.Repair(ASource, mTree, mTables[0].Value, Names, AValues, ARepair));
    Result := TChangeSignature.ApplyEdits(ASource, ARepair.Edits);
  finally
    mTree.Free;
  end;
end;

const
  cUnit_ =
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
  mText: string;
begin
  mText := Created(cUnit_, 'COrderStateNames', TEnumTablePlacement.AfterType, False);
  Assert.IsTrue(Pos('  TOrderState = (osNew, osPaid, osPaymentDue);'#10#10'const'#10 +
    '  COrderStateNames: array[TOrderState] of string = (''New'', ''Paid'', ''Payment due'');'#10#10'type'#10 +
    '  TOther = class', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TEnumTablesTests.CreateInImplementation;
var
  mText: string;
begin
  mText := Created(cUnit_, 'CNames', TEnumTablePlacement.InImplementation, False);
  Assert.IsTrue(Pos('uses System.SysUtils;'#10#10'const'#10'  CNames: array[TOrderState] of string', mText) > 0,
    mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TEnumTablesTests.CreateWithResourceStrings;
var
  mText: string;
begin
  mText := Created(cUnit_, 'COrderStateNames', TEnumTablePlacement.InImplementation, True);
  Assert.IsTrue(Pos('resourcestring'#10'  SOrderStateNew = ''New'';'#10'  SOrderStatePaid = ''Paid'';', mText) > 0,
    mText);
  // Zu lang für eine Zeile: je Eintrag eine.
  Assert.IsTrue(Pos('array[TOrderState] of PResStringRec = ('#10'    @SOrderStateNew,'#10'    @SOrderStatePaid,'#10 +
    '    @SOrderStatePaymentDue);', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TEnumTablesTests.CreateRefusesFixedValuesAndTakenName;
const
  cFixed = 'unit U;'#10'interface'#10'type'#10'  TCode = (cA = 1, cB = 5);'#10'implementation'#10'end.'#10;
var
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
  mReason: string;
begin
  mTree := TPascalParser.Parse(cFixed);
  try
    Assert.IsFalse(TEnumTables.CreateTable(cFixed, mTree, TTextPosition.Create(3, 4),
      TEnumTableRequest.Create('CNames', TEnumTablePlacement.AfterType, False), mEdits, mReason));
    Assert.IsTrue(Pos('festen Werten', mReason) > 0, mReason);
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(cUnit_);
  try
    Assert.IsFalse(TEnumTables.CreateTable(cUnit_, mTree, TTextPosition.Create(3, 4),
      TEnumTableRequest.Create('TOther', TEnumTablePlacement.AfterType, False), mEdits, mReason));
    Assert.IsTrue(Pos('schon vergeben', mReason) > 0, mReason);
    Assert.IsFalse(TEnumTables.CreateTable(cUnit_, mTree, TTextPosition.Create(3, 4),
      TEnumTableRequest.Create('begin', TEnumTablePlacement.AfterType, False), mEdits, mReason));
  finally
    mTree.Free;
  end;
end;

procedure TEnumTablesTests.TablesAreFound;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TOrderState = (osNew, osPaid, osPaymentDue);'#10 +
    'const'#10'  A: array[TOrderState] of string = (''New'', ''Paid'', ''Payment due'');'#10 +
    '  B: array[0..2] of Integer = (1, 2, 3);'#10'var'#10'  C: array[TOrderState] of Integer = (1, 2, 3);'#10 +
    'implementation'#10'end.'#10;
var
  mTree: TSyntaxTree;
  mTables: TArray<TEnumTable>;
  mTable: TEnumTable;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mTables := TEnumTables.Tables(mTree);
    Assert.AreEqual(2, Integer(Length(mTables)));
    Assert.AreEqual('A', mTables[0].Decl.Name);
    Assert.AreEqual('TOrderState', mTables[1].IndexType.Name);
    Assert.IsTrue(TEnumTables.TableAt(mTree, TTextPosition.Create(5, 40), mTable));
    Assert.AreEqual('A', mTable.Decl.Name);
    Assert.IsFalse(TEnumTables.TableAt(mTree, TTextPosition.Create(6, 10), mTable));
    Assert.AreEqual<TEnumTableElement>(TEnumTableElement.Text, TEnumTables.ElementOf('String'));
    Assert.AreEqual<TEnumTableElement>(TEnumTableElement.Number, TEnumTables.ElementOf('Integer'));
    Assert.AreEqual<TEnumTableElement>(TEnumTableElement.Other, TEnumTables.ElementOf('TKunde'));
  finally
    mTree.Free;
  end;
end;

procedure TEnumTablesTests.RepairInsertsAtTextPosition;
const
  cSource = 'const'#10'  A: array[TOrderState] of string = (''New'', ''Payment due'');'#10;
var
  mRepair: TEnumTableRepair;
  mText: string;
begin
  mText := Repaired(cSource, TEnumTableValues.Create(TEnumTableElement.Text, 'string', 'TOrderState'), mRepair);
  Assert.IsTrue(Pos('(''New'', ''Paid'', ''Payment due'');', mText) > 0, mText);
  Assert.IsFalse(mRepair.Uncertain);
  Assert.AreEqual('Fehlenden Eintrag ergänzen (osPaid)', mRepair.Title);
end;

procedure TEnumTablesTests.RepairRemovesByComment;
const
  cSource = 'const'#10'  A: array[TOrderState] of Integer = ('#10 +
    '    1, // osNew'#10 +
    '    7, // osOld'#10 +
    '    2, // osPaid'#10 +
    '    3  // osPaymentDue'#10 +
    '  );'#10;
var
  mRepair: TEnumTableRepair;
  mText: string;
begin
  mText := Repaired(cSource, TEnumTableValues.Create(TEnumTableElement.Number, 'Integer', 'TOrderState'), mRepair);
  Assert.AreEqual('const'#10'  A: array[TOrderState] of Integer = ('#10'    1, // osNew'#10'    2, // osPaid'#10 +
    '    3  // osPaymentDue'#10'  );'#10, mText);
  Assert.AreEqual(1, Integer(Length(mRepair.Removed)));
  Assert.AreEqual('Überzähligen Eintrag entfernen (7)', mRepair.Title);
  Assert.IsFalse(mRepair.Uncertain);
end;

procedure TEnumTablesTests.RepairMultiLineInMiddleKeepsComments;
const
  cSource = 'const'#10'  A: array[TOrderState] of Boolean = ('#10 +
    '    True,  // osNew'#10 +
    '    False  // osPaymentDue'#10 +
    '  );'#10;
var
  mRepair: TEnumTableRepair;
  mText: string;
begin
  mText := Repaired(cSource, TEnumTableValues.Create(TEnumTableElement.Boolean_, 'Boolean', 'TOrderState'), mRepair);
  Assert.AreEqual('const'#10'  A: array[TOrderState] of Boolean = ('#10'    True,  // osNew'#10 +
    '    False {TODO osPaid}, // osPaid'#10'    False  // osPaymentDue'#10'  );'#10, mText);
  Assert.IsFalse(mRepair.Uncertain);
end;

procedure TEnumTablesTests.RepairMultiLineAtEndWithRecords;
const
  cSource = 'const'#10'  A: array[TOrderState] of TRec = ('#10 +
    '    (Name: ''New''; Code: 1),'#10 +
    '    (Name: ''Paid''; Code: 2)'#10 +
    '  );'#10;
var
  mRepair: TEnumTableRepair;
  mText: string;
begin
  mText := Repaired(cSource, TEnumTableValues.Create(TEnumTableElement.Other, 'TRec', 'TOrderState'), mRepair);
  Assert.AreEqual('const'#10'  A: array[TOrderState] of TRec = ('#10'    (Name: ''New''; Code: 1),'#10 +
    '    (Name: ''Paid''; Code: 2),'#10'    (Name: ''Paid''; Code: 2) {TODO osPaymentDue}'#10'  );'#10, mText);
  Assert.IsFalse(mRepair.Uncertain);
end;

procedure TEnumTablesTests.RepairWithoutHintsIsUncertain;
const
  cSource = 'const'#10'  A: array[TOrderState] of Integer = (10, 20);'#10;
var
  mRepair: TEnumTableRepair;
  mText: string;
begin
  mText := Repaired(cSource, TEnumTableValues.Create(TEnumTableElement.Number, 'Integer', 'TOrderState'), mRepair);
  Assert.IsTrue(Pos('(10, 20, 0 {TODO osPaymentDue});', mText) > 0, mText);
  Assert.IsTrue(mRepair.Uncertain);
end;

procedure TEnumTablesTests.RepairAddsResourceString;
const
  cSource = 'unit U;'#10'interface'#10'implementation'#10'resourcestring'#10'  SOrderStateNew = ''New'';'#10 +
    '  SOrderStatePaymentDue = ''Payment due'';'#10'const'#10 +
    '  A: array[TOrderState] of PResStringRec = (@SOrderStateNew, @SOrderStatePaymentDue);'#10'end.'#10;
var
  mRepair: TEnumTableRepair;
  mText: string;
begin
  mText := Repaired(cSource, TEnumTableValues.Create(TEnumTableElement.ResourceString_, 'PResStringRec',
    'TOrderState'), mRepair);
  Assert.IsTrue(Pos('  SOrderStateNew = ''New'';'#10'  SOrderStatePaid = ''Paid'';'#10, mText) > 0, mText);
  Assert.IsTrue(Pos('(@SOrderStateNew, @SOrderStatePaid, @SOrderStatePaymentDue);', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TEnumTablesTests.RepairNothingToDo;
const
  cSource = 'const'#10'  A: array[TOrderState] of string = (''Neu'', ''Bezahlt'', ''Faellig'');'#10;
var
  mTree: TSyntaxTree;
  mRepair: TEnumTableRepair;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsFalse(TEnumTables.Repair(cSource, mTree, TEnumTables.Tables(mTree)[0].Value, Names,
      TEnumTableValues.Create(TEnumTableElement.Text, 'string', 'TOrderState'), mRepair));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEnumTablesTests);

end.
