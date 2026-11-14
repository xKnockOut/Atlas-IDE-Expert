unit Atlas.Common.Lsp.Completion.FormProposals.Tests;

// Tests der Vervollständigung im Formular: Komponenten nach Name, Typ und Kürzel, Sender-Umwandlung,
// Datenfelder und das Lesen der Formulardatei.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.Completion.TestSupport,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Completion;

type
  /// <summary>Vorschläge aus dem Formular: Komponenten, Sender-Umwandlung, Datenfelder.</summary>
  [TestFixture]
  TLspCompletionFormProposalTests = class(TLspCompletionTestCase)
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure OffersFormComponentsByNameAndType;
    /// <summary>#882: Formular-Komponenten auch über Kürzel und Teilwort, mit dem getippten Wort als filterText.</summary>
    [Test]
    procedure OffersFormComponentsFuzzyWithFilterText;
    /// <summary>#882: Anfang vor Kürzel vor Teilwort auch in der Punktzahl des Servers (Kürzen auf MaxItems).</summary>
    [Test]
    procedure MatchScoreRanksAbbreviationBeforeSubstring;
    [Test]
    procedure CastsSenderToAssignedComponents;
    [Test]
    procedure OffersDataFieldNames;
    /// <summary>Außerhalb von Routinen wird das Formular gar nicht gelesen.</summary>
    [Test]
    procedure ComponentItemsOutsideRoutineDoesNotReadForm;
    /// <summary>Die zweite Anfrage nutzt den Auszug der Formulardatei; nach einer Änderung
    /// der Datei wird neu gelesen.</summary>
    [Test]
    procedure ComponentItemsSecondRequestUsesCache;
    /// <summary>Kopf der Methode aus dem Baum, auch weiter oben als die Zeilensuche reichte,
    /// und nicht der einer lokalen Prozedur.</summary>
    [Test]
    procedure SenderItemsFindsHeaderFarAboveAndSkipsLocalRoutines;
  end;

implementation

uses
  Atlas.Common.Semantics.NameResolver,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionCollector;

procedure TLspCompletionFormProposalTests.WarmUpFirstUse;
begin
  Setup;
  try
    ComponentItemsSecondRequestUsesCache;
  finally
    TearDown;
  end;
end;

procedure TLspCompletionFormProposalTests.Setup;
begin
  Prepare;
end;

procedure TLspCompletionFormProposalTests.TearDown;
begin
  Release;
end;

procedure TLspCompletionFormProposalTests.OffersFormComponentsByNameAndType;
const
  UnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm = class'#13#10 +
    '  end;'#13#10 +
    '  TPanel = class'#13#10 +
    '  end;'#13#10 +
    '  TButtonControl = class'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TButtonControl)'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    '  TCheckBox = class(TButtonControl)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  // Formular wie aus dem Designer; der Panel-Inhalt zählt mit.
  FormText =
    'object frmMain: TfrmMain'#13#10 +
    '  Caption = ''Haupt'''#13#10 +
    '  object pnlOben: TPanel'#13#10 +
    '    object btnSave: TButton'#13#10 +
    '      Caption = ''Speichern'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '  end'#13#10 +
    '  object chkAktiv: TCheckBox'#13#10 +
    '  end'#13#10 +
    'end';

  /// <summary>Zeile 15 im Rumpf von Frei, Zeile 19 in TfrmMain.FormCreate.</summary>
  function Source(const AFrei, AForm: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'uses Steuer;'#13#10 +
      'type'#13#10 +
      '  TfrmMain = class(TForm)'#13#10 +
      '    pnlOben: TPanel;'#13#10 +
      '    btnSave: TButton;'#13#10 +
      '    btnLoad: TBitBtn;'#13#10 +
      '    chkAktiv: TCheckBox;'#13#10 +
      '    procedure FormCreate(Sender: TObject);'#13#10 +
      '  end;'#13#10 +
      'implementation'#13#10 +
      '{$R *.dfm}'#13#10 +
      'procedure Frei;'#13#10 +
      'begin'#13#10 +
      '  ' + AFrei + #13#10 +
      'end;'#13#10 +
      'procedure TfrmMain.FormCreate(Sender: TObject);'#13#10 +
      'begin'#13#10 +
      '  ' + AForm + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

  /// <summary>Komponenten mit ATyped vor dem Cursor, in der Methode des Formulars oder in Frei.</summary>
  function Components(const ATyped: string; AInForm: Boolean; out AItems: TArray<TCompletionItem>): Boolean;
  var
    Text: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
    Position: TTextPosition;
  begin
    if AInForm then
    begin
      Text := Source('', ATyped);
      Position := TTextPosition.Create(19, 2 + Length(ATyped));
    end
    else
    begin
      Text := Source(ATyped, '');
      Position := TTextPosition.Create(15, 2 + Length(ATyped));
    end;
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      Result := ComponentsAt(LookupOf(Resolver, nil, Tree, Text,
        function(const AFileName: string; out AText: string): Boolean
        begin
          AText := FormText;
          Result := SameText(ExtractFileExt(AFileName), '.dfm');
        end),
        Position, AItems);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

  function Joined(const AItems: TArray<TCompletionItem>): string;
  var
    Item: TCompletionItem;
  begin
    Result := '';
    for Item in AItems do
    begin
      Result := Result + Item.Name;
      if Item.ByType then
      begin
        Result := Result + '*';
      end;
      Result := Result + ' ';
    end;
    Result := Result.Trim;
  end;

var
  Items: TArray<TCompletionItem>;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSteuer, 'C:\P\Steuer.pas', nil));
  // Ohne Getipptes alle Komponenten in der Reihenfolge der Formulardatei, mit Typ und Formularname.
  Assert.IsTrue(Components('', True, Items));
  Assert.AreEqual('pnlOben btnSave btnLoad chkAktiv', Joined(Items));
  Assert.AreEqual('TButton', Items[1].Detail);
  Assert.AreEqual('frmMain', Items[1].Form);
  Assert.AreEqual(3, Items[1].Scope);
  // Über den Namen.
  Assert.IsTrue(Components('btn', True, Items));
  Assert.AreEqual('btnSave btnLoad', Joined(Items));
  // Über den Typ: TButton selbst und TBitBtn als Nachfahr, nicht TCheckBox über TButtonControl.
  Assert.IsTrue(Components('button', True, Items));
  Assert.AreEqual('btnSave* btnLoad*', Joined(Items));
  // Außerhalb der Methoden des Formulars nichts.
  Assert.IsFalse(Components('', False, Items));
end;
procedure TLspCompletionFormProposalTests.OffersFormComponentsFuzzyWithFilterText;
const
  UnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm = class'#13#10 +
    '  end;'#13#10 +
    '  TButton = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  FormText =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '  end'#13#10 +
    '  object SaveButton: TButton'#13#10 +
    '  end'#13#10 +
    'end';
  Source =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Steuer;'#13#10 +
    'type'#13#10 +
    '  TfrmMain = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    SaveButton: TButton;'#13#10 +
    '    procedure FormCreate(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TfrmMain.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  %s'#13#10 +
    'end;'#13#10 +
    'end.';

  function Components(const ATyped: string): TArray<TCompletionItem>;
  var
    Text: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
  begin
    Text := Format(Source, [ATyped]);
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      ComponentsAt(LookupOf(Resolver, nil, Tree, Text,
        function(const AFileName: string; out AText: string): Boolean
        begin
          AText := FormText;
          Result := SameText(ExtractFileExt(AFileName), '.dfm');
        end),
        TTextPosition.Create(13, 2 + Length(ATyped)), Result);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

  function Find(const AItems: TArray<TCompletionItem>; const AName: string; out AItem: TCompletionItem): Boolean;
  var
    Item: TCompletionItem;
  begin
    for Item in AItems do
    begin
      if Item.Name = AName then
      begin
        AItem := Item;
        Exit(True);
      end;
    end;
    AItem := Default(TCompletionItem);
    Result := False;
  end;

var
  Items: TArray<TCompletionItem>;
  Item: TCompletionItem;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSteuer, 'C:\P\Steuer.pas', nil));
  // Kürzel über Wortanfänge: "SB" → SaveButton, "bs" → btnSave.
  Items := Components('SB');
  Assert.IsTrue(Find(Items, 'SaveButton', Item), 'SB → SaveButton');
  Assert.IsFalse(Item.ByType);
  Assert.AreEqual('SB', Item.FilterText);
  Items := Components('bs');
  Assert.IsTrue(Find(Items, 'btnSave', Item), 'bs → btnSave');
  Assert.AreEqual('bs', Item.FilterText);
  // Teilwort: "Button" mitten im Namen.
  Items := Components('Button');
  Assert.IsTrue(Find(Items, 'SaveButton', Item), 'Button → SaveButton');
  Assert.AreEqual('Button', Item.FilterText);
  // Passender Anfang braucht keinen filterText.
  Items := Components('btn');
  Assert.IsTrue(Find(Items, 'btnSave', Item));
  Assert.AreEqual('', Item.FilterText);
  Items := nil;
  Item := Default(TCompletionItem);
end;
procedure TLspCompletionFormProposalTests.MatchScoreRanksAbbreviationBeforeSubstring;
var
  Prefix, Abbreviation, Substring, WordSubstring: Integer;
begin
  Prefix := MatchScore('SbList', 'sb', TCompletionMatching.Fuzzy);
  Abbreviation := MatchScore('SaveButton', 'sb', TCompletionMatching.Fuzzy);
  Substring := MatchScore('Ausbau', 'sb', TCompletionMatching.Fuzzy);
  WordSubstring := MatchScore('lstSbox', 'sb', TCompletionMatching.Fuzzy);
  Assert.AreNotEqual(Integer(TFuzzyMatch.cNoMatch), Abbreviation);
  Assert.IsTrue(Prefix > Abbreviation, Format('Anfang %d vor Kürzel %d', [Prefix, Abbreviation]));
  Assert.IsTrue(Abbreviation > Substring, Format('Kürzel %d vor Teilwort %d', [Abbreviation, Substring]));
  Assert.IsTrue(Abbreviation > WordSubstring,
    Format('Kürzel %d vor Teilwort am Wortanfang %d', [Abbreviation, WordSubstring]));
  // Mit completion.matching = prefix bleibt es beim Anfang.
  Assert.AreEqual(Integer(TFuzzyMatch.cNoMatch), MatchScore('SaveButton', 'sb', TCompletionMatching.Prefix));
end;

const
  cSenderUnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TControl = class'#13#10 +
    '  public'#13#10 +
    '    Caption: string;'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TControl)'#13#10 +
    '  public'#13#10 +
    '    procedure Click;'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    '  TForm = class(TControl)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TButton.Click;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';
  cSenderFormText =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';
  // Zeile 14: "  Sender.Cap" in btnAnyClick, Zeile 18: "  Sender." in Frei (keinem Ereignis zugewiesen).
  cSenderText =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Steuer;'#13#10 +
    'type'#13#10 +
    '  TfrmMain = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    btnLoad: TBitBtn;'#13#10 +
    '    procedure btnAnyClick(Sender: TObject);'#13#10 +
    '    procedure Frei(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TfrmMain.btnAnyClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  Sender.Cap'#13#10 +
    'end;'#13#10 +
    'procedure TfrmMain.Frei(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  Sender.'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TLspCompletionFormProposalTests.CastsSenderToAssignedComponents;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  ReadForm: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cSenderUnitSteuer, 'C:\P\Steuer.pas', nil));
  ReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cSenderFormText;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  Tree := TPascalParser.Parse(cSenderText);
  Resolver := TNameResolver.Create(FIndex);
  try
    // btnSave (TButton) und btnLoad (TBitBtn): gemeinsamer Vorfahr TButton.
    Assert.IsTrue(SendersAt(LookupOf(Resolver, FIndex, Tree, cSenderText, ReadForm),
      TTextPosition.Create(14, 12), TCompletionSenderCast.AsOperator, Items));
    Assert.AreEqual('Caption', Names(Items));
    Assert.AreEqual('TButton', Items.Items[0].Sender);
    Assert.AreEqual('btnSave, btnLoad', Items.Items[0].SenderOf);
    Assert.IsTrue(Items.Items[0].HasTextEdit);
    Assert.AreEqual('(Sender as TButton).Caption', Items.Items[0].TextEdit.NewText);
    Assert.AreEqual(2, Items.Items[0].TextEdit.Range.StartPos.Character);
    Assert.AreEqual(12, Items.Items[0].TextEdit.Range.EndPos.Character);
    Assert.IsTrue(SendersAt(LookupOf(Resolver, FIndex, Tree, cSenderText, ReadForm),
      TTextPosition.Create(14, 12), TCompletionSenderCast.HardCast, Items));
    Assert.AreEqual('TButton(Sender).Caption', Items.Items[0].TextEdit.NewText);
    // Ohne Zuweisung im Formular bleibt es bei den Mitgliedern von TObject.
    Assert.IsFalse(SendersAt(LookupOf(Resolver, FIndex, Tree, cSenderText, ReadForm),
      TTextPosition.Create(18, 9), TCompletionSenderCast.AsOperator, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionFormProposalTests.OffersDataFieldNames;
const
  FormText =
    'object frmOrders: TfrmOrders'#13#10 +
    '  object qryOrders: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select O.CUSTOMER_ID, O.CURRENCY, O.TOTAL from ORDERS O where O.ID = :OrderId'')'#13#10 +
    '    object qryOrdersCUSTOMER_ID: TIntegerField'#13#10 +
    '      FieldName = ''CUSTOMER_ID'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  function Items(const ALine: string; ACharacter: Integer; out AItems: TCompletionItems): Boolean;
  begin
    Result := DataNamesAt(LookupOf(nil, nil, nil, 'unit Haupt;'#13#10'{$R *.dfm}'#13#10 + ALine + #13#10,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := FormText;
        Result := SameText(ExtractFileExt(AFileName), '.dfm');
      end),
      TTextPosition.Create(2, ACharacter), AItems);
  end;

var
  Found: TCompletionItems;
  Json: TJSONObject;
begin
  // qryOrders.FieldByName('cu|'): persistente Felder, dann Spalten; der ganze String-Inhalt wird ersetzt.
  Assert.IsTrue(Items('  qryOrders.FieldByName(''cu'').AsInteger;', 27, Found));
  Assert.AreEqual(3, Integer(Length(Found.Items)));
  Assert.AreEqual('CUSTOMER_ID', Found.Items[0].Name);
  Assert.AreEqual('Integer', Found.Items[0].Detail);
  Assert.AreEqual('CURRENCY', Found.Items[1].Name);
  Assert.AreEqual('TOTAL', Found.Items[2].Name);
  Assert.IsTrue(Found.Items[1].HasTextEdit);
  Assert.AreEqual(25, Found.Items[1].TextEdit.Range.StartPos.Character);
  Assert.AreEqual(27, Found.Items[1].TextEdit.Range.EndPos.Character);
  Assert.AreEqual('CURRENCY', Found.Items[1].TextEdit.NewText);
  Json := TLspCompletion.ToJson(Found);
  try
    Assert.IsTrue(Json.ToJSON.Contains('"dataSet":"qryOrders"'));
    Assert.IsTrue(Json.ToJSON.Contains('"dataSource":"select O.CUSTOMER_ID'));
  finally
    Json.Free;
  end;
  // ParamByName: die Platzhalter.
  Assert.IsTrue(Items('  qryOrders.ParamByName('''')', 25, Found));
  Assert.AreEqual(1, Integer(Length(Found.Items)));
  Assert.AreEqual('OrderId', Found.Items[0].Name);
  // Zur Laufzeit erzeugt: im String, aber ohne Vorschlag.
  Assert.IsTrue(Items('  qryNeu.FieldByName(''cu'')', 24, Found));
  Assert.AreEqual(0, Integer(Length(Found.Items)));
  // Andere Strings gehören nicht dazu.
  Assert.IsFalse(Items('  ShowMessage(''cu'');', 17, Found));
end;
const
  FormUnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TControl = class'#13#10 +
    '  public'#13#10 +
    '    Caption: string;'#13#10 +
    '  end;'#13#10 +
    '  TForm = class(TControl)'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TControl)'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  FormDfm =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '    OnEnter = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';

/// <summary>Formular-Unit; ABody steht in Zeile 13 im Rumpf von TfrmMain.FormCreate, AClass in Zeile 7 im
/// Klassenrumpf.</summary>
function FormSource(const AClass, ABody: string): string;
begin
  Result :=
    'unit Haupt;'#13#10 +                                  // 0
    'interface'#13#10 +                                    // 1
    'uses Steuer;'#13#10 +                                 // 2
    'type'#13#10 +                                         // 3
    '  TfrmMain = class(TForm)'#13#10 +                    // 4
    '    btnSave: TButton;'#13#10 +                        // 5
    '    btnLoad: TBitBtn;'#13#10 +                        // 6
    '    ' + AClass + #13#10 +                             // 7
    '    procedure FormCreate(Sender: TObject);'#13#10 +   // 8
    '  end;'#13#10 +                                       // 9
    'implementation'#13#10 +                               // 10
    '{$R *.dfm}'#13#10 +                                   // 11
    'procedure TfrmMain.FormCreate(Sender: TObject);'#13#10 + // 12
    'begin'#13#10 +                                        // 13
    '  ' + ABody + #13#10 +                                // 14
    'end;'#13#10 +
    'end.';
end;
procedure TLspCompletionFormProposalTests.ComponentItemsOutsideRoutineDoesNotReadForm;
var
  Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  Reads: Integer;
  ReadForm: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(FormUnitSteuer, 'C:\P\Steuer.pas', nil));
  Reads := 0;
  ReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(Reads);
      AText := FormDfm;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  Resolver := TNameResolver.Create(FIndex);
  try
    // Im Klassenrumpf: keine Routine, also kein Lesezugriff.
    Text := FormSource('btn', '');
    Tree := TPascalParser.Parse(Text);
    try
      Assert.IsFalse(ComponentsAt(LookupOf(Resolver, nil, Tree, Text, ReadForm),
        TTextPosition.Create(7, 7), Items));
      Assert.AreEqual(0, Reads);
    finally
      Tree.Free;
    end;
    // In der Methode: einmal gelesen, beide Komponenten.
    Text := FormSource('', 'btn');
    Tree := TPascalParser.Parse(Text);
    try
      Assert.IsTrue(ComponentsAt(LookupOf(Resolver, nil, Tree, Text, ReadForm),
        TTextPosition.Create(14, 5), Items));
      Assert.AreEqual(1, Reads);
      Assert.AreEqual(2, Integer(Length(Items)));
      Assert.AreEqual('btnSave', Items[0].Name);
      Assert.AreEqual('frmMain', Items[0].Form);
      Assert.AreEqual('TfrmMain', Items[0].Container);
    finally
      Tree.Free;
    end;
  finally
    Resolver.Free;
  end;
end;
procedure TLspCompletionFormProposalTests.ComponentItemsSecondRequestUsesCache;
var
  Folder, UnitFile, DfmFile, Text, Answer: string;
  Store: IDocumentStore;
  Completion: TLspCompletion;
  Dispatcher: TJsonRpcDispatcher;
  Reads, Id: Integer;

  function Ask: string;
  var
    Request, Response: TJSONObject;
  begin
    Inc(Id);
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(Id) +
      ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' +
      TDocumentUris.FromPath(UnitFile).Replace('\', '\\') + '"},"position":{"line":14,"character":5}}}') as TJSONObject;
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
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasFormCache' + IntToStr(Random(1000000)));
  ForceDirectories(Folder);
  UnitFile := TPath.Combine(Folder, 'Haupt.pas');
  DfmFile := TPath.Combine(Folder, 'Haupt.dfm');
  TFile.WriteAllText(DfmFile, FormDfm);
  Text := FormSource('', 'btn');
  FIndex.AddUnit(TIndexExtractor.ExtractText(FormUnitSteuer, TPath.Combine(Folder, 'Steuer.pas'), nil));
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(UnitFile), 'delphi', 1, Text);
  Reads := 0;
  Id := 0;
  Completion := TLspCompletion.Create(Store, FIndex);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Completion.Hooks.ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, DfmFile) and FileExists(AFileName);
        if Result then
        begin
          Inc(Reads);
          AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
        end;
      end;
    Completion.Attach(Dispatcher);
    Answer := Ask;
    Assert.IsTrue(Answer.Contains('"btnSave"'), Answer);
    Assert.AreEqual(1, Reads);
    // Unveränderte Datei: kein weiterer Lesezugriff.
    Answer := Ask;
    Assert.IsTrue(Answer.Contains('"btnLoad"'), Answer);
    Assert.AreEqual(1, Reads);
    // Komponente umbenannt, Datei mit neuer Zeit: neu gelesen.
    TFile.WriteAllText(DfmFile, FormDfm.Replace('btnLoad', 'btnOpen'));
    FileSetDate(DfmFile, DateTimeToFileDate(Now + 1));
    Answer := Ask;
    Assert.AreEqual(2, Reads);
    // btnLoad bleibt als Feld der Klasse in der Liste, nur nicht mehr als Komponente des Formulars.
    Assert.IsTrue(Answer.Contains('"btnOpen"'), Answer);
  finally
    Dispatcher.Free;
    Completion.Free;
    TDirectory.Delete(Folder, True);
  end;
end;
procedure TLspCompletionFormProposalTests.SenderItemsFindsHeaderFarAboveAndSkipsLocalRoutines;
const
  Filler = 2100;
var
  Text, Body: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  ReadForm: TCompletionReadText;
  Index, Line: Integer;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(FormUnitSteuer, 'C:\P\Steuer.pas', nil));
  ReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := FormDfm;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  // Lokale Prozedur zwischen Kopf und Cursor, dann mehr Zeilen, als die frühere Zeilensuche (2000) prüfte.
  Body := '';
  for Index := 1 to Filler do
  begin
    Body := Body + '  // Zeile'#13#10;
  end;
  Text :=
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
    '  procedure Innen(A: Integer);'#13#10 +
    '  begin'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    Body +
    '  Sender.Cap'#13#10 +
    'end;'#13#10 +
    'end.';
  Line := 16 + Filler;
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(SendersAt(LookupOf(Resolver, FIndex, Tree, Text, ReadForm),
      TTextPosition.Create(Line, 12), TCompletionSenderCast.AsOperator, Items));
    Assert.AreEqual('Caption', Names(Items));
    Assert.AreEqual('TButton', Items.Items[0].Sender);
    // btnLoad hat zwei Ereignisse auf die Methode, zählt aber einmal.
    Assert.AreEqual('btnSave, btnLoad', Items.Items[0].SenderOf);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionFormProposalTests);

end.
