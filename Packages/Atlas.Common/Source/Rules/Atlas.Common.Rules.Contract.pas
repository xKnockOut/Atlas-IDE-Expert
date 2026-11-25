unit Atlas.Common.Rules.Contract;

// Gemeinsame Grundlage aller Prüfregeln: Beschreibung, Kontext einer Prüfung,
// Treffer mit optionalen Korrekturen und die Schnittstelle einer Regel.
// Regeln melden lieber zu wenig als zu viel (Spezifikation, Abschnitt 11).
// Jeder Treffer trägt eine Konfidenz; sie begrenzt den Schweregrad (#144).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Projects.Contract.UnitLookup,
  // Genehmigte Ausnahme der Rollenmatrix (Architektur.md, "Genehmigte Ausnahmen"): der Syntaxbaum ist
  // Datengrundlage jeder Regel und hängt selbst nur an Contracts.
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Query.Contract,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Checks.Contract,
  Atlas.Common.Checks.Contract.Refactorings;

type
  /// <summary>Feste Angaben einer Regel.</summary>
  TRuleDescriptor = record
    /// <summary>Kennung in Kleinbuchstaben mit Bindestrich, z. B. "empty-except".</summary>
    Id: string;
    /// <summary>Schweregrad ohne Konfiguration; nie Default.</summary>
    DefaultSeverity: TRuleSeverity;
    Description: string;
    // Ob die Regel experimentell ist (nur im Profil strict oder ausdrücklich eingeschaltet), steht allein im
    // Regelkatalog ("profiles", #145): TRuleProfiles.IsExperimental.
    constructor Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string);
  end;

  /// <summary>Eine Textersetzung einer Korrektur. Alias auf TTextEdit aus Documents.Contract,
  /// damit Editing die Textänderung ohne Abhängigkeit von Rules nutzen kann.</summary>
  TRuleEdit = TTextEdit;

  /// <summary>Befund-Wertetypen aus Findings.Contract: Sprachserver, MCP und Ausgaben verwenden sie, ohne die
  /// Prüfregeln einzubinden.</summary>
  TRuleFileEdits = Atlas.Common.Findings.Contract.TRuleFileEdits;
  TRuleFix = Atlas.Common.Findings.Contract.TRuleFix;
  TRuleRelated = Atlas.Common.Findings.Contract.TRuleRelated;
  TRuleFinding = Atlas.Common.Findings.Contract.TRuleFinding;

  /// <summary>Liest eine Datei neben der Unit, z. B. die .dcr aus {$R *.dcr} (#114).</summary>
  TRuleFileReader = reference to function(const AFileName: string; out AData: TBytes): Boolean;
  /// <summary>Gibt es die Datei AFileName, relativ zum Ordner der Unit oder absolut (#1379)? Liest nichts.</summary>
  TRuleFileExists = reference to function(const AFileName: string): Boolean;
  /// <summary>Unit-Suche und Packages (Atlas.Common.Projects.Contract.UnitLookup) unter den Namen der Regeln.</summary>
  TRulePackageAnswer = Atlas.Common.Projects.Contract.UnitLookup.TPackageAnswer;
  TRulePackageProvides = Atlas.Common.Projects.Contract.UnitLookup.TPackageProvides;
  TRulePackageRequires = Atlas.Common.Projects.Contract.UnitLookup.TPackageRequires;
  TRuleUnitAnswer = Atlas.Common.Projects.Contract.UnitLookup.TUnitAnswer;
  TRuleUnitSource = Atlas.Common.Projects.Contract.UnitLookup.TUnitSource;
  TRuleUnitSources = Atlas.Common.Projects.Contract.UnitLookup.TUnitSources;
  IRuleUnitLookup = Atlas.Common.Projects.Contract.UnitLookup.IUnitLookup;

  TRuleCancelled = Atlas.Common.Findings.Contract.TRuleCancelled;

  ERuleCheckCancelled = Atlas.Common.Findings.Contract.ERuleCheckCancelled;

  /// <summary>Ableitungen einer Prüfung, die alle Regeln eines Laufs teilen.
  /// Besitzt die abgelegten Objekte. Nicht threadsicher: ein Cache gehört genau einem Lauf.
  /// Zugriff typisiert über TRuleDerived (Atlas.Common.Rules.Derived).</summary>
  IRuleDerivedCache = interface
    ['{5CCE4184-2A0F-49C4-9B27-84C08CAC8109}']
    function TryGet(const AKey: string; out AValue: TObject): Boolean;
    /// <summary>Legt AValue ab und übernimmt den Besitz; ein vorhandener Wert wird freigegeben.</summary>
    procedure Put(const AKey: string; AValue: TObject);
    /// <summary>Gibt alle Werte frei (bricht Referenzzyklen über kopierte Kontexte).</summary>
    procedure Clear;
  end;

  /// <summary>Projekte der Gruppe (Atlas.Common.Projects.Contract.Group) unter den Namen der Regeln.</summary>
  TRuleApplicationKind = Atlas.Common.Projects.Contract.Group.TApplicationKind;
  TRuleProjectKind = Atlas.Common.Projects.Contract.Group.TGroupProjectKind;
  TRuleProject = Atlas.Common.Projects.Contract.Group.TGroupProject;
  TRuleNameAnswer = Atlas.Common.Projects.Contract.Group.TNameAnswer;
  TRuleUsesStep = Atlas.Common.Projects.Contract.Group.TGroupUsesStep;
  TRuleUsesEdge = Atlas.Common.Projects.Contract.Group.TGroupUsesEdge;
  TRuleUsesDerive = Atlas.Common.Projects.Contract.Group.TGroupUsesDerive;
  IRuleProjectFiles = Atlas.Common.Projects.Contract.Group.IProjectGroupFiles;
  TRuleNamingKind = Atlas.Common.Projects.Contract.Group.TProjectNamingKind;
  TRuleNaming = Atlas.Common.Projects.Contract.Group.TProjectNaming;

  /// <summary>Alles, was eine Regel über die geprüfte Datei wissen darf.</summary>
  TRuleContext = record
    /// <summary>Pfad relativ zum Ordner der Konfiguration, '' wenn unbekannt.</summary>
    RelativePath: string;
    UnitName: string;
    Text: string;
    /// <summary>Syntaxbaum des Textes; gehört dem Aufrufer.</summary>
    Tree: TSyntaxTree;
    /// <summary>Optionen der Regel aus atlas.json als JSON-Text, sonst ''.</summary>
    Options: string;
    /// <summary>Symbolindex für Vorfahren aus anderen Units (#125); nil ohne Index (--no-index).
    /// Regeln treffen dann keine Aussage, die ihn bräuchte.</summary>
    Index: ISymbolIndex;
    /// <summary>Units bedarfsweise nachladen (Namensauflösung, #178); nil = nur der vorhandene Index.</summary>
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Namespaces des Projekts für Unit-Namen ohne Präfix; leer ohne Projekt.</summary>
    Namespaces: TArray<string>;
    /// <summary>Inhalt der Formulardatei (.dfm/.fmx) neben der Unit (#123); '' ohne.</summary>
    FormText: string;
    /// <summary>Pfad der Formulardatei aus FormText (#309); '' ohne. Korrekturen in der Formulardatei
    /// gibt es nur damit.</summary>
    FormFile: string;
    /// <summary>Eingestellte Delphi-Version (BDS-Nummer, #109); '' = unbekannt. Setzt TRuleEngine.Run
    /// aus den Einstellungen, wenn der Aufrufer sie nicht angibt.</summary>
    DelphiVersion: string;
    /// <summary>Dateien relativ zum Ordner der Unit lesen (#114); nil = keine Dateien, die Regel schweigt.</summary>
    ReadFile: TRuleFileReader;
    /// <summary>Gibt es eine Datei relativ zum Ordner der Unit (#1379)? nil = unbekannt, die Regel schweigt.
    /// </summary>
    FileExists: TRuleFileExists;
    /// <summary>Eigenschaftsregeln für Formulardateien aus atlas.json (#309); setzt TRuleEngine.Run.</summary>
    DfmPropertyRules: TArray<TDfmPropertyRule>;
    /// <summary>Keine Aktionen, die Deklaration und Rumpf angleichen (refactoring.syncSignatures aus, #100);
    /// setzt TRuleEngine.Run.</summary>
    NoSignatureSync: Boolean;
    /// <summary>Forward-Deklarationen nicht prüfen (refactoring.forwardDeclaration aus, #685);
    /// setzt TRuleEngine.Run.</summary>
    NoForwardDeclaration: Boolean;
    /// <summary>Nicht freigegebene Felder nicht melden (refactoring.freeFields aus, #666); setzt TRuleEngine.Run.
    /// </summary>
    NoFreeFields: Boolean;
    /// <summary>Freigabe als FreeAndNil(FFeld) statt FFeld.Free (refactoring.freeFieldsStyle, #666).</summary>
    FreeFieldsFreeAndNil: Boolean;
    /// <summary>Methoden ohne Self nicht melden (refactoring.methodKind aus, #686); setzt TRuleEngine.Run.
    /// </summary>
    NoMethodKind: Boolean;
    /// <summary>class-Methoden als static anlegen (refactoring.methodKindStatic, #686); setzt TRuleEngine.Run.
    /// </summary>
    MethodKindStatic: Boolean;
    /// <summary>Triviale Zugriffsmethoden melden (refactoring.inlineAccessor und inlineAccessorDiagnostic, #717);
    /// setzt TRuleEngine.Run.</summary>
    InlineAccessorDiagnostic: Boolean;
    /// <summary>Setter mit Gleichheitsprüfung nicht als trivial zählen (refactoring.inlineAccessorEqualityCheck
    /// aus, #717).</summary>
    NoAccessorEqualityCheck: Boolean;
    /// <summary>Zugriffsmethoden im protected-Abschnitt anlegen (completion.accessorSection, #467, für #1001).
    /// </summary>
    AccessorsProtected: Boolean;
    /// <summary>Abbruch zwischen den Regeln, damit ein veralteter Lauf nicht zu Ende rechnet; nil = nie abbrechen.
    /// </summary>
    Cancelled: TRuleCancelled;
    /// <summary>Gemeinsame Ableitungen des Laufs; setzt TRuleEngine.Run. nil = jede Regel
    /// rechnet selbst (direkter Aufruf von Check). Zugriff nur über TRuleDerived. Die Werte zeigen in
    /// Tree: Wer einen eigenen Cache setzt, muss ihn vor dem Baum freigeben oder leeren.</summary>
    Derived: IRuleDerivedCache;
    /// <summary>Unit-Index von Tree, einmal je Lauf ausgewertet und von allen Namensauflösern geteilt (#1322); setzt
    /// TRuleEngine.Run. Regeln geben ihn an TNameResolver.Create weiter. nil = jeder Resolver wertet selbst aus.
    /// Wer einen eigenen setzt, ruft Clear, bevor er den Baum freigibt.</summary>
    TreeUnits: ITreeUnits;
    /// <summary>Absoluter Pfad der geprüften Datei; '' wenn unbekannt (#46).</summary>
    FileName: string;
    /// <summary>Inhalt der Packages aus requires (#46); nil = unbekannt, Package-Prüfungen schweigen.</summary>
    PackageProvides: TRulePackageProvides;
    /// <summary>requires eines Packages: dcc sieht auch die Units der Packages, die ein requires-Package
    /// verlangt (Atlas.Windows → Atlas.Common → Atlas.Text); nil = nur die direkten.</summary>
    PackageRequires: TRulePackageRequires;
    /// <summary>Antworten zum Index über alle Units des Arbeitsbereichs (TIndexNameFacts); nil = je Unit neu.
    /// </summary>
    NameFacts: IIndexNameFacts;
    /// <summary>Unit-Suche wie beim Compiler (#1016); nil = unbekannt (Linter, Datei ohne Projekt).</summary>
    Units: IRuleUnitLookup;
    /// <summary>Anwendungsart des Projekts, zu dem die Datei gehört (#926); Unknown ohne Projekt.</summary>
    Application: TRuleApplicationKind;
    /// <summary>Name des Projekts ohne Endung, z. B. Atlas.IDE.Expert (#943); '' ohne Projekt.</summary>
    ProjectName: string;
    /// <summary>Variablen der automatisch erzeugten Formulare und Datenmodule in der Reihenfolge der
    /// Application.CreateForm-Aufrufe der .dpr (#956); nil ohne Projekt.</summary>
    AutoCreateForms: TArray<string>;
    /// <summary>Absoluter Pfad der .dpr, aus der AutoCreateForms stammt (#1055); '' ohne. Korrekturen in der
    /// .dpr gibt es nur damit; gelesen wird sie über ReadFile.</summary>
    ProjectMainSource: string;
    /// <summary>Formatierung aus den Einstellungen (format, #938): Tabbreite und Einrückung für Regeln, die
    /// Spalten zählen oder umbrechen; setzt TRuleEngine.Run. IndentSize 0 = nicht gesetzt.</summary>
    Formatting: TFormatStyle;
    /// <summary>Klassenvervollständigung (classCompletion, #1834) für die Korrektur fehlender Rümpfe; setzt
    /// TRuleEngine.Run. TypeComment '' = nicht gesetzt, es gelten die Vorgaben.</summary>
    ClassCompletion: TClassCompletionSettings;
    /// <summary>Projekte der Gruppe für projektweite Regeln (#1102); nil = unbekannt, diese Regeln schweigen.
    /// </summary>
    ProjectFiles: IRuleProjectFiles;
    /// <summary>Präfixe der Projektdatei .atlas aus dem Projektkontext der IDE (#1111); ohne IDE (Linter) leer.
    /// </summary>
    Naming: TRuleNaming;
    /// <summary>Präfixe für Namen, die Korrekturen neu bilden (Konstante einführen, Hilfsvariable …): die der
    /// Namensregel, wenn sie für die Datei läuft, sonst keine (TRuleEngine.NewNames).</summary>
    NewNames: TPascalNamePrefixes;
    /// <summary>Attribute und Namensmuster, deren Elemente als verwendet gelten (deadCode.keepAttributes und
    /// deadCode.keepPatterns, #64); setzt TRuleEngine.Run. Regeln für ungenutzten Code nehmen sie zu ihren
    /// eigenen Optionen dazu.</summary>
    KeepAttributes: TArray<string>;
    KeepPatterns: TArray<string>;
    /// <summary>Prüfung für den Editor (#896): Diagnosen, Code-Aktionen und Baseline des Servers. Projektweite
    /// Läufe (--check, find_unused_code) lassen es aus. Setzt der Aufrufer.</summary>
    Live: Boolean;
    /// <summary>diagnostics.usesCycleLive aus (#896): uses-cycle schweigt mit Live; setzt TRuleEngine.Run.
    /// </summary>
    NoUsesCycleLive: Boolean;
    /// <summary>diagnostics.usesCycleImplementation (#896): mit Live auch Zyklen mit implementation-Kante, als
    /// Hinweis; setzt TRuleEngine.Run.</summary>
    UsesCycleImplementation: Boolean;
    /// <summary>sortUses (#284): Korrekturen, die uses-Listen ändern, sortieren wie „uses aufräumen“; setzt
    /// TRuleEngine.Run.</summary>
    SortUses: Boolean;
    SortUsesByNamespace: Boolean;
    /// <summary>usesKeep (#621): Units, die unused-uses nie meldet; setzt TRuleEngine.Run.</summary>
    UsesKeep: TArray<string>;
    /// <summary>Inaktive Zweige der bedingten Kompilierung in Text (#1352), z. B. für unused-uses; setzt
    /// TFileChecker.CheckText. nil = keine bekannt.</summary>
    InactiveRanges: TArray<TTextRange>;
    /// <summary>Warnungen der .dproj (aktive Konfiguration und Plattform) als "Bezeichner=Wert", z. B.
    /// "SYMBOL_PLATFORM=false", "UNSAFE_CODE=true", "WARNINGS=false" (#1378); leer ohne Projekt. Regeln lesen sie
    /// über TRuleWarnSwitches.</summary>
    ProjectWarnings: TArray<string>;
    /// <summary>Code-Abfragen des Arbeitsbereichs (#1351) für die Regeln query:&lt;name&gt;; nil = keine, gespeicherte
    /// Abfragen mit failIfAny laufen dann nicht.</summary>
    Queries: ICodeQueries;
    /// <summary>Typen der laufenden IDE ohne Quelltext (ICheckIdeTypes); nil = ohne IDE.</summary>
    IdeTypes: ICheckIdeTypes;
    /// <summary>Refactorings für Korrekturen (TCheckRefactorings); je Eintrag nil = diese Korrektur nicht anbieten.</summary>
    Refactorings: TCheckRefactorings;
    /// <summary>Dateiname für die Namensauflösung (TNameResolver): FileName, sonst RelativePath, sonst
    /// UnitName mit ".pas".</summary>
    function ResolverFileName: string;
    /// <summary>Trägt die Dienste des Projekts (Index, Unit-Suche, IDE-Typen, Refactorings …) ein.</summary>
    procedure UseServices(const AServices: TCheckServices);
  end;

  /// <summary>Sammelt die Treffer einer Regel. Ohne Angabe gilt Konfidenz High.</summary>
  IRuleReport = interface
    ['{6E0D7E61-0B7B-4C4A-9C7F-3B0E5B6E2A11}']
    procedure Add(const ARange: TTextRange; const AMessage: string); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>); overload;
    /// <summary>Treffer mit eigenem Schweregrad aus der Konfiguration der Regel (#309);
    /// TRuleSeverity.Default = Schweregrad der Regel.</summary>
    procedure AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>);
    /// <summary>Treffer mit Zusatz für den Befund-Hover (TRuleFinding.Details, #1102).</summary>
    procedure AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>);
  end;

  /// <summary>Erweiterung des Reports der Engine (#896): Treffer mit Schweregrad, Zusatz und weiteren Stellen
  /// zugleich. Regeln fragen sie mit Supports ab; ohne sie (Test-Doubles) melden sie über IRuleReport ohne die
  /// weiteren Stellen.</summary>
  IRuleRelatedReport = interface
    ['{9D2E4B71-3C58-4A06-B7F1-5E8A2C6D0F94}']
    /// <summary>TRuleSeverity.Default = Schweregrad der Regel; Off meldet nichts.</summary>
    procedure AddRelated(const ARange: TTextRange; const AMessage, ADetails: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>; const ARelated: TArray<TRuleRelated>);
  end;

  IRule = interface
    ['{2C4A1F3E-8D5B-4E7A-A1C2-7F9E0B3D4C55}']
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Regel, die vorgibt, wie neue Namen heißen (naming-prefix): Korrekturen und Refactorings übernehmen
  /// ihre Präfixe, damit sie keine Namen erzeugen, die die Regel gleich wieder meldet.</summary>
  IRuleNewNames = interface
    ['{3F9C2B71-5D84-4A6E-B1C7-8E2D40A95F13}']
    /// <summary>Präfixe neuer Namen; AContext trägt die Optionen dieser Regel.</summary>
    function NewNames(const AContext: TRuleContext): TPascalNamePrefixes;
  end;

  /// <summary>Regel, die je Datei entscheidet, ob sie prüfen kann (#1135), z. B. unused-uses nicht im Editor und
  /// nicht ohne Index. Prüft sie nicht, zählt sie nicht als gelaufen: Ein lsp-ignore für sie ist dann nicht
  /// unused-suppression (dessen sichere Korrektur entfernte den Kommentar sonst beim Speichern).</summary>
  IRuleCondition = interface
    ['{8E3B5C17-2A94-4D6F-B0E8-51C7F92A3D60}']
    /// <summary>False: Die Regel prüft AContext nicht. AContext trägt die Optionen dieser Regel.</summary>
    function Applies(const AContext: TRuleContext): Boolean;
  end;

  /// <summary>Regel, die einzelne Stellen mangels Wissen nicht entscheiden kann, z. B. inline-not-expanded bei
  /// einer Routine, die der Index nicht kennt (RTL unter Linux). Ein lsp-ignore für sie in einer solchen Zeile
  /// gilt nicht als unused-suppression: Mit vollständigem Index meldete die Regel dort womöglich etwas.</summary>
  IRuleLineCertainty = interface
    ['{D81A25A9-CD8F-4412-9468-DAFFB794F2A7}']
    /// <summary>False: Die Regel konnte die Zeile ALine (ab 0; -1 = ganze Datei) nicht sicher prüfen. AContext ist
    /// der Kontext ihres Laufs.</summary>
    function Decides(const AContext: TRuleContext; ALine: Integer): Boolean;
  end;

  /// <summary>Regel, die nach allen anderen die rohen Treffer sieht (vor Unterdrückung und Konfidenzfilter),
  /// z. B. /ignore ohne Treffer in der Zeile darunter (#297).</summary>
  IRuleAfterFindings = interface
    ['{6B1E9D3A-47C2-4F8B-9E05-A3D27C81F4B6}']
    /// <summary>AFindings: Treffer aller Regeln dieses Laufs; ARanIds: Kennungen der gelaufenen Regeln (klein).
    /// </summary>
    procedure CheckFindings(const AContext: TRuleContext; const AFindings: TArray<TRuleFinding>;
      const ARanIds: TArray<string>; const AReport: IRuleReport);
  end;

/// <summary>Sicherheit für Regeln, die eingebundene Dateien nicht sehen: Medium, wenn die Unit {$I …} bzw.
/// {$INCLUDE …} enthält, sonst High.</summary>
function IncludeConfidence(const ATokens: TArray<TPascalToken>): TRuleConfidence;

/// <summary>Schlüssel der Projektart in Einstellungen: "application", "package", "library" oder ''.</summary>
function ProjectKindKey(AKind: TRuleProjectKind): string;

implementation

uses
  System.StrUtils;

{ TRuleContext }

function TRuleContext.ResolverFileName: string;
begin
  Result := FileName;
  if Result = '' then
  begin
    Result := RelativePath;
  end;
  if Result = '' then
  begin
    Result := UnitName + '.pas';
  end;
end;

function ProjectKindKey(AKind: TRuleProjectKind): string;
begin
  case AKind of
    TRuleProjectKind.Application:
      Result := 'application';
    TRuleProjectKind.Package:
      Result := 'package';
    TRuleProjectKind.Library_:
      Result := 'library';
  else
    Result := '';
  end;
end;

function IncludeConfidence(const ATokens: TArray<TPascalToken>): TRuleConfidence;
var
  mToken: TPascalToken;
begin
  Result := TRuleConfidence.High;
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', mToken.Text) or
      StartsText('{$INCLUDE ', mToken.Text)) then
    begin
      Exit(TRuleConfidence.Medium);
    end;
  end;
end;

procedure TRuleContext.UseServices(const AServices: TCheckServices);
begin
  Index := AServices.Index;
  EnsureUnit := AServices.EnsureUnit;
  Namespaces := AServices.Namespaces;
  Units := AServices.Units;
  PackageProvides := AServices.PackageProvides;
  PackageRequires := AServices.PackageRequires;
  NameFacts := AServices.NameFacts;
  ProjectFiles := AServices.ProjectFiles;
  Naming := AServices.Naming;
  ProjectWarnings := AServices.ProjectWarnings;
  Queries := AServices.Queries;
  IdeTypes := AServices.IdeTypes;
  Refactorings := AServices.Refactorings;
end;

{ TRuleDescriptor }

constructor TRuleDescriptor.Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string);
begin
  Id := AId;
  DefaultSeverity := ADefaultSeverity;
  Description := ADescription;
end;

end.
