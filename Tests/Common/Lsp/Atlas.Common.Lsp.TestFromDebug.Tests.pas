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
  GewichtFile = 'C:\P\Quelle\Gewichte.pas';
  TestFile = 'C:\P\Tests\Gewichte.Tests.pas';
  TestsDpr = 'C:\P\Tests\Tests.dpr';
  TestsDproj = 'C:\P\Tests\Tests.dproj';
  GewichtText =
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
  DprText =
    'program Tests;'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'begin'#13#10 +
    'end.';
  DprojText =
    '<Project>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="Tests.dpr"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>';
  TestText =
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
  RaisesRequest = '{"mode": "create", "kind": "raises", "exceptionClass": "EConvertError", ' +
    '"parameters": [{"name": "AText", "text": "''12,5 kg''"}], "fields": [{"name": "Genau", "text": "True"}], ' +
    '"stoppedAt": "2026-11-13 14:05"}';

procedure TLspTestFromDebugTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FFiles := TDictionary<string, string>.Create;
  FUnits := TDictionary<string, string>.Create;
  FFiles.Add(TestsDpr, DprText);
  FFiles.Add(TestsDproj, DprojText);
  FUnits.Add('gewichte', GewichtFile);
  FStore.Open(TDocumentUris.FromPath(GewichtFile), 'pascal', 1, GewichtText);
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
  Files, Units: TDictionary<string, string>;
begin
  Files := FFiles;
  Units := FUnits;
  Result := Default(TTestUnitContext);
  Result.Settings := TTestUnitSettings.Default;
  Result.Root := 'C:\P';
  Result.TestProgram := TestsDpr;
  Result.ReadText :=
    function(const AFileName: string): string
    begin
      if not Files.TryGetValue(AFileName, Result) then
      begin
        Result := '';
      end;
    end;
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := Files.ContainsKey(AFileName);
    end;
  Result.FindUnit :=
    function(const AUnitName: string): string
    begin
      if not Units.TryGetValue(LowerCase(AUnitName), Result) then
      begin
        Result := '';
      end;
    end;
end;

/// <summary>Befehl an ALine mit der Anfrage ARequest (JSON); Antwort als JSON-Text.</summary>
function TLspTestFromDebugTests.Run(ALine: Integer; const ARequest: string): string;
var
  Arguments: TJSONArray;
  Answer: TJSONValue;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(TDocumentUris.FromPath(GewichtFile));
    Arguments.Add(ALine);
    Arguments.AddElement(TJSONObject.ParseJSONValue(ARequest));
    Answer := FFromDebug.Execute(Arguments);
    try
      Result := Answer.ToJSON;
    finally
      Answer.Free;
    end;
  finally
    Arguments.Free;
  end;
end;

procedure TLspTestFromDebugTests.DescribeNamesValuesAndLiterals;
var
  Text: string;
begin
  Text := Run(11, '{"mode": "describe", "parameters": [{"name": "AText", "text": "''12,5 kg''"}], ' +
    '"fields": [{"name": "Genau", "text": "$1"}]}');
  Assert.IsTrue(ContainsStr(Text, '"target":"TGewicht.Parse"'), Text);
  Assert.IsTrue(ContainsStr(Text, '"resultType":"Double"'), Text);
  Assert.IsTrue(ContainsStr(Text, '"name":"AText","type":"string"'), Text);
  Assert.IsTrue(ContainsStr(Text, '"todo":false,"literal":"''12,5 kg''"'), Text);
  Assert.IsTrue(ContainsStr(Text, '"name":"Genau","type":"Boolean","modifier":"","accessible":true,"todo":true'),
    Text);
  Assert.IsTrue(ContainsStr(Text, '"testUnit":"Gewichte.Tests"'), Text);
  Assert.IsTrue(ContainsStr(Text, '"testUnitExists":false'), Text);
  Assert.IsTrue(ContainsStr(Text, '12_5Kg"'), 'Name: ' + Text);
end;

procedure TLspTestFromDebugTests.CreateAddsToExistingTestUnit;
var
  Text: string;
begin
  FFiles.Add(TestFile, TestText);
  FUnits.Add('gewichte.tests', TestFile);
  Text := Run(6, RaisesRequest);
  Assert.IsTrue(ContainsStr(Text, '"documentChanges"'), Text);
  Assert.IsTrue(ContainsStr(Text, 'Assert.WillRaise('), Text);
  Assert.IsTrue(ContainsStr(Text, 'EConvertError);'), Text);
  Assert.IsTrue(ContainsStr(Text, 'Genau := True;'), Text);
  Assert.IsTrue(ContainsStr(Text, '"fixture":"TGewichtTests"'), Text);
  Assert.IsTrue(ContainsStr(Text, 'Gewichte.Tests.pas"'), 'uri: ' + Text);
  Assert.IsTrue(ContainsStr(Text, 'ConvertError"'), 'testName: ' + Text);
  Assert.IsFalse(ContainsStr(Text, '"reason"'), Text);
end;

procedure TLspTestFromDebugTests.CreateWithoutTestUnitCreatesIt;
var
  Text: string;
begin
  Text := Run(6, RaisesRequest);
  Assert.IsTrue(ContainsStr(Text, '"kind":"create"'), 'neue Datei: ' + Text);
  Assert.IsTrue(ContainsStr(Text, 'Assert.WillRaise('), Text);
  Assert.IsTrue(ContainsStr(Text, 'Tests.dpr'), 'Testprojekt: ' + Text);
end;

procedure TLspTestFromDebugTests.NoMethodGivesReason;
var
  Text: string;
begin
  Text := Run(2, '{"mode": "describe"}');
  Assert.IsTrue(ContainsStr(Text, '"reason"'), Text);
  Assert.IsFalse(ContainsStr(Text, '"target"'), Text);
end;

procedure TLspTestFromDebugTests.ReadRequestDefaults;
var
  Json: TJSONObject;
  Request: TDebugStopRequest;
begin
  Request := TLspTestFromDebug.ReadRequest(nil);
  Assert.IsTrue(Request.Kind = TTestDraftKind.Works);
  Assert.AreEqual(TTestFromDebug.cDefaultMaxArray, Request.MaxArray);
  Json := TJSONObject.ParseJSONValue('{"kind": "raises", "maxArray": 5, "testName": "X"}') as TJSONObject;
  try
    Request := TLspTestFromDebug.ReadRequest(Json);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Request.Kind = TTestDraftKind.Raises);
  Assert.AreEqual(5, Request.MaxArray);
  Assert.AreEqual('X', Request.TestName);
  Request := Default(TDebugStopRequest);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTestFromDebugTests);

end.
