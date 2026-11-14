unit Atlas.Common.Semantics.Recursion.Tests;

// Tests der Rekursionsanalyse (#623): direkte Rekursion, Kette über zwei
// Methoden, Tiefe, Getter und Setter der eigenen Property, inherited und
// andere nicht verfolgte Aufrufe, Antwort von atlas.server.recursion und
// Laufzeit für eine Unit mit 5000 Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRecursionAnalysisTests = class
  public
    [Test]
    procedure DirectRecursion;
    [Test]
    procedure ChainOverTwoMethods;
    [Test]
    procedure DepthLimitsChain;
    [Test]
    procedure GetterReadsOwnProperty;
    [Test]
    procedure SetterWritesOwnProperty;
    [Test]
    procedure InheritedIsNoRecursion;
    [Test]
    procedure PointersShadowsAndOtherObjectsAreNotFollowed;
    [Test]
    procedure LocalRoutineCallsItself;
    [Test]
    procedure CommandJson;
    [Test]
    [Category('Benchmark')]
    procedure FiveThousandLinesUnderFiftyMilliseconds;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.Diagnostics,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.Recursion,
  Atlas.Common.Lsp.Recursion;

const
  cHeader =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class(TBase)'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    FCount: Integer;'#10 +
    '    function GetName: string;'#10 +
    '    procedure SetName(const AValue: string);'#10 +
    '    function GetCount: Integer;'#10 +
    '  public'#10 +
    '    procedure Speichern;'#10 +
    '    procedure Pruefen;'#10 +
    '    procedure Run; override;'#10 +
    '    property Name: string read GetName write SetName;'#10 +
    '    property Count: Integer read GetCount;'#10 +
    '  end;'#10 +
    'implementation'#10;

function CallsOf(const ASource: string; ADepth: Integer): TArray<TRecursiveCall>;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(ASource);
  try
    Result := TRecursionAnalysis.Calls(mTree, ADepth);
  finally
    mTree.Free;
  end;
end;

function TrapsOf(const ASource: string): TArray<TAccessorTrap>;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(ASource);
  try
    Result := TRecursionAnalysis.AccessorTraps(mTree);
  finally
    mTree.Free;
  end;
end;

procedure TRecursionAnalysisTests.DirectRecursion;
var
  mCalls: TArray<TRecursiveCall>;
begin
  mCalls := CallsOf('unit U;'#10'implementation'#10 +
    'function Fakultaet(N: Integer): Integer;'#10 +
    'begin'#10 +
    '  if N <= 1 then Result := 1 else Result := N * Fakultaet(N - 1);'#10 +
    'end;'#10'end.', 4);
  Assert.AreEqual(1, Integer(Length(mCalls)));
  Assert.AreEqual(4, mCalls[0].Range.StartPos.Line);
  Assert.AreEqual(48, mCalls[0].Range.StartPos.Character);
  Assert.AreEqual(57, mCalls[0].Range.EndPos.Character);
  Assert.AreEqual('Fakultaet → Fakultaet', TRecursionAnalysis.ChainText(mCalls[0]));
  Assert.AreEqual(2, mCalls[0].Chain[0].Range.StartPos.Line, 'Name im Kopf');
  Assert.AreEqual(9, mCalls[0].Chain[0].Range.StartPos.Character);
end;

procedure TRecursionAnalysisTests.ChainOverTwoMethods;
var
  mCalls: TArray<TRecursiveCall>;
begin
  mCalls := CallsOf(cHeader +
    'procedure TFoo.Speichern;'#10'begin'#10'  Pruefen;'#10'end;'#10 +
    'procedure TFoo.Pruefen;'#10'begin'#10'  if FCount > 0 then Self.Speichern;'#10'end;'#10 +
    'procedure TFoo.Run;'#10'begin'#10'  Speichern;'#10'end;'#10'end.', 4);
  Assert.AreEqual(2, Integer(Length(mCalls)), 'Run liegt nicht auf dem Kreis');
  Assert.AreEqual('Speichern → Pruefen → Speichern', TRecursionAnalysis.ChainText(mCalls[0]));
  Assert.AreEqual('TFoo.Pruefen', mCalls[0].Chain[1].Name);
  Assert.AreEqual(20, mCalls[0].Range.StartPos.Line);
  Assert.AreEqual('Pruefen → Speichern → Pruefen', TRecursionAnalysis.ChainText(mCalls[1]));
  Assert.AreEqual(24, mCalls[1].Range.StartPos.Line);
  Assert.AreEqual(26, mCalls[1].Range.StartPos.Character, 'Name hinter Self.');
end;

procedure TRecursionAnalysisTests.DepthLimitsChain;
const
  cSource = 'unit U;'#10'implementation'#10 +
    'procedure A; forward;'#10 +
    'procedure C; begin A; end;'#10 +
    'procedure B; begin C; end;'#10 +
    'procedure A; begin B; end;'#10'end.';
begin
  Assert.AreEqual(3, Integer(Length(CallsOf(cSource, 3))));
  Assert.AreEqual(0, Integer(Length(CallsOf(cSource, 2))), 'Kreis aus drei Routinen');
  Assert.AreEqual(3, Integer(Length(CallsOf(cSource, 99))), 'nach oben begrenzt');
end;

procedure TRecursionAnalysisTests.GetterReadsOwnProperty;
var
  mTraps: TArray<TAccessorTrap>;
  mCalls: TArray<TRecursiveCall>;
  mSource: string;
begin
  mSource := cHeader +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := Name;'#10'end;'#10 +
    'function TFoo.GetCount: Integer;'#10'begin'#10'  Result := Self.Count + 1;'#10'end;'#10 +
    'procedure TFoo.SetName(const AValue: string);'#10'begin'#10'  FName := AValue + Name;'#10'end;'#10'end.';
  mTraps := TrapsOf(mSource);
  Assert.AreEqual(2, Integer(Length(mTraps)), 'Lesen im Setter ruft den Getter und ist keine Falle');
  Assert.AreEqual('Name', mTraps[0].PropertyName);
  Assert.AreEqual('GetName', mTraps[0].Accessor);
  Assert.IsFalse(mTraps[0].IsSetter);
  Assert.AreEqual('FName', mTraps[0].Field);
  Assert.AreEqual(20, mTraps[0].Range.StartPos.Line);
  Assert.AreEqual(12, mTraps[0].Range.StartPos.Character);
  Assert.AreEqual('Count', mTraps[1].PropertyName);
  Assert.AreEqual('FCount', mTraps[1].Field);
  Assert.AreEqual(17, mTraps[1].Range.StartPos.Character, 'Name hinter Self.');
  mCalls := CallsOf(mSource, 4);
  Assert.AreEqual(2, Integer(Length(mCalls)), 'beide Getter auch im Rand');
  Assert.AreEqual('GetName → GetName', TRecursionAnalysis.ChainText(mCalls[0]));
end;

procedure TRecursionAnalysisTests.SetterWritesOwnProperty;
var
  mTraps: TArray<TAccessorTrap>;
begin
  mTraps := TrapsOf(cHeader +
    'procedure TFoo.SetName(const AValue: string);'#10'begin'#10'  if AValue <> FName then'#10 +
    '    Name := AValue;'#10'end;'#10 +
    'function TFoo.GetName: string;'#10'begin'#10'  Name := ''x'';'#10'  Result := FName;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mTraps)), 'Schreiben im Getter ruft den Setter');
  Assert.IsTrue(mTraps[0].IsSetter);
  Assert.AreEqual('SetName', mTraps[0].Accessor);
  Assert.AreEqual(21, mTraps[0].Range.StartPos.Line);
end;

procedure TRecursionAnalysisTests.InheritedIsNoRecursion;
begin
  Assert.AreEqual(0, Integer(Length(CallsOf(cHeader +
    'procedure TFoo.Run;'#10'begin'#10'  inherited Run;'#10'  inherited;'#10'end;'#10'end.', 4))));
end;

procedure TRecursionAnalysisTests.PointersShadowsAndOtherObjectsAreNotFollowed;
begin
  Assert.AreEqual(0, Integer(Length(CallsOf(cHeader +
    'procedure TFoo.Run;'#10'var'#10'  P: TProc;'#10'begin'#10 +
    '  P := Run;'#10 +
    '  Other.Run;'#10 +
    '  Later(procedure begin Run; end);'#10 +
    '  with Other do Run;'#10 +
    'end;'#10 +
    'procedure TFoo.Speichern;'#10'var'#10'  Speichern: Integer;'#10'begin'#10'  Speichern := 1;'#10'end;'#10 +
    'end.', 4))));
end;

procedure TRecursionAnalysisTests.LocalRoutineCallsItself;
var
  mCalls: TArray<TRecursiveCall>;
begin
  mCalls := CallsOf('unit U;'#10'implementation'#10 +
    'procedure Walk;'#10 +
    '  procedure Visit(N: Integer);'#10 +
    '  begin'#10 +
    '    if N > 0 then Visit(N - 1);'#10 +
    '  end;'#10 +
    'begin'#10'  Visit(3);'#10'end;'#10'end.', 4);
  Assert.AreEqual(1, Integer(Length(mCalls)));
  Assert.AreEqual('Walk.Visit', mCalls[0].Chain[0].Name);
end;

procedure TRecursionAnalysisTests.CommandJson;
var
  mCommand: TLspRecursion;
  mArguments: TJSONArray;
  mValue: TJSONValue;
  mCall, mStep: TJSONObject;
begin
  mCommand := TLspRecursion.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit U;'#10'implementation'#10'procedure A; begin A; end;'#10'end.';
      Result := SameText(ExtractFileName(AFileName), 'U.pas');
    end);
  try
    mArguments := TJSONArray.Create;
    try
      mArguments.Add('file:///C:/P/U.pas');
      mArguments.Add(4);
      mValue := mCommand.Execute(mArguments);
      try
        Assert.AreEqual(1, Integer(TJSONObject(mValue).GetValue<TJSONArray>('calls').Count));
        mCall := TJSONObject(TJSONObject(mValue).GetValue<TJSONArray>('calls').Items[0]);
        Assert.AreEqual(2, mCall.GetValue<Integer>('line'));
        Assert.AreEqual(19, mCall.GetValue<Integer>('character'));
        Assert.AreEqual(20, mCall.GetValue<Integer>('endCharacter'));
        Assert.AreEqual('A → A', mCall.GetValue<string>('text'));
        mStep := TJSONObject(mCall.GetValue<TJSONArray>('chain').Items[0]);
        Assert.AreEqual('A', mStep.GetValue<string>('name'));
        Assert.AreEqual(10, mStep.GetValue<Integer>('character'));
      finally
        mValue.Free;
      end;
      mArguments.Remove(0).Free;
      mArguments.Remove(0).Free;
      mArguments.Add('file:///C:/P/Fehlt.pas');
      mValue := mCommand.Execute(mArguments);
      try
        Assert.AreEqual(0, Integer(TJSONObject(mValue).GetValue<TJSONArray>('calls').Count));
      finally
        mValue.Free;
      end;
    finally
      mArguments.Free;
    end;
  finally
    mCommand.Free;
  end;
end;

procedure TRecursionAnalysisTests.FiveThousandLinesUnderFiftyMilliseconds;
var
  mBuilder: TStringBuilder;
  mTree: TSyntaxTree;
  mIndex: Integer;
  mWatch: TStopwatch;
  mCalls: TArray<TRecursiveCall>;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('unit U;'#10'interface'#10'type'#10'  TBig = class'#10);
    for mIndex := 0 to 499 do
    begin
      mBuilder.Append('    procedure M' + IntToStr(mIndex) + ';'#10);
    end;
    mBuilder.Append('  end;'#10'implementation'#10);
    // 500 Methoden zu je neun Zeilen; jede ruft die nächste, jede fünfte schließt einen Kreis.
    for mIndex := 0 to 499 do
    begin
      mBuilder.Append('procedure TBig.M' + IntToStr(mIndex) + ';'#10'var'#10'  I: Integer;'#10'begin'#10);
      mBuilder.Append('  for I := 0 to 3 do'#10'    M' + IntToStr((mIndex + 1) mod 500) + ';'#10);
      if mIndex mod 5 = 4 then
      begin
        mBuilder.Append('  M' + IntToStr(mIndex - 3) + ';'#10);
      end
      else
      begin
        mBuilder.Append('  Writeln(I);'#10);
      end;
      mBuilder.Append('  I := 0;'#10'end;'#10);
    end;
    mBuilder.Append('end.');
    mTree := TSyntaxTreeCache.Parse(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
  try
    mWatch := TStopwatch.StartNew;
    mCalls := TRecursionAnalysis.Calls(mTree, TRecursionAnalysis.cDefaultDepth);
    mWatch.Stop;
    Assert.IsTrue(Length(mCalls) > 0);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 50, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRecursionAnalysisTests);

end.
