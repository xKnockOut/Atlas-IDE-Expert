unit Atlas.Common.Lsp.Architecture.Tests;

// Tests der Anfrage atlas/architecture und des Befehls
// atlas.architecture.saveReport (#1118), Stand und Vergleich (#1121),
// Feinheit "resolution" für einen Aufruf (#1366).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspArchitectureTests = class
  public
    /// <summary>Einmalige Puffer der JSON-Antwort vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    /// <summary>Globalen String LastScope leeren, sonst zählt der Leckmonitor ihn.</summary>
    [TearDown]
    procedure TearDown;
    [Test]
    procedure JsonAnswerHasDataAndLayout;
    [Test]
    procedure TextSectionAndUnit;
    [Test]
    procedure DisabledAnswersEnabledFalse;
    [Test]
    procedure RejectsUnknownFormatAndScope;
    [Test]
    procedure SavesMarkdownAndHtml;
    [Test]
    procedure CommandAnswersLikeRequest;
    [Test]
    procedure SavesStateAndCompares;
    [Test]
    procedure ResolutionOverridesSettingForOneCall;
    [Test]
    procedure RejectsInvalidResolution;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Lsp.Architecture,
  Atlas.Common.Architecture.UsesGraph.Tests;

var
  Enabled: Boolean;
  LastScope: string;
  /// <summary>architecture.baseline und Projektordner der Anfrage (#1121).</summary>
  BaselineSetting: string;
  ProjectRoot: string = 'C:\Projekt';
  /// <summary>architecture.grouping.resolution der Einstellungen (#1366).</summary>
  ResolutionSetting: Double = 1;

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(UsesUnit('App.Main', ['App.Data'], nil));
  Result.AddUnit(UsesUnit('App.Data', nil, nil));
end;

function NewService(const AIndex: ISymbolIndex): TArchitectureService;
begin
  Result := TArchitectureService.Create(AIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end);
end;

function NewLsp(AService: TArchitectureService): TLspArchitecture;
begin
  Result := TLspArchitecture.Create(AService,
    function(const AFileName, AScope: string; out ARequest: TArchitectureRequest;
      out ASettings: TServerSettings): Boolean
    begin
      ASettings := TServerSettings.Default;
      ASettings.ArchitectureEnabled := Enabled;
      ASettings.ArchitectureBaseline := BaselineSetting;
      ASettings.ArchitectureGroupingResolution := ResolutionSetting;
      ARequest := TArchitectureRequest.FromSettings(ASettings);
      ARequest.Title := 'Beispiel';
      ARequest.Root := ProjectRoot;
      LastScope := AScope;
      Result := True;
    end);
end;

/// <summary>Pfad als JSON-Zeichenkette.</summary>
function JsonPath(const APath: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(APath);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

function Ask(ALsp: TLspArchitecture; const AParams: string): TJSONObject;
var
  mParams: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue(AParams);
  try
    Result := ALsp.Request(mParams) as TJSONObject;
  finally
    mParams.Free;
  end;
end;

{ TLspArchitectureTests }

procedure TLspArchitectureTests.TearDown;
begin
  LastScope := '';
end;

procedure TLspArchitectureTests.WarmUpFirstUse;
begin
  JsonAnswerHasDataAndLayout;
  CommandAnswersLikeRequest;
  SavesStateAndCompares;
  TearDown;
end;

procedure TLspArchitectureTests.JsonAnswerHasDataAndLayout;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
  mAnswer: TJSONObject;
  mData: TJSONObject;
begin
  Enabled := True;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  mAnswer := Ask(mLsp, '{"scope": "project"}');
  try
    Assert.IsTrue(mAnswer.GetValue<Boolean>('enabled'));
    Assert.AreEqual('json', mAnswer.GetValue<string>('format'));
    Assert.AreEqual('project', LastScope);
    mData := mAnswer.GetValue<TJSONObject>('data');
    Assert.AreEqual('Beispiel', mData.GetValue<string>('title'));
    Assert.AreEqual(2, Integer(mData.GetValue<TJSONArray>('units').Count));
    Assert.IsNotNull((mData.GetValue<TJSONArray>('units').Items[0] as TJSONObject).GetValue('x'));
  finally
    mAnswer.Free;
    mLsp.Free;
    mService.Free;
  end;
end;

procedure TLspArchitectureTests.TextSectionAndUnit;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
  mAnswer: TJSONObject;
begin
  Enabled := True;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  try
    mAnswer := Ask(mLsp, '{"format": "text", "section": "central"}');
    try
      Assert.Contains(mAnswer.GetValue<string>('text'), 'App.Data | ');
    finally
      mAnswer.Free;
    end;
    mAnswer := Ask(mLsp, '{"format": "text", "unit": "App.Main"}');
    try
      Assert.StartsWith('App.Main (', mAnswer.GetValue<string>('text'));
    finally
      mAnswer.Free;
    end;
    mAnswer := Ask(mLsp, '{"format": "markdown"}');
    try
      Assert.StartsWith('# Architektur: Beispiel', mAnswer.GetValue<string>('text'));
    finally
      mAnswer.Free;
    end;
    Assert.AreEqual(1, mService.Computations, 'alle Abfragen aus demselben Ergebnis');
  finally
    mLsp.Free;
    mService.Free;
  end;
end;

procedure TLspArchitectureTests.DisabledAnswersEnabledFalse;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
  mAnswer: TJSONObject;
begin
  Enabled := False;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  mAnswer := Ask(mLsp, '{}');
  try
    Assert.IsFalse(mAnswer.GetValue<Boolean>('enabled'));
    Assert.IsNull(mAnswer.GetValue('data'));
    Assert.AreEqual(0, mService.Computations);
  finally
    mAnswer.Free;
    mLsp.Free;
    mService.Free;
  end;
  Enabled := True;
end;

procedure TLspArchitectureTests.RejectsUnknownFormatAndScope;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
begin
  Enabled := True;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  try
    Assert.WillRaise(
      procedure
      begin
        Ask(mLsp, '{"format": "pdf"}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        Ask(mLsp, '{"scope": "alles"}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        Ask(mLsp, '{"format": "text", "section": "nichts"}').Free;
      end, EJsonRpcError);
  finally
    mLsp.Free;
    mService.Free;
  end;
end;

procedure TLspArchitectureTests.SavesMarkdownAndHtml;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
  mFolder, mTarget: string;
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  Enabled := True;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-architektur-' + IntToStr(Random(1000000)));
  try
    mTarget := TPath.Combine(mFolder, 'bericht.md');
    mArguments := TJSONArray.Create;
    try
      mArguments.Add('');
      mArguments.Add(mTarget);
      mAnswer := mLsp.SaveReport(mArguments);
      try
        Assert.AreEqual(2, (mAnswer as TJSONObject).GetValue<Integer>('units'));
      finally
        mAnswer.Free;
      end;
    finally
      mArguments.Free;
    end;
    Assert.StartsWith('# Architektur: Beispiel', TFile.ReadAllText(mTarget, TEncoding.UTF8));
    mTarget := TPath.Combine(mFolder, 'bericht.html');
    mArguments := TJSONArray.Create;
    try
      mArguments.Add('');
      mArguments.Add(mTarget);
      mLsp.SaveReport(mArguments).Free;
    finally
      mArguments.Free;
    end;
    Assert.Contains(TFile.ReadAllText(mTarget, TEncoding.UTF8), '<!doctype html>');
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
    mLsp.Free;
    mService.Free;
  end;
end;

procedure TLspArchitectureTests.CommandAnswersLikeRequest;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
  mArguments: TJSONArray;
  mAnswer: TJSONObject;
begin
  Enabled := True;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  mArguments := TJSONObject.ParseJSONValue('["file:///C:/Projekt/App.dpr", {"scope": "project", "format": "text", ' +
    '"unit": "App.Data"}]') as TJSONArray;
  try
    mAnswer := mLsp.Execute(mArguments) as TJSONObject;
    try
      Assert.AreEqual('project', LastScope);
      Assert.AreEqual('text', mAnswer.GetValue<string>('format'));
      Assert.AreEqual('C:\Projekt', mAnswer.GetValue<string>('root'), 'root nur in der Antwort');
      Assert.IsTrue(Pos('App.Data', mAnswer.GetValue<string>('text')) > 0);
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
    mLsp.Free;
    mService.Free;
  end;
end;

/// <summary>Speichert den Bericht von ALsp nach ATarget.</summary>
procedure SaveReportTo(const ALsp: TLspArchitecture; const ATarget: string);
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add('');
    mArguments.Add(ATarget);
    ALsp.SaveReport(mArguments).Free;
  finally
    mArguments.Free;
  end;
end;

/// <summary>architecture.baseline relativ zum Projekt; "compare": false schaltet ab.</summary>
procedure AssertBaselineSettingAndCompareOff(const ALsp: TLspArchitecture; const AFolder: string);
var
  mAnswer: TJSONObject;
begin
  // architecture.baseline relativ zum Projekt; "compare": false schaltet ab.
  BaselineSetting := 'stand.json';
  ProjectRoot := AFolder;
  mAnswer := Ask(ALsp, '{"format": "markdown"}');
  try
    Assert.Contains(mAnswer.GetValue<string>('text'), '## Vergleich');
  finally
    mAnswer.Free;
  end;
  mAnswer := Ask(ALsp, '{"compare": false}');
  try
    Assert.IsNull(mAnswer.GetValue('comparison'));
  finally
    mAnswer.Free;
  end;
end;

/// <summary>Fehlender Stand: Meldung, die Übersicht kommt trotzdem.</summary>
procedure AssertMissingBaselineReported(const ALsp: TLspArchitecture);
var
  mAnswer: TJSONObject;
begin
  // Fehlender Stand: Meldung, die Übersicht kommt trotzdem.
  BaselineSetting := 'fehlt.json';
  mAnswer := Ask(ALsp, '{}');
  try
    Assert.Contains(mAnswer.GetValue<string>('comparisonError'), 'nicht gefunden');
    Assert.IsNotNull(mAnswer.GetValue('data'));
    Assert.IsNull(mAnswer.GetValue('comparison'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspArchitectureTests.SavesStateAndCompares;
var
  mService, mLater: TArchitectureService;
  mLsp, mLaterLsp: TLspArchitecture;
  mFolder, mTarget: string;
  mAnswer: TJSONObject;
  mIndex: ISymbolIndex;
begin
  Enabled := True;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  // Später: App.Data braucht App.Main, ein neuer Zyklus.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Main', ['App.Data'], nil));
  mIndex.AddUnit(UsesUnit('App.Data', nil, ['App.Main']));
  mLater := NewService(mIndex);
  mLaterLsp := NewLsp(mLater);
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-vergleich-' + IntToStr(Random(1000000)));
  try
    mTarget := TPath.Combine(mFolder, 'stand.json');
    SaveReportTo(mLsp, mTarget);
    Assert.Contains(TFile.ReadAllText(mTarget, TEncoding.UTF8), '"format": 2');
    mAnswer := Ask(mLaterLsp, '{"compareWith": ' + JsonPath(mTarget) + '}');
    try
      Assert.AreEqual(mTarget, mAnswer.GetValue<string>('baseline'));
      Assert.AreEqual(1, mAnswer.GetValue<TJSONObject>('comparison').GetValue<TJSONArray>('newCycles').Count);
      Assert.AreEqual('newCycle', mAnswer.GetValue<TJSONObject>('comparison').GetValue<TJSONArray>('failed')
        .Items[0].Value);
      Assert.IsNotNull(mAnswer.GetValue('data'));
    finally
      mAnswer.Free;
    end;
    mAnswer := Ask(mLaterLsp, '{"format": "text", "compareWith": ' + JsonPath(mTarget) + '}');
    try
      Assert.Contains(mAnswer.GetValue<string>('text'), 'Neue Zyklen: 1');
    finally
      mAnswer.Free;
    end;
    AssertBaselineSettingAndCompareOff(mLaterLsp, mFolder);
    mTarget := TPath.Combine(mFolder, 'bericht.md');
    SaveReportTo(mLaterLsp, mTarget);
    Assert.Contains(TFile.ReadAllText(mTarget, TEncoding.UTF8), '### Neue Zyklen (1)');
    AssertMissingBaselineReported(mLaterLsp);
  finally
    BaselineSetting := '';
    ProjectRoot := 'C:\Projekt';
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
    mLaterLsp.Free;
    mLater.Free;
    mLsp.Free;
    mService.Free;
  end;
end;

function ResolutionIn(AAnswer: TJSONObject): Double;
begin
  Result := AAnswer.GetValue<TJSONObject>('data').GetValue<TJSONObject>('grouping').GetValue<Double>('resolution');
end;

/// <summary>Die Antwort auf AParams nennt die Feinheit AExpected.</summary>
procedure AssertResolutionOf(const ALsp: TLspArchitecture; const AParams: string; AExpected: Double;
  const AMessage: string);
var
  mAnswer: TJSONObject;
begin
  mAnswer := Ask(ALsp, AParams);
  try
    Assert.AreEqual(AExpected, ResolutionIn(mAnswer), 1E-9, AMessage);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspArchitectureTests.ResolutionOverridesSettingForOneCall;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
  mAnswer: TJSONObject;
  mFolder, mTarget: string;
  mArguments: TJSONArray;
  mOptions: TJSONObject;
begin
  Enabled := True;
  ResolutionSetting := 1.5;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-feinheit-' + IntToStr(Random(1000000)));
  try
    AssertResolutionOf(mLsp, '{}', 1.5, 'Einstellung');
    AssertResolutionOf(mLsp, '{"resolution": 2}', 2, 'Anfrage');
    // Die Einstellung bleibt; ein anderer Wert rechnet neu.
    AssertResolutionOf(mLsp, '{}', 1.5, 'wieder die Einstellung');
    Assert.AreEqual(3, mService.Computations);
    mAnswer := Ask(mLsp, '{"format": "markdown", "resolution": 2}');
    try
      // Ohne γ verglichen: Der JSON-Leser unter FPC (Testlauf in der Cloud) liest Zeichen außerhalb Latin-1 falsch.
      Assert.Contains(mAnswer.GetValue<string>('text'), ', Feinheit ');
      Assert.Contains(mAnswer.GetValue<string>('text'), ' = 2,0');
    finally
      mAnswer.Free;
    end;
    // Bericht und Stand nehmen "resolution" aus den Optionen mit.
    mTarget := TPath.Combine(mFolder, 'stand.json');
    mArguments := TJSONArray.Create;
    try
      mArguments.Add('');
      mArguments.Add(mTarget);
      mOptions := TJSONObject.Create;
      mOptions.AddPair('resolution', TJSONNumber.Create(3));
      mArguments.AddElement(mOptions);
      mLsp.SaveReport(mArguments).Free;
    finally
      mArguments.Free;
    end;
    Assert.Contains(TFile.ReadAllText(mTarget, TEncoding.UTF8), '"grouping": {"resolution": 3}');
  finally
    ResolutionSetting := 1;
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
    mLsp.Free;
    mService.Free;
  end;
end;

procedure TLspArchitectureTests.RejectsInvalidResolution;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
begin
  Enabled := True;
  mService := NewService(NewIndex);
  mLsp := NewLsp(mService);
  try
    Assert.WillRaise(
      procedure
      begin
        Ask(mLsp, '{"resolution": 9}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        Ask(mLsp, '{"resolution": 0.1}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        Ask(mLsp, '{"resolution": "fein"}').Free;
      end, EJsonRpcError);
  finally
    mLsp.Free;
    mService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspArchitectureTests);

end.
