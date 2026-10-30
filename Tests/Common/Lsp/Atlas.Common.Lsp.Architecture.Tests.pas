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
  Value: TJSONString;
begin
  Value := TJSONString.Create(APath);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

function Ask(ALsp: TLspArchitecture; const AParams: string): TJSONObject;
var
  Params: TJSONValue;
begin
  Params := TJSONObject.ParseJSONValue(AParams);
  try
    Result := ALsp.Request(Params) as TJSONObject;
  finally
    Params.Free;
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
  Service: TArchitectureService;
  Lsp: TLspArchitecture;
  Answer: TJSONObject;
  Data: TJSONObject;
begin
  Enabled := True;
  Service := NewService(NewIndex);
  Lsp := NewLsp(Service);
  Answer := Ask(Lsp, '{"scope": "project"}');
  try
    Assert.IsTrue(Answer.GetValue<Boolean>('enabled'));
    Assert.AreEqual('json', Answer.GetValue<string>('format'));
    Assert.AreEqual('project', LastScope);
    Data := Answer.GetValue<TJSONObject>('data');
    Assert.AreEqual('Beispiel', Data.GetValue<string>('title'));
    Assert.AreEqual(2, Integer(Data.GetValue<TJSONArray>('units').Count));
    Assert.IsNotNull((Data.GetValue<TJSONArray>('units').Items[0] as TJSONObject).GetValue('x'));
  finally
    Answer.Free;
    Lsp.Free;
    Service.Free;
  end;
end;

procedure TLspArchitectureTests.TextSectionAndUnit;
var
  Service: TArchitectureService;
  Lsp: TLspArchitecture;
  Answer: TJSONObject;
begin
  Enabled := True;
  Service := NewService(NewIndex);
  Lsp := NewLsp(Service);
  try
    Answer := Ask(Lsp, '{"format": "text", "section": "central"}');
    try
      Assert.Contains(Answer.GetValue<string>('text'), 'App.Data | ');
    finally
      Answer.Free;
    end;
    Answer := Ask(Lsp, '{"format": "text", "unit": "App.Main"}');
    try
      Assert.StartsWith('App.Main (', Answer.GetValue<string>('text'));
    finally
      Answer.Free;
    end;
    Answer := Ask(Lsp, '{"format": "markdown"}');
    try
      Assert.StartsWith('# Architektur: Beispiel', Answer.GetValue<string>('text'));
    finally
      Answer.Free;
    end;
    Assert.AreEqual(1, Service.Computations, 'alle Abfragen aus demselben Ergebnis');
  finally
    Lsp.Free;
    Service.Free;
  end;
end;

procedure TLspArchitectureTests.DisabledAnswersEnabledFalse;
var
  Service: TArchitectureService;
  Lsp: TLspArchitecture;
  Answer: TJSONObject;
begin
  Enabled := False;
  Service := NewService(NewIndex);
  Lsp := NewLsp(Service);
  Answer := Ask(Lsp, '{}');
  try
    Assert.IsFalse(Answer.GetValue<Boolean>('enabled'));
    Assert.IsNull(Answer.GetValue('data'));
    Assert.AreEqual(0, Service.Computations);
  finally
    Answer.Free;
    Lsp.Free;
    Service.Free;
  end;
  Enabled := True;
end;

procedure TLspArchitectureTests.RejectsUnknownFormatAndScope;
var
  Service: TArchitectureService;
  Lsp: TLspArchitecture;
begin
  Enabled := True;
  Service := NewService(NewIndex);
  Lsp := NewLsp(Service);
  try
    Assert.WillRaise(
      procedure
      begin
        Ask(Lsp, '{"format": "pdf"}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        Ask(Lsp, '{"scope": "alles"}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        Ask(Lsp, '{"format": "text", "section": "nichts"}').Free;
      end, EJsonRpcError);
  finally
    Lsp.Free;
    Service.Free;
  end;
end;

procedure TLspArchitectureTests.SavesMarkdownAndHtml;
var
  Service: TArchitectureService;
  Lsp: TLspArchitecture;
  Folder, Target: string;
  Arguments: TJSONArray;
  Answer: TJSONValue;
begin
  Enabled := True;
  Service := NewService(NewIndex);
  Lsp := NewLsp(Service);
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-architektur-' + IntToStr(Random(1000000)));
  try
    Target := TPath.Combine(Folder, 'bericht.md');
    Arguments := TJSONArray.Create;
    try
      Arguments.Add('');
      Arguments.Add(Target);
      Answer := Lsp.SaveReport(Arguments);
      try
        Assert.AreEqual(2, (Answer as TJSONObject).GetValue<Integer>('units'));
      finally
        Answer.Free;
      end;
    finally
      Arguments.Free;
    end;
    Assert.StartsWith('# Architektur: Beispiel', TFile.ReadAllText(Target, TEncoding.UTF8));
    Target := TPath.Combine(Folder, 'bericht.html');
    Arguments := TJSONArray.Create;
    try
      Arguments.Add('');
      Arguments.Add(Target);
      Lsp.SaveReport(Arguments).Free;
    finally
      Arguments.Free;
    end;
    Assert.Contains(TFile.ReadAllText(Target, TEncoding.UTF8), '<!doctype html>');
  finally
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
    Lsp.Free;
    Service.Free;
  end;
end;

procedure TLspArchitectureTests.CommandAnswersLikeRequest;
var
  Service: TArchitectureService;
  Lsp: TLspArchitecture;
  Arguments: TJSONArray;
  Answer: TJSONObject;
begin
  Enabled := True;
  Service := NewService(NewIndex);
  Lsp := NewLsp(Service);
  Arguments := TJSONObject.ParseJSONValue('["file:///C:/Projekt/App.dpr", {"scope": "project", "format": "text", ' +
    '"unit": "App.Data"}]') as TJSONArray;
  try
    Answer := Lsp.Execute(Arguments) as TJSONObject;
    try
      Assert.AreEqual('project', LastScope);
      Assert.AreEqual('text', Answer.GetValue<string>('format'));
      Assert.AreEqual('C:\Projekt', Answer.GetValue<string>('root'), 'root nur in der Antwort');
      Assert.IsTrue(Pos('App.Data', Answer.GetValue<string>('text')) > 0);
    finally
      Answer.Free;
    end;
  finally
    Arguments.Free;
    Lsp.Free;
    Service.Free;
  end;
end;

procedure TLspArchitectureTests.SavesStateAndCompares;
var
  Service, Later: TArchitectureService;
  Lsp, LaterLsp: TLspArchitecture;
  Folder, Target: string;
  Arguments: TJSONArray;
  Answer: TJSONObject;
  Index: ISymbolIndex;
begin
  Enabled := True;
  Service := NewService(NewIndex);
  Lsp := NewLsp(Service);
  // Später: App.Data braucht App.Main, ein neuer Zyklus.
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('App.Main', ['App.Data'], nil));
  Index.AddUnit(UsesUnit('App.Data', nil, ['App.Main']));
  Later := NewService(Index);
  LaterLsp := NewLsp(Later);
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-vergleich-' + IntToStr(Random(1000000)));
  try
    Target := TPath.Combine(Folder, 'stand.json');
    Arguments := TJSONArray.Create;
    try
      Arguments.Add('');
      Arguments.Add(Target);
      Lsp.SaveReport(Arguments).Free;
    finally
      Arguments.Free;
    end;
    Assert.Contains(TFile.ReadAllText(Target, TEncoding.UTF8), '"format": 2');
    Answer := Ask(LaterLsp, '{"compareWith": ' + JsonPath(Target) + '}');
    try
      Assert.AreEqual(Target, Answer.GetValue<string>('baseline'));
      Assert.AreEqual(1, Answer.GetValue<TJSONObject>('comparison').GetValue<TJSONArray>('newCycles').Count);
      Assert.AreEqual('newCycle', Answer.GetValue<TJSONObject>('comparison').GetValue<TJSONArray>('failed')
        .Items[0].Value);
      Assert.IsNotNull(Answer.GetValue('data'));
    finally
      Answer.Free;
    end;
    Answer := Ask(LaterLsp, '{"format": "text", "compareWith": ' + JsonPath(Target) + '}');
    try
      Assert.Contains(Answer.GetValue<string>('text'), 'Neue Zyklen: 1');
    finally
      Answer.Free;
    end;
    // architecture.baseline relativ zum Projekt; "compare": false schaltet ab.
    BaselineSetting := 'stand.json';
    ProjectRoot := Folder;
    Answer := Ask(LaterLsp, '{"format": "markdown"}');
    try
      Assert.Contains(Answer.GetValue<string>('text'), '## Vergleich');
    finally
      Answer.Free;
    end;
    Answer := Ask(LaterLsp, '{"compare": false}');
    try
      Assert.IsNull(Answer.GetValue('comparison'));
    finally
      Answer.Free;
    end;
    Target := TPath.Combine(Folder, 'bericht.md');
    Arguments := TJSONArray.Create;
    try
      Arguments.Add('');
      Arguments.Add(Target);
      LaterLsp.SaveReport(Arguments).Free;
    finally
      Arguments.Free;
    end;
    Assert.Contains(TFile.ReadAllText(Target, TEncoding.UTF8), '### Neue Zyklen (1)');
    // Fehlender Stand: Meldung, die Übersicht kommt trotzdem.
    BaselineSetting := 'fehlt.json';
    Answer := Ask(LaterLsp, '{}');
    try
      Assert.Contains(Answer.GetValue<string>('comparisonError'), 'nicht gefunden');
      Assert.IsNotNull(Answer.GetValue('data'));
      Assert.IsNull(Answer.GetValue('comparison'));
    finally
      Answer.Free;
    end;
  finally
    BaselineSetting := '';
    ProjectRoot := 'C:\Projekt';
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
    LaterLsp.Free;
    Later.Free;
    Lsp.Free;
    Service.Free;
  end;
end;

function ResolutionIn(AAnswer: TJSONObject): Double;
begin
  Result := AAnswer.GetValue<TJSONObject>('data').GetValue<TJSONObject>('grouping').GetValue<Double>('resolution');
end;

procedure TLspArchitectureTests.ResolutionOverridesSettingForOneCall;
var
  mService: TArchitectureService;
  mLsp: TLspArchitecture;
  mAnswer: TJSONObject;
  mValue: Double;
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
    mAnswer := Ask(mLsp, '{}');
    try
      mValue := ResolutionIn(mAnswer);
      Assert.AreEqual(Double(1.5), mValue, 1E-9, 'Einstellung');
    finally
      mAnswer.Free;
    end;
    mAnswer := Ask(mLsp, '{"resolution": 2}');
    try
      mValue := ResolutionIn(mAnswer);
      Assert.AreEqual(Double(2), mValue, 1E-9, 'Anfrage');
    finally
      mAnswer.Free;
    end;
    // Die Einstellung bleibt; ein anderer Wert rechnet neu.
    mAnswer := Ask(mLsp, '{}');
    try
      mValue := ResolutionIn(mAnswer);
      Assert.AreEqual(Double(1.5), mValue, 1E-9, 'wieder die Einstellung');
    finally
      mAnswer.Free;
    end;
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
      TDirectory.Delete(mFolder, True);
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
