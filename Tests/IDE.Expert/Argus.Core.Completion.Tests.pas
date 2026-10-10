unit Argus.Core.Completion.Tests;

// Tests der Datenquellen der Vervollständigung (#408).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusCompletionProviderTests = class
  public
    [Test]
    procedure MapsLspCompletionList;
    [Test]
    procedure ReadsTextEditOfPostfixItems;
    [Test]
    procedure ReadsItemArrayAndNull;
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
  TArgusServerCompletionTests = class
  public
    // Startet den echten Server neben dem Testprogramm.
    [Test]
    [IgnoreMemoryLeaks]
    procedure CompletesMembersFromServer;
  end;

  /// <summary>XMLDoc-Tags in ///-Kommentaren (#435).</summary>
  [TestFixture]
  TArgusXmlDocTests = class
  public
    [Test]
    procedure RecognizesTagContext;
    [Test]
    procedure OffersParamsOfFollowingMethod;
  end;

  /// <summary>Zeitbudget (#409): Filtern und Sortieren beim Weitertippen.</summary>
  [TestFixture]
  TArgusMatchingBudgetTests = class
  public
    [Test]
    procedure Filters5000EntriesWithin12ms;
  end;

  [TestFixture]
  TArgusWordTests = class
  public
    [Test]
    procedure FindsStartBeforeCursor;
    [Test]
    procedure FindsEndBehindCursorInsideWord;
    [Test]
    procedure EndStaysAtCursorWithoutWordBehind;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Composite,
  Argus.Core.Completion.Providers.Fixed,
  Argus.Core.Completion.Providers.Server,
  Argus.Core.Completion.Word,
  Argus.Core.Completion.Matching,
  Argus.Core.Completion.Providers.XmlDoc,
  System.Diagnostics,
  Argus.Core.Lsp.Session,
  Argus.Core.Lsp.Adapters.ServerProcess;

type
  /// <summary>Sammelt Einträge aus beliebigen Threads und meldet Complete über ein Ereignis.</summary>
  TCollectingSink = class(TInterfacedObject, IArgusCompletionSink)
  private
    FLock: TCriticalSection;
    FNames: TList<string>;
    FCompleted: Integer;
    FDone: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddItems(const AItems: TArgusCompletionItems);
    procedure MarkIncomplete;
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

procedure TCollectingSink.AddItems(const AItems: TArgusCompletionItems);
var
  Item: TArgusCompletionItem;
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

function Item(const AName: string): TArgusCompletionItem;
begin
  Result := Default(TArgusCompletionItem);
  Result.Name := AName;
end;

function Context: TArgusContext;
begin
  Result := Default(TArgusContext);
  Result.FileName := 'C:\P\A.pas';
end;

{ TArgusCompletionProviderTests }

procedure TArgusCompletionProviderTests.ReadsTextEditOfPostfixItems;
var
  Response: TJSONValue;
  Items: TArgusCompletionItems;
begin
  // Liste.for (#188): ersetzt ab dem Anfang von "Liste" bis zum Cursor.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[{"label":"for","kind":15,"filterText":"Liste.for",' +
    '"textEdit":{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":10}},' +
    '"newText":"for var Item in Liste do\n    "}},{"label":"Count","kind":10}]}');
  try
    Items := TArgusServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(Ord(TArgusItemKind.Snippet), Ord(Items[0].Kind));
  Assert.IsTrue(Items[0].HasTextEdit);
  Assert.AreEqual(7, Items[0].TextEdit.StartLine);
  Assert.AreEqual(2, Items[0].TextEdit.StartCharacter);
  Assert.AreEqual(10, Items[0].TextEdit.EndCharacter);
  Assert.AreEqual('for var Item in Liste do'#10'    ', Items[0].TextEdit.NewText);
  Assert.IsFalse(Items[1].HasTextEdit);
end;

procedure TArgusCompletionProviderTests.MapsLspCompletionList;
var
  Response: TJSONValue;
  Items: TArgusCompletionItems;
begin
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"Add","kind":2,"detail":"function Add(const S: string): Integer",' +
    '"documentation":{"kind":"plaintext","value":"Hängt S an."},' +
    '"additionalTextEdits":[{"range":{"start":{"line":2,"character":5},"end":{"line":2,"character":5}},' +
    '"newText":", System.Classes"}]},' +
    '{"label":"TFoo","kind":7,"documentation":"Klasse"}]}');
  try
    Items := TArgusServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('Add', Items[0].Name);
  Assert.AreEqual(Ord(TArgusItemKind.Method), Ord(Items[0].Kind));
  Assert.AreEqual('function Add(const S: string): Integer', Items[0].Signature);
  Assert.AreEqual('Hängt S an.', Items[0].Documentation);
  Assert.AreEqual(1, Integer(Length(Items[0].AdditionalEdits)));
  Assert.AreEqual(2, Items[0].AdditionalEdits[0].StartLine);
  Assert.AreEqual(5, Items[0].AdditionalEdits[0].EndCharacter);
  Assert.AreEqual(', System.Classes', Items[0].AdditionalEdits[0].NewText);
  Assert.IsFalse(Items[0].UnitUsed, 'Eintrag mit uses-Ergänzung');
  Assert.AreEqual(Ord(TArgusItemKind.Class_), Ord(Items[1].Kind));
  Assert.AreEqual('Klasse', Items[1].Documentation);
  Assert.IsTrue(Items[1].UnitUsed);
  Assert.AreEqual(1, Items[1].Rank);
end;

procedure TArgusCompletionProviderTests.ReadsItemArrayAndNull;
var
  Response: TJSONValue;
begin
  Response := TJSONObject.ParseJSONValue('[{"label":"A"},{"label":"B","kind":99,"filterText":"mylist"}]');
  try
    Assert.AreEqual(2, Integer(Length(TArgusServerCompletionProvider.ItemsFromLsp(Response))));
    Assert.AreEqual(Ord(TArgusItemKind.Unknown),
      Ord(TArgusServerCompletionProvider.ItemsFromLsp(Response)[1].Kind));
    // Der filterText des Servers ist das getippte Wort (für VS Code); Argus filtert gegen den Namen.
    Assert.AreEqual('', TArgusServerCompletionProvider.ItemsFromLsp(Response)[1].FilterText);
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TArgusServerCompletionProvider.ItemsFromLsp(nil))));
end;

procedure TArgusCompletionProviderTests.ReadsResolvedDetails;
var
  Response: TJSONValue;
  Items: TArgusCompletionItems;
  Details: TArgusItemDetails;
begin
  // data bleibt für completionItem/resolve erhalten.
  Response := TJSONObject.ParseJSONValue('[{"label":"Add","data":{"file":"C:\\P\\A.pas","line":9,"character":13}}]');
  try
    Items := TArgusServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.Contains(Items[0].ResolveData, '"line":9');
  Response := TJSONObject.ParseJSONValue(
    '{"label":"Add","detail":"function Add(const S: string): Integer; virtual;","data":{"argus":{' +
    '"declaration":"function Add(const S: string): Integer; virtual;","unit":"Liste","container":"TListe",' +
    '"visibility":"public","directives":["virtual","deprecated"],"deprecated":"Neu verwenden",' +
    '"summary":"Hängt S an.","returns":"Index.","params":[{"name":"S","text":"Der Text."}],' +
    '"exceptions":[{"name":"EListError","text":"Voll."}]}}}');
  try
    Details := TArgusServerCompletionProvider.DetailsFromLsp(Response);
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
  // Andere Server: detail und documentation.
  Response := TJSONObject.ParseJSONValue('{"label":"X","detail":"X: Integer","documentation":{"value":"Doku"}}');
  try
    Details := TArgusServerCompletionProvider.DetailsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('X: Integer', Details.Declaration);
  Assert.AreEqual('Doku', Details.Summary);
  Assert.IsFalse(Details.IsDeprecated);
end;

procedure TArgusCompletionProviderTests.MergesProvidersAndCompletesOnce;
var
  Providers: TArgusCompletionProviders;
  Provider: IArgusCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IArgusCompletionSink;
begin
  Providers := TArgusCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TArgusFixedCompletionProvider.Create([Item('Beta')]));
  Providers.Add(TArgusFixedCompletionProvider.Create([Item('Alpha'), Item('Gamma')], 50));
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(3000), 'Complete kam nicht');
  Assert.AreEqual('Alpha,Beta,Gamma', Sink.Names);
  Assert.AreEqual(1, Sink.Completed);
end;

procedure TArgusCompletionProviderTests.CancelDropsLateItems;
var
  Providers: TArgusCompletionProviders;
  Provider: IArgusCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IArgusCompletionSink;
begin
  Providers := TArgusCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TArgusFixedCompletionProvider.Create([Item('Spaet')], 200));
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Provider.Cancel;
  Assert.IsFalse(Sink.WaitDone(400), 'Nach Cancel darf kein Complete kommen');
  Assert.AreEqual('', Sink.Names);
end;

procedure TArgusCompletionProviderTests.NewQueryReplacesRunningQuery;
var
  Providers: TArgusCompletionProviders;
  Provider: IArgusCompletionProvider;
  First, Second: TCollectingSink;
  FirstRef, SecondRef: IArgusCompletionSink;
begin
  Providers := TArgusCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TArgusFixedCompletionProvider.Create([Item('X')], 100));
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

procedure TArgusCompletionProviderTests.WithoutSessionCompletesEmpty;
var
  Provider: IArgusCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IArgusCompletionSink;
begin
  Provider := TArgusServerCompletionProvider.Create(
    function: TLspSession
    begin
      Result := nil;
    end);
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(0), 'Ohne Server sofort fertig');
  Assert.AreEqual('', Sink.Names);
end;

{ TArgusServerCompletionTests }

procedure TArgusServerCompletionTests.CompletesMembersFromServer;
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
  Provider: TArgusServerCompletionProvider;
  ProviderRef: IArgusCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IArgusCompletionSink;
  Query: TArgusContext;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'ArgusServer.exe');
  if not FileExists(ServerExe) then
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Provider := TArgusServerCompletionProvider.Create(
        function: TLspSession
        begin
          Result := Session;
        end, 5000);
      ProviderRef := Provider;
      Query := Default(TArgusContext);
      Query.FileName := TPath.Combine(TPath.GetTempPath, 'ArgusCompletionProbe.pas');
      Query.Text := UnitText;
      Query.Line := 11;
      // Hinter "  Self.FWe".
      Query.Character := 10;
      Query.Prefix := 'FWe';
      Query.Kind := TArgusContextKind.MemberAccess;
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

{ TArgusXmlDocTests }

procedure TArgusXmlDocTests.RecognizesTagContext;
begin
  Assert.IsTrue(TArgusXmlDoc.IsTagContext('  /// <'));
  Assert.IsTrue(TArgusXmlDoc.IsTagContext('  /// Text <su'));
  Assert.IsFalse(TArgusXmlDoc.IsTagContext('  // <'), 'nur ///');
  Assert.IsFalse(TArgusXmlDoc.IsTagContext('  /// Text'));
  Assert.IsFalse(TArgusXmlDoc.IsTagContext('  if A < B'));
end;

procedure TArgusXmlDocTests.OffersParamsOfFollowingMethod;
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
  Item: TArgusCompletionItem;
begin
  Declaration := TArgusXmlDoc.FollowingDeclaration(Text, 2);
  Assert.AreEqual('function CalcDiscount(const Customer: TCustomer; Rate, Extra: Double): Currency;', Declaration);
  Assert.AreEqual('Customer,Rate,Extra', String.Join(',', TArgusXmlDoc.ParamNames(Declaration)));
  Names := '';
  for Item in TArgusXmlDoc.TagItems(Declaration) do
    Names := Names + Item.Name + '|';
  Assert.IsTrue(Names.StartsWith('summary|param name="Customer"|param name="Rate"|param name="Extra"|returns|'),
    Names);
  Assert.AreEqual('summary>$0</summary>', TArgusXmlDoc.TagItems(Declaration)[0].InsertText);
  // Prozedur: kein returns.
  Assert.IsFalse(String.Join('|', [TArgusXmlDoc.TagItems('procedure Add(A: Integer);')[2].Name]) = 'returns');
end;

{ TArgusMatchingBudgetTests }

procedure TArgusMatchingBudgetTests.Filters5000EntriesWithin12ms;
const
  Words: array[0..11] of string = ('Add', 'String', 'List', 'Item', 'Get', 'Set', 'Count', 'Object', 'Begin',
    'Update', 'Index', 'Value');
var
  Items: TArgusCompletionItems;
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
    TArgusCompletionMatcher.Filter(Items, Pattern);
    Times := nil;
    for Run := 1 to 5 do
    begin
      Watch := TStopwatch.StartNew;
      TArgusCompletionMatcher.Filter(Items, Pattern);
      Times := Times + [Watch.ElapsedMilliseconds];
    end;
    // Median von fünf Läufen, damit ein einzelner Ausreißer der Maschine nicht zählt.
    TArray.Sort<Int64>(Times);
    Assert.IsTrue(Times[2] <= 12, Format('Filtern nach "%s" dauerte %d ms', [Pattern, Times[2]]));
  end;
end;

{ TArgusWordTests }

procedure TArgusWordTests.FindsStartBeforeCursor;
begin
  // "  myList := TStringL|ist.": Präfix ab Index 12.
  Assert.AreEqual(12, TArgusWord.StartBefore('  myList := TStringList.', 20));
  Assert.AreEqual(0, TArgusWord.StartBefore('Format', 3));
  Assert.AreEqual(5, TArgusWord.StartBefore('List.Ad', 7));
  Assert.AreEqual(5, TArgusWord.StartBefore('List.', 5));
end;

procedure TArgusWordTests.FindsEndBehindCursorInsideWord;
begin
  // Mitten im Wort: bis zum Punkt ersetzen, nicht nur bis zum Cursor.
  Assert.AreEqual(23, TArgusWord.EndAfter('  myList := TStringList.', 20));
  Assert.AreEqual(6, TArgusWord.EndAfter('Format', 3));
  Assert.AreEqual(5, TArgusWord.EndAfter('Größe(', 2));
end;

procedure TArgusWordTests.EndStaysAtCursorWithoutWordBehind;
begin
  Assert.AreEqual(4, TArgusWord.EndAfter('List.Add', 4));
  Assert.AreEqual(6, TArgusWord.EndAfter('Format', 6));
  Assert.AreEqual(8, TArgusWord.EndAfter('  Add(  ', 8));
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusCompletionProviderTests);
  TDUnitX.RegisterTestFixture(TArgusServerCompletionTests);
  TDUnitX.RegisterTestFixture(TArgusXmlDocTests);
  TDUnitX.RegisterTestFixture(TArgusMatchingBudgetTests);
  TDUnitX.RegisterTestFixture(TArgusWordTests);

end.
