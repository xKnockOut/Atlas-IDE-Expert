unit Atlas.Common.Rules.Builtin.CompilerTraps.MethodRefs.Tests;

// Tests der Regel method-reference-called (#1899, #1345): Methodenreferenz in Exit(…) und im Array-Literal neben +,
// die Delphi aufruft (E2035), mit RTL-Typen, eigenen Typen der Datei und des Index sowie stillen Fällen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerTrapsMethodRefsTests = class
  public
    /// <summary>Exit(ALookup) mit eigenem reference to-Typ; Korrektur Result := ALookup; Exit.</summary>
    [Test]
    procedure ExitWithReference;
    /// <summary>FHandlers + [AHandler] mit TArray&lt;TFunc&lt;Boolean&gt;&gt;, auch über ein Feld und einen Typ aus dem Index.
    /// </summary>
    [Test]
    procedure ArrayLiteralWithReference;
    [Test]
    procedure SilentCases;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.CompilerTraps.MethodRefs,
  Atlas.Tests.RuleAssert;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ':' + IntToStr(mFinding.Range.StartPos.Character) +
      ' ' + mFinding.Message + '|';
  end;
end;

{ TCompilerTrapsMethodRefsTests }

procedure TCompilerTrapsMethodRefsTests.ExitWithReference;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TLookup = reference to function(const AName: string): Boolean;'#10 +
    'function Wahl(const ALookup: TLookup): TLookup;'#10 +
    'implementation'#10 +
    'function Wahl(const ALookup: TLookup): TLookup;'#10 +
    'begin'#10 +
    '  if Assigned(ALookup) then'#10 +
    '    Exit(ALookup);'#10 +
    '  Result := nil;'#10 +
    'end;'#10 +
    'end.';
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TMethodReferenceCalledRule.Create, cSource);
  Assert.AreEqual('9:9 Exit(ALookup): ALookup ist eine Methodenreferenz (TLookup); Delphi ruft sie hier auf, statt ' +
    'sie zurückzugeben (wie E2035 bzw. E2010). Result := ALookup; Exit; schreiben.|', Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.IsTrue(mFound[0].Fixes[0].Safe);
  // Ohne Block darum: begin … end.
  Assert.AreEqual('begin Result := ALookup; Exit; end', mFound[0].Fixes[0].Edits[0].NewText);
end;

procedure TCompilerTrapsMethodRefsTests.ArrayLiteralWithReference;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  System.SysUtils, Werk.Typen;'#10 +
    'type'#10 +
    '  TListe = class'#10 +
    '  private'#10 +
    '    FHandlers: TArray<TFunc<Boolean>>;'#10 +
    '    FHoerer: TArray<THoerer>;'#10 +
    '  public'#10 +
    '    procedure Add(const AHandler: TFunc<Boolean>; const AHoerer: THoerer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TListe.Add(const AHandler: TFunc<Boolean>; const AHoerer: THoerer);'#10 +
    'begin'#10 +
    '  FHandlers := FHandlers + [AHandler];'#10 +
    '  FHoerer := [AHoerer] + FHoerer;'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Werk.Typen;'#10'interface'#10'type'#10 +
    '  THoerer = reference to function(const AText: string): Boolean;'#10'implementation'#10'end.', 'C:\P\Werk.Typen.pas',
    nil));
  Assert.AreEqual('15:28 [AHandler]: AHandler ist eine Methodenreferenz (TFunc<Boolean>); im Array-Literal neben + ruft ' +
    'Delphi sie auf (wie E2035 bzw. E2010). Länge mit SetLength erhöhen und das Element zuweisen.|16:14 [AHoerer]: ' +
    'AHoerer ist eine Methodenreferenz (THoerer); im Array-Literal neben + ruft Delphi sie auf (wie E2035 bzw. ' +
    'E2010). Länge mit SetLength erhöhen und das Element zuweisen.|',
    Messages(TRuleAssert.IndexFindings(TMethodReferenceCalledRule.Create, cSource, mIndex, '', 'U.pas')));
end;

procedure TCompilerTrapsMethodRefsTests.SilentCases;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  System.SysUtils;'#10 +
    'function Frage(const AFunc: TFunc<Boolean>): Boolean;'#10 +
    'function Gib(const AProc: TProc): TProc;'#10 +
    'function Haenge(const A: TArray<TProc>; const AProc: TProc): TArray<TProc>;'#10 +
    'function Zahlen(const A: TArray<Integer>; AZahl: Integer): TArray<Integer>;'#10 +
    'function Werte(const A: TArray<Boolean>; const AFunc: TFunc<Boolean>): TArray<Boolean>;'#10 +
    'implementation'#10 +
    'function Frage(const AFunc: TFunc<Boolean>): Boolean;'#10 +
    'begin'#10 +
    '  Exit(AFunc);'#10 +
    'end;'#10 +
    'function Gib(const AProc: TProc): TProc;'#10 +
    'begin'#10 +
    '  Result := AProc;'#10 +
    '  Exit;'#10 +
    'end;'#10 +
    'function Haenge(const A: TArray<TProc>; const AProc: TProc): TArray<TProc>;'#10 +
    'begin'#10 +
    '  Result := A + [AProc];'#10 +
    'end;'#10 +
    'function Zahlen(const A: TArray<Integer>; AZahl: Integer): TArray<Integer>;'#10 +
    'begin'#10 +
    '  Result := A + [AZahl];'#10 +
    'end;'#10 +
    'function Werte(const A: TArray<Boolean>; const AFunc: TFunc<Boolean>): TArray<Boolean>;'#10 +
    'begin'#10 +
    '  Result := A + [AFunc];'#10 +
    'end;'#10 +
    'end.';
begin
  // Exit(AFunc) mit Boolean als Ergebnis und [AFunc] neben TArray<Boolean> rufen gewollt auf; eine Referenz auf
  // eine Prozedur (TProc) nimmt Delphi im Array-Literal als Element.
  TRuleAssert.Silent(TMethodReferenceCalledRule.Create, cSource);
end;

procedure TCompilerTrapsMethodRefsTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    mFound := mFound or (mRule.Descriptor.Id = cMethodReferenceCalledRuleId);
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerTrapsMethodRefsTests);

end.
