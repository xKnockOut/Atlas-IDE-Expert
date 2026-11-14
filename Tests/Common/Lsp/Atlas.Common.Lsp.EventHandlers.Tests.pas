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
  cBasisFile = 'C:\P\Basis.pas';
  cKundeFile = 'C:\P\Kunde.pas';
  cKundeForm = 'C:\P\Kunde.dfm';
  cDienstFile = 'C:\P\Dienst.pas';

  cUnitBasis =
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

  cUnitKunde =
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

  cFormKunde =
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

  cUnitDienst =
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunde, cKundeFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitDienst, cDienstFile, nil));
  FFiles := TDictionary<string, string>.Create;
  FFiles.Add(LowerCase(cBasisFile), cUnitBasis);
  FFiles.Add(LowerCase(cKundeFile), cUnitKunde);
  FFiles.Add(LowerCase(cKundeForm), cFormKunde);
  FFiles.Add(LowerCase(cDienstFile), cUnitDienst);
  FCommand := TLspEventHandlers.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Files := TArray<string>.Create(cKundeFile, cKundeForm, cDienstFile);
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
  mItem: TEventHandler;
begin
  for mItem in FHandlers do
  begin
    if SameText(mItem.Component, AComponent) and SameText(mItem.Event, AEvent) then
    begin
      Exit(mItem);
    end;
  end;
  Assert.Fail('nicht gefunden: ' + AComponent + '.' + AEvent);
  Result := Default(TEventHandler);
end;

procedure TLspEventHandlersTests.ProjectFilesWithForms;
var
  mUnresolved: Integer;
begin
  FHandlers := FCommand.Collect(TArray<string>.Create(cKundeFile, cKundeForm, cDienstFile), mUnresolved);
  Assert.AreEqual(3, Integer(Length(FHandlers)));
  Assert.AreEqual(9, Find('btnSpeichern', 'OnClick').Line);
  Assert.AreEqual(cKundeFile, Find('btnSpeichern', 'OnClick').FileName);
  // Zuweisung im Code einer Unit ohne Formular.
  Assert.AreEqual(9, Find('FTimer', 'OnTimer').Line);
  Assert.AreEqual('TDienst', Find('FTimer', 'OnTimer').Container);
end;

procedure TLspEventHandlersTests.InheritedHandlerFoundInAncestor;
var
  mUnresolved: Integer;
  mHandler: TEventHandler;
begin
  FHandlers := FCommand.Collect(TArray<string>.Create(cKundeFile), mUnresolved);
  mHandler := Find('btnHilfe', 'OnClick');
  Assert.AreEqual(cBasisFile, mHandler.FileName);
  Assert.AreEqual(8, mHandler.Line);
  Assert.AreEqual(9, mHandler.BodyLine);
  Assert.AreEqual('TfrmBasis', mHandler.Container);
  Assert.AreEqual('TfrmKunde', mHandler.FormClass);
end;

procedure TLspEventHandlersTests.MissingBodyCounted;
var
  mUnresolved: Integer;
  mItem: TEventHandler;
begin
  FHandlers := FCommand.Collect(TArray<string>.Create(cKundeFile), mUnresolved);
  Assert.AreEqual(1, mUnresolved);
  for mItem in FHandlers do
  begin
    Assert.AreNotEqual('btnWeg', mItem.Component);
  end;
end;

procedure TLspEventHandlersTests.WithoutFilesUsesIndexUnits;
var
  mUnresolved: Integer;
begin
  FHandlers := FCommand.Collect(nil, mUnresolved);
  Assert.AreEqual(3, Integer(Length(FHandlers)));
end;

procedure TLspEventHandlersTests.JsonShape;
var
  mJson: TJSONValue;
  mItem: TJSONObject;
  mHandlers, mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mJson := FCommand.Execute(mArguments);
  finally
    mArguments.Free;
  end;
  try
    Assert.AreEqual(1, (mJson as TJSONObject).GetValue<Integer>('format'));
    Assert.AreEqual(1, (mJson as TJSONObject).GetValue<Integer>('unresolved'));
    mHandlers := (mJson as TJSONObject).GetValue<TJSONArray>('handlers');
    Assert.AreEqual(3, mHandlers.Count);
    mItem := mHandlers.Items[0] as TJSONObject;
    Assert.AreEqual('TfrmKunde', mItem.GetValue<string>('form'));
    Assert.AreEqual('btnSpeichern', mItem.GetValue<string>('component'));
    Assert.AreEqual('TButton', mItem.GetValue<string>('componentClass'));
    Assert.AreEqual('OnClick', mItem.GetValue<string>('event'));
    Assert.AreEqual('btnSpeichernClick', mItem.GetValue<string>('handler'));
    Assert.AreEqual('form', mItem.GetValue<string>('origin'));
    Assert.AreEqual(9, mItem.GetValue<Integer>('line'));
    Assert.AreEqual(10, mItem.GetValue<Integer>('bodyLine'));
    Assert.AreEqual(cKundeForm, mItem.GetValue<string>('source'));
    Assert.IsNull(mItem.FindValue('interval'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspEventHandlersTests);

end.
