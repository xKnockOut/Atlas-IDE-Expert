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
// oder unbekannte Regeln nicht stören.
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
// Laufzeit (Diagnoselog 15.10.2026): Vor jeder Regel fragt die Engine
// AContext.Cancelled und bricht mit ERuleCheckCancelled ab. Früher lief eine
// abgebrochene oder überholte Prüfung bis zum Ende weiter (bis 240 s). Die
// langsamste Regel ab SlowRuleMs geht als slowRule/slowRuleMs ins Diagnoselog.
//
// Robustheit (#1094, Bericht M1): Die Regeln und ihre Dienste gehen iterativ
// durch den Baum (TSyntaxNode.Walk/Search oder eigener Stapel), auch lange
// Ketten wie 1 - 1 - … - 1 sprengen den Stapel nicht. MaxTreeDepth bleibt als
// Netz für unbekannte rekursive Wege: Ist der Baum tiefer, laufen die Regeln
// für diese Datei nicht; die Datei bekommt den Hinweis unit-too-deep an der
// tiefsten Stelle und steht als deepUnit im Diagnoselog. Früher lag die Grenze
// bei 1000 Ebenen, und solche Units verloren still alle Befunde.
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
  UnusedSuppressionRuleId = 'unused-suppression';
  UnknownRuleIdRuleId = 'unknown-rule-id';
  /// <summary>Hinweis, dass die Regeln eine Unit wegen MaxTreeDepth übersprungen haben (Bericht M1).</summary>
  UnitTooDeepRuleId = 'unit-too-deep';

type
  TRuleEngine = class
  public const
    /// <summary>Ab dieser Dauer nennt das Diagnoselog die Regel.</summary>
    SlowRuleMs = 100;
    /// <summary>Netz (#1094, Bericht M1): Tiefere Syntaxbäume prüfen die Regeln nicht, die Unit bekommt den
    /// Hinweis unit-too-deep. Alle Regeln laufen iterativ; TBuiltinRulesTests prüft sie mit Ketten von 5000
    /// Gliedern in 128 KB Stapel. Die Grenze fängt nur unbekannte rekursive Wege ab; so tiefe Bäume entstehen erst aus
    /// Ketten mit 100000 Gliedern.</summary>
    MaxTreeDepth = 100000;
  public
    /// <summary>Wirksamer Schweregrad einer Regel; Off = nicht ausführen.</summary>
    class function EffectiveSeverity(const ARule: TRuleDescriptor;
      const ASettings: TServerSettings; const ARelativePath: string = ''): TRuleSeverity; overload; static;
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
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Profiles,
  Atlas.Common.Rules.Suppressions,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Semantics.TreeUnits;

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

/// <summary>Hinweis unit-too-deep an der tiefsten Stelle einer Unit, deren Baum tiefer als MaxTreeDepth ist
/// (Bericht M1); leer, wenn der Hinweis abgeschaltet ist.</summary>
function TooDeepFindings(ATree: TSyntaxTree; const ASettings: TServerSettings): TArray<TRuleFinding>;
var
  Finding: TRuleFinding;
  Node: TSyntaxNode;
begin
  Result := nil;
  if ASettings.RuleSeverity(UnitTooDeepRuleId, TRuleSeverity.Hint) = TRuleSeverity.Off then
    Exit;
  Node := ATree.Deepest;
  Finding := Default(TRuleFinding);
  Finding.RuleId := UnitTooDeepRuleId;
  Finding.Range := TTextRange.Create(Node.StartPos, Node.EndPos);
  Finding.Message := Format('Die Prüfregeln laufen für diese Unit nicht: Der Syntaxbaum ist %d Ebenen tief ' +
    '(Grenze %d). Die tiefste Stelle liegt hier; eine lange Kette aus - oder * in Teilausdrücke aufteilen',
    [ATree.Depth, TRuleEngine.MaxTreeDepth]);
  Finding.Severity := ASettings.RuleSeverity(UnitTooDeepRuleId, TRuleSeverity.Hint);
  Finding.Confidence := TRuleConfidence.High;
  Result := [Finding];
end;

function CompareFindings(const A, B: TRuleFinding): Integer;
begin
  Result := A.Range.StartPos.Line - B.Range.StartPos.Line;
  if Result = 0 then
    Result := A.Range.StartPos.Character - B.Range.StartPos.Character;
  if Result = 0 then
    Result := CompareText(A.RuleId, B.RuleId);
end;

/// <summary>AFindings nach CompareFindings, bei Gleichstand in Meldereihenfolge (Delphis Sort ist nicht stabil:
/// {$R-,Q-} meldet zwei Treffer derselben Regel an derselben Stelle).</summary>
function SortedFindings(const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  Items: TArray<TRuleFinding>;
  Order: TArray<Integer>;
  Index: Integer;
begin
  Items := AFindings;
  SetLength(Order, Length(Items));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := CompareFindings(Items[A], Items[B]);
      if Result = 0 then
        Result := A - B;
    end));
  SetLength(Result, Length(Items));
  for Index := 0 to High(Order) do
    Result[Index] := Items[Order[Index]];
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
  Finding: TRuleFinding;
begin
  Finding.RuleId := FRuleId;
  Finding.Range := ARange;
  Finding.Message := AMessage;
  Finding.Severity := TRuleEngine.CapSeverity(FSeverity, AConfidence);
  Finding.Confidence := AConfidence;
  Finding.Fixes := AFixes;
  Finding.Details := '';
  FFindings.Add(Finding);
end;

procedure TRuleReport.AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string;
  AConfidence: TRuleConfidence; const AFixes: TArray<TRuleFix>);
var
  Finding: TRuleFinding;
begin
  Finding.RuleId := FRuleId;
  Finding.Range := ARange;
  Finding.Message := AMessage;
  Finding.Severity := TRuleEngine.CapSeverity(FSeverity, AConfidence);
  Finding.Confidence := AConfidence;
  Finding.Fixes := AFixes;
  Finding.Details := ADetails;
  FFindings.Add(Finding);
end;

procedure TRuleReport.AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
  const AFixes: TArray<TRuleFix>);
var
  Finding: TRuleFinding;
begin
  if ASeverity = TRuleSeverity.Off then
    Exit;
  Finding.RuleId := FRuleId;
  Finding.Range := ARange;
  Finding.Message := AMessage;
  if ASeverity = TRuleSeverity.Default then
    Finding.Severity := FSeverity
  else
    Finding.Severity := ASeverity;
  Finding.Confidence := TRuleConfidence.High;
  Finding.Fixes := AFixes;
  Finding.Details := '';
  FFindings.Add(Finding);
end;

procedure TRuleReport.AddRelated(const ARange: TTextRange; const AMessage, ADetails: string; ASeverity: TRuleSeverity;
  const AFixes: TArray<TRuleFix>; const ARelated: TArray<TRuleRelated>);
var
  Finding: TRuleFinding;
begin
  if ASeverity = TRuleSeverity.Off then
    Exit;
  Finding.RuleId := FRuleId;
  Finding.Range := ARange;
  Finding.Message := AMessage;
  if ASeverity = TRuleSeverity.Default then
    Finding.Severity := FSeverity
  else
    Finding.Severity := ASeverity;
  Finding.Confidence := TRuleConfidence.High;
  Finding.Fixes := AFixes;
  Finding.Details := ADetails;
  Finding.Related := ARelated;
  FFindings.Add(Finding);
end;

{ TRuleEngine }

class function TRuleEngine.EffectiveSeverity(const ARule: TRuleDescriptor;
  const ASettings: TServerSettings; const ARelativePath: string): TRuleSeverity;
var
  Enabled: Boolean;
begin
  Result := EffectiveSeverity(ARule, ASettings, ARelativePath, Enabled);
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
    Result := TRuleSeverity.Warning;
end;

class function TRuleEngine.GroupOff(const ARuleId: string; const ASettings: TServerSettings): Boolean;
var
  Entry: TRuleCatalogEntry;
begin
  Result := (Length(ASettings.Rules) > 0) and TRuleCatalog.Shared.TryFind(ARuleId, Entry) and
    (ASettings.RuleSeverity(TRuleCatalog.GroupKey(Entry.Group), TRuleSeverity.Default) = TRuleSeverity.Off);
end;

class function TRuleEngine.TypeLevelOff(const ARuleId: string; const ASettings: TServerSettings): Boolean;
var
  Entry: TRuleCatalogEntry;
  Options: string;
  Value, Level: TJSONValue;
begin
  Result := False;
  if (Length(ASettings.Rules) = 0) or not TRuleCatalog.Shared.TryFind(ARuleId, Entry) or
    (Entry.Group <> TRuleGroup.Compiler) or (Entry.Level <> 'T') then
    Exit;
  Options := RuleOptions(TRuleCatalog.GroupKey(Entry.Group), ASettings);
  if Options = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(Options);
  try
    if Value is TJSONObject then
    begin
      Level := TJSONObject(Value).GetValue('typeLevel');
      Result := (Level is TJSONString) and SameText(TJSONString(Level).Value, 'off');
    end;
  finally
    Value.Free;
  end;
end;

class function TRuleEngine.CapSeverity(ASeverity: TRuleSeverity; AConfidence: TRuleConfidence): TRuleSeverity;
var
  Limit: TRuleSeverity;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Limit := TRuleSeverity.Hint;
    TRuleConfidence.Medium:
      Limit := TRuleSeverity.Warning;
  else
    Limit := TRuleSeverity.Error;
  end;
  if Ord(ASeverity) > Ord(Limit) then
    Result := Limit
  else
    Result := ASeverity;
end;

class function TRuleEngine.RuleOptions(const ARuleId: string; const ASettings: TServerSettings): string;
var
  Rule: TRuleSetting;
begin
  for Rule in ASettings.Rules do
    if SameText(Rule.Id, ARuleId) then
      Exit(Rule.Options);
  Result := '';
end;

class function TRuleEngine.IsExceptedByOptions(const AOptions, ARelativePath, AUnitName: string): Boolean;
var
  Value: TJSONValue;
  Exclude: TJSONValue;
  Item: TJSONValue;
  Pattern: string;
begin
  Result := False;
  if AOptions = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Exclude := TJSONObject(Value).GetValue('exclude');
    if not (Exclude is TJSONArray) then
      Exit;
    for Item in TJSONArray(Exclude) do
    begin
      if not (Item is TJSONString) then
        Continue;
      Pattern := Item.Value;
      if ((AUnitName <> '') and SameText(Pattern, AUnitName)) or
        ((ARelativePath <> '') and MatchesGlob(Pattern, ARelativePath)) then
        Exit(True);
    end;
  finally
    Value.Free;
  end;
end;

class function TRuleEngine.OverridingRule(const ARuleId: string; const ARules: TArray<IRule>;
  const ASettings: TServerSettings; const ARelativePath, AUnitName: string): string;
var
  Entry, Other: TRuleCatalogEntry;
  Id: string;
  Rule: IRule;
  Descriptor: TRuleDescriptor;
  Found, Enabled: Boolean;
begin
  Result := '';
  if not TRuleCatalog.Shared.TryFind(ARuleId, Entry) then
    Exit;
  for Id in Entry.OverriddenBy do
  begin
    Found := False;
    for Rule in ARules do
      if SameText(Rule.Descriptor.Id, Id) then
      begin
        Descriptor := Rule.Descriptor;
        Found := True;
        Break;
      end;
    if not Found then
    begin
      if not TRuleCatalog.Shared.TryFind(Id, Other) then
        Continue;
      Descriptor := TRuleDescriptor.Create(Other.Id, Other.DefaultSeverity, Other.Name);
    end;
    if EffectiveSeverity(Descriptor, ASettings, ARelativePath, Enabled) = TRuleSeverity.Off then
      Continue;
    if (Descriptor.Experimental and not Enabled) or
      IsExceptedByOptions(RuleOptions(Descriptor.Id, ASettings), ARelativePath, AUnitName) then
      Continue;
    Exit(Descriptor.Id);
  end;
end;

class function TRuleEngine.NewNames(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const AContext: TRuleContext): TPascalNamePrefixes;
var
  Rule: IRule;
  Source: IRuleNewNames;
  Descriptor: TRuleDescriptor;
  Enabled: Boolean;
  Context: TRuleContext;
begin
  Result := TPascalNamePrefixes.None;
  for Rule in ARules do
  begin
    if not Supports(Rule, IRuleNewNames, Source) then
      Continue;
    Descriptor := Rule.Descriptor;
    // Dieselben Bedingungen wie für den Lauf der Regel: Schweregrad, experimentell, Ausnahmen der Optionen.
    if (EffectiveSeverity(Descriptor, ASettings, AContext.RelativePath, Enabled) = TRuleSeverity.Off) or
      (Descriptor.Experimental and not Enabled) then
      Continue;
    Context := AContext;
    Context.Options := RuleOptions(Descriptor.Id, ASettings);
    if IsExceptedByOptions(Context.Options, Context.RelativePath, Context.UnitName) then
      Continue;
    Exit(Source.NewNames(Context));
  end;
end;

class function TRuleEngine.Run(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const AContext: TRuleContext): TArray<TRuleFinding>;
var
  Findings: TList<TRuleFinding>;
  Kept: TList<TRuleFinding>;
  Suppressions: TSuppressions;
  Rule: IRule;
  Report: IRuleReport;
  Descriptor: TRuleDescriptor;
  Severity: TRuleSeverity;
  Context: TRuleContext;
  Finding: TRuleFinding;
  RanIds: TList<string>;
  Entry: TSuppressionEntry;
  Id: string;
  AllRan: Boolean;
  Removal: TTextRange;
  Enabled: Boolean;
  Settings: TServerSettings;
  MinConfidence: TRuleConfidence;
  Watch: TStopwatch;
  Elapsed: Int64;
  Shared: TRuleContext;
  OwnCache: IRuleDerivedCache;
  mOwnUnits: ITreeUnits;
  Known: TArray<string>;
  Index: Integer;
  Suggestion: string;
  After: IRuleAfterFindings;
  Afters: TList<IRuleAfterFindings>;
  AfterIds: TList<string>;
  AfterSeverities: TList<TRuleSeverity>;
  AfterContexts: TList<TRuleContext>;
  Before: Integer;
  Failed: Boolean;
begin
  if (AContext.RelativePath <> '') and ASettings.IsExcluded(AContext.RelativePath) then
    Exit(nil);
  Settings := ASettings;
  if (ASettings.ExcludeTests or (ASettings.TestProfile <> '')) and (AContext.Tree <> nil) and
    TRuleProfiles.IsTestUnit(AContext.Tree.Tokens) then
  begin
    if ASettings.ExcludeTests then
      Exit(nil);
    Settings.Profile := ASettings.TestProfile;
  end;
  if (AContext.Tree <> nil) and (AContext.Tree.Depth > MaxTreeDepth) then
  begin
    TRequestDiagnostics.TreeTooDeep(AContext.Tree.Depth);
    Result := TooDeepFindings(AContext.Tree, ASettings);
    Exit;
  end;
  MinConfidence := TRuleProfiles.MinConfidence(Settings, Settings.Profile);
  // Ein Ableitungscache für alle Regeln des Laufs (Review P-03); ein vom Aufrufer
  // gesetzter Cache gehört dem Aufrufer und bleibt gefüllt.
  Shared := AContext;
  // Neue Namen der Korrekturen nach der Namensregel (#1111), einmal für alle Regeln.
  Shared.NewNames := NewNames(ARules, Settings, Shared);
  OwnCache := nil;
  if Shared.Derived = nil then
  begin
    OwnCache := TRuleDerivedCache.Create;
    Shared.Derived := OwnCache;
  end;
  // Eine Auswertung des Baums für alle Namensauflöser des Laufs (#1322): Sonst extrahierte jede Typabfrage
  // eines nicht gepinnten Resolvers die ganze Unit neu, und Regeln mit vielen Abfragen wurden quadratisch.
  mOwnUnits := nil;
  if (Shared.TreeUnits = nil) and (Shared.Tree <> nil) then
  begin
    mOwnUnits := TTreeUnits.Create(Shared.Tree);
    Shared.TreeUnits := mOwnUnits;
  end;
  Findings := TList<TRuleFinding>.Create;
  Kept := TList<TRuleFinding>.Create;
  Suppressions := nil;
  RanIds := TList<string>.Create;
  Afters := TList<IRuleAfterFindings>.Create;
  AfterIds := TList<string>.Create;
  AfterSeverities := TList<TRuleSeverity>.Create;
  AfterContexts := TList<TRuleContext>.Create;
  try
    for Rule in ARules do
    begin
      Descriptor := Rule.Descriptor;
      Severity := EffectiveSeverity(Descriptor, Settings, AContext.RelativePath, Enabled);
      if Severity = TRuleSeverity.Off then
        Continue;
      if Descriptor.Experimental and not Enabled then
        Continue;
      if OverridingRule(Descriptor.Id, ARules, Settings, AContext.RelativePath, AContext.UnitName) <> '' then
        Continue;
      Context := Shared;
      // Sprachstand (#1126): Korrekturen erzeugen keine Merkmale, die minDelphiVersion nicht kennt.
      if Context.DelphiVersion = '' then
        Context.DelphiVersion := TLanguageFeatures.LanguageLevel(Settings.DelphiVersion, Settings.MinDelphiVersion);
      Context.Options := RuleOptions(Descriptor.Id, Settings);
      Context.DfmPropertyRules := Settings.DfmPropertyRules;
      Context.NoSignatureSync := not Settings.Refactoring.SyncSignatures;
      Context.NoForwardDeclaration := not Settings.Refactoring.ForwardDeclaration;
      Context.NoFreeFields := not Settings.Refactoring.FreeFields;
      Context.FreeFieldsFreeAndNil := SameText(Settings.Refactoring.FreeFieldsStyle, 'freeAndNil');
      Context.NoMethodKind := not Settings.Refactoring.MethodKind;
      Context.MethodKindStatic := Settings.Refactoring.MethodKindStatic;
      Context.InlineAccessorDiagnostic := Settings.Refactoring.InlineAccessor and
        Settings.Refactoring.InlineAccessorDiagnostic;
      Context.NoAccessorEqualityCheck := not Settings.Refactoring.InlineAccessorEqualityCheck;
      Context.AccessorsProtected := Settings.Completion.AccessorSection = TCompletionAccessorSection.Protected;
      Context.Formatting := Settings.Formatting;
      Context.KeepAttributes := Settings.DeadCodeKeepAttributes;
      Context.KeepPatterns := Settings.DeadCodeKeepPatterns;
      Context.NoUsesCycleLive := not Settings.DiagnosticsUsesCycleLive;
      Context.UsesCycleImplementation := Settings.DiagnosticsUsesCycleImplementation;
      Context.SortUses := Settings.SortUses;
      Context.SortUsesByNamespace := Settings.SortUsesByNamespace;
      if IsExceptedByOptions(Context.Options, Context.RelativePath, Context.UnitName) then
        Continue;
      // Erst in einer Interface-Variablen halten: Check nimmt den Report als
      // const; ohne gezählte Referenz würde er nie freigegeben (Speicherleck).
      if Assigned(AContext.Cancelled) and AContext.Cancelled() then
        raise ERuleCheckCancelled.Create('Prüfung abgebrochen');
      Report := TRuleReport.Create(Descriptor.Id, Severity, Findings);
      Watch := TStopwatch.StartNew;
      TRequestDiagnostics.CurrentRule(Descriptor.Id);
      Before := Findings.Count;
      Failed := False;
      try
        Rule.Check(Context, Report);
      except
        on ERuleCheckCancelled do
          raise;
        on E: Exception do
        begin
          // Abgebrochen wird weiter wie bisher; sonst kostet eine scheiternde Regel nur ihre eigenen
          // Treffer (#1094).
          if Assigned(AContext.Cancelled) and AContext.Cancelled() then
            raise;
          Findings.Count := Before;
          TStackGuard.AfterError(E);
          TRequestDiagnostics.RuleFailed(Descriptor.Id, E.ClassName);
          Failed := True;
        end;
      end;
      TRequestDiagnostics.CurrentRule('');
      Report := nil;
      if Failed then
        Continue;
      Elapsed := Watch.ElapsedMilliseconds;
      if Elapsed >= SlowRuleMs then
        TRequestDiagnostics.Slowest('slowRule', Descriptor.Id, Integer(Elapsed));
      RanIds.Add(LowerCase(Descriptor.Id));
      if Supports(Rule, IRuleAfterFindings, After) then
      begin
        Afters.Add(After);
        AfterIds.Add(Descriptor.Id);
        AfterSeverities.Add(Severity);
        AfterContexts.Add(Context);
      end;
      After := nil;
    end;
    // Nach allen Regeln, mit den rohen Treffern (#297).
    for Index := 0 to Afters.Count - 1 do
    begin
      Report := TRuleReport.Create(AfterIds[Index], AfterSeverities[Index], Findings);
      TRequestDiagnostics.CurrentRule(AfterIds[Index]);
      Before := Findings.Count;
      try
        Afters[Index].CheckFindings(AfterContexts[Index], Findings.ToArray, RanIds.ToArray, Report);
      except
        on ERuleCheckCancelled do
          raise;
        on E: Exception do
        begin
          if Assigned(AContext.Cancelled) and AContext.Cancelled() then
            raise;
          Findings.Count := Before;
          TStackGuard.AfterError(E);
          TRequestDiagnostics.RuleFailed(AfterIds[Index], E.ClassName);
        end;
      end;
      TRequestDiagnostics.CurrentRule('');
      Report := nil;
    end;

    if AContext.Tree <> nil then
      Suppressions := TSuppressions.Create(AContext.Tree.Tokens);
    // Erst unterdrücken, dann filtern: Auch ausgeblendete Treffer machen einen Kommentar wirksam.
    for Finding in Findings do
      if ((Suppressions = nil) or not Suppressions.IsSuppressed(Finding.RuleId, Finding.Range.StartPos.Line)) and
        (Ord(Finding.Confidence) >= Ord(MinConfidence)) then
        Kept.Add(Finding);

    if (Suppressions <> nil) and
      (ASettings.RuleSeverity(UnusedSuppressionRuleId, TRuleSeverity.Hint) <> TRuleSeverity.Off) then
      for Entry in Suppressions.UnusedEntries do
      begin
        AllRan := Length(Entry.Ids) > 0;
        for Id in Entry.Ids do
          if (Id <> '*') and not RanIds.Contains(Id) then
            AllRan := False;
        if not AllRan then
          Continue;
        if Entry.OwnLine then
          Removal := TTextRange.Create(Entry.Range.StartPos.Line, 0, Entry.Range.EndPos.Line + 1, 0)
        else
          Removal := Entry.Range;
        Finding := Default(TRuleFinding);
        Finding.RuleId := UnusedSuppressionRuleId;
        Finding.Range := Entry.Range;
        Finding.Message := 'Unterdrückung ohne Wirkung: hier meldet keine der genannten Regeln etwas';
        Finding.Severity := ASettings.RuleSeverity(UnusedSuppressionRuleId, TRuleSeverity.Hint);
        Finding.Confidence := TRuleConfidence.High;
        Finding.Fixes := [TRuleFix.Create('Unterdrückung entfernen', [TRuleEdit.Create(Removal, '')], True)];
        Kept.Add(Finding);
      end;

    if (Suppressions <> nil) and (Length(Suppressions.Entries) > 0) and
      (ASettings.RuleSeverity(UnknownRuleIdRuleId, TRuleSeverity.Hint) <> TRuleSeverity.Off) then
    begin
      Known := TRuleProfiles.KnownRuleIds;
      for Rule in ARules do
        Known := Known + [LowerCase(Rule.Descriptor.Id)];
      for Entry in Suppressions.Entries do
        for Index := 0 to High(Entry.Ids) do
        begin
          Id := Entry.Ids[Index];
          if (Id = '*') or (IndexText(TRuleIdAliases.Current(Id), Known) >= 0) then
            Continue;
          Suggestion := TSuppressions.Suggest(Id, Known);
          Finding := Default(TRuleFinding);
          Finding.RuleId := UnknownRuleIdRuleId;
          Finding.Range := Entry.IdRanges[Index];
          Finding.Severity := ASettings.RuleSeverity(UnknownRuleIdRuleId, TRuleSeverity.Hint);
          Finding.Confidence := TRuleConfidence.High;
          if Suggestion = '' then
            Finding.Message := Format('Unbekannte Regelkennung "%s"; die Unterdrückung wirkt nicht', [Id])
          else
          begin
            Finding.Message := Format('Unbekannte Regelkennung "%s"; gemeint ist vermutlich "%s"', [Id, Suggestion]);
            // Nur genau markierte Kennungen ersetzen, nicht den ganzen Kommentar.
            if Entry.IdRanges[Index].StartPos.Line = Entry.IdRanges[Index].EndPos.Line then
              Finding.Fixes := [TRuleFix.Create(Format('Durch "%s" ersetzen', [Suggestion]),
                [TRuleEdit.Create(Entry.IdRanges[Index], Suggestion)], True)];
          end;
          Kept.Add(Finding);
        end;
    end;

    Result := SortedFindings(Kept.ToArray);
  finally
    // Gibt Graphen und Modelle frei, bevor der Aufrufer den Baum freigibt, und bricht
    // Referenzzyklen über Kontextkopien in abgelegten Objekten.
    if OwnCache <> nil then
      OwnCache.Clear;
    // Kontextkopien in abgelegten Objekten können die Auswertung überleben: ohne Baum bedient sie keinen mehr.
    if mOwnUnits <> nil then
      mOwnUnits.Clear;
    AfterContexts.Free;
    AfterSeverities.Free;
    AfterIds.Free;
    Afters.Free;
    RanIds.Free;
    Suppressions.Free;
    Kept.Free;
    Findings.Free;
  end;
end;

end.
