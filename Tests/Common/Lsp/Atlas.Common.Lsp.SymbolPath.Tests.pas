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
  cAFile = 'C:\P\uA.pas';
  cBFile = 'C:\P\uB.pas';
  cCFile = 'C:\P\uC.pas';
  cAText = 'unit uA;'#10'interface'#10'uses uB;'#10'implementation'#10'end.';
  cBText = 'unit uB;'#10'interface'#10'implementation'#10'uses uC;'#10'end.';
  cCText = 'unit uC;'#10'interface'#10'implementation'#10'end.';

function TextOf(const AFileName: string; out AText_: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cAFile) then
  begin
    AText_ := cAText;
  end
  else if SameText(AFileName, cBFile) then
  begin
    AText_ := cBText;
  end
  else if SameText(AFileName, cCFile) then
  begin
    AText_ := cCText;
  end
  else
  begin
    Result := False;
  end;
end;

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cAText, cAFile, nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cBText, cBFile, nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cCText, cCFile, nil));
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
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArgs := TJSONArray.Create;
  try
    mArgs.Add(TDocumentUris.FromPath(cAFile));
    mArgs.AddElement(TJSONObject.ParseJSONValue(AOptions));
    mAnswer := AService.Execute(mArgs);
    try
      Result := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

function ParamsOf(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

{ TLspSymbolPathTests }

procedure TLspSymbolPathTests.ReadsRequest;
var
  mParams: TJSONObject;
  mRequest: TSymbolPathRequest;
begin
  mParams := ParamsOf('{"from":"uA","to":"uC","via":["uses","library"],"maxSteps":3,"all":true}');
  try
    mRequest := TLspSymbolPath.ReadRequest(mParams);
    Assert.AreEqual('uA', mRequest.From);
    Assert.AreEqual('uC', mRequest.To_);
    Assert.AreEqual<TSymbolPathEdgeKinds>([TSymbolPathEdgeKind.Uses_], mRequest.Via);
    Assert.IsTrue(mRequest.ThroughLibrary);
    Assert.AreEqual(3, mRequest.MaxSteps);
    Assert.IsTrue(mRequest.All);
  finally
    mParams.Free;
  end;
  // Ohne via: alle Kantenarten, Bibliothek kein Durchgang, Vorgabe 8 Schritte.
  mParams := ParamsOf('{"from":"uA","to":"uC"}');
  try
    mRequest := TLspSymbolPath.ReadRequest(mParams);
    Assert.AreEqual<TSymbolPathEdgeKinds>(cAllSymbolPathEdges, mRequest.Via);
    Assert.IsFalse(mRequest.ThroughLibrary);
    Assert.AreEqual(TSymbolPathRequest.cDefaultSteps, mRequest.MaxSteps);
    Assert.IsFalse(mRequest.All);
  finally
    mParams.Free;
  end;
end;

procedure TLspSymbolPathTests.RejectsInvalidRequest;
const
  cInvalid: array[0..3] of string = ('{"from":"uA"}', '{"from":"uA","to":"uC","via":["foo"]}',
    '{"from":"uA","to":"uC","maxSteps":0}', '{"from":"uA","to":"uC","maxSteps":17}');
var
  mItem: string;
  mParams: TJSONObject;
begin
  for mItem in cInvalid do
  begin
    mParams := ParamsOf(mItem);
    try
      Assert.WillRaise(
        procedure
        begin
          TLspSymbolPath.ReadRequest(mParams);
        end, EJsonRpcError, mItem);
    finally
      mParams.Free;
    end;
  end;
end;

procedure TLspSymbolPathTests.FindsUsesPath;
var
  mService: TLspSymbolPath;
  mText: string;
begin
  mService := NewService(NewIndex, '{}', True);
  try
    mText := Run(mService, '{"from":"uA","to":"uC"}');
    Assert.Contains(mText, '"enabled":true');
    Assert.Contains(mText, '"status":"found"');
    Assert.Contains(mText, '"uses"');
    Assert.Contains(mText, '"implementation":true');
  finally
    mService.Free;
  end;
end;

procedure TLspSymbolPathTests.DisabledSettingAnswersWithoutSearch;
var
  mService: TLspSymbolPath;
begin
  mService := NewService(NewIndex, '{"navigation": {"symbolPath": false}}', True);
  try
    // Ohne Suche werden auch ungültige Argumente nicht geprüft.
    Assert.AreEqual('{"enabled":false}', Run(mService, '{}'));
  finally
    mService.Free;
  end;
end;

procedure TLspSymbolPathTests.NoProjectIsRejected;
var
  mService: TLspSymbolPath;
begin
  mService := NewService(NewIndex, '{}', False);
  try
    Assert.WillRaise(
      procedure
      begin
        Run(mService, '{"from":"uA","to":"uC"}');
      end, EJsonRpcError);
  finally
    mService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSymbolPathTests);

end.
