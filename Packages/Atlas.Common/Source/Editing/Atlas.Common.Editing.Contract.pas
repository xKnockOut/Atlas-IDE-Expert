unit Atlas.Common.Editing.Contract;

// Gemeinsame Typen des Features Editing (#1450): Umgebung der uses-Aktionen
// (#284) und alles, was die Schnellbefehle mit "/" (#293) untereinander
// austauschen. Die Befehls-Units (*Commands) binden nur diese Unit ein, das
// Register in Atlas.Common.Editing.SlashCommands bindet die Befehls-Units ein;
// so entsteht kein Unit-Zyklus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract;

type

  /// <summary>Was der Index über eine Unit weiß.</summary>
  TUsesUnitInfo = record
    Known: Boolean;
    HasInitialization: Boolean;
    /// <summary>Namen der interface-Symbole, auch Mitglieder.</summary>
    Names: TArray<string>;
  end;

  TUsesUnitInfoFunc = reference to function(const AUnitName: string): TUsesUnitInfo;

  /// <summary>Units, deren interface ein Symbol AName auf Unit-Ebene deklariert.</summary>
  TUnitsDeclaringFunc = reference to function(const AName: string): TArray<string>;

  /// <summary>Alles, was die uses-Aktionen für ein Dokument brauchen.</summary>
  TUsesContext = record
    Info: TUsesUnitInfoFunc;
    Declaring: TUnitsDeclaringFunc;
    /// <summary>Einstellung "usesKeep".</summary>
    Keep: TArray<string>;
    /// <summary>Unit-Namespaces des Projekts (System für SysUtils).</summary>
    Namespaces: TArray<string>;
  end;

  /// <summary>Datei, die ein Befehl neu anlegt oder ganz ersetzt (/unit, #297).</summary>
  TSlashFile = record
    FileName: string;
    Text: string;
    /// <summary>Neu anlegen; sonst den ganzen Inhalt der vorhandenen Datei ersetzen.</summary>
    New: Boolean;
    class function Create(const AFileName, AText: string; ANew: Boolean): TSlashFile; static;
  end;

  /// <summary>Testunit zur Unit einer Datei (/test, #295), wie sie die Code-Aktion aus #274 findet.</summary>
  TSlashTestUnit = record
    /// <summary>Name der Testunit, z. B. Kunden.Tests.</summary>
    UnitName: string;
    /// <summary>Datei der Testunit: die vorhandene oder die neu anzulegende.</summary>
    FileName: string;
    /// <summary>Die Testunit gibt es schon.</summary>
    Exists: Boolean;
    /// <summary>Testprogramm (.dpr), in das eine neue Testunit eingetragen wird.</summary>
    TestProgram: string;
    /// <summary>Warum es keine Testunit gibt und keine angelegt wird; sonst ''.</summary>
    Reason: string;
  end;

  /// <summary>Ein Regeltreffer für /fix und /explain (#300).</summary>
  TSlashFinding = record
    RuleId: string;
    Message: string;
    /// <summary>Name, Beschreibung und Beispiel falsch/richtig aus dem Regelkatalog; '' ohne Eintrag.</summary>
    Explanation: string;
    /// <summary>Edits der sicheren Korrektur im Dokument (#145, #182); nil ohne.</summary>
    SafeFix: TArray<TTextEdit>;
  end;

  /// <summary>Zugriff auf Projekt und Editor für Befehle, die mehr als die Datei ändern (#301).</summary>
  ISlashHost = interface
    ['{8E4A2C61-3B7D-4F95-A0C8-5D1E9F27B364}']
    /// <summary>Geladenes Projekt zur Datei AUri; False ohne Projekt.</summary>
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    /// <summary>Schreibt die .dproj in ihrer Kodierung zurück und lädt das Projekt neu.</summary>
    procedure WriteProject(const AUri, AText: string);
    /// <summary>Wechselt Konfiguration bzw. Plattform ('' = unverändert) wie der Befehl aus #46.</summary>
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    /// <summary>Öffnet AFileName im Editor und markiert ASelection (window/showDocument).</summary>
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
    /// <summary>Vorlage für /header (#306): slashCommands.headerTemplate, sonst die der Regel file-header;
    /// '' ohne.</summary>
    function HeaderTemplate(const AUri: string): string;
    /// <summary>Legt AFiles in einem Schritt an bzw. ersetzt sie (über den Editor, sonst auf der Platte),
    /// lädt das Projekt zu AUri neu und öffnet danach AShow ('' = nichts).</summary>
    procedure WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
    /// <summary>Einstellung slashCommands.AName zur Datei AUri (Namen in TSlashSettings); '' ohne.</summary>
    function Setting(const AUri, AName: string): string;
    /// <summary>Testunit zur Unit AUri mit Text AText (/test, #295); False mit ATarget.Reason.</summary>
    function TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
    /// <summary>Zeigt AMessage als Hinweis im Editor (window/showMessage), nachdem die Änderungen des Befehls
    /// angekommen sind (/task, #322).</summary>
    procedure Notify(const AUri, AMessage: string);
    /// <summary>Setzt den Cursor in AUri auf APosition (im Text nach den Änderungen des Befehls), nachdem sie
    /// angekommen sind (/future, #322).</summary>
    procedure MoveCursor(const AUri: string; const APosition: TTextPosition);
    /// <summary>Kennungen der Prüfregeln, die in Zeile ALine (ab 0) von AText treffen (/ignore, #297); False,
    /// wenn für die Datei keine Prüfregeln laufen (dann gilt jede Kennung).</summary>
    function RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
    /// <summary>Index und usesKeep für ungenutzte uses (/sortuses, #297); False ohne Index.</summary>
    function UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
    /// <summary>Treffer der Prüfregeln in Zeile ALine (ab 0) von AText (/fix, /explain, #300), ohne
    /// slash-command; False, wenn für die Datei keine Prüfregeln laufen.</summary>
    function FindingsAt(const AUri, AText: string; ALine: Integer; out AFindings: TArray<TSlashFinding>): Boolean;
  end;

  /// <summary>Namen der Einstellungen, die Befehle über ISlashHost.Setting lesen.</summary>
  TSlashSettings = record
  public const
    /// <summary>Protokollaufruf für /log, /except und /measure (#304); '' = OutputDebugString.</summary>
    LogCall = 'logCall';
    /// <summary>Palettenseite für /component (#299).</summary>
    ComponentPalette = 'componentPalette';
    DefaultPalette = 'Eigene';
    /// <summary>completion.interfaceSection (#466) für /intf: private, protected oder public.</summary>
    InterfaceSection = 'interfaceSection';
    /// <summary>Name hinter -o für /todo (#297); '' = git config user.name.</summary>
    TodoOwner = 'todoOwner';
    /// <summary>Kategorie hinter -c für /todo (#297); '' = keine.</summary>
    TodoCategory = 'todoCategory';
    /// <summary>/sortuses streicht ungenutzte Units (#297, #284); 'false' = nur sortieren.</summary>
    SortUsesRemoveUnused = 'sortUsesRemoveUnused';
    /// <summary>/helper für Aufzählungen mit cNames, ToString und FromString (#875); 'false' = leerer
    /// Helper.</summary>
    EnumHelper = 'enumHelper';
    /// <summary>/helper für Mengen mit Contains, ToText, Toggle und All (#875); 'false' = leerer Helper.</summary>
    SetHelper = 'setHelper';
  end;

  /// <summary>Ort und Inhalt der Befehlszeile.</summary>
  TSlashContext = record
    /// <summary>Ganzer Text der Datei, Befehlszeile noch enthalten.</summary>
    Text: string;
    /// <summary>Zeile des Befehls ab 0.</summary>
    Line: Integer;
    /// <summary>Ganze Befehlszeile.</summary>
    LineText: string;
    Name: string;
    /// <summary>Text nach dem Namen, ohne führende und folgende Leerzeichen.</summary>
    Arguments: string;
    Namespaces: TArray<string>;
    /// <summary>Symbolindex für Vorfahren und Interfaces aus anderen Units (#295); nil ohne.</summary>
    Index: ISymbolIndex;
    /// <summary>Eingestellte Delphi-Version (BDS-Nummer, #109); '' = unbekannt, alles erlaubt.</summary>
    DelphiVersion: string;
    /// <summary>Formatstil der Datei (#43); die Einrückung der Änderungen setzt Reindent danach um.</summary>
    Style: TFormatStyle;
    /// <summary>URI der Datei; '' ohne.</summary>
    Uri: string;
    /// <summary>Projekt und Editor; nil ohne (z. B. bei der Prüfung stehen gebliebener Zeilen).</summary>
    Host: ISlashHost;
    /// <summary>Aktionen, die erst nach erfolgreichem Befehl laufen (Defer); bei Hinweisen verworfen. nil, wenn
    /// nichts ausgeführt werden soll.</summary>
    Actions: TList<TProc>;
    /// <summary>Umschließen nur bis vor diese Zeile (Markierung im Erzeugen-Menü, #719); 0 = bis zum Ende des
    /// umgebenden Blocks.</summary>
    WrapUntil: Integer;
    /// <summary>Merkt AAction für nach dem Befehl vor; ohne Actions ohne Wirkung.</summary>
    procedure Defer(const AAction: TProc);
  end;

  /// <summary>Führt den Befehl aus. False mit AReason, wenn er hier nicht passt.</summary>
  TSlashExecute = reference to function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
    out AReason: string): Boolean;

  TSlashCommand = record
    Name: string;
    Summary: string;
    Example: string;
    Execute: TSlashExecute;
  end;

  /// <summary>Trägt einen Befehl ins Register ein; so melden die Befehls-Units ihre Befehle, ohne das Register
  /// selbst einzubinden (#1450).</summary>
  TSlashRegister = reference to procedure(const ACommand: TSlashCommand);

  /// <summary>Schnellbefehle für AUri: False = alle aus; ADisabled = abgeschaltete Namen ohne "/".</summary>
  TSlashCommandsProvider = reference to function(const AUri: string; out ADisabled: TArray<string>): Boolean;
  /// <summary>Wie ISlashHost.RuleIdsAt, für die Vervollständigung nach /ignore (#297).</summary>
  TSlashRuleIdsFunc = reference to function(const AUri, AText: string; ALine: Integer;
    out AIds: TArray<string>): Boolean;
  /// <summary>Wie ISlashHost.UsesContext (/sortuses, #297).</summary>
  TSlashUsesContextFunc = reference to function(const AUri: string; out AContext: TUsesContext): Boolean;
  /// <summary>Wie ISlashHost.FindingsAt (/fix, /explain, #300).</summary>
  TSlashFindingsFunc = reference to function(const AUri, AText: string; ALine: Integer;
    out AFindings: TArray<TSlashFinding>): Boolean;

  /// <summary>Hinweis zu einer Befehlszeile, die stehen bleibt.</summary>
  TSlashProblem = record
    Range: TTextRange;
    Message: string;
  end;

implementation

{ TSlashContext }

procedure TSlashContext.Defer(const AAction: TProc);
begin
  if Actions <> nil then
    Actions.Add(AAction);
end;

{ TSlashFile }

class function TSlashFile.Create(const AFileName, AText: string; ANew: Boolean): TSlashFile;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.New := ANew;
end;

end.
