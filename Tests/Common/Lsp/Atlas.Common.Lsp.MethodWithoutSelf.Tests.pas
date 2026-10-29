unit Atlas.Common.Lsp.MethodWithoutSelf.Tests;

// „Methode ohne Self umwandeln“ über das Protokoll (#686): Code-Aktionen mit
// Client-Befehl, keine Aktion bei implizitem Zugriff auf ein Feld (über die
// Namensauflösung) oder bei einem Ereignis der Formulardatei, Antwort des
// Server-Befehls über zwei Units samt Vorschau, Warnung bei sichtbarem
// Helper, Fehler mit Grund, Marken.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspMethodWithoutSelfTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActionsCarryClientCommand;
    [Test]
    procedure ImplicitFieldAndFormEventGiveNoAction;
    [Test]
    procedure ExecuteChangesBothUnits;
    [Test]
    procedure HelperWarnsAboutRtlHelper;
    [Test]
    procedure ErrorsCarryReason;
    [Test]
    procedure MarkersAtHeaderEnd;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Lsp.MethodWithoutSelf;

const
  KundenFile = 'C:\P\Kunden.pas';
  AufruferFile = 'C:\P\Aufrufer.pas';
  FormFile = 'C:\P\Kunden.dfm';
  Kunden =
    'unit Kunden;'#10 +                                                  // 0
    'interface'#10 +                                                     // 1
    'uses System.SysUtils;'#10 +                                         // 2
    'type'#10 +                                                          // 3
    '  TKunde = class'#10 +                                              // 4
    '  private'#10 +                                                     // 5
    '    FName: string;'#10 +                                            // 6
    '  public'#10 +                                                      // 7
    '    function IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 8
    '    procedure Zeige;'#10 +                                          // 9
    '    procedure Knopf(Sender: TObject);'#10 +                         // 10
    '  end;'#10 +                                                        // 11
    'implementation'#10 +                                                // 12
    'procedure TKunde.Zeige;'#10 +                                       // 13
    'begin'#10 +                                                         // 14
    '  if IsValidIban(FName, 2) then'#10 +                               // 15
    '    FName := '''';'#10 +                                            // 16
    'end;'#10 +                                                          // 17
    'function TKunde.IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 18
    'begin'#10 +                                                         // 19
    '  Result := S <> '''';'#10 +                                        // 20
    'end;'#10 +                                                          // 21
    'procedure TKunde.Knopf(Sender: TObject);'#10 +                      // 22
    'begin'#10 +                                                         // 23
    'end;'#10 +                                                          // 24
    'end.'#10;

  Aufrufer =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Kunden;'#10 +
    'procedure Pruefe(K: TKunde; const T: string);'#10 +
    'begin'#10 +
    '  if K.IsValidIban(T, 3) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, FormFile) then
    AText := 'object Kunde: TKunde'#10'  OnClick = Knopf'#10'end'#10
  else if SameText(AFileName, AufruferFile) then
    AText := Aufrufer
  else if SameText(AFileName, KundenFile) then
    AText := Kunden
  else
    Result := False;
end;

procedure TLspMethodWithoutSelfTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(Kunden, KundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(Aufrufer, AufruferFile, nil));
end;

procedure TLspMethodWithoutSelfTests.TearDown;
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
      Result := TLspMethodWithoutSelf.Actions(Tree, Kunden, TDocumentUris.FromPath(KundenFile),
        TTextPosition.Create(ALine, ACharacter), TLspMethodWithoutSelf.Lookup(Resolver, Tree, KundenFile, ReadFile));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AConversion: string): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Context: TMethodKindContext;
begin
  Context := Default(TMethodKindContext);
  Context.Index := AIndex;
  Context.Files := [KundenFile, AufruferFile];
  Context.ReadText := ReadFile;
  Context.WithStatic := True;
  Tree := TPascalParser.Parse(Kunden);
  Resolver := TNameResolver.Create(AIndex);
  try
    Result := TLspMethodWithoutSelf.Execute(Resolver, Tree, KundenFile, Kunden, TTextPosition.Create(ALine,
      ACharacter), AConversion, Context, TFormatStyle.Default);
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

procedure TLspMethodWithoutSelfTests.ActionsCarryClientCommand;
var
  Actions: TArray<TJSONObject>;
  Arguments: TJSONArray;
begin
  Actions := ActionsAt(FIndex, 18, 20);
  try
    Assert.AreEqual(4, Integer(Length(Actions)));
    Assert.AreEqual(TMethodWithoutSelf.ClassMethodTitle, Actions[0].GetValue<string>('title'));
    Assert.AreEqual('In class-Methode umwandeln, Aufrufe über TKunde', Actions[1].GetValue<string>('title'));
    Assert.AreEqual(TMethodWithoutSelf.RoutineTitle, Actions[2].GetValue<string>('title'));
    Assert.AreEqual('In Record-Helper für string verschieben', Actions[3].GetValue<string>('title'));
    Assert.AreEqual(TLspMethodWithoutSelf.Kind, Actions[0].GetValue<string>('kind'));
    Assert.AreEqual(TLspMethodWithoutSelf.ClientCommand, Actions[2].GetValue<string>('command.command'));
    Arguments := Actions[2].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, Arguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(KundenFile), Arguments.Items[0].Value);
    Assert.AreEqual(18, Arguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual('routine', Arguments.Items[2].Value);
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspMethodWithoutSelfTests.ImplicitFieldAndFormEventGiveNoAction;
begin
  // Zeige liest FName ohne Self.
  Assert.AreEqual(0, Integer(Length(ActionsAt(FIndex, 13, 20))));
  // Knopf steht in Kunden.dfm.
  Assert.AreEqual(0, Integer(Length(ActionsAt(FIndex, 22, 20))));
end;

procedure TLspMethodWithoutSelfTests.ExecuteChangesBothUnits;
var
  Answer: TJSONObject;
  Json: string;
begin
  Answer := ExecuteAt(FIndex, 18, 20, 'routine');
  try
    Json := Answer.ToJSON;
    Assert.AreEqual(2, Answer.GetValue<Integer>('files'), Json);
    Assert.AreEqual(1, Answer.GetValue<Integer>('calls'), Json);
    Assert.IsTrue(Pos('"newText":"function IsValidIban(const S: string; N: Integer): Boolean;\n\n"', Json) > 0,
      Json);
    Assert.IsTrue(Pos(TDocumentUris.FromPath(AufruferFile), Json) > 0, Json);
    Assert.IsTrue(Pos('"needsConfirmation":true', Json) > 0, Json);
    Assert.IsTrue(Answer.GetValue<string>('preview').StartsWith('TKunde.IsValidIban wird freie Routine'), Json);
    Assert.IsTrue(Pos('Aufrufer.pas, Zeile 7: if K.IsValidIban(T, 3) then', Answer.GetValue<string>('preview')) > 0,
      Json);
  finally
    Answer.Free;
  end;
  Answer := ExecuteAt(FIndex, 18, 20, 'classMethod');
  try
    Json := Answer.ToJSON;
    Assert.AreEqual(1, Answer.GetValue<Integer>('files'), Json);
    Assert.IsTrue(Pos('" static;"', Json) > 0, Json);
  finally
    Answer.Free;
  end;
end;

procedure TLspMethodWithoutSelfTests.HelperWarnsAboutRtlHelper;
var
  Answer: TJSONObject;
begin
  Answer := ExecuteAt(FIndex, 18, 20, 'helper');
  try
    Assert.AreEqual(1, Answer.GetValue<TJSONArray>('warnings').Count, Answer.ToJSON);
    Assert.IsTrue(Pos('TStringHelper', Answer.GetValue<TJSONArray>('warnings').Items[0].Value) > 0, Answer.ToJSON);
    Assert.IsTrue(Pos('TKundenStringHelper = record helper for string', Answer.ToJSON) > 0, Answer.ToJSON);
    Assert.IsTrue(Pos('"newText":"T.IsValidIban(3)"', Answer.ToJSON) > 0, Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspMethodWithoutSelfTests.ErrorsCarryReason;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 18, 20, 'unbekannt').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 13, 20, 'routine').Free;
    end, EJsonRpcError);
end;

procedure TLspMethodWithoutSelfTests.MarkersAtHeaderEnd;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Found: TArray<TTextPosition>;
begin
  Tree := TPascalParser.Parse(Kunden);
  Resolver := TNameResolver.Create(FIndex);
  try
    Resolver.PinTree(Tree, KundenFile);
    try
      Found := TLspMethodWithoutSelf.Markers(Tree, Kunden, TTextRange.Create(TTextPosition.Create(0, 0),
        TTextPosition.Create(30, 0)), TLspMethodWithoutSelf.Lookup(Resolver, Tree, KundenFile, ReadFile));
      Assert.AreEqual(1, Integer(Length(Found)));
      Assert.AreEqual(18, Found[0].Line);
      Assert.AreEqual(66, Found[0].Character);
      Found := TLspMethodWithoutSelf.Markers(Tree, Kunden, TTextRange.Create(TTextPosition.Create(0, 0),
        TTextPosition.Create(10, 0)), TLspMethodWithoutSelf.Lookup(Resolver, Tree, KundenFile, ReadFile));
      Assert.AreEqual(0, Integer(Length(Found)));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMethodWithoutSelfTests);

end.
