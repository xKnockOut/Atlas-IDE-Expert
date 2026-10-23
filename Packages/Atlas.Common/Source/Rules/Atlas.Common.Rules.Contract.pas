unit Atlas.Common.Rules.Contract;

// Gemeinsame Grundlage aller Prüfregeln: Beschreibung, Kontext einer Prüfung,
// Treffer mit optionalen Korrekturen und die Schnittstelle einer Regel.
// Regeln melden lieber zu wenig als zu viel (Spezifikation, Abschnitt 11).
// Jeder Treffer trägt eine Konfidenz; sie begrenzt den Schweregrad (#144).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  // Genehmigte Ausnahme der Rollenmatrix (Architektur.md, "Genehmigte Ausnahmen"): der Syntaxbaum ist
  // Datengrundlage jeder Regel und hängt selbst nur an Contracts.
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Feste Angaben einer Regel.</summary>
  TRuleDescriptor = record
    /// <summary>Kennung in Kleinbuchstaben mit Bindestrich, z. B. "empty-except".</summary>
    Id: string;
    /// <summary>Schweregrad ohne Konfiguration; nie Default.</summary>
    DefaultSeverity: TRuleSeverity;
    Description: string;
    /// <summary>
    /// Ohne gemessene Fehlalarmquote: läuft nur, wenn die Regel in
    /// atlas.json unter "rules" eingeschaltet ist.
    /// </summary>
    Experimental: Boolean;
    constructor Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string;
      AExperimental: Boolean = False);
  end;

  /// <summary>Eine Textersetzung einer Korrektur. Alias auf TTextEdit aus Documents.Contract,
  /// damit Editing die Textänderung ohne Abhängigkeit von Rules nutzen kann (A-11).</summary>
  TRuleEdit = TTextEdit;

  /// <summary>Edits einer weiteren Datei einer Korrektur (#1105).</summary>
  TRuleFileEdits = record
    FileName: string;
    Edits: TArray<TRuleEdit>;
  end;

  /// <summary>Code-Aktion zu einem Treffer.</summary>
  TRuleFix = record
    Title: string;
    Edits: TArray<TRuleEdit>;
    /// <summary>Sicher ohne Rückfrage anwendbar, z. B. beim Speichern über source.fixAll (#182).
    /// Jede Regel entscheidet das für ihre Korrekturen selbst.</summary>
    Safe: Boolean;
    /// <summary>Eine von mehreren gleichwertigen Korrekturen (#125): keine wird als bevorzugt angeboten.</summary>
    Alternative: Boolean;
    /// <summary>Datei, die die Edits ändern, z. B. die Formulardatei neben der Unit (#309);
    /// '' = die geprüfte Datei.</summary>
    FileName: string;
    /// <summary>Sprung statt Änderung (#915): der Client setzt den Cursor auf JumpTo in der geprüften Datei,
    /// z. B. zur Freigabe bei use-after-free. Edits bleiben leer.</summary>
    HasJump: Boolean;
    JumpTo: TTextPosition;
    /// <summary>Nach dem Sprung öffnet der Client den Parameter-Hint an JumpTo (#1007).</summary>
    OpensSignature: Boolean;
    /// <summary>Edits in weiteren Dateien zusätzlich zu FileName, z. B. Verwendungen eines öffentlichen Felds in
    /// anderen Units (#1105); nil = keine. Solche Korrekturen sind nie Safe.</summary>
    OtherFiles: TArray<TRuleFileEdits>;
    constructor Create(const ATitle: string; const AEdits: TArray<TRuleEdit>; ASafe: Boolean = False);
    /// <summary>Aktion, die nur zu ATarget springt (#915).</summary>
    class function Jump(const ATitle: string; const ATarget: TTextPosition): TRuleFix; static;
    /// <summary>Aktion, die zu ATarget (in den Klammern eines Aufrufs) springt und dort den Parameter-Hint öffnet
    /// (#1007).</summary>
    class function SignatureHelp(const ATitle: string; const ATarget: TTextPosition): TRuleFix; static;
  end;

  /// <summary>Ein Treffer einer Regel. Severity setzt die Engine.</summary>
  TRuleFinding = record
    RuleId: string;
    Range: TTextRange;
    Message: string;
    Severity: TRuleSeverity;
    Confidence: TRuleConfidence;
    Fixes: TArray<TRuleFix>;
    /// <summary>Zusatz für den Befund-Hover, z. B. der durchsuchte Bereich (#1102); '' ohne.</summary>
    Details: string;
  end;

  /// <summary>Liest eine Datei neben der Unit, z. B. die .dcr aus {$R *.dcr} (#114).</summary>
  TRuleFileReader = reference to function(const AFileName: string; out AData: TBytes): Boolean;
  /// <summary>Gehört eine Unit zu einem Package (#46)? Unknown, wenn das Package nicht gefunden wird.</summary>
{$SCOPEDENUMS ON}
  TRulePackageAnswer = (No, Yes, Unknown);
{$SCOPEDENUMS OFF}
  /// <summary>Gehört AUnitName zu Package APackage (aus requires)? Über dessen .dpk bzw. .dcp (#46).</summary>
  TRulePackageProvides = reference to function(const APackage, AUnitName: string): TRulePackageAnswer;
  /// <summary>Antwort der Unit-Suche (#1016): gefunden, sicher nicht gefunden oder ohne Aussage (Pfade der
  /// Installation unbekannt, Makro in einem Pfad offen, Inhalt eines Packages unbekannt).</summary>
{$SCOPEDENUMS ON}
  TRuleUnitAnswer = (Found, Missing, Unknown);
  /// <summary>Wo gesucht wird (#1016): wie der Compiler (Projekt, Suchpfade der .dproj, Bibliothek) bzw. was
  /// Atlas kennt (Index, Quellpfade der Installation).</summary>
  TRuleUnitSource = (Project, Atlas);
{$SCOPEDENUMS OFF}
  TRuleUnitSources = set of TRuleUnitSource;

  /// <summary>Unit-Suche wie beim Compiler für uses-unit-not-found (#1016); nil = unbekannt, die Regel
  /// schweigt bis auf Prüfungen ohne Pfade.</summary>
  IRuleUnitLookup = interface
    ['{7866E50C-6086-4876-A359-8193140A05BD}']
    /// <summary>Findet der Compiler AUnitName, verwendet in AFromFile (absolut)? AInPath ist der Text aus
    /// "in '…'" ('' ohne); dann zählt nur diese Datei.</summary>
    function Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
    /// <summary>Package aus requires als .dpk oder .dcp (E2202).</summary>
    function FindPackage(const APackage: string): TRuleUnitAnswer;
    /// <summary>Namen aller Units, die die Suche findet, für Vorschläge.</summary>
    function KnownUnits(ASources: TRuleUnitSources): TArray<string>;
    /// <summary>Ordner unter dem Projektordner, der AUnitName.pas enthält, aber in keinem Suchpfad steht;
    /// relativ zur .dproj, '' ohne.</summary>
    function FolderOutsidePaths(const AUnitName: string): string;
    /// <summary>Pfad und Text der .dproj; False ohne Projekt.</summary>
    function ReadProject(out AFileName, AText: string): Boolean;
  end;

  /// <summary>True, wenn die Prüfung abgebrochen werden soll (Zeitlimit, Dokument geändert).</summary>
  TRuleCancelled = reference to function: Boolean;

  /// <summary>Die Prüfung wurde über TRuleContext.Cancelled abgebrochen; es gibt kein Ergebnis.</summary>
  ERuleCheckCancelled = class(Exception);

  /// <summary>Ableitungen einer Prüfung, die alle Regeln eines Laufs teilen (Review P-03).
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

  /// <summary>Art der Anwendung, zu der die Datei gehört (#926): mit oder ohne Konsole, Package (#943),
  /// Windows-Dienst und DLL ohne Formulare (#1060). Eine DLL mit Formularen ist Unknown.</summary>
{$SCOPEDENUMS ON}
  TRuleApplicationKind = (Unknown, Console, Gui, Package, Service, Library_);
{$SCOPEDENUMS OFF}

  /// <summary>Art eines Projekts für projektweite Regeln (#1102): Anwendung (program), Package (.dpk) oder DLL
  /// (library).</summary>
{$SCOPEDENUMS ON}
  TRuleProjectKind = (Unknown, Application, Package, Library_);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Projekt der Projektgruppe mit seinen Quelltexten und Formularen (#1102).</summary>
  TRuleProject = record
    /// <summary>Projektdatei (.dproj, .dpr oder .dpk).</summary>
    FileName: string;
    Kind: TRuleProjectKind;
    /// <summary>DUnitX- oder DUnit-Testprojekt.</summary>
    IsTest: Boolean;
    /// <summary>Absolute Pfade der Units samt Hauptquelltext (.dpr/.dpk).</summary>
    Sources: TArray<string>;
    /// <summary>Absolute Pfade der Formulardateien (.dfm/.fmx) neben den Units.</summary>
    Forms: TArray<string>;
  end;

  /// <summary>Antwort auf "kommt der Name in der Datei vor?" (#1102).</summary>
{$SCOPEDENUMS ON}
  TRuleNameAnswer = (Absent, Present, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Die Projekte der Gruppe für projektweite Regeln wie unused-public-member (#1102); nil = unbekannt
  /// (Linter, Datei ohne Projekt), die Regeln schweigen.</summary>
  IRuleProjectFiles = interface
    ['{3F0B6C1D-9A47-4E2B-8D15-6C7A2E94B0F3}']
    /// <summary>Sind alle Projekte geladen und indiziert? Sonst nennt AReason den Grund ("Index läuft (180 von
    /// 214 Units)"), und projektweite Regeln schweigen.</summary>
    function Complete(out AReason: string): Boolean;
    /// <summary>Projekte, zu denen AFileName gehört, zuerst; mit AWholeGroup danach alle übrigen der Gruppe.
    /// </summary>
    function ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TRuleProject>;
    /// <summary>Kommt AName als Bezeichner in AFileName vor (ohne Groß-/Kleinschreibung)? Unknown, wenn die
    /// Datei nicht gelesen werden kann.</summary>
    function NameIn(const AFileName, AName: string): TRuleNameAnswer;
    /// <summary>Text der Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

  /// <summary>Art eines Namens mit Präfix-Vorgabe (#1111).</summary>
{$SCOPEDENUMS ON}
  TRuleNamingKind = (Local, Field, Parameter, Constant);
{$SCOPEDENUMS OFF}

  /// <summary>Präfix-Vorgaben der Projektdatei .atlas (naming, #452, #1111); Known = gesetzt, auch leer (= ohne
  /// Präfix).</summary>
  TRuleNaming = record
    Prefixes: array[TRuleNamingKind] of string;
    Known: array[TRuleNamingKind] of Boolean;
  end;

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
    /// <summary>Zugriffsmethoden im protected-Abschnitt anlegen (completion.accessorSection, #467, für #1001).
    /// </summary>
    AccessorsProtected: Boolean;
    /// <summary>Abbruch zwischen den Regeln (Diagnoselog 15.10.2026); nil = nie abbrechen.</summary>
    Cancelled: TRuleCancelled;
    /// <summary>Gemeinsame Ableitungen des Laufs (Review P-03); setzt TRuleEngine.Run. nil = jede Regel
    /// rechnet selbst (direkter Aufruf von Check). Zugriff nur über TRuleDerived. Die Werte zeigen in
    /// Tree: Wer einen eigenen Cache setzt, muss ihn vor dem Baum freigeben oder leeren.</summary>
    Derived: IRuleDerivedCache;
    /// <summary>Absoluter Pfad der geprüften Datei; '' wenn unbekannt (#46).</summary>
    FileName: string;
    /// <summary>Inhalt der Packages aus requires (#46); nil = unbekannt, Package-Prüfungen schweigen.</summary>
    PackageProvides: TRulePackageProvides;
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
    /// <summary>Projekte der Gruppe für projektweite Regeln (#1102); nil = unbekannt, diese Regeln schweigen.
    /// </summary>
    ProjectFiles: IRuleProjectFiles;
    /// <summary>Präfixe der Projektdatei .atlas aus dem Projektkontext der IDE (#1111); ohne IDE (Linter) leer.
    /// </summary>
    Naming: TRuleNaming;
  end;

  /// <summary>Dienste des Projekts für die Regeln (#1112): Symbolindex, Nachladen von Units, Unit-Suche,
  /// Packages, Projekte der Gruppe und Namenskonvention. Ein Weg für LSP-Server, MCP und Linter: Der
  /// Arbeitsbereich liefert sie (TShellWorkspace.RuleServices), ApplyTo trägt sie in den Regelkontext ein.
  /// Default = ohne Index; Regeln, die ihn brauchen, schweigen dann.</summary>
  TRuleServices = record
    /// <summary>Symbolindex für Typen aus anderen Units und der RTL (#125); nil = keiner.</summary>
    Index: ISymbolIndex;
    /// <summary>Units bedarfsweise nachladen (Namensauflösung, #178); nil = nur der vorhandene Index.</summary>
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Namespaces des Projekts für Unit-Namen ohne Präfix; leer ohne Projekt.</summary>
    Namespaces: TArray<string>;
    /// <summary>Unit-Suche wie beim Compiler (#1016); nil = unbekannt.</summary>
    Units: IRuleUnitLookup;
    /// <summary>Inhalt der Packages aus requires (#46); nil = unbekannt.</summary>
    PackageProvides: TRulePackageProvides;
    /// <summary>Projekte der Gruppe für projektweite Regeln (#1102); nil = unbekannt.</summary>
    ProjectFiles: IRuleProjectFiles;
    /// <summary>Präfixe der Projektdatei .atlas (#1111); leer = unbekannt.</summary>
    Naming: TRuleNaming;
    /// <summary>Trägt die Dienste in AContext ein.</summary>
    procedure ApplyTo(var AContext: TRuleContext);
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

  IRule = interface
    ['{2C4A1F3E-8D5B-4E7A-A1C2-7F9E0B3D4C55}']
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
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

/// <summary>Kennwort der Konfidenz: "hoch", "mittel", "niedrig".</summary>
function ConfidenceText(AConfidence: TRuleConfidence): string;
/// <summary>
///   Kennung der Konfidenz für Maschinen: "high", "medium", "low". Steht als
///   eigenes Feld neben der Meldung (LSP data.confidence, JSON, SARIF), nie im
///   Meldungstext (#144).
/// </summary>
function ConfidenceName(AConfidence: TRuleConfidence): string;

implementation

function ConfidenceText(AConfidence: TRuleConfidence): string;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Result := 'niedrig';
    TRuleConfidence.Medium:
      Result := 'mittel';
  else
    Result := 'hoch';
  end;
end;

function ConfidenceName(AConfidence: TRuleConfidence): string;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Result := 'low';
    TRuleConfidence.Medium:
      Result := 'medium';
  else
    Result := 'high';
  end;
end;

{ TRuleServices }

procedure TRuleServices.ApplyTo(var AContext: TRuleContext);
begin
  AContext.Index := Index;
  AContext.EnsureUnit := EnsureUnit;
  AContext.Namespaces := Namespaces;
  AContext.Units := Units;
  AContext.PackageProvides := PackageProvides;
  AContext.ProjectFiles := ProjectFiles;
  AContext.Naming := Naming;
end;

{ TRuleDescriptor }

constructor TRuleDescriptor.Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string;
  AExperimental: Boolean);
begin
  Id := AId;
  DefaultSeverity := ADefaultSeverity;
  Description := ADescription;
  Experimental := AExperimental;
end;

{ TRuleFix }

constructor TRuleFix.Create(const ATitle: string; const AEdits: TArray<TRuleEdit>; ASafe: Boolean);
begin
  Title := ATitle;
  Edits := AEdits;
  Safe := ASafe;
  Alternative := False;
  FileName := '';
  HasJump := False;
  JumpTo := Default(TTextPosition);
  // Ein Record-Konstruktor setzt nichts von selbst; ohne diese Zeilen trüge ein Sprung zufällig den
  // Parameter-Hint (#1007) oder Edits fremder Dateien (#1105).
  OpensSignature := False;
  OtherFiles := nil;
end;

class function TRuleFix.Jump(const ATitle: string; const ATarget: TTextPosition): TRuleFix;
begin
  Result := TRuleFix.Create(ATitle, nil);
  Result.HasJump := True;
  Result.JumpTo := ATarget;
end;

class function TRuleFix.SignatureHelp(const ATitle: string; const ATarget: TTextPosition): TRuleFix;
begin
  Result := Jump(ATitle, ATarget);
  Result.OpensSignature := True;
end;

end.
