unit Atlas.Common.Lsp.CompletionAnonymous.Tests;

// Anonyme Methoden (#468): Deklaration lesen, Typargumente einsetzen, RTL-Ersatz, Parameternamen, Gerüst und
// der Eintrag der Vervollständigung (oben, nach "(" allein, abschaltbar).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TCompletionAnonymousTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemAt(const AMarked: string; ASnippets: Boolean; const ASettings: TCompletionSettings;
      const ANamingFor: TCompletionNamingFunc; out AItem: TCompletionItem): Boolean; overload;
    function ItemAt(const AMarked: string; out AItem: TCompletionItem): Boolean; overload;
    function HeaderAt(const AMarked: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesDeclarations;
    [Test]
    procedure SplitsTypeArgs;
    [Test]
    procedure SubstitutesWholeWords;
    [Test]
    procedure RtlDeclarations;
    [Test]
    procedure NamesArgParameters;
    [Test]
    procedure BuildsSnippetAndPlain;
    [Test]
    procedure ProcedureForTaskRun;
    [Test]
    procedure PredicateGetsValue;
    [Test]
    procedure GenericRtlTypes;
    [Test]
    procedure OwnTypesAndAliases;
    [Test]
    procedure AssignmentAndResult;
    [Test]
    procedure PrefixAndOtherWords;
    [Test]
    procedure ParameterPrefix;
    [Test]
    procedure SwitchOff;
    [Test]
    procedure AloneAfterParenthesis;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.CompletionAnonymous;

const
  HauptFile = 'C:\P\Haupt.pas';
  TasksFile = 'C:\P\Tasks.pas';

  UnitTasks =
    'unit Tasks;'#10 +
    'interface'#10 +
    'uses System.SysUtils;'#10 +
    'type'#10 +
    '  TTask = class'#10 +
    '  public'#10 +
    '    class function Run(const Action: TProc): Integer;'#10 +
    '  end;'#10 +
    '  TCustomer = class'#10 +
    '  end;'#10 +
    '  TCustomers = class'#10 +
    '  public'#10 +
    '    function Find(const Filter: TPredicate<TCustomer>): TCustomer;'#10 +
    '    procedure Each(const Action: TProc<TCustomer, Integer>);'#10 +
    '    function Sum(const Value: TFunc<TCustomer, Currency>): Currency;'#10 +
    '  end;'#10 +
    '  TCalc = reference to function(const A, B: Integer): Integer;'#10 +
    '  TGenericFilter<T> = TPredicate<T>;'#10 +
    '  TCustomerFilter = TGenericFilter<TCustomer>;'#10 +
    '  TNotify = procedure(Sender: TObject) of object;'#10 +
    '  TRunner = class'#10 +
    '  public'#10 +
    '    procedure Calc(const Calc: TCalc);'#10 +
    '    procedure Filter(const Filter: TCustomerFilter);'#10 +
    '    procedure Notify(const Event: TNotify);'#10 +
    '    function Make: TCalc;'#10 +
    '  end;'#10 +
    '  TBox<T> = class'#10 +
    '  public'#10 +
    '    function Where(const Filter: TPredicate<T>): TBox<T>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses System.SysUtils, Tasks;'#10 +
    'function Main: TCalc;'#10 +
    'var'#10 +
    '  Customers: TCustomers;'#10 +
    '  Runner: TRunner;'#10 +
    '  P: TProc<string>;'#10 +
    '  Box: TBox<TCustomer>;'#10 +
    'begin'#10 +
    '  { Code }'#10 +
    'end;'#10 +
    'end.';

/// <summary>Text ohne "|" und die Position des "|".</summary>
function Split(const AMarked: string; out APosition: TTextPosition): string;
var
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  APosition := TTextPosition.Create(Line, Character);
  Result := StringReplace(AMarked, '|', '', []);
end;

function Source(const AMarked: string): string;
begin
  Result := StringReplace(UnitHaupt, '{ Code }', AMarked, []);
end;

function Param(const AModifier, AName, ATypeText: string): TMethodRefParam;
begin
  Result.Modifier := AModifier;
  Result.Name := AName;
  Result.TypeText := ATypeText;
end;

{ TCompletionAnonymousTests }

procedure TCompletionAnonymousTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitTasks, TasksFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionAnonymousTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCompletionAnonymousTests.ItemAt(const AMarked: string; ASnippets: Boolean;
  const ASettings: TCompletionSettings; const ANamingFor: TCompletionNamingFunc; out AItem: TCompletionItem): Boolean;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Request: TCompletionRequest;
begin
  Text := Split(Source(AMarked), Position);
  Tree := TPascalParser.Parse(Text);
  Request := TCompletionRequest.Create(Text, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := FResolver;
    Request.Index := FIndex;
    Request.Settings := ASettings;
    Result := TLspCompletion.AnonymousItem(Request, ASnippets, ANamingFor, AItem);
  finally
    Request.Free;
    Tree.Free;
  end;
end;

function TCompletionAnonymousTests.ItemAt(const AMarked: string; out AItem: TCompletionItem): Boolean;
begin
  Result := ItemAt(AMarked, True, TCompletionSettings.Default, nil, AItem);
end;

function TCompletionAnonymousTests.HeaderAt(const AMarked: string): string;
var
  Item: TCompletionItem;
begin
  Result := '-';
  if ItemAt(AMarked, Item) then
    Result := Item.Name;
end;

procedure TCompletionAnonymousTests.ParsesDeclarations;
var
  TypeParams: TArray<string>;
  MethodRef: TMethodRef;
  Target: string;
begin
  Assert.IsTrue(TCompletionAnonymous.Parse('TPredicate<T> = reference to function(Arg1: T): Boolean', TypeParams,
    MethodRef, Target));
  Assert.AreEqual('T', string.Join(',', TypeParams));
  Assert.IsTrue(MethodRef.IsFunction);
  Assert.AreEqual(1, Integer(Length(MethodRef.Params)));
  Assert.AreEqual('Arg1', MethodRef.Params[0].Name);
  Assert.AreEqual('T', MethodRef.Params[0].TypeText);
  Assert.AreEqual('Boolean', MethodRef.ResultType);
  // Gruppen, Modifikatoren, Vorgaben, generische Parametertypen und Constraints.
  Assert.IsTrue(TCompletionAnonymous.Parse('TCalc<T: class; U> = reference to procedure(const A, B: TArray<T>; ' +
    'var C: U; out D; E: Integer = 0);', TypeParams, MethodRef, Target));
  Assert.AreEqual('T,U', string.Join(',', TypeParams));
  Assert.IsFalse(MethodRef.IsFunction);
  Assert.AreEqual(5, Integer(Length(MethodRef.Params)));
  Assert.AreEqual('const B: TArray<T>', MethodRef.Params[1].Modifier + ' ' + MethodRef.Params[1].Name + ': ' +
    MethodRef.Params[1].TypeText);
  Assert.AreEqual('var', MethodRef.Params[2].Modifier);
  Assert.AreEqual('out', MethodRef.Params[3].Modifier);
  Assert.AreEqual('', MethodRef.Params[3].TypeText);
  Assert.AreEqual('Integer', MethodRef.Params[4].TypeText);
  // Ohne Parameter.
  Assert.IsTrue(TCompletionAnonymous.Parse('TProc = reference to procedure', TypeParams, MethodRef, Target));
  Assert.AreEqual(0, Integer(Length(MethodRef.Params)));
  // Alias und andere Typen.
  Assert.IsFalse(TCompletionAnonymous.Parse('TFilter = TPredicate<TCustomer>;', TypeParams, MethodRef, Target));
  Assert.AreEqual('TPredicate<TCustomer>', Target);
  Assert.IsFalse(TCompletionAnonymous.Parse('TNotify = procedure(Sender: TObject) of object', TypeParams, MethodRef,
    Target));
  Assert.AreEqual('', Target);
  Assert.IsFalse(TCompletionAnonymous.Parse('TFoo = class(TObject)', TypeParams, MethodRef, Target));
  Assert.AreEqual('', Target);
end;

procedure TCompletionAnonymousTests.SplitsTypeArgs;
var
  Base: string;
begin
  Assert.AreEqual('TCustomer|TFunc<Integer, string>', string.Join('|',
    TCompletionAnonymous.TypeArgs('TFunc<TCustomer, TFunc<Integer, string>>', Base)));
  Assert.AreEqual('TFunc', Base);
  Assert.AreEqual(0, Integer(Length(TCompletionAnonymous.TypeArgs('System.SysUtils.TProc', Base))));
  Assert.AreEqual('System.SysUtils.TProc', Base);
end;

procedure TCompletionAnonymousTests.SubstitutesWholeWords;
begin
  Assert.AreEqual('TArray<TCustomer>; Unit1.T; TX',
    TCompletionAnonymous.Substitute('TArray<T>; Unit1.T; TX', TArray<string>.Create('T'),
    TArray<string>.Create('TCustomer')));
  Assert.AreEqual('Integer, string', TCompletionAnonymous.Substitute('T1, T2', TArray<string>.Create('T1', 'T2'),
    TArray<string>.Create('Integer', 'string')));
end;

procedure TCompletionAnonymousTests.RtlDeclarations;
begin
  Assert.AreEqual('TProc = reference to procedure;', TCompletionAnonymous.RtlDeclaration('TProc', 0));
  Assert.AreEqual('TProc<T> = reference to procedure(Arg1: T);',
    TCompletionAnonymous.RtlDeclaration('System.SysUtils.TProc', 1));
  Assert.AreEqual('TProc<T1, T2> = reference to procedure(Arg1: T1; Arg2: T2);',
    TCompletionAnonymous.RtlDeclaration('TProc', 2));
  Assert.AreEqual('TFunc<TResult> = reference to function: TResult;', TCompletionAnonymous.RtlDeclaration('TFunc', 1));
  Assert.AreEqual('TFunc<T, TResult> = reference to function(Arg1: T): TResult;',
    TCompletionAnonymous.RtlDeclaration('SysUtils.TFunc', 2));
  Assert.AreEqual('TPredicate<T> = reference to function(Arg1: T): Boolean;',
    TCompletionAnonymous.RtlDeclaration('TPredicate', 1));
  Assert.AreEqual('', TCompletionAnonymous.RtlDeclaration('TFunc', 0));
  Assert.AreEqual('', TCompletionAnonymous.RtlDeclaration('TProc', 5));
  Assert.AreEqual('', TCompletionAnonymous.RtlDeclaration('TPredicate', 2));
  Assert.AreEqual('', TCompletionAnonymous.RtlDeclaration('TList', 1));
end;

procedure TCompletionAnonymousTests.NamesArgParameters;
var
  MethodRef: TMethodRef;
begin
  MethodRef := Default(TMethodRef);
  MethodRef.Params := [Param('', 'Arg1', 'TCustomer')];
  Assert.AreEqual('procedure(const Value: TCustomer)',
    TCompletionAnonymous.Header(TCompletionAnonymous.Named(MethodRef, '')));
  // Mehrere: nach dem Typ, sonst nummeriert; eigene Namen und Modifikatoren bleiben, Dubletten bekommen eine Zahl.
  MethodRef.Params := [Param('', 'Arg1', 'TCustomer'), Param('', 'Arg2', 'Integer'), Param('var', 'Arg3', 'TCustomer'),
    Param('', 'Own', 'string')];
  Assert.AreEqual('procedure(const Customer: TCustomer; const Value2: Integer; var Customer2: TCustomer; Own: string)',
    TCompletionAnonymous.Header(TCompletionAnonymous.Named(MethodRef, '')));
  // Präfix der Parameter.
  MethodRef.Params := [Param('', 'Arg1', 'string')];
  Assert.AreEqual('procedure(const AValue: string)',
    TCompletionAnonymous.Header(TCompletionAnonymous.Named(MethodRef, 'A')));
end;

procedure TCompletionAnonymousTests.BuildsSnippetAndPlain;
var
  MethodRef: TMethodRef;
begin
  MethodRef := Default(TMethodRef);
  Assert.AreEqual('procedure'#10'  begin'#10'    $0'#10'  end', TCompletionAnonymous.Snippet(MethodRef));
  Assert.AreEqual('procedure'#13#10'      begin'#13#10#13#10'      end',
    TCompletionAnonymous.Plain(MethodRef, '    ', #13#10));
  MethodRef.IsFunction := True;
  MethodRef.ResultType := 'Boolean';
  MethodRef.Params := [Param('const', 'Value', 'TCustomer')];
  Assert.AreEqual('function(const Value: TCustomer): Boolean'#10'  begin'#10'    Result := $0'#10'  end',
    TCompletionAnonymous.Snippet(MethodRef));
  Assert.AreEqual('function(const Value: TCustomer): Boolean'#10'  begin'#10'    Result := '#10'  end',
    TCompletionAnonymous.Plain(MethodRef, '', #10));
  // "$" im Typ (z. B. Konstanten) maskiert.
  MethodRef.ResultType := 'T$';
  Assert.IsTrue(TCompletionAnonymous.Snippet(MethodRef).Contains('T\$'));
end;

procedure TCompletionAnonymousTests.ProcedureForTaskRun;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(ItemAt('TTask.Run(|', Item));
  Assert.AreEqual('procedure', Item.Name);
  Assert.AreEqual('TProc', Item.MethodRef);
  Assert.AreEqual('anonyme Methode', Item.Detail);
  Assert.AreEqual('anonymous', Item.Action);
  Assert.IsTrue(Item.Snippet);
  Assert.IsTrue(Item.Pinned);
  Assert.AreEqual(KindSnippet, Item.Kind);
  Assert.AreEqual('procedure'#10'  begin'#10'    $0'#10'  end', Item.TextEdit.NewText);
  Assert.AreEqual(12, Item.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(12, Item.TextEdit.Range.EndPos.Character);
end;

procedure TCompletionAnonymousTests.PredicateGetsValue;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(ItemAt('Customers.Find(|', Item));
  Assert.AreEqual('function(const Value: TCustomer): Boolean', Item.Name);
  Assert.AreEqual('function', Item.FilterText);
  Assert.AreEqual('function(const Value: TCustomer): Boolean'#10'  begin'#10'    Result := $0'#10'  end',
    Item.TextEdit.NewText);
end;

procedure TCompletionAnonymousTests.GenericRtlTypes;
begin
  Assert.AreEqual('procedure(const Customer: TCustomer; const Value2: Integer)', HeaderAt('Customers.Each(|'));
  Assert.AreEqual('function(const Value: TCustomer): Currency', HeaderAt('Customers.Sum(|'));
  // Typparameter der Klasse aus dem Typ der Variablen.
  Assert.AreEqual('function(const Value: TCustomer): Boolean', HeaderAt('Box.Where(|'));
end;

procedure TCompletionAnonymousTests.OwnTypesAndAliases;
begin
  // Eigene Namen aus der Deklaration bleiben.
  Assert.AreEqual('function(const A: Integer; const B: Integer): Integer', HeaderAt('Runner.Calc(|'));
  // Alias auf einen generischen Alias auf TPredicate<T>.
  Assert.AreEqual('function(const Value: TCustomer): Boolean', HeaderAt('Runner.Filter(|'));
  // Methodenzeiger "of object" sind Ereignisse (#444), keine anonymen Methoden.
  Assert.AreEqual('-', HeaderAt('Runner.Notify(|'));
  // Andere Parametertypen.
  Assert.AreEqual('-', HeaderAt('Customers.Find(nil); Writeln(|'));
end;

procedure TCompletionAnonymousTests.AssignmentAndResult;
begin
  Assert.AreEqual('procedure(const Value: string)', HeaderAt('P := |'));
  Assert.AreEqual('function(const A: Integer; const B: Integer): Integer', HeaderAt('Result := |'));
end;

procedure TCompletionAnonymousTests.PrefixAndOtherWords;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(ItemAt('TTask.Run(pro|', Item));
  Assert.AreEqual(12, Item.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(15, Item.TextEdit.Range.EndPos.Character);
  Assert.IsTrue(ItemAt('Customers.Find(Func|', Item));
  Assert.IsFalse(ItemAt('TTask.Run(Cust|', Item));
  Assert.IsFalse(ItemAt('TTask.|', Item));
end;

procedure TCompletionAnonymousTests.ParameterPrefix;
var
  Item: TCompletionItem;
  NamingFor: TCompletionNamingFunc;
begin
  // Typisierte Variable: ItemAt ist überladen.
  NamingFor :=
    function(const AUri: string; AKind: TNamingKind): string
    begin
      Result := '';
      if AKind = TNamingKind.Parameter then
        Result := 'A';
    end;
  Assert.IsTrue(ItemAt('P := |', True, TCompletionSettings.Default, NamingFor, Item));
  Assert.AreEqual('procedure(const AValue: string)', Item.Name);
  // Ohne Platzhalter: Klartext mit der Einrückung der Zeile.
  Assert.IsTrue(ItemAt('P := |', False, TCompletionSettings.Default, nil, Item));
  Assert.IsFalse(Item.Snippet);
  Assert.AreEqual('procedure(const Value: string)'#10'    begin'#10#10'    end', Item.TextEdit.NewText);
end;

procedure TCompletionAnonymousTests.SwitchOff;
var
  Settings: TCompletionSettings;
  Item: TCompletionItem;
begin
  Settings := TCompletionSettings.Default;
  Settings.AnonymousMethods := False;
  Assert.IsFalse(ItemAt('TTask.Run(|', True, Settings, nil, Item));
end;

procedure TCompletionAnonymousTests.AloneAfterParenthesis;
var
  Text, Uri, Answer: string;
  Store: IDocumentStore;
  Completion: TLspCompletion;
  Dispatcher: TJsonRpcDispatcher;
  Position: TTextPosition;

  function Ask(const ATrigger: string): string;
  var
    Request, Response: TJSONObject;
    Trigger: string;
  begin
    Trigger := '';
    if ATrigger <> '' then
      Trigger := ',"context":{"triggerKind":2,"triggerCharacter":"' + ATrigger + '"}';
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/completion",' +
      '"params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"position":{"line":' +
      IntToStr(Position.Line) + ',"character":' + IntToStr(Position.Character) + '}' + Trigger + '}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
      try
        Result := Response.ToJSON;
      finally
        Response.Free;
      end;
    finally
      Request.Free;
    end;
  end;

begin
  Text := Split(Source('TTask.Run(|'), Position);
  Uri := TDocumentUris.FromPath(HauptFile);
  Store := TDocumentStore.Create;
  Store.Open(Uri, 'delphi', 1, Text);
  Completion := TLspCompletion.Create(Store, FIndex);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Completion.Attach(Dispatcher);
    // Nach "(": nur das Gerüst.
    Answer := Ask('(');
    Assert.IsTrue(Answer.Contains('"label":"procedure"'), Answer);
    Assert.IsTrue(Answer.Contains('"methodRef":"TProc"'), Answer);
    Assert.IsFalse(Answer.Contains('"label":"Customers"'), Answer);
    // Strg+Leer: oben, die übrige Liste bleibt.
    Answer := Ask('');
    Assert.IsTrue(Answer.Contains('"label":"procedure"'), Answer);
    Assert.IsTrue(Answer.Contains('"label":"Customers"'), Answer);
    Assert.IsTrue(Pos('"label":"procedure"', Answer) < Pos('"label":"Customers"', Answer), Answer);
  finally
    Dispatcher.Free;
    Completion.Free;
  end;
end;

end.
