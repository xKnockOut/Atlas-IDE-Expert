unit Atlas.Common.Lsp.Completion.Handle.Tests;

// Charakterisierungstests für textDocument/completion über den Dispatcher (Code-Review S-01, Block H
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
  HauptFile = 'C:\P\Haupt.pas';

  TypenFile = 'C:\P\Typen.pas';
  UnitTypen =
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
  FCompletion.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      if SameText(ExtractFileExt(AFileName), '.dfm') then
      begin
        AText := FForm;
        Exit(FForm <> '');
      end;
      Result := FFiles.TryGetValue(LowerCase(AFileName), AText);
    end;
  FCompletion.Notify :=
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
  Marker, Index, Line, LineStart: Integer;
  Text, Uri, Params: string;
  Request, Response: TJSONObject;
begin
  Marker := Pos('|', AText);
  if Marker = 0 then
    raise Exception.Create('Marker "|" fehlt');
  Line := 0;
  LineStart := 1;
  for Index := 1 to Marker - 1 do
    if AText[Index] = #10 then
    begin
      Inc(Line);
      LineStart := Index + 1;
    end;
  Text := Copy(AText, 1, Marker - 1) + Copy(AText, Marker + 1, MaxInt);
  Uri := TDocumentUris.FromPath(HauptFile);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, Text);
  Params := '{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"position":{"line":' + IntToStr(Line) +
    ',"character":' + IntToStr(Marker - LineStart) + '}';
  if ATrigger <> '' then
    Params := Params + ',"context":{"triggerKind":2,"triggerCharacter":"' + ATrigger + '"}';
  if AToken <> '' then
    Params := Params + ',"partialResultToken":"' + AToken + '"';
  Params := Params + '}';
  Inc(FId);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/completion","params":' + Params + '}') as TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  Assert.IsNotNull(Response);
  try
    Assert.IsTrue(Response.GetValue('result') is TJSONObject, Response.ToJSON);
    Result := Response.GetValue('result').Clone as TJSONObject;
  finally
    Response.Free;
  end;
end;

/// <summary>Labels der Einträge, mit Leerzeichen getrennt.</summary>
function Labels(AResult: TJSONObject): string;
var
  Items: TJSONArray;
  Index: Integer;
begin
  Result := '';
  Items := AResult.GetValue('items') as TJSONArray;
  for Index := 0 to Items.Count - 1 do
    Result := Result + ' ' + (Items.Items[Index] as TJSONObject).GetValue<string>('label');
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
  Start: Integer;
begin
  Result := 0;
  Start := Pos(AWord, AText);
  while Start > 0 do
  begin
    Inc(Result);
    Start := Pos(AWord, AText, Start + 1);
  end;
end;

procedure TLspCompletionHandleTests.SlashCommandComesFirst;
var
  Answer: TJSONObject;
  Index: Integer;
begin
  Answer := Complete(
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
    Assert.IsTrue(ItemCount(Answer) > 0, Answer.ToJSON);
    Assert.IsTrue(Pos('"insertText":"uses "', Answer.ToJSON) > 0, Answer.ToJSON);
    for Index := 0 to ItemCount(Answer) - 1 do
      Assert.AreEqual(14, ItemAt(Answer, Index).GetValue<Integer>('kind'));
    Assert.IsFalse(Answer.ToJSON.Contains('"Wert"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SlashSortOffersCollectionsThenMembers;
const
  Source =
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
  Answer: TJSONObject;
begin
  // #319: nach /sort die Sammlungen, nach der Sammlung die Mitglieder des Elementtyps.
  Answer := Complete(Format(Source, ['/sort ']));
  try
    Assert.AreEqual('Kunden', Labels(Answer));
  finally
    Answer.Free;
  end;
  Answer := Complete(Format(Source, ['/filter Kunden Ums']));
  try
    Assert.AreEqual('Name Umsatz', Labels(Answer));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DataNameInStringIsExclusive;
const
  Form =
    'object frmOrders: TfrmOrders'#13#10 +
    '  object qryOrders: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select O.CUSTOMER_ID, O.CURRENCY, O.TOTAL from ORDERS O where O.ID = :OrderId'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
var
  Answer: TJSONObject;
begin
  FForm := Form;
  Answer := Complete('unit Haupt;'#13#10'{$R *.dfm}'#13#10'  qryOrders.FieldByName(''cu|'').AsInteger;'#13#10);
  try
    Assert.AreEqual('CUSTOMER_ID CURRENCY TOTAL', Labels(Answer));
  finally
    Answer.Free;
  end;
  // Zur Laufzeit erzeugte Datenmenge: im String nichts, auch keine Namen aus dem Gültigkeitsbereich.
  Answer := Complete('unit Haupt;'#13#10'{$R *.dfm}'#13#10'  qryNeu.FieldByName(''cu|'')'#13#10);
  try
    Assert.AreEqual(0, ItemCount(Answer));
    Assert.IsFalse(Answer.GetValue<Boolean>('isIncomplete'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.GuardTriggerOffersOnlyGuard;
const
  UnitTeile =
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
  Answer: TJSONObject;
begin
  AddUnit('C:\P\Teile.pas', UnitTeile);
  Answer := Complete(Source('List := TStringList.Create;|'), ';', '');
  try
    Assert.AreEqual('Mit try…finally absichern', Labels(Answer));
  finally
    Answer.Free;
  end;
  // Anderer Text mit demselben Auslöser: gar nichts, auch nicht die übrige Liste.
  Answer := Complete(Source('Laden;|'), ';', '');
  try
    Assert.AreEqual(0, ItemCount(Answer), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SetModeReturnsOnlyEnumValues;
var
  Answer: TJSONObject;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  C.Anchors := [akLeft, |];'));
  try
    Assert.AreEqual('akLeft akTop akRight akBottom', Labels(Answer));
    Assert.AreEqual('TAnchorKind', ItemAt(Answer, 0).GetValue<string>('data.setOf'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.BracketWithoutSetIsEmpty;
var
  Answer: TJSONObject;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  List[0] := List[|];'), '[', '');
  try
    Assert.AreEqual(0, ItemCount(Answer), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.EnumValuesPrecedeCollected;
var
  Answer: TJSONObject;
  Text: string;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  C.Align := |;'));
  try
    Text := Labels(Answer);
    Assert.IsTrue(Text.StartsWith('alNone alTop alClient '), Text);
    // Aus der übrigen Liste nicht noch einmal.
    Assert.AreEqual(1, Occurrences(' ' + Text + ' ', ' alNone '), Text);
    Assert.IsTrue(Occurrences(' ' + Text + ' ', ' TControl ') = 1, Text);
    Assert.AreEqual('00000', ItemAt(Answer, 0).GetValue<string>('sortText'));
  finally
    Answer.Free;
  end;
end;

const
  BasisFile = 'C:\P\Basis.pas';
  UnitBasis =
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
  Answer: TJSONObject;
begin
  AddUnit(BasisFile, UnitBasis);
  Answer := Complete(InterfaceSource('    Ex|'));
  try
    Assert.IsTrue(ItemCount(Answer) > 1, Answer.ToJSON);
    Assert.IsTrue(ItemAt(Answer, 0).GetValue<Boolean>('data.hint'), Answer.ToJSON);
    Assert.AreEqual('IExporter', ItemAt(Answer, 0).GetValue<string>('data.container'));
    // Je Interface ein Hinweis, danach die übrige Liste.
    Assert.AreEqual('IFlush', ItemAt(Answer, 1).GetValue<string>('data.container'));
    Assert.IsTrue(ItemCount(Answer) > 2, Answer.ToJSON);
    Assert.IsFalse(ItemAt(Answer, 2).ToJSON.Contains('"hint"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.InterfaceBatchIsExclusive;
var
  Answer: TJSONObject;
begin
  AddUnit(BasisFile, UnitBasis);
  Answer := Complete(InterfaceSource('    |'));
  try
    Assert.AreEqual('Export GetName Flush', Labels(Answer));
    Assert.IsTrue(ItemAt(Answer, 0).GetValue<Boolean>('data.batch'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DeclareItemsLastAndIncomplete;
var
  Answer: TJSONObject;
  Last: TJSONObject;
begin
  Answer := Complete(
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
    Assert.IsTrue(ItemCount(Answer) > 0, Answer.ToJSON);
    Last := ItemAt(Answer, ItemCount(Answer) - 1);
    Assert.AreEqual('declare', Last.GetValue<string>('data.action'), Answer.ToJSON);
    Assert.AreEqual('TotalCount', Last.GetValue<string>('data.unknown'));
    Assert.IsTrue(Answer.GetValue<Boolean>('isIncomplete'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.KeywordsCanBeSwitchedOff;
const
  Text =
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
  Answer: TJSONObject;
begin
  Answer := Complete(Text);
  try
    Assert.IsTrue(Answer.ToJSON.Contains('"label":"begin","kind":14'), Answer.ToJSON);
    Assert.IsTrue(Answer.ToJSON.Contains('"label":"Beginn"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
  FCompletion.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.Keywords := False;
    end;
  Answer := Complete(Text);
  try
    Assert.IsFalse(Answer.ToJSON.Contains('"kind":14'), Answer.ToJSON);
    Assert.IsTrue(Answer.ToJSON.Contains('"label":"Beginn"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.PartialSendsEnumsThenStages;
var
  Answer: TJSONObject;
  Sent, Index: Integer;
  Value: TJSONObject;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  C.Align := |;'), '', 'tok');
  try
    // Zuerst die Aufzählungswerte, dann der eigene Gültigkeitsbereich; die Antwort setzt sortText fort.
    Assert.IsTrue(Length(FProgress) >= 2, IntToStr(Length(FProgress)));
    Assert.IsTrue(FProgress[0].Contains('"token":"tok"'), FProgress[0]);
    Assert.IsTrue(FProgress[0].Contains('"label":"alNone"'), FProgress[0]);
    Assert.IsTrue(FProgress[0].Contains('"sortText":"00000"'), FProgress[0]);
    Assert.IsFalse(FProgress[1].Contains('"label":"alNone"'), FProgress[1]);
    Assert.IsTrue(FProgress[1].Contains('"sortText":"00003"'), FProgress[1]);
    Assert.IsFalse(Answer.ToJSON.Contains('"label":"alNone"'), Answer.ToJSON);
    Sent := 0;
    for Index := 0 to High(FProgress) do
    begin
      Value := TJSONObject.ParseJSONValue(FProgress[Index]) as TJSONObject;
      try
        Inc(Sent, (Value.GetValue('value') as TJSONArray).Count);
      finally
        Value.Free;
      end;
    end;
    if ItemCount(Answer) > 0 then
      Assert.AreEqual(Format('%.5d', [Sent]), ItemAt(Answer, 0).GetValue<string>('sortText'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SenderCastIsExclusive;
const
  UnitSteuer =
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
  Answer: TJSONObject;
begin
  AddUnit('C:\P\Steuer.pas', UnitSteuer);
  FForm :=
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';
  Answer := Complete(
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
    Assert.AreEqual('Caption', Labels(Answer));
    Assert.AreEqual('TButton', ItemAt(Answer, 0).GetValue<string>('data.sender'));
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionHandleTests);

end.
