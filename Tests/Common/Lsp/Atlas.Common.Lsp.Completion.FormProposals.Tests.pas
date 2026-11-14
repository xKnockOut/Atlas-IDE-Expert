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
    /// <summary>#882: Formular-Komponenten auch über Kürzel und Teilwort, mit dem getippten Wort als
    /// filterText.</summary>
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
  cUnitSteuer =
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
  cFormText =
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
    mText: string;
    mTree: TSyntaxTree;
    mResolver: TNameResolver;
    mPosition: TTextPosition;
  begin
    if AInForm then
    begin
      mText := Source('', ATyped);
      mPosition := TTextPosition.Create(19, 2 + Length(ATyped));
    end
    else
    begin
      mText := Source(ATyped, '');
      mPosition := TTextPosition.Create(15, 2 + Length(ATyped));
    end;
    mTree := TPascalParser.Parse(mText);
    mResolver := TNameResolver.Create(FIndex);
    try
      Result := ComponentsAt(LookupOf(mResolver, nil, mTree, mText,
        function(const AFileName: string; out AText: string): Boolean
        begin
          AText := cFormText;
          Result := SameText(ExtractFileExt(AFileName), '.dfm');
        end),
        mPosition, AItems);
    finally
      mResolver.Free;
      mTree.Free;
    end;
  end;

  function Joined(const AItems: TArray<TCompletionItem>): string;
  var
    mItem: TCompletionItem;
  begin
    Result := '';
    for mItem in AItems do
    begin
      Result := Result + mItem.Name;
      if mItem.ByType then
      begin
        Result := Result + '*';
      end;
      Result := Result + ' ';
    end;
    Result := Result.Trim;
  end;

var
  mItems: TArray<TCompletionItem>;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSteuer, 'C:\P\Steuer.pas', nil));
  // Ohne Getipptes alle Komponenten in der Reihenfolge der Formulardatei, mit Typ und Formularname.
  Assert.IsTrue(Components('', True, mItems));
  Assert.AreEqual('pnlOben btnSave btnLoad chkAktiv', Joined(mItems));
  Assert.AreEqual('TButton', mItems[1].Detail);
  Assert.AreEqual('frmMain', mItems[1].Form);
  Assert.AreEqual(3, mItems[1].Scope);
  // Über den Namen.
  Assert.IsTrue(Components('btn', True, mItems));
  Assert.AreEqual('btnSave btnLoad', Joined(mItems));
  // Über den Typ: TButton selbst und TBitBtn als Nachfahr, nicht TCheckBox über TButtonControl.
  Assert.IsTrue(Components('button', True, mItems));
  Assert.AreEqual('btnSave* btnLoad*', Joined(mItems));
  // Außerhalb der Methoden des Formulars nichts.
  Assert.IsFalse(Components('', False, mItems));
end;
procedure TLspCompletionFormProposalTests.OffersFormComponentsFuzzyWithFilterText;
const
  cUnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm = class'#13#10 +
    '  end;'#13#10 +
    '  TButton = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  cFormText =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '  end'#13#10 +
    '  object SaveButton: TButton'#13#10 +
    '  end'#13#10 +
    'end';
  cSource =
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
    mText: string;
    mTree: TSyntaxTree;
    mResolver: TNameResolver;
  begin
    mText := Format(cSource, [ATyped]);
    mTree := TPascalParser.Parse(mText);
    mResolver := TNameResolver.Create(FIndex);
    try
      ComponentsAt(LookupOf(mResolver, nil, mTree, mText,
        function(const AFileName: string; out AText: string): Boolean
        begin
          AText := cFormText;
          Result := SameText(ExtractFileExt(AFileName), '.dfm');
        end),
        TTextPosition.Create(13, 2 + Length(ATyped)), Result);
    finally
      mResolver.Free;
      mTree.Free;
    end;
  end;

  function Find(const AItems: TArray<TCompletionItem>; const AName: string; out AItem: TCompletionItem): Boolean;
  var
    mItem: TCompletionItem;
  begin
    for mItem in AItems do
    begin
      if mItem.Name = AName then
      begin
        AItem := mItem;
        Exit(True);
      end;
    end;
    AItem := Default(TCompletionItem);
    Result := False;
  end;

var
  mItems: TArray<TCompletionItem>;
  mItem: TCompletionItem;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSteuer, 'C:\P\Steuer.pas', nil));
  // Kürzel über Wortanfänge: "SB" → SaveButton, "bs" → btnSave.
  mItems := Components('SB');
  Assert.IsTrue(Find(mItems, 'SaveButton', mItem), 'SB → SaveButton');
  Assert.IsFalse(mItem.ByType);
  Assert.AreEqual('SB', mItem.FilterText);
  mItems := Components('bs');
  Assert.IsTrue(Find(mItems, 'btnSave', mItem), 'bs → btnSave');
  Assert.AreEqual('bs', mItem.FilterText);
  // Teilwort: "Button" mitten im Namen.
  mItems := Components('Button');
  Assert.IsTrue(Find(mItems, 'SaveButton', mItem), 'Button → SaveButton');
  Assert.AreEqual('Button', mItem.FilterText);
  // Passender Anfang braucht keinen filterText.
  mItems := Components('btn');
  Assert.IsTrue(Find(mItems, 'btnSave', mItem));
  Assert.AreEqual('', mItem.FilterText);
  mItems := nil;
  mItem := Default(TCompletionItem);
end;
procedure TLspCompletionFormProposalTests.MatchScoreRanksAbbreviationBeforeSubstring;
var
  mPrefix, mAbbreviation, mSubstring, mWordSubstring: Integer;
begin
  mPrefix := MatchScore('SbList', 'sb', TCompletionMatching.Fuzzy);
  mAbbreviation := MatchScore('SaveButton', 'sb', TCompletionMatching.Fuzzy);
  mSubstring := MatchScore('Ausbau', 'sb', TCompletionMatching.Fuzzy);
  mWordSubstring := MatchScore('lstSbox', 'sb', TCompletionMatching.Fuzzy);
  Assert.AreNotEqual(Integer(TFuzzyMatch.cNoMatch), mAbbreviation);
  Assert.IsTrue(mPrefix > mAbbreviation, Format('Anfang %d vor Kürzel %d', [mPrefix, mAbbreviation]));
  Assert.IsTrue(mAbbreviation > mSubstring, Format('Kürzel %d vor Teilwort %d', [mAbbreviation, mSubstring]));
  Assert.IsTrue(mAbbreviation > mWordSubstring,
    Format('Kürzel %d vor Teilwort am Wortanfang %d', [mAbbreviation, mWordSubstring]));
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TCompletionItems;
  mReadForm: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cSenderUnitSteuer, 'C:\P\Steuer.pas', nil));
  mReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cSenderFormText;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  mTree := TPascalParser.Parse(cSenderText);
  mResolver := TNameResolver.Create(FIndex);
  try
    // btnSave (TButton) und btnLoad (TBitBtn): gemeinsamer Vorfahr TButton.
    Assert.IsTrue(SendersAt(LookupOf(mResolver, FIndex, mTree, cSenderText, mReadForm),
      TTextPosition.Create(14, 12), TCompletionSenderCast.AsOperator, mItems));
    Assert.AreEqual('Caption', Names(mItems));
    Assert.AreEqual('TButton', mItems.Items[0].Sender);
    Assert.AreEqual('btnSave, btnLoad', mItems.Items[0].SenderOf);
    Assert.IsTrue(mItems.Items[0].HasTextEdit);
    Assert.AreEqual('(Sender as TButton).Caption', mItems.Items[0].TextEdit.NewText);
    Assert.AreEqual(2, mItems.Items[0].TextEdit.Range.StartPos.Character);
    Assert.AreEqual(12, mItems.Items[0].TextEdit.Range.EndPos.Character);
    Assert.IsTrue(SendersAt(LookupOf(mResolver, FIndex, mTree, cSenderText, mReadForm),
      TTextPosition.Create(14, 12), TCompletionSenderCast.HardCast, mItems));
    Assert.AreEqual('TButton(Sender).Caption', mItems.Items[0].TextEdit.NewText);
    // Ohne Zuweisung im Formular bleibt es bei den Mitgliedern von TObject.
    Assert.IsFalse(SendersAt(LookupOf(mResolver, FIndex, mTree, cSenderText, mReadForm),
      TTextPosition.Create(18, 9), TCompletionSenderCast.AsOperator, mItems));
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TLspCompletionFormProposalTests.OffersDataFieldNames;
const
  cFormText =
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
        AText := cFormText;
        Result := SameText(ExtractFileExt(AFileName), '.dfm');
      end),
      TTextPosition.Create(2, ACharacter), AItems);
  end;

var
  mFound: TCompletionItems;
  mJson: TJSONObject;
begin
  // qryOrders.FieldByName('cu|'): persistente Felder, dann Spalten; der ganze String-Inhalt wird ersetzt.
  Assert.IsTrue(Items('  qryOrders.FieldByName(''cu'').AsInteger;', 27, mFound));
  Assert.AreEqual(3, Integer(Length(mFound.Items)));
  Assert.AreEqual('CUSTOMER_ID', mFound.Items[0].Name);
  Assert.AreEqual('Integer', mFound.Items[0].Detail);
  Assert.AreEqual('CURRENCY', mFound.Items[1].Name);
  Assert.AreEqual('TOTAL', mFound.Items[2].Name);
  Assert.IsTrue(mFound.Items[1].HasTextEdit);
  Assert.AreEqual(25, mFound.Items[1].TextEdit.Range.StartPos.Character);
  Assert.AreEqual(27, mFound.Items[1].TextEdit.Range.EndPos.Character);
  Assert.AreEqual('CURRENCY', mFound.Items[1].TextEdit.NewText);
  mJson := TLspCompletion.ToJson(mFound);
  try
    Assert.IsTrue(mJson.ToJSON.Contains('"dataSet":"qryOrders"'));
    Assert.IsTrue(mJson.ToJSON.Contains('"dataSource":"select O.CUSTOMER_ID'));
  finally
    mJson.Free;
  end;
  // ParamByName: die Platzhalter.
  Assert.IsTrue(Items('  qryOrders.ParamByName('''')', 25, mFound));
  Assert.AreEqual(1, Integer(Length(mFound.Items)));
  Assert.AreEqual('OrderId', mFound.Items[0].Name);
  // Zur Laufzeit erzeugt: im String, aber ohne Vorschlag.
  Assert.IsTrue(Items('  qryNeu.FieldByName(''cu'')', 24, mFound));
  Assert.AreEqual(0, Integer(Length(mFound.Items)));
  // Andere Strings gehören nicht dazu.
  Assert.IsFalse(Items('  ShowMessage(''cu'');', 17, mFound));
end;
const
  cFormUnitSteuer =
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
  cFormDfm =
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
  mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mReads: Integer;
  mReadForm: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cFormUnitSteuer, 'C:\P\Steuer.pas', nil));
  mReads := 0;
  mReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(mReads);
      AText := cFormDfm;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  mResolver := TNameResolver.Create(FIndex);
  try
    // Im Klassenrumpf: keine Routine, also kein Lesezugriff.
    mText := FormSource('btn', '');
    mTree := TPascalParser.Parse(mText);
    try
      Assert.IsFalse(ComponentsAt(LookupOf(mResolver, nil, mTree, mText, mReadForm),
        TTextPosition.Create(7, 7), mItems));
      Assert.AreEqual(0, mReads);
    finally
      mTree.Free;
    end;
    // In der Methode: einmal gelesen, beide Komponenten.
    mText := FormSource('', 'btn');
    mTree := TPascalParser.Parse(mText);
    try
      Assert.IsTrue(ComponentsAt(LookupOf(mResolver, nil, mTree, mText, mReadForm),
        TTextPosition.Create(14, 5), mItems));
      Assert.AreEqual(1, mReads);
      Assert.AreEqual(2, Integer(Length(mItems)));
      Assert.AreEqual('btnSave', mItems[0].Name);
      Assert.AreEqual('frmMain', mItems[0].Form);
      Assert.AreEqual('TfrmMain', mItems[0].Container);
    finally
      mTree.Free;
    end;
  finally
    mResolver.Free;
  end;
end;
procedure TLspCompletionFormProposalTests.ComponentItemsSecondRequestUsesCache;
var
  mFolder, mUnitFile, mDfmFile, mText, mAnswer: string;
  mStore: IDocumentStore;
  mCompletion: TLspCompletion;
  mDispatcher: TJsonRpcDispatcher;
  mReads, mId: Integer;

  function Ask: string;
  var
    mRequest, mResponse: TJSONObject;
  begin
    Inc(mId);
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(mId) +
      ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' +
      TDocumentUris.FromPath(mUnitFile).Replace('\', '\\') + '"},"position":{"line":14,"character":5}}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
      try
        Result := mResponse.ToJSON;
      finally
        mResponse.Free;
      end;
    finally
      mRequest.Free;
    end;
  end;

begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasFormCache' + IntToStr(Random(1000000)));
  ForceDirectories(mFolder);
  mUnitFile := TPath.Combine(mFolder, 'Haupt.pas');
  mDfmFile := TPath.Combine(mFolder, 'Haupt.dfm');
  TFile.WriteAllText(mDfmFile, cFormDfm);
  mText := FormSource('', 'btn');
  FIndex.AddUnit(TIndexExtractor.ExtractText(cFormUnitSteuer, TPath.Combine(mFolder, 'Steuer.pas'), nil));
  mStore := TDocumentStore.Create;
  mStore.Open(TDocumentUris.FromPath(mUnitFile), 'delphi', 1, mText);
  mReads := 0;
  mId := 0;
  mCompletion := TLspCompletion.Create(mStore, FIndex);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mCompletion.Hooks.ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, mDfmFile) and FileExists(AFileName);
        if Result then
        begin
          Inc(mReads);
          AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
        end;
      end;
    mCompletion.Attach(mDispatcher);
    mAnswer := Ask;
    Assert.IsTrue(mAnswer.Contains('"btnSave"'), mAnswer);
    Assert.AreEqual(1, mReads);
    // Unveränderte Datei: kein weiterer Lesezugriff.
    mAnswer := Ask;
    Assert.IsTrue(mAnswer.Contains('"btnLoad"'), mAnswer);
    Assert.AreEqual(1, mReads);
    // Komponente umbenannt, Datei mit neuer Zeit: neu gelesen.
    TFile.WriteAllText(mDfmFile, cFormDfm.Replace('btnLoad', 'btnOpen'));
    FileSetDate(mDfmFile, DateTimeToFileDate(Now + 1));
    mAnswer := Ask;
    Assert.AreEqual(2, mReads);
    // btnLoad bleibt als Feld der Klasse in der Liste, nur nicht mehr als Komponente des Formulars.
    Assert.IsTrue(mAnswer.Contains('"btnOpen"'), mAnswer);
  finally
    mDispatcher.Free;
    mCompletion.Free;
    TDirectory.Delete(mFolder, True);
  end;
end;
procedure TLspCompletionFormProposalTests.SenderItemsFindsHeaderFarAboveAndSkipsLocalRoutines;
const
  cFiller = 2100;
var
  mText, mBody: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TCompletionItems;
  mReadForm: TCompletionReadText;
  mIndex, mLine: Integer;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cFormUnitSteuer, 'C:\P\Steuer.pas', nil));
  mReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cFormDfm;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  // Lokale Prozedur zwischen Kopf und Cursor, dann mehr Zeilen, als die frühere Zeilensuche (2000) prüfte.
  mBody := '';
  for mIndex := 1 to cFiller do
  begin
    mBody := mBody + '  // Zeile'#13#10;
  end;
  mText :=
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
    mBody +
    '  Sender.Cap'#13#10 +
    'end;'#13#10 +
    'end.';
  mLine := 16 + cFiller;
  mTree := TPascalParser.Parse(mText);
  mResolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(SendersAt(LookupOf(mResolver, FIndex, mTree, mText, mReadForm),
      TTextPosition.Create(mLine, 12), TCompletionSenderCast.AsOperator, mItems));
    Assert.AreEqual('Caption', Names(mItems));
    Assert.AreEqual('TButton', mItems.Items[0].Sender);
    // btnLoad hat zwei Ereignisse auf die Methode, zählt aber einmal.
    Assert.AreEqual('btnSave, btnLoad', mItems.Items[0].SenderOf);
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionFormProposalTests);

end.
