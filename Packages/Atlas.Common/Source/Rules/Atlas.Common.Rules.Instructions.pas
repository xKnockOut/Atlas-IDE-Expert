unit Atlas.Common.Rules.Instructions;

// Abschnitt für die Anweisungsdatei eines KI-Assistenten (#2615): kurze Fassung der Projektkonventionen aus
// atlas.json und dem Regelkatalog (Profil, Grenzwerte der Metriken, Benennung, verbotene Symbole, Regeln, die
// atlas.json auf Fehler setzt, geschützte Dateien aus assistants.protected, Pflichtprüfungen aus
// assistants.instructions.checks). Der Abschnitt steht zwischen
// <!-- atlas:begin … --> und <!-- atlas:end -->; Apply ersetzt nur ihn und lässt den übrigen Text Zeichen für Zeichen
// stehen. Die Sprache wählt der Aufrufer (mcp.promptLanguage), nicht die Oberfläche. Kein Text nennt ein Produkt.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  /// <summary>Stand des Abschnitts in einer Datei: aktuell, veraltet oder (noch) nicht vorhanden.</summary>
  TInstructionsState = (Current, Stale, Missing);
{$SCOPEDENUMS OFF}

  TRuleInstructions = class
  public const
    cBeginMarker = '<!-- atlas:begin';
    cEndMarker = '<!-- atlas:end -->';
  public
    /// <summary>Abschnitt mit beiden Markierungen, Zeilen mit #10 getrennt, ohne Umbruch am Ende. ACatalog in der
    /// Sprache ALanguage; nil = Namen der Regeln aus der Beschreibung.</summary>
    class function Section(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ACatalog: TRuleCatalog; ALanguage: TTextLanguage): string; static;
    /// <summary>Sprache aus mcp.promptLanguage: en englisch, sonst deutsch.</summary>
    class function LanguageOf(const ASettings: TServerSettings): TTextLanguage; static;
    /// <summary>Vorhandener Abschnitt von der Anfangs- bis zur Schlussmarkierung, Umbrüche als #10; '' ohne
    /// vollständigen Abschnitt.</summary>
    class function Extract(const AText: string): string; static;
    /// <summary>AText mit ASection an Stelle des vorhandenen Abschnitts, sonst am Ende angehängt; Umbrüche des
    /// Abschnitts als ALineBreak. Der Text außerhalb bleibt unverändert.</summary>
    class function Apply(const AText, ASection, ALineBreak: string): string; static;
    /// <summary>Steht ASection so in AText?</summary>
    class function State(const AText, ASection: string): TInstructionsState; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Conventions,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Rules.Builtin.ForbiddenSymbols;

{$SCOPEDENUMS ON}

type
  TInstructionsText = (BeginLine, Heading, CheckCode, Limits, Limit, Naming, Prefixes, Local, Field, Parameter,
    Constant, Forbidden, FirstArgument, Instead, Errors, Protected, ProtectedUse, Checks);

const
  cTexts: array[TInstructionsText] of TAtlasText = (
    (De: '<!-- atlas:begin (erzeugt aus atlas.json, nicht von Hand ändern) -->';
     En: '<!-- atlas:begin (generated from atlas.json, do not edit by hand) -->'),
    (De: '## Prüfregeln (Profil `%s`, 0 Befunde Pflicht)'; En: '## Code rules (profile `%s`, 0 findings required)'),
    (De: 'Delphi-Code nach jeder Änderung mit `check_code` prüfen; Einzelheiten in `delphi://conventions`.';
     En: 'Check Delphi code with `check_code` after every change; details in `delphi://conventions`.'),
    (De: '### Grenzwerte'; En: '### Limits'),
    (De: '- %s: höchstens %d (`%s`)'; En: '- %s: at most %d (`%s`)'),
    (De: '### Benennung'; En: '### Naming'),
    (De: '- Präfixe: %s (`naming-prefix`)'; En: '- Prefixes: %s (`naming-prefix`)'),
    (De: 'lokale Variablen `%s`'; En: 'local variables `%s`'),
    (De: 'Felder `%s`'; En: 'fields `%s`'),
    (De: 'Parameter `%s`'; En: 'parameters `%s`'),
    (De: 'Konstanten `%s`'; En: 'constants `%s`'),
    (De: '### Verbotene Symbole'; En: '### Forbidden symbols'),
    (De: ' mit erstem Argument %s'; En: ' with first argument %s'),
    (De: ', stattdessen `%s`'; En: ', use `%s` instead'),
    (De: '### Regeln mit Schweregrad Fehler aus atlas.json'; En: '### Rules with severity error from atlas.json'),
    (De: '### Geschützte Dateien (nicht ändern)'; En: '### Protected files (do not change)'),
    (De: '; stattdessen: %s'; En: '; instead: %s'),
    (De: '### Pflichtprüfungen vor dem Abschluss'; En: '### Required checks before finishing'));

{$SCOPEDENUMS OFF}

function TextOf(AText: TInstructionsText; ALanguage: TTextLanguage): string;
begin
  Result := cTexts[AText].TextIn(ALanguage);
end;

/// <summary>Name der Regel aus dem Katalog, sonst ADefault.</summary>
function RuleName(const ACatalog: TRuleCatalog; const AId, ADefault: string): string;
var
  mEntry: TRuleCatalogEntry;
begin
  Result := ADefault;
  if (ACatalog <> nil) and ACatalog.TryFind(AId, mEntry) and (mEntry.Name <> '') then
  begin
    Result := mEntry.Name;
  end;
end;

/// <summary>Regel AId aus ARules, sofern sie nach ASettings läuft.</summary>
function TryActive(const ARules: TArray<IRule>; const ASettings: TServerSettings; const AId: string;
  out ARule: TRuleDescriptor): Boolean;
var
  mRule: IRule;
  mSeverity: TRuleSeverity;
begin
  for mRule in ARules do
  begin
    ARule := mRule.Descriptor;
    if SameText(ARule.Id, AId) then
    begin
      Exit(TRuleConventions.IsActive(ARule, ASettings, mSeverity));
    end;
  end;
  Result := False;
end;

/// <summary>Überschrift AHeading mit Leerzeile davor und die Zeilen ALines; nichts ohne Zeilen.</summary>
procedure AppendBlock(ABuilder: TStringBuilder; const AHeading: string; const ALines: TArray<string>);
var
  mLine: string;
begin
  if ALines = nil then
  begin
    Exit;
  end;
  ABuilder.Append(#10).Append(AHeading).Append(#10);
  for mLine in ALines do
  begin
    ABuilder.Append(mLine).Append(#10);
  end;
end;

/// <summary>Grenzwerte aller Metrik-Regeln, Methoden- vor Strukturmetriken, Kennung und Wert paarweise.</summary>
procedure AllLimits(const ASettings: TServerSettings; out AIds: TArray<string>; out AValues: TArray<Integer>);
var
  mLimits: TMetricLimits;
  mKind: TMetricKind;
  mStructure: TStructureKind;
begin
  AIds := nil;
  AValues := nil;
  mLimits := TMetricRules.Limits(ASettings);
  for mKind := Low(TMetricKind) to High(TMetricKind) do
  begin
    AIds := AIds + [TMetricRules.RuleId(mKind)];
    AValues := AValues + [mLimits.Values[mKind]];
  end;
  for mStructure := Low(TStructureKind) to High(TStructureKind) do
  begin
    AIds := AIds + [TMetricRules.RuleId(mStructure)];
    AValues := AValues + [mLimits.Structure[mStructure]];
  end;
end;

/// <summary>Je laufender Metrik-Regel eine Zeile mit Name, Grenzwert und Kennung.</summary>
function LimitLines(const ARules: TArray<IRule>; const ASettings: TServerSettings; const ACatalog: TRuleCatalog;
  ALanguage: TTextLanguage): TArray<string>;
var
  mIds: TArray<string>;
  mValues: TArray<Integer>;
  mRule: TRuleDescriptor;
  mIndex: Integer;
begin
  Result := nil;
  AllLimits(ASettings, mIds, mValues);
  for mIndex := 0 to High(mIds) do
  begin
    if TryActive(ARules, ASettings, mIds[mIndex], mRule) then
    begin
      Result := Result + [Format(TextOf(TInstructionsText.Limit, ALanguage),
        [RuleName(ACatalog, mIds[mIndex], mRule.Description), mValues[mIndex], mIds[mIndex]])];
    end;
  end;
end;

function NamingLines(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  ALanguage: TTextLanguage): TArray<string>;
const
  cKindTexts: array[TRuleNamingKind] of TInstructionsText = (TInstructionsText.Local, TInstructionsText.Field,
    TInstructionsText.Parameter, TInstructionsText.Constant);
var
  mRule: TRuleDescriptor;
  mContext: TRuleContext;
  mConvention: TNamingConvention;
  mKind: TRuleNamingKind;
  mParts: TArray<string>;
begin
  Result := nil;
  if not TryActive(ARules, ASettings, cNamingPrefixRuleId, mRule) then
  begin
    Exit;
  end;
  mContext := Default(TRuleContext);
  mContext.Options := TRuleEngine.RuleOptions(cNamingPrefixRuleId, ASettings);
  mConvention := TNamingConvention.Resolve(mContext);
  mParts := nil;
  for mKind := Low(TRuleNamingKind) to High(TRuleNamingKind) do
  begin
    if mConvention.Prefixes[mKind] <> '' then
    begin
      mParts := mParts + [Format(TextOf(cKindTexts[mKind], ALanguage), [mConvention.Prefixes[mKind]])];
    end;
  end;
  if mParts <> nil then
  begin
    Result := [Format(TextOf(TInstructionsText.Prefixes, ALanguage), [string.Join(', ', mParts)])];
  end;
end;

/// <summary>Zeile eines verbotenen Symbols: Name, erstes Argument, Meldung und Ersatz.</summary>
function ForbiddenLine(const ASymbol: TForbiddenSymbol; ALanguage: TTextLanguage): string;
begin
  Result := '- `' + ASymbol.Name + '`';
  if ASymbol.FirstArgument <> nil then
  begin
    Result := Result + Format(TextOf(TInstructionsText.FirstArgument, ALanguage),
      ['`' + string.Join('`, `', ASymbol.FirstArgument) + '`']);
  end;
  if ASymbol.Message <> '' then
  begin
    Result := Result + ': ' + ASymbol.Message;
  end;
  if ASymbol.Replacement <> '' then
  begin
    Result := Result + Format(TextOf(TInstructionsText.Instead, ALanguage), [ASymbol.Replacement]);
  end;
end;

function ForbiddenLines(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  ALanguage: TTextLanguage): TArray<string>;
var
  mRule: TRuleDescriptor;
  mSymbol: TForbiddenSymbol;
begin
  Result := nil;
  if not TryActive(ARules, ASettings, cForbiddenSymbolRuleId, mRule) then
  begin
    Exit;
  end;
  for mSymbol in TForbiddenSymbolRule.ParseSymbols(TRuleEngine.RuleOptions(cForbiddenSymbolRuleId, ASettings)) do
  begin
    Result := Result + [ForbiddenLine(mSymbol, ALanguage)];
  end;
end;

/// <summary>Nennt atlas.json die Regel AId unter "rules"?</summary>
function IsConfigured(const ASettings: TServerSettings; const AId: string): Boolean;
var
  mSetting: TRuleSetting;
begin
  for mSetting in ASettings.Rules do
  begin
    if SameText(mSetting.Id, AId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Laufende Regeln mit Schweregrad Fehler, die atlas.json nennt, nach Kennung sortiert. Regeln, die schon
/// ohne Eintrag Fehler sind, meldet auch der Compiler; sie machten den Abschnitt nur lang.</summary>
function ErrorLines(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ACatalog: TRuleCatalog): TArray<string>;
var
  mRule: IRule;
  mSeverity: TRuleSeverity;
begin
  Result := nil;
  for mRule in ARules do
  begin
    if IsConfigured(ASettings, mRule.Descriptor.Id) and TRuleConventions.IsActive(mRule.Descriptor, ASettings,
      mSeverity) and (mSeverity = TRuleSeverity.Error) then
    begin
      Result := Result + [Format('- `%s`: %s', [mRule.Descriptor.Id,
        RuleName(ACatalog, mRule.Descriptor.Id, mRule.Descriptor.Description)])];
    end;
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareStr(A, B);
    end));
end;

/// <summary>Je geschützter Datei aus assistants.protected (#2608) Muster, Grund und richtiger Weg.</summary>
function ProtectedLines(const ASettings: TServerSettings; ALanguage: TTextLanguage): TArray<string>;
var
  mEntry: TProtectedPath;
  mLine: string;
begin
  Result := nil;
  for mEntry in ASettings.AssistantProtected do
  begin
    mLine := '- `' + mEntry.Path + '`';
    if mEntry.Reason <> '' then
    begin
      mLine := mLine + ': ' + mEntry.Reason;
    end;
    if mEntry.Use <> '' then
    begin
      mLine := mLine + Format(TextOf(TInstructionsText.ProtectedUse, ALanguage), [mEntry.Use]);
    end;
    Result := Result + [mLine];
  end;
end;

function CheckLines(const ASettings: TServerSettings): TArray<string>;
var
  mCheck: string;
begin
  Result := nil;
  for mCheck in ASettings.AssistantsInstructionChecks do
  begin
    Result := Result + ['- `' + mCheck + '`'];
  end;
end;

/// <summary>Umbrüche als #10.</summary>
function Unified(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

/// <summary>Stelle (ab 1) und Länge des Abschnitts in AText; False ohne Schlussmarkierung oder ohne Anfang davor.
/// Die Anfangsmarkierung ist die letzte vor der ersten Schlussmarkierung, damit eine verwaiste Anfangsmarkierung
/// weiter oben keinen fremden Text einschließt.</summary>
function TryFind(const AText: string; out AStart, ALength: Integer): Boolean;
var
  mEnd, mNext: Integer;
begin
  AStart := 0;
  ALength := 0;
  mEnd := Pos(TRuleInstructions.cEndMarker, AText);
  mNext := Pos(TRuleInstructions.cBeginMarker, AText);
  while (mNext > 0) and (mNext < mEnd) do
  begin
    AStart := mNext;
    mNext := Pos(TRuleInstructions.cBeginMarker, AText, mNext + 1);
  end;
  Result := (mEnd > 0) and (AStart > 0);
  if Result then
  begin
    ALength := mEnd + Length(TRuleInstructions.cEndMarker) - AStart;
  end;
end;

{ TRuleInstructions }

class function TRuleInstructions.Section(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ACatalog: TRuleCatalog; ALanguage: TTextLanguage): string;
var
  mBuilder: TStringBuilder;
  mProfile: string;
begin
  mProfile := ASettings.Profile;
  if mProfile = '' then
  begin
    mProfile := 'standard';
  end;
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(TextOf(TInstructionsText.BeginLine, ALanguage)).Append(#10);
    mBuilder.Append(Format(TextOf(TInstructionsText.Heading, ALanguage), [mProfile])).Append(#10#10);
    mBuilder.Append(TextOf(TInstructionsText.CheckCode, ALanguage)).Append(#10);
    AppendBlock(mBuilder, TextOf(TInstructionsText.Limits, ALanguage),
      LimitLines(ARules, ASettings, ACatalog, ALanguage));
    AppendBlock(mBuilder, TextOf(TInstructionsText.Naming, ALanguage), NamingLines(ARules, ASettings, ALanguage));
    AppendBlock(mBuilder, TextOf(TInstructionsText.Forbidden, ALanguage),
      ForbiddenLines(ARules, ASettings, ALanguage));
    AppendBlock(mBuilder, TextOf(TInstructionsText.Errors, ALanguage), ErrorLines(ARules, ASettings, ACatalog));
    AppendBlock(mBuilder, TextOf(TInstructionsText.Protected, ALanguage), ProtectedLines(ASettings, ALanguage));
    AppendBlock(mBuilder, TextOf(TInstructionsText.Checks, ALanguage), CheckLines(ASettings));
    mBuilder.Append(cEndMarker);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TRuleInstructions.LanguageOf(const ASettings: TServerSettings): TTextLanguage;
begin
  Result := TTextLanguage.German;
  if SameText(ASettings.McpPromptLanguage, 'en') then
  begin
    Result := TTextLanguage.English;
  end;
end;

class function TRuleInstructions.Extract(const AText: string): string;
var
  mStart, mLength: Integer;
begin
  Result := '';
  if TryFind(AText, mStart, mLength) then
  begin
    Result := Unified(Copy(AText, mStart, mLength));
  end;
end;

class function TRuleInstructions.Apply(const AText, ASection, ALineBreak: string): string;
var
  mStart, mLength: Integer;
  mSection: string;
begin
  mSection := StringReplace(Unified(ASection), #10, ALineBreak, [rfReplaceAll]);
  if TryFind(AText, mStart, mLength) then
  begin
    Result := Copy(AText, 1, mStart - 1) + mSection + Copy(AText, mStart + mLength, MaxInt);
    Exit;
  end;
  Result := AText;
  if (Result <> '') and not CharInSet(Result[Length(Result)], [#10, #13]) then
  begin
    Result := Result + ALineBreak;
  end;
  if Result <> '' then
  begin
    Result := Result + ALineBreak;
  end;
  Result := Result + mSection + ALineBreak;
end;

class function TRuleInstructions.State(const AText, ASection: string): TInstructionsState;
var
  mFound: string;
begin
  mFound := Extract(AText);
  if mFound = '' then
  begin
    Result := TInstructionsState.Missing;
  end
  else if mFound = Unified(ASection) then
  begin
    Result := TInstructionsState.Current;
  end
  else
  begin
    Result := TInstructionsState.Stale;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Instructions', cTexts);

end.
