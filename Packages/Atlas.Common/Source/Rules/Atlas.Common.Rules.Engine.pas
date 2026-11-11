unit Atlas.Common.Rules.Engine;

// Führt Prüfregeln auf einer Datei aus. Beachtet aus atlas.json den
// Schweregrad je Regel ("off" schaltet ab), den globalen Ausschluss und die
// Ausnahmen je Regel in den Optionen:
//   "rules": { "empty-except": { "severity": "hint", "exclude": ["Legacy/**", "Alt.Unit"] } }
// Muster in "exclude" gelten für den relativen Pfad (Glob) oder den Unit-Namen.
// Danach filtert sie Treffer, die per Kommentar unterdrückt sind.
//
// Konfidenzpolitik (#144): Fehler nur bei hoher Konfidenz, mittlere höchstens
// Warnung, niedrige höchstens Hinweis. Treffer unter "minConfidence" (Vorgabe
// medium) entfallen. Experimentelle Regeln laufen nur, wenn sie in "rules"
// stehen.
//
// Unterdrückungskommentare, die nichts unterdrücken, meldet die Engine als
// Hinweis "unused-suppression" mit Korrektur zum Entfernen (#147); nur wenn
// alle genannten Regeln gelaufen sind, damit Kommentare für abgeschaltete
// oder unbekannte Regeln nicht stören, und nur, wenn jede genannte Regel mit
// IRuleLineCertainty die Zeile entscheiden konnte (sonst fehlt ihr Wissen,
// etwa der Index der RTL).
//
// Eine Kennung im Unterdrückungskommentar, die weder im Regelkatalog noch
// unter den übergebenen Regeln steht, meldet die Engine als Hinweis
// "unknown-rule-id" mit Tippfehler-Vorschlag und Korrektur (#41). Ein solcher
// Kommentar zählt nicht zusätzlich als "unused-suppression".
//
// Hauptschalter je Gruppe (#909): "rules": { "group:threads": "off" } schaltet
// alle Regeln der Gruppe ab, auch einzeln eingestellte; die Gruppe steht im
// Regelkatalog. Für die Gruppe „Compiler vorab“ (#1024) auch als Objekt:
// "group:compiler": {"severity": "off", "typeLevel": "off"}; typeLevel "off"
// schaltet die Regeln der Stufe T (Katalogfeld "level") ab, "certain" (Vorgabe)
// lässt sie laufen, sie melden dann nur bei sicher bekanntem Typ.
//
// Gegenregeln (#1025): Nennt der Katalog unter "overriddenBy" eine Regel, die
// für die Datei an ist, läuft die übersteuerte Regel nicht (redundant-begin-end
// schweigt, solange missing-begin-end an ist). Ob die Gegenregel selbst unter
// den übergebenen Regeln ist, spielt keine Rolle: Es zählt die Einstellung.
//
// Regelprofile, Pfadregeln und das Ausnehmen von Test-Units (#146) wertet
// TRuleProfiles aus; maßgeblich ist das Profil in ASettings.Profile, für
// Test-Units und Testprojekte ASettings.TestProfile, falls gesetzt.
//
// Laufzeit: Vor jeder Regel fragt die Engine AContext.Cancelled und bricht
// mit ERuleCheckCancelled ab, damit eine abgebrochene oder überholte Prüfung
// nicht bis zum Ende weiterläuft. Die
// langsamste Regel ab SlowRuleMs geht als slowRule/slowRuleMs ins Diagnoselog.
// Dieselbe Messung geht an den Profiler des Threads (TCheckProfiler, #1356),
// wenn die Projektprüfung oder --check einen angehängt hat: Summe je Regel
// über den Prüflauf für das Fenster „Atlas-Server“ und --timings.
//
// Robustheit (#1094): Die Regeln und ihre Dienste gehen iterativ
// durch den Baum (TSyntaxNode.Walk/Search oder eigener Stapel), auch lange
// Ketten wie 1 - 1 - … - 1 sprengen den Stapel nicht. MaxTreeDepth bleibt als
// Netz für unbekannte rekursive Wege: Ist der Baum tiefer, laufen die Regeln
// für diese Datei nicht; die Datei bekommt den Hinweis unit-too-deep an der
// tiefsten Stelle und steht als deepUnit im Diagnoselog, statt still alle
// Befunde zu verlieren.
// Wirft eine Regel eine Ausnahme, laufen die übrigen weiter; die
// Regel steht mit Unit und Ausnahmeklasse als failRule im Diagnoselog. Nur der
// Abbruch (ERuleCheckCancelled) beendet den Lauf.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract;

const
  cUnusedSuppressionRuleId = 'unused-suppression';
  cUnknownRuleIdRuleId = 'unknown-rule-id';
  /// <summary>Hinweis, dass die Regeln eine Unit wegen MaxTreeDepth übersprungen haben.</summary>
  cUnitTooDeepRuleId = 'unit-too-deep';

type
  TRuleEngine = class
  public const
    /// <summary>Ab dieser Dauer nennt das Diagnoselog die Regel.</summary>
    cSlowRuleMs = 100;
    /// <summary>Netz (#1094): Tiefere Syntaxbäume prüfen die Regeln nicht, die Unit bekommt den
    /// Hinweis unit-too-deep. Alle Regeln laufen iterativ; TBuiltinRulesTests prüft sie mit Ketten von 5000
    /// Gliedern in 128 KB Stapel. Die Grenze fängt nur unbekannte rekursive Wege ab; so tiefe Bäume entstehen erst aus
    /// Ketten mit 100000 Gliedern.</summary>
    cMaxTreeDepth = 100000;
  public
    /// <summary>Wirksamer Schweregrad einer Regel; Off = nicht ausführen.</summary>
    class function EffectiveSeverity(const ARule: TRuleDescriptor;
      const ASettings: TServerSettings; const ARelativePath: string): TRuleSeverity; overload; static;
    class function EffectiveSeverity(const ARule: TRuleDescriptor; const ASettings: TServerSettings;
      const ARelativePath: string; out AEnabled: Boolean): TRuleSeverity; overload; static;
    /// <summary>Ist die Gruppe der Regel über "group:&lt;gruppe&gt;": "off" abgeschaltet (#909)?</summary>
    class function GroupOff(const ARuleId: string; const ASettings: TServerSettings): Boolean; static;
    /// <summary>Regel der Stufe T der Gruppe „Compiler vorab“ bei "typeLevel": "off" (#1024)?</summary>
    class function TypeLevelOff(const ARuleId: string; const ASettings: TServerSettings): Boolean; static;
    /// <summary>Optionen der Regel als JSON-Text, sonst ''.</summary>
    class function RuleOptions(const ARuleId: string; const ASettings: TServerSettings): string; static;
    /// <summary>Präfixe für Namen, die Korrekturen und Refactorings neu bilden: die der ersten Regel mit
    /// IRuleNewNames (naming-prefix), die für die Datei läuft; sonst keine. AContext liefert Pfad, Unit und die
    /// Vorgaben der Projektdatei.</summary>
    class function NewNames(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const AContext: TRuleContext): TPascalNamePrefixes; static;
    /// <summary>ASeverity begrenzt nach Konfidenz.</summary>
    class function CapSeverity(ASeverity: TRuleSeverity; AConfidence: TRuleConfidence): TRuleSeverity; static;
    /// <summary>True, wenn "exclude" in AOptions den Pfad oder die Unit trifft.</summary>
    class function IsExceptedByOptions(const AOptions, ARelativePath, AUnitName: string): Boolean; static;
    /// <summary>Kennung der eingeschalteten Gegenregel, die ARuleId für diese Datei übersteuert (#1025); '' ohne.
    /// Die Beschreibung der Gegenregel kommt aus ARules, sonst aus dem Katalog.</summary>
    class function OverridingRule(const ARuleId: string; const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath, AUnitName: string): string; static;
    /// <summary>Ist die Regel ARuleId (aus dem Katalog) für die Datei eingeschaltet: nicht ausgeschlossen
    /// ("exclude" allgemein und der Regel), Schweregrad nicht off? Für Darstellungen einer Regel außerhalb des
    /// Prüflaufs, z. B. die abgeblendeten uses im Editor (unused-uses, #1135).</summary>
    class function RuleOn(const ARuleId: string; const ASettings: TServerSettings;
      const ARelativePath, AUnitName: string): Boolean; static;
    /// <summary>Alle Treffer der Regeln auf AContext, nach Zeile sortiert.</summary>
    class function Run(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const AContext: TRuleContext): TArray<TRuleFinding>; static;
  end;

implementation

uses
  System.JSON,
  System.StrUtils,
  System.Diagnostics,
  System.Generics.Defaults,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Rules.Builtin.SavedQueries,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Profiles,
  Atlas.Common.Rules.Suppressions,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Semantics.TreeUnits;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Engine in beiden Sprachen (#1458).</summary>
  TEngineText = (UnitTooDeep, Cancelled, UnusedSuppression, RemoveSuppression, UnknownRuleId, UnknownRuleIdGuess,
    ReplaceWith);

const
  cTexts: array[TEngineText] of TAtlasText = (
    (De: 'Die Prüfregeln laufen für diese Unit nicht: Der Syntaxbaum ist %d Ebenen tief (Grenze %d). Die ' +
      'tiefste Stelle liegt hier; eine lange Kette aus - oder * in Teilausdrücke aufteilen';
     En: 'The rules do not run for this unit: the syntax tree is %d levels deep (limit %d). The deepest point ' +
      'is here; split a long chain of - or * into partial expressions'),
    (De: 'Prüfung abgebrochen'; En: 'Check cancelled'),
    (De: 'Unterdrückung ohne Wirkung: hier meldet keine der genannten Regeln etwas';
     En: 'Suppression without effect: none of the named rules reports anything here'),
    (De: 'Unterdrückung entfernen'; En: 'Remove suppression'),
    (De: 'Unbekannte Regelkennung "%s"; die Unterdrückung wirkt nicht';
     En: 'Unknown rule id "%s"; the suppression has no effect'),
    (De: 'Unbekannte Regelkennung "%s"; gemeint ist vermutlich "%s"';
     En: 'Unknown rule id "%s"; probably "%s" is meant'),
    (De: 'Durch "%s" ersetzen'; En: 'Replace with "%s"'));

{$SCOPEDENUMS OFF}

type
  TRuleReport = class(TInterfacedObject, IRuleReport, IRuleRelatedReport)
  private
    FRuleId: string;
    FSeverity: TRuleSeverity;
    FFindings: TList<TRuleFinding>;
  public
    constructor Create(const ARuleId: string; ASeverity: TRuleSeverity; AFindings: TList<TRuleFinding>);
    procedure Add(const ARange: TTextRange; const AMessage: string); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>); overload;
    procedure AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>);
    procedure AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>);
    procedure AddRelated(const ARange: TTextRange; const AMessage, ADetails: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>; const ARelated: TArray<TRuleRelated>);
  end;

  /// <summary>Gelaufene Regel mit IRuleLineCertainty und dem Kontext ihres Laufs.</summary>
  TUncertainRule = record
    Certainty: IRuleLineCertainty;
    Id: string;
    Context: TRuleContext;
  end;

  /// <summary>Regel mit IRuleAfterFindings, die nach allen Regeln mit den rohen Treffern läuft (#297).</summary>
  TDeferredRule = record
    Rule: IRuleAfterFindings;
    Id: string;
    Severity: TRuleSeverity;
    Context: TRuleContext;
  end;

  /// <summary>Ein Lauf von TRuleEngine.Run über eine Datei: Regeln, nachgelagerte Regeln, Unterdrückungen.
  /// Hält den gemeinsamen Kontext samt eigenem Ableitungscache und eigener Baumauswertung und gibt sie im
  /// Destruktor frei, bevor der Aufrufer den Baum freigibt.</summary>
  TRuleRun = class
  private
    FRules: TArray<IRule>;
    FSettings: TServerSettings;
    FContext: TRuleContext;
    FShared: TRuleContext;
    FOwnCache: IRuleDerivedCache;
    FOwnUnits: ITreeUnits;
    FFindings: TList<TRuleFinding>;
    FKept: TList<TRuleFinding>;
    FRanIds: TList<string>;
    FDeferred: TList<TDeferredRule>;
    FUncertain: TList<TUncertainRule>;
    FSuppressions: TSuppressions;
    function RuleContext(const ARuleId: string): TRuleContext;
    function Runs(const ADescriptor: TRuleDescriptor; out ASeverity: TRuleSeverity): Boolean;
    function MustRaise(AError: Exception): Boolean;
    procedure Discard(AError: Exception; const ARuleId: string; ABefore: Integer);
    procedure CheckCancelled;
    function Checked(const ARule: IRule; const ARuleId: string; ASeverity: TRuleSeverity;
      const AContext: TRuleContext): Boolean;
    procedure RuleTimed(const ARuleId: string; const AWatch: TStopwatch);
    procedure Defer(const ARule: IRule; const ARuleId: string; ASeverity: TRuleSeverity; const AContext: TRuleContext);
    procedure RunRule(const ARule: IRule);
    procedure RunDeferred(const ADeferred: TDeferredRule);
    procedure KeepUnsuppressed;
    function AllRan(const AEntry: TSuppressionEntry): Boolean;
    function AllDecided(const AEntry: TSuppressionEntry): Boolean;
    procedure NoteUncertain(const ARule: IRule; const ARuleId: string; const AContext: TRuleContext);
    procedure KeepUnusedSuppressions;
    function KnownRuleIds: TArray<string>;
    procedure KeepUnknownRuleIds;
  public
    /// <summary>ASettings sind die Einstellungen der Datei, für Test-Units schon mit dem Testprofil.</summary>
    constructor Create(const ARules: TArray<IRule>; const ASettings: TServerSettings; const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Alle Treffer der Regeln, nach Zeile sortiert.</summary>
    function Execute: TArray<TRuleFinding>;
    /// <summary>False, wenn die Datei ausgeschlossen ist (global oder als Test-Unit); AEffective sind die
    /// Einstellungen für die Datei (Testprofil für Test-Units).</summary>
    class function Applies(const ASettings: TServerSettings; const AContext: TRuleContext;
      out AEffective: TServerSettings): Boolean; static;
  end;

/// <summary>Hinweis unit-too-deep an der tiefsten Stelle einer Unit, deren Baum tiefer als MaxTreeDepth ist
///; leer, wenn der Hinweis abgeschaltet ist.</summary>
function TooDeepFindings(ATree: TSyntaxTree; const ASettings: TServerSettings): TArray<TRuleFinding>;
var
  mFinding: TRuleFinding;
  mNode: TSyntaxNode;
begin
  Result := nil;
  if ASettings.RuleSeverity(cUnitTooDeepRuleId, TRuleSeverity.Hint) = TRuleSeverity.Off then
  begin
    Exit;
  end;
  mNode := ATree.Deepest;
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := cUnitTooDeepRuleId;
  mFinding.Range := TTextRange.Create(mNode.StartPos, mNode.EndPos);
  mFinding.Message := cTexts[TEngineText.UnitTooDeep].Fmt([ATree.Depth, TRuleEngine.cMaxTreeDepth]);
  mFinding.Severity := ASettings.RuleSeverity(cUnitTooDeepRuleId, TRuleSeverity.Hint);
  mFinding.Confidence := TRuleConfidence.High;
  Result := [mFinding];
end;

function CompareFindings(const A, B: TRuleFinding): Integer;
begin
  Result := A.Range.StartPos.Line - B.Range.StartPos.Line;
  if Result = 0 then
  begin
    Result := A.Range.StartPos.Character - B.Range.StartPos.Character;
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.RuleId, B.RuleId);
  end;
end;

/// <summary>AFindings nach CompareFindings, bei Gleichstand in Meldereihenfolge (Delphis Sort ist nicht stabil:
/// {$R-,Q-} meldet zwei Treffer derselben Regel an derselben Stelle).</summary>
function SortedFindings(const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  mItems: TArray<TRuleFinding>;
  mOrder: TArray<Integer>;
  mIndex: Integer;
begin
  mItems := AFindings;
  SetLength(mOrder, Length(mItems));
  for mIndex := 0 to High(mOrder) do
  begin
    mOrder[mIndex] := mIndex;
  end;
  TArray.Sort<Integer>(mOrder, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := CompareFindings(mItems[A], mItems[B]);
      if Result = 0 then
      begin
        Result := A - B;
      end;
    end));
  SetLength(Result, Length(mItems));
  for mIndex := 0 to High(mOrder) do
  begin
    Result[mIndex] := mItems[mOrder[mIndex]];
  end;
end;

{ TRuleReport }

constructor TRuleReport.Create(const ARuleId: string; ASeverity: TRuleSeverity; AFindings: TList<TRuleFinding>);
begin
  inherited Create;
  FRuleId := ARuleId;
  FSeverity := ASeverity;
  FFindings := AFindings;
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string);
begin
  Add(ARange, AMessage, nil);
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>);
begin
  Add(ARange, AMessage, TRuleConfidence.High, AFixes);
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence);
begin
  Add(ARange, AMessage, AConfidence, nil);
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
  const AFixes: TArray<TRuleFix>);
var
  mFinding: TRuleFinding;
begin
  mFinding.RuleId := FRuleId;
  mFinding.Range := ARange;
  mFinding.Message := AMessage;
  mFinding.Severity := TRuleEngine.CapSeverity(FSeverity, AConfidence);
  mFinding.Confidence := AConfidence;
  mFinding.Fixes := AFixes;
  mFinding.Details := '';
  FFindings.Add(mFinding);
end;

procedure TRuleReport.AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string;
  AConfidence: TRuleConfidence; const AFixes: TArray<TRuleFix>);
var
  mFinding: TRuleFinding;
begin
  mFinding.RuleId := FRuleId;
  mFinding.Range := ARange;
  mFinding.Message := AMessage;
  mFinding.Severity := TRuleEngine.CapSeverity(FSeverity, AConfidence);
  mFinding.Confidence := AConfidence;
  mFinding.Fixes := AFixes;
  mFinding.Details := ADetails;
  FFindings.Add(mFinding);
end;

procedure TRuleReport.AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
  const AFixes: TArray<TRuleFix>);
var
  mFinding: TRuleFinding;
begin
  if ASeverity = TRuleSeverity.Off then
  begin
    Exit;
  end;
  mFinding.RuleId := FRuleId;
  mFinding.Range := ARange;
  mFinding.Message := AMessage;
  if ASeverity = TRuleSeverity.Default then
  begin
    mFinding.Severity := FSeverity;
  end
  else
  begin
    mFinding.Severity := ASeverity;
  end;
  mFinding.Confidence := TRuleConfidence.High;
  mFinding.Fixes := AFixes;
  mFinding.Details := '';
  FFindings.Add(mFinding);
end;

procedure TRuleReport.AddRelated(const ARange: TTextRange; const AMessage, ADetails: string; ASeverity: TRuleSeverity;
  const AFixes: TArray<TRuleFix>; const ARelated: TArray<TRuleRelated>);
var
  mFinding: TRuleFinding;
begin
  if ASeverity = TRuleSeverity.Off then
  begin
    Exit;
  end;
  mFinding.RuleId := FRuleId;
  mFinding.Range := ARange;
  mFinding.Message := AMessage;
  if ASeverity = TRuleSeverity.Default then
  begin
    mFinding.Severity := FSeverity;
  end
  else
  begin
    mFinding.Severity := ASeverity;
  end;
  mFinding.Confidence := TRuleConfidence.High;
  mFinding.Fixes := AFixes;
  mFinding.Details := ADetails;
  mFinding.Related := ARelated;
  FFindings.Add(mFinding);
end;

{ TRuleEngine }

class function TRuleEngine.EffectiveSeverity(const ARule: TRuleDescriptor;
  const ASettings: TServerSettings; const ARelativePath: string): TRuleSeverity;
var
  mEnabled: Boolean;
begin
  Result := EffectiveSeverity(ARule, ASettings, ARelativePath, mEnabled);
end;

class function TRuleEngine.EffectiveSeverity(const ARule: TRuleDescriptor; const ASettings: TServerSettings;
  const ARelativePath: string; out AEnabled: Boolean): TRuleSeverity;
begin
  if GroupOff(ARule.Id, ASettings) or TypeLevelOff(ARule.Id, ASettings) then
  begin
    AEnabled := False;
    Exit(TRuleSeverity.Off);
  end;
  // Kennzahlen global aus ("metrics": false): metric-* schweigen, außer das Projekt setzt die Regel selbst.
  if not ASettings.Metrics and SameText(Copy(ARule.Id, 1, 7), 'metric-') and
    (ASettings.RuleSeverity(ARule.Id, TRuleSeverity.Default) = TRuleSeverity.Default) then
  begin
    AEnabled := False;
    Exit(TRuleSeverity.Off);
  end;
  Result := TRuleProfiles.Severity(ASettings, ASettings.Profile, ARule, TRuleProfiles.CategoryOf(ARule.Id),
    ARelativePath, AEnabled);
  if Result = TRuleSeverity.Default then
  begin
    Result := TRuleSeverity.Warning;
  end;
end;

class function TRuleEngine.GroupOff(const ARuleId: string; const ASettings: TServerSettings): Boolean;
var
  mEntry: TRuleCatalogEntry;
begin
  Result := (Length(ASettings.Rules) > 0) and TRuleCatalog.Shared.TryFind(ARuleId, mEntry) and
    (ASettings.RuleSeverity(TRuleCatalog.GroupKey(mEntry.Group), TRuleSeverity.Default) = TRuleSeverity.Off);
end;

class function TRuleEngine.TypeLevelOff(const ARuleId: string; const ASettings: TServerSettings): Boolean;
var
  mEntry: TRuleCatalogEntry;
  mOptions: string;
  mValue, mLevel: TJSONValue;
begin
  Result := False;
  if (Length(ASettings.Rules) = 0) or not TRuleCatalog.Shared.TryFind(ARuleId, mEntry) or
    (mEntry.Group <> TRuleGroup.Compiler) or (mEntry.Level <> 'T') then
  begin
    Exit;
  end;
  mOptions := RuleOptions(TRuleCatalog.GroupKey(mEntry.Group), ASettings);
  if mOptions = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mOptions);
  try
    if mValue is TJSONObject then
    begin
      mLevel := TJSONObject(mValue).GetValue('typeLevel');
      Result := (mLevel is TJSONString) and SameText(TJSONString(mLevel).Value, 'off');
    end;
  finally
    mValue.Free;
  end;
end;

class function TRuleEngine.CapSeverity(ASeverity: TRuleSeverity; AConfidence: TRuleConfidence): TRuleSeverity;
var
  mLimit: TRuleSeverity;
begin
  case AConfidence of
    TRuleConfidence.Low:
      mLimit := TRuleSeverity.Hint;
    TRuleConfidence.Medium:
      mLimit := TRuleSeverity.Warning;
  else
    mLimit := TRuleSeverity.Error;
  end;
  if Ord(ASeverity) > Ord(mLimit) then
  begin
    Result := mLimit;
  end
  else
  begin
    Result := ASeverity;
  end;
end;

class function TRuleEngine.RuleOptions(const ARuleId: string; const ASettings: TServerSettings): string;
var
  mRule: TRuleSetting;
begin
  for mRule in ASettings.Rules do
  begin
    if SameText(mRule.Id, ARuleId) then
    begin
      Exit(mRule.Options);
    end;
  end;
  Result := '';
end;

class function TRuleEngine.IsExceptedByOptions(const AOptions, ARelativePath, AUnitName: string): Boolean;
var
  mValue: TJSONValue;
  mExclude: TJSONValue;
  mItem: TJSONValue;
  mPattern: string;
begin
  Result := False;
  if AOptions = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mExclude := TJSONObject(mValue).GetValue('exclude');
    if not (mExclude is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mExclude) do
    begin
      if not (mItem is TJSONString) then
      begin
        Continue;
      end;
      mPattern := mItem.Value;
      if ((AUnitName <> '') and SameText(mPattern, AUnitName)) or
        ((ARelativePath <> '') and MatchesGlob(mPattern, ARelativePath)) then
      begin
        Exit(True);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>True und wirksamer Schweregrad, wenn ADescriptor für den Pfad läuft: nicht aus und, falls
/// experimentell, in "rules" eingeschaltet.</summary>
function SeverityIfOn(const ADescriptor: TRuleDescriptor; const ASettings: TServerSettings;
  const ARelativePath: string; out ASeverity: TRuleSeverity): Boolean;
var
  mEnabled: Boolean;
begin
  ASeverity := TRuleEngine.EffectiveSeverity(ADescriptor, ASettings, ARelativePath, mEnabled);
  Result := (ASeverity <> TRuleSeverity.Off) and (mEnabled or not ADescriptor.Experimental);
end;

/// <summary>Beschreibung der Regel AId aus ARules, sonst aus dem Katalog; False, wenn sie keiner kennt.</summary>
function TryDescriptor(const AId: string; const ARules: TArray<IRule>; out ADescriptor: TRuleDescriptor): Boolean;
var
  mRule: IRule;
  mEntry: TRuleCatalogEntry;
begin
  for mRule in ARules do
  begin
    if SameText(mRule.Descriptor.Id, AId) then
    begin
      ADescriptor := mRule.Descriptor;
      Exit(True);
    end;
  end;
  Result := TRuleCatalog.Shared.TryFind(AId, mEntry);
  if Result then
  begin
    ADescriptor := TRuleDescriptor.Create(mEntry.Id, mEntry.DefaultSeverity, mEntry.Name);
  end;
end;

class function TRuleEngine.OverridingRule(const ARuleId: string; const ARules: TArray<IRule>;
  const ASettings: TServerSettings; const ARelativePath, AUnitName: string): string;
var
  mEntry: TRuleCatalogEntry;
  mId: string;
  mDescriptor: TRuleDescriptor;
  mSeverity: TRuleSeverity;
begin
  Result := '';
  if not TRuleCatalog.Shared.TryFind(ARuleId, mEntry) then
  begin
    Exit;
  end;
  for mId in mEntry.OverriddenBy do
  begin
    if TryDescriptor(mId, ARules, mDescriptor) and
      SeverityIfOn(mDescriptor, ASettings, ARelativePath, mSeverity) and
      not IsExceptedByOptions(RuleOptions(mDescriptor.Id, ASettings), ARelativePath, AUnitName) then
    begin
      Exit(mDescriptor.Id);
    end;
  end;
end;

class function TRuleEngine.RuleOn(const ARuleId: string; const ASettings: TServerSettings;
  const ARelativePath, AUnitName: string): Boolean;
var
  mDescriptor: TRuleDescriptor;
  mSeverity: TRuleSeverity;
begin
  Result := ((ARelativePath = '') or not ASettings.IsExcluded(ARelativePath)) and
    TryDescriptor(ARuleId, nil, mDescriptor) and SeverityIfOn(mDescriptor, ASettings, ARelativePath, mSeverity) and
    not IsExceptedByOptions(RuleOptions(mDescriptor.Id, ASettings), ARelativePath, AUnitName);
end;

class function TRuleEngine.NewNames(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const AContext: TRuleContext): TPascalNamePrefixes;
var
  mRule: IRule;
  mSource: IRuleNewNames;
  mSeverity: TRuleSeverity;
  mContext: TRuleContext;
begin
  Result := TPascalNamePrefixes.None;
  for mRule in ARules do
  begin
    // Dieselben Bedingungen wie für den Lauf der Regel: Schweregrad, experimentell, Ausnahmen der Optionen.
    if not Supports(mRule, IRuleNewNames, mSource) or
      not SeverityIfOn(mRule.Descriptor, ASettings, AContext.RelativePath, mSeverity) then
    begin
      Continue;
    end;
    mContext := AContext;
    mContext.Options := RuleOptions(mRule.Descriptor.Id, ASettings);
    if not IsExceptedByOptions(mContext.Options, mContext.RelativePath, mContext.UnitName) then
    begin
      Exit(mSource.NewNames(mContext));
    end;
  end;
end;

class function TRuleEngine.Run(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const AContext: TRuleContext): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mRun: TRuleRun;
begin
  Result := nil;
  if not TRuleRun.Applies(ASettings, AContext, mSettings) then
  begin
    Exit;
  end;
  if (AContext.Tree <> nil) and (AContext.Tree.Depth > cMaxTreeDepth) then
  begin
    TRequestDiagnostics.TreeTooDeep(AContext.Tree.Depth);
    Exit(TooDeepFindings(AContext.Tree, ASettings));
  end;
  mRun := TRuleRun.Create(ARules, mSettings, AContext);
  try
    Result := mRun.Execute;
  finally
    mRun.Free;
  end;
end;

{ TRuleRun }

class function TRuleRun.Applies(const ASettings: TServerSettings; const AContext: TRuleContext;
  out AEffective: TServerSettings): Boolean;
begin
  AEffective := ASettings;
  Result := (AContext.RelativePath = '') or not ASettings.IsExcluded(AContext.RelativePath);
  if Result and (ASettings.ExcludeTests or (ASettings.TestProfile <> '')) and (AContext.Tree <> nil) and
    TRuleProfiles.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Result := not ASettings.ExcludeTests;
    AEffective.Profile := ASettings.TestProfile;
  end;
end;

constructor TRuleRun.Create(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const AContext: TRuleContext);
begin
  inherited Create;
  FSettings := ASettings;
  FContext := AContext;
  // Gespeicherte Abfragen mit failIfAny (#1351) laufen als Regeln query:<name>, wo der Arbeitsbereich Abfragen
  // anbietet: Editor, --check und SARIF zeigen sie, Unterdrückungen und Baseline wirken wie bei jeder Regel.
  FRules := ARules;
  if AContext.Queries <> nil then
  begin
    FRules := FRules + TSavedQueryRule.RulesOf(ASettings);
  end;
  FFindings := TList<TRuleFinding>.Create;
  FKept := TList<TRuleFinding>.Create;
  FRanIds := TList<string>.Create;
  FDeferred := TList<TDeferredRule>.Create;
  FUncertain := TList<TUncertainRule>.Create;
  // Ein Ableitungscache für alle Regeln des Laufs; ein vom Aufrufer
  // gesetzter Cache gehört dem Aufrufer und bleibt gefüllt.
  FShared := AContext;
  // Neue Namen der Korrekturen nach der Namensregel (#1111), einmal für alle Regeln.
  FShared.NewNames := TRuleEngine.NewNames(FRules, ASettings, FShared);
  if FShared.Derived = nil then
  begin
    FOwnCache := TRuleDerivedCache.Create;
    FShared.Derived := FOwnCache;
  end;
  // Eine Auswertung des Baums für alle Namensauflöser des Laufs (#1322): Sonst extrahierte jede Typabfrage
  // eines nicht gepinnten Resolvers die ganze Unit neu, und Regeln mit vielen Abfragen wurden quadratisch.
  if (FShared.TreeUnits = nil) and (FShared.Tree <> nil) then
  begin
    FOwnUnits := TTreeUnits.Create(FShared.Tree);
    FShared.TreeUnits := FOwnUnits;
  end;
end;

destructor TRuleRun.Destroy;
begin
  // Gibt Graphen und Modelle frei, bevor der Aufrufer den Baum freigibt, und bricht
  // Referenzzyklen über Kontextkopien in abgelegten Objekten.
  if FOwnCache <> nil then
  begin
    FOwnCache.Clear;
  end;
  // Kontextkopien in abgelegten Objekten können die Auswertung überleben: ohne Baum bedient sie keinen mehr.
  if FOwnUnits <> nil then
  begin
    FOwnUnits.Clear;
  end;
  FUncertain.Free;
  FDeferred.Free;
  FRanIds.Free;
  FSuppressions.Free;
  FKept.Free;
  FFindings.Free;
  inherited;
end;

function TRuleRun.Execute: TArray<TRuleFinding>;
var
  mRule: IRule;
  mDeferred: TDeferredRule;
begin
  for mRule in FRules do
  begin
    RunRule(mRule);
  end;
  // Nach allen Regeln, mit den rohen Treffern (#297).
  for mDeferred in FDeferred do
  begin
    RunDeferred(mDeferred);
  end;
  if FContext.Tree <> nil then
  begin
    FSuppressions := TSuppressions.Create(FContext.Tree.Tokens);
  end;
  KeepUnsuppressed;
  if FSuppressions <> nil then
  begin
    KeepUnusedSuppressions;
    KeepUnknownRuleIds;
  end;
  Result := SortedFindings(FKept.ToArray);
end;

function TRuleRun.Runs(const ADescriptor: TRuleDescriptor; out ASeverity: TRuleSeverity): Boolean;
begin
  Result := SeverityIfOn(ADescriptor, FSettings, FContext.RelativePath, ASeverity) and
    (TRuleEngine.OverridingRule(ADescriptor.Id, FRules, FSettings, FContext.RelativePath, FContext.UnitName) = '');
end;

function TRuleRun.RuleContext(const ARuleId: string): TRuleContext;
begin
  Result := FShared;
  // Sprachstand (#1126): Korrekturen erzeugen keine Merkmale, die minDelphiVersion nicht kennt.
  if Result.DelphiVersion = '' then
  begin
    Result.DelphiVersion := TLanguageFeatures.LanguageLevel(FSettings.DelphiVersion, FSettings.MinDelphiVersion);
  end;
  Result.Options := TRuleEngine.RuleOptions(ARuleId, FSettings);
  Result.DfmPropertyRules := FSettings.DfmPropertyRules;
  Result.NoSignatureSync := not FSettings.Refactoring.SyncSignatures;
  Result.NoForwardDeclaration := not FSettings.Refactoring.ForwardDeclaration;
  Result.NoFreeFields := not FSettings.Refactoring.FreeFields;
  Result.FreeFieldsFreeAndNil := SameText(FSettings.Refactoring.FreeFieldsStyle, 'freeAndNil');
  Result.NoMethodKind := not FSettings.Refactoring.MethodKind;
  Result.MethodKindStatic := FSettings.Refactoring.MethodKindStatic;
  Result.InlineAccessorDiagnostic := FSettings.Refactoring.InlineAccessor and
    FSettings.Refactoring.InlineAccessorDiagnostic;
  Result.NoAccessorEqualityCheck := not FSettings.Refactoring.InlineAccessorEqualityCheck;
  Result.AccessorsProtected := FSettings.Completion.AccessorSection = TCompletionAccessorSection.Protected;
  Result.Formatting := FSettings.Formatting;
  Result.ClassCompletion := FSettings.ClassCompletion;
  Result.KeepAttributes := FSettings.DeadCodeKeepAttributes;
  Result.KeepPatterns := FSettings.DeadCodeKeepPatterns;
  Result.NoUsesCycleLive := not FSettings.DiagnosticsUsesCycleLive;
  Result.UsesCycleImplementation := FSettings.DiagnosticsUsesCycleImplementation;
  Result.SortUses := FSettings.SortUses;
  Result.SortUsesByNamespace := FSettings.SortUsesByNamespace;
  Result.UsesKeep := FSettings.UsesKeep;
end;

procedure TRuleRun.CheckCancelled;
begin
  if Assigned(FContext.Cancelled) and FContext.Cancelled() then
  begin
    raise ERuleCheckCancelled.Create(cTexts[TEngineText.Cancelled].Text);
  end;
end;

function TRuleRun.MustRaise(AError: Exception): Boolean;
begin
  // Abgebrochen wird weiter wie bisher; sonst kostet eine scheiternde Regel nur ihre eigenen Treffer (#1094).
  Result := (AError is ERuleCheckCancelled) or (Assigned(FContext.Cancelled) and FContext.Cancelled());
end;

procedure TRuleRun.Discard(AError: Exception; const ARuleId: string; ABefore: Integer);
begin
  FFindings.Count := ABefore;
  TStackGuard.AfterError(AError);
  TRequestDiagnostics.RuleFailed(ARuleId, AError.ClassName);
end;

function TRuleRun.Checked(const ARule: IRule; const ARuleId: string; ASeverity: TRuleSeverity;
  const AContext: TRuleContext): Boolean;
var
  mReport: IRuleReport;
  mBefore: Integer;
begin
  // Erst in einer Interface-Variablen halten: Check nimmt den Report als
  // const; ohne gezählte Referenz würde er nie freigegeben (Speicherleck).
  mReport := TRuleReport.Create(ARuleId, ASeverity, FFindings);
  TRequestDiagnostics.CurrentRule(ARuleId);
  mBefore := FFindings.Count;
  Result := True;
  try
    ARule.Check(AContext, mReport);
  except
    on E: Exception do
    begin
      if MustRaise(E) then
      begin
        raise;
      end;
      Discard(E, ARuleId, mBefore);
      Result := False;
    end;
  end;
  TRequestDiagnostics.CurrentRule('');
end;

procedure TRuleRun.RuleTimed(const ARuleId: string; const AWatch: TStopwatch);
begin
  // Zeitprofil des Prüflaufs (#1356): dieselbe Messung, an den Profiler des Threads, falls einer hängt.
  TCheckProfiler.RuleTimed(ARuleId, TCheckProfiler.TicksToMicroseconds(AWatch.ElapsedTicks, TStopwatch.Frequency));
  if AWatch.ElapsedMilliseconds >= TRuleEngine.cSlowRuleMs then
  begin
    TRequestDiagnostics.Slowest('slowRule', ARuleId, Integer(AWatch.ElapsedMilliseconds));
  end;
end;

procedure TRuleRun.Defer(const ARule: IRule; const ARuleId: string; ASeverity: TRuleSeverity;
  const AContext: TRuleContext);
var
  mDeferred: TDeferredRule;
begin
  mDeferred := Default(TDeferredRule);
  if Supports(ARule, IRuleAfterFindings, mDeferred.Rule) then
  begin
    mDeferred.Id := ARuleId;
    mDeferred.Severity := ASeverity;
    mDeferred.Context := AContext;
    FDeferred.Add(mDeferred);
  end;
end;

procedure TRuleRun.RunRule(const ARule: IRule);
var
  mDescriptor: TRuleDescriptor;
  mSeverity: TRuleSeverity;
  mContext: TRuleContext;
  mCondition: IRuleCondition;
  mWatch: TStopwatch;
begin
  mDescriptor := ARule.Descriptor;
  if not Runs(mDescriptor, mSeverity) then
  begin
    Exit;
  end;
  mContext := RuleContext(mDescriptor.Id);
  if TRuleEngine.IsExceptedByOptions(mContext.Options, mContext.RelativePath, mContext.UnitName) then
  begin
    Exit;
  end;
  // Kann die Regel hier nicht prüfen (#1135), läuft sie nicht: sonst gälte ihr lsp-ignore als unnötig.
  if Supports(ARule, IRuleCondition, mCondition) and not mCondition.Applies(mContext) then
  begin
    Exit;
  end;
  CheckCancelled;
  mWatch := TStopwatch.StartNew;
  if Checked(ARule, mDescriptor.Id, mSeverity, mContext) then
  begin
    RuleTimed(mDescriptor.Id, mWatch);
    FRanIds.Add(LowerCase(mDescriptor.Id));
    Defer(ARule, mDescriptor.Id, mSeverity, mContext);
    NoteUncertain(ARule, mDescriptor.Id, mContext);
  end;
end;

procedure TRuleRun.RunDeferred(const ADeferred: TDeferredRule);
var
  mReport: IRuleReport;
  mBefore: Integer;
  mWatch: TStopwatch;
begin
  mReport := TRuleReport.Create(ADeferred.Id, ADeferred.Severity, FFindings);
  TRequestDiagnostics.CurrentRule(ADeferred.Id);
  mBefore := FFindings.Count;
  mWatch := TStopwatch.StartNew;
  try
    ADeferred.Rule.CheckFindings(ADeferred.Context, FFindings.ToArray, FRanIds.ToArray, mReport);
    TCheckProfiler.RuleTimed(ADeferred.Id, TCheckProfiler.TicksToMicroseconds(mWatch.ElapsedTicks,
      TStopwatch.Frequency));
  except
    on E: Exception do
    begin
      if MustRaise(E) then
      begin
        raise;
      end;
      Discard(E, ADeferred.Id, mBefore);
    end;
  end;
  TRequestDiagnostics.CurrentRule('');
end;

procedure TRuleRun.KeepUnsuppressed;
var
  mFinding: TRuleFinding;
  mMinConfidence: TRuleConfidence;
begin
  mMinConfidence := TRuleProfiles.MinConfidence(FSettings, FSettings.Profile);
  // Erst unterdrücken, dann filtern: Auch ausgeblendete Treffer machen einen Kommentar wirksam.
  for mFinding in FFindings do
  begin
    if ((FSuppressions = nil) or not FSuppressions.IsSuppressed(mFinding.RuleId, mFinding.Range.StartPos.Line)) and
      (Ord(mFinding.Confidence) >= Ord(mMinConfidence)) then
    begin
      FKept.Add(mFinding);
    end;
  end;
end;

function TRuleRun.AllRan(const AEntry: TSuppressionEntry): Boolean;
var
  mId: string;
begin
  Result := Length(AEntry.Ids) > 0;
  for mId in AEntry.Ids do
  begin
    if (mId <> '*') and not FRanIds.Contains(mId) then
    begin
      Exit(False);
    end;
  end;
end;

procedure TRuleRun.NoteUncertain(const ARule: IRule; const ARuleId: string; const AContext: TRuleContext);
var
  mUncertain: TUncertainRule;
begin
  if Supports(ARule, IRuleLineCertainty, mUncertain.Certainty) then
  begin
    mUncertain.Id := LowerCase(ARuleId);
    mUncertain.Context := AContext;
    FUncertain.Add(mUncertain);
  end;
end;

/// <summary>Konnte jede genannte Regel mit IRuleLineCertainty die Zeile von AEntry entscheiden? Gefragt wird
/// erst hier, also nur bei Kommentaren ohne Wirkung.</summary>
function TRuleRun.AllDecided(const AEntry: TSuppressionEntry): Boolean;
var
  mUncertain: TUncertainRule;
begin
  for mUncertain in FUncertain do
  begin
    if ((IndexStr(mUncertain.Id, AEntry.Ids) >= 0) or (IndexStr('*', AEntry.Ids) >= 0)) and
      not mUncertain.Certainty.Decides(mUncertain.Context, AEntry.TargetLine) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Hinweis unused-suppression für AEntry mit Korrektur zum Entfernen (#147).</summary>
function UnusedSuppressionFinding(const AEntry: TSuppressionEntry; ASeverity: TRuleSeverity): TRuleFinding;
var
  mRemoval: TTextRange;
begin
  if AEntry.OwnLine then
  begin
    mRemoval := TTextRange.Create(AEntry.Range.StartPos.Line, 0, AEntry.Range.EndPos.Line + 1, 0);
  end
  else
  begin
    mRemoval := AEntry.Range;
  end;
  Result := Default(TRuleFinding);
  Result.RuleId := cUnusedSuppressionRuleId;
  Result.Range := AEntry.Range;
  Result.Message := cTexts[TEngineText.UnusedSuppression].Text;
  Result.Severity := ASeverity;
  Result.Confidence := TRuleConfidence.High;
  Result.Fixes := [TRuleFix.Create(cTexts[TEngineText.RemoveSuppression].Text, [TRuleEdit.Create(mRemoval, '')],
    True)];
end;

procedure TRuleRun.KeepUnusedSuppressions;
var
  mSeverity: TRuleSeverity;
  mEntry: TSuppressionEntry;
begin
  mSeverity := FSettings.RuleSeverity(cUnusedSuppressionRuleId, TRuleSeverity.Hint);
  if mSeverity = TRuleSeverity.Off then
  begin
    Exit;
  end;
  for mEntry in FSuppressions.UnusedEntries do
  begin
    if AllRan(mEntry) and AllDecided(mEntry) then
    begin
      FKept.Add(UnusedSuppressionFinding(mEntry, mSeverity));
    end;
  end;
end;

function TRuleRun.KnownRuleIds: TArray<string>;
var
  mCatalog: TArray<string>;
  mIndex: Integer;
begin
  mCatalog := TRuleProfiles.KnownRuleIds;
  SetLength(Result, Length(mCatalog) + Length(FRules));
  for mIndex := 0 to High(mCatalog) do
  begin
    Result[mIndex] := mCatalog[mIndex];
  end;
  for mIndex := 0 to High(FRules) do
  begin
    Result[Length(mCatalog) + mIndex] := LowerCase(FRules[mIndex].Descriptor.Id);
  end;
end;

/// <summary>Hinweis unknown-rule-id für die Kennung AIndex von AEntry, mit Tippfehler-Vorschlag aus AKnown und
/// Korrektur, wenn die Kennung in einer Zeile steht (#41).</summary>
function UnknownRuleIdFinding(const AEntry: TSuppressionEntry; AIndex: Integer; const AKnown: TArray<string>;
  ASeverity: TRuleSeverity): TRuleFinding;
var
  mId, mSuggestion: string;
  mRange: TTextRange;
begin
  mId := AEntry.Ids[AIndex];
  mRange := AEntry.IdRanges[AIndex];
  mSuggestion := TSuppressions.Suggest(mId, AKnown);
  Result := Default(TRuleFinding);
  Result.RuleId := cUnknownRuleIdRuleId;
  Result.Range := mRange;
  Result.Severity := ASeverity;
  Result.Confidence := TRuleConfidence.High;
  if mSuggestion = '' then
  begin
    Result.Message := cTexts[TEngineText.UnknownRuleId].Fmt([mId]);
    Exit;
  end;
  Result.Message := cTexts[TEngineText.UnknownRuleIdGuess].Fmt([mId, mSuggestion]);
  // Nur genau markierte Kennungen ersetzen, nicht den ganzen Kommentar.
  if mRange.StartPos.Line = mRange.EndPos.Line then
  begin
    Result.Fixes := [TRuleFix.Create(cTexts[TEngineText.ReplaceWith].Fmt([mSuggestion]),
      [TRuleEdit.Create(mRange, mSuggestion)], True)];
  end;
end;

procedure TRuleRun.KeepUnknownRuleIds;
var
  mSeverity: TRuleSeverity;
  mKnown: TArray<string>;
  mEntry: TSuppressionEntry;
  mIndex: Integer;
begin
  mSeverity := FSettings.RuleSeverity(cUnknownRuleIdRuleId, TRuleSeverity.Hint);
  if (Length(FSuppressions.Entries) = 0) or (mSeverity = TRuleSeverity.Off) then
  begin
    Exit;
  end;
  mKnown := KnownRuleIds;
  for mEntry in FSuppressions.Entries do
  begin
    for mIndex := 0 to High(mEntry.Ids) do
    begin
      if (mEntry.Ids[mIndex] <> '*') and (IndexText(TRuleIdAliases.Current(mEntry.Ids[mIndex]), mKnown) < 0) then
      begin
        FKept.Add(UnknownRuleIdFinding(mEntry, mIndex, mKnown, mSeverity));
      end;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Engine', cTexts);

end.
