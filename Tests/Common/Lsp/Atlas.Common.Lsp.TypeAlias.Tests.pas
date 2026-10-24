unit Atlas.Common.Lsp.TypeAlias.Tests;

// Typ-Alias über das Protokoll (#681): Code-Aktionen mit Reichweiten und
// Client-Befehl, abgeschaltete Aktion bei offenen generischen Parametern,
// Aktion zum Auflösen, Antwort des Server-Befehls über zwei Units mit
// Gleichheit über die Namensauflösung (TKunde und Kunden.TKunde gleich, ein
// eigenes TKunde einer anderen Unit nicht), Auflösen
// über die Referenzsuche, Fehler mit Grund.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspTypeAliasTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActionsOfferScopes;
    [Test]
    procedure OpenParamsGiveDisabledAction;
    [Test]
    procedure InlineActionOnAliasName;
    [Test]
    procedure ExecuteProjectMatchesQualifiedNames;
    [Test]
    procedure ExecuteInlineChangesOtherUnit;
    [Test]
    procedure ErrorsCarryReason;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.TypeAlias,
  Atlas.Common.Lsp.TypeAlias;

const
  KundenFile = 'C:\P\Kunden.pas';
  AufruferFile = 'C:\P\Aufrufer.pas';
  FremdFile = 'C:\P\Fremd.pas';
  AndereFile = 'C:\P\Andere.pas';
  Kunden =
    'unit Kunden;'#10 +                                       // 0
    'interface'#10 +                                          // 1
    'uses System.Generics.Collections;'#10 +                  // 2
    'type'#10 +                                               // 3
    '  TKunde = class'#10 +                                   // 4
    '  end;'#10 +                                             // 5
    '  TKundenListe = TList<TKunde>;'#10 +                    // 6
    '  TBox<T> = class'#10 +                                  // 7
    '    FItems: TList<T>;'#10 +                              // 8
    '  end;'#10 +                                             // 9
    '  TVerwaltung = class'#10 +                              // 10
    '    FAktive: TDictionary<string, TKunde>;'#10 +          // 11
    '    FListe: TKundenListe;'#10 +                          // 12
    '  end;'#10 +                                             // 13
    'implementation'#10 +                                     // 14
    'end.'#10;

  Aufrufer =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'uses System.Generics.Collections, Kunden;'#10 +
    'type'#10 +
    '  TAnzeige = class'#10 +
    '    FDaten: TDictionary<string, Kunden.TKunde>;'#10 +
    '    FListe: TKundenListe;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.'#10;

  // Eigenes TKunde: derselbe Text, ein anderer Typ.
  Andere =
    'unit Andere;'#10 +
    'interface'#10 +
    'uses System.Generics.Collections, Kunden;'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  end;'#10 +
    '  TSicht = class'#10 +
    '    FDaten: TDictionary<string, TKunde>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.'#10;

  // Nennt Kunden nur im Kommentar und bleibt deshalb unberührt.
  Fremd =
    'unit Fremd;'#10 +
    'interface'#10 +
    '// Kunden'#10 +
    'implementation'#10 +
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, AufruferFile) then
    AText := Aufrufer
  else if SameText(AFileName, KundenFile) then
    AText := Kunden
  else if SameText(AFileName, FremdFile) then
    AText := Fremd
  else if SameText(AFileName, AndereFile) then
    AText := Andere
  else
    Result := False;
end;

procedure TLspTypeAliasTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(Kunden, KundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(Aufrufer, AufruferFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(Fremd, FremdFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(Andere, AndereFile, nil));
end;

procedure TLspTypeAliasTests.TearDown;
begin
  FIndex := nil;
end;

function ActionsAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(Kunden);
  Resolver := TNameResolver.Create(AIndex);
  try
    Resolver.PinTree(Tree, KundenFile);
    try
      Result := TLspTypeAlias.Actions(Tree, Kunden, TDocumentUris.FromPath(KundenFile),
        TTextPosition.Create(ALine, ACharacter), TTypeAliasScope.InUnit, TLspTypeAlias.Lookup(Resolver));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function Context(const AIndex: ISymbolIndex): TTypeAliasContext;
begin
  Result := Default(TTypeAliasContext);
  Result.Index := AIndex;
  Result.Files := [KundenFile, AufruferFile, FremdFile, AndereFile];
  Result.ReadText := ReadFile;
end;

function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AName, AScope: string): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(Kunden);
  Resolver := TNameResolver.Create(AIndex);
  try
    Result := TLspTypeAlias.Execute(Resolver, Tree, KundenFile, Kunden, TTextPosition.Create(ALine, ACharacter),
      AName, AScope, Context(AIndex));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function ExecuteInlineAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(Kunden);
  Resolver := TNameResolver.Create(AIndex);
  try
    Result := TLspTypeAlias.ExecuteInline(Resolver, Tree, KundenFile, Kunden, TTextPosition.Create(ALine,
      ACharacter), Context(AIndex));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  Action: TJSONObject;
begin
  for Action in AActions do
    Action.Free;
end;

procedure TLspTypeAliasTests.ActionsOfferScopes;
var
  Actions: TArray<TJSONObject>;
  Arguments: TJSONArray;
begin
  // Auf TDictionary in FAktive.
  Actions := ActionsAt(FIndex, 11, 15);
  try
    Assert.AreEqual(3, Integer(Length(Actions)));
    Assert.AreEqual('Typ-Alias einführen (TDictionary<string, TKunde>)', Actions[0].GetValue<string>('title'));
    Assert.AreEqual('Typ-Alias einführen, nur diese Stelle (TDictionary<string, TKunde>)',
      Actions[1].GetValue<string>('title'));
    Assert.AreEqual('Typ-Alias einführen, im Projekt (TDictionary<string, TKunde>)',
      Actions[2].GetValue<string>('title'));
    Assert.AreEqual(TLspTypeAlias.IntroduceKind, Actions[0].GetValue<string>('kind'));
    Assert.AreEqual(TLspTypeAlias.ClientCommand, Actions[0].GetValue<string>('command.command'));
    Arguments := Actions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(4, Arguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(KundenFile), Arguments.Items[0].Value);
    Assert.AreEqual(11, Arguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual(13, Arguments.Items[1].GetValue<Integer>('character'));
    Assert.AreEqual('TKundeAktive', Arguments.Items[2].Value);
    Assert.AreEqual('unit', Arguments.Items[3].Value);
    Assert.AreEqual('project', Actions[2].GetValue<TJSONArray>('command.arguments').Items[3].Value);
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspTypeAliasTests.OpenParamsGiveDisabledAction;
var
  Actions: TArray<TJSONObject>;
begin
  Actions := ActionsAt(FIndex, 8, 15);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.IsNull(Actions[0].GetValue('command'));
    Assert.AreEqual(Format(TTypeAlias.OpenParamsReason, ['T']), Actions[0].GetValue<string>('disabled.reason'));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspTypeAliasTests.InlineActionOnAliasName;
var
  Actions: TArray<TJSONObject>;
  Arguments: TJSONArray;
begin
  Actions := ActionsAt(FIndex, 6, 5);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual('Alias auflösen (TKundenListe)', Actions[0].GetValue<string>('title'));
    Assert.AreEqual(TLspTypeAlias.InlineKind, Actions[0].GetValue<string>('kind'));
    Assert.AreEqual(TLspTypeAlias.InlineClientCommand, Actions[0].GetValue<string>('command.command'));
    Arguments := Actions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(2, Arguments.Count);
    Assert.AreEqual(6, Arguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual(2, Arguments.Items[1].GetValue<Integer>('character'));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspTypeAliasTests.ExecuteProjectMatchesQualifiedNames;
var
  Answer: TJSONObject;
  Json: string;
begin
  Answer := ExecuteAt(FIndex, 11, 15, 'TKundenMap', 'project');
  try
    Json := Answer.ToJSON;
    Assert.AreEqual(2, Answer.GetValue<Integer>('files'), Json);
    Assert.AreEqual(2, Answer.GetValue<Integer>('places'), Json);
    Assert.IsTrue(Pos(TDocumentUris.FromPath(AufruferFile), Json) > 0, Json);
    Assert.IsFalse(Pos('Fremd', Json) > 0, Json);
    Assert.IsFalse(Pos('Andere', Json) > 0, Json);
    Assert.IsTrue(Pos('TKundenMap = TDictionary<string, TKunde>;', Json) > 0, Json);
    Assert.IsTrue(Pos('"needsConfirmation":true', Json) > 0, Json);
    Assert.IsTrue(Answer.GetValue<string>('preview').StartsWith('TKundenMap = TDictionary<string, TKunde>;'), Json);
  finally
    Answer.Free;
  end;
  // Nur in der Unit: Aufrufer bleibt.
  Answer := ExecuteAt(FIndex, 11, 15, 'TKundenMap', 'unit');
  try
    Assert.AreEqual(1, Answer.GetValue<Integer>('files'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspTypeAliasTests.ExecuteInlineChangesOtherUnit;
var
  Answer: TJSONObject;
  Json: string;
begin
  Answer := ExecuteInlineAt(FIndex, 6, 5);
  try
    Json := Answer.ToJSON;
    Assert.AreEqual(2, Answer.GetValue<Integer>('files'), Json);
    Assert.AreEqual(2, Answer.GetValue<Integer>('places'), Json);
    Assert.IsTrue(Pos(TDocumentUris.FromPath(AufruferFile), Json) > 0, Json);
    Assert.IsTrue(Pos('"newText":"TList<TKunde>"', Json) > 0, Json);
    Assert.IsTrue(Answer.GetValue<string>('preview').EndsWith('der Alias entfällt.') or
      (Pos('der Alias entfällt.', Answer.GetValue<string>('preview')) > 0), Json);
  finally
    Answer.Free;
  end;
end;

procedure TLspTypeAliasTests.ErrorsCarryReason;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 11, 15, 'TKundenMap', 'unbekannt').Free;
    end, EJsonRpcError);
  // Der Name ist schon vergeben.
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 11, 15, 'TKunde', 'unit').Free;
    end, EJsonRpcError);
  // TVerwaltung ist kein Alias.
  Assert.WillRaise(
    procedure
    begin
      ExecuteInlineAt(FIndex, 10, 5).Free;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTypeAliasTests);

end.
