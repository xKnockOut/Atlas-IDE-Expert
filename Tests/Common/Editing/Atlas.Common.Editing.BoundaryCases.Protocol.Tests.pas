unit Atlas.Common.Editing.BoundaryCases.Protocol.Tests;

// Befehl atlas.server.boundaryCases (#2173): Fälle als JSON mit Werten aller Parameter, nil nicht als [TestCase],
// Höchstzahl, null ohne Routine, Fehler ohne URI.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBoundaryCasesProtocolTests = class
  public
    [Test]
    procedure CasesAsJson;
    [Test]
    procedure MaxTruncates;
    [Test]
    procedure NullOutsideRoutine;
    [Test]
    procedure InvalidArguments;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Editing.BoundaryCases.Protocol;

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
    Result := TBoundaryCasesProtocol.Execute(mArguments,
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

{ TBoundaryCasesProtocolTests }

procedure TBoundaryCasesProtocolTests.CasesAsJson;
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

procedure TBoundaryCasesProtocolTests.MaxTruncates;
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

procedure TBoundaryCasesProtocolTests.NullOutsideRoutine;
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

procedure TBoundaryCasesProtocolTests.InvalidArguments;
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

end.
