unit Atlas.Common.Lsp.TestFromDebug.Tests;

// Tests für den Befehl atlas.server.testFromDebugStop (#1873): "describe"
// nennt Methode, Parameter, Felder, Literale und einen Namen; "create" liefert
// das Edit in die vorhandene Testunit bzw. legt sie an.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.TestFromDebug;

type
  [TestFixture]
  TLspTestFromDebugTests = class
  private
    FStore: IDocumentStore;
    FFiles: TDictionary<string, string>;
    FUnits: TDictionary<string, string>;
    FTestUnits: TLspTestUnits;
    FFromDebug: TLspTestFromDebug;
    function Context: TTestUnitContext;
    function Run(ALine: Integer; const ARequest: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DescribeNamesValuesAndLiterals;
    [Test]
    procedure CreateAddsToExistingTestUnit;
    [Test]
    procedure CreateWithoutTestUnitCreatesIt;
    [Test]
    procedure NoMethodGivesReason;
    [Test]
    procedure ReadRequestDefaults;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Editing.TestDrafts,
  Atlas.Common.Editing.TestFromDebug;

const
  cGewichtFile = 'C:\P\Quelle\Gewichte.pas';
  cTestFile = 'C:\P\Tests\Gewichte.Tests.pas';
  cTestsDpr = 'C:\P\Tests\Tests.dpr';
  cTestsDproj = 'C:\P\Tests\Tests.dproj';
  cGewichtText =
    'unit Gewichte;'#10 +                                    // 0
    'interface'#10 +                                         // 1
    'type'#10 +                                              // 2
    '  TGewicht = class'#10 +                                // 3
    '  public'#10 +                                          // 4
    '    Genau: Boolean;'#10 +                               // 5
    '    function Parse(const AText: string): Double;'#10 +  // 6
    '  end;'#10 +                                            // 7
    'implementation'#10 +                                    // 8
    'function TGewicht.Parse(const AText: string): Double;'#10 + // 9
    'begin'#10 +                                             // 10
    '  Result := 0;'#10 +                                    // 11
    'end;'#10 +                                              // 12
    'end.';
  cDprText =
    'program Tests;'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'begin'#13#10 +
    'end.';
  cDprojText =
    '<Project>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="Tests.dpr"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>';
  cTestText =
    'unit Gewichte.Tests;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'type'#13#10 +
    '  [TestFixture]'#13#10 +
    '  TGewichtTests = class'#13#10 +
    '  public'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.'#13#10;
  cRaisesRequest = '{"mode": "create", "kind": "raises", "exceptionClass": "EConvertError", ' +
    '"parameters": [{"name": "AText", "text": "''12,5 kg''"}], "fields": [{"name": "Genau", "text": "True"}], ' +
    '"stoppedAt": "2026-11-13 14:05"}';

procedure TLspTestFromDebugTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FFiles := TDictionary<string, string>.Create;
  FUnits := TDictionary<string, string>.Create;
  FFiles.Add(cTestsDpr, cDprText);
  FFiles.Add(cTestsDproj, cDprojText);
  FUnits.Add('gewichte', cGewichtFile);
  FStore.Open(TDocumentUris.FromPath(cGewichtFile), 'pascal', 1, cGewichtText);
  FTestUnits := TLspTestUnits.Create(FStore,
    function(const AUri: string; out AContext: TTestUnitContext): Boolean
    begin
      AContext := Context;
      Result := True;
    end);
  FFromDebug := TLspTestFromDebug.Create(FTestUnits);
end;

procedure TLspTestFromDebugTests.TearDown;
begin
  FFromDebug.Free;
  FTestUnits.Free;
  FUnits.Free;
  FFiles.Free;
  FStore := nil;
end;

function TLspTestFromDebugTests.Context: TTestUnitContext;
var
  mFiles, mUnits: TDictionary<string, string>;
begin
  mFiles := FFiles;
  mUnits := FUnits;
  Result := Default(TTestUnitContext);
  Result.Settings := TTestUnitSettings.Default;
  Result.Root := 'C:\P';
  Result.TestProgram := cTestsDpr;
  Result.ReadText :=
    function(const AFileName: string): string
    begin
      if not mFiles.TryGetValue(AFileName, Result) then
      begin
        Result := '';
      end;
    end;
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := mFiles.ContainsKey(AFileName);
    end;
  Result.FindUnit :=
    function(const AUnitName: string): string
    begin
      if not mUnits.TryGetValue(LowerCase(AUnitName), Result) then
      begin
        Result := '';
      end;
    end;
end;

/// <summary>Befehl an ALine mit der Anfrage ARequest (JSON); Antwort als JSON-Text.</summary>
function TLspTestFromDebugTests.Run(ALine: Integer; const ARequest: string): string;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TDocumentUris.FromPath(cGewichtFile));
    mArguments.Add(ALine);
    mArguments.AddElement(TJSONObject.ParseJSONValue(ARequest));
    mAnswer := FFromDebug.Execute(mArguments);
    try
      Result := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

procedure TLspTestFromDebugTests.DescribeNamesValuesAndLiterals;
var
  mText: string;
begin
  mText := Run(11, '{"mode": "describe", "parameters": [{"name": "AText", "text": "''12,5 kg''"}], ' +
    '"fields": [{"name": "Genau", "text": "$1"}]}');
  Assert.IsTrue(ContainsStr(mText, '"target":"TGewicht.Parse"'), mText);
  Assert.IsTrue(ContainsStr(mText, '"resultType":"Double"'), mText);
  Assert.IsTrue(ContainsStr(mText, '"name":"AText","type":"string"'), mText);
  Assert.IsTrue(ContainsStr(mText, '"todo":false,"literal":"''12,5 kg''"'), mText);
  Assert.IsTrue(ContainsStr(mText, '"name":"Genau","type":"Boolean","modifier":"","accessible":true,"todo":true'),
    mText);
  Assert.IsTrue(ContainsStr(mText, '"testUnit":"Gewichte.Tests"'), mText);
  Assert.IsTrue(ContainsStr(mText, '"testUnitExists":false'), mText);
  Assert.IsTrue(ContainsStr(mText, '12_5Kg"'), 'Name: ' + mText);
end;

procedure TLspTestFromDebugTests.CreateAddsToExistingTestUnit;
var
  mText: string;
begin
  FFiles.Add(cTestFile, cTestText);
  FUnits.Add('gewichte.tests', cTestFile);
  mText := Run(6, cRaisesRequest);
  Assert.IsTrue(ContainsStr(mText, '"documentChanges"'), mText);
  Assert.IsTrue(ContainsStr(mText, 'Assert.WillRaise('), mText);
  Assert.IsTrue(ContainsStr(mText, 'EConvertError);'), mText);
  Assert.IsTrue(ContainsStr(mText, 'Genau := True;'), mText);
  Assert.IsTrue(ContainsStr(mText, '"fixture":"TGewichtTests"'), mText);
  Assert.IsTrue(ContainsStr(mText, 'Gewichte.Tests.pas"'), 'uri: ' + mText);
  Assert.IsTrue(ContainsStr(mText, 'ConvertError"'), 'testName: ' + mText);
  Assert.IsFalse(ContainsStr(mText, '"reason"'), mText);
end;

procedure TLspTestFromDebugTests.CreateWithoutTestUnitCreatesIt;
var
  mText: string;
begin
  mText := Run(6, cRaisesRequest);
  Assert.IsTrue(ContainsStr(mText, '"kind":"create"'), 'neue Datei: ' + mText);
  Assert.IsTrue(ContainsStr(mText, 'Assert.WillRaise('), mText);
  Assert.IsTrue(ContainsStr(mText, 'Tests.dpr'), 'Testprojekt: ' + mText);
end;

procedure TLspTestFromDebugTests.NoMethodGivesReason;
var
  mText: string;
begin
  mText := Run(2, '{"mode": "describe"}');
  Assert.IsTrue(ContainsStr(mText, '"reason"'), mText);
  Assert.IsFalse(ContainsStr(mText, '"target"'), mText);
end;

procedure TLspTestFromDebugTests.ReadRequestDefaults;
var
  mJson: TJSONObject;
  mRequest: TDebugStopRequest;
begin
  mRequest := TLspTestFromDebug.ReadRequest(nil);
  Assert.AreEqual<TTestDraftKind>(TTestDraftKind.Works, mRequest.Kind);
  Assert.AreEqual(TTestFromDebug.cDefaultMaxArray, mRequest.MaxArray);
  mJson := TJSONObject.ParseJSONValue('{"kind": "raises", "maxArray": 5, "testName": "X"}') as TJSONObject;
  try
    mRequest := TLspTestFromDebug.ReadRequest(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual<TTestDraftKind>(TTestDraftKind.Raises, mRequest.Kind);
  Assert.AreEqual(5, mRequest.MaxArray);
  Assert.AreEqual('X', mRequest.TestName);
  mRequest := Default(TDebugStopRequest);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTestFromDebugTests);

end.
