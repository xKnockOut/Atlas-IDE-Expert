unit Atlas.Core.Debug.DataBreakpoint.Tests;

// Anhalten, wenn sich ein Feld ändert (#584), Kern: Ausdruck unter dem
// Cursor, Ausdrücke für Adresse und Größe, Plan für einen Hardware-Platz
// (Länge, Ausrichtung, nur der erste Teil), freie Plätze und alter bzw. neuer
// Wert aus den Bytes.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TCoreDebugDataBreakpointTests = class
  public
    [Test]
    procedure ExpressionAtCursor;
    [Test]
    procedure ExpressionAtRejectsKeywords;
    [Test]
    procedure ExpressionsForDebugger;
    [Test]
    procedure ParsesSize;
    [Test]
    procedure MaxLengthByPointerSize;
    [Test]
    procedure PlanFitsWholeField;
    [Test]
    procedure PlanWatchesFirstPartOfLargeField;
    [Test]
    procedure PlanRespectsAlignment;
    [Test]
    procedure PlanWithoutAddressOrSize;
    [Test]
    procedure FreeSlotsNeverNegative;
    [Test]
    procedure ReadsLittleEndianIntegers;
    [Test]
    procedure KindFromDebuggerText;
    [Test]
    procedure ValueTextByKind;
    [Test]
    procedure ChangedComparesBytes;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.DataBreakpoint;

function Bytes(const AValues: array of Byte): TBytes;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    Result[mIndex] := AValues[mIndex];
  end;
end;

procedure TCoreDebugDataBreakpointTests.ExpressionAtCursor;
const
  cLine = '  FKunde.FSumme := 0; P^.X := 1;';
begin
  Assert.AreEqual('FKunde.FSumme', TAtlasDataBreakpoint.ExpressionAt(cLine, 12), 'im Feldnamen');
  Assert.AreEqual('FKunde', TAtlasDataBreakpoint.ExpressionAt(cLine, 4), 'im ersten Teil bis zum Wortende');
  Assert.AreEqual('FKunde.FSumme', TAtlasDataBreakpoint.ExpressionAt(cLine, 15), 'direkt hinter dem Wort');
  Assert.AreEqual('P^.X', TAtlasDataBreakpoint.ExpressionAt(cLine, 25));
  Assert.AreEqual('', TAtlasDataBreakpoint.ExpressionAt(cLine, 0), 'Einrückung');
  Assert.AreEqual('', TAtlasDataBreakpoint.ExpressionAt('', 0));
end;

procedure TCoreDebugDataBreakpointTests.ExpressionAtRejectsKeywords;
begin
  Assert.AreEqual('', TAtlasDataBreakpoint.ExpressionAt('  if Summe > 0 then', 3));
  Assert.AreEqual('', TAtlasDataBreakpoint.ExpressionAt('  begin', 4));
  Assert.AreEqual('', TAtlasDataBreakpoint.ExpressionAt('  X := nil;', 8));
  Assert.AreEqual('Summe', TAtlasDataBreakpoint.ExpressionAt('  if Summe > 0 then', 6));
end;

procedure TCoreDebugDataBreakpointTests.ExpressionsForDebugger;
begin
  Assert.AreEqual('Pointer(@FKunde.FSumme)', TAtlasDataBreakpoint.AddressExpression(' FKunde.FSumme '));
  Assert.AreEqual('SizeOf(FKunde.FSumme)', TAtlasDataBreakpoint.SizeExpression('FKunde.FSumme'));
  Assert.AreEqual('PString($0A3F1C20)^', TAtlasDataBreakpoint.TextExpression($0A3F1C20));
end;

procedure TCoreDebugDataBreakpointTests.ParsesSize;
var
  mSize: Integer;
begin
  Assert.IsTrue(TAtlasDataBreakpoint.TryParseSize(' 4 ', mSize));
  Assert.AreEqual(4, mSize);
  Assert.IsTrue(TAtlasDataBreakpoint.TryParseSize('$10', mSize));
  Assert.AreEqual(16, mSize);
  Assert.IsFalse(TAtlasDataBreakpoint.TryParseSize('0', mSize));
  Assert.IsFalse(TAtlasDataBreakpoint.TryParseSize('E2003 Undeclared identifier', mSize));
  Assert.AreEqual(0, mSize);
end;

procedure TCoreDebugDataBreakpointTests.MaxLengthByPointerSize;
begin
  Assert.AreEqual(4, TAtlasDataBreakpoint.MaxLength(4));
  Assert.AreEqual(8, TAtlasDataBreakpoint.MaxLength(8));
  Assert.AreEqual(4, TAtlasDataBreakpoint.MaxLength(0), 'unbekannt: vorsichtig');
end;

procedure TCoreDebugDataBreakpointTests.PlanFitsWholeField;
var
  mPlan: TAtlasDataWatchPlan;
begin
  mPlan := TAtlasDataBreakpoint.Plan($1000, 4, 4);
  Assert.AreEqual(4, mPlan.Length);
  Assert.IsFalse(mPlan.Partial);
  mPlan := TAtlasDataBreakpoint.Plan($1000, 8, 8);
  Assert.AreEqual(8, mPlan.Length, 'Int64 unter Win64');
  Assert.IsFalse(mPlan.Partial);
  mPlan := TAtlasDataBreakpoint.Plan($1001, 1, 8);
  Assert.AreEqual(1, mPlan.Length, 'Byte an ungerader Adresse');
  Assert.IsFalse(mPlan.Partial);
  mPlan := TAtlasDataBreakpoint.Plan($1002, 2, 4);
  Assert.AreEqual(2, mPlan.Length);
  Assert.IsFalse(mPlan.Partial);
end;

procedure TCoreDebugDataBreakpointTests.PlanWatchesFirstPartOfLargeField;
var
  mPlan: TAtlasDataWatchPlan;
begin
  mPlan := TAtlasDataBreakpoint.Plan($1000, 8, 4);
  Assert.AreEqual(4, mPlan.Length, 'Int64 unter Win32');
  Assert.IsTrue(mPlan.Partial);
  Assert.AreEqual(8, mPlan.Size);
  mPlan := TAtlasDataBreakpoint.Plan($2000, 24, 8);
  Assert.AreEqual(8, mPlan.Length, 'Record');
  Assert.IsTrue(mPlan.Partial);
  Assert.IsTrue(UInt64($2000) = mPlan.Address);
end;

procedure TCoreDebugDataBreakpointTests.PlanRespectsAlignment;
var
  mPlan: TAtlasDataWatchPlan;
begin
  mPlan := TAtlasDataBreakpoint.Plan($1002, 4, 4);
  Assert.AreEqual(2, mPlan.Length, 'Integer in gepacktem Record an Adresse mod 4 = 2');
  Assert.IsTrue(mPlan.Partial);
  mPlan := TAtlasDataBreakpoint.Plan($1004, 8, 8);
  Assert.AreEqual(4, mPlan.Length);
  Assert.IsTrue(mPlan.Partial);
  mPlan := TAtlasDataBreakpoint.Plan($1003, 4, 8);
  Assert.AreEqual(1, mPlan.Length);
  Assert.IsTrue(mPlan.Partial);
end;

procedure TCoreDebugDataBreakpointTests.PlanWithoutAddressOrSize;
begin
  Assert.AreEqual(0, TAtlasDataBreakpoint.Plan(0, 4, 4).Length);
  Assert.AreEqual(0, TAtlasDataBreakpoint.Plan($1000, 0, 4).Length);
  Assert.AreEqual(0, TAtlasDataBreakpoint.Plan($1000, 4, 0).Length);
end;

procedure TCoreDebugDataBreakpointTests.FreeSlotsNeverNegative;
begin
  Assert.AreEqual(4, TAtlasDataBreakpoint.FreeSlots(0));
  Assert.AreEqual(1, TAtlasDataBreakpoint.FreeSlots(3));
  Assert.AreEqual(0, TAtlasDataBreakpoint.FreeSlots(4));
  Assert.AreEqual(0, TAtlasDataBreakpoint.FreeSlots(6));
end;

procedure TCoreDebugDataBreakpointTests.ReadsLittleEndianIntegers;
var
  mValue: Int64;
begin
  Assert.IsTrue(TAtlasDataBreakpoint.TryReadInteger(Bytes([$2A, 0, 0, 0]), True, mValue));
  Assert.IsTrue(mValue = 42);
  Assert.IsTrue(TAtlasDataBreakpoint.TryReadInteger(Bytes([$FF, $FF, $FF, $FF]), True, mValue));
  Assert.IsTrue(mValue = -1, 'mit Vorzeichen');
  Assert.IsTrue(TAtlasDataBreakpoint.TryReadInteger(Bytes([$FF, $FF, $FF, $FF]), False, mValue));
  Assert.IsTrue(mValue = 4294967295, 'ohne Vorzeichen');
  Assert.IsTrue(TAtlasDataBreakpoint.TryReadInteger(Bytes([$FE, $FF]), True, mValue));
  Assert.IsTrue(mValue = -2);
  Assert.IsTrue(TAtlasDataBreakpoint.TryReadInteger(Bytes([$FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF]), True, mValue));
  Assert.IsTrue(mValue = -1, 'acht Byte');
  Assert.IsFalse(TAtlasDataBreakpoint.TryReadInteger(nil, True, mValue));
  Assert.IsFalse(TAtlasDataBreakpoint.TryReadInteger(Bytes([1, 2, 3, 4, 5, 6, 7, 8, 9]), True, mValue));
end;

procedure TCoreDebugDataBreakpointTests.KindFromDebuggerText;
begin
  Assert.IsTrue(TAtlasDataValueKind.Signed = TAtlasDataBreakpoint.KindOf('-5', Bytes([$FB, $FF, $FF, $FF]), False));
  Assert.IsTrue(TAtlasDataValueKind.Unsigned =
    TAtlasDataBreakpoint.KindOf('4294967291', Bytes([$FB, $FF, $FF, $FF]), False));
  Assert.IsTrue(TAtlasDataValueKind.Signed = TAtlasDataBreakpoint.KindOf('42', Bytes([$2A, 0, 0, 0]), False));
  Assert.IsTrue(TAtlasDataValueKind.Boolean = TAtlasDataBreakpoint.KindOf('True', Bytes([1]), False));
  Assert.IsTrue(TAtlasDataValueKind.Text = TAtlasDataBreakpoint.KindOf('''Meier''', Bytes([0, $10, 0, 0]), False));
  Assert.IsTrue(TAtlasDataValueKind.Text = TAtlasDataBreakpoint.KindOf('#13#10', Bytes([0, $10, 0, 0]), False));
  Assert.IsTrue(TAtlasDataValueKind.Raw = TAtlasDataBreakpoint.KindOf('3.5', Bytes([0, 0, $60, $40]), False),
    'Gleitkomma');
  Assert.IsTrue(TAtlasDataValueKind.Raw = TAtlasDataBreakpoint.KindOf('42', Bytes([$2A, 0, 0, 0]), True),
    'nur der erste Teil');
  Assert.IsTrue(TAtlasDataValueKind.Raw = TAtlasDataBreakpoint.KindOf('7', Bytes([$2A, 0, 0, 0]), False),
    'Text passt nicht zu den Bytes');
end;

procedure TCoreDebugDataBreakpointTests.ValueTextByKind;
begin
  Assert.AreEqual('-5', TAtlasDataBreakpoint.ValueText(TAtlasDataValueKind.Signed, Bytes([$FB, $FF, $FF, $FF])));
  Assert.AreEqual('4294967291',
    TAtlasDataBreakpoint.ValueText(TAtlasDataValueKind.Unsigned, Bytes([$FB, $FF, $FF, $FF])));
  Assert.AreEqual('False', TAtlasDataBreakpoint.ValueText(TAtlasDataValueKind.Boolean, Bytes([0])));
  Assert.AreEqual('True', TAtlasDataBreakpoint.ValueText(TAtlasDataValueKind.Boolean, Bytes([2])));
  Assert.AreEqual('', TAtlasDataBreakpoint.ValueText(TAtlasDataValueKind.Text, Bytes([0, $10, 0, 0])));
  Assert.AreEqual('$00 00 60 40', TAtlasDataBreakpoint.ValueText(TAtlasDataValueKind.Raw, Bytes([0, 0, $60, $40])));
  Assert.AreEqual('', TAtlasDataBreakpoint.HexText(nil));
end;

procedure TCoreDebugDataBreakpointTests.ChangedComparesBytes;
begin
  Assert.IsFalse(TAtlasDataBreakpoint.Changed(Bytes([1, 2]), Bytes([1, 2])));
  Assert.IsTrue(TAtlasDataBreakpoint.Changed(Bytes([1, 2]), Bytes([1, 3])));
  Assert.IsTrue(TAtlasDataBreakpoint.Changed(Bytes([1, 2]), Bytes([1])));
  Assert.IsFalse(TAtlasDataBreakpoint.Changed(nil, nil));
end;

end.
