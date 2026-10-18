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
  Header =
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
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(ASource);
  try
    Result := TRecursionAnalysis.Calls(Tree, ADepth);
  finally
    Tree.Free;
  end;
end;

function TrapsOf(const ASource: string): TArray<TAccessorTrap>;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(ASource);
  try
    Result := TRecursionAnalysis.AccessorTraps(Tree);
  finally
    Tree.Free;
  end;
end;

procedure TRecursionAnalysisTests.DirectRecursion;
var
  Calls: TArray<TRecursiveCall>;
begin
  Calls := CallsOf('unit U;'#10'implementation'#10 +
    'function Fakultaet(N: Integer): Integer;'#10 +
    'begin'#10 +
    '  if N <= 1 then Result := 1 else Result := N * Fakultaet(N - 1);'#10 +
    'end;'#10'end.', 4);
  Assert.AreEqual(1, Integer(Length(Calls)));
  Assert.AreEqual(4, Calls[0].Range.StartPos.Line);
  Assert.AreEqual(48, Calls[0].Range.StartPos.Character);
  Assert.AreEqual(57, Calls[0].Range.EndPos.Character);
  Assert.AreEqual('Fakultaet → Fakultaet', TRecursionAnalysis.ChainText(Calls[0]));
  Assert.AreEqual(2, Calls[0].Chain[0].Range.StartPos.Line, 'Name im Kopf');
  Assert.AreEqual(9, Calls[0].Chain[0].Range.StartPos.Character);
end;

procedure TRecursionAnalysisTests.ChainOverTwoMethods;
var
  Calls: TArray<TRecursiveCall>;
begin
  Calls := CallsOf(Header +
    'procedure TFoo.Speichern;'#10'begin'#10'  Pruefen;'#10'end;'#10 +
    'procedure TFoo.Pruefen;'#10'begin'#10'  if FCount > 0 then Self.Speichern;'#10'end;'#10 +
    'procedure TFoo.Run;'#10'begin'#10'  Speichern;'#10'end;'#10'end.', 4);
  Assert.AreEqual(2, Integer(Length(Calls)), 'Run liegt nicht auf dem Kreis');
  Assert.AreEqual('Speichern → Pruefen → Speichern', TRecursionAnalysis.ChainText(Calls[0]));
  Assert.AreEqual('TFoo.Pruefen', Calls[0].Chain[1].Name);
  Assert.AreEqual(20, Calls[0].Range.StartPos.Line);
  Assert.AreEqual('Pruefen → Speichern → Pruefen', TRecursionAnalysis.ChainText(Calls[1]));
  Assert.AreEqual(24, Calls[1].Range.StartPos.Line);
  Assert.AreEqual(26, Calls[1].Range.StartPos.Character, 'Name hinter Self.');
end;

procedure TRecursionAnalysisTests.DepthLimitsChain;
const
  Source = 'unit U;'#10'implementation'#10 +
    'procedure A; forward;'#10 +
    'procedure C; begin A; end;'#10 +
    'procedure B; begin C; end;'#10 +
    'procedure A; begin B; end;'#10'end.';
begin
  Assert.AreEqual(3, Integer(Length(CallsOf(Source, 3))));
  Assert.AreEqual(0, Integer(Length(CallsOf(Source, 2))), 'Kreis aus drei Routinen');
  Assert.AreEqual(3, Integer(Length(CallsOf(Source, 99))), 'nach oben begrenzt');
end;

procedure TRecursionAnalysisTests.GetterReadsOwnProperty;
var
  Traps: TArray<TAccessorTrap>;
  Calls: TArray<TRecursiveCall>;
  Source: string;
begin
  Source := Header +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := Name;'#10'end;'#10 +
    'function TFoo.GetCount: Integer;'#10'begin'#10'  Result := Self.Count + 1;'#10'end;'#10 +
    'procedure TFoo.SetName(const AValue: string);'#10'begin'#10'  FName := AValue + Name;'#10'end;'#10'end.';
  Traps := TrapsOf(Source);
  Assert.AreEqual(2, Integer(Length(Traps)), 'Lesen im Setter ruft den Getter und ist keine Falle');
  Assert.AreEqual('Name', Traps[0].PropertyName);
  Assert.AreEqual('GetName', Traps[0].Accessor);
  Assert.IsFalse(Traps[0].IsSetter);
  Assert.AreEqual('FName', Traps[0].Field);
  Assert.AreEqual(20, Traps[0].Range.StartPos.Line);
  Assert.AreEqual(12, Traps[0].Range.StartPos.Character);
  Assert.AreEqual('Count', Traps[1].PropertyName);
  Assert.AreEqual('FCount', Traps[1].Field);
  Assert.AreEqual(17, Traps[1].Range.StartPos.Character, 'Name hinter Self.');
  Calls := CallsOf(Source, 4);
  Assert.AreEqual(2, Integer(Length(Calls)), 'beide Getter auch im Rand');
  Assert.AreEqual('GetName → GetName', TRecursionAnalysis.ChainText(Calls[0]));
end;

procedure TRecursionAnalysisTests.SetterWritesOwnProperty;
var
  Traps: TArray<TAccessorTrap>;
begin
  Traps := TrapsOf(Header +
    'procedure TFoo.SetName(const AValue: string);'#10'begin'#10'  if AValue <> FName then'#10 +
    '    Name := AValue;'#10'end;'#10 +
    'function TFoo.GetName: string;'#10'begin'#10'  Name := ''x'';'#10'  Result := FName;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Traps)), 'Schreiben im Getter ruft den Setter');
  Assert.IsTrue(Traps[0].IsSetter);
  Assert.AreEqual('SetName', Traps[0].Accessor);
  Assert.AreEqual(21, Traps[0].Range.StartPos.Line);
end;

procedure TRecursionAnalysisTests.InheritedIsNoRecursion;
begin
  Assert.AreEqual(0, Integer(Length(CallsOf(Header +
    'procedure TFoo.Run;'#10'begin'#10'  inherited Run;'#10'  inherited;'#10'end;'#10'end.', 4))));
end;

procedure TRecursionAnalysisTests.PointersShadowsAndOtherObjectsAreNotFollowed;
begin
  Assert.AreEqual(0, Integer(Length(CallsOf(Header +
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
  Calls: TArray<TRecursiveCall>;
begin
  Calls := CallsOf('unit U;'#10'implementation'#10 +
    'procedure Walk;'#10 +
    '  procedure Visit(N: Integer);'#10 +
    '  begin'#10 +
    '    if N > 0 then Visit(N - 1);'#10 +
    '  end;'#10 +
    'begin'#10'  Visit(3);'#10'end;'#10'end.', 4);
  Assert.AreEqual(1, Integer(Length(Calls)));
  Assert.AreEqual('Walk.Visit', Calls[0].Chain[0].Name);
end;

procedure TRecursionAnalysisTests.CommandJson;
var
  Command: TLspRecursion;
  Arguments: TJSONArray;
  Value: TJSONValue;
  Call, Step: TJSONObject;
begin
  Command := TLspRecursion.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit U;'#10'implementation'#10'procedure A; begin A; end;'#10'end.';
      Result := SameText(ExtractFileName(AFileName), 'U.pas');
    end);
  try
    Arguments := TJSONArray.Create;
    try
      Arguments.Add('file:///C:/P/U.pas');
      Arguments.Add(4);
      Value := Command.Execute(Arguments);
      try
        Assert.AreEqual(1, Integer(TJSONObject(Value).GetValue<TJSONArray>('calls').Count));
        Call := TJSONObject(TJSONObject(Value).GetValue<TJSONArray>('calls').Items[0]);
        Assert.AreEqual(2, Call.GetValue<Integer>('line'));
        Assert.AreEqual(19, Call.GetValue<Integer>('character'));
        Assert.AreEqual(20, Call.GetValue<Integer>('endCharacter'));
        Assert.AreEqual('A → A', Call.GetValue<string>('text'));
        Step := TJSONObject(Call.GetValue<TJSONArray>('chain').Items[0]);
        Assert.AreEqual('A', Step.GetValue<string>('name'));
        Assert.AreEqual(10, Step.GetValue<Integer>('character'));
      finally
        Value.Free;
      end;
      Arguments.Remove(0).Free;
      Arguments.Remove(0).Free;
      Arguments.Add('file:///C:/P/Fehlt.pas');
      Value := Command.Execute(Arguments);
      try
        Assert.AreEqual(0, Integer(TJSONObject(Value).GetValue<TJSONArray>('calls').Count));
      finally
        Value.Free;
      end;
    finally
      Arguments.Free;
    end;
  finally
    Command.Free;
  end;
end;

procedure TRecursionAnalysisTests.FiveThousandLinesUnderFiftyMilliseconds;
var
  Builder: TStringBuilder;
  Tree: TSyntaxTree;
  Index: Integer;
  Watch: TStopwatch;
  Calls: TArray<TRecursiveCall>;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('unit U;'#10'interface'#10'type'#10'  TBig = class'#10);
    for Index := 0 to 499 do
      Builder.Append('    procedure M' + IntToStr(Index) + ';'#10);
    Builder.Append('  end;'#10'implementation'#10);
    // 500 Methoden zu je neun Zeilen; jede ruft die nächste, jede fünfte schließt einen Kreis.
    for Index := 0 to 499 do
    begin
      Builder.Append('procedure TBig.M' + IntToStr(Index) + ';'#10'var'#10'  I: Integer;'#10'begin'#10);
      Builder.Append('  for I := 0 to 3 do'#10'    M' + IntToStr((Index + 1) mod 500) + ';'#10);
      if Index mod 5 = 4 then
        Builder.Append('  M' + IntToStr(Index - 3) + ';'#10)
      else
        Builder.Append('  Writeln(I);'#10);
      Builder.Append('  I := 0;'#10'end;'#10);
    end;
    Builder.Append('end.');
    Tree := TSyntaxTreeCache.Parse(Builder.ToString);
  finally
    Builder.Free;
  end;
  try
    Watch := TStopwatch.StartNew;
    Calls := TRecursionAnalysis.Calls(Tree, TRecursionAnalysis.DefaultDepth);
    Watch.Stop;
    Assert.IsTrue(Length(Calls) > 0);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 50, Format('%d ms', [Watch.ElapsedMilliseconds]));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRecursionAnalysisTests);

end.
