unit Atlas.Common.Lsp.SymbolPath.Tests;

// Tests von atlas/symbolPath bzw. atlas.symbolPath (#1117): Argumente lesen
// und ablehnen, Weg über den eigenen Uses-Graphen, Einstellung
// navigation.symbolPath = false, fehlendes Projekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspSymbolPathTests = class
  public
    [Test]
    procedure ReadsRequest;
    [Test]
    procedure RejectsInvalidRequest;
    [Test]
    procedure FindsUsesPath;
    [Test]
    procedure DisabledSettingAnswersWithoutSearch;
    [Test]
    procedure NoProjectIsRejected;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Architecture.SymbolPath,
  Atlas.Common.Lsp.SymbolPath;

const
  AFile = 'C:\P\uA.pas';
  BFile = 'C:\P\uB.pas';
  CFile = 'C:\P\uC.pas';
  AText = 'unit uA;'#10'interface'#10'uses uB;'#10'implementation'#10'end.';
  BText = 'unit uB;'#10'interface'#10'implementation'#10'uses uC;'#10'end.';
  CText = 'unit uC;'#10'interface'#10'implementation'#10'end.';

function TextOf(const AFileName: string; out AText_: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, AFile) then
    AText_ := AText
  else if SameText(AFileName, BFile) then
    AText_ := BText
  else if SameText(AFileName, CFile) then
    AText_ := CText
  else
    Result := False;
end;

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(AText, AFile, nil));
  Result.AddUnit(TIndexExtractor.ExtractText(BText, BFile, nil));
  Result.AddUnit(TIndexExtractor.ExtractText(CText, CFile, nil));
end;

function NewService(const AIndex: ISymbolIndex; const AConfig: string; AProject: Boolean): TLspSymbolPath;
begin
  Result := TLspSymbolPath.Create(AIndex,
    function(const AFileName: string; out AText_: string): Boolean
    begin
      Result := TextOf(AFileName, AText_);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end,
    function(const AFileName: string; out ASettings: TServerSettings; out ANamespaces: TArray<string>): Boolean
    var
      Issues: TArray<TConfigurationIssue>;
    begin
      ASettings := TConfigurationParser.Parse(AConfig, Issues);
      ANamespaces := nil;
      Result := AProject;
    end);
end;

function Run(AService: TLspSymbolPath; const AOptions: string): string;
var
  Args: TJSONArray;
  Answer: TJSONValue;
begin
  Args := TJSONArray.Create;
  try
    Args.Add(TDocumentUris.FromPath(AFile));
    Args.AddElement(TJSONObject.ParseJSONValue(AOptions));
    Answer := AService.Execute(Args);
    try
      Result := Answer.ToJSON;
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

function ParamsOf(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

{ TLspSymbolPathTests }

procedure TLspSymbolPathTests.ReadsRequest;
var
  Params: TJSONObject;
  Request: TSymbolPathRequest;
begin
  Params := ParamsOf('{"from":"uA","to":"uC","via":["uses","library"],"maxSteps":3,"all":true}');
  try
    Request := TLspSymbolPath.ReadRequest(Params);
    Assert.AreEqual('uA', Request.From);
    Assert.AreEqual('uC', Request.To_);
    Assert.IsTrue(Request.Via = [TSymbolPathEdgeKind.Uses_]);
    Assert.IsTrue(Request.ThroughLibrary);
    Assert.AreEqual(3, Request.MaxSteps);
    Assert.IsTrue(Request.All);
  finally
    Params.Free;
  end;
  // Ohne via: alle Kantenarten, Bibliothek kein Durchgang, Vorgabe 8 Schritte.
  Params := ParamsOf('{"from":"uA","to":"uC"}');
  try
    Request := TLspSymbolPath.ReadRequest(Params);
    Assert.IsTrue(Request.Via = AllSymbolPathEdges);
    Assert.IsFalse(Request.ThroughLibrary);
    Assert.AreEqual(TSymbolPathRequest.DefaultSteps, Request.MaxSteps);
    Assert.IsFalse(Request.All);
  finally
    Params.Free;
  end;
end;

procedure TLspSymbolPathTests.RejectsInvalidRequest;
const
  Invalid: array[0..3] of string = ('{"from":"uA"}', '{"from":"uA","to":"uC","via":["foo"]}',
    '{"from":"uA","to":"uC","maxSteps":0}', '{"from":"uA","to":"uC","maxSteps":17}');
var
  Item: string;
  Params: TJSONObject;
begin
  for Item in Invalid do
  begin
    Params := ParamsOf(Item);
    try
      Assert.WillRaise(
        procedure
        begin
          TLspSymbolPath.ReadRequest(Params);
        end, EJsonRpcError, Item);
    finally
      Params.Free;
    end;
  end;
end;

procedure TLspSymbolPathTests.FindsUsesPath;
var
  Service: TLspSymbolPath;
  Text: string;
begin
  Service := NewService(NewIndex, '{}', True);
  try
    Text := Run(Service, '{"from":"uA","to":"uC"}');
    Assert.Contains(Text, '"enabled":true');
    Assert.Contains(Text, '"status":"found"');
    Assert.Contains(Text, '"uses"');
    Assert.Contains(Text, '"implementation":true');
  finally
    Service.Free;
  end;
end;

procedure TLspSymbolPathTests.DisabledSettingAnswersWithoutSearch;
var
  Service: TLspSymbolPath;
begin
  Service := NewService(NewIndex, '{"navigation": {"symbolPath": false}}', True);
  try
    // Ohne Suche werden auch ungültige Argumente nicht geprüft.
    Assert.AreEqual('{"enabled":false}', Run(Service, '{}'));
  finally
    Service.Free;
  end;
end;

procedure TLspSymbolPathTests.NoProjectIsRejected;
var
  Service: TLspSymbolPath;
begin
  Service := NewService(NewIndex, '{}', False);
  try
    Assert.WillRaise(
      procedure
      begin
        Run(Service, '{"from":"uA","to":"uC"}');
      end, EJsonRpcError);
  finally
    Service.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSymbolPathTests);

end.
