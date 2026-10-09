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
    procedure ReadsItemArrayAndNull;
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

initialization
  TDUnitX.RegisterTestFixture(TArgusCompletionProviderTests);
  TDUnitX.RegisterTestFixture(TArgusServerCompletionTests);

end.
