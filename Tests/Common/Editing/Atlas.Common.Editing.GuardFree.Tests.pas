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
    [Test]
    procedure AddsMissingSemicolonAfterEnter;
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TGuardFree.Check(mTree, AText, ALine,
      function(const ATypeName: string): TGuardTypeKind
      begin
        Result := AKind;
      end, AOffer);
  finally
    mTree.Free;
  end;
end;

function Offered(const AVar, AStatement, ARest: string; AKind: TGuardTypeKind): Boolean; overload;
var
  mOffer: TGuardOffer;
begin
  Result := Check(Source(AVar, AStatement, ARest), 4, AKind, mOffer);
end;

function Offered(const AVar, AStatement, ARest: string): Boolean; overload;
begin
  Result := Offered(AVar, AStatement, ARest, TGuardTypeKind.Class_);
end;

procedure TGuardFreeTests.OffersForLocalObject;
var
  mOffer: TGuardOffer;
begin
  Assert.IsTrue(Check(Source('List: TStringList;', 'List := TStringList.Create;', ''), 4, TGuardTypeKind.Class_,
    mOffer));
  Assert.AreEqual('List', mOffer.Variable);
  Assert.AreEqual('TStringList', mOffer.TypeName);
  Assert.AreEqual('  ', mOffer.Indent);
  Assert.AreEqual(5, mOffer.EndLine);
  Assert.IsFalse(mOffer.CanEnclose);
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
  mText: string;
  mOffer: TGuardOffer;
  mEdit: TRuleEdit;
begin
  mText := Source('List: TStringList;', 'List := TStringList.Create;', '  List.Add(''a'');'#13#10#13#10 +
    '  Show(List.Text);'#13#10);
  Assert.IsTrue(Check(mText, 4, TGuardTypeKind.Class_, mOffer));
  Assert.IsTrue(mOffer.CanEnclose);
  Assert.AreEqual(8, mOffer.EndLine);
  mEdit := TGuardFree.Edit(mText, mOffer, TGuardScope.NewLine, TCompletionFreeStyle.Free);
  Assert.AreEqual(4, mEdit.Range.StartPos.Line);
  Assert.AreEqual(29, mEdit.Range.StartPos.Character);
  Assert.AreEqual(29, mEdit.Range.EndPos.Character);
  Assert.AreEqual(#13#10'  try'#13#10'    $0'#13#10'  finally'#13#10'    List.Free;'#13#10'  end;', mEdit.NewText);
  mEdit := TGuardFree.Edit(mText, mOffer, TGuardScope.ToRoutineEnd, TCompletionFreeStyle.Free);
  Assert.AreEqual(8, mEdit.Range.EndPos.Line);
  Assert.AreEqual(0, mEdit.Range.EndPos.Character);
  Assert.AreEqual(#13#10'  try'#13#10'    List.Add(''a'');'#13#10#13#10'    Show(List.Text);$0'#13#10 +
    '  finally'#13#10'    List.Free;'#13#10'  end;'#13#10, mEdit.NewText);
  // In einem if-Zweig nur die neue Zeile.
  mText := 'procedure Laden;'#13#10'var'#13#10'  List: TStringList;'#13#10'begin'#13#10'  if A then'#13#10 +
    '  begin'#13#10'    List := TStringList.Create;'#13#10'    List.Add(''a'');'#13#10'  end;'#13#10'end;'#13#10;
  Assert.IsTrue(Check(mText, 6, TGuardTypeKind.Class_, mOffer));
  Assert.IsFalse(mOffer.CanEnclose);
  Assert.AreEqual('    ', mOffer.Indent);
end;

procedure TGuardFreeTests.UsesFreeAndNil;
var
  mText: string;
  mOffer: TGuardOffer;
begin
  mText := Source('List: TStringList;', 'List := TStringList.Create;', '');
  Assert.IsTrue(Check(mText, 4, TGuardTypeKind.Class_, mOffer));
  Assert.IsTrue(TGuardFree.Edit(mText, mOffer, TGuardScope.NewLine, TCompletionFreeStyle.FreeAndNil).NewText.Contains(
    'FreeAndNil(List);'));
end;

procedure TGuardFreeTests.AddsMissingSemicolonAfterEnter;
var
  mText: string;
  mOffer: TGuardOffer;
  mEdit: TRuleEdit;
begin
  // Übernahme mit Enter am Zeilenende, dann Enter: Zeile 5 ist leer (eingerückt), das ";" fehlt.
  mText := Source('List: TStringList;', 'List := TStringList.Create', '  '#13#10);
  Assert.IsTrue(Check(mText, 4, TGuardTypeKind.Class_, mOffer));
  Assert.IsTrue(mOffer.AddSemicolon);
  Assert.AreEqual(28, mOffer.StatementEnd);
  mOffer.BlankLine := 5;
  mEdit := TGuardFree.Edit(mText, mOffer, TGuardScope.NewLine, TCompletionFreeStyle.Free);
  Assert.AreEqual(4, mEdit.Range.StartPos.Line);
  Assert.AreEqual(28, mEdit.Range.StartPos.Character);
  Assert.AreEqual(5, mEdit.Range.EndPos.Line);
  Assert.AreEqual(2, mEdit.Range.EndPos.Character);
  Assert.AreEqual(';'#13#10'  try'#13#10'    $0'#13#10'  finally'#13#10'    List.Free;'#13#10'  end;', mEdit.NewText);
  // Argumente und Kommentar: das ";" kommt hinter die Klammer, der Kommentar bleibt.
  mText := Source('S: TFileStream;', 'S := TFileStream.Create(Name, fmOpenRead) // lesen', '');
  Assert.IsTrue(Check(mText, 4, TGuardTypeKind.Class_, mOffer));
  Assert.IsTrue(mOffer.AddSemicolon);
  mEdit := TGuardFree.Edit(mText, mOffer, TGuardScope.NewLine, TCompletionFreeStyle.Free);
  Assert.IsTrue(mEdit.NewText.StartsWith('; // lesen'#13#10'  try'), mEdit.NewText);
  // Bis zum Routinenende: die leere Zeile entfällt.
  mText := Source('List: TStringList;', 'List := TStringList.Create', '  '#13#10'  List.Add(''a'');'#13#10);
  Assert.IsTrue(Check(mText, 4, TGuardTypeKind.Class_, mOffer));
  Assert.IsTrue(mOffer.CanEnclose);
  mOffer.BlankLine := 5;
  mEdit := TGuardFree.Edit(mText, mOffer, TGuardScope.ToRoutineEnd, TCompletionFreeStyle.Free);
  Assert.AreEqual(';'#13#10'  try'#13#10'    List.Add(''a'');$0'#13#10'  finally'#13#10'    List.Free;'#13#10 +
    '  end;'#13#10, mEdit.NewText);
  // Die nächste Zeile setzt den Ausdruck fort: kein Angebot.
  Assert.IsFalse(Offered('List: TStringList;', 'List := TStringList.Create', '    .Add(''a'');'#13#10));
  Assert.IsFalse(Offered('X: TFoo;', 'X := TFoo.Create', '    (1, 2);'#13#10));
  // Mit ";" bleibt alles wie bisher.
  Assert.IsTrue(Check(Source('List: TStringList;', 'List := TStringList.Create; // a;b', ''), 4,
    TGuardTypeKind.Class_, mOffer));
  Assert.IsFalse(mOffer.AddSemicolon);
end;

initialization
  TDUnitX.RegisterTestFixture(TGuardFreeTests);

end.
