unit Atlas.Common.Editing.GuardFree.Tests;

// Tests für „Freigabe absichern“ (#489).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGuardFreeTests = class
  public
    [Test]
    procedure OffersForLocalObject;
    [Test]
    procedure SkipsOwnedReturnedAndFreedObjects;
    [Test]
    procedure WrapsNewLineOrRestOfRoutine;
    [Test]
    procedure UsesFreeAndNil;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.GuardFree;

/// <summary>Routine mit AVar im var-Abschnitt; AStatement steht in Zeile 4, ARest danach.</summary>
function Source(const AVar, AStatement, ARest: string): string;
begin
  Result :=
    'procedure Laden;'#13#10 +
    'var'#13#10 +
    '  ' + AVar + #13#10 +
    'begin'#13#10 +
    '  ' + AStatement + #13#10 +
    ARest +
    'end;'#13#10;
end;

function Check(const AText: string; ALine: Integer; AKind: TGuardTypeKind; out AOffer: TGuardOffer): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TGuardFree.Check(Tree, AText, ALine,
      function(const ATypeName: string): TGuardTypeKind
      begin
        Result := AKind;
      end, AOffer);
  finally
    Tree.Free;
  end;
end;

function Offered(const AVar, AStatement, ARest: string; AKind: TGuardTypeKind = TGuardTypeKind.Class_): Boolean;
var
  Offer: TGuardOffer;
begin
  Result := Check(Source(AVar, AStatement, ARest), 4, AKind, Offer);
end;

procedure TGuardFreeTests.OffersForLocalObject;
var
  Offer: TGuardOffer;
begin
  Assert.IsTrue(Check(Source('List: TStringList;', 'List := TStringList.Create;', ''), 4, TGuardTypeKind.Class_,
    Offer));
  Assert.AreEqual('List', Offer.Variable);
  Assert.AreEqual('TStringList', Offer.TypeName);
  Assert.AreEqual('  ', Offer.Indent);
  Assert.AreEqual(5, Offer.EndLine);
  Assert.IsFalse(Offer.CanEnclose);
  // Generisch, mit Argumenten, unbekannter Typ, Inline-Variable.
  Assert.IsTrue(Offered('Map: TDictionary<string, Integer>;', 'Map := TDictionary<string, Integer>.Create(16);', ''));
  Assert.IsTrue(Offered('Stream: TStream;', 'Stream := TFileStream.Create(Name, fmOpenRead);', '',
    TGuardTypeKind.Unknown));
  Assert.IsTrue(Offered('X: Integer;', 'var List := TStringList.Create;', ''));
  // Komponente ohne Owner.
  Assert.IsTrue(Offered('Timer: TTimer;', 'Timer := TTimer.Create(nil);', '', TGuardTypeKind.Component));
end;

procedure TGuardFreeTests.SkipsOwnedReturnedAndFreedObjects;
begin
  // Owner, Record, Interface-Variable, Feld (nicht lokal), Result.
  Assert.IsFalse(Offered('Form: TForm;', 'Form := TForm.Create(Self);', ''));
  Assert.IsFalse(Offered('Button: TButton;', 'Button := TButton.Create(pnlOben);', '', TGuardTypeKind.Component));
  Assert.IsFalse(Offered('P: TPoint;', 'P := TPoint.Create(1, 2);', '', TGuardTypeKind.Other));
  Assert.IsFalse(Offered('List: IList;', 'List := TListImpl.Create;', ''));
  Assert.IsFalse(Offered('X: Integer;', 'FList := TStringList.Create;', ''));
  Assert.IsFalse(Offered('X: Integer;', 'Result := TStringList.Create;', ''));
  // Danach zurückgegeben, zugewiesen, in eine Liste gelegt, schon freigegeben, schon im try.
  Assert.IsFalse(Offered('List: TStringList;', 'List := TStringList.Create;', '  Result := List;'#13#10));
  Assert.IsFalse(Offered('List: TStringList;', 'List := TStringList.Create;', '  FItems := List;'#13#10));
  Assert.IsFalse(Offered('Item: TItem;', 'Item := TItem.Create;', '  FItems.Add(Item);'#13#10));
  Assert.IsFalse(Offered('List: TStringList;', 'List := TStringList.Create;', '  FreeAndNil(List);'#13#10));
  Assert.IsFalse(Offered('List: TStringList;', 'List := TStringList.Create;',
    '  try'#13#10'  finally'#13#10'    List.Free;'#13#10'  end;'#13#10));
  // Ein anderes Objekt in der Liste stört nicht.
  Assert.IsTrue(Offered('Item: TItem;', 'Item := TItem.Create;', '  FItems.Add(Other);'#13#10));
end;

procedure TGuardFreeTests.WrapsNewLineOrRestOfRoutine;
var
  Text: string;
  Offer: TGuardOffer;
  Edit: TRuleEdit;
begin
  Text := Source('List: TStringList;', 'List := TStringList.Create;', '  List.Add(''a'');'#13#10#13#10 +
    '  Show(List.Text);'#13#10);
  Assert.IsTrue(Check(Text, 4, TGuardTypeKind.Class_, Offer));
  Assert.IsTrue(Offer.CanEnclose);
  Assert.AreEqual(8, Offer.EndLine);
  Edit := TGuardFree.Edit(Text, Offer, TGuardScope.NewLine, TCompletionFreeStyle.Free);
  Assert.AreEqual(4, Edit.Range.StartPos.Line);
  Assert.AreEqual(29, Edit.Range.StartPos.Character);
  Assert.AreEqual(29, Edit.Range.EndPos.Character);
  Assert.AreEqual(#13#10'  try'#13#10'    $0'#13#10'  finally'#13#10'    List.Free;'#13#10'  end;', Edit.NewText);
  Edit := TGuardFree.Edit(Text, Offer, TGuardScope.ToRoutineEnd, TCompletionFreeStyle.Free);
  Assert.AreEqual(8, Edit.Range.EndPos.Line);
  Assert.AreEqual(0, Edit.Range.EndPos.Character);
  Assert.AreEqual(#13#10'  try'#13#10'    List.Add(''a'');'#13#10#13#10'    Show(List.Text);$0'#13#10 +
    '  finally'#13#10'    List.Free;'#13#10'  end;'#13#10, Edit.NewText);
  // In einem if-Zweig nur die neue Zeile.
  Text := 'procedure Laden;'#13#10'var'#13#10'  List: TStringList;'#13#10'begin'#13#10'  if A then'#13#10 +
    '  begin'#13#10'    List := TStringList.Create;'#13#10'    List.Add(''a'');'#13#10'  end;'#13#10'end;'#13#10;
  Assert.IsTrue(Check(Text, 6, TGuardTypeKind.Class_, Offer));
  Assert.IsFalse(Offer.CanEnclose);
  Assert.AreEqual('    ', Offer.Indent);
end;

procedure TGuardFreeTests.UsesFreeAndNil;
var
  Text: string;
  Offer: TGuardOffer;
begin
  Text := Source('List: TStringList;', 'List := TStringList.Create;', '');
  Assert.IsTrue(Check(Text, 4, TGuardTypeKind.Class_, Offer));
  Assert.IsTrue(TGuardFree.Edit(Text, Offer, TGuardScope.NewLine, TCompletionFreeStyle.FreeAndNil).NewText.Contains(
    'FreeAndNil(List);'));
end;

initialization
  TDUnitX.RegisterTestFixture(TGuardFreeTests);

end.
