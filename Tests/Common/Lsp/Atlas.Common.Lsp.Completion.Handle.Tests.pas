unit Atlas.Common.Lsp.Completion.Handle.Tests;

// Charakterisierungstests für textDocument/completion über den Dispatcher (Block H
// Schritt 0): Reihenfolge und Exklusivität der Fälle in TLspCompletion.Handle – Schnellbefehle,
// Feldnamen im String, Freigabe absichern, Mengen, Aufzählungswerte vorab, Interface-Hinweise,
// Sender, Deklarieren am Ende, abschaltbare Schlüsselwörter und gestaffelte Teilergebnisse.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TLspCompletionHandleTests = class
  private
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    FCompletion: TLspCompletion;
    FDispatcher: TJsonRpcDispatcher;
    FFiles: TDictionary<string, string>;
    FForm: string;
    FProgress: TArray<string>;
    FId: Integer;
    /// <summary>Unit für den Index und für ReadText.</summary>
    procedure AddUnit(const AFileName, AText: string);
    /// <summary>Fragt an der Stelle von "|" in AText; ATrigger und AToken '' = ohne. Der Aufrufer gibt frei.
    /// </summary>
    function Complete(const AText: string): TJSONObject; overload;
    function Complete(const AText, ATrigger, AToken: string): TJSONObject; overload;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SlashCommandComesFirst;
    [Test]
    procedure SlashSortOffersCollectionsThenMembers;
    /// <summary>#297: nach /ignore nur die Regeln, die in der Zeile darunter treffen.</summary>
    [Test]
    procedure SlashIgnoreOffersRulesThatHit;
    /// <summary>#293/#294: Typ im Argument von /var mit uses-Eintrag der Typ-Unit (#180).</summary>
    [Test]
    procedure SlashTypeArgumentAddsUses;
    [Test]
    procedure DataNameInStringIsExclusive;
    [Test]
    procedure GuardTriggerOffersOnlyGuard;
    [Test]
    procedure SetModeReturnsOnlyEnumValues;
    [Test]
    procedure BracketWithoutSetIsEmpty;
    [Test]
    procedure EnumValuesPrecedeCollected;
    [Test]
    procedure InterfaceHintComesFirst;
    [Test]
    procedure InterfaceBatchIsExclusive;
    [Test]
    procedure DeclareItemsLastAndIncomplete;
    [Test]
    procedure KeywordsCanBeSwitchedOff;
    [Test]
    procedure PartialSendsEnumsThenStages;
    [Test]
    procedure SenderCastIsExclusive;
    /// <summary>#452: Feld vom Typ TCustomerList in einem Projekt mit F-Konvention.</summary>
    [Test]
    procedure NameSuggestionsFollowProjectConvention;
    /// <summary>#452: ohne Konvention kein Präfix, vergebene Namen mit Ziffer.</summary>
    [Test]
    procedure NameSuggestionsWithoutConvention;
    /// <summary>#452: Vorgabe der Projektdatei geht vor; completion.nameSuggestions aus schaltet ab.</summary>
    [Test]
    procedure NameSuggestionsForcedAndSwitchedOff;
    [Test]
    procedure ResourceStringInOwnUnit;
    [Test]
    procedure ResourceStringAsLinkedSnippet;
    [Test]
    procedure ResourceStringReusesSameText;
    [Test]
    procedure ResourceStringInConfiguredUnit;
    [Test]
    procedure ResourceStringOnlyInvokedAndSwitchable;
    /// <summary>#88: Strg+Leer in einem ///-Block, dessen Routine einen Parameter mehr hat, bietet nur
    /// „Parameter abgleichen“; completeBlocks.docComment aus schaltet es ab.</summary>
    [Test]
    procedure DocBlockOffersParameterAdjust;
    /// <summary>#102: Nach {$IFDEF  kommen die Symbole mit Herkunft, nicht geltende abgeschwächt;
    /// directives.completion aus lässt die Liste leer.</summary>
    [Test]
    procedure DirectiveSymbolsWithOrigin;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cTypenFile = 'C:\P\Typen.pas';
  cUnitTypen =
    'unit Typen;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TAlign = (alNone, alTop,'#13#10 +
    '    alClient);'#13#10 +
    '  TAnchorKind = (akLeft, akTop, akRight, akBottom);'#13#10 +
    '  TAnchors = set of TAnchorKind;'#13#10 +
    '  TControl = class'#13#10 +
    '    Align: TAlign;'#13#10 +
    '    Anchors: TAnchors;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  /// <summary>Routine mit Zugriff auf Typen; ABody steht zwischen begin und end.</summary>
  function EnumSource(const ABody: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'uses Typen;'#13#10 +
      'implementation'#13#10 +
      'procedure Setze(C: TControl; List: TArray<Integer>);'#13#10 +
      'begin'#13#10 +
      ABody + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

{ TLspCompletionHandleTests }

procedure TLspCompletionHandleTests.WarmUpFirstUse;
begin
  Setup;
  try
    DataNameInStringIsExclusive;
  finally
    TearDown;
  end;
  Setup;
  try
    PartialSendsEnumsThenStages;
  finally
    TearDown;
  end;
end;

procedure TLspCompletionHandleTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FFiles := TDictionary<string, string>.Create;
  FForm := '';
  FProgress := nil;
  FId := 0;
  FCompletion := TLspCompletion.Create(FStore, FIndex);
  FCompletion.Hooks.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      if SameText(ExtractFileExt(AFileName), '.dfm') then
      begin
        AText := FForm;
        Exit(FForm <> '');
      end;
      Result := FFiles.TryGetValue(LowerCase(AFileName), AText);
    end;
  FCompletion.Hooks.Notify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      try
        FProgress := FProgress + [AParams.ToJSON];
      finally
        AParams.Free;
      end;
    end;
  FDispatcher := TJsonRpcDispatcher.Create;
  FCompletion.Attach(FDispatcher);
end;

procedure TLspCompletionHandleTests.TearDown;
begin
  FDispatcher.Free;
  FCompletion.Free;
  FFiles.Free;
  FStore := nil;
  FIndex := nil;
  // Von den Tests gefüllt; der Leckmonitor zählte die Felder sonst dem Test an.
  FProgress := nil;
  FForm := '';
end;

procedure TLspCompletionHandleTests.AddUnit(const AFileName, AText: string);
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
  FFiles.AddOrSetValue(LowerCase(AFileName), AText);
end;

function TLspCompletionHandleTests.Complete(const AText: string): TJSONObject;
begin
  Result := Complete(AText, '', '');
end;

function TLspCompletionHandleTests.Complete(const AText, ATrigger, AToken: string): TJSONObject;
var
  mMarker, mIndex, mLine, mLineStart: Integer;
  mText, mUri, mParams: string;
  mRequest, mResponse: TJSONObject;
begin
  mMarker := Pos('|', AText);
  if mMarker = 0 then
  begin
    raise Exception.Create('Marker "|" fehlt');
  end;
  mLine := 0;
  mLineStart := 1;
  for mIndex := 1 to mMarker - 1 do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
      mLineStart := mIndex + 1;
    end;
  end;
  mText := Copy(AText, 1, mMarker - 1) + Copy(AText, mMarker + 1, MaxInt);
  mUri := TDocumentUris.FromPath(cHauptFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, mText);
  mParams := '{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"position":{"line":' + IntToStr(mLine) +
    ',"character":' + IntToStr(mMarker - mLineStart) + '}';
  if ATrigger <> '' then
  begin
    mParams := mParams + ',"context":{"triggerKind":2,"triggerCharacter":"' + ATrigger + '"}';
  end;
  if AToken <> '' then
  begin
    mParams := mParams + ',"partialResultToken":"' + AToken + '"';
  end;
  mParams := mParams + '}';
  Inc(FId);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/completion","params":' + mParams + '}') as TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  Assert.IsNotNull(mResponse);
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, mResponse.ToJSON);
    Result := mResponse.GetValue('result').Clone as TJSONObject;
  finally
    mResponse.Free;
  end;
end;

/// <summary>Labels der Einträge, mit Leerzeichen getrennt.</summary>
function Labels(AResult: TJSONObject): string;
var
  mItems: TJSONArray;
  mIndex: Integer;
begin
  Result := '';
  mItems := AResult.GetValue('items') as TJSONArray;
  for mIndex := 0 to mItems.Count - 1 do
  begin
    Result := Result + ' ' + (mItems.Items[mIndex] as TJSONObject).GetValue<string>('label');
  end;
  Result := Result.Trim;
end;

function ItemCount(AResult: TJSONObject): Integer;
begin
  Result := (AResult.GetValue('items') as TJSONArray).Count;
end;

function ItemAt(AResult: TJSONObject; AIndex: Integer): TJSONObject;
begin
  Result := (AResult.GetValue('items') as TJSONArray).Items[AIndex] as TJSONObject;
end;

function Occurrences(const AText, AWord: string): Integer;
var
  mStart: Integer;
begin
  Result := 0;
  mStart := Pos(AWord, AText);
  while mStart > 0 do
  begin
    Inc(Result);
    mStart := Pos(AWord, AText, mStart + 1);
  end;
end;

procedure TLspCompletionHandleTests.SlashCommandComesFirst;
var
  mAnswer: TJSONObject;
  mIndex: Integer;
begin
  mAnswer := Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Laden;'#13#10 +
    'var'#13#10 +
    '  Wert: Integer;'#13#10 +
    'begin'#13#10 +
    '  /us|'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    // Nur Schnellbefehle (Schlüsselwort mit Leerzeichen dahinter), keine Namen aus dem Gültigkeitsbereich.
    Assert.IsTrue(ItemCount(mAnswer) > 0, mAnswer.ToJSON);
    Assert.IsTrue(Pos('"insertText":"uses "', mAnswer.ToJSON) > 0, mAnswer.ToJSON);
    for mIndex := 0 to ItemCount(mAnswer) - 1 do
    begin
      Assert.AreEqual(14, ItemAt(mAnswer, mIndex).GetValue<Integer>('kind'));
    end;
    Assert.IsFalse(mAnswer.ToJSON.Contains('"Wert"'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SlashTypeArgumentAddsUses;
var
  mAnswer: TJSONObject;
  mItem: TJSONObject;
begin
  AddUnit(cTypenFile, cUnitTypen);
  mAnswer := Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Laden;'#13#10 +
    'begin'#13#10 +
    '  /var C: TCon|'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual('TControl', Labels(mAnswer));
    mItem := ItemAt(mAnswer, 0);
    Assert.IsTrue(mItem.GetValue('additionalTextEdits') is TJSONArray, mItem.ToJSON);
    Assert.IsTrue(Pos('Typen', mItem.GetValue('additionalTextEdits').ToJSON) > 0, mItem.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SlashIgnoreOffersRulesThatHit;
const
  cSource =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Laden;'#13#10 +
    'begin'#13#10 +
    '  /ignore |'#13#10 +
    '  X := 42;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  mAnswer: TJSONObject;
  mLine: Integer;
  mBlanked: Boolean;
begin
  mLine := -1;
  mBlanked := False;
  FCompletion.Hooks.RuleIdsFor :=
    function(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean
    begin
      mLine := ALine;
      mBlanked := Pos('/ignore', AText) = 0;
      AIds := ['magic-number', 'unused-local'];
      Result := True;
    end;
  mAnswer := Complete(cSource);
  try
    Assert.AreEqual('magic-number unused-local', Labels(mAnswer));
    Assert.AreEqual(6, mLine);
    Assert.IsTrue(mBlanked, 'Befehlszeile nicht ausgeblendet');
  finally
    mAnswer.Free;
  end;
  // Ohne Auskunft der ganze Katalog.
  FCompletion.Hooks.RuleIdsFor := nil;
  mAnswer := Complete(cSource);
  try
    Assert.IsTrue(ItemCount(mAnswer) > 2, Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SlashSortOffersCollectionsThenMembers;
const
  cSource =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TKunde = class'#13#10 +
    '  public'#13#10 +
    '    Name: string;'#13#10 +
    '    Umsatz: Double;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure Laden(Kunden: TList<TKunde>);'#13#10 +
    'var'#13#10 +
    '  Wert: Integer;'#13#10 +
    'begin'#13#10 +
    '  %s|'#13#10 +
    'end;'#13#10 +
    'end.';
var
  mAnswer: TJSONObject;
begin
  // #319: nach /sort die Sammlungen, nach der Sammlung die Mitglieder des Elementtyps.
  mAnswer := Complete(Format(cSource, ['/sort ']));
  try
    Assert.AreEqual('Kunden', Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
  mAnswer := Complete(Format(cSource, ['/filter Kunden Ums']));
  try
    Assert.AreEqual('Name Umsatz', Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DataNameInStringIsExclusive;
const
  cForm =
    'object frmOrders: TfrmOrders'#13#10 +
    '  object qryOrders: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select O.CUSTOMER_ID, O.CURRENCY, O.TOTAL from ORDERS O where O.ID = :OrderId'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
var
  mAnswer: TJSONObject;
begin
  FForm := cForm;
  mAnswer := Complete('unit Haupt;'#13#10'{$R *.dfm}'#13#10'  qryOrders.FieldByName(''cu|'').AsInteger;'#13#10);
  try
    Assert.AreEqual('CUSTOMER_ID CURRENCY TOTAL', Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
  // Zur Laufzeit erzeugte Datenmenge: im String nichts, auch keine Namen aus dem Gültigkeitsbereich.
  mAnswer := Complete('unit Haupt;'#13#10'{$R *.dfm}'#13#10'  qryNeu.FieldByName(''cu|'')'#13#10);
  try
    Assert.AreEqual(0, ItemCount(mAnswer));
    Assert.IsFalse(mAnswer.GetValue<Boolean>('isIncomplete'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.GuardTriggerOffersOnlyGuard;
const
  cUnitTeile =
    'unit Teile;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TComponent = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  function Source(const AStatement: string): string;
  begin
    Result := 'unit Haupt;'#13#10'interface'#13#10'implementation'#13#10'uses Teile;'#13#10 +
      'procedure Laden;'#13#10'var'#13#10'  List: TStringList;'#13#10'begin'#13#10'  ' + AStatement + #13#10 +
      'end;'#13#10'end.';
  end;

var
  mAnswer: TJSONObject;
begin
  AddUnit('C:\P\Teile.pas', cUnitTeile);
  mAnswer := Complete(Source('List := TStringList.Create;|'), ';', '');
  try
    Assert.AreEqual('Mit try…finally absichern', Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
  // Anderer Text mit demselben Auslöser: gar nichts, auch nicht die übrige Liste.
  mAnswer := Complete(Source('Laden;|'), ';', '');
  try
    Assert.AreEqual(0, ItemCount(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SetModeReturnsOnlyEnumValues;
var
  mAnswer: TJSONObject;
begin
  AddUnit(cTypenFile, cUnitTypen);
  mAnswer := Complete(EnumSource('  C.Anchors := [akLeft, |];'));
  try
    Assert.AreEqual('akLeft akTop akRight akBottom', Labels(mAnswer));
    Assert.AreEqual('TAnchorKind', ItemAt(mAnswer, 0).GetValue<string>('data.setOf'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.BracketWithoutSetIsEmpty;
var
  mAnswer: TJSONObject;
begin
  AddUnit(cTypenFile, cUnitTypen);
  mAnswer := Complete(EnumSource('  List[0] := List[|];'), '[', '');
  try
    Assert.AreEqual(0, ItemCount(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.EnumValuesPrecedeCollected;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  AddUnit(cTypenFile, cUnitTypen);
  mAnswer := Complete(EnumSource('  C.Align := |;'));
  try
    mText := Labels(mAnswer);
    Assert.IsTrue(mText.StartsWith('alNone alTop alClient '), mText);
    // Aus der übrigen Liste nicht noch einmal.
    Assert.AreEqual(1, Occurrences(' ' + mText + ' ', ' alNone '), mText);
    Assert.AreEqual(1, Occurrences(' ' + mText + ' ', ' TControl '), mText);
    Assert.AreEqual('00000', ItemAt(mAnswer, 0).GetValue<string>('sortText'));
  finally
    mAnswer.Free;
  end;
end;

const
  cBasisFile = 'C:\P\Basis.pas';
  cUnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  IFlush = interface'#13#10 +
    '    procedure Flush;'#13#10 +
    '  end;'#13#10 +
    '  IExporter = interface(IFlush)'#13#10 +
    '    procedure Export(const AFileName: string);'#13#10 +
    '    function GetName: string;'#13#10 +
    '    procedure SetName(const AValue: string);'#13#10 +
    '  end;'#13#10 +
    '  TBasis = class(TInterfacedObject)'#13#10 +
    '  public'#13#10 +
    '    procedure SetName(const AValue: string);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

function InterfaceSource(const ALine: string): string;
begin
  Result :=
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TJsonExporter = class(TBasis, IExporter)'#13#10 +
    '  private'#13#10 +
    '    FText: string;'#13#10 +
    ALine + #13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
end;

procedure TLspCompletionHandleTests.InterfaceHintComesFirst;
var
  mAnswer: TJSONObject;
begin
  AddUnit(cBasisFile, cUnitBasis);
  mAnswer := Complete(InterfaceSource('    Ex|'));
  try
    Assert.IsTrue(ItemCount(mAnswer) > 1, mAnswer.ToJSON);
    Assert.IsTrue(ItemAt(mAnswer, 0).GetValue<Boolean>('data.hint'), mAnswer.ToJSON);
    Assert.AreEqual('IExporter', ItemAt(mAnswer, 0).GetValue<string>('data.container'));
    // Je Interface ein Hinweis, danach die übrige Liste.
    Assert.AreEqual('IFlush', ItemAt(mAnswer, 1).GetValue<string>('data.container'));
    Assert.IsTrue(ItemCount(mAnswer) > 2, mAnswer.ToJSON);
    Assert.IsFalse(ItemAt(mAnswer, 2).ToJSON.Contains('"hint"'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.InterfaceBatchIsExclusive;
var
  mAnswer: TJSONObject;
begin
  AddUnit(cBasisFile, cUnitBasis);
  mAnswer := Complete(InterfaceSource('    |'));
  try
    Assert.AreEqual('Export GetName Flush', Labels(mAnswer));
    Assert.IsTrue(ItemAt(mAnswer, 0).GetValue<Boolean>('data.batch'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DeclareItemsLastAndIncomplete;
var
  mAnswer: TJSONObject;
  mLast: TJSONObject;
begin
  mAnswer := Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Summe;'#13#10 +
    'var'#13#10 +
    '  Wert: Integer;'#13#10 +
    'begin'#13#10 +
    '  TotalCount| := Wert + 1;'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.IsTrue(ItemCount(mAnswer) > 0, mAnswer.ToJSON);
    mLast := ItemAt(mAnswer, ItemCount(mAnswer) - 1);
    Assert.AreEqual('declare', mLast.GetValue<string>('data.action'), mAnswer.ToJSON);
    Assert.AreEqual('TotalCount', mLast.GetValue<string>('data.unknown'));
    Assert.IsTrue(mAnswer.GetValue<Boolean>('isIncomplete'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.KeywordsCanBeSwitchedOff;
const
  cText =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Laden;'#13#10 +
    'var'#13#10 +
    '  Beginn: Integer;'#13#10 +
    'begin'#13#10 +
    '  be|'#13#10 +
    'end;'#13#10 +
    'end.';
var
  mAnswer: TJSONObject;
begin
  mAnswer := Complete(cText);
  try
    Assert.IsTrue(mAnswer.ToJSON.Contains('"label":"begin","kind":14'), mAnswer.ToJSON);
    Assert.IsTrue(mAnswer.ToJSON.Contains('"label":"Beginn"'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.Keywords := False;
    end;
  mAnswer := Complete(cText);
  try
    Assert.IsFalse(mAnswer.ToJSON.Contains('"kind":14'), mAnswer.ToJSON);
    Assert.IsTrue(mAnswer.ToJSON.Contains('"label":"Beginn"'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.PartialSendsEnumsThenStages;
var
  mAnswer: TJSONObject;
  mSent, mIndex: Integer;
  mValue: TJSONObject;
begin
  AddUnit(cTypenFile, cUnitTypen);
  mAnswer := Complete(EnumSource('  C.Align := |;'), '', 'tok');
  try
    // Zuerst die Aufzählungswerte, dann der eigene Gültigkeitsbereich; die Antwort setzt sortText fort.
    Assert.IsTrue(Length(FProgress) >= 2, IntToStr(Length(FProgress)));
    Assert.IsTrue(FProgress[0].Contains('"token":"tok"'), FProgress[0]);
    Assert.IsTrue(FProgress[0].Contains('"label":"alNone"'), FProgress[0]);
    Assert.IsTrue(FProgress[0].Contains('"sortText":"00000"'), FProgress[0]);
    Assert.IsFalse(FProgress[1].Contains('"label":"alNone"'), FProgress[1]);
    Assert.IsTrue(FProgress[1].Contains('"sortText":"00003"'), FProgress[1]);
    Assert.IsFalse(mAnswer.ToJSON.Contains('"label":"alNone"'), mAnswer.ToJSON);
    mSent := 0;
    for mIndex := 0 to High(FProgress) do
    begin
      mValue := TJSONObject.ParseJSONValue(FProgress[mIndex]) as TJSONObject;
      try
        Inc(mSent, (mValue.GetValue('value') as TJSONArray).Count);
      finally
        mValue.Free;
      end;
    end;
    if ItemCount(mAnswer) > 0 then
    begin
      Assert.AreEqual(Format('%.5d', [mSent]), ItemAt(mAnswer, 0).GetValue<string>('sortText'));
    end;
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SenderCastIsExclusive;
const
  cUnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TControl = class'#13#10 +
    '  public'#13#10 +
    '    Caption: string;'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TControl)'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    '  TForm = class(TControl)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  mAnswer: TJSONObject;
begin
  AddUnit('C:\P\Steuer.pas', cUnitSteuer);
  FForm :=
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';
  mAnswer := Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Steuer;'#13#10 +
    'type'#13#10 +
    '  TfrmMain = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    btnLoad: TBitBtn;'#13#10 +
    '    procedure btnAnyClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TfrmMain.btnAnyClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  Sender.Cap|'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual('Caption', Labels(mAnswer));
    Assert.AreEqual('TButton', ItemAt(mAnswer, 0).GetValue<string>('data.sender'));
  finally
    mAnswer.Free;
  end;
end;

const
  cKundenFile = 'C:\P\Kunden.pas';

  /// <summary>Unit mit AFields Feldern, davon APrefixed mit F.</summary>
  function FieldUnit(AFields, APrefixed: Integer): string;
  var
    mIndex: Integer;
  begin
    Result := 'unit Kunden;'#13#10'interface'#13#10'type'#13#10'  TKunde = class'#13#10;
    for mIndex := 1 to AFields do
    begin
      if mIndex <= APrefixed then
      begin
        Result := Result + '    FWert' + IntToStr(mIndex) + ': Integer;'#13#10;
      end
      else
      begin
        Result := Result + '    Wert' + IntToStr(mIndex) + ': Integer;'#13#10;
      end;
    end;
    Result := Result + '  end;'#13#10'implementation'#13#10'end.';
  end;

const
  cFieldSite =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm = class'#13#10 +
    '  private'#13#10 +
    '    |: TCustomerList;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

procedure TLspCompletionHandleTests.NameSuggestionsFollowProjectConvention;
var
  mAnswer: TJSONObject;
begin
  // 3 von 5 Feldern mit F: genau 60 %.
  AddUnit(cKundenFile, FieldUnit(5, 3));
  mAnswer := Complete(cFieldSite);
  try
    Assert.AreEqual('FCustomers FCustomerList FList', Labels(mAnswer), mAnswer.ToJSON);
    Assert.AreEqual(5, ItemAt(mAnswer, 0).GetValue<Integer>('kind'));
    Assert.AreEqual('TCustomerList', ItemAt(mAnswer, 0).GetValue<string>('detail'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.NameSuggestionsWithoutConvention;
var
  mAnswer: TJSONObject;
begin
  // 2 von 5: unter 60 %.
  AddUnit(cKundenFile, FieldUnit(5, 2));
  mAnswer := Complete(cFieldSite);
  try
    Assert.AreEqual('Customers CustomerList List', Labels(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
  // Lokale Variable: vergebene Namen bekommen eine Ziffer, der Name an der Stelle selbst zählt nicht.
  mAnswer := Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Laden(List: Integer);'#13#10 +
    'var'#13#10 +
    '  Customers: Integer;'#13#10 +
    '  Cu|: TCustomerList;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual('Customers2 CustomerList List2', Labels(mAnswer), mAnswer.ToJSON);
    Assert.AreEqual(6, ItemAt(mAnswer, 0).GetValue<Integer>('kind'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.NameSuggestionsForcedAndSwitchedOff;
var
  mAnswer: TJSONObject;
begin
  AddUnit(cKundenFile, FieldUnit(5, 0));
  FCompletion.Hooks.NamingFor :=
    function(const AUri: string; AKind: TNamingKind): string
    begin
      Result := '';
      if AKind = TNamingKind.Field then
      begin
        Result := 'F';
      end;
    end;
  mAnswer := Complete(cFieldSite);
  try
    Assert.AreEqual('FCustomers FCustomerList FList', Labels(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.NameSuggestions := False;
    end;
  mAnswer := Complete(cFieldSite);
  try
    Assert.IsFalse(Labels(mAnswer).Contains('Customers'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

const
  cFrageUnit =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses'#10 +
    '  Dialogs;'#10 +
    #10 +
    'procedure Frage;'#10 +
    'begin'#10 +
    '  ShowMessage(''Eintrag wirklich l|öschen?'');'#10 +
    'end;'#10 +
    #10 +
    'end.';
  cTexteFile = 'C:\P\Texte.pas';
  cTexteUnit =
    'unit Texte;'#10 +
    'interface'#10 +
    'resourcestring'#10 +
    '  SOk = ''OK'';'#10 +
    'implementation'#10 +
    'end.';

function FirstItem(AResult: TJSONObject): TJSONObject;
begin
  Result := (AResult.GetValue('items') as TJSONArray).Items[0] as TJSONObject;
end;

procedure TLspCompletionHandleTests.ResourceStringInOwnUnit;
var
  mAnswer, mItem: TJSONObject;
  mExtra: TJSONArray;
begin
  mAnswer := Complete(cFrageUnit);
  try
    // Abnahme: Das Literal wird zum Bezeichner, der Abschnitt hinter dem uses enthält den Text unverändert.
    Assert.AreEqual('Als resourcestring auslagern', Labels(mAnswer), mAnswer.ToJSON);
    mItem := FirstItem(mAnswer);
    Assert.AreEqual('SEintragWirklichLoeschen', mItem.GetValue<string>('textEdit.newText'));
    Assert.AreEqual(8, mItem.GetValue<Integer>('textEdit.range.start.line'));
    Assert.AreEqual(14, mItem.GetValue<Integer>('textEdit.range.start.character'));
    Assert.AreEqual(41, mItem.GetValue<Integer>('textEdit.range.end.character'));
    mExtra := mItem.GetValue('additionalTextEdits') as TJSONArray;
    Assert.AreEqual(1, Integer(mExtra.Count));
    Assert.AreEqual(#10#10'resourcestring'#10'  SEintragWirklichLoeschen = ''Eintrag wirklich löschen?'';',
      mExtra.Items[0].GetValue<string>('newText'));
    Assert.AreEqual(4, mExtra.Items[0].GetValue<Integer>('range.start.line'));
    Assert.AreEqual('create', mItem.GetValue<string>('data.action'));
    Assert.IsNull(mItem.GetValue('insertTextFormat'));
    Assert.IsNull(mItem.GetValue('command'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.ResourceStringAsLinkedSnippet;
var
  mAnswer, mItem: TJSONObject;
begin
  FCompletion.Hooks.SnippetSupport := True;
  mAnswer := Complete(StringReplace(cFrageUnit, 'Eintrag wirklich', 'Preis in $ wirklich', []));
  try
    // Platzhalter-Modus (#51): derselbe Platzhalter an der Stelle und im Abschnitt, "$" maskiert.
    mItem := FirstItem(mAnswer);
    Assert.AreEqual(2, mItem.GetValue<Integer>('insertTextFormat'));
    Assert.AreEqual('${1:SPreisInWirklichLoeschen}', mItem.GetValue<string>('textEdit.newText'));
    Assert.IsTrue(mItem.GetValue<Boolean>('data.linkedEdits'), mItem.ToJSON);
    Assert.Contains((mItem.GetValue('additionalTextEdits') as TJSONArray).Items[0].GetValue<string>('newText'),
      '  ${1:SPreisInWirklichLoeschen} = ''Preis in \$ wirklich löschen?'';');
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.ResourceStringReusesSameText;
var
  mAnswer: TJSONObject;
  mItems: TJSONArray;
begin
  mAnswer := Complete(StringReplace(cFrageUnit, '  Dialogs;'#10, '  Dialogs;'#10#10'resourcestring'#10 +
    '  SFrage = ''Eintrag wirklich löschen?'';'#10'  SEintragWirklichLoeschen = ''anders'';'#10, []));
  try
    // Abnahme: Bei gleichem Text steht der vorhandene Bezeichner vorn; der neue Name bekommt eine Ziffer.
    Assert.AreEqual('Vorhandenen verwenden: SFrage Als resourcestring auslagern', Labels(mAnswer), mAnswer.ToJSON);
    Assert.AreEqual('SFrage', FirstItem(mAnswer).GetValue<string>('textEdit.newText'));
    Assert.IsNull(FirstItem(mAnswer).GetValue('additionalTextEdits'));
    mItems := mAnswer.GetValue('items') as TJSONArray;
    Assert.AreEqual('SEintragWirklichLoeschen2', mItems.Items[1].GetValue<string>('textEdit.newText'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.ResourceStringInConfiguredUnit;
var
  mAnswer, mItem: TJSONObject;
  mArguments: TJSONArray;
begin
  AddUnit(cTexteFile, cTexteUnit);
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.ResourceStringUnit := 'Texte';
    end;
  mAnswer := Complete(cFrageUnit);
  try
    mItem := FirstItem(mAnswer);
    Assert.AreEqual('SEintragWirklichLoeschen', mItem.GetValue<string>('textEdit.newText'), mAnswer.ToJSON);
    Assert.AreEqual('atlas.server.addResourceString', mItem.GetValue<string>('command.command'));
    mArguments := (mItem.GetValue('command') as TJSONObject).GetValue('arguments') as TJSONArray;
    Assert.AreEqual(3, Integer(mArguments.Count), mItem.ToJSON);
    Assert.AreEqual(cTexteFile, mArguments.Items[0].Value);
    Assert.AreEqual('SEintragWirklichLoeschen', mArguments.Items[1].Value);
    Assert.AreEqual('''Eintrag wirklich löschen?''', mArguments.Items[2].Value);
    // Die Unit kommt ins uses der implementation.
    Assert.Contains((mItem.GetValue('additionalTextEdits') as TJSONArray).Items[0].GetValue<string>('newText'),
      'Texte');
  finally
    mAnswer.Free;
  end;
  // Gleicher Text in der festgelegten Unit.
  mAnswer := Complete(StringReplace(cFrageUnit, 'Eintrag wirklich l|öschen?', 'O|K', []));
  try
    Assert.AreEqual('Vorhandenen verwenden: SOk Als resourcestring auslagern', Labels(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.ResourceStringOnlyInvokedAndSwitchable;
var
  mAnswer: TJSONObject;
begin
  // Mit Auslösezeichen nicht, nur mit Strg+Leer.
  mAnswer := Complete(cFrageUnit, '.', '');
  try
    Assert.IsFalse(Labels(mAnswer).Contains('resourcestring'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
  // In einer Konstanten nicht.
  mAnswer := Complete(StringReplace(cFrageUnit, 'implementation'#10, 'implementation'#10'const'#10 +
    '  CText = ''Kon|stante'';'#10, []).Replace('l|ö', 'lö'));
  try
    Assert.IsFalse(Labels(mAnswer).Contains('resourcestring'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.ResourceStrings := False;
    end;
  mAnswer := Complete(cFrageUnit);
  try
    Assert.IsFalse(Labels(mAnswer).Contains('resourcestring'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DocBlockOffersParameterAdjust;
const
  cSource =
    'unit Haupt;'#13#10'interface'#13#10'type'#13#10'  TRechner = class'#13#10 +
    '    /// <summary>Rabatt|</summary>'#13#10'    /// <param name="Customer">Kunde</param>'#13#10 +
    '    function CalcDiscount(Customer: TObject; Rate: Double): Currency;'#13#10 +
    '  end;'#13#10'implementation'#13#10'end.';
var
  mAnswer: TJSONObject;
  mEdits: TJSONArray;
  mEnabled: Boolean;
begin
  mEnabled := True;
  FCompletion.Hooks.DocCommentsFor :=
    function(const AUri: string): Boolean
    begin
      Result := mEnabled;
    end;
  mAnswer := Complete(cSource);
  try
    Assert.AreEqual('Parameter abgleichen', Labels(mAnswer));
    mEdits := ((mAnswer.GetValue('items') as TJSONArray).Items[0] as TJSONObject).GetValue('additionalTextEdits')
      as TJSONArray;
    Assert.AreEqual(1, Integer(mEdits.Count));
    Assert.AreEqual('    /// <param name="Rate"></param>'#13#10,
      (mEdits.Items[0] as TJSONObject).GetValue<string>('newText'));
    Assert.IsTrue(mAnswer.ToJSON.Contains('"action":"docParams"'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
  // Passt der Block, kommt das Angebot nicht.
  mAnswer := Complete(StringReplace(cSource, 'Kunde</param>', 'Kunde</param>'#13#10 +
    '    /// <param name="Rate">Satz</param>', []));
  try
    Assert.IsFalse(Labels(mAnswer).Contains('Parameter abgleichen'), Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
  mEnabled := False;
  mAnswer := Complete(cSource);
  try
    Assert.IsFalse(Labels(mAnswer).Contains('Parameter abgleichen'), Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DirectiveSymbolsWithOrigin;
var
  mAnswer: TJSONObject;
  mEnabled: Boolean;
begin
  mEnabled := True;
  FCompletion.Hooks.SymbolsFor :=
    function(const AUri: string): TConditionalContext
    begin
      Result := TConditionalContext.Default;
      Result.CompletionEnabled := mEnabled;
      Result.HasDefines := True;
      Result.Defines := ['DEBUG', 'MSWINDOWS'];
      Result.Sources := TConditionalSymbols.SourcesOf(['DEBUG'],
        [TPair<string, string>.Create('DEBUG', 'Konfiguration Debug')], ['MSWINDOWS'], 'Win64');
    end;
  mAnswer := Complete('unit Haupt;'#13#10'{$IFDEF |'#13#10'implementation'#13#10'end.');
  try
    Assert.AreEqual('DEBUG', ItemAt(mAnswer, 0).GetValue<string>('label'));
    Assert.AreEqual('Konfiguration Debug (.dproj)', ItemAt(mAnswer, 0).GetValue<string>('detail'));
    Assert.IsTrue(Labels(mAnswer).Contains('MSWINDOWS'), Labels(mAnswer));
    Assert.IsTrue(Labels(mAnswer).Contains('LINUX'), Labels(mAnswer));
    Assert.IsFalse(Labels(mAnswer).Contains('ALIGN'), Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
  mEnabled := False;
  mAnswer := Complete('unit Haupt;'#13#10'{$IFDEF |'#13#10'implementation'#13#10'end.');
  try
    Assert.AreEqual(0, ItemCount(mAnswer), Labels(mAnswer));
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionHandleTests);

end.
