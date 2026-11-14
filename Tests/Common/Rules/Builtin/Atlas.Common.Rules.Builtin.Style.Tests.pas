unit Atlas.Common.Rules.Builtin.Style.Tests;

// Tests für die Stilregeln (#104): je Regel positiv, negativ und Schnellkorrektur; boolean-assign-if (#935),
// case-insensitive-compare (#936), magic-number (#937), line-length (#938), public-field (#940), global-variable (#941)
// und missing-begin-end (#1025) samt Gegenregel redundant-begin-end.

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
    [Test]
    procedure BooleanAssignIfIssueExample;
    [Test]
    procedure BooleanAssignIfVariants;
    [Test]
    procedure BooleanAssignIfSilentCases;
    [Test]
    procedure CaseInsensitiveCompareIssueExample;
    [Test]
    procedure CaseInsensitiveCompareVariants;
    [Test]
    procedure CaseInsensitiveCompareSilentCases;
    [Test]
    procedure MagicNumberIssueExample;
    [Test]
    procedure MagicNumberVariantsAndOptions;
    [Test]
    procedure MagicNumberSilentCases;
    [Test]
    procedure LineLengthIssueExample;
    [Test]
    procedure LineLengthOptions;
    [Test]
    procedure LineLengthCompilerLimit;
    [Test]
    procedure PublicFieldIssueExample;
    [Test]
    procedure PublicFieldVariantsAndOptions;
    [Test]
    procedure PublicFieldSilentCases;
    [Test]
    procedure GlobalVariableIssueExample;
    [Test]
    procedure GlobalVariableFormVariablesAndOptions;
    [Test]
    procedure MissingBeginEndIssueExample;
    [Test]
    procedure MissingBeginEndFixesIssueExample;
    /// <summary>format.elsePlacement sameLine: Die Korrektur setzt else hinter das end.</summary>
    [Test]
    procedure MissingBeginEndFixFollowsElsePlacement;
    [Test]
    procedure MissingBeginEndSameLineAndNestedFixes;
    [Test]
    procedure MissingBeginEndSilentCases;
    [Test]
    procedure MissingBeginEndOptions;
    [Test]
    procedure MissingBeginEndOverridesRedundantBeginEnd;
    [Test]
    procedure MissingBeginEndOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Style,
  Atlas.Common.Rules.Builtin.Style.LineLength,
  Atlas.Common.Rules.Builtin.Style.Declarations,
  Atlas.Common.Rules.Builtin.Style.BeginEnd,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Engine,
  Atlas.Tests.RuleAssert;

const
  cParensOn = '{ "rules": { "redundant-parens": "hint" } }';
  // Die Gegenregel missing-begin-end ist standardmäßig an und übersteuert redundant-begin-end (#1025).
  cBeginEndOn = '{ "rules": { "redundant-begin-end": "hint", "missing-begin-end": "off" } }';
  cBothBeginEndOn = '{ "rules": { "redundant-begin-end": "hint" } }';

function InRoutine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10 + AVars + #10'begin'#10 +
    ABody + #10'end;'#10'end.';
end;

/// <summary>Wendet AFix auf ASource an.</summary>
function Applied(const ASource: string; const AFix: TRuleFix): string;
var
  mLines: TArray<string>;
  mOffsets: TArray<Integer>;
  mIndex, mStart: Integer;
  mEdit: TRuleEdit;
  mEdits: TArray<TRuleEdit>;
begin
  mLines := nil;
  mStart := 1;
  for mIndex := 1 to Length(ASource) + 1 do
  begin
    if (mIndex > Length(ASource)) or (ASource[mIndex] = #10) then
    begin
      mLines := mLines + [Copy(ASource, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  Result := ASource;
  // Von hinten nach vorn, damit die Positionen stimmen (die Edits einer Korrektur sind nicht sortiert).
  mEdits := Copy(AFix.Edits);
  for mIndex := 1 to High(mEdits) do
  begin
    mEdit := mEdits[mIndex];
    mStart := mIndex - 1;
    while (mStart >= 0) and ((mEdits[mStart].Range.StartPos.Line > mEdit.Range.StartPos.Line) or
      ((mEdits[mStart].Range.StartPos.Line = mEdit.Range.StartPos.Line) and
      (mEdits[mStart].Range.StartPos.Character > mEdit.Range.StartPos.Character))) do
    begin
      mEdits[mStart + 1] := mEdits[mStart];
      Dec(mStart);
    end;
    mEdits[mStart + 1] := mEdit;
  end;
  for mIndex := High(mEdits) downto 0 do
  begin
    mEdit := mEdits[mIndex];
    Result := Copy(Result, 1, mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character) + mEdit.NewText +
      Copy(Result, mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character + 1, MaxInt);
  end;
end;

/// <summary>Wendet die erste Korrektur des ersten Treffers auf ASource an.</summary>
function Fixed(const ASource: string; const AFindings: TArray<TRuleFinding>): string;
begin
  Result := Applied(ASource, AFindings[0].Fixes[0]);
end;

/// <summary>Korrektur von AFinding mit AText im Titel.</summary>
function FixTitled(const AFinding: TRuleFinding; const AText: string): TRuleFix;
var
  mFix: TRuleFix;
begin
  for mFix in AFinding.Fixes do
  begin
    if Pos(AText, mFix.Title) > 0 then
    begin
      Exit(mFix);
    end;
  end;
  Assert.Fail('Keine Korrektur mit "' + AText + '"');
  Result := Default(TRuleFix);
end;

/// <summary>ASource parst ohne Syntaxfehler.</summary>
procedure AssertParses(const ASource: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), ASource);
  finally
    mTree.Free;
  end;
end;

procedure TStyleRulesTests.BoolCompareOnBoolean;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TBoolCompareRule.Create, InRoutine('  B: Boolean;', '  if B = True then Save;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
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
  mSource: string;
begin
  mSource := InRoutine('  B: Boolean;', '  if B = False then Save;');
  Assert.AreEqual(InRoutine('  B: Boolean;', '  if not B then Save;'),
    Fixed(mSource, TRuleAssert.Findings(TBoolCompareRule.Create, mSource)));
  mSource := InRoutine('  B, C: Boolean;', '  C := True <> B;');
  Assert.AreEqual(InRoutine('  B, C: Boolean;', '  C := not B;'),
    Fixed(mSource, TRuleAssert.Findings(TBoolCompareRule.Create, mSource)));
end;

procedure TStyleRulesTests.AssignedFreeReported;
var
  mSource: string;
begin
  mSource := InRoutine('  L: TObject;', '  if Assigned(L) then L.Free;');
  Assert.AreEqual(InRoutine('  L: TObject;', '  L.Free;'),
    Fixed(mSource, TRuleAssert.Findings(TRedundantAssignedFreeRule.Create, mSource)));
  TRuleAssert.Reports(TRedundantAssignedFreeRule.Create, InRoutine('  X: Integer;',
    '  if Assigned(Self.FListe) then'#10'    Self.FListe.Free;'));
end;

procedure TStyleRulesTests.AssignedFreeWithNilBecomesFreeAndNil;
var
  mSource: string;
begin
  mSource := InRoutine('  L: TObject;', '  if Assigned(L) then'#10'  begin'#10'    L.Free;'#10'    L := nil;'#10 +
    '  end;');
  Assert.AreEqual(InRoutine('  L: TObject;', '  FreeAndNil(L);'),
    Fixed(mSource, TRuleAssert.Findings(TRedundantAssignedFreeRule.Create, mSource)));
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TRaiseInFinallyRule.Create, InRoutine('  X: Integer;',
    '  try'#10'    Save;'#10'  finally'#10'    if Fehler then'#10'      raise EFehler.Create(''X'');'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
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
  cSource = '  if (A) then Save;'#10'  X := (A + B) * C;'#10'  if (A) and (B) then Save;';
begin
  TRuleAssert.Silent(TRedundantParensRule.Create, InRoutine('  X: Integer;', cSource));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRedundantParensRule.Create, InRoutine('  X: Integer;',
    cSource), cParensOn))));
end;

procedure TStyleRulesTests.RedundantParensFix;
var
  mSource: string;
begin
  mSource := InRoutine('  X: Integer;', '  while (X > 0) do Dec(X);'#10'  X := (A + B);');
  Assert.AreEqual(InRoutine('  X: Integer;', '  while X > 0 do Dec(X);'#10'  X := (A + B);'),
    Fixed(mSource, TRuleAssert.Findings(TRedundantParensRule.Create, mSource, cParensOn)));
end;

procedure TStyleRulesTests.RedundantBeginEndFix;
var
  mSource: string;
begin
  mSource := InRoutine('  X: Integer;', '  if A then begin Save(X); end else Load;');
  TRuleAssert.Silent(TRedundantBeginEndRule.Create, mSource);
  Assert.AreEqual(InRoutine('  X: Integer;', '  if A then Save(X) else Load;'),
    Fixed(mSource, TRuleAssert.Findings(TRedundantBeginEndRule.Create, mSource, cBeginEndOn)));
end;

procedure TStyleRulesTests.RedundantBeginEndKeepsDanglingElse;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRedundantBeginEndRule.Create, InRoutine('  X: Integer;',
    '  if A then begin if B then X := 1; end else X := 2;'#10 +
    '  for X := 1 to 2 do begin Save; Load; end;'), cBeginEndOn))));
end;

procedure TStyleRulesTests.WithStatementReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Verschachtelt: jedes with einzeln, markiert ist das Schlüsselwort.
  mFindings := TRuleAssert.Findings(TWithStatementRule.Create, InRoutine('  P: TPoint;',
    '  with P do'#10'    with Q, R do'#10'      X := Y;'));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(6, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
end;

procedure TStyleRulesTests.WithoutWithSilent;
begin
  TRuleAssert.Silent(TWithStatementRule.Create, InRoutine('  P: TPoint;', '  P.X := P.Y; // with P do'));
end;

procedure TStyleRulesTests.BooleanAssignIfIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  Betrag: Integer;', '  if Betrag > 0 then'#10'    Result := True'#10'  else'#10 +
    '    Result := False;');
  mFindings := TRuleAssert.Findings(TBooleanAssignIfRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Das if weist nur True oder False zu.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Durch Result := Betrag > 0 ersetzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  Betrag: Integer;', '  Result := Betrag > 0;'), Fixed(mSource, mFindings));
  TRuleAssert.Silent(TBooleanAssignIfRule.Create, Fixed(mSource, mFindings));
end;

procedure TStyleRulesTests.BooleanAssignIfVariants;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Umgekehrt, mit begin/end, mit not, Exit mit else und Exit als Folgeanweisung.
  mSource := InRoutine('  X: Boolean;', '  if Liste.Count = 0 then begin X := False; end else begin X := True; end;');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  X := not (Liste.Count = 0);'),
    Fixed(mSource, TRuleAssert.Findings(TBooleanAssignIfRule.Create, mSource)));
  mSource := InRoutine('  X: Boolean;', '  if not Fertig then X := False else X := True;');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  X := Fertig;'),
    Fixed(mSource, TRuleAssert.Findings(TBooleanAssignIfRule.Create, mSource)));
  mSource := InRoutine('  X: Boolean;', '  if Gefunden(A) then Exit(False) else Exit(True);');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  Exit(not Gefunden(A));'),
    Fixed(mSource, TRuleAssert.Findings(TBooleanAssignIfRule.Create, mSource)));
  mSource := InRoutine('  X: Boolean;', '  if A and B then'#10'    Exit(True);'#10'  Exit(False);');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  Exit(A and B);'),
    Fixed(mSource, TRuleAssert.Findings(TBooleanAssignIfRule.Create, mSource)));
  // Wie THTTPClient.CheckDownloadResume (System.Net.HttpClient): Kommentar hinter then, Meldung ohne Korrektur.
  mFindings := TRuleAssert.Findings(TBooleanAssignIfRule.Create, InRoutine('  LValue: string;',
    '  if (LValue = '''') or SameText(LResponse.HeaderValue[sAcceptRanges], ''none'') then  // do not translate'#10 +
    '    Result := False'#10'  else'#10'    Result := True;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Kommentar im if: Meldung ohne Korrektur.
  mFindings := TRuleAssert.Findings(TBooleanAssignIfRule.Create, InRoutine('  X: Boolean;',
    '  if A then X := True // wichtig'#10'  else X := False;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TBooleanAssignIfRule.Create, mSource,
    '{"rules": {"boolean-assign-if": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TBooleanAssignIfRule.Create, mSource,
    '{"rules": {"boolean-assign-if": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TStyleRulesTests.BooleanAssignIfSilentCases;
begin
  // Verschiedene Ziele, gleiche Werte, weitere Anweisungen, Exit mit Folgeanweisung im else, Result := B.
  TRuleAssert.Silent(TBooleanAssignIfRule.Create, InRoutine('  X, Y: Boolean;', '  if A then X := True else Y := False;'#10 +
    '  if A then X := True else X := True;'#10'  if A then begin X := True; Log; end else X := False;'#10 +
    '  if A then Exit(True);'#10'  Log;'#10'  if A then X := 1 else X := 0;'#10'  Result := A;'#10 +
    '  if A then Exit(True) else if B then Exit(False);'#10'  Exit(True);'));
end;

procedure TStyleRulesTests.CaseInsensitiveCompareIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  Land, Standard: string;', '  if UpperCase(Land) = UpperCase(Standard) then'#10'    Log;');
  mFindings := TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Vergleich über UpperCase; SameText vergleicht ohne Zwischenstrings.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Durch SameText(Land, Standard) ersetzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  Land, Standard: string;', '  if SameText(Land, Standard) then'#10'    Log;'),
    Fixed(mSource, mFindings));
  TRuleAssert.Silent(TCaseInsensitiveCompareRule.Create, Fixed(mSource, mFindings));
end;

procedure TStyleRulesTests.CaseInsensitiveCompareVariants;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  S: string;', '  if LowerCase(S) <> ''ja'' then Exit;');
  Assert.AreEqual(InRoutine('  S: string;', '  if not SameText(S, ''ja'') then Exit;'),
    Fixed(mSource, TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, mSource)));
  mSource := InRoutine('  S: string;', '  B := ''JA'' = AnsiUpperCase(Trim(S));');
  Assert.AreEqual(InRoutine('  S: string;', '  B := AnsiSameText(Trim(S), ''JA'');'),
    Fixed(mSource, TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, mSource)));
  mSource := InRoutine('  S: string;', '  B := S.ToUpper = Name.ToUpper();');
  mFindings := TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, mSource);
  Assert.AreEqual('Vergleich über ToUpper; AnsiSameText vergleicht ohne Zwischenstrings.', mFindings[0].Message);
  Assert.AreEqual(InRoutine('  S: string;', '  B := AnsiSameText(S, Name);'), Fixed(mSource, mFindings));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, mSource,
    '{"rules": {"case-insensitive-compare": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, mSource,
    '{"rules": {"case-insensitive-compare": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TStyleRulesTests.CaseInsensitiveCompareSilentCases;
begin
  // Gemischte Umwandlung, Literal mit anderer Schreibweise, nur eine Seite umgewandelt, Zuweisung.
  TRuleAssert.Silent(TCaseInsensitiveCompareRule.Create, InRoutine('  S, T: string;',
    '  B := UpperCase(S) = LowerCase(T);'#10'  B := UpperCase(S) = ''ja'';'#10'  B := UpperCase(S) = T;'#10 +
    '  S := UpperCase(T);'#10'  B := SameText(S, T);'#10'  B := UpperCase(S) < UpperCase(T);'));
end;

const
  // Niedrige Konfidenz: erst mit minConfidence low sichtbar.
  cMagicOn = '{ "minConfidence": "low", "rules": { "magic-number": "hint" } }';

procedure TStyleRulesTests.MagicNumberIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  Tage: Integer;', '  if Tage > 42 then'#10'    Mahnen;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, mSource))), 'Standard aus');
  mFindings := TRuleAssert.Findings(TMagicNumberRule.Create, mSource, cMagicOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Zahl 42 ohne Namen; als Konstante wird klar, was sie bedeutet.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Konstante einführen', mFindings[0].Fixes[0].Title);
  mSource := Fixed(mSource, mFindings);
  Assert.IsTrue(Pos('NewConstant = 42;', mSource) > 0, mSource);
  Assert.IsTrue(Pos('if Tage > NewConstant then', mSource) > 0, mSource);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, mSource, cMagicOn))));
end;

procedure TStyleRulesTests.MagicNumberVariantsAndOptions;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  X: Double;', '  X := -7 * 3.5 + $FF;'#10'  Warten(1000);'#10'  X := 2 * 10 - 1;');
  mFindings := TRuleAssert.Findings(TMagicNumberRule.Create, mSource, cMagicOn);
  // $FF ist eine volle Bitmaske und spricht für sich.
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual('Zahl -7 ohne Namen; als Konstante wird klar, was sie bedeutet.', mFindings[0].Message);
  Assert.AreEqual('Zahl 3.5 ohne Namen; als Konstante wird klar, was sie bedeutet.', mFindings[1].Message);
  Assert.AreEqual('Zahl 1000 ohne Namen; als Konstante wird klar, was sie bedeutet.', mFindings[2].Message);
  mFindings := TRuleAssert.Findings(TMagicNumberRule.Create, mSource,
    '{ "minConfidence": "low", "rules": { "magic-number": { "severity": "hint", "allowed": [1000, -7, 255, 3.5] } } }');
  Assert.AreEqual(3, Integer(Length(mFindings)), '2 und 10 nicht mehr erlaubt');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, mSource,
    '{ "minConfidence": "low", "rules": { "magic-number": { "severity": "hint", "exclude": ["Tests/*.pas"] } } }',
    'Tests/U.pas'))));
end;

procedure TStyleRulesTests.MagicNumberSilentCases;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Konstanten, Array-Grenzen, Teilbereiche, erlaubte Werte, Zeichen und Strings.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, 'unit U;'#10'interface'#10'const'#10'  Grenze = 42;'#10'type'#10 +
    '  TFeld = array[0..41] of Integer;'#10'  TTag = 1..31;'#10'implementation'#10'procedure P;'#10'const'#10 +
    '  Tage = 30;'#10'var'#10'  A: array[0..9] of Byte;'#10'begin'#10'  if X > Grenze then'#10'    X := 0;'#10 +
    '  S := ''42'' + #13#10;'#10'  X := X * 2 + 1 - 100;'#10'  var B: array[0..4] of Byte;'#10'end;'#10'end.',
    cMagicOn))));
  // Zahlen, die für sich sprechen: DPI-Basis, Bitmasken, Zeiteinheiten, Punktlisten (Marcos Lauf 06.11.2026).
  // Gemeldet bleiben 72 in MulDiv, WaitFor(1000) und Pixelwerte außerhalb einer Punktliste (SetBounds: 4 Zahlen).
  Assert.AreEqual(6, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, 'unit U;'#10'interface'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  X := MulDiv(X, PPI, 96);'#10'  K := EnsureRange(K, 0, $FFFF);'#10 +
    '  M := S div 60 + S mod 3600 + Ms div 1000;'#10'  Q := [P(3.5, 1.5), P(-2, 12.5)];'#10 +
    '  Y := MulDiv(X, PPI, 72);'#10'  T.WaitFor(1000);'#10'  E.SetBounds(12, 9, 360, 23);'#10'end;'#10'end.',
    cMagicOn))));
  // Nahe an einer Bitmaske ist keine: $10000 und $FFFD bleiben gemeldet (nicht über SameValue mit Single).
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, 'unit U;'#10'interface'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Dec(C, $10000);'#10'  Put(R, $FFFD);'#10'end;'#10'end.',
    cMagicOn))));
  TConfigurationParser.Parse('{"rules": {"magic-number": {"allowed": ["42"]}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"allowed" muss eine Liste von Zahlen sein', mIssues[0].Message);
end;

const
  cLineOn = '{ "rules": { "line-length": "hint" } }';
  cLongCall = '  Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, ' +
    'Lager.Verfuegbarkeit(Artikel), Steuer.Satz(Land));';

procedure TStyleRulesTests.LineLengthIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  Ergebnis: Integer;', cLongCall);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource))), 'Standard aus');
  mFindings := TRuleAssert.Findings(TLineLengthRule.Create, mSource, cLineOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Zeile hat 123 Zeichen (Grenze 120).', mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(120, mFindings[0].Range.StartPos.Character, 'Markierung ab der Grenze');
  Assert.AreEqual('Zeile umbrechen', mFindings[0].Fixes[0].Title);
  mSource := Fixed(mSource, mFindings);
  Assert.IsTrue(Pos('Lager.Verfuegbarkeit(Artikel),'#10'    Steuer.Satz(Land));', mSource) > 0, mSource);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource, cLineOn))));
  // Ohne Komma und Operator gibt es keine Stelle zum Umbrechen.
  mFindings := TRuleAssert.Findings(TLineLengthRule.Create, InRoutine('  X: Integer;', '  ' +
    StringOfChar('A', 130) + ';'), cLineOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TStyleRulesTests.LineLengthOptions;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  // max
  mSource := InRoutine('  Summe: Integer;', '  Summe := Erster + Zweiter + Dritter + Vierter + Fuenfter + Sechster;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource, cLineOn))));
  mFindings := TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "max": 40 } } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Zeile hat 70 Zeichen (Grenze 40).', mFindings[0].Message);
  mSource := Fixed(mSource, mFindings);
  Assert.IsTrue(Pos('  Summe := Erster + Zweiter + Dritter'#10'    + Vierter + Fuenfter + Sechster;', mSource) > 0,
    mSource);
  // ignoreStrings (Vorgabe an) und ignoreComments (Vorgabe aus)
  mSource := InRoutine('  S: string;', '  S := ''' + StringOfChar('x', 130) + ''';');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource, cLineOn))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "ignoreStrings": false } } }'))));
  mSource := InRoutine('  X: Integer;', '  X := 1; // ' + StringOfChar('k', 130));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource, cLineOn))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "ignoreComments": true } } }'))));
  // Tabs zählen bis zur nächsten Tabstelle nach format.indentSize.
  mSource := InRoutine('  X: Integer;', #9#9#9#9#9'X := Erster + Zweiter;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "max": 40 } } }'))));
  mFindings := TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "format": { "indentSize": 8 }, "rules": { "line-length": { "severity": "hint", "max": 40 } } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Zeile hat 62 Zeichen (Grenze 40).', mFindings[0].Message);
  // off und exclude
  mSource := InRoutine('  Ergebnis: Integer;', cLongCall);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": "off" } }'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "exclude": ["Generiert/*.pas"] } } }', 'Generiert/U.pas'))));
  TConfigurationParser.Parse('{"rules": {"line-length": {"ignoreStrings": "ja", "ignoreComments": 1}}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.AreEqual('"ignoreStrings" muss true oder false sein', mIssues[0].Message);
end;

procedure TStyleRulesTests.LineLengthCompilerLimit;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'const'#10'  Logo = ''' + StringOfChar('i', 1400) + ''';'#10 +
    'implementation'#10'end.';
  // Unabhängig von max und ignoreStrings immer eine Warnung, ohne Code: Delphi 13 übersetzt solche Zeilen in
  // der IDE noch (#1383, Cm.F2069).
  mFindings := TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "max": 5000 } } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Zeile mit 1412 Zeichen; je nach Delphi-Version bricht der Compiler über 1023 Zeichen ab.',
    mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
  // Über 4095 Zeichen bricht auch Delphi 13 ab (Cm.F2069c): Error mit Code.
  mFindings := TRuleAssert.Findings(TLineLengthRule.Create, StringReplace(mSource, StringOfChar('i', 1400),
    StringOfChar('i', 4084), []), '{ "rules": { "line-length": { "severity": "hint", "max": 5000 } } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Zeile mit 4096 Zeichen; der Compiler bricht über 4095 Zeichen ab (wie F2069).',
    mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  // Genau 1023 Zeichen übersetzt der Compiler noch.
  mSource := 'unit U;'#10'interface'#10'const'#10'  Logo = ''' + StringOfChar('i', 1011) + ''';'#10 +
    'implementation'#10'end.';
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "max": 5000 } } }'))));
  mSource := StringReplace(mSource, StringOfChar('i', 1011), StringOfChar('i', 1012), []);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": { "severity": "hint", "max": 5000 } } }'))), '1024 Zeichen');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, mSource,
    '{ "rules": { "line-length": "off" } }'))));
end;

const
  cFieldOn = '{ "rules": { "public-field": "hint" } }';

function TypeUnit(const ADeclaration: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 + ADeclaration + #10'implementation'#10'end.';
end;

procedure TStyleRulesTests.PublicFieldIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := TypeUnit('  TKunde = class'#10'  public'#10'    Name: string;'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, mSource))), 'Standard aus');
  mFindings := TRuleAssert.Findings(TPublicFieldRule.Create, mSource, cFieldOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Öffentliches Feld Name; eine Property hält die Klasse änderbar.', mFindings[0].Message);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual('Feld kapseln', mFindings[0].Fixes[0].Title);
  mSource := Fixed(mSource, mFindings);
  Assert.AreEqual(TypeUnit('  TKunde = class'#10'  private'#10'    FName: string;'#10'  public'#10 +
    '    property Name: string read FName write FName;'#10'  end;'), mSource);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, mSource, cFieldOn))));
end;

procedure TStyleRulesTests.PublicFieldVariantsAndOptions;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // published mit weiteren Mitgliedern: der Abschnitt bleibt, die Property kommt nach published.
  mSource := TypeUnit('  TKunde = class(TPersistent)'#10'  published'#10'    Name: string;'#10 +
    '    property Ort: string read FOrt;'#10'  private'#10'    FOrt: string;'#10'  end;');
  mFindings := TRuleAssert.Findings(TPublicFieldRule.Create, mSource, cFieldOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(TypeUnit('  TKunde = class(TPersistent)'#10'  published'#10 +
    '    property Ort: string read FOrt;'#10'  private'#10'    FOrt: string;'#10'  private'#10 +
    '    FName: string;'#10'  published'#10'    property Name: string read FName write FName;'#10'  end;'),
    Fixed(mSource, mFindings));
  // Abschnitt ohne Sichtbarkeitswort bei einer Klasse ohne Vorfahren; zwei Namen in einer Zeile ohne Korrektur.
  mFindings := TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit('  TPunkt = class'#10'    X, Y: Integer;'#10 +
    '  end;'), cFieldOn);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Öffentliches Feld Y; eine Property hält die Klasse änderbar.', mFindings[1].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Mit F-Präfix keine Korrektur: die Property hieße anders.
  mFindings := TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit('  TKunde = class'#10'  public'#10 +
    '    FName: string;'#10'  end;'), cFieldOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // includeRecords
  mSource := TypeUnit('  TPunkt = record'#10'    X: Integer;'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, mSource, cFieldOn))));
  mFindings := TRuleAssert.Findings(TPublicFieldRule.Create, mSource,
    '{ "rules": { "public-field": { "severity": "hint", "includeRecords": true } } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(TypeUnit('  TPunkt = record'#10'  private'#10'    FX: Integer;'#10'  public'#10 +
    '    property X: Integer read FX write FX;'#10'  end;'), Fixed(mSource, mFindings));
  // off und exclude
  mSource := TypeUnit('  TKunde = class'#10'  public'#10'    Name: string;'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, mSource,
    '{ "rules": { "public-field": "off" } }'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, mSource,
    '{ "rules": { "public-field": { "severity": "hint", "exclude": ["Daten/*.pas"] } } }', 'Daten/U.pas'))));
end;

procedure TStyleRulesTests.PublicFieldSilentCases;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Designerfelder im Abschnitt ohne Sichtbarkeitswort, private, protected und class var.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit(
    '  TfrmHaupt = class(TForm)'#10'    btnOk: TButton;'#10'  private'#10'    FA: Integer;'#10'  protected'#10 +
    '    FB: Integer;'#10'  strict private'#10'    FC: Integer;'#10'  public'#10'    class var Anzahl: Integer;'#10 +
    '    property A: Integer read FA;'#10'  end;'), cFieldOn))));
  // Hilfsklasse unter protected type bzw. strict private type: ihre Felder erreicht von außen niemand.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit(
    '  TListe = class'#10'  protected type'#10'    TEintrag = class'#10'      Name: string;'#10'    end;'#10 +
    '  strict private type'#10'    TZeile = class'#10'    public'#10'      Text: string;'#10'    end;'#10 +
    '  private'#10'    FA: TEintrag;'#10'  end;'), cFieldOn))));
  // Unter public type zählt die Hilfsklasse weiter.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit(
    '  TListe = class'#10'  public type'#10'    TEintrag = class'#10'      Name: string;'#10'    end;'#10 +
    '  end;'), cFieldOn))));
  TConfigurationParser.Parse('{"rules": {"public-field": {"includeRecords": "ja"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"includeRecords" muss true oder false sein', mIssues[0].Message);
end;

const
  cGlobalOn = '{ "rules": { "global-variable": "hint" } }';

procedure TStyleRulesTests.GlobalVariableIssueExample;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'uses Benutzer;'#10'var'#10'  AktuellerBenutzer: TBenutzer;'#10 +
    'implementation'#10'end.';
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGlobalVariableRule.Create, mSource))), 'Standard aus');
  mFindings := TRuleAssert.Findings(TGlobalVariableRule.Create, mSource, cGlobalOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Globale Variable AktuellerBenutzer ist in jeder Unit sichtbar, die diese verwendet.',
    mFindings[0].Message);
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(19, mFindings[0].Range.EndPos.Character);
  // Korrigiert: im implementation-Teil, dazu eine Funktion im interface.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGlobalVariableRule.Create, 'unit U;'#10'interface'#10 +
    'uses Benutzer;'#10'function AktuellerBenutzer: TBenutzer;'#10'implementation'#10'var'#10 +
    '  GBenutzer: TBenutzer;'#10'function AktuellerBenutzer: TBenutzer;'#10'begin'#10'  Result := GBenutzer;'#10 +
    'end;'#10'end.', cGlobalOn))));
end;

procedure TStyleRulesTests.GlobalVariableFormVariablesAndOptions;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := 'unit U;'#10'interface'#10'type'#10'  TfrmHaupt = class(TForm)'#10'  end;'#10'var'#10 +
    '  frmHaupt: TfrmHaupt;'#10'  A, B: Integer;'#10'threadvar'#10'  Puffer: string;'#10'implementation'#10'end.';
  mFindings := TRuleAssert.Findings(TGlobalVariableRule.Create, mSource, cGlobalOn);
  Assert.AreEqual(3, Integer(Length(mFindings)), 'ohne die Formularvariable');
  Assert.AreEqual('Globale Variable B ist in jeder Unit sichtbar, die diese verwendet.', mFindings[1].Message);
  Assert.AreEqual('Globale Variable Puffer ist in jeder Unit sichtbar, die diese verwendet.', mFindings[2].Message);
  mFindings := TRuleAssert.Findings(TGlobalVariableRule.Create, mSource,
    '{ "rules": { "global-variable": { "severity": "hint", "includeFormVariables": true } } }');
  Assert.AreEqual(4, Integer(Length(mFindings)));
  Assert.AreEqual('Globale Variable frmHaupt ist in jeder Unit sichtbar, die diese verwendet.', mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGlobalVariableRule.Create, mSource,
    '{ "rules": { "global-variable": "off" } }'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGlobalVariableRule.Create, mSource,
    '{ "rules": { "global-variable": { "severity": "hint", "exclude": ["Alt/*.pas"] } } }', 'Alt/U.pas'))));
  // Programme haben keinen interface-Teil.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGlobalVariableRule.Create,
    'program P;'#10'var'#10'  X: Integer;'#10'begin'#10'end.', cGlobalOn))));
  TConfigurationParser.Parse('{"rules": {"global-variable": {"includeFormVariables": 1}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

procedure TStyleRulesTests.MissingBeginEndIssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Das Beispiel aus #1025: if, else und for, je ein Befund am Schlüsselwort.
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, InRoutine('  I: Integer;',
    '  if Kunde.Gesperrt then'#10'    Protokoll.Warnung(''Gesperrt'')'#10'  else'#10'    Speichern(Kunde);'#10 +
    '  for I := 0 to High(Werte) do'#10'    Summe := Summe + Werte[I];'));
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual('if ohne begin … end', mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(4, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual('else ohne begin … end', mFindings[1].Message);
  Assert.AreEqual(9, mFindings[1].Range.StartPos.Line);
  Assert.AreEqual('for ohne begin … end', mFindings[2].Message);
  Assert.AreEqual(11, mFindings[2].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TStyleRulesTests.MissingBeginEndFixesIssueExample;
var
  mSource, mExpected: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  I: Integer;',
    '  if Kunde.Gesperrt then'#10'    Protokoll.Warnung(''Gesperrt'')'#10'  else'#10'    Speichern(Kunde);'#10 +
    '  for I := 0 to High(Werte) do'#10'    Summe := Summe + Werte[I];');
  mExpected := InRoutine('  I: Integer;',
    '  if Kunde.Gesperrt then'#10'  begin'#10'    Protokoll.Warnung(''Gesperrt'');'#10'  end'#10'  else'#10 +
    '  begin'#10'    Speichern(Kunde);'#10'  end;'#10 +
    '  for I := 0 to High(Werte) do'#10'  begin'#10'    Summe := Summe + Werte[I];'#10'  end;');
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource);
  Assert.AreEqual(3, Integer(Length(mFindings)));
  // Drei Reichweiten: die Stelle, die Methode, die Datei (hier nur eine Methode, also zwei Korrekturen).
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(mExpected, Applied(mSource, FixTitled(mFindings[0], 'ganzen Methode')));
  AssertParses(mExpected);
  // Sammelkorrektur (--fix missing-begin-end): nur die Stelle ist sicher, die Methode bleibt eine Auswahl.
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  Assert.IsFalse(mFindings[0].Fixes[1].Safe);
  // Nur die Stelle: ; vor else wandert in den Block (kein E2153).
  Assert.AreEqual(InRoutine('  I: Integer;',
    '  if Kunde.Gesperrt then'#10'  begin'#10'    Protokoll.Warnung(''Gesperrt'');'#10'  end'#10'  else'#10 +
    '    Speichern(Kunde);'#10'  for I := 0 to High(Werte) do'#10'    Summe := Summe + Werte[I];'),
    Fixed(mSource, mFindings));
  TRuleAssert.Silent(TMissingBeginEndRule.Create, mExpected);
  // Zwei Routinen: dazu die Korrektur für die ganze Datei.
  mSource := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  if A then'#10'    B;'#10 +
    '  while C do'#10'    D;'#10'end;'#10'procedure Q;'#10'begin'#10'  with E do'#10'    F;'#10'end;'#10'end.';
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource);
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual(3, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(2, Integer(Length(mFindings[2].Fixes)));
  mExpected := Applied(mSource, FixTitled(mFindings[2], 'ganzen Datei'));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  if A then'#10 +
    '  begin'#10'    B;'#10'  end;'#10'  while C do'#10'  begin'#10'    D;'#10'  end;'#10'end;'#10'procedure Q;'#10 +
    'begin'#10'  with E do'#10'  begin'#10'    F;'#10'  end;'#10'end;'#10'end.', mExpected);
  AssertParses(mExpected);
end;

procedure TStyleRulesTests.MissingBeginEndFixFollowsElsePlacement;
const
  cSameLine = '{ "format": { "elsePlacement": "sameLine" } }';
var
  mSource, mExpected: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('', '  if Kunde.Gesperrt then'#10'    Protokoll.Warnung(''Gesperrt'')'#10'  else'#10 +
    '    Speichern(Kunde);');
  mExpected := InRoutine('', '  if Kunde.Gesperrt then'#10'  begin'#10'    Protokoll.Warnung(''Gesperrt'');'#10 +
    '  end else'#10'  begin'#10'    Speichern(Kunde);'#10'  end;');
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource, cSameLine);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(mExpected, Applied(mSource, FixTitled(mFindings[0], 'ganzen Methode')));
  AssertParses(mExpected);
  // Alles in einer Zeile: else bleibt hinter dem end.
  mSource := InRoutine('', '  if A then B else C;');
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource, cSameLine);
  mExpected := Applied(mSource, FixTitled(mFindings[0], 'ganzen Methode'));
  Assert.Contains(mExpected, '  end else'#10);
  AssertParses(mExpected);
  // Ein Kommentar zwischen Rumpf und else bleibt stehen, else dann in eigener Zeile.
  mSource := InRoutine('', '  if A then'#10'    B // Grund'#10'  else'#10'    C;');
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource, cSameLine);
  mExpected := Applied(mSource, FixTitled(mFindings[0], 'ganzen Methode'));
  Assert.Contains(mExpected, '// Grund');
  AssertParses(mExpected);
end;

procedure TStyleRulesTests.MissingBeginEndSameLineAndNestedFixes;
var
  mSource, mExpected: string;
  mFindings: TArray<TRuleFinding>;
begin
  // then und else in einer Zeile: Rümpfe rücken ein, else steht unter if.
  mSource := InRoutine('  X: Integer;', '  if A then X := 1 else X := 2;');
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  mExpected := InRoutine('  X: Integer;', '  if A then'#10'  begin'#10'    X := 1;'#10'  end'#10'  else'#10'  begin'#10 +
    '    X := 2;'#10'  end;');
  Assert.AreEqual(mExpected, Applied(mSource, FixTitled(mFindings[0], 'ganzen Methode')));
  AssertParses(mExpected);
  // Verschachtelt in einer Zeile: innen zuerst geschlossen, eine Ebene tiefer eingerückt.
  mSource := InRoutine('  I: Integer;', '  for I := 0 to 1 do if A then X := I;');
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  mExpected := InRoutine('  I: Integer;', '  for I := 0 to 1 do'#10'  begin'#10'    if A then'#10'    begin'#10 +
    '      X := I;'#10'    end;'#10'  end;');
  Assert.AreEqual(mExpected, Applied(mSource, FixTitled(mFindings[0], 'ganzen Methode')));
  AssertParses(mExpected);
  Assert.AreEqual(InRoutine('  I: Integer;', '  for I := 0 to 1 do'#10'  begin'#10'    if A then X := I;'#10'  end;'),
    Fixed(mSource, mFindings));
  // Dangling else: das else gehört zum inneren if und bleibt dort.
  mSource := InRoutine('  X: Integer;', '  if A then'#10'    if B then'#10'      X := 1'#10'    else'#10'      X := 2;');
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource);
  Assert.AreEqual(3, Integer(Length(mFindings)));
  mExpected := InRoutine('  X: Integer;', '  if A then'#10'  begin'#10'    if B then'#10'    begin'#10'      X := 1;'#10 +
    '    end'#10'    else'#10'    begin'#10'      X := 2;'#10'    end;'#10'  end;');
  Assert.AreEqual(mExpected, Applied(mSource, FixTitled(mFindings[0], 'ganzen Methode')));
  AssertParses(mExpected);
  // Letzte Anweisung ohne Semikolon vor end, Kommentar hinter dem Rumpf.
  mSource := InRoutine('  X: Integer;', '  while A do'#10'    X := 1 // weiter'#10'  ;');
  mExpected := Fixed(mSource, TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource));
  Assert.AreEqual(InRoutine('  X: Integer;', '  while A do'#10'  begin'#10'    X := 1;'#10'  end // weiter'#10'  ;'),
    mExpected);
  AssertParses(mExpected);
end;

procedure TStyleRulesTests.MissingBeginEndSilentCases;
begin
  TRuleAssert.Silent(TMissingBeginEndRule.Create, InRoutine('  X: Integer;',
    // else if: das innere if braucht keinen eigenen Block.
    '  if A then'#10'  begin'#10'    X := 1;'#10'  end'#10'  else if B then'#10'  begin'#10'    X := 2;'#10'  end'#10 +
    '  else'#10'  begin'#10'    X := 3;'#10'  end;'#10 +
    // repeat, case, try und asm sind schon Blöcke.
    '  repeat'#10'    Inc(X);'#10'  until X > 3;'#10 +
    '  case X of'#10'    1: X := 2;'#10'  else'#10'    X := 0;'#10'  end;'#10 +
    '  if A then'#10'    try'#10'      X := 1;'#10'    finally'#10'      X := 2;'#10'    end;'#10 +
    '  while A do'#10'    case X of'#10'      1: X := 2;'#10'    end;'#10 +
    // Leere Anweisung meldet empty-statement.
    '  if A then ;'#10 +
    // Rumpf mit {$IFDEF}: ohne sichere Lage keine Meldung.
    '  if A then'#10'  {$IFDEF DEBUG}'#10'    X := 1'#10'  {$ELSE}'#10'    X := 2'#10'  {$ENDIF};'));
  // else if: nur der Rumpf des inneren if wird gemeldet.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, InRoutine('  X: Integer;',
    '  if A then'#10'  begin'#10'    X := 1;'#10'  end'#10'  else if B then'#10'    X := 2;')))));
end;

procedure TStyleRulesTests.MissingBeginEndOptions;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := InRoutine('  I: Integer;', '  for I := 0 to 1 do'#10'    if A then Exit;'#10'  case I of'#10 +
    '    1: X := 2;'#10'    2:'#10'    begin'#10'      X := 3;'#10'    end;'#10'  end;'#10'  if B then'#10'    Continue;'#10 +
    '  while C do Inc(I);');
  // Vorgabe: for, if (Exit), if (Continue), while.
  Assert.AreEqual(4, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource))));
  // statements: nur case-Zweige.
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource,
    '{"rules": {"missing-begin-end": {"statements": ["case"]}}}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('case-Zweig ohne begin … end', mFindings[0].Message);
  Assert.AreEqual(Integer(10), mFindings[0].Range.StartPos.Line);
  // allowSingleLineExit: if … then Exit; in einer Zeile erlaubt, Continue in der nächsten Zeile nicht.
  Assert.AreEqual(3, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource,
    '{"rules": {"missing-begin-end": {"allowSingleLineExit": true}}}'))));
  // allowSameLine: jede einzelne Anweisung in derselben Zeile (Exit und Inc).
  mFindings := TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource,
    '{"rules": {"missing-begin-end": {"allowSameLine": true}}}');
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('for ohne begin … end', mFindings[0].Message);
  Assert.AreEqual('if ohne begin … end', mFindings[1].Message);
end;

procedure TStyleRulesTests.MissingBeginEndOverridesRedundantBeginEnd;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := InRoutine('  X: Integer;', '  if A then begin Save(X); end else Load;');
  // missing-begin-end ist an (Vorgabe): redundant-begin-end schweigt, auch wenn es eingeschaltet ist.
  mFindings := TRuleAssert.FindingsOfAll([TRedundantBeginEndRule.Create, TMissingBeginEndRule.Create], mSource,
    cBothBeginEndOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('missing-begin-end', mFindings[0].RuleId);
  // Auch allein gelaufen zählt die Einstellung, nicht die Liste der Regeln.
  TRuleAssert.Silent(TRedundantBeginEndRule.Create, mSource);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRedundantBeginEndRule.Create, mSource, cBothBeginEndOn))));
  // missing-begin-end aus: redundant-begin-end meldet wieder.
  mFindings := TRuleAssert.Findings(TRedundantBeginEndRule.Create, mSource,
    '{ "rules": { "redundant-begin-end": "hint", "missing-begin-end": "off" } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  // Gruppe Stil aus: beide schweigen.
  mSettings := TConfigurationParser.Parse('{ "rules": { "redundant-begin-end": "hint", "group:style": "off" } }',
    mIssues);
  Assert.AreEqual('', TRuleEngine.OverridingRule('redundant-begin-end', nil, mSettings, '', ''));
  mSettings := TConfigurationParser.Parse(cBothBeginEndOn, mIssues);
  Assert.AreEqual('missing-begin-end', TRuleEngine.OverridingRule('redundant-begin-end', nil, mSettings, '', ''));
  // Mit exclude der Gegenregel gilt redundant-begin-end in den ausgenommenen Dateien wieder.
  mSettings := TConfigurationParser.Parse('{ "rules": { "redundant-begin-end": "hint", "missing-begin-end": ' +
    '{ "exclude": ["Alt/**"] } } }', mIssues);
  Assert.AreEqual('', TRuleEngine.OverridingRule('redundant-begin-end', nil, mSettings, 'Alt/U.pas', 'U'));
  Assert.AreEqual('missing-begin-end', TRuleEngine.OverridingRule('redundant-begin-end', nil, mSettings,
    'Neu/U.pas', 'U'));
  Assert.AreEqual('', TRuleEngine.OverridingRule('missing-begin-end', nil, mSettings, '', ''));
end;

procedure TStyleRulesTests.MissingBeginEndOffAndExclude;
var
  mSource: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := InRoutine('  X: Integer;', '  if A then'#10'    X := 1;');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource,
    '{"rules": {"missing-begin-end": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource,
    '{"rules": {"group:style": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource,
    '{"rules": {"missing-begin-end": {"exclude": ["Alt/**"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMissingBeginEndRule.Create, mSource,
    '{"rules": {"missing-begin-end": {"exclude": ["Alt/**"]}}}', 'Neu/U.pas'))));
  // Optionen mit falschem Typ meldet der Konfigurationsparser.
  TConfigurationParser.Parse('{"rules": {"missing-begin-end": {"statements": "if", "allowSameLine": 1}}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
end;

initialization
  TDUnitX.RegisterTestFixture(TStyleRulesTests);

end.
