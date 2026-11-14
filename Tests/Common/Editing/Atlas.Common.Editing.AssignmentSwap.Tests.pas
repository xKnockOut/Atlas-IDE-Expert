unit Atlas.Common.Editing.AssignmentSwap.Tests;

// Tests für "Zuweisungen umkehren" (#313).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAssignmentSwapTests = class
  public
    [Test]
    procedure SwapsExampleLinesKeepingComments;
    [Test]
    procedure CallOnRightGetsMarker;
    [Test]
    procedure ReadOnlyPropertyStays;
    [Test]
    procedure TwiceGivesOriginal;
    [Test]
    procedure AlignedBlockStaysAligned;
    [Test]
    procedure AssignableExpressions;
    [Test]
    procedure NothingToSwap;
    [Test]
    procedure ReadOnlyFromIndex;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.AssignmentSwap;

/// <summary>Wendet die Edits zeilenweise an (eine Edit je ganze Zeile).</summary>
function Apply(const AText: string; const AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mIndex: Integer;
begin
  mLines := AText.Split([#10]);
  for mEdit in AEdits do
  begin
    mLines[mEdit.Range.StartPos.Line] := mEdit.NewText;
  end;
  Result := '';
  for mIndex := 0 to High(mLines) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + #10;
    end;
    Result := Result + mLines[mIndex];
  end;
end;

function SwapAll(const AText: string; const AReadOnly: TReadOnlyCheck): string; overload;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TAssignmentSwap.Swap(AText, TTextRange.Create(0, 0, 99, 0), AReadOnly, mEdits), AText);
  Result := Apply(AText, mEdits);
end;

function SwapAll(const AText: string): string; overload;
begin
  Result := SwapAll(AText, nil);
end;

procedure TAssignmentSwapTests.SwapsExampleLinesKeepingComments;
begin
  Assert.AreEqual('  Kunde.Name := edtName.Text; // Name'#10'  Kunde.Aktiv := chkAktiv.Checked;',
    SwapAll('  edtName.Text := Kunde.Name; // Name'#10'  chkAktiv.Checked := Kunde.Aktiv;'));
end;

procedure TAssignmentSwapTests.CallOnRightGetsMarker;
begin
  Assert.AreEqual('  Kunde.Name := edtName.Text;'#10'  Label1.Caption := IntToStr(N); // nicht umkehrbar',
    SwapAll('  edtName.Text := Kunde.Name;'#10'  Label1.Caption := IntToStr(N);'));
  Assert.AreEqual('  A := B;'#10'  X := 1; // nicht umkehrbar; Zähler',
    SwapAll('  B := A;'#10'  X := 1; // Zähler'));
end;

function IsCountReadOnly(const AExpression: string): Boolean;
begin
  Result := SameText(AExpression, 'Liste.Count');
end;

procedure TAssignmentSwapTests.ReadOnlyPropertyStays;
begin
  Assert.AreEqual('  Kunde.Name := edtName.Text;'#10'  N := Liste.Count; // nicht umkehrbar',
    SwapAll('  edtName.Text := Kunde.Name;'#10'  N := Liste.Count;', IsCountReadOnly));
end;

procedure TAssignmentSwapTests.TwiceGivesOriginal;
const
  cOriginal = '  edtName.Text := Kunde.Name; // Name'#10'  Ini.Werte[''A''] := Wert^'#10'  X:=Y;';
begin
  Assert.AreEqual(cOriginal, SwapAll(SwapAll(cOriginal)));
end;

procedure TAssignmentSwapTests.AlignedBlockStaysAligned;
const
  cOriginal = '  edtName.Text     := Kunde.Name;'#10'  chkAktiv.Checked := Kunde.Aktiv;';
begin
  Assert.AreEqual('  Kunde.Name  := edtName.Text;'#10'  Kunde.Aktiv := chkAktiv.Checked;', SwapAll(cOriginal));
  Assert.AreEqual(cOriginal, SwapAll(SwapAll(cOriginal)));
end;

procedure TAssignmentSwapTests.AssignableExpressions;
begin
  Assert.IsTrue(TAssignmentSwap.IsAssignable('Kunde.Adresse.Ort'));
  Assert.IsTrue(TAssignmentSwap.IsAssignable('Liste[I + 1].Name'));
  Assert.IsTrue(TAssignmentSwap.IsAssignable('P^.Wert'));
  Assert.IsFalse(TAssignmentSwap.IsAssignable('IntToStr(N)'));
  Assert.IsFalse(TAssignmentSwap.IsAssignable('A + B'));
  Assert.IsFalse(TAssignmentSwap.IsAssignable('''Text'''));
  Assert.IsFalse(TAssignmentSwap.IsAssignable('42'));
  Assert.IsFalse(TAssignmentSwap.IsAssignable('nil'));
end;

procedure TAssignmentSwapTests.NothingToSwap;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(TAssignmentSwap.Swap('  Label1.Caption := IntToStr(N);'#10'  Save;',
    TTextRange.Create(0, 0, 1, 0), nil, mEdits));
  Assert.IsFalse(TAssignmentSwap.Swap('  if A then B := C;', TTextRange.Create(0, 0, 0, 0), nil, mEdits));
end;

procedure TAssignmentSwapTests.ReadOnlyFromIndex;
const
  cFileName = 'C:\P\Liste.pas';
  cSource = 'unit Liste;'#10'interface'#10'type'#10'  TListe = class'#10'  public'#10 +
    '    property Count: Integer read FCount;'#10'    property Name: string read FName write FName;'#10 +
    '  end;'#10'implementation'#10'end.';
var
  mIndex: ISymbolIndex;
  mCheck: TReadOnlyCheck;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cSource, cFileName, nil));
  Assert.IsTrue(TAssignmentSwap.ReadOnlyByIndex(mIndex, cFileName, cSource, 'Liste.Count'));
  Assert.IsFalse(TAssignmentSwap.ReadOnlyByIndex(mIndex, cFileName, cSource, 'Kunden[0].Name'));
  Assert.IsFalse(TAssignmentSwap.ReadOnlyByIndex(mIndex, cFileName, cSource, 'Unbekannt'));
  Assert.IsFalse(TAssignmentSwap.ReadOnlyByIndex(nil, cFileName, cSource, 'Liste.Count'));
  mCheck := TAssignmentSwap.ReadOnlyCheckOf(mIndex, cFileName, cSource);
  Assert.IsTrue(mCheck('Liste.Count'));
  Assert.IsFalse(mCheck('Kunden[0].Name'));
  mCheck := TAssignmentSwap.ReadOnlyCheckOf(nil, cFileName, cSource);
  Assert.IsFalse(Assigned(mCheck));
end;

initialization
  TDUnitX.RegisterTestFixture(TAssignmentSwapTests);

end.
