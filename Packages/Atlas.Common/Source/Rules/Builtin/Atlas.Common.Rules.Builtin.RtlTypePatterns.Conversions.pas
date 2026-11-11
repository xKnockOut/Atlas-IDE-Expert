unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Conversions;

// Regeln für Umwandlungen und Formateinstellungen aus Atlas.Common.Rules.Builtin.RtlTypePatterns (Stufe 2 aus #153,
// angemeldet in
// RegisterRtlTypePatternRules):
//   format-without-settings  Format mit %f/%n/%m/%g/%e, FloatToStr, StrToDate … ohne TFormatSettings
//                            (FormatDateTime/FormatFloat mit festem Bild nur, wenn es Trennzeichen
//                            wie : / . , enthält)
//   unchecked-conversion     StrToInt, StrToFloat, StrToDate … direkt auf Edit.Text, Cells[…] oder Lines[…]
//                            ohne umgebendes try/except (#932); Korrektur: TryStrToInt … mit raise im
//                            Fehlerzweig, wenn das Ziel eine Variable des passenden Typs ist
//   unchecked-enum-cast      TStatus(Zahl) mit einem Aufzählungstyp aus Datei oder Index, wenn die Zahl aus einer
//                            Quelle der Option "sources" stammt (FieldByName, ReadInteger, AsInteger, StrToInt):
//                            direkt im Argument oder über eine Variable, die zwischen Zuweisung und Umwandlung
//                            nicht gelesen (geprüft) wird (#954). EnsureRange/Min/Max im Argument gelten als
//                            Prüfung. Korrektur bei direkter Quelle: Hilfsvariable, InRange-Prüfung mit raise
//                            EConvertError davor, System.Math in uses
//   global-formatsettings-modified
//                            Zuweisung an die globale FormatSettings oder eines ihrer Felder, auch an die veralteten
//                            globalen Variablen DecimalSeparator, ShortDateFormat … (#1089): ändert die Formatierung
//                            für die ganze Anwendung, alle Packages im Prozess (im IDE-Plugin die IDE) und alle
//                            Threads. Gemeldet wird nur, wenn der Name sicher die Variable aus System.SysUtils ist:
//                            keine lokale Deklaration, kein Mitglied der Klasse und ihrer Vorfahren (bricht die Kette
//                            an einem unbekannten Vorfahren ab, schweigt die Regel), kein with. Korrektur bei genau
//                            einer solchen Zuweisung in der Routine und Formatierungsaufrufen danach: lokale
//                            TFormatSettings (TFormatSettings.Invariant für DecimalSeparator := '.', sonst eine
//                            Kopie mit dem geänderten Feld) an diese Aufrufe übergeben. Option allowInProgram
//                            erlaubt die Zuweisungen in der .dpr

interface

uses
  Atlas.Common.Rules.Contract;

type
  TFormatWithoutSettingsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Enthält AFormat einen vom Gebietsschema abhängigen Platzhalter (%f, %n, %m, %g, %e)?</summary>
    class function HasLocaleSpecifier(const AFormat: string): Boolean; static;
    /// <summary>Hängt das Bild APicture von FormatDateTime bzw. FormatFloat/FormatCurr (AFunction) vom
    /// Gebietsschema ab? Nur die Trennzeichen außerhalb von Anführungszeichen tun es: ":" und "/" werden zu
    /// TimeSeparator und DateSeparator, "." und "," zu DecimalSeparator und ThousandSeparator. Ziffernfelder
    /// ('yyyy"-"mm"-"dd') sind fest; Namen und Gesamtformate ('ddddd t', 'mmmm') verlangen das Gebietsschema
    /// ausdrücklich (#1109).</summary>
    class function PictureDependsOnLocale(const AFunction, APicture: string): Boolean; static;
  end;

  TUncheckedConversionRule = class(TInterfacedObject, IRule)
  public const
    cDefaultFunctions: array[0..5] of string = ('StrToInt', 'StrToInt64', 'StrToFloat', 'StrToDate', 'StrToDateTime',
      'StrToCurr');
    cDefaultSources: array[0..2] of string = ('Text', 'Cells', 'Lines');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUncheckedEnumCastRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Herkunft für die Meldung: "aus der Datenbank", "aus einem Text" …</summary>
    class function Origin(const ASource: string): string; static;
  end;

  TGlobalFormatSettingsModifiedRule = class(TInterfacedObject, IRule)
  public const
    /// <summary>Veraltete globale Variablen aus System.SysUtils (bis XE5), gleichnamig mit den Feldern von
    /// TFormatSettings.</summary>
    cDeprecatedGlobals: array[0..19] of string = ('CurrencyString', 'CurrencyFormat', 'NegCurrFormat',
      'ThousandSeparator', 'DecimalSeparator', 'CurrencyDecimals', 'DateSeparator', 'ShortDateFormat',
      'LongDateFormat', 'TimeSeparator', 'TimeAMString', 'TimePMString', 'ShortTimeFormat', 'LongTimeFormat',
      'ShortMonthNames', 'LongMonthNames', 'ShortDayNames', 'LongDayNames', 'ListSeparator',
      'TwoDigitYearCenturyWindow');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Was die Zuweisung an das Feld AField ändert, für die Meldung ("den Dezimaltrenner");
    /// AField = '' steht für die ganze FormatSettings.</summary>
    class function Subject(const AField: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRtlTypePatternsConversionsText = (LocaleTitle, Locale, PassFormatSettings, UncheckedTitle, Unchecked,
    EnumCastTitle, FromRegistry, FromText, FromDatabase, FromOutside, InvalidValueCode, InsertInRange, EnumCast,
    GlobalTitle, AllSettings, TheSetting, LocalSettings, Global, NotNumber, NotAmount, NotDate, NotDateTime, NotTime,
    NotBoolean, CurrencyString, CurrencyFormat, NegCurrFormat, ThousandSeparator, DecimalSeparator, CurrencyDecimals,
    DateSeparator, ShortDateFormat, LongDateFormat, TimeSeparator, TimeAMString, TimePMString, ShortTimeFormat,
    LongTimeFormat, ShortMonthNames, LongMonthNames, ShortDayNames, LongDayNames, ListSeparator,
    TwoDigitYearCenturyWindow, RewriteTry);

const
  cTexts: array[TRtlTypePatternsConversionsText] of TAtlasText = (
    (De: 'Formatierung abhängig vom Gebietsschema'; En: 'Formatting depends on the locale'),
    (De: '%s ohne TFormatSettings hängt vom Gebietsschema ab (Dezimaltrenner, Datumsformat); für Dateien und ' +
      'Protokolle eine feste TFormatSettings übergeben';
     En: '%s without TFormatSettings depends on the locale (decimal separator, date format); pass a fixed ' +
      'TFormatSettings for files and logs'),
    (De: 'FormatSettings übergeben'; En: 'Pass FormatSettings'),
    (De: 'Umwandlung einer Benutzereingabe ohne Prüfung'; En: 'Conversion of user input without check'),
    (De: 'Eingabe aus %s ohne Prüfung umgewandelt; eine Fehleingabe löst EConvertError aus.';
     En: 'Input from %s converted without check; an invalid input raises EConvertError.'),
    (De: 'Zahl ungeprüft in Aufzählung umgewandelt'; En: 'Number converted to enumeration without check'),
    (De: 'aus der Registry bzw. INI-Datei'; En: 'from the registry or INI file'),
    (De: 'aus einem Text'; En: 'from a text'),
    (De: 'aus der Datenbank'; En: 'from the database'),
    (De: 'von außen'; En: 'from outside'),
    (De: 'raise EConvertError.CreateFmt(''Ungültiger Wert %d für ';
     En: 'raise EConvertError.CreateFmt(''Invalid value %d for '),
    (De: 'Prüfung mit InRange davorsetzen'; En: 'Insert a check with InRange before it'),
    (De: 'Wert %s ungeprüft nach %s umgewandelt; Werte außerhalb %s ergeben keinen gültigen %s-Wert.';
     En: 'Value %s converted to %s without check; values outside %s give no valid %s value.'),
    (De: 'Globale FormatSettings wird verändert'; En: 'Global FormatSettings is modified'),
    (De: 'alle Formateinstellungen'; En: 'all format settings'),
    (De: 'die Formateinstellung %s'; En: 'the format setting %s'),
    (De: 'Lokale TFormatSettings anlegen und übergeben'; En: 'Create and pass a local TFormatSettings'),
    (De: 'Ändert %s für die ganze Anwendung und alle Threads; eine lokale TFormatSettings verwenden.';
     En: 'Changes %s for the whole application and all threads; use a local TFormatSettings.'),
    (De: 'ist keine Zahl'; En: 'is not a number'),
    (De: 'ist kein Betrag'; En: 'is not an amount'),
    (De: 'ist kein Datum'; En: 'is not a date'),
    (De: 'ist kein Zeitpunkt'; En: 'is not a point in time'),
    (De: 'ist keine Uhrzeit'; En: 'is not a time of day'),
    (De: 'ist kein Wahrheitswert'; En: 'is not a truth value'),
    (De: 'das Währungssymbol'; En: 'the currency symbol'),
    (De: 'das Währungsformat'; En: 'the currency format'),
    (De: 'das Format negativer Beträge'; En: 'the format of negative amounts'),
    (De: 'das Tausendertrennzeichen'; En: 'the thousands separator'),
    (De: 'den Dezimaltrenner'; En: 'the decimal separator'),
    (De: 'die Nachkommastellen von Beträgen'; En: 'the decimal places of amounts'),
    (De: 'das Datumstrennzeichen'; En: 'the date separator'),
    (De: 'das kurze Datumsformat'; En: 'the short date format'),
    (De: 'das lange Datumsformat'; En: 'the long date format'),
    (De: 'das Zeittrennzeichen'; En: 'the time separator'),
    (De: 'die Vormittagskennung'; En: 'the AM designator'),
    (De: 'die Nachmittagskennung'; En: 'the PM designator'),
    (De: 'das kurze Zeitformat'; En: 'the short time format'),
    (De: 'das lange Zeitformat'; En: 'the long time format'),
    (De: 'die kurzen Monatsnamen'; En: 'the short month names'),
    (De: 'die Monatsnamen'; En: 'the month names'),
    (De: 'die kurzen Tagesnamen'; En: 'the short day names'),
    (De: 'die Tagesnamen'; En: 'the day names'),
    (De: 'das Listentrennzeichen'; En: 'the list separator'),
    (De: 'das Jahrhundertfenster zweistelliger Jahreszahlen'; En: 'the century window of two-digit years'),
    (De: 'In Try%s mit Fehlerzweig umschreiben'; En: 'Rewrite as Try%s with error branch'));

{$SCOPEDENUMS OFF}

{ TFormatWithoutSettingsRule }

function TFormatWithoutSettingsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('format-without-settings', TRuleSeverity.Hint,
    cTexts[TRtlTypePatternsConversionsText.LocaleTitle].Text);
end;

class function TFormatWithoutSettingsRule.HasLocaleSpecifier(const AFormat: string): Boolean;
var
  mValue: string;
begin
  // Zerlegung gemeinsam mit format-args; ein Literal mit Hochkommas wird erst ausgewertet.
  if TFormatString.LiteralValue(AFormat, mValue) then
  begin
    Result := TFormatString.HasLocaleSpecifier(mValue);
  end
  else
  begin
    Result := TFormatString.HasLocaleSpecifier(AFormat);
  end;
end;

class function TFormatWithoutSettingsRule.PictureDependsOnLocale(const AFunction, APicture: string): Boolean;
var
  mIndex: Integer;
  mQuote: Char;
  mSeparators: TSysCharSet;
begin
  if SameText(AFunction, 'FormatDateTime') then
  begin
    mSeparators := [':', '/'];
  end
  else
  begin
    mSeparators := ['.', ','];
  end;
  mQuote := #0;
  for mIndex := 1 to Length(APicture) do
  begin
    if mQuote <> #0 then
    begin
      if APicture[mIndex] = mQuote then
      begin
        mQuote := #0;
      end;
    end
    else if CharInSet(APicture[mIndex], ['"', '''']) then
    begin
      mQuote := APicture[mIndex];
    end
    else if CharInSet(APicture[mIndex], mSeparators) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zahl der Argumente ohne TFormatSettings; 0, wenn AName keine solche Funktion ist.</summary>
function PlainArgumentCount(const AName: string): Integer;
const
  cOne: array[0..10] of string = ('FloatToStr', 'StrToFloat', 'DateToStr', 'StrToDate', 'DateTimeToStr',
    'StrToDateTime', 'TimeToStr', 'StrToTime', 'CurrToStr', 'StrToCurr', 'TextToFloat');
  cTwo: array[0..8] of string = ('FormatFloat', 'FormatDateTime', 'TryStrToFloat', 'StrToFloatDef',
    'TryStrToDate', 'StrToDateDef', 'TryStrToDateTime', 'StrToDateTimeDef', 'FormatCurr');
begin
  if MatchText(AName, cOne) then
  begin
    Result := 1;
  end
  else if MatchText(AName, cTwo) then
  begin
    Result := 2;
  end
  else if SameText(AName, 'FloatToStrF') then
  begin
    Result := 4;
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Steht bei APrev ein Punkt, der nicht SysUtils bzw. System.SysUtils qualifiziert (Writer.Format)?
/// </summary>
function IsForeignMember(const ATokens: TTokens; APrev: Integer): Boolean;
var
  mOwner: Integer;
begin
  Result := (APrev >= 0) and ATokens[APrev].IsSymbol('.');
  if Result then
  begin
    mOwner := PreviousCode(ATokens, APrev);
    Result := not ((mOwner >= 0) and MatchText(ATokens[mOwner].Text, ['SysUtils', 'System.SysUtils']));
  end;
end;

/// <summary>Formatierungsaufruf ohne TFormatSettings bei AIndex (Format mit %f/%n/%m/%g/%e, FloatToStr, StrToDate
/// …); AClose ist dann die schließende Klammer.</summary>
function IsLocaleCall(const ATokens: TTokens; AIndex: Integer; out AClose: Integer): Boolean;
var
  mOpen, mFirst, mPrev: Integer;
begin
  Result := False;
  AClose := -1;
  if ATokens[AIndex].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  mPrev := PreviousCode(ATokens, AIndex);
  mOpen := NextCode(ATokens, AIndex + 1);
  // Methoden wie Writer.Format bleiben außen vor; SysUtils.Format zählt.
  if (mOpen > High(ATokens)) or not ATokens[mOpen].IsSymbol('(') or IsForeignMember(ATokens, mPrev) then
  begin
    Exit;
  end;
  AClose := Closing(ATokens, mOpen);
  if AClose < 0 then
  begin
    Exit;
  end;
  if SameText(ATokens[AIndex].Text, 'Format') then
  begin
    mFirst := NextCode(ATokens, mOpen + 1);
    Result := (ArgumentCount(ATokens, mOpen, AClose) = 2) and
      (ATokens[mFirst].Kind = TPascalTokenKind.StringLiteral) and
      TFormatWithoutSettingsRule.HasLocaleSpecifier(ATokens[mFirst].Text);
  end
  else
  begin
    Result := (PlainArgumentCount(ATokens[AIndex].Text) > 0) and
      (ArgumentCount(ATokens, mOpen, AClose) = PlainArgumentCount(ATokens[AIndex].Text));
    // Festes Bild als einzelnes Literal: nur seine Trennzeichen hängen vom Gebietsschema ab.
    mFirst := NextCode(ATokens, mOpen + 1);
    if Result and MatchText(ATokens[AIndex].Text, ['FormatDateTime', 'FormatFloat', 'FormatCurr']) and
      (ATokens[mFirst].Kind = TPascalTokenKind.StringLiteral) and ATokens[NextCode(ATokens, mFirst + 1)].IsSymbol(',')
      then
    begin
      Result := TFormatWithoutSettingsRule.PictureDependsOnLocale(ATokens[AIndex].Text,
        StringReplace(Copy(ATokens[mFirst].Text, 2, Length(ATokens[mFirst].Text) - 2), '''''', '''', [rfReplaceAll]));
    end;
  end;
end;

/// <summary>Steht vor dem Namen an AIndex ein Punkt (SysUtils.Format)?</summary>
function IsQualified(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  mPrev: Integer;
begin
  mPrev := PreviousCode(ATokens, AIndex);
  Result := (mPrev >= 0) and ATokens[mPrev].IsSymbol('.');
end;

/// <summary>Rang von AUnitName unter den uses von AUnit, höchste Priorität zuerst (die letzten Einträge gewinnen,
/// implementation vor interface); -1, wenn die Unit nicht in uses steht.</summary>
function UsesRank(const AUnit: TUnitIndex; const AUnitNames: array of string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := High(AUnit.ImplementationUses) downto 0 do
  begin
    if MatchText(AUnit.ImplementationUses[mIndex], AUnitNames) then
    begin
      Exit(High(AUnit.ImplementationUses) - mIndex);
    end;
  end;
  for mIndex := High(AUnit.InterfaceUses) downto 0 do
  begin
    if MatchText(AUnit.InterfaceUses[mIndex], AUnitNames) then
    begin
      Exit(Length(AUnit.ImplementationUses) + High(AUnit.InterfaceUses) - mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Ruft der Name an AIndex eine eigene Routine statt der aus System.SysUtils auf? Aufgelöst wie vom
/// Compiler: lokale Routinen, Methoden der eigenen Klasse und Routinen der eigenen Unit verdecken die RTL, ebenso
/// eine Unit, die in uses nach System.SysUtils steht. Unbekannte Namen (ohne Index) gelten als RTL; ebenso eine
/// fremde Unit, wenn System.SysUtils in uses danach steht, aber nicht im Index ist.</summary>
function CallsOwnRoutine(const AContext: TRuleContext; var ACache: IRuleDerivedCache; const AToken: TPascalToken):
  Boolean;
var
  mResolved: TResolvedSymbol;
  mUnit: TUnitIndex;
  mOwnRank: Integer;
begin
  if ACache = nil then
  begin
    ACache := TRuleDerived.Open(AContext);
  end;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mResolved := TRuleDerived.Resolver(ACache, AContext).ResolveChain(AContext.Tree, AContext.RelativePath,
    [AToken.Text], AToken.Offset, False);
  if (mResolved.Kind in [TResolvedKind.None, TResolvedKind.UnitName]) or
    MatchText(mResolved.UnitName, ['System.SysUtils', 'SysUtils']) then
  begin
    Exit(False);
  end;
  mUnit := TRuleDerived.UnitIndex(ACache, AContext);
  if (mResolved.Kind = TResolvedKind.Local) or (mResolved.Container <> '') or
    SameText(mResolved.UnitName, mUnit.UnitName) then
  begin
    Exit(True);
  end;
  mOwnRank := UsesRank(mUnit, [mResolved.UnitName]);
  Result := (mOwnRank < 0) or (UsesRank(mUnit, ['System.SysUtils', 'SysUtils']) < 0) or
    (mOwnRank < UsesRank(mUnit, ['System.SysUtils', 'SysUtils']));
end;

procedure TFormatWithoutSettingsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mIndex, mClose: Integer;
  mCache: IRuleDerivedCache;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCache := nil;
  mTokens := AContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    // Erst das Muster, dann die Auflösung: Eine eigene Routine gleichen Namens (auch aus einer anderen Unit) ist
    // nicht die aus System.SysUtils. SysUtils.Format ist ausdrücklich die RTL.
    if IsLocaleCall(mTokens, mIndex, mClose) and (IsQualified(mTokens, mIndex) or
      not CallsOwnRoutine(AContext, mCache, mTokens[mIndex])) then
    begin
      AReport.Add(RangeOf(mTokens, mIndex, mClose), cTexts[TRtlTypePatternsConversionsText.Locale].Fmt(
        [mTokens[mIndex].Text]), TRuleConfidence.Medium,
          [TRuleFix.Create(cTexts[TRtlTypePatternsConversionsText.PassFormatSettings].Text,
        [TRuleEdit.Create(TTextRange.Create(mTokens[mClose].StartPos, mTokens[mClose].StartPos),
        ', FormatSettings')])]);
    end;
  end;
end;

{ TUncheckedConversionRule }

type
  /// <summary>Umwandlung mit Try-Gegenstück: Zieltypen, die als out-Parameter passen, und Meldungstext.</summary>
  TCheckedConversion = record
    Name: string;
    Types: string;
    Problem: TRtlTypePatternsConversionsText;
  end;

const
  cCheckedConversions: array[0..8] of TCheckedConversion = (
    (Name: 'StrToInt'; Types: ',integer,longint,'; Problem: TRtlTypePatternsConversionsText.NotNumber),
    (Name: 'StrToInt64'; Types: ',int64,'; Problem: TRtlTypePatternsConversionsText.NotNumber),
    (Name: 'StrToFloat'; Types: ',double,extended,single,'; Problem: TRtlTypePatternsConversionsText.NotNumber),
    (Name: 'StrToCurr'; Types: ',currency,'; Problem: TRtlTypePatternsConversionsText.NotAmount),
    (Name: 'StrToDate'; Types: ',tdatetime,'; Problem: TRtlTypePatternsConversionsText.NotDate),
    (Name: 'StrToDateTime'; Types: ',tdatetime,'; Problem: TRtlTypePatternsConversionsText.NotDateTime),
    (Name: 'StrToTime'; Types: ',tdatetime,'; Problem: TRtlTypePatternsConversionsText.NotTime),
    (Name: 'StrToBool'; Types: ',boolean,'; Problem: TRtlTypePatternsConversionsText.NotBoolean),
    (Name: 'StrToUInt'; Types: ',cardinal,longword,'; Problem: TRtlTypePatternsConversionsText.NotNumber));
  // Hüllen, durch die die Eingabe unverändert geprüft wird: StrToInt(Trim(Edit.Text)).
  cTransparentCalls: array[0..3] of string = ('Trim', 'TrimLeft', 'TrimRight', 'Copy');

function TUncheckedConversionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unchecked-conversion', TRuleSeverity.Hint,
    cTexts[TRtlTypePatternsConversionsText.UncheckedTitle].Text);
end;

/// <summary>ANode ohne umgebende Klammern.</summary>
function WithoutParentheses(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

/// <summary>Hülle wie Trim(…), durch die die Eingabe unverändert geprüft wird?</summary>
function IsTransparentCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) and MatchText(ANode.Name, cTransparentCalls);
end;

/// <summary>Eingabe aus einer der Quellen ASources: Edit.Text, Grid.Cells[C, R], Memo.Lines[I]?</summary>
function IsInputNode(ANode: TSyntaxNode; const ASources: TArray<string>): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.MemberAccess:
      Result := MatchText(ANode.Name, ASources);
    TSyntaxKind.IndexAccess:
      Result := (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.MemberAccess) and
        MatchText(ANode.Name, ASources);
  else
    Result := False;
  end;
end;

procedure TUncheckedConversionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mFunctions, mSources: TArray<string>;
  mTypes: TDeclaredTypes;
  mLineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Edit.Text, Grid.Cells[C, R], Memo.Lines[I], auch in Trim(…); nil, wenn das Argument keine Eingabe ist.
  function InputSource(ANode: TSyntaxNode): TSyntaxNode;
  var
    mNode: TSyntaxNode;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht): durch Klammern und Hüllen wie Trim(…) hindurch.
    mNode := WithoutParentheses(ANode);
    while IsTransparentCall(mNode) do
    begin
      mNode := WithoutParentheses(mNode[1]);
    end;
    Result := nil;
    if IsInputNode(mNode, mSources) then
    begin
      Result := mNode;
    end;
  end;

  // Im try-Teil eines try/except: die Fehleingabe wird abgefangen.
  function Caught(ANode: TSyntaxNode): Boolean;
  var
    mChild, mParent: TSyntaxNode;
  begin
    mChild := ANode;
    mParent := ANode.Parent;
    while (mParent <> nil) and not (mParent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    begin
      if (mParent.Kind = TSyntaxKind.TryStatement) and not (mChild.Kind in [TSyntaxKind.ExceptBlock,
        TSyntaxKind.FinallyBlock]) and (mParent.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
      begin
        Exit(True);
      end;
      mChild := mParent;
      mParent := mParent.Parent;
    end;
    Result := False;
  end;

  function ConversionOf(const AName: string; out AConversion: TCheckedConversion): Boolean;
  var
    mConversion: TCheckedConversion;
  begin
    for mConversion in cCheckedConversions do
    begin
      if SameText(mConversion.Name, AName) then
      begin
        AConversion := mConversion;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // X := StrToInt(Edit.Text); als eigene Anweisung in einer Anweisungsliste, X eine Variable des
  // passenden Typs: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create('X ist keine Zahl').
  function Fixes(ACall, AArgument: TSyntaxNode): TArray<TRuleFix>;
  var
    mStatement, mTarget: TSyntaxNode;
    mConversion: TCheckedConversion;
    mTypeName, mIndent: string;
  begin
    Result := nil;
    mStatement := ACall.Parent;
    if not IsListedAssignment(mStatement, ACall) then
    begin
      Exit;
    end;
    mTarget := mStatement[0];
    if (mTarget.Kind <> TSyntaxKind.Identifier) or not ConversionOf(ACall.Name, mConversion) then
    begin
      Exit;
    end;
    mTypeName := LowerCase(mTypes.DeclaredType(mTarget.Name, mTarget.StartPos));
    if (mTypeName = '') or (Pos(',' + mTypeName + ',', mConversion.Types) = 0) then
    begin
      Exit;
    end;
    mIndent := StringOfChar(' ', mStatement.StartPos.Character);
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsConversionsText.RewriteTry].Fmt([mConversion.Name]),
      [TRuleEdit.Create(TTextRange.Create(mStatement.StartPos, mStatement.EndPos), 'if not Try' + mConversion.Name +
      '(' + Text(AArgument) + ', ' + mTarget.Name + ') then' + mLineBreak + mIndent + '  raise EConvertError.Create(''' +
      mTarget.Name + ' ' + cTexts[mConversion.Problem].Text + ''')')])];
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mSource: TSyntaxNode;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount = 2) and MatchText(mNode.Name, mFunctions) then
        begin
          mSource := InputSource(mNode[1]);
          if (mSource <> nil) and not Caught(mNode) then
          begin
            AReport.Add(TTextRange.Create(mNode.StartPos, mNode.EndPos),
              cTexts[TRtlTypePatternsConversionsText.Unchecked].Fmt([Text(mSource)]), TRuleConfidence.Medium,
              Fixes(mNode, mNode[1]));
          end;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mDefaults: TArray<string>;
  mName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mDefaults := nil;
  for mName in cDefaultFunctions do
  begin
    mDefaults := mDefaults + [mName];
  end;
  mFunctions := TRuleOptions.Strings(AContext.Options, 'functions', mDefaults);
  mDefaults := nil;
  for mName in cDefaultSources do
  begin
    mDefaults := mDefaults + [mName];
  end;
  mSources := TRuleOptions.Strings(AContext.Options, 'sources', mDefaults);
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    mTypes.Free;
  end;
end;

{ TUncheckedEnumCastRule }

const
  cDefaultEnumSources: array[0..3] of string = ('FieldByName', 'ReadInteger', 'AsInteger', 'StrToInt');
  // Aufrufe, die den Wert schon begrenzen: TStatus(EnsureRange(…)).
  cEnumGuards: array[0..2] of string = ('EnsureRange', 'Min', 'Max');

function TUncheckedEnumCastRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unchecked-enum-cast', TRuleSeverity.Hint,
    cTexts[TRtlTypePatternsConversionsText.EnumCastTitle].Text);
end;

class function TUncheckedEnumCastRule.Origin(const ASource: string): string;
begin
  if MatchText(ASource, ['ReadInteger', 'ReadInt64', 'ReadBinaryData']) then
  begin
    Result := cTexts[TRtlTypePatternsConversionsText.FromRegistry].Text;
  end
  else if MatchText(ASource, ['StrToInt', 'StrToInt64', 'StrToIntDef', 'StrToUInt']) then
  begin
    Result := cTexts[TRtlTypePatternsConversionsText.FromText].Text;
  end
  else if MatchText(ASource, ['FieldByName', 'FindField', 'Fields', 'FieldValues', 'AsInteger', 'AsLargeInt',
    'AsLongWord', 'AsSmallInt', 'ParamByName']) then
  begin
    Result := cTexts[TRtlTypePatternsConversionsText.FromDatabase].Text;
  end
  else
  begin
    Result := cTexts[TRtlTypePatternsConversionsText.FromOutside].Text;
  end;
end;

procedure TUncheckedEnumCastRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mCode: TArray<Integer>;
  mSources: TArray<string>;
  mLineBreak: string;
  mLocal: TUnitIndex;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    mDepth: Integer;
  begin
    mDepth := 0;
    for Result := AOpen to High(mCode) do
    begin
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(mDepth);
        if mDepth = 0 then
        begin
          Exit;
        end;
      end;
    end;
    Result := -1;
  end;

  function CodeAt(AOffset: Integer): Integer;
  var
    mHigh, mMiddle: Integer;
  begin
    // Binär statt ab Dateianfang mit einer Kopie je Token: Code steht nach Offset sortiert (#1342).
    Result := 0;
    mHigh := Length(mCode);
    while Result < mHigh do
    begin
      mMiddle := (Result + mHigh) div 2;
      if mTokens[mCode[mMiddle]].Offset < AOffset then
      begin
        Result := mMiddle + 1;
      end
      else
      begin
        mHigh := mMiddle;
      end;
    end;
  end;

  // Aufzählungstyp AName in AUnit: Zahl der Werte und ob sie eigene Ordinalwerte tragen.
  function EnumIn(const AUnit: TUnitIndex; const AName: string; out ACount: Integer;
    out AExplicit: Boolean): Boolean;
  var
    mSymbol: TIndexSymbol;
    mSignature: string;
  begin
    Result := False;
    ACount := 0;
    AExplicit := False;
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.EnumType) and (mSymbol.Container = '') and SameText(mSymbol.Name, AName) then
      begin
        mSignature := mSymbol.Signature;
        AExplicit := (Pos('(', mSignature) > 0) and (Pos('=', Copy(mSignature, Pos('(', mSignature), MaxInt)) > 0);
        Result := True;
      end;
    end;
    if not Result then
    begin
      Exit;
    end;
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, AName) then
      begin
        Inc(ACount);
      end;
    end;
  end;

  function EnumInfo(const AName: string; out ACount: Integer; out AExplicit: Boolean): Boolean;
  var
    mLocation: TSymbolLocation;
    mOwner: TUnitIndex;
  begin
    if EnumIn(mLocal, AName, ACount, AExplicit) then
    begin
      Exit(True);
    end;
    Result := False;
    if AContext.Index = nil then
    begin
      Exit;
    end;
    for mLocation in AContext.Index.FindSymbols(AName) do
    begin
      if (mLocation.Symbol.Kind = TIndexSymbolKind.EnumType) and (mLocation.Symbol.Container = '') and
        AContext.Index.FindFile(mLocation.FileName, mOwner) and EnumIn(mOwner, AName, ACount, AExplicit) then
      begin
        Exit(True);
      end;
    end;
  end;

  // Erste Quelle (aus "sources") zwischen AFirst und ALast; '' ohne.
  function SourceIn(AFirst, ALast: Integer): string;
  var
    mPosition: Integer;
  begin
    for mPosition := AFirst to ALast do
    begin
      if IsWord(mPosition) and MatchText(Token(mPosition).Text, mSources) then
      begin
        Exit(Token(mPosition).Text);
      end;
    end;
    Result := '';
  end;

  // V := Ausdruck mit Quelle vor ACast in der Routine, ohne dass V danach noch gelesen wird (Prüfung).
  function VariableSource(ARoutine: TSyntaxNode; AVariable, ACast: Integer): string;
  var
    mPosition, mAssigned, mEnding: Integer;
  begin
    Result := '';
    mAssigned := -1;
    for mPosition := CodeAt(ARoutine.StartOffset) to ACast - 1 do
    begin
      if IsWord(mPosition) and SameText(Token(mPosition).Text, Token(AVariable).Text) and
        not IsSym(mPosition - 1, '.') then
      begin
        if IsSym(mPosition + 1, ':=') then
        begin
          mAssigned := mPosition;
        end
        else if mAssigned >= 0 then
        begin
          // Gelesen zwischen Zuweisung und Umwandlung: als geprüft ansehen (InRange, Vergleich, case …).
          Exit('');
        end;
      end;
    end;
    if mAssigned < 0 then
    begin
      Exit;
    end;
    mEnding := mAssigned + 2;
    while (mEnding <= High(mCode)) and not Token(mEnding).IsSymbol(';') and not Token(mEnding).IsKeyword('end') do
    begin
      Inc(mEnding);
    end;
    Result := SourceIn(mAssigned + 2, mEnding - 1);
    if (Result <> '') and IsWord(mAssigned + 2) and MatchText(Token(mAssigned + 2).Text, cEnumGuards) then
    begin
      Result := '';
    end;
  end;

  // Korrektur bei TStatus(Quelle) in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise davor.
  function Fixes(ARoutine: TSyntaxNode; const ATypeName: string; AFirst, ALast: Integer): TArray<TRuleFix>;
  var
    mStatement: TSyntaxNode;
    mName, mIndent, mPrefix: string;
    mEdits: TArray<TTextEdit>;
    mUsesEdit: TTextEdit;
    mUsed: TArray<string>;
  begin
    Result := nil;
    mStatement := TRoutineBody.Enclosing(ARoutine, Token(AFirst).Offset, Token(ALast).Offset);
    while (mStatement <> nil) and (mStatement <> ARoutine) and not TRoutineBody.IsStatement(mStatement) do
    begin
      mStatement := mStatement.Parent;
    end;
    if (mStatement = nil) or (mStatement = ARoutine) or not TRoutineBody.InList(mStatement) or
      (mStatement.Kind in [TSyntaxKind.Block, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement,
      TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement]) then
    begin
      Exit;
    end;
    mName := TRoutineBody.UniqueName(mTokens, AContext.NewNames.Local('Wert'));
    mIndent := TTextLines.IndentOf(AContext.Text, mStatement.StartPos.Line);
    mEdits := [TRoutineBody.AddVariable(AContext.Text, ARoutine, mName, 'Integer', AContext.Formatting),
      TRoutineBody.InsertBefore(AContext.Text, mStatement, mName + ' := ' + TextOf(AFirst, ALast) + ';' +
      mLineBreak + mIndent + 'if not InRange(' + mName + ', Ord(Low(' + ATypeName + ')), Ord(High(' + ATypeName +
      '))) then' + mLineBreak + mIndent + TRoutineBody.IndentUnit(AContext.Formatting) +
      cTexts[TRtlTypePatternsConversionsText.InvalidValueCode].Text + ATypeName + ''', [' + mName + ']);'),
      TTextEdit.Create(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), mName)];
    // InRange steht in System.Math.
    mUsed := TUsesClauses.UsedUnits(mTokens);
    if not MatchText('System.Math', mUsed) and not MatchText('Math', mUsed) then
    begin
      mPrefix := 'System.';
      if (Length(mUsed) > 0) and not MatchText('System.SysUtils', mUsed) and MatchText('SysUtils', mUsed) then
      begin
        mPrefix := '';
      end;
      if not TUsesClauses.AddUnit(mTokens, Token(AFirst).Offset, mPrefix + 'Math', mLineBreak, mUsesEdit) then
      begin
        Exit;
      end;
      mEdits := [mUsesEdit] + mEdits;
    end;
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsConversionsText.InsertInRange].Text, mEdits)];
  end;

  procedure CheckCast(APosition: Integer);
  var
    mClose, mCount: Integer;
    mExplicit: Boolean;
    mTypeName, mSource, mRange: string;
    mRoutine: TSyntaxNode;
    mDirect: Boolean;
  begin
    mClose := Closing(APosition + 1);
    if (mClose < 0) or (mClose = APosition + 2) then
    begin
      Exit;
    end;
    mTypeName := Token(APosition).Text;
    if not EnumInfo(mTypeName, mCount, mExplicit) then
    begin
      Exit;
    end;
    mRoutine := TRoutineBody.RoutineAt(AContext.Tree, Token(APosition).Offset);
    if mRoutine = nil then
    begin
      Exit;
    end;
    // Direkt: TStatus(qry.FieldByName('Status').AsInteger); über eine Variable: TStatus(Wert).
    mDirect := not (IsWord(APosition + 2) and MatchText(Token(APosition + 2).Text, cEnumGuards));
    mSource := '';
    if mDirect then
    begin
      mSource := SourceIn(APosition + 2, mClose - 1);
    end;
    if (mSource = '') and (mClose = APosition + 3) and IsWord(APosition + 2) then
    begin
      mSource := VariableSource(mRoutine, APosition + 2, APosition);
      mDirect := False;
    end;
    if mSource = '' then
    begin
      Exit;
    end;
    if mExplicit or (mCount = 0) then
    begin
      mRange := Format('Ord(Low(%s))..Ord(High(%s))', [mTypeName, mTypeName]);
    end
    else
    begin
      mRange := Format('0..%d', [mCount - 1]);
    end;
    if mDirect then
    begin
      AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(mClose).EndPos),
        cTexts[TRtlTypePatternsConversionsText.EnumCast].Fmt(
        [Origin(mSource), mTypeName, mRange, mTypeName]), TRuleConfidence.Medium,
        Fixes(mRoutine, mTypeName, APosition + 2, mClose - 1));
    end
    else
    begin
      AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(mClose).EndPos),
        cTexts[TRtlTypePatternsConversionsText.EnumCast].Fmt(
        [Origin(mSource), mTypeName, mRange, mTypeName]), TRuleConfidence.Medium);
    end;
  end;

var
  mIndex, mPosition: Integer;
  mDefaults: TArray<string>;
  mName: string;
  mCache: IRuleDerivedCache;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mDefaults := nil;
  for mName in cDefaultEnumSources do
  begin
    mDefaults := mDefaults + [mName];
  end;
  mSources := TRuleOptions.Strings(AContext.Options, 'sources', mDefaults);
  if Length(mSources) = 0 then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsTrivia(mTokens[mIndex]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mCache := TRuleDerived.Open(AContext);
  mLocal := TRuleDerived.UnitIndex(mCache, AContext);
  for mPosition := 0 to High(mCode) - 2 do
  begin
    // TName( … ) als Ausdruck: kein Punkt davor (X.TName), kein Typ in einer Deklaration.
    if IsWord(mPosition) and (Token(mPosition).Text[1] = 'T') and IsSym(mPosition + 1, '(') and
      not IsSym(mPosition - 1, '.') then
    begin
      CheckCast(mPosition);
    end;
  end;
end;

{ TGlobalFormatSettingsModifiedRule }

function TGlobalFormatSettingsModifiedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('global-formatsettings-modified', TRuleSeverity.Warning,
    cTexts[TRtlTypePatternsConversionsText.GlobalTitle].Text);
end;

class function TGlobalFormatSettingsModifiedRule.Subject(const AField: string): string;
const
  // In der Reihenfolge von DeprecatedGlobals.
  cSubjectTexts: array[0..19] of TRtlTypePatternsConversionsText = (TRtlTypePatternsConversionsText.CurrencyString,
    TRtlTypePatternsConversionsText.CurrencyFormat, TRtlTypePatternsConversionsText.NegCurrFormat,
    TRtlTypePatternsConversionsText.ThousandSeparator, TRtlTypePatternsConversionsText.DecimalSeparator,
    TRtlTypePatternsConversionsText.CurrencyDecimals, TRtlTypePatternsConversionsText.DateSeparator,
    TRtlTypePatternsConversionsText.ShortDateFormat, TRtlTypePatternsConversionsText.LongDateFormat,
    TRtlTypePatternsConversionsText.TimeSeparator, TRtlTypePatternsConversionsText.TimeAMString,
    TRtlTypePatternsConversionsText.TimePMString, TRtlTypePatternsConversionsText.ShortTimeFormat,
    TRtlTypePatternsConversionsText.LongTimeFormat, TRtlTypePatternsConversionsText.ShortMonthNames,
    TRtlTypePatternsConversionsText.LongMonthNames, TRtlTypePatternsConversionsText.ShortDayNames,
    TRtlTypePatternsConversionsText.LongDayNames, TRtlTypePatternsConversionsText.ListSeparator,
    TRtlTypePatternsConversionsText.TwoDigitYearCenturyWindow);
var
  mIndex: Integer;
begin
  if AField = '' then
  begin
    Exit(cTexts[TRtlTypePatternsConversionsText.AllSettings].Text);
  end;
  for mIndex := 0 to High(cDeprecatedGlobals) do
  begin
    if SameText(cDeprecatedGlobals[mIndex], AField) then
    begin
      Exit(cTexts[cSubjectTexts[mIndex]].Text);
    end;
  end;
  Result := cTexts[TRtlTypePatternsConversionsText.TheSetting].Fmt([AField]);
end;

type
  /// <summary>Gefundene Zuweisung an die globale FormatSettings bzw. eine veraltete globale Variable.</summary>
  TFormatSettingsModification = record
    Statement: TSyntaxNode;
    Target: TSyntaxNode;
    Routine: TSyntaxNode;
    /// <summary>Feld hinter FormatSettings bzw. die veraltete Variable; '' = die ganze FormatSettings.</summary>
    Field: string;
  end;

/// <summary>Name der geprüften Datei: FileName, sonst der relative Pfad, sonst Unitname mit .pas.</summary>
function RuleFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

/// <summary>Zahl der Änderungen in AFound, die in der Routine ARoutine stehen.</summary>
function ModificationCount(const AFound: TArray<TFormatSettingsModification>; ARoutine: TSyntaxNode): Integer;
var
  mItem: TFormatSettingsModification;
begin
  Result := 0;
  for mItem in AFound do
  begin
    if mItem.Routine = ARoutine then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TGlobalFormatSettingsModifiedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // RTL- und VCL-Basisklassen ohne Mitglieder namens FormatSettings, DecimalSeparator …: Bricht die Kette der
  // Vorfahren ohne Index an einer von ihnen ab, ist der Name trotzdem sicher die globale Variable.
  cSafeBases: array[0..18] of string = ('TObject', 'TInterfacedObject', 'TAggregatedObject', 'TContainedObject',
    'TPersistent', 'TInterfacedPersistent', 'TComponent', 'TThread', 'TCustomAttribute', 'TControl', 'TWinControl',
    'TCustomControl', 'TGraphicControl', 'TScrollingWinControl', 'TCustomForm', 'TForm', 'TCustomFrame', 'TFrame',
    'TDataModule');
var
  mTokens: TTokens;
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName, mLineBreak: string;
  mUsed, mLines: TArray<string>;
  mFound: TArray<TFormatSettingsModification>;
  mItem: TFormatSettingsModification;
  mFixes: TArray<TRuleFix>;
  mFix: TRuleFix;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function ChainOf(ANode: TSyntaxNode; out ANames: TArray<string>): Boolean;
  var
    mNode: TSyntaxNode;
    mMembers: TArray<string>;
    mIndex: Integer;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht): am Empfänger entlang nach innen, die Namen dann von innen nach außen.
    ANames := nil;
    mMembers := nil;
    mNode := ANode;
    while (mNode.Kind = TSyntaxKind.MemberAccess) and (mNode.ChildCount > 0) do
    begin
      mMembers := mMembers + [mNode.Name];
      mNode := mNode[0];
    end;
    Result := mNode.Kind = TSyntaxKind.Identifier;
    if not Result then
    begin
      Exit;
    end;
    ANames := [mNode.Name];
    for mIndex := High(mMembers) downto 0 do
    begin
      ANames := ANames + [mMembers[mIndex]];
    end;
  end;

  function InWith(ANode: TSyntaxNode): Boolean;
  begin
    Result := False;
    while (ANode <> nil) and (ANode.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      if ANode.Kind = TSyntaxKind.WithStatement then
      begin
        Exit(True);
      end;
      ANode := ANode.Parent;
    end;
  end;

  /// <summary>Kann ein Vorfahr der Klasse, in deren Methode AOffset liegt, den Namen selbst deklarieren? Ja, wenn
  /// die Kette an einem unbekannten Vorfahren abbricht, der nicht in SafeBases steht.</summary>
  function UnknownAncestor(AOffset: Integer): Boolean;
  var
    mCurrent, mNext: TResolvedSymbol;
    mExpected: string;
    mDepth: Integer;
  begin
    Result := False;
    mCurrent := mResolver.ResolveChain(AContext.Tree, mFileName, ['Self'], AOffset);
    if mCurrent.Kind <> TResolvedKind.Symbol then
    begin
      Exit;
    end;
    for mDepth := 1 to 64 do
    begin
      if mResolver.AncestorOf(mCurrent, mNext) then
      begin
        mCurrent := mNext;
        Continue;
      end;
      mExpected := '';
      if Length(mCurrent.Ancestors) > 0 then
      begin
        mExpected := mCurrent.Ancestors[0];
      end
      else if (mCurrent.SymbolKind = TIndexSymbolKind.ClassType) and not SameText(mCurrent.Name, 'TObject') then
      begin
        mExpected := 'TObject';
      end;
      if Pos('.', mExpected) > 0 then
      begin
        mExpected := Copy(mExpected, LastDelimiter('.', mExpected) + 1, MaxInt);
      end;
      Exit((mExpected <> '') and not MatchText(mExpected, cSafeBases));
    end;
  end;

  /// <summary>Ist AName an der Stelle sicher die globale Variable aus System.SysUtils?</summary>
  function IsGlobal(AStatement: TSyntaxNode; const AName: string; AQualified: Boolean): Boolean;
  var
    mResolved: TResolvedSymbol;
  begin
    if AQualified then
    begin
      Exit(True);
    end;
    Result := False;
    if InWith(AStatement) or not (MatchText('System.SysUtils', mUsed) or MatchText('SysUtils', mUsed)) then
    begin
      Exit;
    end;
    mResolved := mResolver.ResolveChain(AContext.Tree, mFileName, [AName], AStatement.StartOffset);
    case mResolved.Kind of
      TResolvedKind.Local, TResolvedKind.UnitName:
        Exit;
      TResolvedKind.Symbol:
        if not MatchText(mResolved.UnitName, ['System.SysUtils', 'SysUtils']) then
        begin
          Exit;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    Result := not UnknownAncestor(AStatement.StartOffset);
  end;

  procedure Inspect(AStatement: TSyntaxNode);
  var
    mTarget: TSyntaxNode;
    mNames: TArray<string>;
    mFirst: Integer;
    mModification: TFormatSettingsModification;
  begin
    mTarget := AStatement[0];
    while (mTarget.Kind = TSyntaxKind.IndexAccess) and (mTarget.ChildCount > 0) do
    begin
      mTarget := mTarget[0];
    end;
    if not ChainOf(mTarget, mNames) then
    begin
      Exit;
    end;
    mFirst := 0;
    if (Length(mNames) >= 3) and SameText(mNames[0], 'System') and SameText(mNames[1], 'SysUtils') then
    begin
      mFirst := 2;
    end
    else if (Length(mNames) >= 2) and SameText(mNames[0], 'SysUtils') then
    begin
      mFirst := 1;
    end;
    mModification.Field := '';
    if SameText(mNames[mFirst], 'FormatSettings') and (Length(mNames) - mFirst <= 2) then
    begin
      if Length(mNames) - mFirst = 2 then
      begin
        mModification.Field := mNames[mFirst + 1];
      end;
    end
    else if (Length(mNames) - mFirst = 1) and MatchText(mNames[mFirst], cDeprecatedGlobals) then
    begin
      mModification.Field := mNames[mFirst];
    end
    else
    begin
      Exit;
    end;
    if not IsGlobal(AStatement, mNames[mFirst], mFirst > 0) then
    begin
      Exit;
    end;
    mModification.Statement := AStatement;
    mModification.Target := AStatement[0];
    mModification.Routine := TRoutineBody.RoutineAt(AContext.Tree, AStatement.StartOffset);
    mFound := mFound + [mModification];
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mChild: Integer;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount >= 2) then
        begin
          Inspect(mNode);
        end;
        for mChild := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mChild]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Formatierungsaufrufe nach der Anweisung bis zum Ende des Rumpfs: AName als letztes Argument.</summary>
  function CallEdits(ABody: TSyntaxNode; const AItem: TFormatSettingsModification;
    const AName: string): TArray<TRuleEdit>;
  var
    mPosition, mClose: Integer;
  begin
    Result := nil;
    mPosition := TRoutineBody.TokenAt(mTokens, AItem.Statement.EndOffset);
    while (mPosition <= High(mTokens)) and (mTokens[mPosition].Offset < ABody.EndOffset) do
    begin
      if IsLocaleCall(mTokens, mPosition, mClose) then
      begin
        Result := Result + [TRuleEdit.Create(TTextRange.Create(mTokens[mClose].StartPos, mTokens[mClose].StartPos),
          ', ' + AName)];
      end;
      Inc(mPosition);
    end;
  end;

  /// <summary>Feld samt Index wie geschrieben: ShortMonthNames[1] aus FormatSettings.ShortMonthNames[1]; '' wenn
  /// das Feld im Ziel nicht steht.</summary>
  function FieldTail(const AItem: TFormatSettingsModification): string;
  var
    mField: Integer;
  begin
    Result := '';
    mField := TRoutineBody.TokenAt(mTokens, AItem.Target.StartOffset);
    while (mField <= High(mTokens)) and (mTokens[mField].Offset < AItem.Target.EndOffset) and
      not IsIdentifierNamed(mTokens[mField], AItem.Field) do
    begin
      Inc(mField);
    end;
    if (mField <= High(mTokens)) and (mTokens[mField].Offset < AItem.Target.EndOffset) then
    begin
      Result := Copy(AContext.Text, mTokens[mField].Offset + 1, AItem.Target.EndOffset - mTokens[mField].Offset);
    end;
  end;

  /// <summary>Neuer Text der Zuweisung mit der lokalen TFormatSettings AName; False, wenn das Feld im Ziel nicht
  /// zu finden ist.</summary>
  function AssignmentText(const AItem: TFormatSettingsModification; const AName: string; out AText: string): Boolean;
  var
    mValue, mTail: string;
  begin
    Result := True;
    mValue := NodeText(AItem.Statement[1]);
    if AItem.Field = '' then
    begin
      AText := AName + ' := ' + mValue;
    end
    else if SameText(AItem.Field, 'DecimalSeparator') and (mValue = '''.''') then
    begin
      AText := AName + ' := TFormatSettings.Invariant';
    end
    else
    begin
      mTail := FieldTail(AItem);
      Result := mTail <> '';
      AText := AName + ' := FormatSettings;' + mLineBreak + TTextLines.IndentOf(mLines[AItem.Statement.StartPos.Line]) +
        AName + '.' + mTail + ' := ' + mValue;
    end;
  end;

  /// <summary>Einzeilige Anweisung in einer Anweisungsliste?</summary>
  function IsSingleLineStatement(const AItem: TFormatSettingsModification): Boolean;
  begin
    Result := TRoutineBody.InList(AItem.Statement) and (AItem.Statement.StartPos.Line = AItem.Statement.EndPos.Line) and
      (AItem.Statement.StartPos.Line <= High(mLines));
  end;

  /// <summary>Lokale TFormatSettings anlegen, statt der Zuweisung belegen und an die Formatierungsaufrufe danach
  /// übergeben. Nur bei einer einzeiligen Anweisung in einer Anweisungsliste mit mindestens einem solchen Aufruf.
  /// </summary>
  function LocalFix(const AItem: TFormatSettingsModification; out AFix: TRuleFix): Boolean;
  var
    mBody: TSyntaxNode;
    mName, mText: string;
    mEdits, mCalls: TArray<TRuleEdit>;
  begin
    Result := False;
    mBody := TRoutineBody.BodyOf(AItem.Routine);
    if (mBody = nil) or not IsSingleLineStatement(AItem) then
    begin
      Exit;
    end;
    mName := TRoutineBody.UniqueName(mTokens, AContext.NewNames.Local('FS'));
    mCalls := CallEdits(mBody, AItem, mName);
    if (mCalls = nil) or not AssignmentText(AItem, mName, mText) then
    begin
      Exit;
    end;
    mEdits := [TRoutineBody.AddVariable(AContext.Text, AItem.Routine, mName, 'TFormatSettings', AContext.Formatting),
      TRuleEdit.Create(TTextRange.Create(AItem.Statement.StartPos, AItem.Statement.EndPos), mText)];
    mEdits := mEdits + mCalls;
    AFix := TRuleFix.Create(cTexts[TRtlTypePatternsConversionsText.LocalSettings].Text, mEdits);
    Result := True;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  if (AContext.Tree.Root.Kind in [TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) and
    TRuleOptions.Bool(AContext.Options, 'allowInProgram', False) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mUsed := TUsesClauses.UsedUnits(mTokens);
  mFileName := RuleFileName(AContext);
  mLines := TTextLines.SplitLines(AContext.Text);
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mFound := nil;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  Visit(AContext.Tree.Root);
  for mItem in mFound do
  begin
    // Die Korrektur nur bei genau einer Änderung in der Routine; sonst stellt sie etwa ein Zurücksetzen im
    // finally nicht sinnvoll um.
    mFixes := nil;
    if (mItem.Routine <> nil) and (ModificationCount(mFound, mItem.Routine) = 1) and LocalFix(mItem, mFix) then
    begin
      mFixes := [mFix];
    end;
    AReport.Add(TTextRange.Create(mItem.Statement.StartPos, mItem.Statement.EndPos),
      cTexts[TRtlTypePatternsConversionsText.Global].Fmt([Subject(mItem.Field)]), TRuleConfidence.High, mFixes);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.RtlTypePatterns.Conversions', cTexts);

end.
