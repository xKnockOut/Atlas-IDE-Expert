unit Atlas.Core.Completion.Tests;

// Tests der Datenquellen der Vervollständigung (#408).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCompletionProviderTests = class
  public
    [Test]
    procedure MapsLspCompletionList;
    [Test]
    procedure ReadsTextEditOfPostfixItems;
    [Test]
    procedure ReadsScopeUnitAndHiddenNames;
    [Test]
    procedure KeepsAnonymousMethodsWithoutSnippets;
    [Test]
    procedure KeepsRaiseItemsWithoutSnippets;
    [Test]
    procedure ReadsSyntaxNotice;
    [Test]
    procedure ReadsItemArrayAndNull;
    [Test]
    procedure PartialItemsContinueRank;
    [Test]
    procedure ServerSnippetsUsePlaceholderMode;
    [Test]
    procedure ReadsResolvedDetails;
    [Test]
    procedure MergesProvidersAndCompletesOnce;
    [Test]
    procedure CancelDropsLateItems;
    [Test]
    procedure NewQueryReplacesRunningQuery;
    [Test]
    procedure WithoutSessionCompletesEmpty;
  end;

  [TestFixture]
  TAtlasServerCompletionTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    // Startet den echten Server neben dem Testprogramm.
    [Test]
    procedure CompletesMembersFromServer;
  end;

  /// <summary>XMLDoc-Tags in ///-Kommentaren (#435).</summary>
  [TestFixture]
  TAtlasItemDetailsTests = class
  public
    /// <summary>Ein Hinweis zur Verfügbarkeit allein füllt das Panel (#476).</summary>
    [Test]
    procedure AvailabilityAloneIsNotEmpty;
  end;

  [TestFixture]
  TAtlasXmlDocTests = class
  public
    [Test]
    procedure RecognizesTagContext;
    [Test]
    procedure OffersParamsOfFollowingMethod;
  end;

  /// <summary>Zeitbudget (#409): Filtern und Sortieren beim Weitertippen.</summary>
  [TestFixture]
  TAtlasMatchingBudgetTests = class
  public
    [Test]
    procedure CommitTextFixesCase;
    [Test]
    procedure AnnouncementNamesKindPositionAndDetail;
    [Test]
    procedure TagTextNamesStatesInWords;
    [Test]
    procedure TyposAppearUnderDidYouMean;
    [Test]
    procedure CommitTextKeepsTypedCaseWhenOff;
    [Test]
    [Category('Benchmark')]
    procedure Filters5000EntriesWithin12ms;
    /// <summary>Mit dem Rest der Liste (#497) bleibt ein Filterschritt unter 16 ms (#409).</summary>
    [Test]
    [Category('Benchmark')]
    procedure Orders5000EntriesWithRestWithin16ms;
  end;

  [TestFixture]
  TAtlasWordTests = class
  public
    [Test]
    procedure FindsStartBeforeCursor;
    [Test]
    procedure FindsEndBehindCursorInsideWord;
    [Test]
    procedure EndStaysAtCursorWithoutWordBehind;
    [Test]
    procedure DetectsDataNameStrings;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Composite,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Completion.Word,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Presentation,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Providers.XmlDoc,
  System.Diagnostics,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Adapters.ServerProcess;

type
  /// <summary>Sammelt Einträge aus beliebigen Threads und meldet Complete über ein Ereignis.</summary>
  TCollectingSink = class(TInterfacedObject, IAtlasCompletionSink)
  private
    FLock: TCriticalSection;
    FNames: TList<string>;
    FCompleted: Integer;
    FDone: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddItems(const AItems: TAtlasCompletionItems);
    procedure MarkIncomplete;
    procedure MarkSyntax(const ANotice: TAtlasSyntaxNotice);
    procedure Complete;
    function WaitDone(ATimeoutMs: Cardinal): Boolean;
    function Names: string;
    function Completed: Integer;
  end;

constructor TCollectingSink.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FNames := TList<string>.Create;
  FDone := TEvent.Create(nil, True, False, '');
end;

destructor TCollectingSink.Destroy;
begin
  FDone.Free;
  FNames.Free;
  FLock.Free;
  inherited;
end;

procedure TCollectingSink.AddItems(const AItems: TAtlasCompletionItems);
var
  Item: TAtlasCompletionItem;
begin
  FLock.Enter;
  try
    for Item in AItems do
      FNames.Add(Item.Name);
  finally
    FLock.Leave;
  end;
end;

procedure TCollectingSink.MarkIncomplete;
begin
end;

procedure TCollectingSink.MarkSyntax(const ANotice: TAtlasSyntaxNotice);
begin
end;

procedure TCollectingSink.Complete;
begin
  TInterlocked.Increment(FCompleted);
  FDone.SetEvent;
end;

function TCollectingSink.WaitDone(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FDone.WaitFor(ATimeoutMs) = wrSignaled;
end;

function TCollectingSink.Names: string;
var
  List: TArray<string>;
begin
  FLock.Enter;
  try
    List := FNames.ToArray;
  finally
    FLock.Leave;
  end;
  TArray.Sort<string>(List);
  Result := string.Join(',', List);
end;

function TCollectingSink.Completed: Integer;
begin
  Result := TInterlocked.CompareExchange(FCompleted, 0, 0);
end;

function Item(const AName: string): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
end;

function Context: TAtlasContext;
begin
  Result := Default(TAtlasContext);
  Result.FileName := 'C:\P\A.pas';
end;

{ TAtlasCompletionProviderTests }

procedure TAtlasCompletionProviderTests.ReadsTextEditOfPostfixItems;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
begin
  // Liste.for (#188): ersetzt ab dem Anfang von "Liste" bis zum Cursor.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[{"label":"for","kind":15,"filterText":"Liste.for",' +
    '"textEdit":{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":10}},' +
    '"newText":"for var Item in Liste do\n    "},"data":{"action":"postfix"}},{"label":"Count","kind":10},' +
    '{"label":"notnil","kind":15,"filterText":"Wert.notnil","insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":13}},' +
    '"newText":"if Assigned(Wert) then\n    $0"},"data":{"action":"postfix"}}]}');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  // Gefiltert wird über das Kürzel hinter dem Punkt.
  Assert.IsTrue(Items[0].Postfix);
  Assert.AreEqual('for', Items[0].FilterText);
  Assert.IsFalse(Items[1].Postfix);
  Assert.AreEqual('notnil', Items[2].FilterText);
  Assert.AreEqual('if Assigned(Wert) then'#10'    $0', Items[2].Snippet);
  // completion.snippets aus lässt Postfix-Vorlagen stehen; sie haben einen eigenen Schalter.
  Assert.AreEqual(3, Integer(Length(TAtlasServerCompletionProvider.WithoutSnippets(Items))));
  Assert.AreEqual(Ord(TAtlasItemKind.Snippet), Ord(Items[0].Kind));
  Assert.IsTrue(Items[0].HasTextEdit);
  Assert.AreEqual(7, Items[0].TextEdit.StartLine);
  Assert.AreEqual(2, Items[0].TextEdit.StartCharacter);
  Assert.AreEqual(10, Items[0].TextEdit.EndCharacter);
  Assert.AreEqual('for var Item in Liste do'#10'    ', Items[0].TextEdit.NewText);
  Assert.IsFalse(Items[1].HasTextEdit);
end;

procedure TAtlasCompletionProviderTests.KeepsAnonymousMethodsWithoutSnippets;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
begin
  // #468: Typ als methodRef; completion.snippets aus macht das Gerüst zu Klartext, statt es zu entfernen.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"procedure","kind":15,"insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":3,"character":12},"end":{"line":3,"character":12}},' +
    '"newText":"procedure\n  begin\n    $0\n  end"},"data":{"methodRef":"TProc","action":"anonymous"}}]}');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('TProc', Items[0].MethodRef);
  Items := TAtlasServerCompletionProvider.WithoutSnippets(Items);
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.AreEqual('', Items[0].Snippet);
  Assert.AreEqual('procedure'#10'  begin'#10'    '#10'  end', Items[0].TextEdit.NewText);
end;

procedure TAtlasCompletionProviderTests.ReadsSyntaxNotice;
var
  Response: TJSONValue;
  Notice: TAtlasSyntaxNotice;
begin
  // #457: syntaxNotice der CompletionList; ohne Angabe sicher.
  Response := TJSONObject.ParseJSONValue('{"isIncomplete":false,"items":[],"syntaxNotice":' +
    '{"trust":"unknown","line":13,"character":12,"message":"Ausdruck erwartet"}}');
  try
    Notice := TAtlasServerCompletionProvider.SyntaxNoticeOf(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(Ord(TAtlasSyntaxTrust.Unknown), Ord(Notice.Trust));
  Assert.AreEqual(13, Notice.Line);
  Assert.AreEqual(12, Notice.Character);
  Assert.AreEqual('Ausdruck erwartet', Notice.Message);
  Response := TJSONObject.ParseJSONValue('{"isIncomplete":false,"items":[]}');
  try
    Notice := TAtlasServerCompletionProvider.SyntaxNoticeOf(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(Ord(TAtlasSyntaxTrust.Sure), Ord(Notice.Trust));
  Assert.AreEqual(-1, Notice.Line);
end;

procedure TAtlasCompletionProviderTests.KeepsRaiseItemsWithoutSnippets;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
begin
  // #483: Gruppe und Reihenfolge-Warnung aus data; nach raise bleibt "EFoo.Create('')" ohne Platzhalter.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"EAppError","kind":7,"insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":3,"character":8},"end":{"line":3,"character":8}},' +
    '"newText":"EAppError.Create(''$0'')"},"data":{"exceptionGroup":"raise"}},' +
    '{"label":"EConvertError","kind":7,"data":{"exceptionGroup":"general","unreachable":"Exception"}}]}');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('raise', Items[0].ExceptionGroup);
  Assert.AreEqual('general', Items[1].ExceptionGroup);
  Assert.AreEqual('Exception', Items[1].Unreachable);
  Items := TAtlasServerCompletionProvider.WithoutSnippets(Items);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('', Items[0].Snippet);
  Assert.AreEqual('EAppError.Create('''')', Items[0].TextEdit.NewText);
end;

procedure TAtlasCompletionProviderTests.ReadsScopeUnitAndHiddenNames;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
begin
  // #488: Bereichsstufe, Unit bei Stufe 5 und verdeckte Deklarationen.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"Name","kind":6,"data":{"scope":1,"hides":["Feld TFoo.Name","Werkzeug.Name"]}},' +
    '{"label":"Rechne","kind":3,"data":{"scope":5,"unit":"Werkzeug"}}]}');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(1, Items[0].Scope);
  Assert.AreEqual(2, Integer(Length(Items[0].Hides)));
  Assert.AreEqual('Feld TFoo.Name', Items[0].Hides[0]);
  Assert.AreEqual('Werkzeug.Name', Items[0].Hides[1]);
  Assert.AreEqual(5, Items[1].Scope);
  Assert.AreEqual('Werkzeug', Items[1].DeclaringUnit);
  Assert.AreEqual(0, Integer(Length(Items[1].Hides)));
end;

procedure TAtlasCompletionProviderTests.MapsLspCompletionList;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
begin
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"Add","kind":2,"detail":"function Add(const S: string): Integer",' +
    '"documentation":{"kind":"plaintext","value":"Hängt S an."},' +
    '"additionalTextEdits":[{"range":{"start":{"line":2,"character":5},"end":{"line":2,"character":5}},' +
    '"newText":", System.Classes"}]},' +
    '{"label":"TFoo","kind":7,"documentation":"Klasse"}]}');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('Add', Items[0].Name);
  Assert.AreEqual(Ord(TAtlasItemKind.Method), Ord(Items[0].Kind));
  Assert.AreEqual('function Add(const S: string): Integer', Items[0].Signature);
  Assert.AreEqual('Hängt S an.', Items[0].Documentation);
  Assert.AreEqual(1, Integer(Length(Items[0].AdditionalEdits)));
  Assert.AreEqual(2, Items[0].AdditionalEdits[0].StartLine);
  Assert.AreEqual(5, Items[0].AdditionalEdits[0].EndCharacter);
  Assert.AreEqual(', System.Classes', Items[0].AdditionalEdits[0].NewText);
  Assert.IsFalse(Items[0].UnitUsed, 'Eintrag mit uses-Ergänzung');
  Assert.AreEqual(Ord(TAtlasItemKind.Class_), Ord(Items[1].Kind));
  Assert.AreEqual('Klasse', Items[1].Documentation);
  Assert.IsTrue(Items[1].UnitUsed);
  Assert.AreEqual(1, Items[1].Rank);
end;

procedure TAtlasCompletionProviderTests.ServerSnippetsUsePlaceholderMode;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
begin
  // Kontextabhängige Vorlage des Servers (#51): insertTextFormat 2 wird zum Snippet für den Platzhalter-Modus,
  // die Setter-Änderungen sind keine uses-Ergänzung.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"prop Farbe","kind":15,"insertTextFormat":2,"data":{"action":"snippet"},' +
    '"textEdit":{"range":{"start":{"line":9,"character":4},"end":{"line":9,"character":7}},' +
    '"newText":"property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0"},' +
    '"additionalTextEdits":[{"range":{"start":{"line":10,"character":0},"end":{"line":10,"character":0}},' +
    '"newText":"  private\n    procedure SetFarbe(const Value: TColor);\n"}]},' +
    '{"label":"Farbe","kind":5,"insertText":"Farbe"}]}');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual(Ord(TAtlasItemKind.Snippet), Ord(Items[0].Kind));
  Assert.AreEqual('property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0', Items[0].Snippet);
  Assert.IsTrue(Items[0].HasTextEdit);
  Assert.AreEqual(4, Items[0].TextEdit.StartCharacter);
  Assert.AreEqual(1, Integer(Length(Items[0].AdditionalEdits)));
  Assert.IsTrue(Items[0].UnitUsed, 'Keine uses-Ergänzung');
  Assert.AreEqual('', Items[1].Snippet);
  // completion.snippets aus: wie ohne die Funktion.
  Items := TAtlasServerCompletionProvider.WithoutSnippets(Items);
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.AreEqual('Farbe', Items[0].Name);
end;

procedure TAtlasCompletionProviderTests.PartialItemsContinueRank;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
begin
  // Teilergebnis als CompletionItem[] (#616): Rang zählt ab dem ersten Eintrag dieses Teils.
  Response := TJSONObject.ParseJSONValue('[{"label":"A","kind":6},5,{"label":"B","kind":6}]');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response, 10);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Items)), 'Nicht-Objekte übersprungen');
  Assert.AreEqual('B', Items[1].Name);
  Assert.AreEqual(10, Items[0].Rank);
  Assert.AreEqual(12, Items[1].Rank);
end;

procedure TAtlasCompletionProviderTests.ReadsItemArrayAndNull;
var
  Response: TJSONValue;
begin
  Response := TJSONObject.ParseJSONValue('[{"label":"A"},{"label":"B","kind":99,"filterText":"mylist"}]');
  try
    Assert.AreEqual(2, Integer(Length(TAtlasServerCompletionProvider.ItemsFromLsp(Response))));
    Assert.AreEqual(Ord(TAtlasItemKind.Unknown),
      Ord(TAtlasServerCompletionProvider.ItemsFromLsp(Response)[1].Kind));
    // Der filterText des Servers ist das getippte Wort (für VS Code); Atlas filtert gegen den Namen.
    Assert.AreEqual('', TAtlasServerCompletionProvider.ItemsFromLsp(Response)[1].FilterText);
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasServerCompletionProvider.ItemsFromLsp(nil))));
end;

procedure TAtlasCompletionProviderTests.ReadsResolvedDetails;
var
  Response: TJSONValue;
  Items: TAtlasCompletionItems;
  Details: TAtlasItemDetails;
begin
  // data bleibt für completionItem/resolve erhalten.
  Response := TJSONObject.ParseJSONValue('[{"label":"Add","data":{"file":"C:\\P\\A.pas","line":9,"character":13}}]');
  try
    Items := TAtlasServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.Contains(Items[0].ResolveData, '"line":9');
  Response := TJSONObject.ParseJSONValue(
    '{"label":"Add","detail":"function Add(const S: string): Integer; virtual;","data":{"atlas":{' +
    '"declaration":"function Add(const S: string): Integer; virtual;","unit":"Liste","container":"TListe",' +
    '"visibility":"public","directives":["virtual","deprecated"],"deprecated":"Neu verwenden",' +
    '"summary":"Hängt S an.","returns":"Index.","params":[{"name":"S","text":"Der Text."}],' +
    '"exceptions":[{"name":"EListError","text":"Voll."}],' +
    '"documentation":{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Hängt "},' +
    '{"kind":"paramref","text":"S"},{"kind":"text","text":" an."}]}]},' +
    '"xmlDoc":{"full":true,"maxLines":20}}}}');
  try
    Details := TAtlasServerCompletionProvider.DetailsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('function Add(const S: string): Integer; virtual;', Details.Declaration);
  Assert.AreEqual('Liste', Details.UnitName);
  Assert.AreEqual('TListe', Details.Container);
  Assert.AreEqual('public', Details.Visibility);
  Assert.AreEqual(2, Integer(Length(Details.Directives)));
  Assert.IsTrue(Details.IsDeprecated);
  Assert.AreEqual('Neu verwenden', Details.DeprecatedText);
  Assert.AreEqual('Hängt S an.', Details.Summary);
  Assert.AreEqual('Index.', Details.Returns);
  Assert.AreEqual('Der Text.', Details.Params[0].Text);
  Assert.AreEqual('EListError', Details.Exceptions[0].Name);
  // Vollständige XMLDoc und Anzeige (#654).
  Assert.AreEqual(1, Integer(Length(Details.Doc.Sections)));
  Assert.AreEqual('Hängt S an.', Details.Doc.Sections[0].Text);
  Assert.IsTrue(Details.Display.Known);
  Assert.AreEqual(20, Details.Display.MaxLines);
  Assert.IsFalse(Details.IsHelper);
  // Mitglied eines Helpers (#456).
  Response := TJSONObject.ParseJSONValue('{"label":"Trim","data":{"atlas":{"declaration":"function Trim: string;",' +
    '"unit":"System.SysUtils","container":"TStringHelper","helper":true}}}');
  try
    Details := TAtlasServerCompletionProvider.DetailsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.IsTrue(Details.IsHelper);
  Assert.AreEqual('TStringHelper', Details.Container);
  // Andere Server: detail und documentation.
  Response := TJSONObject.ParseJSONValue('{"label":"X","detail":"X: Integer","documentation":{"value":"Doku"}}');
  try
    Details := TAtlasServerCompletionProvider.DetailsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('X: Integer', Details.Declaration);
  Assert.AreEqual('Doku', Details.Summary);
  Assert.IsFalse(Details.IsDeprecated);
  Assert.IsTrue(Details.Doc.IsEmpty);
  Assert.IsFalse(Details.Display.Known);
end;

procedure TAtlasCompletionProviderTests.MergesProvidersAndCompletesOnce;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IAtlasCompletionSink;
begin
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TAtlasFixedCompletionProvider.Create([Item('Beta')]));
  Providers.Add(TAtlasFixedCompletionProvider.Create([Item('Alpha'), Item('Gamma')], 50));
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(3000), 'Complete kam nicht');
  Assert.AreEqual('Alpha,Beta,Gamma', Sink.Names);
  Assert.AreEqual(1, Sink.Completed);
end;

procedure TAtlasCompletionProviderTests.CancelDropsLateItems;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IAtlasCompletionSink;
begin
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TAtlasFixedCompletionProvider.Create([Item('Spaet')], 200));
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Provider.Cancel;
  Assert.IsFalse(Sink.WaitDone(400), 'Nach Cancel darf kein Complete kommen');
  Assert.AreEqual('', Sink.Names);
end;

procedure TAtlasCompletionProviderTests.NewQueryReplacesRunningQuery;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  First, Second: TCollectingSink;
  FirstRef, SecondRef: IAtlasCompletionSink;
begin
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TAtlasFixedCompletionProvider.Create([Item('X')], 100));
  First := TCollectingSink.Create;
  FirstRef := First;
  Second := TCollectingSink.Create;
  SecondRef := Second;
  Provider.Query(Context, FirstRef);
  Provider.Query(Context, SecondRef);
  Assert.IsTrue(Second.WaitDone(3000), 'Complete des neuen Query kam nicht');
  Assert.AreEqual('X', Second.Names);
  Assert.AreEqual(0, First.Completed, 'Der ersetzte Query wurde noch beendet');
  Assert.AreEqual('', First.Names);
end;

procedure TAtlasCompletionProviderTests.WithoutSessionCompletesEmpty;
var
  Server: TAtlasServerCompletionProvider;
  Provider: IAtlasCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IAtlasCompletionSink;
  Logged: string;
begin
  Server := TAtlasServerCompletionProvider.Create(
    function: TLspSession
    begin
      Result := nil;
    end);
  Provider := Server;
  // Warum die Liste leer bleibt, steht im Diagnoselog des Plugins (#647).
  Logged := '';
  Server.OnLog :=
    procedure(const AMessage: string)
    begin
      Logged := Logged + AMessage;
    end;
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(0), 'Ohne Server sofort fertig');
  Assert.AreEqual('', Sink.Names);
  Assert.Contains(Logged, 'kein Server');
end;

{ TAtlasServerCompletionTests }

procedure TAtlasItemDetailsTests.AvailabilityAloneIsNotEmpty;
var
  Details: TAtlasItemDetails;
begin
  Details := Default(TAtlasItemDetails);
  Assert.IsTrue(Details.IsEmpty);
  Details.Availability := 'Nicht verfügbar: Die Bedingung „WIN64“ ist für Win32 · Debug nicht erfüllt.';
  Assert.IsFalse(Details.IsEmpty);
end;

procedure TAtlasServerCompletionTests.WarmUpFirstUse;
begin
  // Erster echter Start (Pipes, Threads, Sitzung, Zeitlimit-Arbeiter) ungemessen statt [IgnoreMemoryLeaks]
  // (Bericht N2). Ohne Server neben dem Testprogramm überspringt der Test ohnehin.
  if FileExists(TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe')) then
    try
      CompletesMembersFromServer;
    except
      // Scheitert der Lauf, meldet das der Test selbst.
      on Exception do
        ;
    end;
end;

procedure TAtlasServerCompletionTests.CompletesMembersFromServer;
const
  UnitText =
    'unit Probe;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    FWert: Integer;'#13#10 +
    '    FWeite: Integer;'#13#10 +
    '    procedure Setze;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Setze;'#13#10 +
    'begin'#13#10 +
    '  Self.FWe'#13#10 +
    'end;'#13#10 +
    'end.';
var
  ServerExe: string;
  Server: TLspServerProcess;
  Session: TLspSession;
  Provider: TAtlasServerCompletionProvider;
  ProviderRef: IAtlasCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IAtlasCompletionSink;
  Query: TAtlasContext;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(ServerExe) then
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Provider := TAtlasServerCompletionProvider.Create(
        function: TLspSession
        begin
          Result := Session;
        end, 5000);
      ProviderRef := Provider;
      Query := Default(TAtlasContext);
      Query.FileName := TPath.Combine(TPath.GetTempPath, 'AtlasCompletionProbe.pas');
      Query.Text := UnitText;
      Query.Line := 11;
      // Hinter "  Self.FWe".
      Query.Character := 10;
      Query.Prefix := 'FWe';
      Query.Kind := TAtlasContextKind.MemberAccess;
      Sink := TCollectingSink.Create;
      SinkRef := Sink;
      ProviderRef.Query(Query, SinkRef);
      Assert.IsTrue(Sink.WaitDone(10000), 'Keine Antwort vom Server');
      Assert.Contains(Sink.Names, 'FWeite');
      Assert.Contains(Sink.Names, 'FWert');
      // Vor dem Freigeben der Sitzung auf laufende Anfragen warten.
      Provider.Shutdown;
      ProviderRef := nil;
    finally
      Session.Free;
    end;
  finally
    Server.Free;
  end;
end;

{ TAtlasXmlDocTests }

procedure TAtlasXmlDocTests.RecognizesTagContext;
begin
  Assert.IsTrue(TAtlasXmlDoc.IsTagContext('  /// <'));
  Assert.IsTrue(TAtlasXmlDoc.IsTagContext('  /// Text <su'));
  Assert.IsFalse(TAtlasXmlDoc.IsTagContext('  // <'), 'nur ///');
  Assert.IsFalse(TAtlasXmlDoc.IsTagContext('  /// Text'));
  Assert.IsFalse(TAtlasXmlDoc.IsTagContext('  if A < B'));
end;

procedure TAtlasXmlDocTests.OffersParamsOfFollowingMethod;
const
  Text = 'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    /// <'#13#10 +
    '    /// weiter'#13#10 +
    '    function CalcDiscount(const Customer: TCustomer;'#13#10 +
    '      Rate, Extra: Double): Currency;'#13#10 +
    '  end;';
var
  Declaration, Names: string;
  Item: TAtlasCompletionItem;
begin
  Declaration := TAtlasXmlDoc.FollowingDeclaration(Text, 2);
  Assert.AreEqual('function CalcDiscount(const Customer: TCustomer; Rate, Extra: Double): Currency;', Declaration);
  Assert.AreEqual('Customer,Rate,Extra', String.Join(',', TAtlasXmlDoc.ParamNames(Declaration)));
  Names := '';
  for Item in TAtlasXmlDoc.TagItems(Declaration) do
    Names := Names + Item.Name + '|';
  Assert.IsTrue(Names.StartsWith('summary|param name="Customer"|param name="Rate"|param name="Extra"|returns|'),
    Names);
  Assert.AreEqual('summary>$0</summary>', TAtlasXmlDoc.TagItems(Declaration)[0].InsertText);
  // Prozedur: kein returns.
  Assert.IsFalse(String.Join('|', [TAtlasXmlDoc.TagItems('procedure Add(A: Integer);')[2].Name]) = 'returns');
end;

{ TAtlasMatchingBudgetTests }

procedure TAtlasMatchingBudgetTests.Filters5000EntriesWithin12ms;
const
  Words: array[0..11] of string = ('Add', 'String', 'List', 'Item', 'Get', 'Set', 'Count', 'Object', 'Begin',
    'Update', 'Index', 'Value');
var
  Items: TAtlasCompletionItems;
  Index, Run: Integer;
  Pattern: string;
  Watch: TStopwatch;
  Times: TArray<Int64>;
begin
  SetLength(Items, 5000);
  for Index := 0 to High(Items) do
  begin
    Items[Index].Name := Words[Index mod 12] + Words[(Index div 12) mod 12] + Words[(Index div 144) mod 12] +
      IntToStr(Index);
    Items[Index].Rank := Index;
  end;
  // Typische Schritte beim Tippen: Anfang, CamelCase, Teilfolge, kein Treffer.
  for Pattern in ['A', 'Ad', 'AddS', 'ASL', 'stl', 'xyz'] do
  begin
    TAtlasCompletionMatcher.Filter(Items, Pattern);
    Times := nil;
    for Run := 1 to 5 do
    begin
      Watch := TStopwatch.StartNew;
      TAtlasCompletionMatcher.Filter(Items, Pattern);
      Times := Times + [Watch.ElapsedMilliseconds];
    end;
    // Median von fünf Läufen, damit ein einzelner Ausreißer der Maschine nicht zählt.
    TArray.Sort<Int64>(Times);
    Assert.IsTrue(Times[2] <= 12, Format('Filtern nach "%s" dauerte %d ms', [Pattern, Times[2]]));
  end;
end;

procedure TAtlasMatchingBudgetTests.Orders5000EntriesWithRestWithin16ms;
const
  Words: array[0..11] of string = ('Add', 'String', 'List', 'Item', 'Get', 'Set', 'Count', 'Object', 'Begin',
    'Update', 'Index', 'Value');
var
  Items: TAtlasCompletionItems;
  Index, Run, RestStart: Integer;
  Pattern: string;
  Watch: TStopwatch;
  Times: TArray<Int64>;
  Options: TAtlasRankOptions;
  Order: TArray<Integer>;
begin
  SetLength(Items, 5000);
  for Index := 0 to High(Items) do
  begin
    Items[Index].Name := Words[Index mod 12] + Words[(Index div 12) mod 12] + Words[(Index div 144) mod 12] +
      IntToStr(Index);
    Items[Index].Rank := Index;
  end;
  Options := TAtlasRankOptions.Defaults;
  Options.ListMode := TAtlasListMode.Rest;
  for Pattern in ['A', 'AddS', 'ASL', 'xyz'] do
  begin
    Order := TAtlasRanking.Order(Items, Pattern, Options, RestStart);
    Assert.AreEqual(5000, TAtlasRanking.ItemCount(Order), 'Alle Einträge bleiben sichtbar');
    Times := nil;
    for Run := 1 to 5 do
    begin
      Watch := TStopwatch.StartNew;
      TAtlasRanking.Order(Items, Pattern, Options, RestStart);
      Times := Times + [Watch.ElapsedMilliseconds];
    end;
    TArray.Sort<Int64>(Times);
    Assert.IsTrue(Times[2] <= 16, Format('Ordnen mit Rest nach "%s" dauerte %d ms', [Pattern, Times[2]]));
  end;
  Items := nil;
  Order := nil;
end;

{ TAtlasWordTests }

procedure TAtlasWordTests.FindsStartBeforeCursor;
begin
  // "  myList := TStringL|ist.": Präfix ab Index 12.
  Assert.AreEqual(12, TAtlasWord.StartBefore('  myList := TStringList.', 20));
  Assert.AreEqual(0, TAtlasWord.StartBefore('Format', 3));
  Assert.AreEqual(5, TAtlasWord.StartBefore('List.Ad', 7));
  Assert.AreEqual(5, TAtlasWord.StartBefore('List.', 5));
end;

procedure TAtlasWordTests.FindsEndBehindCursorInsideWord;
begin
  // Mitten im Wort: bis zum Punkt ersetzen, nicht nur bis zum Cursor.
  Assert.AreEqual(23, TAtlasWord.EndAfter('  myList := TStringList.', 20));
  Assert.AreEqual(6, TAtlasWord.EndAfter('Format', 3));
  Assert.AreEqual(5, TAtlasWord.EndAfter('Größe(', 2));
end;

procedure TAtlasWordTests.EndStaysAtCursorWithoutWordBehind;
begin
  Assert.AreEqual(4, TAtlasWord.EndAfter('List.Add', 4));
  Assert.AreEqual(6, TAtlasWord.EndAfter('Format', 6));
  Assert.AreEqual(8, TAtlasWord.EndAfter('  Add(  ', 8));
end;

procedure TAtlasWordTests.DetectsDataNameStrings;
begin
  // Feld- und Parameternamen (#461): nur im ersten String-Argument.
  Assert.IsTrue(TAtlasWord.InDataNameString('  qryOrders.FieldByName(''cu', 27));
  Assert.IsTrue(TAtlasWord.InDataNameString('  qryOrders.Params.ParamByName(''', 32));
  Assert.IsTrue(TAtlasWord.InDataNameString('  if q.FindField(''A''''B'') = nil', 22));
  Assert.IsFalse(TAtlasWord.InDataNameString('  qryOrders.FieldByName(''cu'').AsString', 29));
  Assert.IsFalse(TAtlasWord.InDataNameString('  ShowMessage(''cu', 17));
  Assert.IsFalse(TAtlasWord.InDataNameString('  FieldByName(''cu', 17));
  Assert.IsFalse(TAtlasWord.InDataNameString('  // q.FieldByName(''cu', 22));
end;

procedure TAtlasMatchingBudgetTests.TyposAppearUnderDidYouMean;
var
  Items: TAtlasCompletionItems;
  Order: TArray<Integer>;
  Name: string;
  Item: TAtlasCompletionItem;
begin
  Assert.AreEqual(1, TAtlasCompletionMatcher.Distance('Lenght', 'Length'), 'Vertauschung zählt 1');
  Assert.AreEqual(1, TAtlasCompletionMatcher.Distance('lengh', 'Length'));
  Assert.AreEqual(0, TAtlasCompletionMatcher.TypoLimit('Le'));
  Items := nil;
  for Name in ['Length', 'Low', 'High', 'Lengthy'] do
  begin
    Item := Default(TAtlasCompletionItem);
    Item.Name := Name;
    Items := Items + [Item];
  end;
  Order := TAtlasRanking.Order(Items, 'Lenght', TAtlasRankOptions.Defaults);
  Assert.AreEqual(TAtlasRanking.TypoHeader, Order[0], 'keine regulären Treffer: gleich „Meintest du“');
  Assert.AreEqual('Length', Items[Order[1]].Name);
  Assert.AreEqual(2, TAtlasRanking.ItemCount(Order), 'Length und Lengthy (Anfang), nicht Low');
  Assert.IsTrue(TAtlasRanking.OnlyTypos(Order), 'Fußzeile: Keine Treffer für „Lenght“');
  // Mit genug regulären Treffern keine Tippfehler-Gruppe.
  Order := TAtlasRanking.Order(Items, 'L', TAtlasRankOptions.Defaults);
  Assert.IsFalse(TAtlasRanking.IsHeader(Order[0]));
  Assert.IsFalse(TAtlasRanking.OnlyTypos(Order));
  Assert.IsFalse(TAtlasRanking.OnlyTypos([TAtlasRanking.TypoHeader]));
end;

procedure TAtlasMatchingBudgetTests.AnnouncementNamesKindPositionAndDetail;
var
  Item: TAtlasCompletionItem;
begin
  Item := Default(TAtlasCompletionItem);
  Item.Name := 'ShowMessage';
  Item.Signature := 'procedure ShowMessage(const Msg: string)';
  Assert.AreEqual('ShowMessage, Methode, 3 von 12. procedure ShowMessage(const Msg: string)',
    TAtlasItemPresentation.Announcement(Item, 'Methode', '%d von %d', 3, 12));
  Item.Signature := '';
  Assert.AreEqual('ShowMessage, 1 von 1.', TAtlasItemPresentation.Announcement(Item, '', '%d von %d', 1, 1));
end;

procedure TAtlasMatchingBudgetTests.TagTextNamesStatesInWords;
var
  Item: TAtlasCompletionItem;
begin
  Item := Default(TAtlasCompletionItem);
  Item.Name := 'AddPair';
  Assert.AreEqual('', TAtlasItemPresentation.TagText(Item));
  Item.Directives := ['deprecated'];
  Item.IsHelper := True;
  Assert.AreEqual('deprecated, Helper', TAtlasItemPresentation.TagText(Item));
  Item.Directives := nil;
end;

procedure TAtlasMatchingBudgetTests.CommitTextFixesCase;
begin
  Assert.AreEqual('ShowMessage', TAtlasCompletionMatcher.CommitText('showmessage', 'ShowMessage', True));
  Assert.AreEqual('ShowMessage', TAtlasCompletionMatcher.CommitText('showm', 'ShowMessage', True));
end;

procedure TAtlasMatchingBudgetTests.CommitTextKeepsTypedCaseWhenOff;
begin
  Assert.AreEqual('showmessage', TAtlasCompletionMatcher.CommitText('showmessage', 'ShowMessage', False));
  Assert.AreEqual('showMessage', TAtlasCompletionMatcher.CommitText('show', 'ShowMessage', False));
  // Unscharfer Treffer ("TSL" → TStringList): kein Anfang, also der Name.
  Assert.AreEqual('TStringList', TAtlasCompletionMatcher.CommitText('tsl', 'TStringList', False));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompletionProviderTests);
  TDUnitX.RegisterTestFixture(TAtlasServerCompletionTests);
  TDUnitX.RegisterTestFixture(TAtlasItemDetailsTests);
  TDUnitX.RegisterTestFixture(TAtlasXmlDocTests);
  TDUnitX.RegisterTestFixture(TAtlasMatchingBudgetTests);
  TDUnitX.RegisterTestFixture(TAtlasWordTests);

end.
