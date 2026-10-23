unit Atlas.Common.Lsp.Architecture.Tests;

// Tests der Anfrage atlas/architecture und des Befehls
// atlas.architecture.saveReport (#1118).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspArchitectureTests = class
  public
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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
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
      ARequest := TArchitectureRequest.FromSettings(ASettings);
      ARequest.Title := 'Beispiel';
      LastScope := AScope;
      Result := True;
    end);
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

initialization
  TDUnitX.RegisterTestFixture(TLspArchitectureTests);

end.
