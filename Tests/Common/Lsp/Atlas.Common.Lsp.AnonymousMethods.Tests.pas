unit Atlas.Common.Lsp.AnonymousMethods.Tests;

// „Anonyme Methode und Methode umwandeln“ über das Protokoll (#680): Code-Aktion
// mit Client-Befehl und Vorschlag, Antwort des Server-Befehls mit Vorschau,
// Fehler mit Grund, Form nach der Einstellung, Zieltypen über die
// Namensauflösung (reference to, of object, Alias) beim Einbetten, Ereignis
// in der Formulardatei.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspAnonymousMethodsTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActionCarriesClientCommand;
    [Test]
    procedure ExecuteAnswersEditAndPreview;
    [Test]
    procedure ConflictIsAnError;
    [Test]
    procedure EmbedFollowsTargetType;
    [Test]
    procedure EmbedSkipsFormEvent;
    [Test]
    procedure CaptureSetting;
  end;

implementation

uses
  System.SysUtils,
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
  Atlas.Common.Editing.AnonymousMethods,
  Atlas.Common.Lsp.AnonymousMethods;

const
  FileName = 'C:\P\Haupt.pas';
  FormFile = 'C:\P\Haupt.dfm';
  Text =
    'unit Haupt;'#10 +                                               // 0
    'interface'#10 +                                                 // 1
    'type'#10 +                                                      // 2
    '  TAktion = reference to procedure(const AWert: Integer);'#10 + // 3
    '  TEreignis = procedure(Sender: TObject) of object;'#10 +       // 4
    '  TListe = class'#10 +                                          // 5
    '  public'#10 +                                                  // 6
    '    procedure ForEach(const AAktion: TAktion);'#10 +            // 7
    '    property OnTick: TEreignis read FOnTick write FOnTick;'#10 + // 8
    '  end;'#10 +                                                    // 9
    '  TKunde = class'#10 +                                          // 10
    '  private'#10 +                                                 // 11
    '    FListe: TListe;'#10 +                                       // 12
    '    FSumme: Integer;'#10 +                                      // 13
    '    procedure Addiere(const AWert: Integer);'#10 +              // 14
    '    procedure Tick(Sender: TObject);'#10 +                      // 15
    '    procedure Knopf(Sender: TObject);'#10 +                     // 16
    '  public'#10 +                                                  // 17
    '    procedure Run;'#10 +                                        // 18
    '  end;'#10 +                                                    // 19
    'implementation'#10 +                                            // 20
    'procedure TKunde.Run;'#10 +                                     // 21
    'begin'#10 +                                                     // 22
    '  FListe.ForEach(Addiere);'#10 +                                // 23
    '  FListe.OnTick := Tick;'#10 +                                  // 24
    '  FListe.ForEach(procedure(const AWert: Integer) begin FSumme := AWert; end);'#10 + // 25
    '  FListe.OnTick := Knopf;'#10 +                                 // 26
    'end;'#10 +                                                      // 27
    'procedure TKunde.Addiere(const AWert: Integer);'#10 +           // 28
    'begin'#10 +                                                     // 29
    '  FSumme := FSumme + AWert;'#10 +                               // 30
    'end;'#10 +                                                      // 31
    'procedure TKunde.Tick(Sender: TObject);'#10 +                   // 32
    'begin'#10 +                                                     // 33
    'end;'#10 +                                                      // 34
    'procedure TKunde.Knopf(Sender: TObject);'#10 +                  // 35
    'begin'#10 +                                                     // 36
    'end;'#10 +                                                      // 37
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, FormFile);
  if Result then
    AText := 'object Kunde: TKunde'#10'  OnClick = Knopf'#10'end'#10;
end;

procedure TLspAnonymousMethodsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(Text, FileName, nil));
end;

procedure TLspAnonymousMethodsTests.TearDown;
begin
  FIndex := nil;
end;

/// <summary>Aktionen an ALine/ACharacter mit Namensauflösung.</summary>
function ActionsAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): TArray<TJSONObject>;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(AIndex);
  try
    Resolver.PinTree(Tree, FileName);
    try
      Result := TLspAnonymousMethods.Actions(Tree, Text, TDocumentUris.FromPath(FileName), TTextPosition.Create(ALine,
        ACharacter), TLspAnonymousMethods.Lookup(Resolver, Tree, FileName, ReadFile), TDeferredCapture.Forward,
        TFormatStyle.Default);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

/// <summary>Antwort von atlas.server.anonymousMethod an ALine/ACharacter mit dem Namen AName.</summary>
function ExecuteAt(const AIndex: ISymbolIndex; ALine, ACharacter: Integer; const AName: string): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(AIndex);
  try
    Resolver.PinTree(Tree, FileName);
    try
      Result := TLspAnonymousMethods.Execute(Tree, Text, TDocumentUris.FromPath(FileName), TTextPosition.Create(ALine,
        ACharacter), AName, TLspAnonymousMethods.Lookup(Resolver, Tree, FileName, ReadFile),
        TDeferredCapture.Forward, TFormatStyle.Default);
    finally
      Resolver.UnpinTree;
    end;
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

procedure TLspAnonymousMethodsTests.ActionCarriesClientCommand;
var
  Actions: TArray<TJSONObject>;
  Arguments: TJSONArray;
begin
  Actions := ActionsAt(FIndex, 25, 18);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual(TLspAnonymousMethods.Kind, Actions[0].GetValue<string>('kind'));
    Assert.AreEqual('In Methode umwandeln (ProcessItem)', Actions[0].GetValue<string>('title'));
    Assert.AreEqual(TLspAnonymousMethods.ClientCommand, Actions[0].GetValue<string>('command.command'));
    Arguments := Actions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(3, Arguments.Count);
    Assert.AreEqual(TDocumentUris.FromPath(FileName), Arguments.Items[0].Value);
    Assert.AreEqual(25, Arguments.Items[1].GetValue<Integer>('line'));
    Assert.AreEqual('ProcessItem', Arguments.Items[2].Value);
  finally
    FreeAll(Actions);
  end;
  // Im Rumpf: nichts.
  Actions := ActionsAt(FIndex, 25, 58);
  Assert.AreEqual(0, Integer(Length(Actions)));
end;

procedure TLspAnonymousMethodsTests.ExecuteAnswersEditAndPreview;
var
  Answer: TJSONObject;
begin
  Answer := ExecuteAt(FIndex, 25, 18, 'Merke');
  try
    Assert.IsTrue(Pos('"newText":"Merke"', Answer.ToJSON) > 0, Answer.ToJSON);
    Assert.IsTrue(Pos('end;\n\n"', Answer.ToJSON) > 0, Answer.ToJSON);
    Assert.IsTrue(Pos('procedure TKunde.Merke(const AWert: Integer);', Answer.ToJSON) > 0, Answer.ToJSON);
    Assert.IsTrue(Answer.GetValue<string>('preview').StartsWith('Neue Methode: '), Answer.ToJSON);
    Assert.AreEqual(1, Answer.GetValue<Integer>('files'));
    Assert.AreEqual(0, Answer.GetValue<TJSONArray>('warnings').Count);
  finally
    Answer.Free;
  end;
end;

procedure TLspAnonymousMethodsTests.ConflictIsAnError;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 25, 18, 'Addiere').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      ExecuteAt(FIndex, 25, 18, 'end').Free;
    end, EJsonRpcError);
end;

procedure TLspAnonymousMethodsTests.EmbedFollowsTargetType;
var
  Actions: TArray<TJSONObject>;
begin
  // Addiere geht an TAktion (reference to): einbetten mit Vorschau.
  Actions := ActionsAt(FIndex, 28, 18);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual(TAnonymousMethods.EmbedTitle, Actions[0].GetValue<string>('title'));
    Assert.IsTrue(Actions[0].GetValue<string>('data.preview') <> '', Actions[0].ToJSON);
    Assert.IsTrue(Pos('procedure(const AWert: Integer)', Actions[0].ToJSON) > 0, Actions[0].ToJSON);
  finally
    FreeAll(Actions);
  end;
  // Tick geht an TEreignis (of object): nicht.
  Actions := ActionsAt(FIndex, 32, 18);
  Assert.AreEqual(0, Integer(Length(Actions)));
end;

procedure TLspAnonymousMethodsTests.EmbedSkipsFormEvent;
begin
  // Knopf steht in Haupt.dfm.
  Assert.AreEqual(0, Integer(Length(ActionsAt(FIndex, 35, 18))));
end;

procedure TLspAnonymousMethodsTests.CaptureSetting;
begin
  Assert.AreEqual(Ord(TDeferredCapture.Fields), Ord(TLspAnonymousMethods.CaptureOf('fields')));
  Assert.AreEqual(Ord(TDeferredCapture.Forward), Ord(TLspAnonymousMethods.CaptureOf('forward')));
  Assert.AreEqual(Ord(TDeferredCapture.Forward), Ord(TLspAnonymousMethods.CaptureOf('')));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspAnonymousMethodsTests);

end.
