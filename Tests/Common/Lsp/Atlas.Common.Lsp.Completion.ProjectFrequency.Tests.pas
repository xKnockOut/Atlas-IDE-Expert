unit Atlas.Common.Lsp.Completion.ProjectFrequency.Tests;

// Tests für die Rangfolge aus der Verwendung im Projekt (#2109): Zahl "projectUses" an den Mitgliedern nach "X.",
// Einstellung completion.projectFrequency und Antwortzeit.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TCompletionProjectFrequencyTests = class
  private
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    FCompletion: TLspCompletion;
    FDispatcher: TJsonRpcDispatcher;
    FSettings: TCompletionSettings;
    FId: Integer;
    /// <summary>Fragt an der Stelle von "|" in AText (Datei Haupt.pas). Der Aufrufer gibt frei.</summary>
    function Complete(const AText: string): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MembersCarryProjectCount;
    [Test]
    procedure UnusedMemberHasNoCount;
    [Test]
    procedure ScopeListHasNoCount;
    [Test]
    procedure SwitchedOffHasNoCount;
    [Test]
    procedure ChangedUnitUpdatesCount;
    [Test]
    [Category('Benchmark')]
    procedure ManyMembersStayFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitZaehler =
    'unit Zaehler;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TZaehler = class'#13#10 +
    '  public'#13#10 +
    '    FEnde: Integer;'#13#10 +
    '    procedure Leere;'#13#10 +
    '    function Anzahl: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TZaehler.Leere; begin end;'#13#10 +
    'function TZaehler.Anzahl: Integer; begin Result := 0; end;'#13#10 +
    'end.';

  /// <summary>Projekt-Unit, die Anzahl dreimal und FEnde einmal verwendet.</summary>
  cUnitNutzer =
    'unit Nutzer;'#13#10 +
    'interface'#13#10 +
    'uses Zaehler;'#13#10 +
    'implementation'#13#10 +
    'procedure Lauf(AZaehler: TZaehler);'#13#10 +
    'begin'#13#10 +
    '  if AZaehler.Anzahl > AZaehler.Anzahl then AZaehler.FEnde := AZaehler.Anzahl;'#13#10 +
    'end;'#13#10 +
    'end.';

  /// <summary>Unit Haupt mit Pruefe(AZaehler: TZaehler), ABody zwischen begin und end.</summary>
  function HauptWith(const ABody: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'uses Zaehler;'#13#10 +
      'implementation'#13#10 +
      'procedure Pruefe(AZaehler: TZaehler);'#13#10 +
      'begin'#13#10 +
      ABody + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

  /// <summary>data.projectUses des Eintrags ALabel; 0 ohne Zahl, -1 ohne Eintrag.</summary>
  function ProjectUsesOf(AResult: TJSONObject; const ALabel: string): Integer;
  var
    mItem: TJSONValue;
    mData: TJSONValue;
  begin
    Result := -1;
    for mItem in AResult.GetValue('items') as TJSONArray do
    begin
      if (mItem as TJSONObject).GetValue<string>('label') <> ALabel then
      begin
        Continue;
      end;
      Result := 0;
      mData := TJSONObject(mItem).GetValue('data');
      if (mData is TJSONObject) and (TJSONObject(mData).GetValue('projectUses') <> nil) then
      begin
        Result := StrToInt(TJSONObject(mData).GetValue('projectUses').Value);
      end;
      Exit;
    end;
  end;

{ TCompletionProjectFrequencyTests }

procedure TCompletionProjectFrequencyTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FSettings := TCompletionSettings.Default;
  FId := 0;
  FCompletion := TLspCompletion.Create(FStore, FIndex);
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := FSettings;
    end;
  FDispatcher := TJsonRpcDispatcher.Create;
  FCompletion.Attach(FDispatcher);
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitZaehler, 'C:\P\Zaehler.pas', nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitNutzer, 'C:\P\Nutzer.pas', nil, nil, True));
end;

procedure TCompletionProjectFrequencyTests.TearDown;
begin
  FDispatcher.Free;
  FCompletion.Free;
  FStore := nil;
  FIndex := nil;
end;

function TCompletionProjectFrequencyTests.Complete(const AText: string): TJSONObject;
var
  mMarker, mIndex, mLine, mLineStart: Integer;
  mText, mUri: string;
  mRequest, mResponse: TJSONObject;
begin
  mMarker := Pos('|', AText);
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
  Inc(FId);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') +
    '"},"position":{"line":' + IntToStr(mLine) + ',"character":' + IntToStr(mMarker - mLineStart) + '}}}') as
    TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, mResponse.ToJSON);
    Result := mResponse.GetValue('result').Clone as TJSONObject;
  finally
    mResponse.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.MembersCarryProjectCount;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(3, ProjectUsesOf(mAnswer, 'Anzahl'), mAnswer.ToJSON);
    Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'FEnde'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.UnusedMemberHasNoCount;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(0, ProjectUsesOf(mAnswer, 'Leere'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.ScopeListHasNoCount;
var
  mAnswer: TJSONObject;
begin
  // Nur nach "X.": In der Liste ohne Punkt ordnet die Zählung nichts.
  mAnswer := Complete(HauptWith('  AZae|'));
  try
    Assert.AreEqual(0, ProjectUsesOf(mAnswer, 'AZaehler'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.SwitchedOffHasNoCount;
var
  mAnswer: TJSONObject;
begin
  FSettings.ProjectFrequency := False;
  mAnswer := Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(0, ProjectUsesOf(mAnswer, 'Anzahl'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.ChangedUnitUpdatesCount;
var
  mAnswer: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitNutzer.Replace('AZaehler.Anzahl > AZaehler.Anzahl',
    'AZaehler.Leere'), 'C:\P\Nutzer.pas', nil, nil, True));
  mAnswer := Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'Anzahl'), mAnswer.ToJSON);
    Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'Leere'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.ManyMembersStayFast;
const
  cMembers = 3000;
  cRounds = 5;
var
  mUnit: TStringBuilder;
  mIndex: Integer;
  mWatch: TStopwatch;
  mWith, mWithout: Int64;
  mAnswer: TJSONObject;
  mText: string;
begin
  // Klasse mit vielen Mitgliedern, eine Projekt-Unit verwendet jedes: Die Zahlen dürfen die Antwort nur
  // geringfügig verlangsamen.
  mUnit := TStringBuilder.Create;
  try
    mUnit.Append('unit Gross;'#13#10'interface'#13#10'type'#13#10'  TGross = class'#13#10'  public'#13#10);
    for mIndex := 1 to cMembers do
    begin
      mUnit.Append('    FFeld' + IntToStr(mIndex) + ': Integer;'#13#10);
    end;
    mUnit.Append('  end;'#13#10'implementation'#13#10'end.');
    FIndex.AddUnit(TIndexExtractor.ExtractText(mUnit.ToString, 'C:\P\Gross.pas', nil, nil, True));
    mUnit.Clear;
    mUnit.Append('unit Gebrauch;'#13#10'interface'#13#10'uses Gross;'#13#10'implementation'#13#10 +
      'procedure Lauf(AGross: TGross);'#13#10'begin'#13#10);
    for mIndex := 1 to cMembers do
    begin
      mUnit.Append('  AGross.FFeld' + IntToStr(mIndex) + ' := 0;'#13#10);
    end;
    mUnit.Append('end;'#13#10'end.');
    FIndex.AddUnit(TIndexExtractor.ExtractText(mUnit.ToString, 'C:\P\Gebrauch.pas', nil, nil, True));
  finally
    mUnit.Free;
  end;
  mText := 'unit Haupt;'#13#10'interface'#13#10'uses Gross;'#13#10'implementation'#13#10 +
    'procedure Pruefe(AGross: TGross);'#13#10'begin'#13#10'  AGross.FFeld7|'#13#10'end;'#13#10'end.';
  mWith := 0;
  mWithout := 0;
  for mIndex := 1 to cRounds do
  begin
    FSettings.ProjectFrequency := False;
    mWatch := TStopwatch.StartNew;
    Complete(mText).Free;
    Inc(mWithout, mWatch.ElapsedMilliseconds);
    FSettings.ProjectFrequency := True;
    mWatch := TStopwatch.StartNew;
    mAnswer := Complete(mText);
    Inc(mWith, mWatch.ElapsedMilliseconds);
    try
      Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'FFeld7'));
    finally
      mAnswer.Free;
    end;
  end;
  Assert.IsTrue(mWith <= 2 * mWithout + 50 * cRounds, Format('%d ms mit, %d ms ohne', [mWith, mWithout]));
end;

end.
