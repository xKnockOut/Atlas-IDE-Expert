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
    /// <summary>#2108: nicht sichtbare Mitglieder mit Befehl für ihre Aktionen, außer aus fremdem Code.
    /// </summary>
    [Test]
    procedure ReadsHiddenMembersWithActions;
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
  mItem: TAtlasCompletionItem;
begin
  FLock.Enter;
  try
    for mItem in AItems do
    begin
      FNames.Add(mItem.Name);
    end;
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
  mList: TArray<string>;
begin
  FLock.Enter;
  try
    mList := FNames.ToArray;
  finally
    FLock.Leave;
  end;
  TArray.Sort<string>(mList);
  Result := string.Join(',', mList);
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
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  // Liste.for (#188): ersetzt ab dem Anfang von "Liste" bis zum Cursor.
  mResponse := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[{"label":"for","kind":15,"filterText":"Liste.for",' +
    '"textEdit":{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":10}},' +
    '"newText":"for var Item in Liste do\n    "},"data":{"action":"postfix"}},{"label":"Count","kind":10},' +
    '{"label":"notnil","kind":15,"filterText":"Wert.notnil","insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":13}},' +
    '"newText":"if Assigned(Wert) then\n    $0"},"data":{"action":"postfix"}}]}');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  // Gefiltert wird über das Kürzel hinter dem Punkt.
  Assert.IsTrue(mItems[0].Postfix);
  Assert.AreEqual('for', mItems[0].FilterText);
  Assert.IsFalse(mItems[1].Postfix);
  Assert.AreEqual('notnil', mItems[2].FilterText);
  Assert.AreEqual('if Assigned(Wert) then'#10'    $0', mItems[2].Snippet);
  // completion.snippets aus lässt Postfix-Vorlagen stehen; sie haben einen eigenen Schalter.
  Assert.AreEqual(3, Integer(Length(TAtlasServerCompletionProvider.WithoutSnippets(mItems))));
  Assert.AreEqual(Ord(TAtlasItemKind.Snippet), Ord(mItems[0].Kind));
  Assert.IsTrue(mItems[0].HasTextEdit);
  Assert.AreEqual(7, mItems[0].TextEdit.StartLine);
  Assert.AreEqual(2, mItems[0].TextEdit.StartCharacter);
  Assert.AreEqual(10, mItems[0].TextEdit.EndCharacter);
  Assert.AreEqual('for var Item in Liste do'#10'    ', mItems[0].TextEdit.NewText);
  Assert.IsFalse(mItems[1].HasTextEdit);
end;

procedure TAtlasCompletionProviderTests.KeepsAnonymousMethodsWithoutSnippets;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  // #468: Typ als methodRef; completion.snippets aus macht das Gerüst zu Klartext, statt es zu entfernen.
  mResponse := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"procedure","kind":15,"insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":3,"character":12},"end":{"line":3,"character":12}},' +
    '"newText":"procedure\n  begin\n    $0\n  end"},"data":{"methodRef":"TProc","action":"anonymous"}}]}');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual('TProc', mItems[0].MethodRef);
  mItems := TAtlasServerCompletionProvider.WithoutSnippets(mItems);
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('', mItems[0].Snippet);
  Assert.AreEqual('procedure'#10'  begin'#10'    '#10'  end', mItems[0].TextEdit.NewText);
end;

procedure TAtlasCompletionProviderTests.ReadsSyntaxNotice;
var
  mResponse: TJSONValue;
  mNotice: TAtlasSyntaxNotice;
begin
  // #457: syntaxNotice der CompletionList; ohne Angabe sicher.
  mResponse := TJSONObject.ParseJSONValue('{"isIncomplete":false,"items":[],"syntaxNotice":' +
    '{"trust":"unknown","line":13,"character":12,"message":"Ausdruck erwartet"}}');
  try
    mNotice := TAtlasServerCompletionProvider.SyntaxNoticeOf(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(Ord(TAtlasSyntaxTrust.Unknown), Ord(mNotice.Trust));
  Assert.AreEqual(13, mNotice.Line);
  Assert.AreEqual(12, mNotice.Character);
  Assert.AreEqual('Ausdruck erwartet', mNotice.Message);
  mResponse := TJSONObject.ParseJSONValue('{"isIncomplete":false,"items":[]}');
  try
    mNotice := TAtlasServerCompletionProvider.SyntaxNoticeOf(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(Ord(TAtlasSyntaxTrust.Sure), Ord(mNotice.Trust));
  Assert.AreEqual(-1, mNotice.Line);
end;

procedure TAtlasCompletionProviderTests.ReadsHiddenMembersWithActions;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  mResponse := TJSONObject.ParseJSONValue('{"isIncomplete":false,"items":[],"hiddenMembers":{"count":2,' +
    '"items":[{"name":"FEintraege","kind":5,"visibility":"private","container":"TZaehler","unit":"Zaehler",' +
    '"uri":"file:///C:/P/Zaehler.pas","line":7,"character":4,"external":false},' +
    '{"name":"FHandle","kind":5,"visibility":"private","container":"TStream","unit":"System.Classes",' +
    '"uri":"file:///C:/BDS/System.Classes.pas","line":9,"character":4,"external":true}]}}');
  try
    mItems := TAtlasServerCompletionProvider.HiddenMembersOf(mResponse, 10);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('FEintraege', mItems[0].Name);
  Assert.AreEqual('private', mItems[0].Inaccessible);
  Assert.AreEqual('TZaehler', mItems[0].DeclaringClass);
  Assert.AreEqual(10, mItems[0].Rank);
  Assert.AreEqual(TAtlasServerCompletionProvider.cMemberActionsCommand, mItems[0].Command);
  Assert.AreEqual('["file:///C:/P/Zaehler.pas",{"line":7,"character":4},"FEintraege"]',
    mItems[0].CommandArguments);
  // Fremder Code: ausgegraut, aber ohne Aktionen.
  Assert.AreEqual('FHandle', mItems[1].Name);
  Assert.AreEqual('', mItems[1].Command);
end;

procedure TAtlasCompletionProviderTests.KeepsRaiseItemsWithoutSnippets;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  // #483: Gruppe und Reihenfolge-Warnung aus data; nach raise bleibt "EFoo.Create('')" ohne Platzhalter.
  mResponse := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"EAppError","kind":7,"insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":3,"character":8},"end":{"line":3,"character":8}},' +
    '"newText":"EAppError.Create(''$0'')"},"data":{"exceptionGroup":"raise"}},' +
    '{"label":"EConvertError","kind":7,"data":{"exceptionGroup":"general","unreachable":"Exception"}}]}');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual('raise', mItems[0].ExceptionGroup);
  Assert.AreEqual('general', mItems[1].ExceptionGroup);
  Assert.AreEqual('Exception', mItems[1].Unreachable);
  mItems := TAtlasServerCompletionProvider.WithoutSnippets(mItems);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('', mItems[0].Snippet);
  Assert.AreEqual('EAppError.Create('''')', mItems[0].TextEdit.NewText);
end;

procedure TAtlasCompletionProviderTests.ReadsScopeUnitAndHiddenNames;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  // #488: Bereichsstufe, Unit bei Stufe 5 und verdeckte Deklarationen.
  mResponse := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"Name","kind":6,"data":{"scope":1,"hides":["Feld TFoo.Name","Werkzeug.Name"]}},' +
    '{"label":"Rechne","kind":3,"data":{"scope":5,"unit":"Werkzeug"}}]}');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(1, mItems[0].Scope);
  Assert.AreEqual(2, Integer(Length(mItems[0].Hides)));
  Assert.AreEqual('Feld TFoo.Name', mItems[0].Hides[0]);
  Assert.AreEqual('Werkzeug.Name', mItems[0].Hides[1]);
  Assert.AreEqual(5, mItems[1].Scope);
  Assert.AreEqual('Werkzeug', mItems[1].DeclaringUnit);
  Assert.AreEqual(0, Integer(Length(mItems[1].Hides)));
end;

procedure TAtlasCompletionProviderTests.MapsLspCompletionList;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  mResponse := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"Add","kind":2,"detail":"function Add(const S: string): Integer",' +
    '"documentation":{"kind":"plaintext","value":"Hängt S an."},' +
    '"additionalTextEdits":[{"range":{"start":{"line":2,"character":5},"end":{"line":2,"character":5}},' +
    '"newText":", System.Classes"}]},' +
    '{"label":"TFoo","kind":7,"documentation":"Klasse"}]}');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Add', mItems[0].Name);
  Assert.AreEqual(Ord(TAtlasItemKind.Method), Ord(mItems[0].Kind));
  Assert.AreEqual('function Add(const S: string): Integer', mItems[0].Signature);
  Assert.AreEqual('Hängt S an.', mItems[0].Documentation);
  Assert.AreEqual(1, Integer(Length(mItems[0].AdditionalEdits)));
  Assert.AreEqual(2, mItems[0].AdditionalEdits[0].StartLine);
  Assert.AreEqual(5, mItems[0].AdditionalEdits[0].EndCharacter);
  Assert.AreEqual(', System.Classes', mItems[0].AdditionalEdits[0].NewText);
  Assert.IsFalse(mItems[0].UnitUsed, 'Eintrag mit uses-Ergänzung');
  Assert.AreEqual(Ord(TAtlasItemKind.Class_), Ord(mItems[1].Kind));
  Assert.AreEqual('Klasse', mItems[1].Documentation);
  Assert.IsTrue(mItems[1].UnitUsed);
  Assert.AreEqual(1, mItems[1].Rank);
end;

procedure TAtlasCompletionProviderTests.ServerSnippetsUsePlaceholderMode;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  // Kontextabhängige Vorlage des Servers (#51): insertTextFormat 2 wird zum Snippet für den Platzhalter-Modus,
  // die Setter-Änderungen sind keine uses-Ergänzung.
  mResponse := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"prop Farbe","kind":15,"insertTextFormat":2,"data":{"action":"snippet"},' +
    '"textEdit":{"range":{"start":{"line":9,"character":4},"end":{"line":9,"character":7}},' +
    '"newText":"property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0"},' +
    '"additionalTextEdits":[{"range":{"start":{"line":10,"character":0},"end":{"line":10,"character":0}},' +
    '"newText":"  private\n    procedure SetFarbe(const Value: TColor);\n"}]},' +
    '{"label":"Farbe","kind":5,"insertText":"Farbe"}]}');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual(Ord(TAtlasItemKind.Snippet), Ord(mItems[0].Kind));
  Assert.AreEqual('property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0', mItems[0].Snippet);
  Assert.IsTrue(mItems[0].HasTextEdit);
  Assert.AreEqual(4, mItems[0].TextEdit.StartCharacter);
  Assert.AreEqual(1, Integer(Length(mItems[0].AdditionalEdits)));
  Assert.IsTrue(mItems[0].UnitUsed, 'Keine uses-Ergänzung');
  Assert.AreEqual('', mItems[1].Snippet);
  // completion.snippets aus: wie ohne die Funktion.
  mItems := TAtlasServerCompletionProvider.WithoutSnippets(mItems);
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('Farbe', mItems[0].Name);
end;

procedure TAtlasCompletionProviderTests.PartialItemsContinueRank;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
begin
  // Teilergebnis als CompletionItem[] (#616): Rang zählt ab dem ersten Eintrag dieses Teils.
  mResponse := TJSONObject.ParseJSONValue('[{"label":"A","kind":6},5,{"label":"B","kind":6}]');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse, 10);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mItems)), 'Nicht-Objekte übersprungen');
  Assert.AreEqual('B', mItems[1].Name);
  Assert.AreEqual(10, mItems[0].Rank);
  Assert.AreEqual(12, mItems[1].Rank);
end;

procedure TAtlasCompletionProviderTests.ReadsItemArrayAndNull;
var
  mResponse: TJSONValue;
begin
  mResponse := TJSONObject.ParseJSONValue('[{"label":"A"},{"label":"B","kind":99,"filterText":"mylist"}]');
  try
    Assert.AreEqual(2, Integer(Length(TAtlasServerCompletionProvider.ItemsFromLsp(mResponse))));
    Assert.AreEqual(Ord(TAtlasItemKind.Unknown),
      Ord(TAtlasServerCompletionProvider.ItemsFromLsp(mResponse)[1].Kind));
    // Der filterText des Servers ist das getippte Wort (für VS Code); Atlas filtert gegen den Namen.
    Assert.AreEqual('', TAtlasServerCompletionProvider.ItemsFromLsp(mResponse)[1].FilterText);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasServerCompletionProvider.ItemsFromLsp(nil))));
end;

/// <summary>Mitglied eines Helpers (#456) und Angaben anderer Server.</summary>
procedure AssertHelperAndForeignDetails;
var
  mResponse: TJSONValue;
  mDetails: TAtlasItemDetails;
begin
  // Mitglied eines Helpers (#456).
  mResponse := TJSONObject.ParseJSONValue('{"label":"Trim","data":{"atlas":{"declaration":"function Trim: string;",' +
    '"unit":"System.SysUtils","container":"TStringHelper","helper":true}}}');
  try
    mDetails := TAtlasServerCompletionProvider.DetailsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.IsTrue(mDetails.IsHelper);
  Assert.AreEqual('TStringHelper', mDetails.Container);
  // Andere Server: detail und documentation.
  mResponse := TJSONObject.ParseJSONValue('{"label":"X","detail":"X: Integer","documentation":{"value":"Doku"}}');
  try
    mDetails := TAtlasServerCompletionProvider.DetailsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual('X: Integer', mDetails.Declaration);
  Assert.AreEqual('Doku', mDetails.Summary);
  Assert.IsFalse(mDetails.IsDeprecated);
  Assert.IsTrue(mDetails.Doc.IsEmpty);
  Assert.IsFalse(mDetails.Display.Known);
end;

procedure TAtlasCompletionProviderTests.ReadsResolvedDetails;
var
  mResponse: TJSONValue;
  mItems: TAtlasCompletionItems;
  mDetails: TAtlasItemDetails;
begin
  // data bleibt für completionItem/resolve erhalten.
  mResponse := TJSONObject.ParseJSONValue('[{"label":"Add","data":{"file":"C:\\P\\A.pas","line":9,"character":13}}]');
  try
    mItems := TAtlasServerCompletionProvider.ItemsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.Contains(mItems[0].ResolveData, '"line":9');
  mResponse := TJSONObject.ParseJSONValue(
    '{"label":"Add","detail":"function Add(const S: string): Integer; virtual;","data":{"atlas":{' +
    '"declaration":"function Add(const S: string): Integer; virtual;","unit":"Liste","container":"TListe",' +
    '"visibility":"public","directives":["virtual","deprecated"],"deprecated":"Neu verwenden",' +
    '"summary":"Hängt S an.","returns":"Index.","params":[{"name":"S","text":"Der Text."}],' +
    '"exceptions":[{"name":"EListError","text":"Voll."}],' +
    '"documentation":{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Hängt "},' +
    '{"kind":"paramref","text":"S"},{"kind":"text","text":" an."}]}]},' +
    '"xmlDoc":{"full":true,"maxLines":20}}}}');
  try
    mDetails := TAtlasServerCompletionProvider.DetailsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual('function Add(const S: string): Integer; virtual;', mDetails.Declaration);
  Assert.AreEqual('Liste', mDetails.UnitName);
  Assert.AreEqual('TListe', mDetails.Container);
  Assert.AreEqual('public', mDetails.Visibility);
  Assert.AreEqual(2, Integer(Length(mDetails.Directives)));
  Assert.IsTrue(mDetails.IsDeprecated);
  Assert.AreEqual('Neu verwenden', mDetails.DeprecatedText);
  Assert.AreEqual('Hängt S an.', mDetails.Summary);
  Assert.AreEqual('Index.', mDetails.Returns);
  Assert.AreEqual('Der Text.', mDetails.Params[0].Text);
  Assert.AreEqual('EListError', mDetails.Exceptions[0].Name);
  // Vollständige XMLDoc und Anzeige (#654).
  Assert.AreEqual(1, Integer(Length(mDetails.Doc.Sections)));
  Assert.AreEqual('Hängt S an.', mDetails.Doc.Sections[0].Text);
  Assert.IsTrue(mDetails.Display.Known);
  Assert.AreEqual(20, mDetails.Display.MaxLines);
  Assert.IsFalse(mDetails.IsHelper);
  AssertHelperAndForeignDetails;
end;

procedure TAtlasCompletionProviderTests.MergesProvidersAndCompletesOnce;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
begin
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.Add(TAtlasFixedCompletionProvider.Create([Item('Beta')]));
  mProviders.Add(TAtlasFixedCompletionProvider.Create([Item('Alpha'), Item('Gamma')], 50));
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(3000), 'Complete kam nicht');
  Assert.AreEqual('Alpha,Beta,Gamma', mSink.Names);
  Assert.AreEqual(1, mSink.Completed);
end;

procedure TAtlasCompletionProviderTests.CancelDropsLateItems;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
begin
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.Add(TAtlasFixedCompletionProvider.Create([Item('Spaet')], 200));
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  mProvider.Cancel;
  Assert.IsFalse(mSink.WaitDone(400), 'Nach Cancel darf kein Complete kommen');
  Assert.AreEqual('', mSink.Names);
end;

procedure TAtlasCompletionProviderTests.NewQueryReplacesRunningQuery;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mFirst, mSecond: TCollectingSink;
  mFirstRef, mSecondRef: IAtlasCompletionSink;
begin
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.Add(TAtlasFixedCompletionProvider.Create([Item('X')], 100));
  mFirst := TCollectingSink.Create;
  mFirstRef := mFirst;
  mSecond := TCollectingSink.Create;
  mSecondRef := mSecond;
  mProvider.Query(Context, mFirstRef);
  mProvider.Query(Context, mSecondRef);
  Assert.IsTrue(mSecond.WaitDone(3000), 'Complete des neuen Query kam nicht');
  Assert.AreEqual('X', mSecond.Names);
  Assert.AreEqual(0, mFirst.Completed, 'Der ersetzte Query wurde noch beendet');
  Assert.AreEqual('', mFirst.Names);
end;

procedure TAtlasCompletionProviderTests.WithoutSessionCompletesEmpty;
var
  mServer: TAtlasServerCompletionProvider;
  mProvider: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
  mLogged: string;
begin
  mServer := TAtlasServerCompletionProvider.Create(
    function: TLspSession
    begin
      Result := nil;
    end);
  mProvider := mServer;
  // Warum die Liste leer bleibt, steht im Diagnoselog des Plugins (#647).
  mLogged := '';
  mServer.OnLog :=
    procedure(const AMessage: string)
    begin
      mLogged := mLogged + AMessage;
    end;
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(0), 'Ohne Server sofort fertig');
  Assert.AreEqual('', mSink.Names);
  Assert.Contains(mLogged, 'kein Server');
end;

{ TAtlasServerCompletionTests }

procedure TAtlasItemDetailsTests.AvailabilityAloneIsNotEmpty;
var
  mDetails: TAtlasItemDetails;
begin
  mDetails := Default(TAtlasItemDetails);
  Assert.IsTrue(mDetails.IsEmpty);
  mDetails.Availability := 'Nicht verfügbar: Die Bedingung „WIN64“ ist für Win32 · Debug nicht erfüllt.';
  Assert.IsFalse(mDetails.IsEmpty);
end;

procedure TAtlasServerCompletionTests.WarmUpFirstUse;
begin
  // Erster echter Start (Pipes, Threads, Sitzung, Zeitlimit-Arbeiter) ungemessen statt [IgnoreMemoryLeaks]
  //. Ohne Server neben dem Testprogramm überspringt der Test ohnehin.
  if FileExists(TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe')) then
    try
      CompletesMembersFromServer;
    except
      // Scheitert der Lauf, meldet das der Test selbst.
      on Exception do
        ;
    end;
end;

const
  cCompletesMembersUnitText =
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

procedure TAtlasServerCompletionTests.CompletesMembersFromServer;
var
  mServerExe: string;
  mServer: TLspServerProcess;
  mSession: TLspSession;
  mProvider: TAtlasServerCompletionProvider;
  mProviderRef: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
  mQuery: TAtlasContext;
begin
  mServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(mServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + mServerExe);
  end;
  mServer := TLspServerProcess.Create(mServerExe, '');
  try
    mSession := TLspSession.Create(mServer.Client, 5000);
    try
      mSession.Initialize;
      mProvider := TAtlasServerCompletionProvider.Create(
        function: TLspSession
        begin
          Result := mSession;
        end, 5000);
      mProviderRef := mProvider;
      mQuery := Default(TAtlasContext);
      mQuery.FileName := TPath.Combine(TPath.GetTempPath, 'AtlasCompletionProbe.pas');
      mQuery.Text := cCompletesMembersUnitText;
      mQuery.Line := 11;
      // Hinter "  Self.FWe".
      mQuery.Character := 10;
      mQuery.Prefix := 'FWe';
      mQuery.Kind := TAtlasContextKind.MemberAccess;
      mSink := TCollectingSink.Create;
      mSinkRef := mSink;
      mProviderRef.Query(mQuery, mSinkRef);
      Assert.IsTrue(mSink.WaitDone(10000), 'Keine Antwort vom Server');
      Assert.Contains(mSink.Names, 'FWeite');
      Assert.Contains(mSink.Names, 'FWert');
      // Vor dem Freigeben der Sitzung auf laufende Anfragen warten.
      mProvider.Shutdown;
      mProviderRef := nil;
    finally
      mSession.Free;
    end;
  finally
    mServer.Free;
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
  cText = 'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    /// <'#13#10 +
    '    /// weiter'#13#10 +
    '    function CalcDiscount(const Customer: TCustomer;'#13#10 +
    '      Rate, Extra: Double): Currency;'#13#10 +
    '  end;';
var
  mDeclaration, mNames: string;
  mItem: TAtlasCompletionItem;
begin
  mDeclaration := TAtlasXmlDoc.FollowingDeclaration(cText, 2);
  Assert.AreEqual('function CalcDiscount(const Customer: TCustomer; Rate, Extra: Double): Currency;', mDeclaration);
  Assert.AreEqual('Customer,Rate,Extra', String.Join(',', TAtlasXmlDoc.ParamNames(mDeclaration)));
  mNames := '';
  for mItem in TAtlasXmlDoc.TagItems(mDeclaration) do
  begin
    mNames := mNames + mItem.Name + '|';
  end;
  Assert.IsTrue(mNames.StartsWith('summary|param name="Customer"|param name="Rate"|param name="Extra"|returns|'),
    mNames);
  Assert.AreEqual('summary>$0</summary>', TAtlasXmlDoc.TagItems(mDeclaration)[0].InsertText);
  // Prozedur: kein returns.
  Assert.AreNotEqual('returns', String.Join('|', [TAtlasXmlDoc.TagItems('procedure Add(A: Integer);')[2].Name]));
end;

{ TAtlasMatchingBudgetTests }

procedure TAtlasMatchingBudgetTests.Filters5000EntriesWithin12ms;
const
  cWords: array[0..11] of string = ('Add', 'String', 'List', 'Item', 'Get', 'Set', 'Count', 'Object', 'Begin',
    'Update', 'Index', 'Value');
var
  mItems: TAtlasCompletionItems;
  mIndex, mRun: Integer;
  mPattern: string;
  mWatch: TStopwatch;
  mTimes: TArray<Int64>;
begin
  SetLength(mItems, 5000);
  for mIndex := 0 to High(mItems) do
  begin
    mItems[mIndex].Name := cWords[mIndex mod 12] + cWords[(mIndex div 12) mod 12] + cWords[(mIndex div 144) mod 12] +
      IntToStr(mIndex);
    mItems[mIndex].Rank := mIndex;
  end;
  // Typische Schritte beim Tippen: Anfang, CamelCase, Teilfolge, kein Treffer.
  for mPattern in ['A', 'Ad', 'AddS', 'ASL', 'stl', 'xyz'] do
  begin
    TAtlasCompletionMatcher.Filter(mItems, mPattern);
    mTimes := nil;
    for mRun := 1 to 5 do
    begin
      mWatch := TStopwatch.StartNew;
      TAtlasCompletionMatcher.Filter(mItems, mPattern);
      mTimes := mTimes + [mWatch.ElapsedMilliseconds];
    end;
    // Median von fünf Läufen, damit ein einzelner Ausreißer der Maschine nicht zählt.
    TArray.Sort<Int64>(mTimes);
    Assert.IsTrue(mTimes[2] <= 12, Format('Filtern nach "%s" dauerte %d ms', [mPattern, mTimes[2]]));
  end;
end;

procedure TAtlasMatchingBudgetTests.Orders5000EntriesWithRestWithin16ms;
const
  cWords: array[0..11] of string = ('Add', 'String', 'List', 'Item', 'Get', 'Set', 'Count', 'Object', 'Begin',
    'Update', 'Index', 'Value');
var
  mItems: TAtlasCompletionItems;
  mIndex, mRun, mRestStart: Integer;
  mPattern: string;
  mWatch: TStopwatch;
  mTimes: TArray<Int64>;
  mOptions: TAtlasRankOptions;
  mOrder: TArray<Integer>;
begin
  SetLength(mItems, 5000);
  for mIndex := 0 to High(mItems) do
  begin
    mItems[mIndex].Name := cWords[mIndex mod 12] + cWords[(mIndex div 12) mod 12] + cWords[(mIndex div 144) mod 12] +
      IntToStr(mIndex);
    mItems[mIndex].Rank := mIndex;
  end;
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.ListMode := TAtlasListMode.Rest;
  for mPattern in ['A', 'AddS', 'ASL', 'xyz'] do
  begin
    mOrder := TAtlasRanking.Order(mItems, mPattern, mOptions, mRestStart);
    Assert.AreEqual(5000, TAtlasRanking.ItemCount(mOrder), 'Alle Einträge bleiben sichtbar');
    mTimes := nil;
    for mRun := 1 to 5 do
    begin
      mWatch := TStopwatch.StartNew;
      TAtlasRanking.Order(mItems, mPattern, mOptions, mRestStart);
      mTimes := mTimes + [mWatch.ElapsedMilliseconds];
    end;
    TArray.Sort<Int64>(mTimes);
    Assert.IsTrue(mTimes[2] <= 16, Format('Ordnen mit Rest nach "%s" dauerte %d ms', [mPattern, mTimes[2]]));
  end;
  mItems := nil;
  mOrder := nil;
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
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
  mName: string;
  mItem: TAtlasCompletionItem;
begin
  Assert.AreEqual(1, TAtlasCompletionMatcher.Distance('Lenght', 'Length'), 'Vertauschung zählt 1');
  Assert.AreEqual(1, TAtlasCompletionMatcher.Distance('lengh', 'Length'));
  Assert.AreEqual(0, TAtlasCompletionMatcher.TypoLimit('Le'));
  mItems := nil;
  for mName in ['Length', 'Low', 'High', 'Lengthy'] do
  begin
    mItem := Default(TAtlasCompletionItem);
    mItem.Name := mName;
    mItems := mItems + [mItem];
  end;
  mOrder := TAtlasRanking.Order(mItems, 'Lenght', TAtlasRankOptions.Defaults);
  Assert.AreEqual(TAtlasRanking.cTypoHeader, mOrder[0], 'keine regulären Treffer: gleich „Meintest du“');
  Assert.AreEqual('Length', mItems[mOrder[1]].Name);
  Assert.AreEqual(2, TAtlasRanking.ItemCount(mOrder), 'Length und Lengthy (Anfang), nicht Low');
  Assert.IsTrue(TAtlasRanking.OnlyTypos(mOrder), 'Fußzeile: Keine Treffer für „Lenght“');
  // Mit genug regulären Treffern keine Tippfehler-Gruppe.
  mOrder := TAtlasRanking.Order(mItems, 'L', TAtlasRankOptions.Defaults);
  Assert.IsFalse(TAtlasRanking.IsHeader(mOrder[0]));
  Assert.IsFalse(TAtlasRanking.OnlyTypos(mOrder));
  Assert.IsFalse(TAtlasRanking.OnlyTypos([TAtlasRanking.cTypoHeader]));
end;

procedure TAtlasMatchingBudgetTests.AnnouncementNamesKindPositionAndDetail;
var
  mItem: TAtlasCompletionItem;
begin
  mItem := Default(TAtlasCompletionItem);
  mItem.Name := 'ShowMessage';
  mItem.Signature := 'procedure ShowMessage(const Msg: string)';
  Assert.AreEqual('ShowMessage, Methode, 3 von 12. procedure ShowMessage(const Msg: string)',
    TAtlasItemPresentation.Announcement(mItem, 'Methode', '%d von %d', 3, 12));
  mItem.Signature := '';
  Assert.AreEqual('ShowMessage, 1 von 1.', TAtlasItemPresentation.Announcement(mItem, '', '%d von %d', 1, 1));
end;

procedure TAtlasMatchingBudgetTests.TagTextNamesStatesInWords;
var
  mItem: TAtlasCompletionItem;
begin
  mItem := Default(TAtlasCompletionItem);
  mItem.Name := 'AddPair';
  Assert.AreEqual('', TAtlasItemPresentation.TagText(mItem));
  mItem.Directives := ['deprecated'];
  mItem.IsHelper := True;
  Assert.AreEqual('deprecated, Helper', TAtlasItemPresentation.TagText(mItem));
  mItem.Directives := nil;
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
