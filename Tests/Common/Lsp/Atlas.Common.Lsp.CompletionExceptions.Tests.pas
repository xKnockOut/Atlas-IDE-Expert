unit Atlas.Common.Lsp.CompletionExceptions.Tests;

// Exception-Klassen nach raise und on (#483): nur Exception-Klassen, Projekt vor Bibliothek, Create/CreateFmt,
// Gruppen "Aus dem try-Block"/"Allgemein", behandelte Klassen fehlen, Warnung bei falscher Reihenfolge der Zweige,
// Schalter completion.exceptionClasses. Testquellen in ASCII (FPC-Harness: TRegEx und Nicht-ASCII).

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
  TCompletionExceptionsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AMarked: string; const ASettings: TCompletionSettings;
      const APostfix: TPostfixOptions): TCompletionItems; overload;
    function ItemsAt(const AMarked: string; const ASettings: TCompletionSettings): TCompletionItems; overload;
    function ItemsAt(const AMarked: string): TCompletionItems; overload;
    function Find(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Boolean;
    function IndexOf(const AItems: TCompletionItems; const AName: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RaiseOffersOnlyExceptionClasses;
    [Test]
    procedure RaiseProjectBeforeLibrary;
    [Test]
    procedure RaiseInsertsCreateAndCreateFmt;
    [Test]
    procedure RaiseWithoutSnippets;
    [Test]
    procedure HandlerShowsTryClassesFirst;
    [Test]
    procedure HandlerReadsXmlDoc;
    [Test]
    procedure HandlerAddsUsesForTryClasses;
    [Test]
    procedure HandlerSkipsHandledClasses;
    [Test]
    procedure HandlerWarnsAboutOrder;
    [Test]
    procedure HandlerWithoutTryClassesHasNoGroups;
    [Test]
    procedure SiteNeedsExcept;
    [Test]
    procedure WritesJson;
    [Test]
    procedure SwitchOff;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.CompletionExceptions;

const
  HauptFile = 'C:\P\Haupt.pas';
  SysUtilsFile = 'C:\Rtl\System.SysUtils.pas';
  ClassesFile = 'C:\Rtl\System.Classes.pas';

  UnitSysUtils =
    'unit System.SysUtils;'#10 +
    'interface'#10 +
    'type'#10 +
    '  Exception = class(TObject)'#10 +
    '  public'#10 +
    '    constructor Create(const Msg: string);'#10 +
    '    constructor CreateFmt(const Msg: string; const Args: array of const);'#10 +
    '  end;'#10 +
    '  EConvertError = class(Exception);'#10 +
    '  EAbort = class(Exception);'#10 +
    '  TFormatSettings = record'#10 +
    '  end;'#10 +
    'function StrToInt(const S: string): Integer;'#10 +
    'implementation'#10 +
    'constructor Exception.Create(const Msg: string); begin end;'#10 +
    'constructor Exception.CreateFmt(const Msg: string; const Args: array of const); begin end;'#10 +
    'function StrToInt(const S: string): Integer; begin Result := 0; end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  System.SysUtils;'#10 +
    'type'#10 +
    '  EAppError = class(Exception);'#10 +
    '  ELoadError = class(EAppError);'#10 +
    '  TWorker = class'#10 +
    '  public'#10 +
    '    /// <summary>Loads the data.</summary>'#10 +
    '    /// <exception cref="ELoadError">When the file is broken.</exception>'#10 +
    '    procedure Load;'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TWorker.Load;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TWorker.Run;'#10 +
    'var'#10 +
    '  Value: Integer;'#10 +
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

{ TCompletionExceptionsTests }

procedure TCompletionExceptionsTests.Setup;
var
  Rtl: TUnitIndex;
begin
  FIndex := TSymbolIndex.Create;
  Rtl := TIndexExtractor.ExtractText(UnitSysUtils, SysUtilsFile, nil);
  Rtl.Library_ := True;
  FIndex.AddUnit(Rtl);
  Rtl := TIndexExtractor.ExtractText('unit System.Classes;'#10'interface'#10'uses'#10'  System.SysUtils;'#10 +
    'type'#10'  EFOpenError = class(Exception);'#10'implementation'#10'end.', ClassesFile, nil);
  Rtl.Library_ := True;
  FIndex.AddUnit(Rtl);
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionExceptionsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCompletionExceptionsTests.ItemsAt(const AMarked: string; const ASettings: TCompletionSettings;
  const APostfix: TPostfixOptions): TCompletionItems;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Request: TCompletionRequest;
begin
  Text := Split(StringReplace(UnitHaupt, '{ Code }', AMarked, []), Position);
  Tree := TPascalParser.Parse(Text);
  FIndex.AddUnit(TIndexExtractor.ExtractText(StringReplace(Text, '|', '', []), HauptFile, nil));
  Request := TCompletionRequest.Create(Text, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := FResolver;
    Request.Index := FIndex;
    Request.Matching := TCompletionMatching.Prefix;
    Request.Settings := ASettings;
    Result := TLspCompletion.Collect(Request, APostfix, nil);
  finally
    Request.Free;
    Tree.Free;
  end;
end;

function TCompletionExceptionsTests.ItemsAt(const AMarked: string;
  const ASettings: TCompletionSettings): TCompletionItems;
begin
  Result := ItemsAt(AMarked, ASettings, Default(TPostfixOptions));
end;

function TCompletionExceptionsTests.ItemsAt(const AMarked: string): TCompletionItems;
begin
  Result := ItemsAt(AMarked, TCompletionSettings.Default);
end;

function TCompletionExceptionsTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AItems, AName);
  Result := Index >= 0;
  if Result then
    AItem := AItems.Items[Index]
  else
    AItem := Default(TCompletionItem);
end;

function TCompletionExceptionsTests.IndexOf(const AItems: TCompletionItems; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AItems.Items) do
    if AItems.Items[Index].Name = AName then
      Exit(Index);
  Result := -1;
end;

procedure TCompletionExceptionsTests.RaiseOffersOnlyExceptionClasses;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('raise |');
  Assert.IsTrue(Find(Items, 'EAppError', Item), 'Projektklasse fehlt');
  Assert.IsTrue(Find(Items, 'ELoadError', Item), 'Nachfahre fehlt');
  Assert.IsTrue(Find(Items, 'Exception', Item), 'Exception fehlt');
  Assert.IsTrue(Find(Items, 'EConvertError', Item), 'RTL-Klasse fehlt');
  Assert.AreEqual(-1, IndexOf(Items, 'TWorker'), 'keine Exception');
  Assert.AreEqual(-1, IndexOf(Items, 'TFormatSettings'), 'kein Record');
  Assert.AreEqual(-1, IndexOf(Items, 'Value'), 'keine Variable');
  Assert.AreEqual(-1, IndexOf(Items, 'StrToInt'), 'keine Routine');
end;

procedure TCompletionExceptionsTests.RaiseProjectBeforeLibrary;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt('raise E|');
  Assert.IsTrue(IndexOf(Items, 'EAppError') >= 0);
  Assert.IsTrue(IndexOf(Items, 'EAppError') < IndexOf(Items, 'EConvertError'), 'Projekt vor Bibliothek');
  Assert.IsTrue(IndexOf(Items, 'ELoadError') < IndexOf(Items, 'EAbort'), 'Projekt vor Bibliothek');
end;

procedure TCompletionExceptionsTests.RaiseInsertsCreateAndCreateFmt;
var
  Postfix: TPostfixOptions;
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Postfix := Default(TPostfixOptions);
  Postfix.Snippet := True;
  Items := ItemsAt('raise EApp|', TCompletionSettings.Default, Postfix);
  Assert.IsTrue(Find(Items, 'EAppError', Item));
  Assert.AreEqual('EAppError.Create(''$0'')', Item.InsertText);
  Assert.IsTrue(Item.Snippet);
  Assert.AreEqual(TCompletionExceptions.GroupRaise, Item.ExceptionGroup);
  Assert.IsTrue(Find(Items, 'EAppError.CreateFmt', Item), 'eigener Eintrag fuer CreateFmt');
  Assert.AreEqual('EAppError.CreateFmt(''$1'', [$2])$0', Item.InsertText);
  Assert.AreEqual(KindConstructor, Item.Kind);
  Assert.AreEqual('EAppError', Item.FilterText);
  Assert.AreEqual(IndexOf(Items, 'EAppError') + 1, IndexOf(Items, 'EAppError.CreateFmt'), 'direkt dahinter');
end;

procedure TCompletionExceptionsTests.RaiseWithoutSnippets;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('raise EApp|');
  Assert.IsTrue(Find(Items, 'EAppError', Item));
  Assert.AreEqual('EAppError.Create('''')', Item.InsertText);
  Assert.IsFalse(Item.Snippet);
  Assert.IsTrue(Find(Items, 'EAppError.CreateFmt', Item));
  Assert.AreEqual('EAppError.CreateFmt('''', [])', Item.InsertText);
end;

procedure TCompletionExceptionsTests.HandlerShowsTryClassesFirst;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  // Akzeptanz: Nach StrToInt im try zeigt "on E: " als erstes EConvertError.
  Items := ItemsAt('try'#10'    Value := StrToInt(''1'');'#10'  except'#10'    on E: |');
  Assert.IsTrue(Length(Items.Items) > 0);
  Assert.AreEqual('EConvertError', Items.Items[0].Name);
  Assert.AreEqual(TCompletionExceptions.GroupTry, Items.Items[0].ExceptionGroup);
  Assert.IsTrue(Items.Items[0].Fits);
  Assert.IsTrue(Find(Items, 'EAppError', Item));
  Assert.AreEqual(TCompletionExceptions.GroupGeneral, Item.ExceptionGroup);
  Assert.IsFalse(Item.Fits);
  Assert.AreEqual(-1, IndexOf(Items, 'TWorker'));
end;

procedure TCompletionExceptionsTests.HandlerReadsXmlDoc;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt('try'#10'    Load;'#10'    Value := StrToInt(''1'');'#10'  except'#10'    on E: |');
  Assert.IsTrue(Length(Items.Items) > 1);
  Assert.AreEqual('ELoadError', Items.Items[0].Name, 'Reihenfolge der Aufrufe');
  Assert.AreEqual('EConvertError', Items.Items[1].Name);
  Assert.AreEqual(TCompletionExceptions.GroupTry, Items.Items[1].ExceptionGroup);
end;

procedure TCompletionExceptionsTests.HandlerAddsUsesForTryClasses;
var
  Items: TCompletionItems;
begin
  // LoadFromFile ohne aufgeloesten Empfaenger: bekannter Fall der RTL, Klasse aus nicht eingebundener Unit.
  Items := ItemsAt('try'#10'    Lines.LoadFromFile(''a.txt'');'#10'  except'#10'    on E: |');
  Assert.IsTrue(Length(Items.Items) > 0);
  Assert.AreEqual('EFOpenError', Items.Items[0].Name);
  Assert.AreEqual(TCompletionExceptions.GroupTry, Items.Items[0].ExceptionGroup);
  Assert.AreEqual(1, Integer(Length(Items.Items[0].AdditionalEdits)), 'uses ergaenzen');
  Assert.IsTrue(Items.Items[0].AdditionalEdits[0].NewText.Contains('System.Classes'));
end;

procedure TCompletionExceptionsTests.HandlerSkipsHandledClasses;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt('try'#10'    Value := StrToInt(''1'');'#10'  except'#10'    on E: EConvertError do'#10 +
    '      Value := 0;'#10'    on E: |');
  Assert.AreEqual(-1, IndexOf(Items, 'EConvertError'), 'schon behandelt');
  Assert.IsTrue(IndexOf(Items, 'EAppError') >= 0);
end;

procedure TCompletionExceptionsTests.HandlerWarnsAboutOrder;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  // Akzeptanz: on E: Exception vor on E: EConvertError erzeugt die Warnung.
  Items := ItemsAt('try'#10'    Value := 1;'#10'  except'#10'    on E: Exception do'#10'      Value := 0;'#10 +
    '    on E: |');
  Assert.IsTrue(Find(Items, 'EConvertError', Item));
  Assert.AreEqual('Exception', Item.Unreachable);
  Assert.AreEqual(-1, IndexOf(Items, 'Exception'), 'schon behandelt');
  // Zweig danach (nicht davor) loest keine Warnung aus.
  Items := ItemsAt('try'#10'    Value := 1;'#10'  except'#10'    on E: E|'#10'    on E: Exception do'#10 +
    '      Value := 0;');
  Assert.IsTrue(Find(Items, 'EConvertError', Item));
  Assert.AreEqual('', Item.Unreachable);
  Assert.AreEqual(-1, IndexOf(Items, 'Exception'));
end;

procedure TCompletionExceptionsTests.HandlerWithoutTryClassesHasNoGroups;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('try'#10'    Value := 1;'#10'  except'#10'    on E: |');
  Assert.IsTrue(Find(Items, 'EAppError', Item));
  Assert.AreEqual('', Item.ExceptionGroup);
  Assert.AreEqual('', Item.Expected);
end;

procedure TCompletionExceptionsTests.SiteNeedsExcept;
var
  Items: TCompletionItems;
begin
  // Ohne except ist "on E:" keine Behandlung; die gewoehnliche Liste gilt.
  Items := ItemsAt('Value := 1;'#10'  on E: |');
  Assert.AreEqual(-1, IndexOf(Items, 'EAppError.CreateFmt'));
  // Verschachtelter Block im try zaehlt nicht als except-Ebene.
  Items := ItemsAt('try'#10'    begin'#10'      Value := StrToInt(''1'');'#10'    end;'#10'  except'#10 +
    '    on E: |');
  Assert.IsTrue(Length(Items.Items) > 0);
  Assert.AreEqual('EConvertError', Items.Items[0].Name);
end;

procedure TCompletionExceptionsTests.WritesJson;
var
  Json: TJSONObject;
  Text: string;
begin
  Json := TLspCompletion.ToJson(ItemsAt('try'#10'    Value := StrToInt(''1'');'#10'  except'#10 +
    '    on E: Exception do'#10'      Value := 0;'#10'    on E: |'));
  try
    Text := Json.ToJSON;
  finally
    Json.Free;
  end;
  Assert.IsTrue(Text.Contains('"exceptionGroup":"try"'), Text);
  Assert.IsTrue(Text.Contains('"unreachable":"Exception"'), Text);
end;

procedure TCompletionExceptionsTests.SwitchOff;
var
  Settings: TCompletionSettings;
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Settings := TCompletionSettings.Default;
  Settings.ExceptionClasses := False;
  Items := ItemsAt('raise |', Settings);
  Assert.IsTrue(Find(Items, 'EAppError', Item));
  Assert.AreEqual('', Item.ExceptionGroup);
  Assert.AreEqual(-1, IndexOf(Items, 'EAppError.CreateFmt'));
  Assert.IsTrue(IndexOf(Items, 'Value') >= 0, 'gewoehnliche Liste');
end;

end.
