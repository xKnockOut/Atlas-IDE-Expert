unit Atlas.Common.Editing.GenericLists.Tests;

// Tests für die Umwandlung ungenerischer Listen (#1105, #1106): Beispiel aus dem
// Issue, Casts, Schleifen, Properties, uses-Klauseln, andere Units, Stapel und
// Warteschlangen sowie je ein Fall für jeden Ablehnungsgrund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGenericListsTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure ResultParsesWithoutErrors;
    [Test]
    procedure AsCastAndParentheses;
    [Test]
    procedure ItemsFirstLastAndExtract;
    [Test]
    procedure UncastReadsThatStayValid;
    [Test]
    procedure ForInLoopVariable;
    [Test]
    procedure InlineLoopVariable;
    [Test]
    procedure LocalVariableAndInlineVar;
    [Test]
    procedure SplitsDeclarationWithSeveralNames;
    [Test]
    procedure PropertyReadingField;
    [Test]
    procedure SameNameOnOtherClassIsIgnored;
    [Test]
    procedure ObjectListKeepsCreateArguments;
    [Test]
    procedure UsesAddedToImplementation;
    [Test]
    procedure UsesAddedToInterface;
    [Test]
    procedure UsesNotDuplicated;
    [Test]
    procedure UsesMovedFromImplementation;
    [Test]
    procedure ContnrsRemovedWhenUnused;
    [Test]
    procedure ContnrsKeptWhenStillUsed;
    [Test]
    procedure ContnrsRemovedFromOtherClause;
    [Test]
    procedure ContnrsKeptInClauseWithDirectives;
    [Test]
    procedure SafeOnlyWithKnownTypes;
    [Test]
    procedure RejectsSort;
    [Test]
    procedure RejectsAssign;
    [Test]
    procedure RejectsListProperty;
    [Test]
    procedure RejectsPointerValues;
    [Test]
    procedure RejectsIntegerCasts;
    [Test]
    procedure RejectsLookupWithOtherType;
    [Test]
    procedure RejectsPassingTheList;
    [Test]
    procedure RejectsDifferentCasts;
    [Test]
    procedure RejectsReadsWithoutCast;
    [Test]
    procedure RejectsPropertyWithGetter;
    [Test]
    procedure RejectsOtherCreation;
    [Test]
    procedure RejectsParameter;
    [Test]
    procedure PublicFieldNamesExternalUses;
    [Test]
    procedure PrivateFieldNeedsNoOtherUnits;
    [Test]
    procedure OtherUnitIsRewritten;
    [Test]
    procedure OtherUnitBlocksConversion;
    [Test]
    procedure QueueRenamesMethods;
    [Test]
    procedure ObjectStackGetsCreateFalse;
    [Test]
    procedure ObjectStackWithoutCreateIsRejected;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists;

const
  cMainFile = 'C:\P\Haupt.pas';
  cOtherFile = 'C:\P\Andere.pas';

type
  TOtherUnit = record
    FileName: string;
    Text: string;
  end;

  TOutcome = record
    Converted: Boolean;
    Text: string;
    Reason: string;
    Plan: TGenericListPlan;
    External: TArray<string>;
  end;

function FindDeclaration(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
  mName: string;
begin
  if ANode.Kind in [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter] then
  begin
    for mName in ANode.Name.Split([',']) do
    begin
      if SameText(Trim(mName), AName) then
      begin
        Exit(ANode);
      end;
    end;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindDeclaration(ANode[mIndex], AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

function Convert(const AKind: TLegacyListKind; const ASource, AName: string;
  const AOthers: TArray<TOtherUnit>): TOutcome; overload;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mConversion: TGenericListConversion;
  mOther: TOtherUnit;
  mIndex: ISymbolIndex;
begin
  Result := Default(TOutcome);
  // Mit weiteren Units ein Index aus allen, sonst ohne Index wie im Linter.
  mIndex := nil;
  if AOthers <> nil then
  begin
    mIndex := TSymbolIndex.Create;
    mIndex.AddUnit(TIndexExtractor.ExtractText(ASource, cMainFile, nil));
    for mOther in AOthers do
    begin
      mIndex.AddUnit(TIndexExtractor.ExtractText(mOther.Text, mOther.FileName, nil));
    end;
  end;
  mTree := TSyntaxTreeCache.Parse(ASource);
  mResolver := TNameResolver.Create(mIndex);
  try
    mConversion := TGenericListConversion.Create(AKind, mResolver);
    try
      Result.Converted := mConversion.Start(mTree, ASource, cMainFile, FindDeclaration(mTree.Root, AName), AName);
      Result.External := mConversion.ExternalNames;
      if Result.Converted then
      begin
        for mOther in AOthers do
        begin
          mConversion.AddFile(mOther.Text, mOther.FileName);
        end;
        Result.Converted := mConversion.Finish(Result.Plan);
      end;
      Result.Reason := mConversion.Reason;
      if Result.Converted then
      begin
        Result.Text := TChangeSignature.ApplyEdits(ASource, Result.Plan.Edits);
      end;
    finally
      mConversion.Free;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function Convert(const AKind: TLegacyListKind; const ASource, AName: string): TOutcome; overload;
begin
  Result := Convert(AKind, ASource, AName, nil);
end;

function InUnit(const AUses, ADeclarations, ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10 + AUses + 'type'#10'  TPosition = class'#10 +
    '    Name: string;'#10'  end;'#10'  TListe = class'#10'  private'#10 + ADeclarations +
    '  public'#10'    procedure Lauf;'#10'  end;'#10'implementation'#10'procedure TListe.Lauf;'#10 +
    'var'#10'  I: Integer;'#10'  Pos: TPosition;'#10'  P: Pointer;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure AssertRejected(const AOutcome: TOutcome; const AReasonPart: string);
begin
  Assert.IsFalse(AOutcome.Converted, 'Umwandlung angeboten');
  Assert.IsTrue(Pos(AReasonPart, AOutcome.Reason) > 0, 'Grund: ' + AOutcome.Reason);
end;

procedure AssertContains(const AText, APart: string);
begin
  // Groß-/Kleinschreibung zählt (DUnitX Contains ignoriert sie).
  Assert.IsTrue(Pos(APart, AText) > 0, 'Fehlt "' + APart + '" in:'#10 + AText);
end;

procedure AssertLacks(const AText, APart: string);
begin
  Assert.AreEqual(0, Pos(APart, AText), 'Unerwartet "' + APart + '" in:'#10 + AText);
end;

{ TGenericListsTests }

procedure TGenericListsTests.IssueExample;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses'#10'  Classes;'#10, '    FPositionen: TList;'#10,
    '  FPositionen := TList.Create;'#10'  Pos := TPosition(FPositionen[I]);'#10), 'FPositionen');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '    FPositionen: TList<TPosition>;'#10);
  AssertContains(mOutcome.Text, '  FPositionen := TList<TPosition>.Create;'#10);
  AssertContains(mOutcome.Text, '  Pos := FPositionen[I];'#10);
  AssertContains(mOutcome.Text, 'uses'#10'  Classes,'#10'  System.Generics.Collections;');
  Assert.AreEqual('In TList<TPosition> umwandeln', mOutcome.Plan.Title);
  Assert.AreEqual('TPosition', mOutcome.Plan.ItemType);
  // Ein Undo-Schritt: alles in einer Korrektur derselben Datei.
  Assert.IsNull(Pointer(mOutcome.Plan.FileEdits));
  Assert.IsTrue(mOutcome.Plan.Safe);
end;

procedure TGenericListsTests.ResultParsesWithoutErrors;
var
  mOutcome: TOutcome;
  mTree: TSyntaxTree;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses'#10'  Classes;'#10, '    FPositionen: TList;'#10,
    '  FPositionen := TList.Create;'#10'  Pos := TPosition(FPositionen[I]);'#10 +
    '  Pos := FPositionen.Items[I] as TPosition;'#10'  FPositionen.Add(TPosition.Create);'#10 +
    '  FPositionen.Delete(0);'#10'  FPositionen.Free;'#10), 'FPositionen');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  mTree := TSyntaxTreeCache.Parse(mOutcome.Text);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), mOutcome.Text);
  finally
    mTree.Free;
  end;
end;

procedure TGenericListsTests.AsCastAndParentheses;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses'#10'  Classes;'#10, '    FListe: TList;'#10,
    '  Pos := FListe[I] as TPosition;'#10'  (FListe[0] as TPosition).Name := '''';'#10 +
    '  TPosition(Self.FListe[1]).Name := '''';'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  Pos := FListe[I];'#10);
  AssertContains(mOutcome.Text, '  FListe[0].Name := '''';'#10);
  AssertContains(mOutcome.Text, '  Self.FListe[1].Name := '''';'#10);
end;

procedure TGenericListsTests.ItemsFirstLastAndExtract;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses'#10'  Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe.Items[I]);'#10'  Pos := TPosition(FListe.First);'#10 +
    '  Pos := TPosition(FListe.Last);'#10'  Pos := TPosition(FListe.Extract(Pos));'#10 +
    '  FListe.Items[0] := Pos;'#10'  FListe.Insert(0, Pos);'#10'  I := FListe.IndexOf(Pos);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  Pos := FListe.Items[I];'#10);
  AssertContains(mOutcome.Text, '  Pos := FListe.First;'#10);
  AssertContains(mOutcome.Text, '  Pos := FListe.Last;'#10);
  AssertContains(mOutcome.Text, '  Pos := FListe.Extract(Pos);'#10);
  Assert.IsTrue(mOutcome.Plan.Safe);
end;

procedure TGenericListsTests.UncastReadsThatStayValid;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.ObjectList, InUnit('uses'#10'  Contnrs;'#10, '    FListe: TObjectList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  if FListe[I] = nil then'#10'    Exit;'#10 +
    '  if Assigned(FListe[I]) then'#10'    FListe[I].Free;'#10'  P := FListe[I];'#10 +
    '  if FListe.Count > 0 then'#10'    FListe.Clear;'#10'  FListe.OwnsObjects := False;'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  if FListe[I] = nil then'#10);
  AssertContains(mOutcome.Text, '    FListe[I].Free;'#10);
end;

procedure TGenericListsTests.ForInLoopVariable;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'implementation'#10 +
    'uses'#10'  Classes;'#10'type'#10'  TPosition = class'#10'  end;'#10'procedure Lauf;'#10'var'#10 +
    '  Liste: TList;'#10'  Eintrag: Pointer;'#10'begin'#10'  Liste := TList.Create;'#10 +
    '  for Eintrag in Liste do'#10'    TPosition(Eintrag).Free;'#10'  Liste.Free;'#10'end;'#10'end.', 'Liste');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  Liste: TList<TPosition>;'#10'  Eintrag: TPosition;'#10);
  AssertContains(mOutcome.Text, '    Eintrag.Free;'#10);
  AssertContains(mOutcome.Text, 'uses'#10'  Classes,'#10'  System.Generics.Collections;');
end;

procedure TGenericListsTests.InlineLoopVariable;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses'#10'  Classes;'#10, '    FListe: TList;'#10,
    '  for var E in FListe do'#10'    TPosition(E).Free;'#10'  for var F: Pointer in FListe do'#10 +
    '    Pos := TPosition(F);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  for var E in FListe do'#10'    E.Free;'#10);
  AssertContains(mOutcome.Text, '  for var F: TPosition in FListe do'#10'    Pos := F;'#10);
end;

procedure TGenericListsTests.LocalVariableAndInlineVar;
var
  mOutcome: TOutcome;
  mSource: string;
begin
  mSource := 'program Haupt;'#10'uses'#10'  Classes;'#10'type'#10'  TPosition = class'#10'  end;'#10 +
    'procedure Lauf;'#10'begin'#10'  var Liste := TList.Create;'#10'  TPosition(Liste[0]).Free;'#10'end;'#10 +
    'begin'#10'end.';
  mOutcome := Convert(TLegacyListKind.PointerList, mSource, 'Liste');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  var Liste := TList<TPosition>.Create;'#10'  Liste[0].Free;'#10);
  AssertContains(mOutcome.Text, 'uses'#10'  Classes,'#10'  System.Generics.Collections;');
end;

procedure TGenericListsTests.SplitsDeclarationWithSeveralNames;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses'#10'  Classes;'#10, '    FA, FListe, FB: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '    FA, FB: TList;'#10'    FListe: TList<TPosition>;'#10);
end;

procedure TGenericListsTests.PropertyReadingField;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses'#10'  Classes;'#10, '    FListe: TList;'#10 +
    '  public'#10'    property Liste: TList read FListe;'#10, '  Pos := TPosition(Liste[0]);'#10 +
    '  Pos := TPosition(FListe[1]);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '    property Liste: TList<TPosition> read FListe;'#10);
  AssertContains(mOutcome.Text, '  Pos := Liste[0];'#10);
  AssertContains(mOutcome.Text, '  Pos := FListe[1];'#10);
  Assert.AreEqual('Liste', string.Join(',', mOutcome.External));
end;

procedure TGenericListsTests.SameNameOnOtherClassIsIgnored;
var
  mOutcome: TOutcome;
begin
  // F.Items gehört zu TFremd (auch wenn das Mitglied dort unbekannt ist), nicht zur Property Items von TListe.
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'uses Classes;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'  TFremd = class(TUnbekannt)'#10'  end;'#10'  TListe = class'#10 +
    '  private'#10'    FListe: TList;'#10'  public'#10'    property Items: TList read FListe;'#10'  end;'#10 +
    'implementation'#10'procedure Lauf(F: TFremd; L: TListe);'#10'begin'#10'  F.Items.Clear;'#10 +
    '  TPosition(L.Items[0]).Free;'#10'end;'#10'end.', 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  F.Items.Clear;'#10'  L.Items[0].Free;'#10);
end;

procedure TGenericListsTests.ObjectListKeepsCreateArguments;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.ObjectList, InUnit('uses'#10'  Contnrs;'#10, '    FListe: TObjectList;'#10,
    '  FListe := TObjectList.Create(False);'#10'  Pos := FListe[0] as TPosition;'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  FListe := TObjectList<TPosition>.Create(False);'#10);
end;

procedure TGenericListsTests.UsesAddedToImplementation;
var
  mOutcome: TOutcome;
begin
  // Lokale Liste: System.Generics.Collections ins implementation-uses, auch wenn es noch keins gibt.
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'uses'#10'  Classes;'#10 +
    'implementation'#10'type'#10'  TPosition = class'#10'  end;'#10'procedure Lauf;'#10'var'#10 +
    '  Liste: TList;'#10'begin'#10'  TPosition(Liste[0]).Free;'#10'end;'#10'end.', 'Liste');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'implementation'#10#10'uses'#10'  System.Generics.Collections;'#10);
  AssertContains(mOutcome.Text, 'interface'#10'uses'#10'  Classes;'#10);
end;

procedure TGenericListsTests.UsesAddedToInterface;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'uses Classes, System.Generics.Collections;'#10);
end;

procedure TGenericListsTests.UsesNotDuplicated;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses Classes, System.Generics.Collections;'#10,
    '    FListe: TList;'#10, '  Pos := TPosition(FListe[0]);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'uses Classes, System.Generics.Collections;'#10'type');
end;

procedure TGenericListsTests.UsesMovedFromImplementation;
var
  mOutcome: TOutcome;
begin
  // Der Typ steht im interface, die Unit nur im implementation-uses: sie wandert nach oben.
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'uses Classes;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'  TListe = class'#10'    FListe: TList;'#10'  end;'#10 +
    'implementation'#10'uses SysUtils, System.Generics.Collections;'#10'procedure X(L: TListe);'#10'begin'#10 +
    '  TPosition(L.FListe[0]).Free;'#10'end;'#10'end.', 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'interface'#10'uses Classes, System.Generics.Collections;'#10);
  AssertContains(mOutcome.Text, 'implementation'#10'uses SysUtils;'#10);
end;

procedure TGenericListsTests.ContnrsRemovedWhenUnused;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.ObjectList, InUnit('uses Classes, Contnrs, SysUtils;'#10,
    '    FListe: TObjectList;'#10, '  FListe := TObjectList.Create;'#10'  Pos := TPosition(FListe[0]);'#10),
    'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'uses Classes, System.Generics.Collections, SysUtils;'#10);
  AssertLacks(mOutcome.Text, 'Contnrs');
end;

procedure TGenericListsTests.ContnrsKeptWhenStillUsed;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.ObjectList, InUnit('uses Classes, System.Contnrs;'#10,
    '    FListe: TObjectList;'#10'    FAndere: TObjectList;'#10, '  FListe := TObjectList.Create;'#10 +
    '  Pos := TPosition(FListe[0]);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'uses Classes, System.Contnrs, System.Generics.Collections;'#10);
  AssertContains(mOutcome.Text, '    FAndere: TObjectList;'#10);
end;

procedure TGenericListsTests.ContnrsRemovedFromOtherClause;
var
  mOutcome: TOutcome;
begin
  // Liste lokal im implementation, Contnrs im interface-uses ohne weitere Verwendung.
  mOutcome := Convert(TLegacyListKind.ObjectList, 'unit Haupt;'#10'interface'#10'uses Classes, Contnrs;'#10 +
    'implementation'#10'uses SysUtils;'#10'type'#10'  TPosition = class'#10'  end;'#10'procedure Lauf;'#10 +
    'var'#10'  Liste: TObjectList;'#10'begin'#10'  Liste := TObjectList.Create;'#10 +
    '  TPosition(Liste[0]).Free;'#10'end;'#10'end.', 'Liste');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'interface'#10'uses Classes;'#10);
  AssertContains(mOutcome.Text, 'implementation'#10'uses SysUtils, System.Generics.Collections;'#10);
end;

procedure TGenericListsTests.ContnrsKeptInClauseWithDirectives;
var
  mOutcome: TOutcome;
begin
  // Contnrs steht in einer Liste mit Direktive: Sie bleibt unverändert und bekommt auch kein
  // System.Generics.Collections, das schon in das uses des implementation-Abschnitts kommt.
  mOutcome := Convert(TLegacyListKind.ObjectList, 'unit Haupt;'#10'interface'#10 +
    'uses Classes{$IFDEF X}, Foo{$ENDIF}, Contnrs;'#10'implementation'#10'uses SysUtils;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'procedure Lauf;'#10'var'#10'  Liste: TObjectList;'#10'begin'#10 +
    '  Liste := TObjectList.Create;'#10'  TPosition(Liste[0]).Free;'#10'end;'#10'end.', 'Liste');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, 'interface'#10'uses Classes{$IFDEF X}, Foo{$ENDIF}, Contnrs;'#10);
  AssertContains(mOutcome.Text, 'implementation'#10'uses SysUtils, System.Generics.Collections;'#10);
end;

procedure TGenericListsTests.SafeOnlyWithKnownTypes;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  FListe.Add(Pos);'#10'  FListe.Add(nil);'#10 +
    '  FListe.Add(TPosition.Create);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  Assert.IsTrue(mOutcome.Plan.Safe);
  // Argument unbekannten Typs: als Code-Aktion, aber nicht in source.fixAll.
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  FListe.Add(Unbekannt);'#10), 'FListe');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  Assert.IsFalse(mOutcome.Plan.Safe);
end;

procedure TGenericListsTests.RejectsSort;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  FListe.Sort(Vergleich);'#10), 'FListe'), 'TListSortCompare');
end;

procedure TGenericListsTests.RejectsAssign;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  FListe.Assign(Andere, laOr);'#10), 'FListe'), 'TListAssignOp');
end;

procedure TGenericListsTests.RejectsListProperty;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  P := FListe.List;'#10), 'FListe'), 'PPointerList');
end;

procedure TGenericListsTests.RejectsPointerValues;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  FListe.Add(Pointer(I));'#10), 'FListe'), 'Pointer');
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  FListe.Add(P);'#10), 'FListe'), 'Pointer');
end;

procedure TGenericListsTests.RejectsIntegerCasts;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  I := Integer(FListe[0]);'#10), 'FListe'), 'Integer');
end;

procedure TGenericListsTests.RejectsLookupWithOtherType;
var
  mSource: string;
begin
  mSource := 'unit Haupt;'#10'interface'#10'uses Classes;'#10'type'#10'  TPosition = class'#10'  end;'#10 +
    '  TFremd = class'#10'  end;'#10'implementation'#10'procedure Lauf;'#10'var'#10'  Liste: TList;'#10 +
    '  Fremd: TFremd;'#10'begin'#10'  TPosition(Liste[0]).Free;'#10'  Liste.%s(Fremd);'#10'end;'#10'end.';
  AssertRejected(Convert(TLegacyListKind.PointerList, Format(mSource, ['Extract']), 'Liste'), 'TFremd');
  AssertRejected(Convert(TLegacyListKind.PointerList, Format(mSource, ['Remove']), 'Liste'), 'TFremd');
  AssertRejected(Convert(TLegacyListKind.PointerList, Format(mSource, ['IndexOf']), 'Liste'), 'TFremd');
end;

procedure TGenericListsTests.RejectsPassingTheList;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  Fuellen(FListe);'#10), 'FListe'), 'an Fuellen übergeben');
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  P := FListe;'#10), 'FListe'), 'weitergegeben');
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  with FListe do'#10'    Clear;'#10), 'FListe'), 'with');
end;

procedure TGenericListsTests.RejectsDifferentCasts;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10'  TListe(FListe[1]).Free;'#10), 'FListe'), 'verschiedenen Casts');
end;

procedure TGenericListsTests.RejectsReadsWithoutCast;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Verarbeiten(FListe[0]);'#10), 'FListe'), 'ohne Cast');
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  FListe.Clear;'#10), 'FListe'), 'Elementtyp ist unbekannt');
end;

procedure TGenericListsTests.RejectsPropertyWithGetter;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10 +
    '    function GetListe: TList;'#10'  public'#10'    property Liste: TList read GetListe write FListe;'#10,
    '  Pos := TPosition(FListe[0]);'#10), 'FListe'), 'GetListe');
end;

procedure TGenericListsTests.RejectsOtherCreation;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  FListe := TMeineListe.Create;'#10'  Pos := TPosition(FListe[0]);'#10), 'FListe'), 'TMeineListe');
end;

procedure TGenericListsTests.RejectsParameter;
begin
  AssertRejected(Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'implementation'#10 +
    'uses Classes;'#10'procedure Lauf(Liste: TList);'#10'begin'#10'end;'#10'end.', 'Liste'), 'Parameter');
end;

procedure TGenericListsTests.PublicFieldNamesExternalUses;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'uses Classes;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'  TListe = class'#10'  public'#10'    Liste: TList;'#10'  end;'#10 +
    'var'#10'  Global: TList;'#10'implementation'#10'end.', 'Liste');
  Assert.AreEqual('Liste', string.Join(',', mOutcome.External));
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'uses Classes;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'var'#10'  Global: TList;'#10'implementation'#10'end.', 'Global');
  Assert.AreEqual('Global', string.Join(',', mOutcome.External));
end;

procedure TGenericListsTests.PrivateFieldNeedsNoOtherUnits;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.PointerList, InUnit('uses Classes;'#10, '    FListe: TList;'#10,
    '  Pos := TPosition(FListe[0]);'#10), 'FListe');
  Assert.AreEqual(0, Integer(Length(mOutcome.External)));
end;

procedure TGenericListsTests.OtherUnitIsRewritten;
var
  mOutcome: TOutcome;
  mOther: TOtherUnit;
begin
  mOther.FileName := cOtherFile;
  mOther.Text := 'unit Andere;'#10'interface'#10'implementation'#10'uses Haupt;'#10'procedure Zeigen(L: TListe);'#10 +
    'begin'#10'  TPosition(L.Liste[0]).Free;'#10'end;'#10'end.';
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'uses Classes;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'  TListe = class'#10'  public'#10'    Liste: TList;'#10 +
    '    procedure Lauf;'#10'  end;'#10'implementation'#10'procedure TListe.Lauf;'#10'begin'#10 +
    '  Liste := TList.Create;'#10'  TPosition(Liste[0]).Free;'#10'end;'#10'end.', 'Liste', [mOther]);
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  Assert.AreEqual(1, Integer(Length(mOutcome.Plan.FileEdits)));
  Assert.AreEqual(cOtherFile, mOutcome.Plan.FileEdits[0].FileName);
  AssertContains(TChangeSignature.ApplyEdits(mOther.Text, mOutcome.Plan.FileEdits[0].Edits), '  L.Liste[0].Free;'#10);
  // Andere Units ändern sich mit: nicht in source.fixAll.
  Assert.IsFalse(mOutcome.Plan.Safe);
end;

procedure TGenericListsTests.OtherUnitBlocksConversion;
var
  mOutcome: TOutcome;
  mOther: TOtherUnit;
begin
  mOther.FileName := cOtherFile;
  mOther.Text := 'unit Andere;'#10'interface'#10'implementation'#10'uses Haupt;'#10'procedure Zeigen(L: TListe);'#10 +
    'begin'#10'  L.Liste.Sort(Vergleich);'#10'end;'#10'end.';
  mOutcome := Convert(TLegacyListKind.PointerList, 'unit Haupt;'#10'interface'#10'uses Classes;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'  TListe = class'#10'  public'#10'    Liste: TList;'#10 +
    '    procedure Lauf;'#10'  end;'#10'implementation'#10'procedure TListe.Lauf;'#10'begin'#10 +
    '  TPosition(Liste[0]).Free;'#10'end;'#10'end.', 'Liste', [mOther]);
  AssertRejected(mOutcome, 'TListSortCompare');
end;

procedure TGenericListsTests.QueueRenamesMethods;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.Queue, InUnit('uses Contnrs;'#10, '    FSchlange: TQueue;'#10,
    '  FSchlange := TQueue.Create;'#10'  FSchlange.Push(Pos);'#10'  Pos := TPosition(FSchlange.Pop);'#10 +
    '  Pos := TPosition(FSchlange.Peek);'#10'  if FSchlange.Count > 0 then'#10'    FSchlange.Pop;'#10 +
    '  if FSchlange.Count() = 0 then'#10'    Exit;'#10), 'FSchlange');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '    FSchlange: TQueue<TPosition>;'#10);
  AssertContains(mOutcome.Text, '  FSchlange.Enqueue(Pos);'#10'  Pos := FSchlange.Dequeue;'#10);
  AssertContains(mOutcome.Text, '  Pos := FSchlange.Peek;'#10);
  AssertContains(mOutcome.Text, '    FSchlange.Dequeue;'#10);
  // Count ist in Contnrs eine Funktion, in TQueue<T> eine Property.
  AssertContains(mOutcome.Text, '  if FSchlange.Count = 0 then'#10);
  AssertContains(mOutcome.Text, 'uses System.Generics.Collections;'#10);
end;

procedure TGenericListsTests.ObjectStackGetsCreateFalse;
var
  mOutcome: TOutcome;
begin
  mOutcome := Convert(TLegacyListKind.ObjectStack, InUnit('uses Contnrs;'#10, '    FStapel: TObjectStack;'#10,
    '  FStapel := TObjectStack.Create;'#10'  FStapel.Push(Pos);'#10'  Pos := FStapel.Pop as TPosition;'#10), 'FStapel');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  FStapel := TObjectStack<TPosition>.Create(False);'#10);
  AssertContains(mOutcome.Text, '  Pos := FStapel.Extract;'#10);
  mOutcome := Convert(TLegacyListKind.ObjectQueue, InUnit('uses Contnrs;'#10, '    FSchlange: TObjectQueue;'#10,
    '  FSchlange := TObjectQueue.Create();'#10'  FSchlange.Push(Pos);'#10'  Pos := TPosition(FSchlange.Pop);'#10),
    'FSchlange');
  Assert.IsTrue(mOutcome.Converted, mOutcome.Reason);
  AssertContains(mOutcome.Text, '  FSchlange := TObjectQueue<TPosition>.Create(False);'#10);
  AssertContains(mOutcome.Text, '  FSchlange.Enqueue(Pos);'#10'  Pos := FSchlange.Extract;'#10);
end;

procedure TGenericListsTests.ObjectStackWithoutCreateIsRejected;
begin
  AssertRejected(Convert(TLegacyListKind.ObjectStack, InUnit('uses Contnrs;'#10, '    FStapel: TObjectStack;'#10,
    '  Pos := TPosition(FStapel.Pop);'#10), 'FStapel'), 'nicht erzeugt');
end;

initialization
  TDUnitX.RegisterTestFixture(TGenericListsTests);

end.
