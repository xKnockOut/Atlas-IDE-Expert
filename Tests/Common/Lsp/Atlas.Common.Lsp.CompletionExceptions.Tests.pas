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
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.CompletionExceptions;

const
  cHauptFile = 'C:\P\Haupt.pas';
  cSysUtilsFile = 'C:\Rtl\System.SysUtils.pas';
  cClassesFile = 'C:\Rtl\System.Classes.pas';

  cUnitSysUtils =
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

  cUnitHaupt =
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
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  APosition := TTextPosition.Create(mLine, mCharacter);
  Result := StringReplace(AMarked, '|', '', []);
end;

{ TCompletionExceptionsTests }

procedure TCompletionExceptionsTests.Setup;
var
  mRtl: TUnitIndex;
begin
  FIndex := TSymbolIndex.Create;
  mRtl := TIndexExtractor.ExtractText(cUnitSysUtils, cSysUtilsFile, nil);
  mRtl.Library_ := True;
  FIndex.AddUnit(mRtl);
  mRtl := TIndexExtractor.ExtractText('unit System.Classes;'#10'interface'#10'uses'#10'  System.SysUtils;'#10 +
    'type'#10'  EFOpenError = class(Exception);'#10'implementation'#10'end.', cClassesFile, nil);
  mRtl.Library_ := True;
  FIndex.AddUnit(mRtl);
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
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  mText := Split(StringReplace(cUnitHaupt, '{ Code }', AMarked, []), mPosition);
  mTree := TPascalParser.Parse(mText);
  FIndex.AddUnit(TIndexExtractor.ExtractText(StringReplace(mText, '|', '', []), cHauptFile, nil));
  mRequest := TCompletionRequest.Create(mText, cHauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := ASettings;
    Result := TCompletionLists.Collect(mRequest, APostfix, nil);
  finally
    mRequest.Free;
    mTree.Free;
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
  mIndex: Integer;
begin
  mIndex := IndexOf(AItems, AName);
  Result := mIndex >= 0;
  if Result then
  begin
    AItem := AItems.Items[mIndex];
  end
  else
  begin
    AItem := Default(TCompletionItem);
  end;
end;

function TCompletionExceptionsTests.IndexOf(const AItems: TCompletionItems; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems.Items) do
  begin
    if AItems.Items[mIndex].Name = AName then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TCompletionExceptionsTests.RaiseOffersOnlyExceptionClasses;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('raise |');
  Assert.IsTrue(Find(mItems, 'EAppError', mItem), 'Projektklasse fehlt');
  Assert.IsTrue(Find(mItems, 'ELoadError', mItem), 'Nachfahre fehlt');
  Assert.IsTrue(Find(mItems, 'Exception', mItem), 'Exception fehlt');
  Assert.IsTrue(Find(mItems, 'EConvertError', mItem), 'RTL-Klasse fehlt');
  Assert.AreEqual(-1, IndexOf(mItems, 'TWorker'), 'keine Exception');
  Assert.AreEqual(-1, IndexOf(mItems, 'TFormatSettings'), 'kein Record');
  Assert.AreEqual(-1, IndexOf(mItems, 'Value'), 'keine Variable');
  Assert.AreEqual(-1, IndexOf(mItems, 'StrToInt'), 'keine Routine');
end;

procedure TCompletionExceptionsTests.RaiseProjectBeforeLibrary;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt('raise E|');
  Assert.IsTrue(IndexOf(mItems, 'EAppError') >= 0);
  Assert.IsTrue(IndexOf(mItems, 'EAppError') < IndexOf(mItems, 'EConvertError'), 'Projekt vor Bibliothek');
  Assert.IsTrue(IndexOf(mItems, 'ELoadError') < IndexOf(mItems, 'EAbort'), 'Projekt vor Bibliothek');
end;

procedure TCompletionExceptionsTests.RaiseInsertsCreateAndCreateFmt;
var
  mPostfix: TPostfixOptions;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mPostfix := Default(TPostfixOptions);
  mPostfix.Snippet := True;
  mItems := ItemsAt('raise EApp|', TCompletionSettings.Default, mPostfix);
  Assert.IsTrue(Find(mItems, 'EAppError', mItem));
  Assert.AreEqual('EAppError.Create(''$0'')', mItem.InsertText);
  Assert.IsTrue(mItem.Snippet);
  Assert.AreEqual(TCompletionExceptions.cGroupRaise, mItem.ExceptionGroup);
  Assert.IsTrue(Find(mItems, 'EAppError.CreateFmt', mItem), 'eigener Eintrag fuer CreateFmt');
  Assert.AreEqual('EAppError.CreateFmt(''$1'', [$2])$0', mItem.InsertText);
  Assert.AreEqual(cKindConstructor, mItem.Kind);
  Assert.AreEqual('EAppError', mItem.FilterText);
  Assert.AreEqual(IndexOf(mItems, 'EAppError') + 1, IndexOf(mItems, 'EAppError.CreateFmt'), 'direkt dahinter');
end;

procedure TCompletionExceptionsTests.RaiseWithoutSnippets;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('raise EApp|');
  Assert.IsTrue(Find(mItems, 'EAppError', mItem));
  Assert.AreEqual('EAppError.Create('''')', mItem.InsertText);
  Assert.IsFalse(mItem.Snippet);
  Assert.IsTrue(Find(mItems, 'EAppError.CreateFmt', mItem));
  Assert.AreEqual('EAppError.CreateFmt('''', [])', mItem.InsertText);
end;

procedure TCompletionExceptionsTests.HandlerShowsTryClassesFirst;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  // Akzeptanz: Nach StrToInt im try zeigt "on E: " als erstes EConvertError.
  mItems := ItemsAt('try'#10'    Value := StrToInt(''1'');'#10'  except'#10'    on E: |');
  Assert.IsTrue(Length(mItems.Items) > 0);
  Assert.AreEqual('EConvertError', mItems.Items[0].Name);
  Assert.AreEqual(TCompletionExceptions.cGroupTry, mItems.Items[0].ExceptionGroup);
  Assert.IsTrue(mItems.Items[0].Fits);
  Assert.IsTrue(Find(mItems, 'EAppError', mItem));
  Assert.AreEqual(TCompletionExceptions.cGroupGeneral, mItem.ExceptionGroup);
  Assert.IsFalse(mItem.Fits);
  Assert.AreEqual(-1, IndexOf(mItems, 'TWorker'));
end;

procedure TCompletionExceptionsTests.HandlerReadsXmlDoc;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt('try'#10'    Load;'#10'    Value := StrToInt(''1'');'#10'  except'#10'    on E: |');
  Assert.IsTrue(Length(mItems.Items) > 1);
  Assert.AreEqual('ELoadError', mItems.Items[0].Name, 'Reihenfolge der Aufrufe');
  Assert.AreEqual('EConvertError', mItems.Items[1].Name);
  Assert.AreEqual(TCompletionExceptions.cGroupTry, mItems.Items[1].ExceptionGroup);
end;

procedure TCompletionExceptionsTests.HandlerAddsUsesForTryClasses;
var
  mItems: TCompletionItems;
begin
  // LoadFromFile ohne aufgeloesten Empfaenger: bekannter Fall der RTL, Klasse aus nicht eingebundener Unit.
  mItems := ItemsAt('try'#10'    Lines.LoadFromFile(''a.txt'');'#10'  except'#10'    on E: |');
  Assert.IsTrue(Length(mItems.Items) > 0);
  Assert.AreEqual('EFOpenError', mItems.Items[0].Name);
  Assert.AreEqual(TCompletionExceptions.cGroupTry, mItems.Items[0].ExceptionGroup);
  Assert.AreEqual(1, Integer(Length(mItems.Items[0].AdditionalEdits)), 'uses ergaenzen');
  Assert.IsTrue(mItems.Items[0].AdditionalEdits[0].NewText.Contains('System.Classes'));
end;

procedure TCompletionExceptionsTests.HandlerSkipsHandledClasses;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt('try'#10'    Value := StrToInt(''1'');'#10'  except'#10'    on E: EConvertError do'#10 +
    '      Value := 0;'#10'    on E: |');
  Assert.AreEqual(-1, IndexOf(mItems, 'EConvertError'), 'schon behandelt');
  Assert.IsTrue(IndexOf(mItems, 'EAppError') >= 0);
end;

procedure TCompletionExceptionsTests.HandlerWarnsAboutOrder;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  // Akzeptanz: on E: Exception vor on E: EConvertError erzeugt die Warnung.
  mItems := ItemsAt('try'#10'    Value := 1;'#10'  except'#10'    on E: Exception do'#10'      Value := 0;'#10 +
    '    on E: |');
  Assert.IsTrue(Find(mItems, 'EConvertError', mItem));
  Assert.AreEqual('Exception', mItem.Unreachable);
  Assert.AreEqual(-1, IndexOf(mItems, 'Exception'), 'schon behandelt');
  // Zweig danach (nicht davor) loest keine Warnung aus.
  mItems := ItemsAt('try'#10'    Value := 1;'#10'  except'#10'    on E: E|'#10'    on E: Exception do'#10 +
    '      Value := 0;');
  Assert.IsTrue(Find(mItems, 'EConvertError', mItem));
  Assert.AreEqual('', mItem.Unreachable);
  Assert.AreEqual(-1, IndexOf(mItems, 'Exception'));
end;

procedure TCompletionExceptionsTests.HandlerWithoutTryClassesHasNoGroups;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('try'#10'    Value := 1;'#10'  except'#10'    on E: |');
  Assert.IsTrue(Find(mItems, 'EAppError', mItem));
  Assert.AreEqual('', mItem.ExceptionGroup);
  Assert.AreEqual('', mItem.Expected);
end;

procedure TCompletionExceptionsTests.SiteNeedsExcept;
var
  mItems: TCompletionItems;
begin
  // Ohne except ist "on E:" keine Behandlung; die gewoehnliche Liste gilt.
  mItems := ItemsAt('Value := 1;'#10'  on E: |');
  Assert.AreEqual(-1, IndexOf(mItems, 'EAppError.CreateFmt'));
  // Verschachtelter Block im try zaehlt nicht als except-Ebene.
  mItems := ItemsAt('try'#10'    begin'#10'      Value := StrToInt(''1'');'#10'    end;'#10'  except'#10 +
    '    on E: |');
  Assert.IsTrue(Length(mItems.Items) > 0);
  Assert.AreEqual('EConvertError', mItems.Items[0].Name);
end;

procedure TCompletionExceptionsTests.WritesJson;
var
  mJson: TJSONObject;
  mText: string;
begin
  mJson := TLspCompletion.ToJson(ItemsAt('try'#10'    Value := StrToInt(''1'');'#10'  except'#10 +
    '    on E: Exception do'#10'      Value := 0;'#10'    on E: |'));
  try
    mText := mJson.ToJSON;
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mText.Contains('"exceptionGroup":"try"'), mText);
  Assert.IsTrue(mText.Contains('"unreachable":"Exception"'), mText);
end;

procedure TCompletionExceptionsTests.SwitchOff;
var
  mSettings: TCompletionSettings;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.ExceptionClasses := False;
  mItems := ItemsAt('raise |', mSettings);
  Assert.IsTrue(Find(mItems, 'EAppError', mItem));
  Assert.AreEqual('', mItem.ExceptionGroup);
  Assert.AreEqual(-1, IndexOf(mItems, 'EAppError.CreateFmt'));
  Assert.IsTrue(IndexOf(mItems, 'Value') >= 0, 'gewoehnliche Liste');
end;

end.
