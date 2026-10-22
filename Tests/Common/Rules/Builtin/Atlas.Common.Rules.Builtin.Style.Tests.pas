unit Atlas.Common.Rules.Builtin.Style.Tests;

// Tests für die Stilregeln (#104): je Regel positiv, negativ und Schnellkorrektur; boolean-assign-if (#935),
// case-insensitive-compare (#936), magic-number (#937), line-length (#938) und public-field (#940).

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Style,
  Atlas.Common.Configuration.Parser,
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

procedure TStyleRulesTests.BooleanAssignIfIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  Betrag: Integer;', '  if Betrag > 0 then'#10'    Result := True'#10'  else'#10 +
    '    Result := False;');
  Findings := TRuleAssert.Findings(TBooleanAssignIfRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Das if weist nur True oder False zu.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Durch Result := Betrag > 0 ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  Betrag: Integer;', '  Result := Betrag > 0;'), Fixed(Source, Findings));
  TRuleAssert.Silent(TBooleanAssignIfRule.Create, Fixed(Source, Findings));
end;

procedure TStyleRulesTests.BooleanAssignIfVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Umgekehrt, mit begin/end, mit not, Exit mit else und Exit als Folgeanweisung.
  Source := InRoutine('  X: Boolean;', '  if Liste.Count = 0 then begin X := False; end else begin X := True; end;');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  X := not (Liste.Count = 0);'),
    Fixed(Source, TRuleAssert.Findings(TBooleanAssignIfRule.Create, Source)));
  Source := InRoutine('  X: Boolean;', '  if not Fertig then X := False else X := True;');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  X := Fertig;'),
    Fixed(Source, TRuleAssert.Findings(TBooleanAssignIfRule.Create, Source)));
  Source := InRoutine('  X: Boolean;', '  if Gefunden(A) then Exit(False) else Exit(True);');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  Exit(not Gefunden(A));'),
    Fixed(Source, TRuleAssert.Findings(TBooleanAssignIfRule.Create, Source)));
  Source := InRoutine('  X: Boolean;', '  if A and B then'#10'    Exit(True);'#10'  Exit(False);');
  Assert.AreEqual(InRoutine('  X: Boolean;', '  Exit(A and B);'),
    Fixed(Source, TRuleAssert.Findings(TBooleanAssignIfRule.Create, Source)));
  // Kommentar im if: Meldung ohne Korrektur.
  Findings := TRuleAssert.Findings(TBooleanAssignIfRule.Create, InRoutine('  X: Boolean;',
    '  if A then X := True // wichtig'#10'  else X := False;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TBooleanAssignIfRule.Create, Source,
    '{"rules": {"boolean-assign-if": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TBooleanAssignIfRule.Create, Source,
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
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  Land, Standard: string;', '  if UpperCase(Land) = UpperCase(Standard) then'#10'    Log;');
  Findings := TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Vergleich über UpperCase; SameText vergleicht ohne Zwischenstrings.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Durch SameText(Land, Standard) ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  Land, Standard: string;', '  if SameText(Land, Standard) then'#10'    Log;'),
    Fixed(Source, Findings));
  TRuleAssert.Silent(TCaseInsensitiveCompareRule.Create, Fixed(Source, Findings));
end;

procedure TStyleRulesTests.CaseInsensitiveCompareVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  S: string;', '  if LowerCase(S) <> ''ja'' then Exit;');
  Assert.AreEqual(InRoutine('  S: string;', '  if not SameText(S, ''ja'') then Exit;'),
    Fixed(Source, TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, Source)));
  Source := InRoutine('  S: string;', '  B := ''JA'' = AnsiUpperCase(Trim(S));');
  Assert.AreEqual(InRoutine('  S: string;', '  B := AnsiSameText(Trim(S), ''JA'');'),
    Fixed(Source, TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, Source)));
  Source := InRoutine('  S: string;', '  B := S.ToUpper = Name.ToUpper();');
  Findings := TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, Source);
  Assert.AreEqual('Vergleich über ToUpper; AnsiSameText vergleicht ohne Zwischenstrings.', Findings[0].Message);
  Assert.AreEqual(InRoutine('  S: string;', '  B := AnsiSameText(S, Name);'), Fixed(Source, Findings));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, Source,
    '{"rules": {"case-insensitive-compare": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCaseInsensitiveCompareRule.Create, Source,
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
  MagicOn = '{ "minConfidence": "low", "rules": { "magic-number": "hint" } }';

procedure TStyleRulesTests.MagicNumberIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  Tage: Integer;', '  if Tage > 42 then'#10'    Mahnen;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, Source))), 'Standard aus');
  Findings := TRuleAssert.Findings(TMagicNumberRule.Create, Source, MagicOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zahl 42 ohne Namen; als Konstante wird klar, was sie bedeutet.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
  Assert.AreEqual('Konstante einführen', Findings[0].Fixes[0].Title);
  Source := Fixed(Source, Findings);
  Assert.IsTrue(Pos('NewConstant = 42;', Source) > 0, Source);
  Assert.IsTrue(Pos('if Tage > NewConstant then', Source) > 0, Source);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, Source, MagicOn))));
end;

procedure TStyleRulesTests.MagicNumberVariantsAndOptions;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  X: Double;', '  X := -7 * 3.5 + $FF;'#10'  Warten(1000);'#10'  X := 2 * 10 - 1;');
  Findings := TRuleAssert.Findings(TMagicNumberRule.Create, Source, MagicOn);
  Assert.AreEqual(4, Integer(Length(Findings)));
  Assert.AreEqual('Zahl -7 ohne Namen; als Konstante wird klar, was sie bedeutet.', Findings[0].Message);
  Assert.AreEqual('Zahl 3.5 ohne Namen; als Konstante wird klar, was sie bedeutet.', Findings[1].Message);
  Assert.AreEqual('Zahl $FF ohne Namen; als Konstante wird klar, was sie bedeutet.', Findings[2].Message);
  Assert.AreEqual('Zahl 1000 ohne Namen; als Konstante wird klar, was sie bedeutet.', Findings[3].Message);
  Findings := TRuleAssert.Findings(TMagicNumberRule.Create, Source,
    '{ "minConfidence": "low", "rules": { "magic-number": { "severity": "hint", "allowed": [1000, -7, 255, 3.5] } } }');
  Assert.AreEqual(3, Integer(Length(Findings)), '2 und 10 nicht mehr erlaubt');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, Source,
    '{ "minConfidence": "low", "rules": { "magic-number": { "severity": "hint", "exclude": ["Tests/*.pas"] } } }',
    'Tests/U.pas'))));
end;

procedure TStyleRulesTests.MagicNumberSilentCases;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Konstanten, Array-Grenzen, Teilbereiche, erlaubte Werte, Zeichen und Strings.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMagicNumberRule.Create, 'unit U;'#10'interface'#10'const'#10'  Grenze = 42;'#10'type'#10 +
    '  TFeld = array[0..41] of Integer;'#10'  TTag = 1..31;'#10'implementation'#10'procedure P;'#10'const'#10 +
    '  Tage = 30;'#10'var'#10'  A: array[0..9] of Byte;'#10'begin'#10'  if X > Grenze then'#10'    X := 0;'#10 +
    '  S := ''42'' + #13#10;'#10'  X := X * 2 + 1 - 100;'#10'  var B: array[0..4] of Byte;'#10'end;'#10'end.',
    MagicOn))));
  TConfigurationParser.Parse('{"rules": {"magic-number": {"allowed": ["42"]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowed" muss eine Liste von Zahlen sein', Issues[0].Message);
end;

const
  LineOn = '{ "rules": { "line-length": "hint" } }';
  LongCall = '  Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, ' +
    'Lager.Verfuegbarkeit(Artikel), Steuer.Satz(Land));';

procedure TStyleRulesTests.LineLengthIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := InRoutine('  Ergebnis: Integer;', LongCall);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source))), 'Standard aus');
  Findings := TRuleAssert.Findings(TLineLengthRule.Create, Source, LineOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zeile hat 123 Zeichen (Grenze 120).', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(120, Findings[0].Range.StartPos.Character, 'Markierung ab der Grenze');
  Assert.AreEqual('Zeile umbrechen', Findings[0].Fixes[0].Title);
  Source := Fixed(Source, Findings);
  Assert.IsTrue(Pos('Lager.Verfuegbarkeit(Artikel),'#10'    Steuer.Satz(Land));', Source) > 0, Source);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source, LineOn))));
  // Ohne Komma und Operator gibt es keine Stelle zum Umbrechen.
  Findings := TRuleAssert.Findings(TLineLengthRule.Create, InRoutine('  X: Integer;', '  ' +
    StringOfChar('A', 130) + ';'), LineOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TStyleRulesTests.LineLengthOptions;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  // max
  Source := InRoutine('  Summe: Integer;', '  Summe := Erster + Zweiter + Dritter + Vierter + Fuenfter + Sechster;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source, LineOn))));
  Findings := TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "max": 40 } } }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zeile hat 70 Zeichen (Grenze 40).', Findings[0].Message);
  Source := Fixed(Source, Findings);
  Assert.IsTrue(Pos('  Summe := Erster + Zweiter + Dritter'#10'    + Vierter + Fuenfter + Sechster;', Source) > 0,
    Source);
  // ignoreStrings (Vorgabe an) und ignoreComments (Vorgabe aus)
  Source := InRoutine('  S: string;', '  S := ''' + StringOfChar('x', 130) + ''';');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source, LineOn))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "ignoreStrings": false } } }'))));
  Source := InRoutine('  X: Integer;', '  X := 1; // ' + StringOfChar('k', 130));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source, LineOn))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "ignoreComments": true } } }'))));
  // Tabs zählen bis zur nächsten Tabstelle nach format.indentSize.
  Source := InRoutine('  X: Integer;', #9#9#9#9#9'X := Erster + Zweiter;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "max": 40 } } }'))));
  Findings := TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "format": { "indentSize": 8 }, "rules": { "line-length": { "severity": "hint", "max": 40 } } }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zeile hat 62 Zeichen (Grenze 40).', Findings[0].Message);
  // off und exclude
  Source := InRoutine('  Ergebnis: Integer;', LongCall);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": "off" } }'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "exclude": ["Generiert/*.pas"] } } }', 'Generiert/U.pas'))));
  TConfigurationParser.Parse('{"rules": {"line-length": {"ignoreStrings": "ja", "ignoreComments": 1}}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.AreEqual('"ignoreStrings" muss true oder false sein', Issues[0].Message);
end;

procedure TStyleRulesTests.LineLengthCompilerLimit;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := 'unit U;'#10'interface'#10'const'#10'  Logo = ''' + StringOfChar('i', 1400) + ''';'#10 +
    'implementation'#10'end.';
  // Unabhängig von max und ignoreStrings immer ein Error.
  Findings := TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "max": 5000 } } }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zeile mit 1412 Zeichen; der Compiler bricht über 1023 Zeichen ab (wie F2069).',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  // Genau 1023 Zeichen übersetzt der Compiler noch.
  Source := 'unit U;'#10'interface'#10'const'#10'  Logo = ''' + StringOfChar('i', 1011) + ''';'#10 +
    'implementation'#10'end.';
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "max": 5000 } } }'))));
  Source := StringReplace(Source, StringOfChar('i', 1011), StringOfChar('i', 1012), []);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": { "severity": "hint", "max": 5000 } } }'))), '1024 Zeichen');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLineLengthRule.Create, Source,
    '{ "rules": { "line-length": "off" } }'))));
end;

const
  FieldOn = '{ "rules": { "public-field": "hint" } }';

function TypeUnit(const ADeclaration: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 + ADeclaration + #10'implementation'#10'end.';
end;

procedure TStyleRulesTests.PublicFieldIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := TypeUnit('  TKunde = class'#10'  public'#10'    Name: string;'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, Source))), 'Standard aus');
  Findings := TRuleAssert.Findings(TPublicFieldRule.Create, Source, FieldOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Öffentliches Feld Name; eine Property hält die Klasse änderbar.', Findings[0].Message);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('Feld kapseln', Findings[0].Fixes[0].Title);
  Source := Fixed(Source, Findings);
  Assert.AreEqual(TypeUnit('  TKunde = class'#10'  private'#10'    FName: string;'#10'  public'#10 +
    '    property Name: string read FName write FName;'#10'  end;'), Source);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, Source, FieldOn))));
end;

procedure TStyleRulesTests.PublicFieldVariantsAndOptions;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // published mit weiteren Mitgliedern: der Abschnitt bleibt, die Property kommt nach published.
  Source := TypeUnit('  TKunde = class(TPersistent)'#10'  published'#10'    Name: string;'#10 +
    '    property Ort: string read FOrt;'#10'  private'#10'    FOrt: string;'#10'  end;');
  Findings := TRuleAssert.Findings(TPublicFieldRule.Create, Source, FieldOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(TypeUnit('  TKunde = class(TPersistent)'#10'  published'#10 +
    '    property Ort: string read FOrt;'#10'  private'#10'    FOrt: string;'#10'  private'#10 +
    '    FName: string;'#10'  published'#10'    property Name: string read FName write FName;'#10'  end;'),
    Fixed(Source, Findings));
  // Abschnitt ohne Sichtbarkeitswort bei einer Klasse ohne Vorfahren; zwei Namen in einer Zeile ohne Korrektur.
  Findings := TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit('  TPunkt = class'#10'    X, Y: Integer;'#10 +
    '  end;'), FieldOn);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Öffentliches Feld Y; eine Property hält die Klasse änderbar.', Findings[1].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Mit F-Präfix keine Korrektur: die Property hieße anders.
  Findings := TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit('  TKunde = class'#10'  public'#10 +
    '    FName: string;'#10'  end;'), FieldOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // includeRecords
  Source := TypeUnit('  TPunkt = record'#10'    X: Integer;'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, Source, FieldOn))));
  Findings := TRuleAssert.Findings(TPublicFieldRule.Create, Source,
    '{ "rules": { "public-field": { "severity": "hint", "includeRecords": true } } }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(TypeUnit('  TPunkt = record'#10'  private'#10'    FX: Integer;'#10'  public'#10 +
    '    property X: Integer read FX write FX;'#10'  end;'), Fixed(Source, Findings));
  // off und exclude
  Source := TypeUnit('  TKunde = class'#10'  public'#10'    Name: string;'#10'  end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, Source,
    '{ "rules": { "public-field": "off" } }'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, Source,
    '{ "rules": { "public-field": { "severity": "hint", "exclude": ["Daten/*.pas"] } } }', 'Daten/U.pas'))));
end;

procedure TStyleRulesTests.PublicFieldSilentCases;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Designerfelder im Abschnitt ohne Sichtbarkeitswort, private, protected und class var.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPublicFieldRule.Create, TypeUnit(
    '  TfrmHaupt = class(TForm)'#10'    btnOk: TButton;'#10'  private'#10'    FA: Integer;'#10'  protected'#10 +
    '    FB: Integer;'#10'  strict private'#10'    FC: Integer;'#10'  public'#10'    class var Anzahl: Integer;'#10 +
    '    property A: Integer read FA;'#10'  end;'), FieldOn))));
  TConfigurationParser.Parse('{"rules": {"public-field": {"includeRecords": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"includeRecords" muss true oder false sein', Issues[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TStyleRulesTests);

end.
