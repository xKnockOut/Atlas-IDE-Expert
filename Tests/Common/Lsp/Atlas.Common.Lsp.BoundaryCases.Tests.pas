unit Atlas.Common.Lsp.BoundaryCases.Tests;

// Befehl atlas.server.boundaryCases und Markdown für MCP (#2173): Fälle als JSON mit Werten aller Parameter,
// nil nicht als [TestCase], Höchstzahl, null ohne Routine, Routine nach Namen, Fehler ohne URI.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspBoundaryCasesTests = class
  public
    [Test]
    procedure CasesAsJson;
    [Test]
    procedure MaxTruncates;
    [Test]
    procedure NullOutsideRoutine;
    [Test]
    procedure InvalidArguments;
    [Test]
    procedure RoutineByName;
    [Test]
    procedure MarkdownTable;
    [Test]
    procedure ReportForMcp;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.BoundaryCases,
  Atlas.Common.Lsp.BoundaryCases;

const
  cUri = 'file:///C:/P/Rabatt.pas';
  cBreak = #13#10;
  cText = 'unit Rabatt;' + cBreak + 'interface' + cBreak + 'implementation' + cBreak +
    'function Rabatt(ABetrag: Integer; AKunde: TObject): Integer;' + cBreak + 'begin' + cBreak +
    '  Result := 0;' + cBreak + '  if (ABetrag >= 100) and (AKunde <> nil) then' + cBreak + '    Result := 5;' +
    cBreak + 'end;' + cBreak + 'end.';

function Run(const AArguments: string): TJSONValue;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    Result := TLspBoundaryCases.Execute(mArguments,
      function(const AUri: string; out AText: string): Boolean
      begin
        AText := cText;
        Result := AUri = cUri;
      end);
  finally
    mArguments.Free;
  end;
end;

function Entry(AObject: TJSONObject; const AName: string; AIndex: Integer): TJSONObject;
begin
  Result := (AObject.GetValue(AName) as TJSONArray).Items[AIndex] as TJSONObject;
end;

function Count(AObject: TJSONObject; const AName: string): Integer;
begin
  Result := (AObject.GetValue(AName) as TJSONArray).Count;
end;

{ TLspBoundaryCasesTests }

procedure TLspBoundaryCasesTests.CasesAsJson;
var
  mResult: TJSONValue;
  mObject, mCase: TJSONObject;
  mValues: TJSONArray;
begin
  mResult := Run('["' + cUri + '",7]');
  try
    mObject := mResult as TJSONObject;
    Assert.AreEqual('Rabatt', mObject.GetValue<string>('routine'));
    Assert.AreEqual('Integer', mObject.GetValue<string>('resultType'));
    Assert.AreEqual(3, mObject.GetValue<Integer>('line'));
    Assert.AreEqual(2, Count(mObject, 'parameters'));
    Assert.AreEqual('ordinal', Entry(mObject, 'parameters', 0).GetValue<string>('kind'));
    Assert.AreEqual('reference', Entry(mObject, 'parameters', 1).GetValue<string>('kind'));
    // 99, 100, 101 für ABetrag, dann nil für AKunde.
    Assert.AreEqual(4, Count(mObject, 'cases'));
    mCase := Entry(mObject, 'cases', 0);
    Assert.AreEqual('99', mCase.GetValue<string>('value'));
    Assert.AreEqual(6, mCase.GetValue<Integer>('line'));
    Assert.IsTrue(mCase.GetValue<Boolean>('testCase'));
    mValues := mCase.GetValue('values') as TJSONArray;
    Assert.AreEqual(2, mValues.Count);
    Assert.AreEqual('99', mValues.Items[0].Value);
    mCase := Entry(mObject, 'cases', 3);
    Assert.AreEqual(1, mCase.GetValue<Integer>('parameter'));
    Assert.AreEqual('nil', mCase.GetValue<string>('value'));
    Assert.IsFalse(mCase.GetValue<Boolean>('testCase'), 'nil passt in kein [TestCase]');
    Assert.IsFalse(mObject.GetValue<Boolean>('truncated'));
  finally
    mResult.Free;
  end;
end;

procedure TLspBoundaryCasesTests.MaxTruncates;
var
  mResult: TJSONValue;
begin
  mResult := Run('["' + cUri + '",5,2]');
  try
    Assert.AreEqual(2, Count(mResult as TJSONObject, 'cases'));
    Assert.IsTrue((mResult as TJSONObject).GetValue<Boolean>('truncated'));
  finally
    mResult.Free;
  end;
  // 0 gilt als 1 (Untergrenze).
  mResult := Run('["' + cUri + '",5,0]');
  try
    Assert.AreEqual(1, Count(mResult as TJSONObject, 'cases'));
  finally
    mResult.Free;
  end;
end;

procedure TLspBoundaryCasesTests.NullOutsideRoutine;
var
  mResult: TJSONValue;
begin
  mResult := Run('["' + cUri + '",1]');
  try
    Assert.IsTrue(mResult is TJSONNull);
  finally
    mResult.Free;
  end;
end;

procedure TLspBoundaryCasesTests.InvalidArguments;
begin
  Assert.WillRaise(
    procedure
    begin
      Run('["' + cUri + '"]').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      Run('["file:///C:/P/Andere.pas",5]').Free;
    end, EJsonRpcError);
end;

procedure TLspBoundaryCasesTests.RoutineByName;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    Assert.IsNotNull(TLspBoundaryCases.RoutineOf(mTree, -1, 'rabatt'));
    Assert.IsNull(TLspBoundaryCases.RoutineOf(mTree, -1, 'Fehlt'));
    Assert.IsNull(TLspBoundaryCases.RoutineOf(mTree, -1, ''));
  finally
    mTree.Free;
  end;
end;

procedure TLspBoundaryCasesTests.MarkdownTable;
var
  mTree: TSyntaxTree;
  mRoutine: TSyntaxNode;
  mText: string;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mRoutine := TLspBoundaryCases.RoutineOf(mTree, 6, '');
    mText := TLspBoundaryCases.ToMarkdown('Rabatt.pas', mRoutine.StartPos.Line,
      TBoundaryCases.Find(mTree, mRoutine, 20));
  finally
    mTree.Free;
  end;
  Assert.Contains(mText, 'Rabatt.pas');
  Assert.Contains(mText, 'ABetrag: Integer (0)');
  Assert.Contains(mText, '| ABetrag | `100` |');
  Assert.Contains(mText, '| 7 | `100, nil` |');
  Assert.Contains(mText, '[TestCase]');
end;

procedure TLspBoundaryCasesTests.ReportForMcp;
var
  mReport: string;
  mValue: TJSONValue;
  mRequest: TLspBoundaryRequest;
begin
  mRequest := Default(TLspBoundaryRequest);
  mRequest.FileName := 'Rabatt.pas';
  mRequest.Line := -1;
  mRequest.Routine := 'Rabatt';
  mRequest.Json := True;
  Assert.IsTrue(TLspBoundaryCases.Report(cText, mRequest, mReport));
  mValue := TJSONObject.ParseJSONValue(mReport);
  try
    Assert.AreEqual(4, Count(mValue as TJSONObject, 'cases'));
    Assert.AreEqual('Rabatt.pas', (mValue as TJSONObject).GetValue<string>('uri'));
  finally
    mValue.Free;
  end;
  mRequest.Line := 6;
  mRequest.Routine := '';
  mRequest.Max := 1;
  mRequest.Json := False;
  Assert.IsTrue(TLspBoundaryCases.Report(cText, mRequest, mReport));
  Assert.Contains(mReport, 'maxCases');
  mRequest.Line := 0;
  Assert.IsFalse(TLspBoundaryCases.Report(cText, mRequest, mReport));
  Assert.AreEqual(TBoundaryCases.cDefaultMax, TLspBoundaryCases.MaxCases(0));
  Assert.AreEqual(TLspBoundaryCases.cMaxMax, TLspBoundaryCases.MaxCases(1000));
  Assert.AreEqual(TLspBoundaryCases.cMinMax, TLspBoundaryCases.MaxCases(-5));
end;

end.
