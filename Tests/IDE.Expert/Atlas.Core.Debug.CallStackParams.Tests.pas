unit Atlas.Core.Debug.CallStackParams.Tests;

// Tests zu den Parametern im Fenster „Aufrufstapel“ (#843): Werte aus dem Rahmentext der IDE zerlegen, Namen und
// Typen des Servers zuordnen, Auswertung und lesbare Werte, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasCallStackParamsTests = class
  public
    [Test]
    procedure SplitsTopLevelCommasOnly;
    [Test]
    procedure NoParenthesesNoArguments;
    [Test]
    procedure NamesFromLldbHeader;
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure CombineMatchesCountOrSelf;
    [Test]
    procedure CombineKeepsValuesOnMismatch;
    [Test]
    procedure ExpressionTopFrameUsesName;
    [Test]
    procedure ExpressionOtherFrameCastsAddress;
    [Test]
    procedure ValueAndObjectTexts;
    [Test]
    procedure ListTextNamesValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStackParams;

function Param(const AName, ATypeName, ARaw: string): TAtlasCallStackParam;
begin
  Result := Default(TAtlasCallStackParam);
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.Raw := ARaw;
end;

function Declared(const ANames: array of string): TAtlasCallStackDeclaredList;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    Result[mIndex] := Default(TAtlasCallStackDeclared);
    Result[mIndex].Name := ANames[mIndex];
    Result[mIndex].TypeName := 'T' + ANames[mIndex];
  end;
end;

procedure TAtlasCallStackParamsTests.SplitsTopLevelCommasOnly;
var
  mArgs: TArray<string>;
begin
  mArgs := TAtlasCallStackParams.SplitArguments('Unit1.TForm1.Import(5,''a, b (c)'',(X: 1; Y: 2),[1, 2],$2A3F2C0)');
  Assert.AreEqual(5, Integer(Length(mArgs)));
  Assert.AreEqual('5', mArgs[0]);
  Assert.AreEqual('''a, b (c)''', mArgs[1]);
  Assert.AreEqual('(X: 1; Y: 2)', mArgs[2]);
  Assert.AreEqual('[1, 2]', mArgs[3]);
  Assert.AreEqual('$2A3F2C0', mArgs[4]);
end;

procedure TAtlasCallStackParamsTests.NoParenthesesNoArguments;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasCallStackParams.SplitArguments(':7714C3E2 KERNELBASE.RaiseException + 0x62'))));
  Assert.AreEqual(0, Integer(Length(TAtlasCallStackParams.SplitArguments('Unit1.Run()'))));
end;

procedure TAtlasCallStackParamsTests.NamesFromLldbHeader;
var
  mParams: TAtlasCallStackParamList;
begin
  mParams := TAtlasCallStackParams.FromHeader('Unit1.TForm1.Button1Click(Self=$02A3F2C0, Sender=$02A40010)');
  Assert.AreEqual(2, Integer(Length(mParams)));
  Assert.AreEqual('Self', mParams[0].Name);
  Assert.AreEqual('$02A3F2C0', mParams[0].Raw);
  Assert.AreEqual('Sender', mParams[1].Name);
  // Ein Vergleich im Wert ist kein Name.
  mParams := TAtlasCallStackParams.FromHeader('Unit1.Run(''a=b'',5)');
  Assert.AreEqual('', mParams[0].Name);
  Assert.AreEqual('''a=b''', mParams[0].Raw);
end;

procedure TAtlasCallStackParamsTests.ReadsServerAnswer;
var
  mRoutine: string;
  mDeclared: TAtlasCallStackDeclaredList;
begin
  Assert.IsTrue(TAtlasCallStackParams.ReadAnswer('{"format":1,"routine":"TImport.Lies","parameters":' +
    '[{"name":"AName","type":"string","modifier":"const"},{"name":"AListe","type":"TObjectList<TKunde>"}]}',
    mRoutine, mDeclared));
  Assert.AreEqual('TImport.Lies', mRoutine);
  Assert.AreEqual(2, Integer(Length(mDeclared)));
  Assert.AreEqual('AListe', mDeclared[1].Name);
  Assert.AreEqual('TObjectList<TKunde>', mDeclared[1].TypeName);
  Assert.IsFalse(TAtlasCallStackParams.ReadAnswer('{"format":2}', mRoutine, mDeclared));
  Assert.IsFalse(TAtlasCallStackParams.ReadAnswer('', mRoutine, mDeclared));
  Assert.AreEqual('["file:///C:/P/Unit1.pas",41]', TAtlasCallStackParams.Arguments('file:///C:/P/Unit1.pas', 41));
end;

procedure TAtlasCallStackParamsTests.CombineMatchesCountOrSelf;
var
  mParams: TAtlasCallStackParamList;
begin
  mParams := TAtlasCallStackParams.FromHeader('Unit1.Import(5,''x'')');
  Assert.IsTrue(TAtlasCallStackParams.Combine(mParams, Declared(['Anzahl', 'Name']), False));
  Assert.AreEqual('Anzahl', mParams[0].Name);
  Assert.AreEqual('TName', mParams[1].TypeName);
  // Methode: vorn steht Self.
  mParams := TAtlasCallStackParams.FromHeader('Unit1.TForm1.Click($2A3F2C0,$2A40010)');
  Assert.IsTrue(TAtlasCallStackParams.Combine(mParams, Declared(['Sender']), True));
  Assert.AreEqual('Self', mParams[0].Name);
  Assert.AreEqual('Sender', mParams[1].Name);
end;

procedure TAtlasCallStackParamsTests.CombineKeepsValuesOnMismatch;
var
  mParams: TAtlasCallStackParamList;
begin
  mParams := TAtlasCallStackParams.FromHeader('Unit1.Import(5,''x'',7)');
  Assert.IsFalse(TAtlasCallStackParams.Combine(mParams, Declared(['Anzahl']), False));
  Assert.AreEqual('', mParams[0].Name);
  Assert.AreEqual('5', mParams[0].Raw);
  Assert.IsFalse(TAtlasCallStackParams.Combine(mParams, nil, True));
end;

procedure TAtlasCallStackParamsTests.ExpressionTopFrameUsesName;
var
  mParam: TAtlasCallStackParam;
begin
  mParam := Param('AListe', 'TObjectList<TKunde>', '$2A3F2C0');
  Assert.AreEqual('AListe', TAtlasCallStackParams.ExpressionFor(mParam, True));
  mParam.Done := True;
  Assert.AreEqual('', TAtlasCallStackParams.ExpressionFor(mParam, True));
  Assert.AreEqual('', TAtlasCallStackParams.ExpressionFor(Param('', 'Integer', '5'), True));
end;

procedure TAtlasCallStackParamsTests.ExpressionOtherFrameCastsAddress;
begin
  Assert.AreEqual('TKunde($2A3F2C0)',
    TAtlasCallStackParams.ExpressionFor(Param('AKunde', 'TKunde', '$2A3F2C0'), False));
  // Werte ohne Adresse zeigt der Rahmentext schon; ohne Typ keine Umwandlung.
  Assert.AreEqual('', TAtlasCallStackParams.ExpressionFor(Param('N', 'Integer', '5'), False));
  Assert.AreEqual('', TAtlasCallStackParams.ExpressionFor(Param('P', '', '$2A3F2C0'), False));
  Assert.AreEqual('', TAtlasCallStackParams.ExpressionFor(Param('A', 'array of Integer', '$2A3F2C0'), False));
  Assert.IsTrue(TAtlasCallStackParams.IsAddress('0x7ff6a1b2'));
  Assert.IsFalse(TAtlasCallStackParams.IsAddress('$'));
  Assert.IsFalse(TAtlasCallStackParams.IsAddress('nil'));
end;

procedure TAtlasCallStackParamsTests.ValueAndObjectTexts;
begin
  Assert.AreEqual('''Meier''', TAtlasCallStackParams.ValueText('Meier', True));
  Assert.AreEqual('''O''''Neil''', TAtlasCallStackParams.ValueText('O''Neil', True));
  Assert.AreEqual('''schon''', TAtlasCallStackParams.ValueText('''schon''', True));
  Assert.AreEqual('42', TAtlasCallStackParams.ValueText(' 42 ', False));
  Assert.AreEqual(Integer(TAtlasCallStackParams.cMaxValue),
    Integer(Length(TAtlasCallStackParams.ValueText(StringOfChar('x', 200), False))));
  Assert.AreEqual('TKunde ''Meier''', TAtlasCallStackParams.ObjectText('TKunde', '''Meier''', '$2A3F2C0'));
  Assert.AreEqual('TKunde ($2A3F2C0)', TAtlasCallStackParams.ObjectText('TKunde', '', '$2A3F2C0'));
  Assert.IsTrue(TAtlasCallStackParams.IsStringType('UnicodeString'));
  Assert.IsFalse(TAtlasCallStackParams.IsStringType('TStrings'));
  Assert.IsTrue(TAtlasCallStackParams.IsStructure('(FName: ''x''; FCount: 3)'));
  Assert.IsFalse(TAtlasCallStackParams.IsStructure('(1, 2)'));
end;

procedure TAtlasCallStackParamsTests.ListTextNamesValues;
var
  mParams: TAtlasCallStackParamList;
begin
  mParams := [Param('Anzahl', 'Integer', '5'), Param('', '', '''x''')];
  mParams[0].Value := '6';
  Assert.AreEqual('Anzahl = 6, ''x''', TAtlasCallStackParams.ListText(mParams));
end;

end.
