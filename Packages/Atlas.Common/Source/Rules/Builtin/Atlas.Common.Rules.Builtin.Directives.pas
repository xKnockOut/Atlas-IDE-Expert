unit Atlas.Common.Rules.Builtin.Directives;

// Regeln für Direktiven (#909):
//   compiler-warnings-disabled        (#972, Gruppe Robustheit und Muster)
//                                     {$WARNINGS OFF}, {$HINTS OFF}, {$WARN X
//                                     OFF}, {$R-}, {$Q-} und die langen Formen
//                                     ohne spätere Wiederherstellung (ON, +,
//                                     DEFAULT, ERROR oder {$POPOPT}); ein
//                                     Gegenstück im anderen Zweig desselben
//                                     {$IF} ist gewollt. Option allow.
// Gruppe Compiler vorab:
//   conditional-directive-unbalanced  Bedingte Direktiven unvollständig oder
//                                     unbekannt (#989): {$IF…} ohne {$ENDIF}
//                                     (E2095, E2280), {$ELSE}/{$ENDIF} ohne
//                                     Gegenstück (E2279), fehlendes oder
//                                     ungültiges Symbol (E2173), unbekannte
//                                     Direktive oder {$WARN}-Bezeichner (E1030,
//                                     vor Delphi 13 W1030),
//                                     {$POPOPT}/{$PUSHOPT} ohne Gegenstück
//                                     (W1078, W1079), ungültiger Wert für
//                                     {$ALIGN} (E2573).
//   directive-typo                    Unbekanntes Wort an der Stelle einer
//                                     Direktive nach einem Routinenkopf
//                                     (overide;) bzw. nach einer Property
//                                     (defualt;), mit Vorschlag (E2070, #1068).
//   compiler-directive-invalid        Compileranweisungen, die dcc ablehnt oder
//                                     selbst meldet (#1379): {$MESSAGE WARN|HINT}
//                                     (W1054, H1054), {$WEAKPACKAGEUNIT ON} mit
//                                     {$DENYPACKAGEUNIT ON} (E2222),
//                                     {$DESIGNONLY}/{$RUNONLY} in einer Unit
//                                     (E2224), {$OBJTYPENAME} an einem Alias
//                                     (E2560), {$CODEPAGE} über 65535 (E1030),
//                                     fehlende Datei aus {$I} (F1026) bzw. {$R}
//                                     (E1026), Include-Datei, die sich über
//                                     unbedingte {$I} selbst einbindet (E2245).
//
// Die Regel liest die Direktiven-Token des ganzen Textes, auch in inaktiven
// Zweigen; dort zählt Delphi die Verschachtelung ebenfalls. Unbekannte Namen
// prüft sie nicht in Zweigen, deren Bedingung FPC abfragt ({$IFDEF FPC}{$MODE
// DELPHI}{$ENDIF}). {$PUSHOPT}/{$POPOPT} prüft sie nur, wenn keines davon in
// einem bedingten Zweig steht.
//
// compiler-directive-invalid prüft nur Direktiven außerhalb bedingter Zweige:
// Welcher Zweig gilt, weiß die Regel nicht, und dcc meldet nur aus geltenden.
// Dateien sucht sie neben der Unit (TRuleContext.FileExists) und über die
// Suchpfade des Projekts (IRuleUnitLookup.FindFile); ohne sichere Aussage
// schweigt sie. {$R Name.res Name.rc}, Formulare und Masken ({$R *.res}) prüft
// sie nicht, ebenso keine .res, neben der eine .rc gleichen Namens liegt (die
// IDE übersetzt sie vor dem Compiler). {$MESSAGE} ohne Art und mit ERROR/FATAL
// ist noch nicht mit dcc abgeglichen und bleibt still.
//
// directive-typo liest die Directive-Knoten des Syntaxbaums: Der Parser legt
// sie auch für unbekannte Wörter mit ';' dahinter an. Methodenzuordnungen
// (procedure IFoo.Bar = Baz;) übergeht sie (#1325). In Zweigen, deren
// Bedingung FPC abfragt, bleibt sie still (FPC kennt weitere Direktiven wie
// nostackframe).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cConditionalDirectiveUnbalancedRuleId = 'conditional-directive-unbalanced';
  cDirectiveTypoRuleId = 'directive-typo';
  cCompilerWarningsDisabledRuleId = 'compiler-warnings-disabled';
  cCompilerDirectiveInvalidRuleId = 'compiler-directive-invalid';

type
  TConditionalDirectiveUnbalancedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDirectiveTypoRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCompilerWarningsDisabledRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCompilerDirectiveInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDirectiveRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Text.Fuzzy,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDirectivesText = (ConditionalTitle, FixTypo, AddEndif, NoIf, RemoveExtra, NoSymbol, BadSymbol, BadAlign,
    UnknownDirectiveGuess, UnknownDirectiveCode, UnknownWarningGuess, UnknownWarning, NeverClosed, AfterElse,
    PopWithoutPush, PushWithoutPop, TypoTitle, UnknownMeant, ReplaceWith, UnknownDirective, WarningsOff, HintsOff,
    RangeOff, OverflowOff, WarningOff, OffTitle, Restore, DirectiveTitle, ResourceMissing, IncludeMissing,
    RecursiveInclude, MessageWarn, MessageHint, WeakDeny, PackageOnly, ObjTypeName, BadCodepage);

const
  cTexts: array[TDirectivesText] of TAtlasText = (
    (De: 'Bedingte Direktiven unvollständig oder unbekannt'; En: 'Conditional directives incomplete or unknown'),
    (De: 'Tippfehler korrigieren: %s'; En: 'Fix typo: %s'),
    (De: '{$ENDIF} nach Zeile %d ergänzen'; En: 'Add {$ENDIF} after line %d'),
    (De: '{$%s} ohne passendes {$IF…} (wie E2279).'; En: '{$%s} without matching {$IF…} (like E2279).'),
    (De: 'Überzähliges {$%s} entfernen'; En: 'Remove superfluous {$%s}'),
    (De: '{$%s} ohne Symbol (wie E2173).'; En: '{$%s} without symbol (like E2173).'),
    (De: '%s ist kein gültiges Symbol für {$%s} (wie E2173).'; En: '%s is not a valid symbol for {$%s} (like E2173).'),
    (De: 'Ungültiger Wert %s für {$ALIGN}; erlaubt sind ON, OFF, 1, 2, 4, 8 und 16 (wie E2573).';
     En: 'Invalid value %s for {$ALIGN}; ON, OFF, 1, 2, 4, 8 and 16 are allowed (like E2573).'),
    (De: 'Unbekannte Direktive {$%s}; gemeint ist wohl {$%s} (wie %s).';
     En: 'Unknown directive {$%s}; probably {$%s} is meant (like %s).'),
    (De: 'Unbekannte Direktive {$%s} (wie %s).'; En: 'Unknown directive {$%s} (like %s).'),
    (De: 'Unbekannte Warnung %s in {$WARN}; gemeint ist wohl %s (wie %s).';
     En: 'Unknown warning %s in {$WARN}; probably %s is meant (like %s).'),
    (De: 'Unbekannte Warnung %s in {$WARN} (wie %s).'; En: 'Unknown warning %s in {$WARN} (like %s).'),
    (De: '%s wird nie geschlossen; der Rest der Datei hängt an %s (wie %s).';
     En: '%s is never closed; the rest of the file depends on %s (like %s).'),
    (De: '{$%s} nach {$ELSE} von %s aus Zeile %d (wie E2279).';
     En: '{$%s} after {$ELSE} of %s from line %d (like E2279).'),
    (De: '{$POPOPT} ohne vorheriges {$PUSHOPT} (wie W1078).';
     En: '{$POPOPT} without preceding {$PUSHOPT} (like W1078).'),
    (De: '{$PUSHOPT} ohne passendes {$POPOPT} (wie W1079).'; En: '{$PUSHOPT} without matching {$POPOPT} (like W1079).'),
    (De: 'Unbekannte Direktive (Tippfehler)'; En: 'Unknown directive (typo)'),
    (De: 'Unbekannte Direktive %s; gemeint ist %s (wie E2070).'; En: 'Unknown directive %s; %s is meant (like E2070).'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'),
    (De: 'Unbekannte Direktive %s (wie E2070).'; En: 'Unknown directive %s (like E2070).'),
    (De: 'WARNINGS bleibt bis zum Ende der Unit aus; alle späteren Warnungen fehlen.';
     En: 'WARNINGS stays off until the end of the unit; all later warnings are missing.'),
    (De: 'HINTS bleibt bis zum Ende der Unit aus; alle späteren Hinweise fehlen.';
     En: 'HINTS stays off until the end of the unit; all later hints are missing.'),
    (De: 'Die Bereichsprüfung bleibt bis zum Ende der Unit aus; Überschreitungen fallen nicht mehr auf.';
     En: 'Range checking stays off until the end of the unit; out-of-range values go unnoticed.'),
    (De: 'Die Überlaufprüfung bleibt bis zum Ende der Unit aus; Überläufe fallen nicht mehr auf.';
     En: 'Overflow checking stays off until the end of the unit; overflows go unnoticed.'),
    (De: 'Die Warnung %s bleibt bis zum Ende der Unit aus.'; En: 'The warning %s stays off until the end of the unit.'),
    (De: 'Compiler-Warnungen oder Prüfungen bis zum Ende der Unit abgeschaltet';
     En: 'Compiler warnings or checks switched off until the end of the unit'),
    (De: 'Nach dem nächsten Block wiederherstellen'; En: 'Restore after the next block'),
    (De: 'Compileranweisung ungültig oder Datei aus {$I}/{$R} fehlt';
     En: 'Compiler directive invalid or file from {$I}/{$R} missing'),
    (De: 'Ressourcendatei %s nicht gefunden (wie E1026).'; En: 'Resource file %s not found (like E1026).'),
    (De: 'Include-Datei %s nicht gefunden (wie F1026).'; En: 'Include file %s not found (like F1026).'),
    (De: 'Rekursive Include-Datei: %s (wie E2245).'; En: 'Recursive include file: %s (like E2245).'),
    (De: '{$MESSAGE WARN}: %s (wie W1054).'; En: '{$MESSAGE WARN}: %s (like W1054).'),
    (De: '{$MESSAGE HINT}: %s (wie H1054).'; En: '{$MESSAGE HINT}: %s (like H1054).'),
    (De: '{$WEAKPACKAGEUNIT ON} und {$DENYPACKAGEUNIT ON} schließen sich aus (wie E2222).';
     En: '{$WEAKPACKAGEUNIT ON} and {$DENYPACKAGEUNIT ON} exclude each other (like E2222).'),
    (De: '{$%s} ist nur in einem Package (.dpk) erlaubt, nicht in einer Unit (wie E2224).';
     En: '{$%s} is only allowed in a package (.dpk), not in a unit (like E2224).'),
    (De: '{$OBJTYPENAME} gilt nicht für den Alias %s; erlaubt sind nur globale Typen, die kein Alias sind (wie E2560).';
     En: '{$OBJTYPENAME} does not apply to the alias %s; only global types that are not aliases are allowed (like ' +
      'E2560).'),
    (De: '%s ist keine Codepage für {$CODEPAGE} (wie E1030).';
     En: '%s is not a codepage for {$CODEPAGE} (like E1030).'));

{$SCOPEDENUMS OFF}

const
  /// <summary>BDS-Nummer von Delphi 13: ab hier ist eine unbekannte Direktive ein Fehler (E1030, #1382).</summary>
  cDelphi13 = '37.0';

type
  /// <summary>Offenes {$IF…} mit seiner Kette aus {$ELSEIF}/{$ELSE}.</summary>
  TOpenConditional = record
    /// <summary>Index der öffnenden Direktive in den Token.</summary>
    Opening: Integer;
    /// <summary>Index der letzten Direktive der Kette.</summary>
    Last: Integer;
    Name: string;
    /// <summary>Bedingung für die Meldung, z. B. DEBUG oder not DEBUG.</summary>
    Condition: string;
    HadElse: Boolean;
    /// <summary>Fragt diese oder eine umschließende Kette FPC ab?</summary>
    Fpc: Boolean;
  end;

/// <summary>Leerraum zu einem Zeichen zusammengefasst, höchstens AMax Zeichen.</summary>
function Compact(const AText: string; AMax: Integer): string;
var
  mCh: Char;
  mSpace: Boolean;
begin
  Result := '';
  mSpace := False;
  for mCh in Trim(AText) do
  begin
    if CharInSet(mCh, [' ', #9, #10, #13]) then
    begin
      mSpace := True;
    end
    else
    begin
      if mSpace then
      begin
        Result := Result + ' ';
      end;
      mSpace := False;
      Result := Result + mCh;
    end;
  end;
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, 1, AMax - 1) + '…';
  end;
end;

/// <summary>Erstes Wort bis Leerraum oder Komma.</summary>
function FirstWord(const AText: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(AText)) and not CharInSet(AText[mIndex], [' ', #9, #10, #13, ',']) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(AText, 1, mIndex - 1);
end;

/// <summary>Kommt ein Bezeichner vor, der mit FPC beginnt (FPC, FPC_FULLVERSION)?</summary>
function MentionsFpc(const AText: string): Boolean;
var
  mIndex, mStart: Integer;
begin
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_']) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      begin
        Inc(mIndex);
      end;
      if StartsText('FPC', Copy(AText, mStart, mIndex - mStart)) then
      begin
        Exit(True);
      end;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
  Result := False;
end;

/// <summary>Ersatz in der Schreibweise des Originals: groß bleibt groß, sonst klein.</summary>
function LikeOriginal(const AOriginal, AReplacement: string): string;
begin
  if AOriginal = UpperCase(AOriginal) then
  begin
    Result := UpperCase(AReplacement);
  end
  else
  begin
    Result := LowerCase(AReplacement);
  end;
end;

{ TConditionalDirectiveUnbalancedRule }

function TConditionalDirectiveUnbalancedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cConditionalDirectiveUnbalancedRuleId, TRuleSeverity.Error,
    cTexts[TDirectivesText.ConditionalTitle].Text);
end;

procedure TConditionalDirectiveUnbalancedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mStack: TArray<TOpenConditional>;
  mOptions: TArray<Integer>;
  mOptionInBranch: Boolean;
  mLineBreak, mUnknownCode: string;

  function RangeOf(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(mTokens[AIndex].StartPos, mTokens[AIndex].EndPos);
  end;

  function InFpcBranch: Boolean;
  begin
    Result := (mStack <> nil) and mStack[High(mStack)].Fpc;
  end;

  /// <summary>Korrektur, die das Wort AWord (ab Zeichen AFrom der Direktive) durch AReplacement in seiner
  /// Schreibweise ersetzt; AShown steht im Titel.</summary>
  function ReplaceFix(AIndex: Integer; const AWord, AReplacement, AShown: string; AFrom: Integer;
    out AFix: TRuleFix): Boolean;
  var
    mAt: Integer;
    mStart: TTextPosition;
  begin
    AFix := Default(TRuleFix);
    mAt := PosEx(AWord, mTokens[AIndex].Text, AFrom);
    Result := (mAt > 0) and (mTokens[AIndex].StartPos.Line = mTokens[AIndex].EndPos.Line);
    if not Result then
    begin
      Exit;
    end;
    mStart := TTextPosition.Create(mTokens[AIndex].StartPos.Line, mTokens[AIndex].StartPos.Character + mAt - 1);
    AFix := TRuleFix.Create(cTexts[TDirectivesText.FixTypo].Fmt([AShown]),
      [TRuleEdit.Create(TTextRange.Create(mStart, TTextPosition.Create(mStart.Line, mStart.Character + Length(AWord))),
      LikeOriginal(AWord, AReplacement))]);
  end;

  /// <summary>Entfernt die Direktive AIndex, steht sie allein in der Zeile, mitsamt der Zeile.</summary>
  function RemoveFix(AIndex: Integer; const ATitle: string): TRuleFix;
  var
    mLine: Integer;
    mAlone: Boolean;
  begin
    mLine := mTokens[AIndex].StartPos.Line;
    mAlone := mTokens[AIndex].EndPos.Line = mLine;
    if mAlone and (AIndex > 0) then
    begin
      mAlone := mTokens[AIndex - 1].EndPos.Line < mLine;
    end;
    if mAlone and (AIndex < High(mTokens)) then
    begin
      mAlone := mTokens[AIndex + 1].StartPos.Line > mLine;
    end;
    if mAlone then
    begin
      Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(TTextRange.Create(mLine, 0, mLine + 1, 0), '')]);
    end
    else
    begin
      Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(RangeOf(AIndex), '')]);
    end;
  end;

  /// <summary>{$ENDIF} vor der ersten Leerzeile hinter der Kette; False ohne Leerzeile.</summary>
  function EndifFix(const AOpen: TOpenConditional; out AFix: TRuleFix): Boolean;
  var
    mIndex, mLine: Integer;
  begin
    AFix := Default(TRuleFix);
    for mIndex := AOpen.Last + 1 to High(mTokens) do
    begin
      if mTokens[mIndex].StartPos.Line > mTokens[mIndex - 1].EndPos.Line + 1 then
      begin
        mLine := mTokens[mIndex - 1].EndPos.Line;
        AFix := TRuleFix.Create(cTexts[TDirectivesText.AddEndif].Fmt([mLine + 1]),
          [TRuleEdit.Create(TTextRange.Create(mLine + 1, 0, mLine + 1, 0),
          StringOfChar(' ', mTokens[AOpen.Opening].StartPos.Character) + '{$ENDIF}' + mLineBreak)]);
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure Stray(AIndex: Integer; const AName: string);
  begin
    AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.NoIf].Fmt([AName]), TRuleConfidence.High,
      [RemoveFix(AIndex, cTexts[TDirectivesText.RemoveExtra].Fmt([AName]))]);
  end;

  procedure CheckSymbol(AIndex: Integer; const AName, ARest: string);
  var
    mSymbol: string;
  begin
    mSymbol := FirstWord(ARest);
    if mSymbol = '' then
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.NoSymbol].Fmt([AName]), TRuleConfidence.High);
    end
    else if not IsValidIdent(mSymbol) then
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.BadSymbol].Fmt([mSymbol, AName]),
        TRuleConfidence.High);
    end;
  end;

  procedure CheckAlignValue(AIndex: Integer; const AValue: string; ALong: Boolean);
  begin
    if AValue = '' then
    begin
      Exit;
    end;
    if MatchText(AValue, ['1', '2', '4', '8', '16']) then
    begin
      Exit;
    end;
    if ALong and MatchText(AValue, ['ON', 'OFF']) then
    begin
      Exit;
    end;
    if not ALong and not CharInSet(AValue[1], ['0'..'9']) then
    begin
      Exit;
    end;
    AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.BadAlign].Fmt([AValue]), TRuleConfidence.High);
  end;

  procedure CheckShortSwitches(AIndex: Integer; const ABody: string);
  var
    mPart: string;
  begin
    for mPart in SplitString(ABody, ',') do
    begin
      if SameText(TDirectiveNames.LeadingName(Trim(mPart)), 'A') then
      begin
        CheckAlignValue(AIndex, Trim(Copy(Trim(mPart), 2, MaxInt)), False);
      end;
    end;
  end;

  procedure CheckUnknown(AIndex: Integer; const AName: string);
  var
    mClosest: string;
    mFix: TRuleFix;
  begin
    if InFpcBranch or TDirectiveNames.IsDirective(AName) then
    begin
      Exit;
    end;
    mClosest := TTextFuzzy.Closest(AName, TDirectiveNames.Directives);
    if (mClosest <> '') and ReplaceFix(AIndex, AName, mClosest, '{$' + mClosest + '}', 1, mFix) then
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.UnknownDirectiveGuess].Fmt(
        [AName, mClosest, mUnknownCode]), TRuleConfidence.High, [mFix]);
    end
    else
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.UnknownDirectiveCode].Fmt([AName, mUnknownCode]),
        TRuleConfidence.High);
    end;
  end;

  /// <summary>AFrom: erstes Zeichen hinter WARN in der Direktive.</summary>
  procedure CheckWarn(AIndex, AFrom: Integer; const ARest: string);
  var
    mId, mClosest: string;
    mFix: TRuleFix;
  begin
    mId := TDirectiveNames.LeadingName(ARest);
    if (mId = '') or InFpcBranch or TDirectiveNames.IsWarning(mId) then
    begin
      Exit;
    end;
    mClosest := TTextFuzzy.Closest(mId, TDirectiveNames.Warnings);
    if (mClosest <> '') and ReplaceFix(AIndex, mId, mClosest, mClosest, AFrom, mFix) then
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.UnknownWarningGuess].Fmt(
        [mId, mClosest, mUnknownCode]), TRuleConfidence.High, [mFix]);
    end
    else
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.UnknownWarning].Fmt([mId, mUnknownCode]),
        TRuleConfidence.High);
    end;
  end;

  procedure Open(AIndex: Integer; const AName, ARest: string);
  var
    mItem: TOpenConditional;
  begin
    mItem.Opening := AIndex;
    mItem.Last := AIndex;
    mItem.Name := AName;
    mItem.HadElse := False;
    mItem.Fpc := InFpcBranch or MentionsFpc(ARest);
    if AName = 'IFNDEF' then
    begin
      mItem.Condition := 'not ' + FirstWord(ARest);
    end
    else if AName = 'IFDEF' then
    begin
      mItem.Condition := FirstWord(ARest);
    end
    else
    begin
      mItem.Condition := Compact(ARest, 40);
    end;
    mStack := mStack + [mItem];
  end;

  procedure Unclosed(const AItem: TOpenConditional; ATop: Boolean);
  var
    mCode: string;
    mMessage: string;
    mFix: TRuleFix;
  begin
    mCode := 'E2095';
    if AItem.Name = 'IF' then
    begin
      mCode := 'E2280';
    end;
    mMessage := cTexts[TDirectivesText.NeverClosed].Fmt(
      [Compact(mTokens[AItem.Opening].Text, 60), AItem.Condition, mCode]);
    if ATop and EndifFix(AItem, mFix) then
    begin
      AReport.Add(RangeOf(AItem.Opening), mMessage, TRuleConfidence.High, [mFix]);
    end
    else
    begin
      AReport.Add(RangeOf(AItem.Opening), mMessage, TRuleConfidence.High);
    end;
  end;

  /// <summary>{$ELSE} oder {$ELSEIF} an AIndex.</summary>
  procedure VisitElse(AIndex: Integer; const AName, ARest: string);
  begin
    if mStack = nil then
    begin
      Stray(AIndex, AName);
    end
    else if mStack[High(mStack)].HadElse then
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.AfterElse].Fmt(
        [AName, Compact(mTokens[mStack[High(mStack)].Opening].Text, 60),
        mTokens[mStack[High(mStack)].Opening].StartPos.Line + 1]), TRuleConfidence.High);
    end
    else
    begin
      mStack[High(mStack)].HadElse := AName = 'ELSE';
      mStack[High(mStack)].Last := AIndex;
      mStack[High(mStack)].Fpc := mStack[High(mStack)].Fpc or MentionsFpc(ARest);
    end;
  end;

  /// <summary>{$ENDIF} oder {$IFEND} an AIndex.</summary>
  procedure VisitEnd(AIndex: Integer; const AName: string);
  begin
    if mStack = nil then
    begin
      Stray(AIndex, AName);
    end
    else
    begin
      SetLength(mStack, Length(mStack) - 1);
    end;
  end;

  /// <summary>Direktiven ohne Bedingung: Symbole, Optionen, Schalter.</summary>
  procedure VisitOther(AIndex: Integer; const ABody, AName, ARest: string);
  begin
    if MatchStr(AName, ['DEFINE', 'UNDEF']) then
    begin
      CheckSymbol(AIndex, AName, ARest);
    end
    else if MatchStr(AName, ['PUSHOPT', 'POPOPT']) then
    begin
      mOptions := mOptions + [AIndex];
      mOptionInBranch := mOptionInBranch or (mStack <> nil);
    end
    else if AName = 'ALIGN' then
    begin
      CheckAlignValue(AIndex, FirstWord(ARest), True);
    end
    else if AName = 'WARN' then
    begin
      CheckWarn(AIndex, Pos(TDirectiveNames.LeadingName(ABody), mTokens[AIndex].Text) + Length(AName), ARest);
    end
    else if Length(AName) = 1 then
    begin
      CheckShortSwitches(AIndex, ABody);
    end
    else
    begin
      CheckUnknown(AIndex, TDirectiveNames.LeadingName(ABody));
    end;
  end;

  procedure Visit(AIndex: Integer);
  var
    mBody, mName, mRest: string;
  begin
    mBody := TDirectiveNames.Body(mTokens[AIndex].Text);
    mName := UpperCase(TDirectiveNames.LeadingName(mBody));
    mRest := Trim(Copy(mBody, Length(mName) + 1, MaxInt));
    if mName = '' then
    begin
      Exit;
    end;
    if MatchStr(mName, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
    begin
      if MatchStr(mName, ['IFDEF', 'IFNDEF']) then
      begin
        CheckSymbol(AIndex, mName, mRest);
      end;
      Open(AIndex, mName, mRest);
    end
    else if MatchStr(mName, ['ELSE', 'ELSEIF']) then
    begin
      VisitElse(AIndex, mName, mRest);
    end
    else if MatchStr(mName, ['ENDIF', 'IFEND']) then
    begin
      VisitEnd(AIndex, mName);
    end
    else
    begin
      VisitOther(AIndex, mBody, mName, mRest);
    end;
  end;

  procedure CheckOptionStack;
  var
    mPushes: TArray<Integer>;
    mIndex: Integer;
  begin
    if mOptionInBranch then
    begin
      Exit;
    end;
    mPushes := nil;
    for mIndex in mOptions do
    begin
      if SameText(TDirectiveNames.LeadingName(TDirectiveNames.Body(mTokens[mIndex].Text)), 'PUSHOPT') then
      begin
        mPushes := mPushes + [mIndex];
      end
      else if mPushes = nil then
      begin
        AReport.Add(RangeOf(mIndex), cTexts[TDirectivesText.PopWithoutPush].Text, TRuleConfidence.High);
      end
      else
      begin
        SetLength(mPushes, Length(mPushes) - 1);
      end;
    end;
    for mIndex in mPushes do
    begin
      AReport.Add(RangeOf(mIndex), cTexts[TDirectivesText.PushWithoutPop].Text, TRuleConfidence.High);
    end;
  end;

var
  mIndex: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mLineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
  begin
    mLineBreak := #13#10;
  end;
  mStack := nil;
  mOptions := nil;
  mOptionInBranch := False;
  // Delphi 13 meldet unbekannte Direktiven und {$WARN}-Bezeichner als Fehler E1030, ältere Versionen als W1030
  // (#1382).
  mUnknownCode := 'W1030';
  if TLanguageFeatures.IsAtLeast(AContext.DelphiVersion, cDelphi13) then
  begin
    mUnknownCode := 'E1030';
  end;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      Visit(mIndex);
    end;
  end;
  for mIndex := 0 to High(mStack) do
  begin
    Unclosed(mStack[mIndex], mIndex = High(mStack));
  end;
  CheckOptionStack;
end;

{ TDirectiveTypoRule }

function TDirectiveTypoRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDirectiveTypoRuleId, TRuleSeverity.Error, cTexts[TDirectivesText.TypoTitle].Text);
end;

/// <summary>Offsets der Token in Zweigen, deren Bedingung (auch umschließend) FPC abfragt.</summary>
function FpcOffsets(const ATokens: TArray<TPascalToken>): TArray<Integer>;
var
  mToken: TPascalToken;
  mStack: TArray<Boolean>;
  mBody, mName, mRest: string;
  mFpc: Boolean;
begin
  Result := nil;
  mStack := nil;
  for mToken in ATokens do
  begin
    mFpc := (mStack <> nil) and mStack[High(mStack)];
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      if mFpc then
      begin
        Result := Result + [mToken.Offset];
      end;
      Continue;
    end;
    mBody := TDirectiveNames.Body(mToken.Text);
    mName := UpperCase(TDirectiveNames.LeadingName(mBody));
    mRest := Copy(mBody, Length(mName) + 1, MaxInt);
    if (mName = 'IF') or (mName = 'IFDEF') or (mName = 'IFNDEF') or (mName = 'IFOPT') then
    begin
      mStack := mStack + [mFpc or MentionsFpc(mRest)];
    end
    else if (mName = 'ELSEIF') and (mStack <> nil) then
    begin
      mStack[High(mStack)] := mStack[High(mStack)] or MentionsFpc(mRest);
    end
    else if ((mName = 'ENDIF') or (mName = 'IFEND')) and (mStack <> nil) then
    begin
      SetLength(mStack, Length(mStack) - 1);
    end;
  end;
end;

/// <summary>Erlaubte Direktiven am Knoten ANode: nach einer Property nur default, nach Routinenköpfen eine der
/// Direktiven. False, wenn der Knoten nicht zu prüfen ist.</summary>
function DirectiveCandidates(ANode: TSyntaxNode; out ACandidates: TArray<string>): Boolean;
begin
  ACandidates := nil;
  Result := (ANode.Kind = TSyntaxKind.Directive) and (ANode.Parent <> nil);
  if not Result then
  begin
    Exit;
  end;
  if ANode.Parent.Kind = TSyntaxKind.PropertyDecl then
  begin
    ACandidates := TArray<string>.Create('default');
  end
  // Methodenzuordnung "function IFoo.GetX = MyGetX;": "= MyGetX" ist keine Direktive (#1325).
  else if (ANode.Parent.Kind = TSyntaxKind.RoutineHeader) and not ANode.Parent.IsMethodResolution then
  begin
    ACandidates := TDirectiveNames.RoutineDirectives;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Steht ANode in einem Zweig, dessen Bedingung FPC abfragt (Offsets AFpc)?</summary>
function InFpcBranch(const AFpc: TArray<Integer>; ANode: TSyntaxNode): Boolean;
var
  mOffset: Integer;
begin
  for mOffset in AFpc do
  begin
    if mOffset = ANode.StartOffset then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure ReportTypo(const AContext: TRuleContext; const AReport: IRuleReport; ANode: TSyntaxNode;
  const ACandidates: TArray<string>);
var
  mWord, mClosest: string;
  mRange: TTextRange;
begin
  mWord := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  mRange := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  mClosest := TTextFuzzy.Closest(mWord, ACandidates);
  if mClosest <> '' then
  begin
    mClosest := LikeOriginal(mWord, mClosest);
    AReport.Add(mRange, cTexts[TDirectivesText.UnknownMeant].Fmt([mWord, mClosest]),
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TDirectivesText.ReplaceWith].Fmt([mClosest]),
      [TRuleEdit.Create(mRange, mClosest)])]);
  end
  else
  begin
    AReport.Add(mRange, cTexts[TDirectivesText.UnknownDirective].Fmt([mWord]), TRuleConfidence.High);
  end;
end;

procedure TDirectiveTypoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mFpc: TArray<Integer>;
  mContext: TRuleContext;
  mReport: IRuleReport;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mFpc := nil;
  if Pos('{$', AContext.Text) > 0 then
  begin
    mFpc := FpcOffsets(AContext.Tree.Tokens);
  end;
  mContext := AContext;
  mReport := AReport;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mCandidates: TArray<string>;
    begin
      Result := True;
      if DirectiveCandidates(ANode, mCandidates) and not MatchText(ANode.Name, mCandidates) and
        not InFpcBranch(mFpc, ANode) then
      begin
        ReportTypo(mContext, mReport, ANode, mCandidates);
      end;
    end);
end;

{ TCompilerWarningsDisabledRule }

type
  /// <summary>Ein Schalter in einer Direktive: WARNINGS, HINTS, RANGECHECKS, OVERFLOWCHECKS, WARN:Name,
  /// PUSHOPT oder POPOPT.</summary>
  TCompilerSwitch = record
    Switch: string;
    /// <summary>So stand der Schalter da: R, RANGECHECKS, WARN usw.; bestimmt die Form der Wiederherstellung.
    /// </summary>
    Written: string;
    Off: Boolean;
  end;

  /// <summary>Ein ausgeschalteter Schalter und ob er wiederhergestellt wird.</summary>
  TSwitchOff = record
    Item: TCompilerSwitch;
    Token: Integer;
    Restored: Boolean;
  end;

/// <summary>Schalter aus {$WARNINGS OFF}, {$HINTS ON} usw.; False bei anderem Wert.</summary>
function LongSwitch(const AName, ARest: string; out AItem: TCompilerSwitch): Boolean;
begin
  AItem := Default(TCompilerSwitch);
  AItem.Written := AName;
  Result := MatchStr(ARest, ['ON', 'OFF']);
  AItem.Switch := AName;
  AItem.Off := ARest = 'OFF';
end;

/// <summary>Schalter aus {$WARN Name ON|OFF|ERROR|DEFAULT}; False bei anderer Form.</summary>
function WarnSwitch(const ARest: string; out AItem: TCompilerSwitch): Boolean;
var
  mWords: TArray<string>;
begin
  AItem := Default(TCompilerSwitch);
  AItem.Written := 'WARN';
  mWords := ARest.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  Result := (Length(mWords) = 2) and MatchStr(mWords[1], ['ON', 'OFF', 'ERROR', 'DEFAULT']);
  if Result then
  begin
    AItem.Switch := 'WARN:' + mWords[0];
    AItem.Off := mWords[1] = 'OFF';
  end;
end;

/// <summary>Ist APart ein Kurzschalter wie R- oder Q+?</summary>
function IsShortSwitch(const APart: string): Boolean;
var
  mPart: string;
begin
  mPart := Trim(APart);
  Result := (Length(mPart) = 2) and CharInSet(mPart[1], ['A'..'Z', 'a'..'z']) and CharInSet(mPart[2], ['+', '-']);
end;

/// <summary>Kurzschalter: {$R-}, {$Q+}, {$R-,Q-,O+}; {$R *.dfm} ist eine Ressource. Nur R und Q zählen.
/// </summary>
function ShortSwitches(const ABody: string): TArray<TCompilerSwitch>;
var
  mParts: TArray<string>;
  mPart: string;
  mItem: TCompilerSwitch;
begin
  Result := nil;
  mParts := ABody.Split([',']);
  for mPart in mParts do
  begin
    if not IsShortSwitch(mPart) then
    begin
      Exit;
    end;
  end;
  for mPart in mParts do
  begin
    mItem := Default(TCompilerSwitch);
    mItem.Written := UpperCase(Trim(mPart)[1]);
    if mItem.Written = 'R' then
    begin
      mItem.Switch := 'RANGECHECKS';
    end
    else if mItem.Written = 'Q' then
    begin
      mItem.Switch := 'OVERFLOWCHECKS';
    end
    else
    begin
      Continue;
    end;
    mItem.Off := Trim(mPart)[2] = '-';
    Result := Result + [mItem];
  end;
end;

/// <summary>Schalter der Direktive ADirective; leer bei allen anderen Direktiven, auch {$R *.dfm}.</summary>
function SwitchesOf(const ADirective: string): TArray<TCompilerSwitch>;
var
  mBody, mName, mRest: string;
  mItem: TCompilerSwitch;
  mFound: Boolean;
begin
  mBody := TDirectiveNames.Body(ADirective);
  mName := UpperCase(TDirectiveNames.LeadingName(mBody));
  mRest := UpperCase(Trim(Copy(mBody, Length(mName) + 1, MaxInt)));
  mItem := Default(TCompilerSwitch);
  mItem.Written := mName;
  mItem.Switch := mName;
  if MatchStr(mName, ['WARNINGS', 'HINTS', 'RANGECHECKS', 'OVERFLOWCHECKS']) then
  begin
    mFound := LongSwitch(mName, mRest, mItem);
  end
  else if mName = 'WARN' then
  begin
    mFound := WarnSwitch(mRest, mItem);
  end
  else if MatchStr(mName, ['PUSHOPT', 'POPOPT']) then
  begin
    mFound := True;
  end
  else
  begin
    Exit(ShortSwitches(mBody));
  end;
  Result := nil;
  if mFound then
  begin
    Result := [mItem];
  end;
end;

/// <summary>Direktive, die AItem wieder einschaltet.</summary>
function RestoreText(const AItem: TCompilerSwitch): string;
begin
  if StartsStr('WARN:', AItem.Switch) then
  begin
    Result := Format('{$WARN %s DEFAULT}', [Copy(AItem.Switch, 6, MaxInt)]);
  end
  else if Length(AItem.Written) = 1 then
  begin
    Result := Format('{$%s+}', [AItem.Written]);
  end
  else
  begin
    Result := Format('{$%s ON}', [AItem.Written]);
  end;
end;

function SwitchMessage(const AItem: TCompilerSwitch): string;
begin
  if AItem.Switch = 'WARNINGS' then
  begin
    Result := cTexts[TDirectivesText.WarningsOff].Text;
  end
  else if AItem.Switch = 'HINTS' then
  begin
    Result := cTexts[TDirectivesText.HintsOff].Text;
  end
  else if AItem.Switch = 'RANGECHECKS' then
  begin
    Result := cTexts[TDirectivesText.RangeOff].Text;
  end
  else if AItem.Switch = 'OVERFLOWCHECKS' then
  begin
    Result := cTexts[TDirectivesText.OverflowOff].Text;
  end
  else
  begin
    Result := cTexts[TDirectivesText.WarningOff].Fmt([Copy(AItem.Switch, 6, MaxInt)]);
  end;
end;

/// <summary>Steht AItem in der Liste allow (Warnungsname, WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw.
/// OVERFLOWCHECKS)?</summary>
function SwitchAllowed(const AItem: TCompilerSwitch; const AAllow: TArray<string>): Boolean;
begin
  if StartsStr('WARN:', AItem.Switch) then
  begin
    Result := MatchText(Copy(AItem.Switch, 6, MaxInt), AAllow);
  end
  else
  begin
    Result := MatchText(AItem.Switch, AAllow) or ((AItem.Switch = 'RANGECHECKS') and MatchText('R', AAllow)) or
      ((AItem.Switch = 'OVERFLOWCHECKS') and MatchText('Q', AAllow));
  end;
end;

/// <summary>Folgt hinter dem Token AIndex noch Code außer dem abschließenden "end."?</summary>
function CodeFollows(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := AIndex + 1 to High(ATokens) do
  begin
    if not (ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      not ATokens[mIndex].IsKeyword('end') and not ATokens[mIndex].IsSymbol('.') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Der nächste Block hinter AOffset: das erste Geschwister hinter der Direktive im innersten Knoten,
/// der sie umschließt; nil ohne oder wenn es ein ganzer Abschnitt wäre.</summary>
function NextBlock(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mNode, mInner: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mNode := ATree.Root;
  while mNode <> nil do
  begin
    mInner := nil;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if (mNode[mIndex].StartOffset <= AOffset) and (AOffset < mNode[mIndex].EndOffset) then
      begin
        mInner := mNode[mIndex];
        Break;
      end
      else if mNode[mIndex].StartOffset >= AOffset then
      begin
        Result := mNode[mIndex];
        Break;
      end;
    end;
    mNode := mInner;
  end;
  if (Result <> nil) and (Result.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection]) then
  begin
    Result := nil;
  end;
end;

function TCompilerWarningsDisabledRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCompilerWarningsDisabledRuleId, TRuleSeverity.Warning,
    cTexts[TDirectivesText.OffTitle].Text);
end;

/// <summary>Schalter AItem aus der Direktive an AIndex in die ausgeschalteten AOffs eintragen.</summary>
procedure ApplySwitch(var AOffs: TArray<TSwitchOff>; const AItem: TCompilerSwitch; AIndex: Integer);
var
  mOther: Integer;
  mOff: TSwitchOff;
begin
  if AItem.Off then
  begin
    mOff := Default(TSwitchOff);
    mOff.Item := AItem;
    mOff.Token := AIndex;
    AOffs := AOffs + [mOff];
    Exit;
  end;
  // {$POPOPT} stellt alles wieder her, was seit {$PUSHOPT} umgestellt wurde.
  for mOther := 0 to High(AOffs) do
  begin
    if (AItem.Switch = 'POPOPT') or (AOffs[mOther].Item.Switch = AItem.Switch) then
    begin
      AOffs[mOther].Restored := True;
    end;
  end;
end;

/// <summary>Alle ausgeschalteten Schalter der Datei und ob sie wiederhergestellt werden.</summary>
function SwitchOffs(const ATokens: TArray<TPascalToken>): TArray<TSwitchOff>;
var
  mIndex: Integer;
  mItem: TCompilerSwitch;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      for mItem in SwitchesOf(ATokens[mIndex].Text) do
      begin
        ApplySwitch(Result, mItem, mIndex);
      end;
    end;
  end;
end;

/// <summary>Schaltet die Direktive ADirective den Schalter ASwitch ein?</summary>
function SwitchesOn(const ADirective, ASwitch: string): Boolean;
var
  mItem: TCompilerSwitch;
begin
  for mItem in SwitchesOf(ADirective) do
  begin
    if (mItem.Switch = ASwitch) and not mItem.Off then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>{$IFDEF DEBUG}{$R+}{$ELSE}{$R-}{$ENDIF}: gewollt je Konfiguration, kein Vergessen.</summary>
function Deliberate(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>;
  const AOff: TSwitchOff): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Directive) and TConditionalBranches.Exclusive(
      TConditionalBranches.PathAt(APaths, mIndex), TConditionalBranches.PathAt(APaths, AOff.Token)) and
      SwitchesOn(ATokens[mIndex].Text, AOff.Item.Switch) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Korrektur: den Schalter nach dem nächsten Block wiederherstellen.</summary>
function RestoreFixes(ATree: TSyntaxTree; const ALines: TArray<string>; const ALineBreak: string;
  const AOff: TSwitchOff): TArray<TRuleFix>;
var
  mBlock: TSyntaxNode;
  mLine: Integer;
  mIndent: string;
  mToken: TPascalToken;
begin
  Result := nil;
  mToken := ATree.Tokens[AOff.Token];
  mBlock := NextBlock(ATree, mToken.Offset + Length(mToken.Text));
  if (mBlock = nil) or (mBlock.EndPos.Line > High(ALines)) then
  begin
    Exit;
  end;
  mLine := mBlock.EndPos.Line;
  mIndent := '';
  if mToken.StartPos.Line <= High(ALines) then
  begin
    mIndent := TTextLines.IndentOf(ALines[mToken.StartPos.Line]);
  end;
  // Bereichs- und Überlaufprüfung: {$R+} schaltet sie womöglich erst ein, wenn das Projekt sie aus hat;
  // deshalb nur einzeln.
  Result := [TRuleFix.Create(cTexts[TDirectivesText.Restore].Text,
    [TRuleEdit.Create(TTextRange.Create(mLine, Length(ALines[mLine]), mLine, Length(ALines[mLine])),
    ALineBreak + mIndent + RestoreText(AOff.Item))], not MatchStr(AOff.Item.Switch, ['RANGECHECKS',
    'OVERFLOWCHECKS']))];
end;

procedure TCompilerWarningsDisabledRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths, mAllow, mLines: TArray<string>;
  mOffs: TArray<TSwitchOff>;
  mOff: TSwitchOff;
  mLineBreak: string;
begin
  // Die Schalter einer .dpk sind die Optionen des Packages, die die IDE dort pflegt.
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind = TSyntaxKind.PackageFile) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mOffs := SwitchOffs(mTokens);
  if mOffs = nil then
  begin
    Exit;
  end;
  mAllow := TRuleOptions.Strings(AContext.Options, 'allow', nil);
  mPaths := TConditionalBranches.Paths(mTokens);
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  for mOff in mOffs do
  begin
    if mOff.Restored or SwitchAllowed(mOff.Item, mAllow) or not CodeFollows(mTokens, mOff.Token) or
      Deliberate(mTokens, mPaths, mOff) then
    begin
      Continue;
    end;
    AReport.Add(TTextRange.Create(mTokens[mOff.Token].StartPos, mTokens[mOff.Token].EndPos),
      SwitchMessage(mOff.Item), TRuleConfidence.High, RestoreFixes(AContext.Tree, mLines, mLineBreak, mOff));
  end;
end;

{ TCompilerDirectiveInvalidRule }

const
  /// <summary>So tief folgt compiler-directive-invalid Include-Dateien in Include-Dateien.</summary>
  cMaxIncludeDepth = 16;
  /// <summary>Zeichen, die in keinem Dateinamen stehen (Masken, Makros); dann schweigt die Regel.</summary>
  cNoFileChars: TSysCharSet = ['*', '?', '<', '>', '|', '"', '%'];

/// <summary>Text in Hochkommas ab AText[2] ('' für ein Hochkomma); AIndex steht danach auf dem schließenden
/// Hochkomma bzw. hinter dem Ende.</summary>
function QuotedArgument(const AText: string; out AIndex: Integer): string;
begin
  Result := '';
  AIndex := 2;
  while AIndex <= Length(AText) do
  begin
    if AText[AIndex] = '''' then
    begin
      if (AIndex >= Length(AText)) or (AText[AIndex + 1] <> '''') then
      begin
        Exit;
      end;
      Inc(AIndex);
    end;
    Result := Result + AText[AIndex];
    Inc(AIndex);
  end;
end;

/// <summary>Erstes Argument einer Direktive: Text in Hochkommas ('' für ein Hochkomma) oder bis zum Leerraum;
/// ARest erhält den Rest ohne Rand.</summary>
function FirstArgument(const AText: string; out ARest: string): string;
var
  mText: string;
  mIndex: Integer;
begin
  mText := Trim(AText);
  if (mText <> '') and (mText[1] = '''') then
  begin
    Result := QuotedArgument(mText, mIndex);
  end
  else
  begin
    mIndex := 1;
    while (mIndex <= Length(mText)) and not CharInSet(mText[mIndex], [' ', #9, #10, #13]) do
    begin
      Inc(mIndex);
    end;
    Result := Copy(mText, 1, mIndex - 1);
  end;
  ARest := Trim(Copy(mText, mIndex + 1, MaxInt));
end;

/// <summary>Kann AName ein Dateiname sein (keine Maske, kein Makro)?</summary>
function PlainFileName(const AName: string): Boolean;
var
  mChar: Char;
begin
  Result := AName <> '';
  for mChar in AName do
  begin
    if CharInSet(mChar, cNoFileChars) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Namen, unter denen dcc die Datei aus {$I} bzw. {$R} sucht: wie geschrieben, ohne passende Endung
/// zusätzlich mit .inc und .pas bzw. .res. Lieber ein Name zu viel als eine Meldung, wo dcc die Datei findet.
/// </summary>
function FileCandidates(const AName: string; AResource: Boolean): TArray<string>;
begin
  Result := [AName];
  if AResource then
  begin
    if not EndsText('.res', AName) then
    begin
      Result := Result + [AName + '.res'];
    end;
  end
  else if not EndsText('.inc', AName) and not EndsText('.pas', AName) then
  begin
    Result := Result + [AName + '.inc', AName + '.pas'];
  end;
end;

/// <summary>Datei aus {$I}/{$INCLUDE} bzw. {$R}/{$RESOURCE} (ARest: alles hinter dem Namen der Direktive);
/// False für Kurzschalter ({$I+}, {$R-,Q+}) und ohne Dateinamen.</summary>
function DirectiveFile(const AName, ARest: string; out AResource: Boolean; out AFile, AMore: string): Boolean;
begin
  AFile := '';
  AMore := '';
  AResource := (AName = 'R') or (AName = 'RESOURCE');
  Result := AResource or (AName = 'I') or (AName = 'INCLUDE');
  if not Result then
  begin
    Exit;
  end;
  Result := (ARest <> '') and not CharInSet(ARest[1], ['+', '-', ',']);
  if Result then
  begin
    AFile := FirstArgument(ARest, AMore);
  end;
end;

/// <summary>Schlüssel einer Include-Datei für den Vergleich: "\" als Trenner, klein.</summary>
function IncludeKey(const AName: string): string;
begin
  Result := LowerCase(StringReplace(AName, '/', '\', [rfReplaceAll]));
end;

function TCompilerDirectiveInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCompilerDirectiveInvalidRuleId, TRuleSeverity.Error,
    cTexts[TDirectivesText.DirectiveTitle].Text);
end;

procedure TCompilerDirectiveInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths: TArray<string>;
  mWeak, mDeny, mPackageUnknown: Boolean;
  mIndex: Integer;

  function RangeOf(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(mTokens[AIndex].StartPos, mTokens[AIndex].EndPos);
  end;

  /// <summary>Gibt es eine der Dateien ACandidates (relativ zur Unit bzw. über die Suchpfade des Projekts)?
  /// Unknown ohne Dateizugriff oder wenn die Suche keine sichere Aussage trifft.</summary>
  function Locate(const ACandidates: TArray<string>): TRuleUnitAnswer;
  var
    mName: string;
    mAnswer: TRuleUnitAnswer;
  begin
    if not Assigned(AContext.FileExists) or (AContext.FileName = '') then
    begin
      Exit(TRuleUnitAnswer.Unknown);
    end;
    for mName in ACandidates do
    begin
      if AContext.FileExists(mName) then
      begin
        Exit(TRuleUnitAnswer.Found);
      end;
    end;
    if AContext.Units = nil then
    begin
      Exit(TRuleUnitAnswer.Unknown);
    end;
    Result := TRuleUnitAnswer.Missing;
    for mName in ACandidates do
    begin
      mAnswer := AContext.Units.FindFile(mName, AContext.FileName);
      if mAnswer = TRuleUnitAnswer.Found then
      begin
        Exit(TRuleUnitAnswer.Found);
      end;
      if mAnswer = TRuleUnitAnswer.Unknown then
      begin
        Result := TRuleUnitAnswer.Unknown;
      end;
    end;
  end;

  /// <summary>Text der Include-Datei AName relativ zum Ordner der Unit; AFound ist der gelesene Name.</summary>
  function ReadInclude(const AName: string; out AFound, AText: string): Boolean;
  var
    mName: string;
    mData: TBytes;
    mFormat: TFileFormat;
  begin
    AFound := '';
    AText := '';
    Result := False;
    if not Assigned(AContext.ReadFile) or not PlainFileName(AName) then
    begin
      Exit;
    end;
    for mName in FileCandidates(AName, False) do
    begin
      if AContext.ReadFile(mName, mData) then
      begin
        AFound := mName;
        AText := TFileEncoding.Decode(mData, mFormat);
        Exit(True);
      end;
    end;
  end;

  /// <summary>Ist die Direktive AToken ein {$I} außerhalb jeder Bedingung? ADepth: Tiefe der Bedingungen,
  /// nachgeführt; AFile: die Datei, ohne Laufwerk relativ zu AFolder. Ein Wächter wie {$IFNDEF X_INC}
  /// {$DEFINE X_INC} … {$ENDIF} beendet so den Kreis.</summary>
  function UnconditionalInclude(const AToken: TPascalToken; const AFolder: string; var ADepth: Integer;
    out AFile: string): Boolean;
  var
    mBody, mDirective, mRest, mMore: string;
    mResource: Boolean;
  begin
    AFile := '';
    mBody := TDirectiveNames.Body(AToken.Text);
    mDirective := UpperCase(TDirectiveNames.LeadingName(mBody));
    mRest := Trim(Copy(mBody, Length(mDirective) + 1, MaxInt));
    Result := False;
    if MatchStr(mDirective, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
    begin
      Inc(ADepth);
    end
    else if MatchStr(mDirective, ['ENDIF', 'IFEND']) then
    begin
      Dec(ADepth);
    end
    else
    begin
      Result := (ADepth = 0) and DirectiveFile(mDirective, mRest, mResource, AFile, mMore) and not mResource and
        PlainFileName(AFile);
      if Result and (ExtractFileDrive(AFile) = '') then
      begin
        AFile := AFolder + AFile;
      end;
    end;
  end;

  /// <summary>Bindet sich die Include-Datei AName (relativ zur Unit) über unbedingte {$I} selbst ein, direkt oder
  /// über weitere Include-Dateien? AStack: Schlüssel der Dateien auf dem Weg dorthin; AChain: der Weg bis zur
  /// Wiederholung, z. B. "A.inc → B.inc → A.inc".</summary>
  function Recursive(const AName: string; const AStack: TArray<string>; out AChain: string): Boolean;
  var
    mFound, mText, mKey, mFile, mInner, mFolder: string;
    mToken: TPascalToken;
    mDepth: Integer;
  begin
    AChain := '';
    Result := False;
    if (Length(AStack) >= cMaxIncludeDepth) or not ReadInclude(AName, mFound, mText) then
    begin
      Exit;
    end;
    mKey := IncludeKey(mFound);
    if IndexStr(mKey, AStack) >= 0 then
    begin
      AChain := ExtractFileName(mFound);
      Exit(True);
    end;
    mFolder := ExtractFilePath(StringReplace(mFound, '/', '\', [rfReplaceAll]));
    mDepth := 0;
    for mToken in TPascalLexer.Tokenize(mText) do
    begin
      if (mToken.Kind = TPascalTokenKind.Directive) and UnconditionalInclude(mToken, mFolder, mDepth, mFile) and
        Recursive(mFile, AStack + [mKey], mInner) then
      begin
        AChain := ExtractFileName(mFound) + ' → ' + mInner;
        Exit(True);
      end;
    end;
  end;

  procedure CheckFile(AIndex: Integer; AResource: Boolean; const AFile, AMore: string);
  var
    mChain: string;
  begin
    if not PlainFileName(AFile) then
    begin
      Exit;
    end;
    if AResource then
    begin
      // {$R Name.res Name.rc}: Die .res entsteht beim Bau aus der .rc; Formulare prüft form-resource-missing.
      if (AMore <> '') or MatchText(ExtractFileExt(AFile), ['.dfm', '.fmx', '.xfm', '.lfm']) then
      begin
        Exit;
      end;
      // Eine .rc gleichen Namens übersetzt die IDE vor dem Compiler (RcCompile in der .dproj).
      if Assigned(AContext.FileExists) and AContext.FileExists(ChangeFileExt(AFile, '.rc')) then
      begin
        Exit;
      end;
      if Locate(FileCandidates(AFile, True)) = TRuleUnitAnswer.Missing then
      begin
        AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.ResourceMissing].Fmt([AFile]));
      end;
      Exit;
    end;
    case Locate(FileCandidates(AFile, False)) of
      TRuleUnitAnswer.Missing:
        AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.IncludeMissing].Fmt([AFile]));
      TRuleUnitAnswer.Found:
        if Recursive(AFile, nil, mChain) then
        begin
          AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.RecursiveInclude].Fmt([mChain]));
        end;
    end;
  end;

  procedure CheckMessage(AIndex: Integer; const ARest: string);
  var
    mKind, mText, mAfter: string;
  begin
    // {$MESSAGE HINT|WARN 'Text'}; ohne Art und mit ERROR/FATAL noch nicht mit dcc abgeglichen.
    mKind := UpperCase(FirstArgument(ARest, mText));
    if (mText = '') or (mText[1] <> '''') then
    begin
      Exit;
    end;
    mText := FirstArgument(mText, mAfter);
    if mKind = 'WARN' then
    begin
      AReport.AddWithSeverity(RangeOf(AIndex), cTexts[TDirectivesText.MessageWarn].Fmt([mText]),
        TRuleSeverity.Warning, nil);
    end
    else if mKind = 'HINT' then
    begin
      AReport.AddWithSeverity(RangeOf(AIndex), cTexts[TDirectivesText.MessageHint].Fmt([mText]),
        TRuleSeverity.Hint, nil);
    end;
  end;

  procedure CheckPackageSwitch(AIndex: Integer; const AName, ARest: string);
  var
    mValue, mAfter: string;
    mOn: Boolean;
  begin
    mValue := UpperCase(FirstArgument(ARest, mAfter));
    if (mValue <> 'ON') and (mValue <> 'OFF') then
    begin
      mPackageUnknown := True;
      Exit;
    end;
    mOn := mValue = 'ON';
    if AName = 'WEAKPACKAGEUNIT' then
    begin
      if mOn and mDeny and not mWeak and not mPackageUnknown then
      begin
        AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.WeakDeny].Text);
      end;
      mWeak := mOn;
    end
    else
    begin
      if mOn and mWeak and not mDeny and not mPackageUnknown then
      begin
        AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.WeakDeny].Text);
      end;
      mDeny := mOn;
    end;
  end;

  procedure CheckPackageOnly(AIndex: Integer; const AName, ARest: string);
  var
    mValue, mAfter: string;
  begin
    if (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind <> TSyntaxKind.UnitFile) then
    begin
      Exit;
    end;
    mValue := UpperCase(FirstArgument(ARest, mAfter));
    if (mValue = '') or (mValue = 'ON') then
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.PackageOnly].Fmt([AName]));
    end;
  end;

  /// <summary>Ist ADecl ein globaler, schlichter Alias wie TZahl = Integer (nicht TZahl = type Integer)?</summary>
  function IsGlobalAlias(ADecl: TSyntaxNode): Boolean;
  var
    mTarget: TSyntaxNode;
    mToken: Integer;
  begin
    Result := False;
    if (ADecl.Parent = nil) or (ADecl.Parent.Kind <> TSyntaxKind.TypeSection) or (ADecl.Parent.Parent = nil) or
      not (ADecl.Parent.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) or
      (ADecl.ChildCount <> 1) then
    begin
      Exit;
    end;
    mTarget := ADecl[0];
    if (mTarget.Kind <> TSyntaxKind.TypeReference) or (mTarget.ChildCount > 0) or
      MatchText(mTarget.Name, ['', 'string', 'file', 'const']) then
    begin
      Exit;
    end;
    mToken := AContext.Tree.FirstTokenFrom(mTarget.StartOffset) - 1;
    while (mToken >= 0) and (mTokens[mToken].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    begin
      Dec(mToken);
    end;
    Result := (mToken >= 0) and (mTokens[mToken].Text = '=');
  end;

  procedure CheckObjTypeName(AIndex: Integer; const ARest: string);
  var
    mName, mAfter: string;
    mDecls, mPending: TArray<TSyntaxNode>;
    mDecl, mNode: TSyntaxNode;
    mChild: Integer;
  begin
    mName := FirstArgument(ARest, mAfter);
    if not IsValidIdent(mName) then
    begin
      Exit;
    end;
    // Iterativ (tiefe Bäume sprengen den Stapel nicht); Typen stehen nicht in Anweisungen.
    mDecls := nil;
    mPending := [AContext.Tree.Root];
    while mPending <> nil do
    begin
      mNode := mPending[High(mPending)];
      SetLength(mPending, Length(mPending) - 1);
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, mName) then
      begin
        mDecls := mDecls + [mNode];
      end;
      if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]) then
      begin
        for mChild := 0 to mNode.ChildCount - 1 do
        begin
          mPending := mPending + [mNode[mChild]];
        end;
      end;
    end;
    if mDecls = nil then
    begin
      Exit;
    end;
    for mDecl in mDecls do
    begin
      if not IsGlobalAlias(mDecl) then
      begin
        Exit;
      end;
    end;
    AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.ObjTypeName].Fmt([mName]));
  end;

  procedure CheckCodePage(AIndex: Integer; const ARest: string);
  var
    mValue, mAfter: string;
    mNumber: Int64;
  begin
    // Codepages sind 16 Bit groß; welche installiert sind, weiß nur der Rechner, der übersetzt (E2424).
    mValue := FirstArgument(ARest, mAfter);
    if TryStrToInt64(mValue, mNumber) and (mNumber > 65535) then
    begin
      AReport.Add(RangeOf(AIndex), cTexts[TDirectivesText.BadCodepage].Fmt([mValue]));
    end;
  end;

  procedure Visit(AIndex: Integer);
  var
    mBody, mName, mRest, mFile, mMore: string;
    mResource: Boolean;
  begin
    mBody := TDirectiveNames.Body(mTokens[AIndex].Text);
    mName := UpperCase(TDirectiveNames.LeadingName(mBody));
    mRest := Trim(Copy(mBody, Length(mName) + 1, MaxInt));
    if (mName = 'WEAKPACKAGEUNIT') or (mName = 'DENYPACKAGEUNIT') then
    begin
      // Was in bedingten Zweigen steht, wird vielleicht nicht übersetzt: dann ohne Aussage.
      if TConditionalBranches.PathAt(mPaths, AIndex) <> '' then
      begin
        mPackageUnknown := True;
      end
      else
      begin
        CheckPackageSwitch(AIndex, mName, mRest);
      end;
      Exit;
    end;
    if TConditionalBranches.PathAt(mPaths, AIndex) <> '' then
    begin
      Exit;
    end;
    if DirectiveFile(mName, mRest, mResource, mFile, mMore) then
    begin
      CheckFile(AIndex, mResource, mFile, mMore);
    end
    else if mName = 'MESSAGE' then
    begin
      CheckMessage(AIndex, mRest);
    end
    else if (mName = 'DESIGNONLY') or (mName = 'RUNONLY') then
    begin
      CheckPackageOnly(AIndex, mName, mRest);
    end
    else if mName = 'OBJTYPENAME' then
    begin
      CheckObjTypeName(AIndex, mRest);
    end
    else if mName = 'CODEPAGE' then
    begin
      CheckCodePage(AIndex, mRest);
    end;
  end;

begin
  if (AContext.Tree = nil) or (Pos('$', AContext.Text) = 0) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  mWeak := False;
  mDeny := False;
  mPackageUnknown := False;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      Visit(mIndex);
    end;
  end;
end;

procedure RegisterDirectiveRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConditionalDirectiveUnbalancedRule.Create);
  ARegistry.Register(TDirectiveTypoRule.Create);
  ARegistry.Register(TCompilerWarningsDisabledRule.Create);
  ARegistry.Register(TCompilerDirectiveInvalidRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Directives', cTexts);

end.
