unit Atlas.Common.Lsp.EventHandlers.Tests;

// Befehl atlas.server.eventHandlers (#856): Handler eines Projekts, Rümpfe in
// Vorfahren über den Index, nicht auffindbare gezählt, Form der Antwort.

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Dfm.EventHandlers,
  Atlas.Common.Lsp.EventHandlers;

type
  [TestFixture]
  TLspEventHandlersTests = class
  private
    FIndex: ISymbolIndex;
    FFiles: TDictionary<string, string>;
    FCommand: TLspEventHandlers;
    FHandlers: TArray<TEventHandler>;
    function Find(const AComponent, AEvent: string): TEventHandler;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ProjectFilesWithForms;
    [Test]
    procedure InheritedHandlerFoundInAncestor;
    [Test]
    procedure MissingBodyCounted;
    [Test]
    procedure WithoutFilesUsesIndexUnits;
    [Test]
    procedure JsonShape;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Metrics;

const
  BasisFile = 'C:\P\Basis.pas';
  KundeFile = 'C:\P\Kunde.pas';
  KundeForm = 'C:\P\Kunde.dfm';
  DienstFile = 'C:\P\Dienst.pas';

  UnitBasis =
    'unit Basis;'#10 +                                     // 0
    'interface'#10 +                                       // 1
    'type'#10 +                                            // 2
    '  TfrmBasis = class(TForm)'#10 +                      // 3
    '    procedure HilfeClick(Sender: TObject);'#10 +      // 4
    '  end;'#10 +                                          // 5
    'implementation'#10 +                                  // 6
    'procedure TfrmBasis.HilfeClick(Sender: TObject);'#10 + // 7
    'begin'#10 +                                           // 8
    'end;'#10 +                                            // 9
    'end.'#10;

  UnitKunde =
    'unit Kunde;'#10 +                                     // 0
    'interface'#10 +                                       // 1
    'uses Basis;'#10 +                                     // 2
    'type'#10 +                                            // 3
    '  TfrmKunde = class(TfrmBasis)'#10 +                  // 4
    '    procedure btnSpeichernClick(Sender: TObject);'#10 + // 5
    '  end;'#10 +                                          // 6
    'implementation'#10 +                                  // 7
    'procedure TfrmKunde.btnSpeichernClick(Sender: TObject);'#10 + // 8
    'begin'#10 +                                           // 9
    'end;'#10 +                                            // 10
    'end.'#10;

  FormKunde =
    'inherited frmKunde: TfrmKunde'#10 +
    '  object btnSpeichern: TButton'#10 +
    '    OnClick = btnSpeichernClick'#10 +
    '  end'#10 +
    '  object btnHilfe: TButton'#10 +
    '    OnClick = HilfeClick'#10 +
    '  end'#10 +
    '  object btnWeg: TButton'#10 +
    '    OnClick = GibtEsNicht'#10 +
    '  end'#10 +
    'end'#10;

  UnitDienst =
    'unit Dienst;'#10 +                                    // 0
    'interface'#10 +                                       // 1
    'type'#10 +                                            // 2
    '  TDienst = class'#10 +                               // 3
    '    procedure Tick(Sender: TObject);'#10 +            // 4
    '    procedure Start;'#10 +                            // 5
    '  end;'#10 +                                          // 6
    'implementation'#10 +                                  // 7
    'procedure TDienst.Tick(Sender: TObject);'#10 +        // 8
    'begin'#10 +                                           // 9
    'end;'#10 +                                            // 10
    'procedure TDienst.Start;'#10 +                        // 11
    'begin'#10 +                                           // 12
    '  FTimer.OnTimer := Tick;'#10 +                       // 13
    'end;'#10 +                                            // 14
    'end.'#10;

procedure TLspEventHandlersTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKunde, KundeFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitDienst, DienstFile, nil));
  FFiles := TDictionary<string, string>.Create;
  FFiles.Add(LowerCase(BasisFile), UnitBasis);
  FFiles.Add(LowerCase(KundeFile), UnitKunde);
  FFiles.Add(LowerCase(KundeForm), FormKunde);
  FFiles.Add(LowerCase(DienstFile), UnitDienst);
  FCommand := TLspEventHandlers.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Files := TArray<string>.Create(KundeFile, KundeForm, DienstFile);
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FFiles.TryGetValue(LowerCase(AFileName), AText);
    end);
  FCommand.Index := FIndex;
end;

procedure TLspEventHandlersTests.TearDown;
begin
  FreeAndNil(FCommand);
  FreeAndNil(FFiles);
  FIndex := nil;
  FHandlers := nil;
end;

function TLspEventHandlersTests.Find(const AComponent, AEvent: string): TEventHandler;
var
  Item: TEventHandler;
begin
  for Item in FHandlers do
    if SameText(Item.Component, AComponent) and SameText(Item.Event, AEvent) then
      Exit(Item);
  Assert.Fail('nicht gefunden: ' + AComponent + '.' + AEvent);
  Result := Default(TEventHandler);
end;

procedure TLspEventHandlersTests.ProjectFilesWithForms;
var
  Unresolved: Integer;
begin
  FHandlers := FCommand.Collect(TArray<string>.Create(KundeFile, KundeForm, DienstFile), Unresolved);
  Assert.AreEqual(3, Integer(Length(FHandlers)));
  Assert.AreEqual(9, Find('btnSpeichern', 'OnClick').Line);
  Assert.AreEqual(KundeFile, Find('btnSpeichern', 'OnClick').FileName);
  // Zuweisung im Code einer Unit ohne Formular.
  Assert.AreEqual(9, Find('FTimer', 'OnTimer').Line);
  Assert.AreEqual('TDienst', Find('FTimer', 'OnTimer').Container);
end;

procedure TLspEventHandlersTests.InheritedHandlerFoundInAncestor;
var
  Unresolved: Integer;
  Handler: TEventHandler;
begin
  FHandlers := FCommand.Collect(TArray<string>.Create(KundeFile), Unresolved);
  Handler := Find('btnHilfe', 'OnClick');
  Assert.AreEqual(BasisFile, Handler.FileName);
  Assert.AreEqual(8, Handler.Line);
  Assert.AreEqual(9, Handler.BodyLine);
  Assert.AreEqual('TfrmBasis', Handler.Container);
  Assert.AreEqual('TfrmKunde', Handler.FormClass);
end;

procedure TLspEventHandlersTests.MissingBodyCounted;
var
  Unresolved: Integer;
  Item: TEventHandler;
begin
  FHandlers := FCommand.Collect(TArray<string>.Create(KundeFile), Unresolved);
  Assert.AreEqual(1, Unresolved);
  for Item in FHandlers do
    Assert.AreNotEqual('btnWeg', Item.Component);
end;

procedure TLspEventHandlersTests.WithoutFilesUsesIndexUnits;
var
  Unresolved: Integer;
begin
  FHandlers := FCommand.Collect(nil, Unresolved);
  Assert.AreEqual(3, Integer(Length(FHandlers)));
end;

procedure TLspEventHandlersTests.JsonShape;
var
  Json: TJSONValue;
  Item: TJSONObject;
  Handlers, Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  try
    Json := FCommand.Execute(Arguments);
  finally
    Arguments.Free;
  end;
  try
    Assert.AreEqual(1, (Json as TJSONObject).GetValue<Integer>('format'));
    Assert.AreEqual(1, (Json as TJSONObject).GetValue<Integer>('unresolved'));
    Handlers := (Json as TJSONObject).GetValue<TJSONArray>('handlers');
    Assert.AreEqual(3, Handlers.Count);
    Item := Handlers.Items[0] as TJSONObject;
    Assert.AreEqual('TfrmKunde', Item.GetValue<string>('form'));
    Assert.AreEqual('btnSpeichern', Item.GetValue<string>('component'));
    Assert.AreEqual('TButton', Item.GetValue<string>('componentClass'));
    Assert.AreEqual('OnClick', Item.GetValue<string>('event'));
    Assert.AreEqual('btnSpeichernClick', Item.GetValue<string>('handler'));
    Assert.AreEqual('form', Item.GetValue<string>('origin'));
    Assert.AreEqual(9, Item.GetValue<Integer>('line'));
    Assert.AreEqual(10, Item.GetValue<Integer>('bodyLine'));
    Assert.AreEqual(KundeForm, Item.GetValue<string>('source'));
    Assert.IsNull(Item.FindValue('interval'));
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspEventHandlersTests);

end.
