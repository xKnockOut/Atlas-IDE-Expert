unit Argus.Common.Editing.AssignmentSwap.Tests;

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
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Index.Contract,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor,
  Argus.Common.Editing.AssignmentSwap;

/// <summary>Wendet die Edits zeilenweise an (eine Edit je ganze Zeile).</summary>
function Apply(const AText: string; const AEdits: TArray<TRuleEdit>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Index: Integer;
begin
  Lines := AText.Split([#10]);
  for Edit in AEdits do
    Lines[Edit.Range.StartPos.Line] := Edit.NewText;
  Result := '';
  for Index := 0 to High(Lines) do
  begin
    if Index > 0 then
      Result := Result + #10;
    Result := Result + Lines[Index];
  end;
end;

function SwapAll(const AText: string; const AReadOnly: TReadOnlyCheck = nil): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TAssignmentSwap.Swap(AText, TTextRange.Create(0, 0, 99, 0), AReadOnly, Edits), AText);
  Result := Apply(AText, Edits);
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
  Original = '  edtName.Text := Kunde.Name; // Name'#10'  Ini.Werte[''A''] := Wert^'#10'  X:=Y;';
begin
  Assert.AreEqual(Original, SwapAll(SwapAll(Original)));
end;

procedure TAssignmentSwapTests.AlignedBlockStaysAligned;
const
  Original = '  edtName.Text     := Kunde.Name;'#10'  chkAktiv.Checked := Kunde.Aktiv;';
begin
  Assert.AreEqual('  Kunde.Name  := edtName.Text;'#10'  Kunde.Aktiv := chkAktiv.Checked;', SwapAll(Original));
  Assert.AreEqual(Original, SwapAll(SwapAll(Original)));
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
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(TAssignmentSwap.Swap('  Label1.Caption := IntToStr(N);'#10'  Save;',
    TTextRange.Create(0, 0, 1, 0), nil, Edits));
  Assert.IsFalse(TAssignmentSwap.Swap('  if A then B := C;', TTextRange.Create(0, 0, 0, 0), nil, Edits));
end;

procedure TAssignmentSwapTests.ReadOnlyFromIndex;
const
  FileName = 'C:\P\Liste.pas';
  Source = 'unit Liste;'#10'interface'#10'type'#10'  TListe = class'#10'  public'#10 +
    '    property Count: Integer read FCount;'#10'    property Name: string read FName write FName;'#10 +
    '  end;'#10'implementation'#10'end.';
var
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(Source, FileName, nil));
  Assert.IsTrue(TAssignmentSwap.ReadOnlyByIndex(Index, FileName, Source, 'Liste.Count'));
  Assert.IsFalse(TAssignmentSwap.ReadOnlyByIndex(Index, FileName, Source, 'Kunden[0].Name'));
  Assert.IsFalse(TAssignmentSwap.ReadOnlyByIndex(Index, FileName, Source, 'Unbekannt'));
  Assert.IsFalse(TAssignmentSwap.ReadOnlyByIndex(nil, FileName, Source, 'Liste.Count'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAssignmentSwapTests);

end.
