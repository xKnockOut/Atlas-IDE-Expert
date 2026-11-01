unit Atlas.UI.Tracker.SettingsSection;

// Abschnitt „Issue-Tracker“ des Moduls Tracker im Optionsdialog (#1455, ADR
// 0017 Entscheidung 3; vorher Teil von Atlas.UI.Settings.Page). Die Seite von
// Base baut ihn über IAtlasSettingsSectionHost in den Bereich „issues“:
// - Schalter, Zahlen, Textzeilen und Auswahlen hängen an ihrem Schlüssel
//   (issues.*); sie liest und schreibt die Seite selbst.
// - Eigene Zeilen: Verbindungen (#1260), Zuordnung der Projekte (#1261),
//   Abfragen (#1262, Dialog Atlas.UI.Tracker.QueryDialog), Zustand im Tracker
//   mit Klapplisten (#1266) und Textbausteine (#1278). Ihre Werte liest Load
//   und schreibt Save über IAtlasSettingsValues; ungekürzt bleiben das Muster
//   des Commits und die Kommentare beim Beginnen und Beenden, die Zielzustände
//   werden geordnet.
// - Netz, Anmeldespeicher und Projekt der IDE kommen über die Haken On…; sie
//   setzt Atlas.IDE.Tracker.Settings. Ohne Haken: keine Prüfung, kein Token.
// Steuerelemente gehören einem eigenen Besitzer; Close gibt sie frei, danach
// erreicht den Abschnitt nichts mehr (Regel 3).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.QueryDialog;

type
  /// <summary>Zustand des Tokens einer Tracker-Verbindung (#1260), ohne Netz.</summary>
  TAtlasTrackerStateEvent = reference to function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus;
  /// <summary>Knopf an einer Tracker-Verbindung (#1260): Token hinterlegen, prüfen, entfernen.</summary>
  TAtlasTrackerConnectionEvent = reference to procedure(const AConnection: TAtlasTrackerConnection);
  /// <summary>„Hinzufügen …“ der Tabelle Projekte (#1261): .dproj bzw. .groupproj (AFolder False) oder Ordner
  /// wählen; False bei Abbruch.</summary>
  TAtlasTrackerBrowseEvent = reference to function(AFolder: Boolean; out APath: string): Boolean;
  /// <summary>„Bearbeiten …“ der Tabelle Abfragen (#1263): AQuery im Dialog ändern; True bei OK. ATaken: Namen der
  /// übrigen Abfragen.</summary>
  TAtlasTrackerQueryEditEvent = reference to function(var AQuery: TAtlasTrackerQuery;
    const AConnections: TArray<TAtlasTrackerConnection>; const ATaken: TArray<string>): Boolean;
  /// <summary>„Werte vom Tracker laden“ (#1266) für AConnection mit dem Zustandsfeld AStateField; das Ergebnis meldet
  /// TrackerValuesDone.</summary>
  TAtlasTrackerValuesEvent = reference to procedure(const AConnection: TAtlasTrackerConnection;
    const AStateField: string);

  TAtlasTrackerSettingsSection = class(TInterfacedObject, IAtlasSettingsSection)
  public const
    SectionOwner = 'atlas.tracker';
    SectionArea = 'issues';
  private
    /// <summary>Besitzer aller eigenen Steuerelemente; Close gibt ihn frei.</summary>
    FOwner: TComponent;
    FHost: IAtlasSettingsSectionHost;
    FClosed: Boolean;
    /// <summary>Zeilen der Seite mit den Tabellen; an ihnen hängen Felder und Knöpfe darunter (Attach).</summary>
    FConnectionsRow: TWinControl;
    FProjectsRow: TWinControl;
    FQueriesRow: TWinControl;
    FSnippetsRow: TWinControl;
    FIssuesTracker: TAtlasChoiceBox;
    FIssuesStart: TAtlasChoiceBox;
    FIssuesBranchPattern: TEdit;
    FIssuesBranchBase: TEdit;
    FIssuesCommitPattern: TEdit;
    FTrackerLogin: TCheckBox;
    FIssuesPreview: TCheckBox;
    FIssuesPreviewComments: TCheckBox;
    FIssuesCodeLinks: TCheckBox;
    FIssuesBlameLinks: TCheckBox;
    FIssuesBlameMaxRevisions: TEdit;
    // Zustand im Tracker beim Beginnen und Beenden (#1266).
    FIssuesSyncState: TCheckBox;
    FIssuesStateField: TAtlasValueBox;
    FIssuesAssigneeField: TAtlasValueBox;
    FIssuesStartState: TAtlasValueBox;
    FIssuesAssignOnStart: TCheckBox;
    FIssuesStartComment: TEdit;
    FIssuesEndStates: TEdit;
    FIssuesEndComment: TEdit;
    FIssuesLoadValues: TButton;
    FIssuesValuesNote: TLabel;
    // Zeiterfassung (#1267).
    FIssuesTimeTracking: TCheckBox;
    FIssuesIdleMinutes: TEdit;
    FIssuesTimeRounding: TEdit;
    FIssuesPreviewChecklists: TCheckBox;
    FIssuesChecklistStatus: TCheckBox;
    FIssuesPreviewLinks: TCheckBox;
    FIssuesWarnBlocked: TCheckBox;
    FIssuesBoard: TCheckBox;
    FIssuesBoardConfirmMove: TCheckBox;
    FIssuesBoardOnlyMine: TCheckBox;
    FIssuesSprintBurndown: TCheckBox;
    FIssuesSprintCompare: TCheckBox;
    FIssuesPaletteSearch: TCheckBox;
    FIssuesCommentEditor: TCheckBox;
    /// <summary>Textbausteine für Kommentare (#1278): Tabelle Name/Text, darunter die gewählte Zeile.</summary>
    FIssuesSnippets: TListView;
    FIssuesSnippetName: TEdit;
    FIssuesSnippetText: TMemo;
    FIssuesSnippetAdd: TButton;
    FIssuesSnippetRemove: TButton;
    FIssuesSnippetDefaults: TButton;
    FCommentSnippets: TArray<TAtlasCommentSnippet>;
    /// <summary>Gewählter Textbaustein; -1 = keiner.</summary>
    FSnippetSelected: Integer;
    /// <summary>Die Seite füllt die Felder selbst: OnChange übernimmt nichts.</summary>
    FSnippetFilling: Boolean;
    FIssuesPreviewDevelopment: TCheckBox;
    FIssuesNotify: TCheckBox;
    FIssuesNotifyInterval: TEdit;
    FIssuesNotifyScope: TAtlasChoiceBox;
    FIssuesAttach: TCheckBox;
    FIssuesAttachLogFiles: TEdit;
    FIssuesAttachMaxImageWidth: TEdit;
    // Tracker-Verbindungen (#1260): Tabelle, Felder der gewählten Zeile, Knöpfe.
    FIssuesConnections: TListView;
    FIssuesConnectionName: TEdit;
    FIssuesConnectionProvider: TAtlasChoiceBox;
    FIssuesConnectionUrl: TEdit;
    FIssuesConnectionNote: TLabel;
    FIssuesConnectionAdd: TButton;
    FIssuesConnectionRemove: TButton;
    FIssuesConnectionToken: TButton;
    FIssuesConnectionCheck: TButton;
    // Werte der gewählten Verbindung für Zustand und Zuständigkeit (#1266); leer = globale Einstellung.
    FIssuesConnectionStateField: TAtlasValueBox;
    FIssuesConnectionAssigneeField: TAtlasValueBox;
    FIssuesConnectionStartState: TAtlasValueBox;
    FIssuesConnectionEndStates: TEdit;
    // Zeilen von Zustandsfeld und Benutzerfeld: nur bei Anbietern mit Feldern sichtbar (YouTrack, nicht GitHub).
    FIssuesConnectionStateRow: TWinControl;
    FIssuesConnectionAssigneeRow: TWinControl;
    FOnTrackerValues: TAtlasTrackerValuesEvent;
    /// <summary>Persönliche Verbindungen, wie die Seite sie zeigt; gespeichert werden die mit Adresse.</summary>
    FTrackerConnections: TArray<TAtlasTrackerConnection>;
    /// <summary>Verbindung aus der .atlas des aktiven Projekts (schreibgeschützt), hinter den persönlichen.</summary>
    FTrackerTeam: TArray<TAtlasTrackerConnection>;
    FTrackerProviderNames: TArray<string>;
    FTrackerProviderCaptions: TArray<string>;
    /// <summary>Server (CredentialTarget), deren Prüfung läuft.</summary>
    FTrackerChecking: TArray<string>;
    /// <summary>Gewählte Zeile; -1 = keine.</summary>
    FTrackerSelected: Integer;
    /// <summary>Die Seite füllt die Felder selbst: OnChange übernimmt nichts.</summary>
    FTrackerFilling: Boolean;
    FOnTrackerState: TAtlasTrackerStateEvent;
    FOnTrackerToken: TAtlasTrackerConnectionEvent;
    FOnTrackerCheck: TAtlasTrackerConnectionEvent;
    FOnTrackerRemove: TAtlasTrackerConnectionEvent;
    FOnTrackerTeam: TFunc<TArray<TAtlasTrackerConnection>>;
    // Zuordnung Delphi-Projekt → Tracker-Projekt (#1261): Tabelle, Felder der gewählten Zeile, Knöpfe.
    FIssuesProjects: TListView;
    FIssuesProjectMatch: TEdit;
    FIssuesProjectConnection: TAtlasChoiceBox;
    FIssuesProjectProject: TEdit;
    FIssuesProjectNote: TLabel;
    FIssuesProjectAddCurrent: TButton;
    FIssuesProjectAdd: TButton;
    FIssuesProjectRemove: TButton;
    FIssuesProjectAddMenu: TPopupMenu;
    /// <summary>Persönliche Zeilen, wie die Seite sie zeigt; gespeichert werden die mit Pfad und Verbindung.
    /// </summary>
    FTrackerProjects: TArray<TAtlasTrackerProjectMapping>;
    /// <summary>Aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas (beim Aufbau der Tabelle).</summary>
    FTrackerContext: TAtlasTrackerProjectContext;
    /// <summary>Namen der Verbindungen in der Auswahl der Zeile.</summary>
    FTrackerProjectChoices: TArray<string>;
    FTrackerProjectSelected: Integer;
    FTrackerProjectFilling: Boolean;
    FOnTrackerContext: TFunc<TAtlasTrackerProjectContext>;
    FOnTrackerBrowse: TAtlasTrackerBrowseEvent;
    // Benannte Abfragen (#1262).
    FIssuesQueries: TListView;
    FIssuesQueryName: TEdit;
    FIssuesQueryText: TEdit;
    FIssuesQueryConnection: TAtlasChoiceBox;
    FIssuesQueryProject: TEdit;
    FIssuesQueryNote: TLabel;
    FIssuesQueryAdd: TButton;
    FIssuesQueryRemove: TButton;
    FIssuesQueryEdit: TButton;
    FOnTrackerQueryTest: TAtlasQueryTestEvent;
    FOnTrackerQueryEdit: TAtlasTrackerQueryEditEvent;
    FIssuesQueryPicker: TCheckBox;
    FIssuesCreate: TCheckBox;
    FIssuesCreateIncludeCode: TCheckBox;
    /// <summary>Zeilen, wie die Seite sie zeigt; gespeichert werden die mit Name und Abfrage.</summary>
    FTrackerQueries: TArray<TAtlasTrackerQuery>;
    FTrackerQuerySelected: Integer;
    FTrackerQueryFilling: Boolean;
    function AddPanel(AHeight: Integer): TWinControl;
    function AddKeyedPanel(AHeight: Integer; const AKey: string): TWinControl;
    procedure AddTitle(const ACaption: string);
    function AddCheck(const AKey, ACaption: string): TCheckBox;
    function AddNumber(const AKey, ACaption: string): TEdit;
    function AddTextLine(const AKey, ACaption: string): TEdit;
    function AddChoice(const AKey, ACaption: string; const ACaptions, AValues: TArray<string>): TAtlasChoiceBox;
    procedure Attach(ARow, AAnchor: TControl);
    procedure Allow(AControl: TControl; AValue: Boolean);
    function ListReady(AControl: TWinControl): Boolean;
    procedure Changed;
    procedure AddIssuesSection;
    procedure AddIssuesTimeSection;
    function AddLabelled(const ACaption: string; AControl: TWinControl; AHeight: Integer): TWinControl;
    procedure AddIssuesSnippetsSection;
    procedure RefreshSnippets;
    procedure SnippetFillFields;
    procedure SnippetSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure SnippetNameChange(Sender: TObject);
    procedure SnippetTextChange(Sender: TObject);
    procedure SnippetAddClick(Sender: TObject);
    procedure SnippetRemoveClick(Sender: TObject);
    procedure SnippetDefaultsClick(Sender: TObject);
    procedure AddIssuesWorkflowSection;
    function AddValueBox(const AKey, ACaption: string): TAtlasValueBox;
    procedure AddTrackerConnectionsSection;
    function AddTrackerLabelled(const ACaption: string; AControl: TWinControl; AWidth: Integer): TWinControl;
    function AddTrackerButton(AParent: TWinControl; ALeft, AWidth: Integer; const ACaption: string;
      AClick: TNotifyEvent): TButton;
    procedure AddTrackerColumn(AList: TListView; const ACaption: string; AWidth: Integer);
    procedure AddTrackerHint(const ACaption: string; AAnchor: TControl);
    function TrackerRows: TArray<TAtlasTrackerConnection>;
    function TrackerProviderCaption(const AName: string): string;
    function TrackerStateText(const AConnection: TAtlasTrackerConnection): string;
    function TrackerEditable: Boolean;
    procedure TrackerFillFields;
    procedure TrackerShowFields;
    procedure TrackerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure TrackerNameChange(Sender: TObject);
    procedure TrackerProviderChange(Sender: TObject);
    procedure TrackerUrlChange(Sender: TObject);
    procedure TrackerAddClick(Sender: TObject);
    procedure TrackerRemoveClick(Sender: TObject);
    procedure TrackerTokenClick(Sender: TObject);
    procedure TrackerCheckClick(Sender: TObject);
    procedure AddTrackerProjectsSection;
    function TrackerProjectRows: TArray<TAtlasTrackerProjectMapping>;
    function TrackerProjectEditable: Boolean;
    function TrackerProjectCovered(const AMapping: TAtlasTrackerProjectMapping): Boolean;
    function TrackerProjectSourceText(const AMapping: TAtlasTrackerProjectMapping): string;
    procedure TrackerProjectNoteFor(const AMapping: TAtlasTrackerProjectMapping);
    procedure TrackerProjectFillFields;
    procedure TrackerProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure TrackerProjectDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure TrackerProjectMatchChange(Sender: TObject);
    procedure TrackerProjectConnectionChange(Sender: TObject);
    procedure TrackerProjectProjectChange(Sender: TObject);
    procedure TrackerProjectAdd(const AMatch: string);
    procedure TrackerProjectAddCurrentClick(Sender: TObject);
    procedure TrackerProjectAddClick(Sender: TObject);
    function TrackerBrowse(AFolder: Boolean; out APath: string): Boolean;
    procedure TrackerProjectAddFileClick(Sender: TObject);
    procedure TrackerProjectAddFolderClick(Sender: TObject);
    procedure TrackerProjectRemoveClick(Sender: TObject);
    procedure AddTrackerQueriesSection;
    function TrackerQueryEditable: Boolean;
    function TrackerQueryConnectionChoice(const AConnection: string): Integer;
    procedure TrackerQueryNoteFor(const AQuery: TAtlasTrackerQuery);
    procedure TrackerQueryFillFields;
    procedure TrackerQuerySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure TrackerQueryRowChanged;
    procedure TrackerQueryNameChange(Sender: TObject);
    procedure TrackerQueryTextChange(Sender: TObject);
    procedure TrackerQueryConnectionChange(Sender: TObject);
    procedure TrackerQueryProjectChange(Sender: TObject);
    procedure TrackerQueryAddClick(Sender: TObject);
    procedure TrackerQueryRemoveClick(Sender: TObject);
    procedure TrackerQueryEditClick(Sender: TObject);
    procedure TrackerWorkflowChange(Sender: TObject);
    function TrackerValuesConnection(out AConnection: TAtlasTrackerConnection): Boolean;
    procedure TrackerLoadValuesClick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasSettingsSection }
    function OwnerId: string;
    function AreaId: string;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    procedure WindowReady;
    function Show(const AKey, AArgument: string): Boolean;
    procedure Close;
    /// <summary>Nach Close: Die Seite ist zu oder das Modul gegangen; späte Antworten verfallen.</summary>
    property Closed: Boolean read FClosed;
    /// <summary>Anbieter der Auswahl (Name wie in issues.connections, Anzeigename); Vorgabe YouTrack und GitHub.
    /// </summary>
    procedure SetTrackerProviders(const ANames, ACaptions: TArray<string>);
    /// <summary>Tabelle der Verbindungen neu aufbauen (Zustand, .atlas); ohne Fenster folgt es in WindowReady.
    /// </summary>
    procedure RefreshTrackerConnections;
    /// <summary>Prüfung von AConnection ist fertig; der Zustand kommt über OnTrackerState.</summary>
    procedure TrackerCheckDone(const AConnection: TAtlasTrackerConnection);
    /// <summary>Tabelle Projekte neu aufbauen (Kontext, Verbindungen); ohne Fenster folgt es in WindowReady.
    /// </summary>
    procedure RefreshTrackerProjects;
    /// <summary>„zuordnen …“ aus „Meine Issues“ (#1261): Zeile für AMatch anlegen bzw. wählen und zeigen.</summary>
    procedure AssignTrackerProject(const AMatch: string);
    /// <summary>Tabelle Abfragen neu aufbauen; ohne Fenster folgt es in WindowReady.</summary>
    procedure RefreshTrackerQueries;
    /// <summary>Werte vom Tracker sind da (#1266): AError '' = geladen, sonst der Grund für die Zeile unter dem
    /// Knopf.</summary>
    procedure TrackerValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
    /// <summary>Gespeicherte Form der Tabellen: nur vollständige Zeilen, Namen bzw. Pfade eindeutig.</summary>
    function TrackerConnectionsJson: string;
    function TrackerProjectsJson: string;
    function TrackerQueriesJson: string;
    property IssuesTracker: TAtlasChoiceBox read FIssuesTracker;
    property IssuesQueryPicker: TCheckBox read FIssuesQueryPicker;
    property IssuesCreate: TCheckBox read FIssuesCreate;
    property IssuesCreateIncludeCode: TCheckBox read FIssuesCreateIncludeCode;
    property TrackerQueries: TArray<TAtlasTrackerQuery> read FTrackerQueries;
    property IssuesStart: TAtlasChoiceBox read FIssuesStart;
    property IssuesBranchPattern: TEdit read FIssuesBranchPattern;
    property IssuesBranchBase: TEdit read FIssuesBranchBase;
    property IssuesCommitPattern: TEdit read FIssuesCommitPattern;
    property TrackerLogin: TCheckBox read FTrackerLogin;
    property IssuesPreview: TCheckBox read FIssuesPreview;
    property IssuesPreviewComments: TCheckBox read FIssuesPreviewComments;
    property IssuesCodeLinks: TCheckBox read FIssuesCodeLinks;
    property IssuesBlameLinks: TCheckBox read FIssuesBlameLinks;
    property IssuesBlameMaxRevisions: TEdit read FIssuesBlameMaxRevisions;
    property IssuesSyncState: TCheckBox read FIssuesSyncState;
    property IssuesStateField: TAtlasValueBox read FIssuesStateField;
    property IssuesAssigneeField: TAtlasValueBox read FIssuesAssigneeField;
    property IssuesStartState: TAtlasValueBox read FIssuesStartState;
    property IssuesAssignOnStart: TCheckBox read FIssuesAssignOnStart;
    property IssuesStartComment: TEdit read FIssuesStartComment;
    property IssuesEndStates: TEdit read FIssuesEndStates;
    property IssuesEndComment: TEdit read FIssuesEndComment;
    property IssuesLoadValues: TButton read FIssuesLoadValues;
    property IssuesValuesNote: TLabel read FIssuesValuesNote;
    property IssuesTimeTracking: TCheckBox read FIssuesTimeTracking;
    property IssuesIdleMinutes: TEdit read FIssuesIdleMinutes;
    property IssuesTimeRounding: TEdit read FIssuesTimeRounding;
    property IssuesConnectionStateField: TAtlasValueBox read FIssuesConnectionStateField;
    property IssuesConnectionAssigneeField: TAtlasValueBox read FIssuesConnectionAssigneeField;
    property IssuesConnectionStartState: TAtlasValueBox read FIssuesConnectionStartState;
    property IssuesConnectionEndStates: TEdit read FIssuesConnectionEndStates;
    property IssuesConnectionStateRow: TWinControl read FIssuesConnectionStateRow;
    property IssuesConnectionAssigneeRow: TWinControl read FIssuesConnectionAssigneeRow;
    property IssuesPreviewChecklists: TCheckBox read FIssuesPreviewChecklists;
    property IssuesChecklistStatus: TCheckBox read FIssuesChecklistStatus;
    property IssuesPreviewLinks: TCheckBox read FIssuesPreviewLinks;
    property IssuesWarnBlocked: TCheckBox read FIssuesWarnBlocked;
    property IssuesBoard: TCheckBox read FIssuesBoard;
    property IssuesBoardConfirmMove: TCheckBox read FIssuesBoardConfirmMove;
    property IssuesBoardOnlyMine: TCheckBox read FIssuesBoardOnlyMine;
    property IssuesSprintBurndown: TCheckBox read FIssuesSprintBurndown;
    property IssuesSprintCompare: TCheckBox read FIssuesSprintCompare;
    property IssuesPaletteSearch: TCheckBox read FIssuesPaletteSearch;
    property IssuesPreviewDevelopment: TCheckBox read FIssuesPreviewDevelopment;
    property IssuesNotify: TCheckBox read FIssuesNotify;
    property IssuesNotifyInterval: TEdit read FIssuesNotifyInterval;
    property IssuesNotifyScope: TAtlasChoiceBox read FIssuesNotifyScope;
    property IssuesAttach: TCheckBox read FIssuesAttach;
    property IssuesAttachLogFiles: TEdit read FIssuesAttachLogFiles;
    property IssuesAttachMaxImageWidth: TEdit read FIssuesAttachMaxImageWidth;
    /// <summary>Zum Testen: Tracker-Verbindungen (#1260).</summary>
    property IssuesConnections: TListView read FIssuesConnections;
    /// <summary>Zum Testen: Kommentar-Editor und Textbausteine (#1278).</summary>
    property IssuesCommentEditor: TCheckBox read FIssuesCommentEditor;
    property IssuesSnippets: TListView read FIssuesSnippets;
    property IssuesSnippetName: TEdit read FIssuesSnippetName;
    property IssuesSnippetText: TMemo read FIssuesSnippetText;
    property IssuesSnippetAdd: TButton read FIssuesSnippetAdd;
    property IssuesSnippetRemove: TButton read FIssuesSnippetRemove;
    property IssuesSnippetDefaults: TButton read FIssuesSnippetDefaults;
    property IssuesConnectionName: TEdit read FIssuesConnectionName;
    property IssuesConnectionProvider: TAtlasChoiceBox read FIssuesConnectionProvider;
    property IssuesConnectionUrl: TEdit read FIssuesConnectionUrl;
    property IssuesConnectionNote: TLabel read FIssuesConnectionNote;
    property IssuesConnectionAdd: TButton read FIssuesConnectionAdd;
    property IssuesConnectionRemove: TButton read FIssuesConnectionRemove;
    property IssuesConnectionToken: TButton read FIssuesConnectionToken;
    property IssuesConnectionCheck: TButton read FIssuesConnectionCheck;
    /// <summary>Persönliche Verbindungen, wie die Seite sie gerade zeigt.</summary>
    property TrackerConnections: TArray<TAtlasTrackerConnection> read FTrackerConnections;
    /// <summary>Zum Testen: Zuordnung Delphi-Projekt → Tracker-Projekt (#1261).</summary>
    property IssuesProjects: TListView read FIssuesProjects;
    property IssuesProjectMatch: TEdit read FIssuesProjectMatch;
    property IssuesProjectConnection: TAtlasChoiceBox read FIssuesProjectConnection;
    property IssuesProjectProject: TEdit read FIssuesProjectProject;
    property IssuesProjectNote: TLabel read FIssuesProjectNote;
    property IssuesProjectAddCurrent: TButton read FIssuesProjectAddCurrent;
    property IssuesProjectAdd: TButton read FIssuesProjectAdd;
    property IssuesProjectRemove: TButton read FIssuesProjectRemove;
    property IssuesProjectAddMenu: TPopupMenu read FIssuesProjectAddMenu;
    /// <summary>Persönliche Zeilen, wie die Seite sie gerade zeigt.</summary>
    property TrackerProjects: TArray<TAtlasTrackerProjectMapping> read FTrackerProjects;
    /// <summary>Zum Testen: benannte Abfragen (#1262).</summary>
    property IssuesQueries: TListView read FIssuesQueries;
    property IssuesQueryName: TEdit read FIssuesQueryName;
    property IssuesQueryText: TEdit read FIssuesQueryText;
    property IssuesQueryConnection: TAtlasChoiceBox read FIssuesQueryConnection;
    property IssuesQueryProject: TEdit read FIssuesQueryProject;
    property IssuesQueryNote: TLabel read FIssuesQueryNote;
    property IssuesQueryAdd: TButton read FIssuesQueryAdd;
    property IssuesQueryRemove: TButton read FIssuesQueryRemove;
    property IssuesQueryEdit: TButton read FIssuesQueryEdit;
    /// <summary>Tracker-Verbindungen (#1260): Zustand je Server (ohne Netz); nil = „fehlt“.</summary>
    property OnTrackerState: TAtlasTrackerStateEvent read FOnTrackerState write FOnTrackerState;
    /// <summary>„Token hinterlegen …“ für die gewählte Verbindung; danach RefreshTrackerConnections.</summary>
    property OnTrackerToken: TAtlasTrackerConnectionEvent read FOnTrackerToken write FOnTrackerToken;
    /// <summary>„Verbindung prüfen“ im Hintergrund; das Ergebnis meldet TrackerCheckDone.</summary>
    property OnTrackerCheck: TAtlasTrackerConnectionEvent read FOnTrackerCheck write FOnTrackerCheck;
    /// <summary>Vor dem Entfernen einer Verbindung: fragt, ob das Token mit entfernt werden soll.</summary>
    property OnTrackerRemove: TAtlasTrackerConnectionEvent read FOnTrackerRemove write FOnTrackerRemove;
    /// <summary>„Testen“ im Dialog „Abfrage bearbeiten“ (#1263); nil = Knopf gesperrt.</summary>
    property OnTrackerQueryTest: TAtlasQueryTestEvent read FOnTrackerQueryTest write FOnTrackerQueryTest;
    /// <summary>Statt des Dialogs (Tests); nil = TAtlasTrackerQueryDialog.</summary>
    property OnTrackerQueryEdit: TAtlasTrackerQueryEditEvent read FOnTrackerQueryEdit write FOnTrackerQueryEdit;
    /// <summary>Verbindung aus der .atlas des aktiven Projekts; leer ohne.</summary>
    property OnTrackerTeam: TFunc<TArray<TAtlasTrackerConnection>> read FOnTrackerTeam write FOnTrackerTeam;
    /// <summary>„Werte vom Tracker laden“ (#1266) im Hintergrund; das Ergebnis meldet TrackerValuesDone.</summary>
    property OnTrackerValues: TAtlasTrackerValuesEvent read FOnTrackerValues write FOnTrackerValues;
    /// <summary>Tabelle Projekte (#1261): aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas; nil =
    /// ohne Projekt.</summary>
    property OnTrackerContext: TFunc<TAtlasTrackerProjectContext> read FOnTrackerContext write FOnTrackerContext;
    /// <summary>„Hinzufügen …“ (#1261); nil = Datei- bzw. Ordnerauswahl von Windows.</summary>
    property OnTrackerBrowse: TAtlasTrackerBrowseEvent read FOnTrackerBrowse write FOnTrackerBrowse;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Dialogs,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

const
  /// <summary>Linker Rand der Klapplisten im Abschnitt „Zustand im Tracker“, wie die Felder der Seite.</summary>
  FieldLeft = 280;

{ TAtlasTrackerSettingsSection }

constructor TAtlasTrackerSettingsSection.Create;
begin
  inherited Create;
  FOwner := TComponent.Create(nil);
  FTrackerSelected := -1;
  FTrackerProjectSelected := -1;
  FTrackerQuerySelected := -1;
  FSnippetSelected := -1;
  FTrackerProviderNames := TArray<string>.Create('youtrack', 'github');
  FTrackerProviderCaptions := TArray<string>.Create('YouTrack', 'GitHub');
  FTrackerContext := TAtlasTrackerProjectContext.Empty;
end;

destructor TAtlasTrackerSettingsSection.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TAtlasTrackerSettingsSection.OwnerId: string;
begin
  Result := SectionOwner;
end;

function TAtlasTrackerSettingsSection.AreaId: string;
begin
  Result := SectionArea;
end;

procedure TAtlasTrackerSettingsSection.Build(const AHost: IAtlasSettingsSectionHost);
begin
  FHost := AHost;
  AddIssuesSection;
end;

procedure TAtlasTrackerSettingsSection.Load(const AValues: IAtlasSettingsValues);
begin
  if FClosed or (FHost = nil) then
    Exit;
  // Gebundene Felder hat die Seite schon geladen; hier die eigenen Zeilen.
  FIssuesStateField.Value := AValues.ReadString('issues.stateField');
  FIssuesAssigneeField.Value := AValues.ReadString('issues.assigneeField');
  FIssuesStartState.Value := AValues.ReadString('issues.startState');
  FCommentSnippets := TAtlasCommentSnippets.Read(AValues.ReadString('issues.commentSnippets'));
  FSnippetSelected := -1;
  if Length(FCommentSnippets) > 0 then
    FSnippetSelected := 0;
  RefreshSnippets;
  FTrackerConnections := TAtlasTrackerConnections.Read(AValues.ReadString('issues.connections'));
  FTrackerSelected := -1;
  if Length(FTrackerConnections) > 0 then
    FTrackerSelected := 0;
  // Zuordnung (#1261) vor dem Aufbau: RefreshTrackerConnections baut die Tabelle Projekte mit.
  FTrackerProjects := TAtlasTrackerProjects.Read(AValues.ReadString('issues.projects'));
  FTrackerProjectSelected := -1;
  if Length(FTrackerProjects) > 0 then
    FTrackerProjectSelected := 0;
  // Ebenso die Abfragen (#1262): RefreshTrackerProjects baut sie mit.
  FTrackerQueries := TAtlasTrackerQueries.Read(AValues.ReadString('issues.queries'));
  FTrackerQuerySelected := -1;
  if Length(FTrackerQueries) > 0 then
    FTrackerQuerySelected := 0;
  RefreshTrackerConnections;
end;

procedure TAtlasTrackerSettingsSection.Save(const AValues: IAtlasSettingsValues);
begin
  if FClosed or (FHost = nil) then
    Exit;
  // Nicht gekürzt: Das Leerzeichen am Ende von "{kennung} " trennt Kennung und Nachricht; die Kommentare bleiben,
  // wie eingegeben (die Seite kürzt gebundene Textzeilen).
  AValues.WriteString('issues.commitPattern', FIssuesCommitPattern.Text);
  AValues.WriteString('issues.startComment', FIssuesStartComment.Text);
  AValues.WriteString('issues.endComment', FIssuesEndComment.Text);
  AValues.WriteString('issues.endStates',
    TAtlasTrackerWorkflow.ListText(TAtlasTrackerWorkflow.ParseList(FIssuesEndStates.Text)));
  AValues.WriteString('issues.stateField', FIssuesStateField.Value);
  AValues.WriteString('issues.assigneeField', FIssuesAssigneeField.Value);
  AValues.WriteString('issues.startState', FIssuesStartState.Value);
  AValues.WriteString('issues.commentSnippets', TAtlasCommentSnippets.ToJson(FCommentSnippets));
  AValues.WriteString('issues.connections', TrackerConnectionsJson);
  AValues.WriteString('issues.projects', TrackerProjectsJson);
  AValues.WriteString('issues.queries', TrackerQueriesJson);
end;

procedure TAtlasTrackerSettingsSection.WindowReady;
begin
  if FClosed or (FHost = nil) then
    Exit;
  RefreshTrackerConnections;
  RefreshSnippets;
end;

function TAtlasTrackerSettingsSection.Show(const AKey, AArgument: string): Boolean;
begin
  // „zuordnen …“ aus „Meine Issues“ (#1261): Zeile für das Projekt anlegen bzw. wählen.
  Result := not FClosed and (FHost <> nil) and SameText(AKey, 'issues.projects');
  if Result and (AArgument <> '') then
    AssignTrackerProject(AArgument);
end;

procedure TAtlasTrackerSettingsSection.Close;
begin
  if FClosed then
    Exit;
  FClosed := True;
  FHost := nil;
  // Die Zeilen gehören der Seite; die Elemente darin dem Abschnitt.
  FreeAndNil(FOwner);
  FOnTrackerState := nil;
  FOnTrackerToken := nil;
  FOnTrackerCheck := nil;
  FOnTrackerRemove := nil;
  FOnTrackerTeam := nil;
  FOnTrackerValues := nil;
  FOnTrackerQueryTest := nil;
  FOnTrackerQueryEdit := nil;
  FOnTrackerContext := nil;
  FOnTrackerBrowse := nil;
end;

function TAtlasTrackerSettingsSection.AddPanel(AHeight: Integer): TWinControl;
begin
  Result := FHost.AddRow(AHeight, nil);
end;

function TAtlasTrackerSettingsSection.AddKeyedPanel(AHeight: Integer; const AKey: string): TWinControl;
begin
  Result := FHost.AddRow(AHeight, TArray<string>.Create(AKey));
end;

procedure TAtlasTrackerSettingsSection.AddTitle(const ACaption: string);
begin
  FHost.AddTitle(ACaption);
end;

function TAtlasTrackerSettingsSection.AddCheck(const AKey, ACaption: string): TCheckBox;
begin
  Result := FHost.AddSwitch(AKey, ACaption) as TCheckBox;
end;

function TAtlasTrackerSettingsSection.AddNumber(const AKey, ACaption: string): TEdit;
begin
  Result := FHost.AddNumber(AKey, ACaption) as TEdit;
end;

function TAtlasTrackerSettingsSection.AddTextLine(const AKey, ACaption: string): TEdit;
begin
  Result := FHost.AddText(AKey, ACaption) as TEdit;
end;

function TAtlasTrackerSettingsSection.AddChoice(const AKey, ACaption: string;
  const ACaptions, AValues: TArray<string>): TAtlasChoiceBox;
begin
  Result := FHost.AddChoice(AKey, ACaption, ACaptions, AValues) as TAtlasChoiceBox;
end;

procedure TAtlasTrackerSettingsSection.Attach(ARow, AAnchor: TControl);
begin
  FHost.Attach(ARow, AAnchor);
end;

procedure TAtlasTrackerSettingsSection.Allow(AControl: TControl; AValue: Boolean);
begin
  if FHost <> nil then
    FHost.Allow(AControl, AValue)
  else
    AControl.Enabled := AValue;
end;

function TAtlasTrackerSettingsSection.ListReady(AControl: TWinControl): Boolean;
begin
  Result := (FHost <> nil) and FHost.ListReady(AControl);
end;

procedure TAtlasTrackerSettingsSection.Changed;
begin
  if FHost <> nil then
    FHost.Changed;
end;


function SnippetLine(const AText: string): string;
begin
  // Eine Zeile in der Tabelle; Umbrüche als „⏎“.
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #10, ' ⏎ ', [rfReplaceAll]);
end;

procedure TAtlasTrackerSettingsSection.AddIssuesSection;
begin
  // Verbindungen zuerst (#1260, Mockup IT1): Tabelle mit Token-Zustand, darunter die gewählte Zeile.
  AddTrackerConnectionsSection;
  // Danach die Zuordnung der Delphi-Projekte (#1261, Mockup IT2).
  AddTrackerProjectsSection;
  // Benannte Abfragen und Klappliste (#1262, Mockup IT3).
  AddTrackerQueriesSection;
  // Anbieter (Vorgabe aus der .atlas), „Beginnen“, Muster für Branch und Commit, Zugang (#765).
  FIssuesTracker := AddChoice('issues.tracker', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTracker),
    [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTrackerTeam), 'GitHub', 'YouTrack'], ['', 'github', 'youtrack']);
  FIssuesStart := AddChoice('issues.start', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStart),
    [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartBranch),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartRemember)],
    [TAtlasPluginSettings.IssuesStartBranch, TAtlasPluginSettings.IssuesStartRemember]);
  FIssuesBranchPattern := AddTextLine('issues.branchPattern', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesBranchPattern));
  FIssuesBranchBase := AddTextLine('issues.branchBase', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesBranchBase));
  FIssuesCommitPattern := AddTextLine('issues.commitPattern', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesCommitPattern));
  FTrackerLogin := AddCheck('issues.login', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsTrackerLogin));
  // Issue-Vorschau (#1264): Hauptschalter, Kommentare und Reiter „Entwicklung“ (#1269) darunter.
  FIssuesPreview := AddCheck('issues.preview', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesPreview));
  FIssuesPreviewComments := AddCheck('issues.preview.comments', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesPreviewComments));
  FIssuesCodeLinks := AddCheck('issues.codeLinks', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesCodeLinks));
  // Issues in der Zeilenhistorie (#1275): Schalter, darunter die Grenze für „Issues zu dieser Methode“.
  FIssuesBlameLinks := AddCheck('issues.blameLinks', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesBlameLinks));
  FIssuesBlameMaxRevisions := AddNumber('issues.blameLinks.maxRevisions', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesBlameMaxRevisions));
  // Issues in der Befehlspalette (#1270).
  FIssuesPaletteSearch := AddCheck('issues.paletteSearch', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesPaletteSearch));
  // Kommentar-Editor (#1278); die Textbausteine stehen unter den Vorlagen.
  FIssuesCommentEditor := AddCheck('issues.commentEditor', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesCommentEditor));
  AddIssuesWorkflowSection;
  AddIssuesTimeSection;
  // Checklisten (#1273): in der Vorschau unter deren Hauptschalter, das Statusfeld eigenständig.
  FIssuesPreviewChecklists := AddCheck('issues.preview.checklists', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesPreviewChecklists));
  FIssuesChecklistStatus := AddCheck('issues.checklistStatus', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesChecklistStatus));
  // Abhängigkeiten und Unteraufgaben (#1279): Baum in der Vorschau, Warnung beim Beginnen.
  FIssuesPreviewLinks := AddCheck('issues.preview.links', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesPreviewLinks));
  FIssuesWarnBlocked := AddCheck('issues.warnBlocked', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesWarnBlocked));
  // Board (#1272): Hauptschalter, Rückfrage beim Ziehen, Filter beim Öffnen.
  FIssuesBoard := AddCheck('issues.board', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesBoard));
  FIssuesBoardConfirmMove := AddCheck('issues.board.confirmMove', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesBoardConfirmMove));
  FIssuesBoardOnlyMine := AddCheck('issues.board.onlyMine', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesBoardOnlyMine));
  // Sprint-Kachel (#1277): Burndown-Linie, Vergleich mit dem Vorsprint und Velocity.
  FIssuesSprintBurndown := AddCheck('issues.sprint.burndown', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSprintBurndown));
  FIssuesSprintCompare := AddCheck('issues.sprint.compare', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSprintCompare));
  FIssuesPreviewDevelopment := AddCheck('issues.preview.development', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesPreviewDevelopment));
  // Meldungen zu meinen Issues (#1271): Hauptschalter, Abstand und Umfang darunter.
  FIssuesNotify := AddCheck('issues.notify', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotify));
  FIssuesNotifyInterval := AddNumber('issues.notify.intervalMinutes', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyInterval));
  // Reihenfolge wie TAtlasTrackerNotifyScope.
  FIssuesNotifyScope := AddChoice('issues.notify.scope', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScope),
    [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScopeAssigned),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScopeCreated),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesNotifyScopeWatched)],
    [TAtlasPluginSettings.IssuesNotifyAssigned, TAtlasPluginSettings.IssuesNotifyAssignedOrCreated,
    TAtlasPluginSettings.IssuesNotifyWatched]);
  // An Issue anhängen (#1276): Hauptschalter, Logdateien und Bildbreite darunter.
  FIssuesAttach := AddCheck('issues.attach', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesAttach));
  FIssuesAttachLogFiles := AddTextLine('issues.attach.logFiles', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesAttachLogFiles));
  FIssuesAttachMaxImageWidth := AddNumber('issues.attach.maxImageWidth', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesAttachMaxImageWidth));
end;

procedure TAtlasTrackerSettingsSection.AddIssuesTimeSection;
begin
  // Zeiterfassung (#1267): Hauptschalter, Leerlauf und Rundung (x-parent issues.timeTracking).
  AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTimeTitle));
  FIssuesTimeTracking := AddCheck('issues.timeTracking', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTimeTracking));
  FIssuesIdleMinutes := AddNumber('issues.idleMinutes', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesIdleMinutes));
  FIssuesTimeRounding := AddNumber('issues.timeRounding', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesTimeRounding));
  AddIssuesSnippetsSection;
end;

/// <summary>Zeile mit Beschriftung links und AControl rechts (Höhe AHeight); auch für die Verbindungen (#1266).
/// </summary>
function TAtlasTrackerSettingsSection.AddLabelled(const ACaption: string; AControl: TWinControl; AHeight: Integer): TWinControl;
var
  mCaption: TLabel;
begin
  Result := AddPanel(AHeight);
  mCaption := TLabel.Create(FOwner);
  mCaption.Parent := Result;
  mCaption.Caption := ACaption + ':';
  mCaption.Left := 0;
  mCaption.Top := 5;
  AControl.Parent := Result;
  AControl.Left := 90;
  AControl.Top := 1;
  AControl.Width := 376;
  AControl.Height := AHeight - 2;
  AControl.Anchors := [akLeft, akTop, akRight];
end;

procedure TAtlasTrackerSettingsSection.AddIssuesSnippetsSection;

  function AddButton(AParent: TWinControl; ALeft: Integer; const ACaption: string; AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(FOwner);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Left := ALeft;
    Result.Top := 3;
    Result.Width := 100;
    Result.OnClick := AClick;
  end;

  procedure AddColumn(const ACaption: string; AWidth: Integer);
  var
    mColumn: TListColumn;
  begin
    mColumn := FIssuesSnippets.Columns.Add;
    mColumn.Caption := ACaption;
    mColumn.Width := AWidth;
  end;

var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  FSnippetSelected := -1;
  AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetsTitle));
  FSnippetsRow := AddKeyedPanel(100, 'issues.commentSnippets');
  mPanel := FSnippetsRow;
  // Die Zeilen brauchen ein Fenster: RefreshSnippets füllt sie (auch aus WindowReady).
  FIssuesSnippets := TListView.Create(FOwner);
  FIssuesSnippets.Parent := mPanel;
  FIssuesSnippets.Align := alClient;
  FIssuesSnippets.ViewStyle := vsReport;
  FIssuesSnippets.ReadOnly := True;
  FIssuesSnippets.RowSelect := True;
  FIssuesSnippets.HideSelection := False;
  FIssuesSnippets.OnSelectItem := SnippetSelectItem;
  AddColumn(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetName), 200);
  AddColumn(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetText), 330);
  FIssuesSnippetName := TEdit.Create(FOwner);
  FIssuesSnippetName.MaxLength := TAtlasCommentSnippets.MaxName;
  FIssuesSnippetName.OnChange := SnippetNameChange;
  Attach(AddLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetName), FIssuesSnippetName, 26), FSnippetsRow);
  FIssuesSnippetText := TMemo.Create(FOwner);
  FIssuesSnippetText.MaxLength := TAtlasCommentSnippets.MaxText;
  FIssuesSnippetText.ScrollBars := ssVertical;
  FIssuesSnippetText.WantReturns := True;
  FIssuesSnippetText.OnChange := SnippetTextChange;
  Attach(AddLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetText), FIssuesSnippetText, 64), FSnippetsRow);
  mPanel := AddPanel(32);
  FIssuesSnippetAdd := AddButton(mPanel, 0, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetAdd), SnippetAddClick);
  FIssuesSnippetRemove := AddButton(mPanel, 106, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetRemove), SnippetRemoveClick);
  FIssuesSnippetDefaults := AddButton(mPanel, 212, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetDefaults), SnippetDefaultsClick);
  Attach(mPanel, FSnippetsRow);
  mPanel := AddPanel(34);
  mHint := TLabel.Create(FOwner);
  mHint.Parent := mPanel;
  mHint.Align := alClient;
  mHint.WordWrap := True;
  mHint.Font.Color := clGrayText;
  mHint.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetsHint);
  Attach(mPanel, FSnippetsRow);
end;

procedure TAtlasTrackerSettingsSection.RefreshSnippets;
var
  mSnippet: TAtlasCommentSnippet;
  mItem: TListItem;
begin
  if FClosed or (FIssuesSnippets = nil) then
    Exit;
  if FSnippetSelected > High(FCommentSnippets) then
    FSnippetSelected := High(FCommentSnippets);
  if ListReady(FIssuesSnippets) then
  begin
    FSnippetFilling := True;
    FIssuesSnippets.Items.BeginUpdate;
    try
      FIssuesSnippets.Items.Clear;
      for mSnippet in FCommentSnippets do
      begin
        mItem := FIssuesSnippets.Items.Add;
        mItem.Caption := mSnippet.Name;
        mItem.SubItems.Add(SnippetLine(mSnippet.Text));
      end;
      if FSnippetSelected >= 0 then
        FIssuesSnippets.Items[FSnippetSelected].Selected := True;
    finally
      FIssuesSnippets.Items.EndUpdate;
      FSnippetFilling := False;
    end;
  end;
  SnippetFillFields;
end;

procedure TAtlasTrackerSettingsSection.SnippetFillFields;
var
  mEditable: Boolean;
begin
  mEditable := (FSnippetSelected >= 0) and (FSnippetSelected <= High(FCommentSnippets));
  FSnippetFilling := True;
  try
    if mEditable then
    begin
      FIssuesSnippetName.Text := FCommentSnippets[FSnippetSelected].Name;
      FIssuesSnippetText.Text := AdjustLineBreaks(FCommentSnippets[FSnippetSelected].Text, tlbsCRLF);
    end
    else
    begin
      FIssuesSnippetName.Text := '';
      FIssuesSnippetText.Text := '';
    end;
  finally
    FSnippetFilling := False;
  end;
  // Über Allow: Sonst schaltet UpdateLocks (Hauptschalter) die Felder wieder frei.
  Allow(FIssuesSnippetName, mEditable);
  Allow(FIssuesSnippetText, mEditable);
  Allow(FIssuesSnippetRemove, mEditable);
  Allow(FIssuesSnippetAdd, Length(FCommentSnippets) < TAtlasCommentSnippets.MaxSnippets);
end;

procedure TAtlasTrackerSettingsSection.SnippetSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FSnippetFilling or not Selected or (Item = nil) then
    Exit;
  FSnippetSelected := Item.Index;
  SnippetFillFields;
end;

procedure TAtlasTrackerSettingsSection.SnippetNameChange(Sender: TObject);
begin
  if FSnippetFilling or (FSnippetSelected < 0) or (FSnippetSelected > High(FCommentSnippets)) then
    Exit;
  FCommentSnippets[FSnippetSelected].Name := FIssuesSnippetName.Text;
  if ListReady(FIssuesSnippets) and (FSnippetSelected < FIssuesSnippets.Items.Count) then
    FIssuesSnippets.Items[FSnippetSelected].Caption := FIssuesSnippetName.Text;
end;

procedure TAtlasTrackerSettingsSection.SnippetTextChange(Sender: TObject);
begin
  if FSnippetFilling or (FSnippetSelected < 0) or (FSnippetSelected > High(FCommentSnippets)) then
    Exit;
  // Wie im Kommentar: Zeilen mit #10.
  FCommentSnippets[FSnippetSelected].Text := StringReplace(FIssuesSnippetText.Text, #13#10, #10, [rfReplaceAll]);
  if ListReady(FIssuesSnippets) and (FSnippetSelected < FIssuesSnippets.Items.Count) and
    (FIssuesSnippets.Items[FSnippetSelected].SubItems.Count > 0) then
    FIssuesSnippets.Items[FSnippetSelected].SubItems[0] := SnippetLine(FCommentSnippets[FSnippetSelected].Text);
end;

procedure TAtlasTrackerSettingsSection.SnippetAddClick(Sender: TObject);
begin
  if Length(FCommentSnippets) >= TAtlasCommentSnippets.MaxSnippets then
    Exit;
  // Ohne Text wird der Baustein nicht gespeichert (TAtlasCommentSnippets.Parse lässt ihn fallen).
  FCommentSnippets := FCommentSnippets + [TAtlasCommentSnippet.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetNew), '')];
  FSnippetSelected := High(FCommentSnippets);
  RefreshSnippets;
  if FIssuesSnippetName.CanFocus and FIssuesSnippetName.Showing then
    FIssuesSnippetName.SetFocus;
end;

procedure TAtlasTrackerSettingsSection.SnippetRemoveClick(Sender: TObject);
begin
  if (FSnippetSelected < 0) or (FSnippetSelected > High(FCommentSnippets)) then
    Exit;
  Delete(FCommentSnippets, FSnippetSelected, 1);
  RefreshSnippets;
end;

procedure TAtlasTrackerSettingsSection.SnippetDefaultsClick(Sender: TObject);
begin
  FCommentSnippets := TAtlasCommentSnippets.Defaults;
  FSnippetSelected := 0;
  RefreshSnippets;
end;

procedure TAtlasTrackerSettingsSection.AddIssuesWorkflowSection;
var
  mPanel: TWinControl;
begin
  // Zustand im Tracker (#1266): Schalter, Felder und Zustände mit Werten vom Tracker, Vorlagen der Kommentare.
  AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesWorkflowTitle));
  FIssuesSyncState := AddCheck('issues.syncState', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSyncState));
  FIssuesStateField := AddValueBox('issues.stateField', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStateField));
  FIssuesAssigneeField := AddValueBox('issues.assigneeField', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesAssigneeField));
  FIssuesStartState := AddValueBox('issues.startState', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartState));
  FIssuesAssignOnStart := AddCheck('issues.assignOnStart', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesAssignOnStart));
  FIssuesStartComment := AddTextLine('issues.startComment', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartComment));
  FIssuesEndStates := AddTextLine('issues.endStates', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesEndStates));
  FIssuesEndComment := AddTextLine('issues.endComment', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesEndComment));
  mPanel := AddPanel(30);
  FIssuesLoadValues := TButton.Create(FOwner);
  FIssuesLoadValues.Parent := mPanel;
  FIssuesLoadValues.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesLoadValues);
  FIssuesLoadValues.Left := 0;
  FIssuesLoadValues.Top := 3;
  FIssuesLoadValues.Width := 180;
  FIssuesLoadValues.OnClick := TrackerLoadValuesClick;
  FIssuesValuesNote := TLabel.Create(FOwner);
  FIssuesValuesNote.Parent := mPanel;
  FIssuesValuesNote.Left := 190;
  FIssuesValuesNote.Top := 7;
  FIssuesValuesNote.Font.Color := clGrayText;
  FIssuesValuesNote.Caption := '';
end;

function TAtlasTrackerSettingsSection.AddValueBox(const AKey, ACaption: string): TAtlasValueBox;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddKeyedPanel(26, AKey);
  mCaption := TLabel.Create(FOwner);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  Result := TAtlasValueBox.Create(FOwner);
  Result.Parent := mPanel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 180;
end;

procedure TAtlasTrackerSettingsSection.AddTrackerConnectionsSection;
var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnections));
  FConnectionsRow := AddKeyedPanel(110, 'issues.connections');
  mPanel := FConnectionsRow;
  // Die Zeilen brauchen ein Fenster: RefreshTrackerConnections füllt sie (auch aus WindowReady).
  FIssuesConnections := TListView.Create(FOwner);
  FIssuesConnections.Parent := mPanel;
  FIssuesConnections.Align := alClient;
  FIssuesConnections.ViewStyle := vsReport;
  FIssuesConnections.ReadOnly := True;
  FIssuesConnections.RowSelect := True;
  FIssuesConnections.HideSelection := False;
  FIssuesConnections.OnSelectItem := TrackerSelectItem;
  AddTrackerColumn(FIssuesConnections, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionName), 110);
  AddTrackerColumn(FIssuesConnections, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionProvider), 80);
  AddTrackerColumn(FIssuesConnections, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrl), 200);
  AddTrackerColumn(FIssuesConnections, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionToken), 170);
  FIssuesConnectionName := TEdit.Create(FOwner);
  FIssuesConnectionName.OnChange := TrackerNameChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionName), FIssuesConnectionName, 180),
    FConnectionsRow);
  FIssuesConnectionProvider := TAtlasChoiceBox.Create(FOwner);
  FIssuesConnectionProvider.SetChoices(FTrackerProviderCaptions);
  FIssuesConnectionProvider.OnChange := TrackerProviderChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionProvider), FIssuesConnectionProvider, 180),
    FConnectionsRow);
  FIssuesConnectionUrl := TEdit.Create(FOwner);
  FIssuesConnectionUrl.OnChange := TrackerUrlChange;
  mPanel := AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrl), FIssuesConnectionUrl, 376);
  FIssuesConnectionUrl.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FConnectionsRow);
  // Grund, warum eine Eingabe nicht übernommen wird (nur https, Name vergeben …).
  mPanel := AddPanel(18);
  FIssuesConnectionNote := TLabel.Create(FOwner);
  FIssuesConnectionNote.Parent := mPanel;
  FIssuesConnectionNote.Left := 90;
  FIssuesConnectionNote.Top := 1;
  FIssuesConnectionNote.Font.Color := clRed;
  Attach(mPanel, FConnectionsRow);
  // Zustand und Zuständigkeit je Verbindung (#1266); leer gilt „Zustand im Tracker“ weiter unten. Einzeilig wie
  // Name und Adresse: AddLabelled nimmt eine Höhe, 180 bzw. 376 waren als Breite gemeint (Leerraum).
  FIssuesConnectionStateField := TAtlasValueBox.Create(FOwner);
  FIssuesConnectionStateField.OnChange := TrackerWorkflowChange;
  FIssuesConnectionStateRow := AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionStateField),
    FIssuesConnectionStateField, 180);
  Attach(FIssuesConnectionStateRow, FConnectionsRow);
  FIssuesConnectionAssigneeField := TAtlasValueBox.Create(FOwner);
  FIssuesConnectionAssigneeField.OnChange := TrackerWorkflowChange;
  FIssuesConnectionAssigneeRow := AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionAssigneeField),
    FIssuesConnectionAssigneeField, 180);
  Attach(FIssuesConnectionAssigneeRow, FConnectionsRow);
  FIssuesConnectionStartState := TAtlasValueBox.Create(FOwner);
  FIssuesConnectionStartState.OnChange := TrackerWorkflowChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionStartState), FIssuesConnectionStartState, 180),
    FConnectionsRow);
  FIssuesConnectionEndStates := TEdit.Create(FOwner);
  FIssuesConnectionEndStates.OnChange := TrackerWorkflowChange;
  mPanel := AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionEndStates), FIssuesConnectionEndStates, 376);
  FIssuesConnectionEndStates.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FConnectionsRow);
  mPanel := AddPanel(18);
  mHint := TLabel.Create(FOwner);
  mHint.Parent := mPanel;
  mHint.Left := 90;
  mHint.Top := 1;
  mHint.Font.Color := clGrayText;
  mHint.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionStatesHint);
  Attach(mPanel, FConnectionsRow);
  mPanel := AddPanel(32);
  FIssuesConnectionAdd := AddTrackerButton(mPanel, 0, 100, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionAdd),
    TrackerAddClick);
  FIssuesConnectionRemove := AddTrackerButton(mPanel, 106, 100, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionRemove),
    TrackerRemoveClick);
  FIssuesConnectionToken := AddTrackerButton(mPanel, 212, 140, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionEnterToken),
    TrackerTokenClick);
  FIssuesConnectionCheck := AddTrackerButton(mPanel, 358, 140, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionCheck),
    TrackerCheckClick);
  Attach(mPanel, FConnectionsRow);
  AddTrackerHint(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionsHint), FConnectionsRow);
end;

function TAtlasTrackerSettingsSection.AddTrackerLabelled(const ACaption: string; AControl: TWinControl;
  AWidth: Integer): TWinControl;
var
  mCaption: TLabel;
begin
  Result := AddPanel(26);
  mCaption := TLabel.Create(FOwner);
  mCaption.Parent := Result;
  mCaption.Caption := ACaption + ':';
  mCaption.Left := 0;
  mCaption.Top := 5;
  AControl.Parent := Result;
  AControl.Left := 90;
  AControl.Top := 1;
  AControl.Width := AWidth;
end;

function TAtlasTrackerSettingsSection.AddTrackerButton(AParent: TWinControl; ALeft, AWidth: Integer; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(FOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := 3;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

procedure TAtlasTrackerSettingsSection.AddTrackerColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := AWidth;
end;

procedure TAtlasTrackerSettingsSection.AddTrackerHint(const ACaption: string; AAnchor: TControl);
var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  mPanel := AddPanel(34);
  mHint := TLabel.Create(FOwner);
  mHint.Parent := mPanel;
  mHint.Align := alClient;
  mHint.WordWrap := True;
  mHint.Font.Color := clGrayText;
  mHint.Caption := ACaption;
  Attach(mPanel, AAnchor);
end;

procedure TAtlasTrackerSettingsSection.SetTrackerProviders(const ANames, ACaptions: TArray<string>);
begin
  if FClosed or (Length(ANames) = 0) or (Length(ANames) <> Length(ACaptions)) then
    Exit;
  FTrackerProviderNames := ANames;
  FTrackerProviderCaptions := ACaptions;
  // Vor Build (aus CreateSection) übernimmt der Aufbau die Auswahl.
  if FIssuesConnectionProvider <> nil then
    FIssuesConnectionProvider.SetChoices(ACaptions);
  RefreshTrackerConnections;
end;

function TAtlasTrackerSettingsSection.TrackerRows: TArray<TAtlasTrackerConnection>;
begin
  Result := FTrackerConnections + FTrackerTeam;
end;

function TAtlasTrackerSettingsSection.TrackerProviderCaption(const AName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Min(High(FTrackerProviderNames), High(FTrackerProviderCaptions)) do
    if SameText(FTrackerProviderNames[mIndex], AName) then
      Exit(FTrackerProviderCaptions[mIndex]);
  Result := AName;
end;

function TAtlasTrackerSettingsSection.TrackerStateText(const AConnection: TAtlasTrackerConnection): string;
var
  mStatus: TAtlasTrackerTokenStatus;
begin
  if MatchText(AConnection.Target.CredentialTarget, FTrackerChecking) then
    Exit(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenChecking));
  mStatus := TAtlasTrackerTokenStatus.Stored(False);
  if Assigned(FOnTrackerState) and (AConnection.Target.Server <> '') then
    mStatus := FOnTrackerState(AConnection);
  case mStatus.State of
    TAtlasTrackerTokenState.Saved:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenSaved);
    TAtlasTrackerTokenState.Verified:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenVerified, [FormatDateTime('hh:nn', mStatus.CheckedAt)]);
    TAtlasTrackerTokenState.Rejected:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenRejected);
    TAtlasTrackerTokenState.Unreachable:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenUnreachable);
    TAtlasTrackerTokenState.Unexpected:
      if mStatus.HttpStatus > 0 then
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenUnexpectedStatus, [mStatus.HttpStatus])
      else
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenUnexpected);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenMissing);
  end;
end;

function TAtlasTrackerSettingsSection.TrackerEditable: Boolean;
begin
  Result := (FTrackerSelected >= 0) and (FTrackerSelected < Length(FTrackerConnections));
end;

procedure TAtlasTrackerSettingsSection.RefreshTrackerConnections;
var
  mRows: TArray<TAtlasTrackerConnection>;
  mRow: TAtlasTrackerConnection;
  mItem: TListItem;
begin
  if FClosed or (FIssuesConnections = nil) then
    Exit;
  FTrackerTeam := nil;
  if Assigned(FOnTrackerTeam) then
    FTrackerTeam := FOnTrackerTeam();
  mRows := TrackerRows;
  if FTrackerSelected > High(mRows) then
    FTrackerSelected := High(mRows);
  // Wie die Liste der Favoriten: ohne Fenster folgt das in CreateWnd.
  if ListReady(FIssuesConnections) then
  begin
    FTrackerFilling := True;
    FIssuesConnections.Items.BeginUpdate;
    try
      FIssuesConnections.Items.Clear;
      for mRow in mRows do
      begin
        mItem := FIssuesConnections.Items.Add;
        if mRow.ReadOnly then
          mItem.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesConnectionTeam, [mRow.Name])
        else
          mItem.Caption := mRow.Name;
        mItem.SubItems.Add(TrackerProviderCaption(mRow.Provider));
        mItem.SubItems.Add(mRow.Url);
        mItem.SubItems.Add(TrackerStateText(mRow));
      end;
      if FTrackerSelected >= 0 then
        FIssuesConnections.Items[FTrackerSelected].Selected := True;
    finally
      FIssuesConnections.Items.EndUpdate;
      FTrackerFilling := False;
    end;
  end;
  TrackerFillFields;
  // Die Auswahl der Verbindung in der Tabelle Projekte folgt den Verbindungen.
  RefreshTrackerProjects;
end;

procedure TAtlasTrackerSettingsSection.TrackerFillFields;
var
  mRows: TArray<TAtlasTrackerConnection>;
  mRow: TAtlasTrackerConnection;
  mIndex: Integer;
  mSelected, mEditable, mHasUrl: Boolean;
begin
  mRows := TrackerRows;
  mSelected := (FTrackerSelected >= 0) and (FTrackerSelected <= High(mRows));
  mEditable := TrackerEditable;
  FTrackerFilling := True;
  try
    if mSelected then
    begin
      mRow := mRows[FTrackerSelected];
      FIssuesConnectionName.Text := mRow.Name;
      FIssuesConnectionUrl.Text := mRow.Url;
      FIssuesConnectionProvider.Choice := -1;
      for mIndex := 0 to High(FTrackerProviderNames) do
        if SameText(FTrackerProviderNames[mIndex], mRow.Provider) then
          FIssuesConnectionProvider.Choice := mIndex;
      // Zustand und Zuständigkeit je Verbindung (#1266).
      FIssuesConnectionStateField.Value := mRow.StateField;
      FIssuesConnectionAssigneeField.Value := mRow.AssigneeField;
      FIssuesConnectionStartState.Value := mRow.StartState;
      FIssuesConnectionEndStates.Text := TAtlasTrackerWorkflow.ListText(mRow.EndStates);
    end
    else
    begin
      FIssuesConnectionName.Text := '';
      FIssuesConnectionUrl.Text := '';
      FIssuesConnectionProvider.Choice := -1;
      FIssuesConnectionStateField.Value := '';
      FIssuesConnectionAssigneeField.Value := '';
      FIssuesConnectionStartState.Value := '';
      FIssuesConnectionEndStates.Text := '';
    end;
  finally
    FTrackerFilling := False;
  end;
  mHasUrl := mSelected and (mRows[FTrackerSelected].Url <> '');
  if mSelected and not mEditable then
    FIssuesConnectionNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionReadOnly)
  else if mEditable and not mHasUrl then
    FIssuesConnectionNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlEmpty)
  else
    FIssuesConnectionNote.Caption := '';
  Allow(FIssuesConnectionName, mEditable);
  Allow(FIssuesConnectionProvider, mEditable);
  Allow(FIssuesConnectionUrl, mEditable);
  Allow(FIssuesConnectionStateField, mEditable);
  Allow(FIssuesConnectionAssigneeField, mEditable);
  Allow(FIssuesConnectionStartState, mEditable);
  Allow(FIssuesConnectionEndStates, mEditable);
  Allow(FIssuesConnectionRemove, mEditable);
  TrackerShowFields;
  // Token und Prüfung auch für die Verbindung aus der .atlas, nicht ohne gültige Adresse.
  Allow(FIssuesConnectionToken, mHasUrl and Assigned(FOnTrackerToken));
  Allow(FIssuesConnectionCheck, mHasUrl and Assigned(FOnTrackerCheck));
end;

procedure TAtlasTrackerSettingsSection.TrackerShowFields;
var
  mRows: TArray<TAtlasTrackerConnection>;
  mShown: Boolean;

  // alTop ordnet eine wieder gezeigte Zeile nach ihrem alten Top ein: knapp über „Beim Beginnen“ stellen, damit
  // die Reihenfolge Zustandsfeld, Benutzerfeld, Beim Beginnen bleibt.
  procedure ShowAbove(ARow: TWinControl; AShown: Boolean);
  begin
    if AShown and not ARow.Visible then
      ARow.Top := FIssuesConnectionStartState.Parent.Top - 1;
    ARow.Visible := AShown;
  end;

begin
  mRows := TrackerRows;
  mShown := True;
  if (FTrackerSelected >= 0) and (FTrackerSelected <= High(mRows)) then
    mShown := TAtlasTrackerWorkflow.UsesFields(mRows[FTrackerSelected].Provider);
  ShowAbove(FIssuesConnectionStateRow, mShown);
  ShowAbove(FIssuesConnectionAssigneeRow, mShown);
end;

procedure TAtlasTrackerSettingsSection.TrackerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FTrackerFilling or not Selected or (Item = nil) then
    Exit;
  FTrackerSelected := Item.Index;
  TrackerFillFields;
end;

procedure TAtlasTrackerSettingsSection.TrackerNameChange(Sender: TObject);
var
  mName, mOld: string;
  mIndex: Integer;
begin
  if FTrackerFilling or not TrackerEditable then
    Exit;
  mName := Trim(FIssuesConnectionName.Text);
  if TAtlasTrackerConnections.NameTaken(FTrackerConnections, mName, FTrackerSelected) then
  begin
    FIssuesConnectionNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNameTaken);
    Exit;
  end;
  FIssuesConnectionNote.Caption := '';
  // Zeilen der Tabelle Projekte verweisen per Name: umbenennen statt sie ins Leere zeigen zu lassen (#1261).
  mOld := FTrackerConnections[FTrackerSelected].Name;
  for mIndex := 0 to High(FTrackerProjects) do
    if (mOld <> '') and SameText(FTrackerProjects[mIndex].Connection, mOld) then
      FTrackerProjects[mIndex].Connection := mName;
  // Ebenso die Abfragen mit dieser Verbindung (#1262).
  TAtlasTrackerQueries.RenameConnection(FTrackerQueries, mOld, mName);
  FTrackerConnections[FTrackerSelected].Name := mName;
  if ListReady(FIssuesConnections) and (FTrackerSelected < FIssuesConnections.Items.Count) then
    FIssuesConnections.Items[FTrackerSelected].Caption := mName;
  RefreshTrackerProjects;
end;

procedure TAtlasTrackerSettingsSection.TrackerProviderChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FIssuesConnectionProvider.Choice;
  if FTrackerFilling or not TrackerEditable or (mChoice < 0) or (mChoice > High(FTrackerProviderNames)) then
    Exit;
  FTrackerConnections[FTrackerSelected].Provider := FTrackerProviderNames[mChoice];
  TrackerShowFields;
  if ListReady(FIssuesConnections) and (FTrackerSelected < FIssuesConnections.Items.Count) then
    FIssuesConnections.Items[FTrackerSelected].SubItems[0] := FTrackerProviderCaptions[mChoice];
end;

procedure TAtlasTrackerSettingsSection.TrackerUrlChange(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
begin
  if FTrackerFilling or not TrackerEditable then
    Exit;
  // Nur gültige Adressen übernehmen: http oder ein Benutzer in der Adresse werden abgewiesen, mit Grund.
  case TAtlasTrackerConnections.CheckUrl(FIssuesConnectionUrl.Text) of
    TAtlasTrackerUrlCheck.Empty:
      FIssuesConnectionNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlEmpty);
    TAtlasTrackerUrlCheck.NotHttps:
      FIssuesConnectionNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlHttps);
    TAtlasTrackerUrlCheck.WithUser:
      FIssuesConnectionNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlUser);
    TAtlasTrackerUrlCheck.Invalid:
      FIssuesConnectionNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlInvalid);
  else
    begin
      FIssuesConnectionNote.Caption := '';
      // WithUrl behält Zustandsfeld, Zielzustände usw. (#1266).
      mConnection := FTrackerConnections[FTrackerSelected].WithUrl(FIssuesConnectionUrl.Text);
      FTrackerConnections[FTrackerSelected] := mConnection;
      if ListReady(FIssuesConnections) and (FTrackerSelected < FIssuesConnections.Items.Count) then
      begin
        FIssuesConnections.Items[FTrackerSelected].SubItems[1] := mConnection.Url;
        FIssuesConnections.Items[FTrackerSelected].SubItems[2] := TrackerStateText(mConnection);
      end;
      Allow(FIssuesConnectionToken, Assigned(FOnTrackerToken));
      Allow(FIssuesConnectionCheck, Assigned(FOnTrackerCheck));
    end;
  end;
end;

procedure TAtlasTrackerSettingsSection.TrackerAddClick(Sender: TObject);
begin
  // Neue Zeile ohne Adresse: gespeichert wird sie erst mit gültiger Adresse.
  FTrackerConnections := FTrackerConnections + [TAtlasTrackerConnection.Create(
    TAtlasTrackerConnections.FreeName(TrackerRows, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNew)),
    FTrackerProviderNames[0], '')];
  FTrackerSelected := High(FTrackerConnections);
  RefreshTrackerConnections;
  if FIssuesConnectionName.CanFocus and FIssuesConnectionName.Showing then
    FIssuesConnectionName.SetFocus;
end;

procedure TAtlasTrackerSettingsSection.TrackerRemoveClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
begin
  if not TrackerEditable then
    Exit;
  mConnection := FTrackerConnections[FTrackerSelected];
  // Die Rückfrage zum Token (Anmeldespeicher) stellt die IDE; die Zeile geht in jedem Fall.
  if Assigned(FOnTrackerRemove) and (mConnection.Target.Server <> '') then
    FOnTrackerRemove(mConnection);
  Delete(FTrackerConnections, FTrackerSelected, 1);
  if FTrackerSelected > High(TrackerRows) then
    FTrackerSelected := High(TrackerRows);
  RefreshTrackerConnections;
end;

procedure TAtlasTrackerSettingsSection.TrackerTokenClick(Sender: TObject);
var
  mRows: TArray<TAtlasTrackerConnection>;
begin
  mRows := TrackerRows;
  if not Assigned(FOnTrackerToken) or (FTrackerSelected < 0) or (FTrackerSelected > High(mRows)) then
    Exit;
  FOnTrackerToken(mRows[FTrackerSelected]);
  RefreshTrackerConnections;
end;

procedure TAtlasTrackerSettingsSection.TrackerCheckClick(Sender: TObject);
var
  mRows: TArray<TAtlasTrackerConnection>;
  mServer: string;
begin
  mRows := TrackerRows;
  if not Assigned(FOnTrackerCheck) or (FTrackerSelected < 0) or (FTrackerSelected > High(mRows)) then
    Exit;
  mServer := mRows[FTrackerSelected].Target.CredentialTarget;
  if (mServer = '') or MatchText(mServer, FTrackerChecking) then
    Exit;
  FTrackerChecking := FTrackerChecking + [mServer];
  RefreshTrackerConnections;
  FOnTrackerCheck(mRows[FTrackerSelected]);
end;

procedure TAtlasTrackerSettingsSection.TrackerCheckDone(const AConnection: TAtlasTrackerConnection);
var
  mIndex: Integer;
  mStatus: TAtlasTrackerTokenStatus;
begin
  // Späte Antwort nach dem Schließen: verfällt (Regel 3).
  if FClosed then
    Exit;
  for mIndex := High(FTrackerChecking) downto 0 do
    if SameText(FTrackerChecking[mIndex], AConnection.Target.CredentialTarget) then
      Delete(FTrackerChecking, mIndex, 1);
  // Erkannte Sprache der Oberfläche (#1263) an den persönlichen Verbindungen zu diesem Server merken; gespeichert
  // mit OK.
  if Assigned(FOnTrackerState) then
  begin
    mStatus := FOnTrackerState(AConnection);
    if mStatus.Language <> '' then
      for mIndex := 0 to High(FTrackerConnections) do
        if SameText(FTrackerConnections[mIndex].Target.CredentialTarget, AConnection.Target.CredentialTarget) then
          FTrackerConnections[mIndex].Language := mStatus.Language;
  end;
  RefreshTrackerConnections;
end;

function TAtlasTrackerSettingsSection.TrackerConnectionsJson: string;
var
  mKept: TArray<TAtlasTrackerConnection>;
  mConnection: TAtlasTrackerConnection;
begin
  mKept := nil;
  for mConnection in FTrackerConnections do
    if (mConnection.Name <> '') and (mConnection.Provider <> '') and
      (TAtlasTrackerConnections.CheckUrl(mConnection.Url) = TAtlasTrackerUrlCheck.Valid) and
      (TAtlasTrackerConnections.IndexOfName(mKept, mConnection.Name) < 0) then
      mKept := mKept + [mConnection];
  Result := TAtlasTrackerConnections.ToJson(mKept);
end;

procedure TAtlasTrackerSettingsSection.AddTrackerProjectsSection;

  function AddMenuItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FOwner);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    FIssuesProjectAddMenu.Items.Add(Result);
  end;

var
  mPanel: TWinControl;
begin
  FTrackerProjectSelected := -1;
  FTrackerContext := TAtlasTrackerProjectContext.Empty;
  AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjects));
  FProjectsRow := AddKeyedPanel(110, 'issues.projects');
  mPanel := FProjectsRow;
  // Wie die Verbindungen: die Zeilen erst mit Fenster (RefreshTrackerProjects, auch aus WindowReady).
  FIssuesProjects := TListView.Create(FOwner);
  FIssuesProjects.Parent := mPanel;
  FIssuesProjects.Align := alClient;
  FIssuesProjects.ViewStyle := vsReport;
  FIssuesProjects.ReadOnly := True;
  FIssuesProjects.RowSelect := True;
  FIssuesProjects.HideSelection := False;
  FIssuesProjects.OnSelectItem := TrackerProjectSelectItem;
  FIssuesProjects.OnCustomDrawItem := TrackerProjectDrawItem;
  AddTrackerColumn(FIssuesProjects, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatch), 230);
  AddTrackerColumn(FIssuesProjects, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectConnection), 100);
  AddTrackerColumn(FIssuesProjects, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectProject), 100);
  AddTrackerColumn(FIssuesProjects, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectSource), 150);
  FIssuesProjectMatch := TEdit.Create(FOwner);
  FIssuesProjectMatch.OnChange := TrackerProjectMatchChange;
  mPanel := AddTrackerLabelled(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatch), FIssuesProjectMatch, 376);
  FIssuesProjectMatch.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FProjectsRow);
  FIssuesProjectConnection := TAtlasChoiceBox.Create(FOwner);
  FIssuesProjectConnection.OnChange := TrackerProjectConnectionChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectConnection), FIssuesProjectConnection, 180),
    FProjectsRow);
  FIssuesProjectProject := TEdit.Create(FOwner);
  FIssuesProjectProject.OnChange := TrackerProjectProjectChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectProject), FIssuesProjectProject, 180),
    FProjectsRow);
  // Grund, warum eine Zeile nicht greift (Verbindung fehlt, von .atlas überdeckt …).
  mPanel := AddPanel(18);
  FIssuesProjectNote := TLabel.Create(FOwner);
  FIssuesProjectNote.Parent := mPanel;
  FIssuesProjectNote.Left := 90;
  FIssuesProjectNote.Top := 1;
  FIssuesProjectNote.Font.Color := clRed;
  Attach(mPanel, FProjectsRow);
  mPanel := AddPanel(32);
  FIssuesProjectAddCurrent := AddTrackerButton(mPanel, 0, 180, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAddCurrent),
    TrackerProjectAddCurrentClick);
  FIssuesProjectAdd := AddTrackerButton(mPanel, 186, 110, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAdd),
    TrackerProjectAddClick);
  FIssuesProjectRemove := AddTrackerButton(mPanel, 302, 100, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionRemove),
    TrackerProjectRemoveClick);
  Attach(mPanel, FProjectsRow);
  // „Hinzufügen …“: Projektdatei oder Ordner.
  FIssuesProjectAddMenu := TPopupMenu.Create(FOwner);
  AddMenuItem(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAddFile), TrackerProjectAddFileClick);
  AddMenuItem(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAddFolder), TrackerProjectAddFolderClick);
  AddTrackerHint(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectsHint), FProjectsRow);
end;

function TAtlasTrackerSettingsSection.TrackerProjectRows: TArray<TAtlasTrackerProjectMapping>;
begin
  Result := FTrackerProjects + FTrackerContext.Team;
end;

function TAtlasTrackerSettingsSection.TrackerProjectEditable: Boolean;
begin
  Result := (FTrackerProjectSelected >= 0) and (FTrackerProjectSelected < Length(FTrackerProjects));
end;

function TAtlasTrackerSettingsSection.TrackerProjectCovered(const AMapping: TAtlasTrackerProjectMapping): Boolean;
begin
  Result := TAtlasTrackerProjects.Covered(AMapping, FTrackerContext.HasTeam, FTrackerContext.ProjectFile,
    FTrackerContext.GroupFile);
end;

function TAtlasTrackerSettingsSection.TrackerProjectSourceText(const AMapping: TAtlasTrackerProjectMapping): string;
begin
  if AMapping.ReadOnly then
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam)
  else if TrackerProjectCovered(AMapping) then
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectPersonal);
end;

procedure TAtlasTrackerSettingsSection.RefreshTrackerProjects;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mRow: TAtlasTrackerProjectMapping;
  mItem: TListItem;
  mConnection: TAtlasTrackerConnection;
begin
  if FClosed or (FIssuesProjects = nil) then
    Exit;
  FTrackerContext := TAtlasTrackerProjectContext.Empty;
  if Assigned(FOnTrackerContext) then
    FTrackerContext := FOnTrackerContext();
  // Auswahl der Verbindung: die persönlichen mit Namen (eine Zeile verweist per Name auf sie).
  FTrackerProjectChoices := nil;
  for mConnection in FTrackerConnections do
    if (mConnection.Name <> '') and not MatchText(mConnection.Name, FTrackerProjectChoices) then
      FTrackerProjectChoices := FTrackerProjectChoices + [mConnection.Name];
  FTrackerProjectFilling := True;
  try
    FIssuesProjectConnection.SetChoices(FTrackerProjectChoices);
  finally
    FTrackerProjectFilling := False;
  end;
  mRows := TrackerProjectRows;
  if FTrackerProjectSelected > High(mRows) then
    FTrackerProjectSelected := High(mRows);
  if ListReady(FIssuesProjects) then
  begin
    FTrackerProjectFilling := True;
    FIssuesProjects.Items.BeginUpdate;
    try
      FIssuesProjects.Items.Clear;
      for mRow in mRows do
      begin
        mItem := FIssuesProjects.Items.Add;
        mItem.Caption := mRow.Match;
        mItem.SubItems.Add(mRow.Connection);
        mItem.SubItems.Add(mRow.Project);
        mItem.SubItems.Add(TrackerProjectSourceText(mRow));
      end;
      if FTrackerProjectSelected >= 0 then
        FIssuesProjects.Items[FTrackerProjectSelected].Selected := True;
    finally
      FIssuesProjects.Items.EndUpdate;
      FTrackerProjectFilling := False;
    end;
  end;
  TrackerProjectFillFields;
  // Die Auswahl der Verbindung in der Tabelle Abfragen folgt ebenfalls den Verbindungen.
  RefreshTrackerQueries;
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectNoteFor(const AMapping: TAtlasTrackerProjectMapping);
begin
  if AMapping.ReadOnly then
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly)
  else if Length(FTrackerProjectChoices) = 0 then
    FIssuesProjectNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectNoConnection)
  else if not MatchText(AMapping.Connection, FTrackerProjectChoices) then
    FIssuesProjectNote.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesProjectConnectionMissing,
      [AMapping.Connection])
  else if TrackerProjectCovered(AMapping) then
    FIssuesProjectNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectCoveredHint)
  else
    FIssuesProjectNote.Caption := '';
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectFillFields;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mSelected, mEditable: Boolean;
  mIndex: Integer;
begin
  mRows := TrackerProjectRows;
  mSelected := (FTrackerProjectSelected >= 0) and (FTrackerProjectSelected <= High(mRows));
  mEditable := TrackerProjectEditable;
  FTrackerProjectFilling := True;
  try
    if mSelected then
    begin
      FIssuesProjectMatch.Text := mRows[FTrackerProjectSelected].Match;
      FIssuesProjectProject.Text := mRows[FTrackerProjectSelected].Project;
      FIssuesProjectConnection.Choice := -1;
      for mIndex := 0 to High(FTrackerProjectChoices) do
        if SameText(FTrackerProjectChoices[mIndex], mRows[FTrackerProjectSelected].Connection) then
          FIssuesProjectConnection.Choice := mIndex;
      TrackerProjectNoteFor(mRows[FTrackerProjectSelected]);
    end
    else
    begin
      FIssuesProjectMatch.Text := '';
      FIssuesProjectProject.Text := '';
      FIssuesProjectConnection.Choice := -1;
      FIssuesProjectNote.Caption := '';
      if Length(FTrackerProjectChoices) = 0 then
        FIssuesProjectNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectNoConnection);
    end;
  finally
    FTrackerProjectFilling := False;
  end;
  Allow(FIssuesProjectMatch, mEditable);
  Allow(FIssuesProjectConnection, mEditable and (Length(FTrackerProjectChoices) > 0));
  Allow(FIssuesProjectProject, mEditable);
  Allow(FIssuesProjectRemove, mEditable);
  Allow(FIssuesProjectAddCurrent, FTrackerContext.ProjectFile <> '');
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FTrackerProjectFilling or not Selected or (Item = nil) then
    Exit;
  FTrackerProjectSelected := Item.Index;
  TrackerProjectFillFields;
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
begin
  // Von der .atlas überdeckte persönliche Zeile grau (Mockup IT2).
  mRows := TrackerProjectRows;
  if (Item <> nil) and (Item.Index <= High(mRows)) and TrackerProjectCovered(mRows[Item.Index]) then
    Sender.Canvas.Font.Color := clGrayText;
  DefaultDraw := True;
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectMatchChange(Sender: TObject);
var
  mMatch: string;
  mOther: Integer;
begin
  if FTrackerProjectFilling or not TrackerProjectEditable then
    Exit;
  mMatch := Trim(FIssuesProjectMatch.Text);
  // Ein Pfad hat höchstens eine persönliche Zeile.
  mOther := TAtlasTrackerProjects.IndexOfMatch(FTrackerProjects, mMatch);
  if (mMatch <> '') and (mOther >= 0) and (mOther <> FTrackerProjectSelected) then
  begin
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken);
    Exit;
  end;
  FTrackerProjects[FTrackerProjectSelected].Match := mMatch;
  TrackerProjectNoteFor(FTrackerProjects[FTrackerProjectSelected]);
  if ListReady(FIssuesProjects) and (FTrackerProjectSelected < FIssuesProjects.Items.Count) then
  begin
    FIssuesProjects.Items[FTrackerProjectSelected].Caption := mMatch;
    FIssuesProjects.Items[FTrackerProjectSelected].SubItems[2] :=
      TrackerProjectSourceText(FTrackerProjects[FTrackerProjectSelected]);
  end;
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectConnectionChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FIssuesProjectConnection.Choice;
  if FTrackerProjectFilling or not TrackerProjectEditable or (mChoice < 0) or
    (mChoice > High(FTrackerProjectChoices)) then
    Exit;
  FTrackerProjects[FTrackerProjectSelected].Connection := FTrackerProjectChoices[mChoice];
  TrackerProjectNoteFor(FTrackerProjects[FTrackerProjectSelected]);
  if ListReady(FIssuesProjects) and (FTrackerProjectSelected < FIssuesProjects.Items.Count) then
    FIssuesProjects.Items[FTrackerProjectSelected].SubItems[0] := FTrackerProjectChoices[mChoice];
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectProjectChange(Sender: TObject);
begin
  if FTrackerProjectFilling or not TrackerProjectEditable then
    Exit;
  FTrackerProjects[FTrackerProjectSelected].Project := Trim(FIssuesProjectProject.Text);
  if ListReady(FIssuesProjects) and (FTrackerProjectSelected < FIssuesProjects.Items.Count) then
    FIssuesProjects.Items[FTrackerProjectSelected].SubItems[1] := FTrackerProjects[FTrackerProjectSelected].Project;
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectAdd(const AMatch: string);
var
  mIndex: Integer;
  mConnection: string;
begin
  if Trim(AMatch) = '' then
    Exit;
  mIndex := TAtlasTrackerProjects.IndexOfMatch(FTrackerProjects, AMatch);
  if mIndex < 0 then
  begin
    // Vorbelegt mit der ersten Verbindung; das Tracker-Projekt trägt man selbst ein.
    mConnection := '';
    if Length(FTrackerProjectChoices) > 0 then
      mConnection := FTrackerProjectChoices[0];
    FTrackerProjects := FTrackerProjects + [TAtlasTrackerProjectMapping.Create(AMatch, mConnection, '')];
    mIndex := High(FTrackerProjects);
  end;
  FTrackerProjectSelected := mIndex;
  RefreshTrackerProjects;
  if FIssuesProjectProject.CanFocus and FIssuesProjectProject.Showing then
    FIssuesProjectProject.SetFocus;
end;

procedure TAtlasTrackerSettingsSection.AssignTrackerProject(const AMatch: string);
begin
  // Späte Antwort nach dem Schließen: verfällt (Regel 3).
  if FClosed then
    Exit;
  TrackerProjectAdd(AMatch);
  FHost.Reveal('issues.projects');
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectAddCurrentClick(Sender: TObject);
begin
  RefreshTrackerProjects;
  if FTrackerContext.ProjectFile = '' then
  begin
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectNoProject);
    Exit;
  end;
  // Die geöffnete .groupproj, sonst die aktive .dproj.
  TrackerProjectAdd(TAtlasTrackerProjects.CurrentMatch(FTrackerContext.ProjectFile, FTrackerContext.GroupFile));
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectAddClick(Sender: TObject);
begin
  // Unter dem Knopf aufklappen.
  FIssuesProjectAddMenu.Popup(FIssuesProjectAdd.ClientOrigin.X,
    FIssuesProjectAdd.ClientOrigin.Y + FIssuesProjectAdd.Height);
end;

function TAtlasTrackerSettingsSection.TrackerBrowse(AFolder: Boolean; out APath: string): Boolean;
var
  mFolder: TFileOpenDialog;
  mFile: TOpenDialog;
begin
  APath := '';
  if Assigned(FOnTrackerBrowse) then
    Exit(FOnTrackerBrowse(AFolder, APath));
  if AFolder then
  begin
    mFolder := TFileOpenDialog.Create(nil);
    try
      mFolder.Options := mFolder.Options + [fdoPickFolders, fdoPathMustExist];
      Result := mFolder.Execute;
      if Result then
        APath := mFolder.FileName;
    finally
      mFolder.Free;
    end;
    Exit;
  end;
  mFile := TOpenDialog.Create(nil);
  try
    mFile.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectFileFilter);
    mFile.Options := mFile.Options + [ofFileMustExist];
    Result := mFile.Execute;
    if Result then
      APath := mFile.FileName;
  finally
    mFile.Free;
  end;
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectAddFileClick(Sender: TObject);
var
  mPath: string;
begin
  if TrackerBrowse(False, mPath) then
    TrackerProjectAdd(mPath);
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectAddFolderClick(Sender: TObject);
var
  mPath: string;
begin
  if TrackerBrowse(True, mPath) then
    TrackerProjectAdd(mPath);
end;

procedure TAtlasTrackerSettingsSection.TrackerProjectRemoveClick(Sender: TObject);
begin
  if not TrackerProjectEditable then
    Exit;
  Delete(FTrackerProjects, FTrackerProjectSelected, 1);
  if FTrackerProjectSelected > High(TrackerProjectRows) then
    FTrackerProjectSelected := High(TrackerProjectRows);
  RefreshTrackerProjects;
end;

function TAtlasTrackerSettingsSection.TrackerProjectsJson: string;
var
  mKept: TArray<TAtlasTrackerProjectMapping>;
  mMapping: TAtlasTrackerProjectMapping;
begin
  mKept := nil;
  for mMapping in FTrackerProjects do
    if (mMapping.Match <> '') and (mMapping.Connection <> '') and
      (TAtlasTrackerProjects.IndexOfMatch(mKept, mMapping.Match) < 0) then
      mKept := mKept + [mMapping];
  Result := TAtlasTrackerProjects.ToJson(mKept);
end;

procedure TAtlasTrackerSettingsSection.AddTrackerQueriesSection;
var
  mPanel: TWinControl;
begin
  FTrackerQuerySelected := -1;
  FTrackerQueries := nil;
  AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueries));
  FQueriesRow := AddKeyedPanel(96, 'issues.queries');
  mPanel := FQueriesRow;
  // Wie die Verbindungen: die Zeilen erst mit Fenster (RefreshTrackerQueries, auch aus WindowReady).
  FIssuesQueries := TListView.Create(FOwner);
  FIssuesQueries.Parent := mPanel;
  FIssuesQueries.Align := alClient;
  FIssuesQueries.ViewStyle := vsReport;
  FIssuesQueries.ReadOnly := True;
  FIssuesQueries.RowSelect := True;
  FIssuesQueries.HideSelection := False;
  FIssuesQueries.OnSelectItem := TrackerQuerySelectItem;
  AddTrackerColumn(FIssuesQueries, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryName), 130);
  AddTrackerColumn(FIssuesQueries, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQuery), 230);
  AddTrackerColumn(FIssuesQueries, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectConnection), 100);
  AddTrackerColumn(FIssuesQueries, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectProject), 100);
  FIssuesQueryName := TEdit.Create(FOwner);
  FIssuesQueryName.OnChange := TrackerQueryNameChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryName), FIssuesQueryName, 180), FQueriesRow);
  FIssuesQueryText := TEdit.Create(FOwner);
  FIssuesQueryText.OnChange := TrackerQueryTextChange;
  mPanel := AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQuery), FIssuesQueryText, 376);
  FIssuesQueryText.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FQueriesRow);
  FIssuesQueryConnection := TAtlasChoiceBox.Create(FOwner);
  FIssuesQueryConnection.OnChange := TrackerQueryConnectionChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectConnection), FIssuesQueryConnection, 180),
    FQueriesRow);
  FIssuesQueryProject := TEdit.Create(FOwner);
  FIssuesQueryProject.OnChange := TrackerQueryProjectChange;
  Attach(AddTrackerLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectProject), FIssuesQueryProject, 180), FQueriesRow);
  // Grund, warum eine Zeile nicht gespeichert wird (Name doppelt, Abfrage fehlt), bzw. die Vorgabe ohne Zeilen.
  mPanel := AddPanel(18);
  FIssuesQueryNote := TLabel.Create(FOwner);
  FIssuesQueryNote.Parent := mPanel;
  FIssuesQueryNote.Left := 90;
  FIssuesQueryNote.Top := 1;
  Attach(mPanel, FQueriesRow);
  mPanel := AddPanel(32);
  FIssuesQueryAdd := AddTrackerButton(mPanel, 0, 110, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAdd), TrackerQueryAddClick);
  FIssuesQueryRemove := AddTrackerButton(mPanel, 116, 100, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionRemove),
    TrackerQueryRemoveClick);
  // Dialog mit Vorlagen und „Testen“ (#1263); auch Doppelklick auf eine Zeile.
  FIssuesQueryEdit := AddTrackerButton(mPanel, 222, 110, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryEdit),
    TrackerQueryEditClick);
  FIssuesQueries.OnDblClick := TrackerQueryEditClick;
  Attach(mPanel, FQueriesRow);
  AddTrackerHint(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueriesHint), FQueriesRow);
  FIssuesQueryPicker := AddCheck('issues.queryPicker', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryPicker));
  // „Issue anlegen …“ im Editor und bei Befunden (#1268).
  FIssuesCreate := AddCheck('issues.create', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesCreate));
  FIssuesCreateIncludeCode := AddCheck('issues.create.includeCode', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesCreateIncludeCode));
end;

function TAtlasTrackerSettingsSection.TrackerQueryEditable: Boolean;
begin
  Result := (FTrackerQuerySelected >= 0) and (FTrackerQuerySelected <= High(FTrackerQueries));
end;

function TAtlasTrackerSettingsSection.TrackerQueryConnectionChoice(const AConnection: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if AConnection = '' then
    Exit;
  Result := -1;
  for mIndex := 0 to High(FTrackerProjectChoices) do
    if SameText(FTrackerProjectChoices[mIndex], AConnection) then
      Exit(mIndex + 1);
end;

procedure TAtlasTrackerSettingsSection.RefreshTrackerQueries;
var
  mQuery: TAtlasTrackerQuery;
  mItem: TListItem;
begin
  if FClosed or (FIssuesQueries = nil) then
    Exit;
  // Auswahl: „(alle)“, dann die Verbindungen mit Namen (wie bei den Projekten).
  FTrackerQueryFilling := True;
  try
    FIssuesQueryConnection.SetChoices(TArray<string>.Create(
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryAny)) + FTrackerProjectChoices);
  finally
    FTrackerQueryFilling := False;
  end;
  if FTrackerQuerySelected > High(FTrackerQueries) then
    FTrackerQuerySelected := High(FTrackerQueries);
  if ListReady(FIssuesQueries) then
  begin
    FTrackerQueryFilling := True;
    FIssuesQueries.Items.BeginUpdate;
    try
      FIssuesQueries.Items.Clear;
      for mQuery in FTrackerQueries do
      begin
        mItem := FIssuesQueries.Items.Add;
        mItem.Caption := mQuery.Name;
        mItem.SubItems.Add(mQuery.Query);
        mItem.SubItems.Add(mQuery.Connection);
        mItem.SubItems.Add(mQuery.Project);
      end;
      if FTrackerQuerySelected >= 0 then
        FIssuesQueries.Items[FTrackerQuerySelected].Selected := True;
    finally
      FIssuesQueries.Items.EndUpdate;
      FTrackerQueryFilling := False;
    end;
  end;
  TrackerQueryFillFields;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryNoteFor(const AQuery: TAtlasTrackerQuery);
begin
  if AQuery.Query = '' then
    FIssuesQueryNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryEmpty)
  else if (AQuery.Connection <> '') and (TrackerQueryConnectionChoice(AQuery.Connection) < 0) then
    FIssuesQueryNote.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesProjectConnectionMissing,
      [AQuery.Connection])
  else
    FIssuesQueryNote.Caption := '';
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryFillFields;
var
  mEditable: Boolean;
begin
  mEditable := TrackerQueryEditable;
  FTrackerQueryFilling := True;
  try
    if mEditable then
    begin
      FIssuesQueryName.Text := FTrackerQueries[FTrackerQuerySelected].Name;
      FIssuesQueryText.Text := FTrackerQueries[FTrackerQuerySelected].Query;
      FIssuesQueryProject.Text := FTrackerQueries[FTrackerQuerySelected].Project;
      FIssuesQueryConnection.Choice :=
        TrackerQueryConnectionChoice(FTrackerQueries[FTrackerQuerySelected].Connection);
      TrackerQueryNoteFor(FTrackerQueries[FTrackerQuerySelected]);
    end
    else
    begin
      FIssuesQueryName.Text := '';
      FIssuesQueryText.Text := '';
      FIssuesQueryProject.Text := '';
      FIssuesQueryConnection.Choice := 0;
      FIssuesQueryNote.Caption := '';
      // Ohne eigene Zeilen gilt die Vorgabe je Anbieter.
      if Length(FTrackerQueries) = 0 then
        FIssuesQueryNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueriesNone);
    end;
  finally
    FTrackerQueryFilling := False;
  end;
  Allow(FIssuesQueryName, mEditable);
  Allow(FIssuesQueryText, mEditable);
  Allow(FIssuesQueryConnection, mEditable);
  Allow(FIssuesQueryProject, mEditable);
  Allow(FIssuesQueryRemove, mEditable);
  Allow(FIssuesQueryEdit, mEditable);
end;

procedure TAtlasTrackerSettingsSection.TrackerQuerySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FTrackerQueryFilling or not Selected or (Item = nil) then
    Exit;
  FTrackerQuerySelected := Item.Index;
  TrackerQueryFillFields;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryRowChanged;
var
  mQuery: TAtlasTrackerQuery;
  mItem: TListItem;
begin
  mQuery := FTrackerQueries[FTrackerQuerySelected];
  TrackerQueryNoteFor(mQuery);
  if not ListReady(FIssuesQueries) or (FTrackerQuerySelected >= FIssuesQueries.Items.Count) then
    Exit;
  mItem := FIssuesQueries.Items[FTrackerQuerySelected];
  mItem.Caption := mQuery.Name;
  mItem.SubItems[0] := mQuery.Query;
  mItem.SubItems[1] := mQuery.Connection;
  mItem.SubItems[2] := mQuery.Project;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryNameChange(Sender: TObject);
var
  mName: string;
  mOther: Integer;
begin
  if FTrackerQueryFilling or not TrackerQueryEditable then
    Exit;
  mName := Trim(FIssuesQueryName.Text);
  // Die Klappliste unterscheidet die Abfragen am Namen.
  mOther := TAtlasTrackerQueries.IndexOfName(FTrackerQueries, mName);
  if (mName = '') or ((mOther >= 0) and (mOther <> FTrackerQuerySelected)) then
  begin
    FIssuesQueryNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNameTaken);
    Exit;
  end;
  FTrackerQueries[FTrackerQuerySelected].Name := mName;
  TrackerQueryRowChanged;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryTextChange(Sender: TObject);
var
  mQuery: TAtlasTrackerQuery;
begin
  if FTrackerQueryFilling or not TrackerQueryEditable then
    Exit;
  // Einzeilig wie beim Lesen (TAtlasTrackerQuery.Create).
  mQuery := FTrackerQueries[FTrackerQuerySelected];
  FTrackerQueries[FTrackerQuerySelected] := TAtlasTrackerQuery.Create(mQuery.Name, FIssuesQueryText.Text,
    mQuery.Connection, mQuery.Project);
  TrackerQueryRowChanged;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryConnectionChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FIssuesQueryConnection.Choice;
  if FTrackerQueryFilling or not TrackerQueryEditable or (mChoice < 0) or
    (mChoice > Length(FTrackerProjectChoices)) then
    Exit;
  if mChoice = 0 then
    FTrackerQueries[FTrackerQuerySelected].Connection := ''
  else
    FTrackerQueries[FTrackerQuerySelected].Connection := FTrackerProjectChoices[mChoice - 1];
  TrackerQueryRowChanged;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryProjectChange(Sender: TObject);
begin
  if FTrackerQueryFilling or not TrackerQueryEditable then
    Exit;
  FTrackerQueries[FTrackerQuerySelected].Project := Trim(FIssuesQueryProject.Text);
  TrackerQueryRowChanged;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryAddClick(Sender: TObject);
var
  mBase, mName: string;
  mNumber: Integer;
begin
  // Neue Zeile ohne Abfrage: gespeichert wird sie erst mit Abfrage.
  mBase := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNew);
  mName := mBase;
  mNumber := 1;
  while TAtlasTrackerQueries.IndexOfName(FTrackerQueries, mName) >= 0 do
  begin
    Inc(mNumber);
    mName := mBase + ' ' + IntToStr(mNumber);
  end;
  FTrackerQueries := FTrackerQueries + [TAtlasTrackerQuery.Create(mName, '', '', '')];
  FTrackerQuerySelected := High(FTrackerQueries);
  RefreshTrackerQueries;
  if FIssuesQueryText.CanFocus and FIssuesQueryText.Showing then
    FIssuesQueryText.SetFocus;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryRemoveClick(Sender: TObject);
begin
  if not TrackerQueryEditable then
    Exit;
  Delete(FTrackerQueries, FTrackerQuerySelected, 1);
  if FTrackerQuerySelected > High(FTrackerQueries) then
    FTrackerQuerySelected := High(FTrackerQueries);
  RefreshTrackerQueries;
end;

procedure TAtlasTrackerSettingsSection.TrackerQueryEditClick(Sender: TObject);
var
  mQuery: TAtlasTrackerQuery;
  mTaken: TArray<string>;
  mIndex: Integer;
  mOk: Boolean;
begin
  if not TrackerQueryEditable then
    Exit;
  mQuery := FTrackerQueries[FTrackerQuerySelected];
  mTaken := nil;
  for mIndex := 0 to High(FTrackerQueries) do
    if mIndex <> FTrackerQuerySelected then
      mTaken := mTaken + [FTrackerQueries[mIndex].Name];
  if Assigned(FOnTrackerQueryEdit) then
    mOk := FOnTrackerQueryEdit(mQuery, TrackerRows, mTaken)
  else
    mOk := TAtlasTrackerQueryDialog.Execute(mQuery, TrackerRows, mTaken, FOnTrackerQueryTest);
  if not mOk then
    Exit;
  FTrackerQueries[FTrackerQuerySelected] := mQuery;
  RefreshTrackerQueries;
end;

procedure TAtlasTrackerSettingsSection.TrackerWorkflowChange(Sender: TObject);
begin
  if FTrackerFilling or not TrackerEditable then
    Exit;
  FTrackerConnections[FTrackerSelected].StateField := FIssuesConnectionStateField.Value;
  FTrackerConnections[FTrackerSelected].AssigneeField := FIssuesConnectionAssigneeField.Value;
  FTrackerConnections[FTrackerSelected].StartState := FIssuesConnectionStartState.Value;
  FTrackerConnections[FTrackerSelected].EndStates := TAtlasTrackerWorkflow.ParseList(FIssuesConnectionEndStates.Text);
end;

function TAtlasTrackerSettingsSection.TrackerValuesConnection(out AConnection: TAtlasTrackerConnection): Boolean;
var
  mRows: TArray<TAtlasTrackerConnection>;
  mRow: TAtlasTrackerConnection;
begin
  mRows := TrackerRows;
  if (FTrackerSelected >= 0) and (FTrackerSelected <= High(mRows)) and
    (mRows[FTrackerSelected].Target.Server <> '') then
  begin
    AConnection := mRows[FTrackerSelected];
    Exit(True);
  end;
  for mRow in mRows do
    if mRow.Target.Server <> '' then
    begin
      AConnection := mRow;
      Exit(True);
    end;
  AConnection := TAtlasTrackerConnection.Create('', '', '');
  Result := False;
end;

procedure TAtlasTrackerSettingsSection.TrackerLoadValuesClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
  mField: string;
begin
  if not Assigned(FOnTrackerValues) then
    Exit;
  if not TrackerValuesConnection(mConnection) then
  begin
    FIssuesValuesNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesValuesNoConnection);
    Exit;
  end;
  // Zustände zum Feld der Verbindung, sonst zum globalen Feld.
  mField := mConnection.StateField;
  if mField = '' then
    mField := FIssuesStateField.Value;
  FIssuesValuesNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesValuesLoading);
  FIssuesLoadValues.Enabled := False;
  FOnTrackerValues(mConnection, mField);
end;

procedure TAtlasTrackerSettingsSection.TrackerValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
begin
  // Späte Antwort nach dem Schließen: verfällt (Regel 3).
  if FClosed then
    Exit;
  FIssuesLoadValues.Enabled := True;
  if AError <> '' then
  begin
    FIssuesValuesNote.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesFailed, [AError]);
    Exit;
  end;
  // Vorschläge für die globalen Felder und die der Verbindung; eingegebene Texte bleiben.
  FIssuesStateField.SetValues(AValues.StateFields);
  FIssuesAssigneeField.SetValues(AValues.UserFields);
  FIssuesStartState.SetValues(AValues.States);
  FIssuesConnectionStateField.SetValues(AValues.StateFields);
  FIssuesConnectionAssigneeField.SetValues(AValues.UserFields);
  FIssuesConnectionStartState.SetValues(AValues.States);
  FIssuesValuesNote.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesLoaded,
    [Length(AValues.States), Length(AValues.StateFields) + Length(AValues.UserFields)]);
end;

function TAtlasTrackerSettingsSection.TrackerQueriesJson: string;
var
  mKept: TArray<TAtlasTrackerQuery>;
  mQuery: TAtlasTrackerQuery;
begin
  mKept := nil;
  for mQuery in FTrackerQueries do
    if (mQuery.Name <> '') and (mQuery.Query <> '') and (TAtlasTrackerQueries.IndexOfName(mKept, mQuery.Name) < 0) then
      mKept := mKept + [mQuery];
  Result := TAtlasTrackerQueries.ToJson(mKept);
end;

end.
