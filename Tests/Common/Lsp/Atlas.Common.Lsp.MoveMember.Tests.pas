unit Atlas.Common.Lsp.MoveMember.Tests;

// Tests für „Mitglied in Vorfahr oder Nachfahr verschieben“ über das Protokoll
// (#675): Angebot der Code-Aktionen je nach Vorfahr und Nachfahren im Projekt,
// Antwort auf prepare, Verschieben in einen Vorfahren einer anderen Unit
// samt uses, Abbruch bei Kreisverweis, Verbot bei Nutzung über den
// Vorfahr-Typ und die abstrakte Variante nach unten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspMoveMemberTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OffersByHierarchy;
    [Test]
    procedure PrepareListsTargets;
    [Test]
    procedure PullsUpIntoOtherUnitWithUses;
    [Test]
    procedure RefusesCircularReference;
    [Test]
    procedure PushDownRefusedByForeignUse;
    [Test]
    procedure PushDownKeepsAbstract;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveMember;

const
  cClassesFile = 'C:\L\System.Classes.pas';
  cBasisFile = 'C:\P\Basis.pas';
  cKindFile = 'C:\P\Kind.pas';
  cMainFile = 'C:\P\Main.pas';

  cUnitClasses =
    'unit System.Classes;'#10'interface'#10'type'#10'  TStrings = class'#10'  end;'#10 +
    'implementation'#10'end.'#10;
  cUnitBasis =
    'unit Basis;'#10 +                         // 0
    'interface'#10 +                           // 1
    'type'#10 +                                // 2
    '  TBase = class'#10 +                     // 3
    '  public'#10 +                            // 4
    '    procedure Show;'#10 +                 // 5
    '  end;'#10 +                              // 6
    'implementation'#10#10 +
    'procedure TBase.Show;'#10'begin'#10'end;'#10#10 +
    'end.'#10;
  cUnitKind =
    'unit Kind;'#10 +                          // 0
    'interface'#10 +                           // 1
    'uses'#10 +                                // 2
    '  System.Classes, Basis;'#10 +            // 3
    'type'#10 +                                // 4
    '  THelper = class'#10 +                   // 5
    '  end;'#10 +                              // 6
    '  TChild = class(TBase)'#10 +             // 7
    '  private'#10 +                           // 8
    '    FItems: TStrings;'#10 +               // 9
    '    FHelper: THelper;'#10 +               // 10
    '  public'#10 +                            // 11
    '    procedure Fill;'#10 +                 // 12
    '  end;'#10 +                              // 13
    'implementation'#10#10 +
    'procedure TChild.Fill;'#10'begin'#10'  FItems := nil;'#10'end;'#10#10 +
    'end.'#10;
  cUnitMain =
    'unit Main;'#10'interface'#10'uses'#10'  Basis;'#10'implementation'#10#10 +
    'procedure Go(B: TBase);'#10'begin'#10'  B.Show;'#10'end;'#10#10 +
    'end.'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, cClassesFile) then
  begin
    Result := cUnitClasses;
  end
  else if SameText(AFileName, cBasisFile) then
  begin
    Result := cUnitBasis;
  end
  else if SameText(AFileName, cKindFile) then
  begin
    Result := cUnitKind;
  end
  else if SameText(AFileName, cMainFile) then
  begin
    Result := cUnitMain;
  end
  else
  begin
    Result := '';
  end;
end;

function Context(const AIndex: ISymbolIndex): TMoveMemberContext;
begin
  Result := Default(TMoveMemberContext);
  Result.Index := AIndex;
  Result.Files := [cBasisFile, cKindFile, cMainFile];
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
end;

function Request(const AMembers: array of Integer; const ATarget: string; AOption: Boolean): TJSONObject;
var
  mMembers, mTargets: TJSONArray;
  mId: Integer;
begin
  Result := TJSONObject.Create;
  mMembers := TJSONArray.Create;
  for mId in AMembers do
  begin
    mMembers.AddElement(TJSONNumber.Create(mId));
  end;
  Result.AddPair('members', mMembers);
  mTargets := TJSONArray.Create;
  mTargets.Add(ATarget);
  Result.AddPair('targets', mTargets);
  Result.AddPair('option', TJSONBool.Create(AOption));
end;

/// <summary>Text von AFileName nach dem WorkspaceEdit in AAnswer.</summary>
function After(AAnswer: TJSONObject; const AFileName: string): string;
var
  mItem, mEdit: TJSONValue;
  mDocument, mRange: TJSONObject;
  mEdits: TArray<TTextEdit>;
  mUri: string;
begin
  Result := TextOf(AFileName);
  for mItem in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    mDocument := TJSONObject(mItem);
    if mDocument.GetValue('textDocument') = nil then
    begin
      Continue;
    end;
    mUri := (mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(mUri), AFileName) then
    begin
      Continue;
    end;
    mEdits := nil;
    for mEdit in mDocument.GetValue('edits') as TJSONArray do
    begin
      mRange := TJSONObject(mEdit).GetValue('range') as TJSONObject;
      mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
        TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mEdit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, mEdits);
  end;
end;

/// <summary>Context mit der Richtung ADirection.</summary>
function ContextFor(const AIndex: ISymbolIndex; const ADirection: string): TMoveMemberContext;
begin
  Result := Context(AIndex);
  Result.Direction := ADirection;
end;

function Run(const AIndex: ISymbolIndex; const AFileName: string; ALine: Integer; const ADirection: string;
  ARequest: TJSONObject): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mContext: TMoveMemberContext;
begin
  mContext := ContextFor(AIndex, ADirection);
  mContext.Request := ARequest;
  mTree := TPascalParser.Parse(TextOf(AFileName));
  mResolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspMoveMember.Execute(mResolver, mTree, AFileName, TextOf(AFileName), TTextPosition.Create(ALine, 6),
      mContext);
  finally
    mResolver.Free;
    mTree.Free;
    ARequest.Free;
  end;
end;

procedure FreeAll(const AItems: TArray<TJSONObject>);
var
  mItem: TJSONObject;
begin
  for mItem in AItems do
  begin
    mItem.Free;
  end;
end;

procedure TLspMoveMemberTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitClasses, cClassesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKind, cKindFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TLspMoveMemberTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspMoveMemberTests.OffersByHierarchy;
var
  mTree: TSyntaxTree;
  mActions: TArray<TJSONObject>;
begin
  mTree := TPascalParser.Parse(cUnitKind);
  try
    mActions := TLspMoveMember.Actions(mTree, cUnitKind, cKindFile, 'file:///C:/P/Kind.pas',
      TTextPosition.Create(12, 6), FIndex);
    try
      // TChild hat einen Vorfahren im Projekt, aber keine Nachfahren.
      Assert.AreEqual(1, Integer(Length(mActions)));
      Assert.AreEqual('„Fill“ in Vorfahr verschieben …', mActions[0].GetValue('title').Value);
      Assert.AreEqual(TLspMoveMember.cClientCommand,
        (mActions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      FreeAll(mActions);
    end;
    Assert.AreEqual(0, Integer(Length(TLspMoveMember.Actions(mTree, cUnitKind, cKindFile, 'u',
      TTextPosition.Create(7, 4), FIndex))), 'Kopfzeile');
    // THelper hat weder Vorfahren noch Nachfahren im Projekt; leere Klasse: nichts.
    Assert.AreEqual(0, Integer(Length(TLspMoveMember.Actions(mTree, cUnitKind, cKindFile, 'u',
      TTextPosition.Create(5, 4), FIndex))), 'THelper');
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(cUnitBasis);
  try
    mActions := TLspMoveMember.Actions(mTree, cUnitBasis, cBasisFile, 'u', TTextPosition.Create(5, 6), FIndex);
    try
      Assert.AreEqual(1, Integer(Length(mActions)));
      Assert.AreEqual('„Show“ in Nachfahren verschieben …', mActions[0].GetValue('title').Value);
    finally
      FreeAll(mActions);
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLspMoveMemberTests.PrepareListsTargets;
var
  mTree: TSyntaxTree;
  mAnswer: TJSONObject;
  mTargets, mCandidates: TJSONArray;
begin
  mTree := TPascalParser.Parse(cUnitKind);
  mAnswer := nil;
  try
    mAnswer := TLspMoveMember.Prepare(mTree, cUnitKind, cKindFile, TTextPosition.Create(12, 6), ContextFor(FIndex, 'up'));
    Assert.AreEqual('TChild', mAnswer.GetValue('className').Value);
    Assert.AreEqual('Fill', mAnswer.GetValue('member').Value);
    mTargets := mAnswer.GetValue('targets') as TJSONArray;
    Assert.AreEqual(1, mTargets.Count);
    Assert.AreEqual('TBase', (mTargets.Items[0] as TJSONObject).GetValue('name').Value);
    Assert.AreEqual('Basis', (mTargets.Items[0] as TJSONObject).GetValue('unit').Value);
    mCandidates := mAnswer.GetValue('candidates') as TJSONArray;
    Assert.AreEqual(3, mCandidates.Count);
    Assert.IsTrue(((mCandidates.Items[2] as TJSONObject).GetValue('checked') as TJSONBool).AsBoolean);
    Assert.IsFalse(((mCandidates.Items[0] as TJSONObject).GetValue('checked') as TJSONBool).AsBoolean);
    Assert.AreEqual('overrideSiblings', ((mAnswer.GetValue('option') as TJSONObject).GetValue('kind')).Value);
    Assert.WillRaise(
      procedure
      begin
        TLspMoveMember.Prepare(mTree, cUnitKind, cKindFile, TTextPosition.Create(12, 6), ContextFor(FIndex, 'down')).Free;
      end, EJsonRpcError);
  finally
    mAnswer.Free;
    mTree.Free;
  end;
end;

procedure TLspMoveMemberTests.PullsUpIntoOtherUnitWithUses;
var
  mAnswer: TJSONObject;
  mBasis, mKind: string;
begin
  // FItems (Id 0) und Fill (Id 2).
  mAnswer := Run(FIndex, cKindFile, 12, 'up', Request([0, 2], 'TBase', True));
  try
    mBasis := After(mAnswer, cBasisFile);
    mKind := After(mAnswer, cKindFile);
    Assert.IsTrue(ContainsStr(mBasis, 'uses'#10'  System.Classes;'), mBasis);
    Assert.IsTrue(ContainsStr(mBasis, '  private'#10'    FItems: TStrings;'#10'  public'#10'    procedure Show;'#10 +
      '    procedure Fill;'), mBasis);
    Assert.IsTrue(ContainsStr(mBasis, 'procedure TBase.Fill;'), mBasis);
    Assert.IsFalse(ContainsStr(mKind, 'FItems'), mKind);
    Assert.IsFalse(ContainsStr(mKind, 'Fill'), mKind);
    Assert.AreEqual(2, (mAnswer.GetValue('moved') as TJSONNumber).AsInt);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspMoveMemberTests.RefusesCircularReference;
var
  mMessage_: string;
begin
  // FHelper (Id 1) hat den Typ THelper aus Kind: Basis muesste Kind im interface einbinden.
  mMessage_ := '';
  try
    Run(FIndex, cKindFile, 10, 'up', Request([1], 'TBase', True)).Free;
  except
    on E: EJsonRpcError do
      mMessage_ := E.Message;
  end;
  Assert.IsTrue(ContainsStr(mMessage_, 'Kreisverweis'), mMessage_);
end;

procedure TLspMoveMemberTests.PushDownRefusedByForeignUse;
var
  mMessage_: string;
begin
  mMessage_ := '';
  try
    Run(FIndex, cBasisFile, 5, 'down', Request([0], 'TChild', False)).Free;
  except
    on E: EJsonRpcError do
      mMessage_ := E.Message;
  end;
  Assert.IsTrue(ContainsStr(mMessage_, 'Main.pas:9'), mMessage_);
end;

procedure TLspMoveMemberTests.PushDownKeepsAbstract;
var
  mAnswer: TJSONObject;
  mBasis, mKind: string;
begin
  mAnswer := Run(FIndex, cBasisFile, 5, 'down', Request([0], 'TChild', True));
  try
    mBasis := After(mAnswer, cBasisFile);
    mKind := After(mAnswer, cKindFile);
    Assert.IsTrue(ContainsStr(mBasis, 'procedure Show; virtual; abstract;'), mBasis);
    Assert.IsFalse(ContainsStr(mBasis, 'procedure TBase.Show;'), mBasis);
    Assert.IsTrue(ContainsStr(mKind, '    procedure Fill;'#10'    procedure Show; override;'#10'  end;'), mKind);
    Assert.IsTrue(ContainsStr(mKind, 'procedure TChild.Show;'), mKind);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMoveMemberTests);

end.
