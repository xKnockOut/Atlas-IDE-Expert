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
  ClassesFile = 'C:\L\System.Classes.pas';
  BasisFile = 'C:\P\Basis.pas';
  KindFile = 'C:\P\Kind.pas';
  MainFile = 'C:\P\Main.pas';

  UnitClasses =
    'unit System.Classes;'#10'interface'#10'type'#10'  TStrings = class'#10'  end;'#10 +
    'implementation'#10'end.'#10;
  UnitBasis =
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
  UnitKind =
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
  UnitMain =
    'unit Main;'#10'interface'#10'uses'#10'  Basis;'#10'implementation'#10#10 +
    'procedure Go(B: TBase);'#10'begin'#10'  B.Show;'#10'end;'#10#10 +
    'end.'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, ClassesFile) then
    Result := UnitClasses
  else if SameText(AFileName, BasisFile) then
    Result := UnitBasis
  else if SameText(AFileName, KindFile) then
    Result := UnitKind
  else if SameText(AFileName, MainFile) then
    Result := UnitMain
  else
    Result := '';
end;

function Context(const AIndex: ISymbolIndex): TMoveMemberContext;
begin
  Result := Default(TMoveMemberContext);
  Result.Index := AIndex;
  Result.Files := [BasisFile, KindFile, MainFile];
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
end;

function Request(const AMembers: array of Integer; const ATarget: string; AOption: Boolean): TJSONObject;
var
  Members, Targets: TJSONArray;
  Id: Integer;
begin
  Result := TJSONObject.Create;
  Members := TJSONArray.Create;
  for Id in AMembers do
    Members.AddElement(TJSONNumber.Create(Id));
  Result.AddPair('members', Members);
  Targets := TJSONArray.Create;
  Targets.Add(ATarget);
  Result.AddPair('targets', Targets);
  Result.AddPair('option', TJSONBool.Create(AOption));
end;

/// <summary>Text von AFileName nach dem WorkspaceEdit in AAnswer.</summary>
function After(AAnswer: TJSONObject; const AFileName: string): string;
var
  Item, Edit: TJSONValue;
  Document, Range: TJSONObject;
  Edits: TArray<TTextEdit>;
  Uri: string;
begin
  Result := TextOf(AFileName);
  for Item in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    Document := TJSONObject(Item);
    if Document.GetValue('textDocument') = nil then
      Continue;
    Uri := (Document.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(Uri), AFileName) then
      Continue;
    Edits := nil;
    for Edit in Document.GetValue('edits') as TJSONArray do
    begin
      Range := TJSONObject(Edit).GetValue('range') as TJSONObject;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(Range.GetValue('start')),
        TLspPositions.ReadPosition(Range.GetValue('end'))), TJSONObject(Edit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, Edits);
  end;
end;

function Run(const AIndex: ISymbolIndex; const AFileName: string; ALine: Integer; const ADirection: string;
  ARequest: TJSONObject): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(TextOf(AFileName));
  Resolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspMoveMember.Execute(Resolver, Tree, AFileName, TextOf(AFileName), TTextPosition.Create(ALine, 6),
      ADirection, ARequest, Context(AIndex));
  finally
    Resolver.Free;
    Tree.Free;
    ARequest.Free;
  end;
end;

procedure FreeAll(const AItems: TArray<TJSONObject>);
var
  Item: TJSONObject;
begin
  for Item in AItems do
    Item.Free;
end;

procedure TLspMoveMemberTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitClasses, ClassesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKind, KindFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TLspMoveMemberTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspMoveMemberTests.OffersByHierarchy;
var
  Tree: TSyntaxTree;
  Actions: TArray<TJSONObject>;
begin
  Tree := TPascalParser.Parse(UnitKind);
  try
    Actions := TLspMoveMember.Actions(True, Tree, UnitKind, KindFile, 'file:///C:/P/Kind.pas',
      TTextPosition.Create(12, 6), FIndex);
    try
      // TChild hat einen Vorfahren im Projekt, aber keine Nachfahren.
      Assert.AreEqual(1, Integer(Length(Actions)));
      Assert.AreEqual('„Fill“ in Vorfahr verschieben …', Actions[0].GetValue('title').Value);
      Assert.AreEqual(TLspMoveMember.ClientCommand,
        (Actions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      FreeAll(Actions);
    end;
    Assert.AreEqual(0, Integer(Length(TLspMoveMember.Actions(False, Tree, UnitKind, KindFile, 'u',
      TTextPosition.Create(12, 6), FIndex))), 'abgeschaltet');
    Assert.AreEqual(0, Integer(Length(TLspMoveMember.Actions(True, Tree, UnitKind, KindFile, 'u',
      TTextPosition.Create(7, 4), FIndex))), 'Kopfzeile');
    // THelper hat weder Vorfahren noch Nachfahren im Projekt; leere Klasse: nichts.
    Assert.AreEqual(0, Integer(Length(TLspMoveMember.Actions(True, Tree, UnitKind, KindFile, 'u',
      TTextPosition.Create(5, 4), FIndex))), 'THelper');
  finally
    Tree.Free;
  end;
  Tree := TPascalParser.Parse(UnitBasis);
  try
    Actions := TLspMoveMember.Actions(True, Tree, UnitBasis, BasisFile, 'u', TTextPosition.Create(5, 6), FIndex);
    try
      Assert.AreEqual(1, Integer(Length(Actions)));
      Assert.AreEqual('„Show“ in Nachfahren verschieben …', Actions[0].GetValue('title').Value);
    finally
      FreeAll(Actions);
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspMoveMemberTests.PrepareListsTargets;
var
  Tree: TSyntaxTree;
  Answer: TJSONObject;
  Targets, Candidates: TJSONArray;
begin
  Tree := TPascalParser.Parse(UnitKind);
  Answer := nil;
  try
    Answer := TLspMoveMember.Prepare(Tree, UnitKind, KindFile, TTextPosition.Create(12, 6), 'up', Context(FIndex));
    Assert.AreEqual('TChild', Answer.GetValue('className').Value);
    Assert.AreEqual('Fill', Answer.GetValue('member').Value);
    Targets := Answer.GetValue('targets') as TJSONArray;
    Assert.AreEqual(1, Targets.Count);
    Assert.AreEqual('TBase', (Targets.Items[0] as TJSONObject).GetValue('name').Value);
    Assert.AreEqual('Basis', (Targets.Items[0] as TJSONObject).GetValue('unit').Value);
    Candidates := Answer.GetValue('candidates') as TJSONArray;
    Assert.AreEqual(3, Candidates.Count);
    Assert.IsTrue(((Candidates.Items[2] as TJSONObject).GetValue('checked') as TJSONBool).AsBoolean);
    Assert.IsFalse(((Candidates.Items[0] as TJSONObject).GetValue('checked') as TJSONBool).AsBoolean);
    Assert.AreEqual('overrideSiblings', ((Answer.GetValue('option') as TJSONObject).GetValue('kind')).Value);
    Assert.WillRaise(
      procedure
      begin
        TLspMoveMember.Prepare(Tree, UnitKind, KindFile, TTextPosition.Create(12, 6), 'down', Context(FIndex)).Free;
      end, EJsonRpcError);
  finally
    Answer.Free;
    Tree.Free;
  end;
end;

procedure TLspMoveMemberTests.PullsUpIntoOtherUnitWithUses;
var
  Answer: TJSONObject;
  Basis, Kind: string;
begin
  // FItems (Id 0) und Fill (Id 2).
  Answer := Run(FIndex, KindFile, 12, 'up', Request([0, 2], 'TBase', True));
  try
    Basis := After(Answer, BasisFile);
    Kind := After(Answer, KindFile);
    Assert.IsTrue(ContainsStr(Basis, 'uses'#10'  System.Classes;'), Basis);
    Assert.IsTrue(ContainsStr(Basis, '  private'#10'    FItems: TStrings;'#10'  public'#10'    procedure Show;'#10 +
      '    procedure Fill;'), Basis);
    Assert.IsTrue(ContainsStr(Basis, 'procedure TBase.Fill;'), Basis);
    Assert.IsFalse(ContainsStr(Kind, 'FItems'), Kind);
    Assert.IsFalse(ContainsStr(Kind, 'Fill'), Kind);
    Assert.AreEqual(2, (Answer.GetValue('moved') as TJSONNumber).AsInt);
  finally
    Answer.Free;
  end;
end;

procedure TLspMoveMemberTests.RefusesCircularReference;
var
  Message_: string;
begin
  // FHelper (Id 1) hat den Typ THelper aus Kind: Basis muesste Kind im interface einbinden.
  Message_ := '';
  try
    Run(FIndex, KindFile, 10, 'up', Request([1], 'TBase', True)).Free;
  except
    on E: EJsonRpcError do
      Message_ := E.Message;
  end;
  Assert.IsTrue(ContainsStr(Message_, 'Kreisverweis'), Message_);
end;

procedure TLspMoveMemberTests.PushDownRefusedByForeignUse;
var
  Message_: string;
begin
  Message_ := '';
  try
    Run(FIndex, BasisFile, 5, 'down', Request([0], 'TChild', False)).Free;
  except
    on E: EJsonRpcError do
      Message_ := E.Message;
  end;
  Assert.IsTrue(ContainsStr(Message_, 'Main.pas:9'), Message_);
end;

procedure TLspMoveMemberTests.PushDownKeepsAbstract;
var
  Answer: TJSONObject;
  Basis, Kind: string;
begin
  Answer := Run(FIndex, BasisFile, 5, 'down', Request([0], 'TChild', True));
  try
    Basis := After(Answer, BasisFile);
    Kind := After(Answer, KindFile);
    Assert.IsTrue(ContainsStr(Basis, 'procedure Show; virtual; abstract;'), Basis);
    Assert.IsFalse(ContainsStr(Basis, 'procedure TBase.Show;'), Basis);
    Assert.IsTrue(ContainsStr(Kind, '    procedure Fill;'#10'    procedure Show; override;'#10'  end;'), Kind);
    Assert.IsTrue(ContainsStr(Kind, 'procedure TChild.Show;'), Kind);
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMoveMemberTests);

end.
