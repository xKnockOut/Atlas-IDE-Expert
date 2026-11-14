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
  System.Generics.Collections,
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
  cKundenFile = 'C:\P\Kunden.pas';
  cAufruferFile = 'C:\P\Aufrufer.pas';
  cFremdFile = 'C:\P\Fremd.pas';
  cAndereFile = 'C:\P\Andere.pas';
  cKunden =
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

  cAufrufer =
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
  cAndere =
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
  cFremd =
    'unit Fremd;'#10 +
    'interface'#10 +
    '// Kunden'#10 +
    'implementation'#10 +
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cAufruferFile) then
  begin
    AText := cAufrufer;
  end
  else if SameText(AFileName, cKundenFile) then
  begin
    AText := cKunden;
  end
  else if SameText(AFileName, cFremdFile) then
  begin
    AText := cFremd;
  end
  else if SameText(AFileName, cAndereFile) then
  begin
    AText := cAndere;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TLspTypeAliasTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cKunden, cKundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cAufrufer, cAufruferFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cFremd, cFremdFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cAndere, cAndereFile, nil));
end;

procedure TLspTypeAliasTests.TearDown;
begin
  FIndex := nil;
end;

function ActionsAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(cKunden);
  mResolver := TNameResolver.Create(AIndex);
  try
    mResolver.PinTree(mTree, cKundenFile);
    try
      Result := TLspTypeAlias.Actions(mTree, cKunden, TDocumentUris.FromPath(cKundenFile),
        TTextPosition.Create(ALine, ACharacter), TTypeAliasScope.InUnit, TLspTypeAlias.Lookup(mResolver));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function Context(const AIndex: ISymbolIndex): TTypeAliasContext;
begin
  Result := Default(TTypeAliasContext);
  Result.Index := AIndex;
  Result.Files := [cKundenFile, cAufruferFile, cFremdFile, cAndereFile];
  Result.ReadText := ReadFile;
end;

function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AName, AScope: string): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mRequest: TTypeAliasContext;
begin
  mRequest := Context(AIndex);
  mRequest.Name := AName;
  mRequest.Scope := AScope;
  mTree := TPascalParser.Parse(cKunden);
  mResolver := TNameResolver.Create(AIndex);
  try
    Result := TLspTypeAlias.Execute(mResolver, mTree, cKundenFile, cKunden, TTextPosition.Create(ALine, ACharacter),
      mRequest);
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function ExecuteInlineAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(cKunden);
  mResolver := TNameResolver.Create(AIndex);
  try
    Result := TLspTypeAlias.ExecuteInline(mResolver, mTree, cKundenFile, cKunden, TTextPosition.Create(ALine,
      ACharacter), Context(AIndex));
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  mAction: TJSONObject;
begin
  for mAction in AActions do
  begin
    mAction.Free;
  end;
end;

procedure TLspTypeAliasTests.ActionsOfferScopes;
var
  mActions: TArray<TJSONObject>;
  mArguments: TJSONArray;
begin
  // Auf TDictionary in FAktive.
  mActions := ActionsAt(FIndex, 11, 15);
  try
    Assert.AreEqual(3, Integer(Length(mActions)));
    Assert.AreEqual('Typ-Alias einführen (TDictionary<string, TKunde>)', mActions[0].GetValue<string>('title'));
    Assert.AreEqual('Typ-Alias einführen, nur diese Stelle (TDictionary<string, TKunde>)',
      mActions[1].GetValue<string>('title'));
    Assert.AreEqual('Typ-Alias einführen, im Projekt (TDictionary<string, TKunde>)',
      mActions[2].GetValue<string>('title'));
    Assert.AreEqual(TLspTypeAlias.cIntroduceKind, mActions[0].GetValue<string>('kind'));
    Assert.AreEqual(TLspTypeAlias.cClientCommand, mActions[0].GetValue<string>('command.command'));
    mArguments := mActions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(4, mArguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(cKundenFile), mArguments.Items[0].Value);
    Assert.AreEqual(11, mArguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual(13, mArguments.Items[1].GetValue<Integer>('character'));
    Assert.AreEqual('TKundeAktive', mArguments.Items[2].Value);
    Assert.AreEqual('unit', mArguments.Items[3].Value);
    Assert.AreEqual('project', mActions[2].GetValue<TJSONArray>('command.arguments').Items[3].Value);
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspTypeAliasTests.OpenParamsGiveDisabledAction;
var
  mActions: TArray<TJSONObject>;
begin
  mActions := ActionsAt(FIndex, 8, 15);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.IsNull(mActions[0].GetValue('command'));
    Assert.AreEqual(Format(TTypeAlias.OpenParamsReason, ['T']), mActions[0].GetValue<string>('disabled.reason'));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspTypeAliasTests.InlineActionOnAliasName;
var
  mActions: TArray<TJSONObject>;
  mArguments: TJSONArray;
begin
  mActions := ActionsAt(FIndex, 6, 5);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual('Alias auflösen (TKundenListe)', mActions[0].GetValue<string>('title'));
    Assert.AreEqual(TLspTypeAlias.cInlineKind, mActions[0].GetValue<string>('kind'));
    Assert.AreEqual(TLspTypeAlias.cInlineClientCommand, mActions[0].GetValue<string>('command.command'));
    mArguments := mActions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(2, mArguments.Count);
    Assert.AreEqual(6, mArguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual(2, mArguments.Items[1].GetValue<Integer>('character'));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspTypeAliasTests.ExecuteProjectMatchesQualifiedNames;
var
  mAnswer: TJSONObject;
  mJson: string;
begin
  mAnswer := ExecuteAt(FIndex, 11, 15, 'TKundenMap', 'project');
  try
    mJson := mAnswer.ToJSON;
    Assert.AreEqual(2, mAnswer.GetValue<Integer>('files'), mJson);
    Assert.AreEqual(2, mAnswer.GetValue<Integer>('places'), mJson);
    Assert.IsTrue(Pos(TDocumentUris.FromPath(cAufruferFile), mJson) > 0, mJson);
    Assert.IsFalse(Pos('Fremd', mJson) > 0, mJson);
    Assert.IsFalse(Pos('Andere', mJson) > 0, mJson);
    Assert.IsTrue(Pos('TKundenMap = TDictionary<string, TKunde>;', mJson) > 0, mJson);
    Assert.IsTrue(Pos('"needsConfirmation":true', mJson) > 0, mJson);
    Assert.IsTrue(mAnswer.GetValue<string>('preview').StartsWith('TKundenMap = TDictionary<string, TKunde>;'), mJson);
  finally
    mAnswer.Free;
  end;
  // Nur in der Unit: Aufrufer bleibt.
  mAnswer := ExecuteAt(FIndex, 11, 15, 'TKundenMap', 'unit');
  try
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('files'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspTypeAliasTests.ExecuteInlineChangesOtherUnit;
var
  mAnswer: TJSONObject;
  mJson: string;
begin
  mAnswer := ExecuteInlineAt(FIndex, 6, 5);
  try
    mJson := mAnswer.ToJSON;
    Assert.AreEqual(2, mAnswer.GetValue<Integer>('files'), mJson);
    Assert.AreEqual(2, mAnswer.GetValue<Integer>('places'), mJson);
    Assert.IsTrue(Pos(TDocumentUris.FromPath(cAufruferFile), mJson) > 0, mJson);
    Assert.IsTrue(Pos('"newText":"TList<TKunde>"', mJson) > 0, mJson);
    Assert.IsTrue(mAnswer.GetValue<string>('preview').EndsWith('der Alias entfällt.') or
      (Pos('der Alias entfällt.', mAnswer.GetValue<string>('preview')) > 0), mJson);
  finally
    mAnswer.Free;
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
