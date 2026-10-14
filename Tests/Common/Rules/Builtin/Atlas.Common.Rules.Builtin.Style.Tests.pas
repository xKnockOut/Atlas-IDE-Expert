unit Atlas.Common.Rules.Builtin.Style.Tests;

// Tests für die Stilregeln (#104): je Regel positiv, negativ und Schnellkorrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStyleRulesTests = class
  public
    [Test]
    procedure BoolCompareOnBoolean;
    [Test]
    procedure BoolCompareNotOnLongBool;
    [Test]
    procedure BoolCompareFixes;
    [Test]
    procedure AssignedFreeReported;
    [Test]
    procedure AssignedFreeWithNilBecomesFreeAndNil;
    [Test]
    procedure AssignedFreeOtherShapesSilent;
    [Test]
    procedure RaiseInFinallyReported;
    [Test]
    procedure RaiseInExceptSilent;
    [Test]
    procedure RedundantParensOnlyWhenEnabled;
    [Test]
    procedure RedundantParensFix;
    [Test]
    procedure RedundantBeginEndFix;
    [Test]
    procedure RedundantBeginEndKeepsDanglingElse;
    [Test]
    procedure WithStatementReported;
    [Test]
    procedure WithoutWithSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Style,
  Atlas.Tests.RuleAssert;

const
  ParensOn = '{ "rules": { "redundant-parens": "hint" } }';
  BeginEndOn = '{ "rules": { "redundant-begin-end": "hint" } }';

function InRoutine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10 + AVars + #10'begin'#10 +
    ABody + #10'end;'#10'end.';
end;

/// <summary>Wendet die erste Korrektur des ersten Treffers auf ASource an.</summary>
function Fixed(const ASource: string; const AFindings: TArray<TRuleFinding>): string;
var
  Lines: TArray<string>;
  Offsets: TArray<Integer>;
  Index, Start: Integer;
  Edit: TRuleEdit;
  Edits: TArray<TRuleEdit>;
begin
  Lines := nil;
  Start := 1;
  for Index := 1 to Length(ASource) + 1 do
    if (Index > Length(ASource)) or (ASource[Index] = #10) then
    begin
      Lines := Lines + [Copy(ASource, Start, Index - Start)];
      Start := Index + 1;
    end;
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  Result := ASource;
  // Von hinten nach vorn, damit die Positionen stimmen.
  Edits := AFindings[0].Fixes[0].Edits;
  for Index := High(Edits) downto 0 do
  begin
    Edit := Edits[Index];
    Result := Copy(Result, 1, Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character) + Edit.NewText +
      Copy(Result, Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character + 1, MaxInt);
  end;
end;

procedure TStyleRulesTests.BoolCompareOnBoolean;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TBoolCompareRule.Create, InRoutine('  B: Boolean;', '  if B = True then Save;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TStyleRulesTests.BoolCompareNotOnLongBool;
begin
  TRuleAssert.Silent(TBoolCompareRule.Create, InRoutine('  B: LongBool;'#10'  N: Integer;'#10'  U: TUnbekannt;',
    '  if B = True then Save;'#10'  if N = 1 then Save;'#10'  if U = True then Save;'));
  // A and B = True bindet als (A and B) = True: nicht melden.
  TRuleAssert.Silent(TBoolCompareRule.Create, InRoutine('  A, B: Boolean;', '  if A and B = True then Save;'));
end;

procedure TStyleRulesTests.BoolCompareFixes;
var
  Source: string;
begin
  Source := InRoutine('  B: Boolean;', '  if B = False then Save;');
  Assert.AreEqual(InRoutine('  B: Boolean;', '  if not B then Save;'),
    Fixed(Source, TRuleAssert.Findings(TBoolCompareRule.Create, Source)));
  Source := InRoutine('  B, C: Boolean;', '  C := True <> B;');
  Assert.AreEqual(InRoutine('  B, C: Boolean;', '  C := not B;'),
    Fixed(Source, TRuleAssert.Findings(TBoolCompareRule.Create, Source)));
end;

procedure TStyleRulesTests.AssignedFreeReported;
var
  Source: string;
begin
  Source := InRoutine('  L: TObject;', '  if Assigned(L) then L.Free;');
  Assert.AreEqual(InRoutine('  L: TObject;', '  L.Free;'),
    Fixed(Source, TRuleAssert.Findings(TRedundantAssignedFreeRule.Create, Source)));
  TRuleAssert.Reports(TRedundantAssignedFreeRule.Create, InRoutine('  X: Integer;',
    '  if Assigned(Self.FListe) then'#10'    Self.FListe.Free;'));
end;

procedure TStyleRulesTests.AssignedFreeWithNilBecomesFreeAndNil;
var
  Source: string;
begin
  Source := InRoutine('  L: TObject;', '  if Assigned(L) then'#10'  begin'#10'    L.Free;'#10'    L := nil;'#10 +
    '  end;');
  Assert.AreEqual(InRoutine('  L: TObject;', '  FreeAndNil(L);'),
    Fixed(Source, TRuleAssert.Findings(TRedundantAssignedFreeRule.Create, Source)));
end;

procedure TStyleRulesTests.AssignedFreeOtherShapesSilent;
begin
  TRuleAssert.Silent(TRedundantAssignedFreeRule.Create, InRoutine('  L, M: TObject;',
    '  if Assigned(L) then M.Free;'#10 +
    '  if Assigned(L) then L.Free else Log;'#10 +
    '  if Assigned(L) then begin L.Free; Log; end;'#10 +
    '  if Assigned(FOnChange) then FOnChange(Self);'));
end;

procedure TStyleRulesTests.RaiseInFinallyReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TRaiseInFinallyRule.Create, InRoutine('  X: Integer;',
    '  try'#10'    Save;'#10'  finally'#10'    if Fehler then'#10'      raise EFehler.Create(''X'');'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TStyleRulesTests.RaiseInExceptSilent;
begin
  TRuleAssert.Silent(TRaiseInFinallyRule.Create, InRoutine('  X: Integer;',
    '  try'#10'    Save;'#10'  except'#10'    on E: Exception do'#10'      raise;'#10'  end;'#10 +
    // Im finally abgefangen bzw. in einer anonymen Methode: kein Treffer.
    '  try'#10'    Save;'#10'  finally'#10'    try'#10'      raise E;'#10'    except'#10'    end;'#10 +
    '    TThread.Queue(nil, procedure begin raise E; end);'#10'  end;'));
end;

procedure TStyleRulesTests.RedundantParensOnlyWhenEnabled;
const
  Source = '  if (A) then Save;'#10'  X := (A + B) * C;'#10'  if (A) and (B) then Save;';
begin
  TRuleAssert.Silent(TRedundantParensRule.Create, InRoutine('  X: Integer;', Source));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRedundantParensRule.Create, InRoutine('  X: Integer;',
    Source), ParensOn))));
end;

procedure TStyleRulesTests.RedundantParensFix;
var
  Source: string;
begin
  Source := InRoutine('  X: Integer;', '  while (X > 0) do Dec(X);'#10'  X := (A + B);');
  Assert.AreEqual(InRoutine('  X: Integer;', '  while X > 0 do Dec(X);'#10'  X := (A + B);'),
    Fixed(Source, TRuleAssert.Findings(TRedundantParensRule.Create, Source, ParensOn)));
end;

procedure TStyleRulesTests.RedundantBeginEndFix;
var
  Source: string;
begin
  Source := InRoutine('  X: Integer;', '  if A then begin Save(X); end else Load;');
  TRuleAssert.Silent(TRedundantBeginEndRule.Create, Source);
  Assert.AreEqual(InRoutine('  X: Integer;', '  if A then Save(X) else Load;'),
    Fixed(Source, TRuleAssert.Findings(TRedundantBeginEndRule.Create, Source, BeginEndOn)));
end;

procedure TStyleRulesTests.RedundantBeginEndKeepsDanglingElse;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRedundantBeginEndRule.Create, InRoutine('  X: Integer;',
    '  if A then begin if B then X := 1; end else X := 2;'#10 +
    '  for X := 1 to 2 do begin Save; Load; end;'), BeginEndOn))));
end;

procedure TStyleRulesTests.WithStatementReported;
var
  Findings: TArray<TRuleFinding>;
begin
  // Verschachtelt: jedes with einzeln, markiert ist das Schlüsselwort.
  Findings := TRuleAssert.Findings(TWithStatementRule.Create, InRoutine('  P: TPoint;',
    '  with P do'#10'    with Q, R do'#10'      X := Y;'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(6, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
end;

procedure TStyleRulesTests.WithoutWithSilent;
begin
  TRuleAssert.Silent(TWithStatementRule.Create, InRoutine('  P: TPoint;', '  P.X := P.Y; // with P do'));
end;

initialization
  TDUnitX.RegisterTestFixture(TStyleRulesTests);

end.
