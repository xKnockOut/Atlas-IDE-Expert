unit Atlas.UI.Tracker.IssueFrame;

// Inhalt des andockbaren Fensters „Atlas-Issue“ (#1264), reine VCL ohne Open
// Tools API:
//   [◀] [▶]  [Beginnen] [Beenden …] [Im Browser öffnen] [Kennung kopieren] [Anhängen …] [Aktualisieren]
//   ───────────────── dünne Leiste beim Laden ─────────────────
//   (Stand vom …  bzw. Fehler mit Knopf zum Beheben)
//   ATL-123 · 3/5   (Fortschritt der Checkliste, #1273)
//   Titel des Issues (Klick öffnet den Tracker)
//   (In Arbeit) (Hoch) (Bug) (M. Muster) (Sprint 12) (ui) (erstellt vor 3 Tg.)
//   Beschreibung: Markdown gesetzt wie die XMLDoc im Hover (TAtlasDocView):
//   Überschriften, Listen, fett/kursiv, Links, Tabellen, Zitate, Codeblöcke
//   (Delphi eingefärbt); alleinstehende Bilder als Vorschau in Fensterbreite,
//   Klick vergrößert. Aufgabenlisten (#1273) als Häkchen: Klick meldet
//   OnToggleTask (die IDE-Schicht schreibt zurück), darunter „Punkt
//   hinzufügen …“ (OnAddTask); ohne Schreibrecht nur lesend mit Tooltip;
//   mit Checklists = False als Text wie geschrieben. In Kommentaren nur
//   Kästchen ohne Klick.
//   KOMMENTARE (n): neueste unten, ältere hinter „12 ältere Kommentare“.
//   Aus einer Meldung (#1271, SetAnchor) öffnet der Inhalt am ersten neuen
//   Kommentar; sein Kopf ist hervorgehoben.
//   ANHÄNGE (n): Name und Größe; Doppelklick öffnet.
//   VERKNÜPFTE ISSUES (n): Kennung, Titel, Art; Klick öffnet im Fenster.
//   ───────────────── unten (#1266, nur mit issues.syncState) ─────────────────
//   Kommentar schreiben … (Markdown, Strg+Enter sendet)          [Senden]
// „Beenden …“ (#1266) gibt es nur für das aktuelle Issue (CanEnd), Feld und
// Knopf nur, wenn der Tracker schreiben kann (CanWrite).
//   Mit LinksAsTree (#1279, issues.preview.links) stattdessen
//   VERKNÜPFUNGEN (n) als Baum: Hängt ab von, Blockiert, Unteraufgaben 2/3,
//   Übergeordnet; Duplikate, „Bezieht sich auf“ und Erwähnungen eingeklappt;
//   je Zeile Symbol (✓ erledigt, ○ offen, ⛔ blockiert dieses Issue, ? Zustand
//   unbekannt), Kennung, Titel und Zustand; Klick öffnet im Fenster. Mit
//   CanWriteLinks darüber [Unteraufgabe anlegen …] [Verknüpfen …].
// Inhalt auf zwei Reitern: „Details“ (oben beschrieben) und „Entwicklung“
// (#1269, TAtlasIssueDevelopmentView: Branches, Commits, Pull Requests,
// geänderte Units); der zweite fehlt bei issues.preview.development aus.
// Gesucht wird erst, wenn der Reiter sichtbar wird (OnDevelopmentShown).
// „Anhängen …“ (#1276) als Knopf und im Kontextmenü nur mit CanAttach
// (issues.attach); die IDE-Schicht öffnet den Dialog für dieses Issue.
// Ein Fenster, der Inhalt wechselt; Verlauf über Zurück/Vor (Alt+Links,
// Alt+Rechts). Schließen des Fensters (OnHidden) bricht das Laden ab. Laden, Netz, Verlauf und Zwischenspeicher liegen in der
// IDE-Schicht; der Frame meldet nur Wünsche (On…). Text in der Beschreibung
// und den Kommentaren lässt sich markieren und mit Strg+C kopieren. Die DFM
// ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Actions,
  System.Generics.Collections,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.ActnList,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.DocBox,
  Atlas.UI.Tracker.CommentEditor,
  Atlas.UI.Tracker.DevelopmentView;

const
  /// <summary>Nachricht an den Frame: Inhalt neu bzw. verknüpftes Issue öffnen, nach dem auslösenden Klick (das
  /// Steuerelement des Klicks wird dabei freigegeben). Mit dem Fenster verfällt sie.</summary>
  WM_ATLAS_ISSUE_DEFERRED = WM_APP + 1264;

type
  /// <summary>Bild in Fensterbreite (höchstens Originalgröße); Klick vergrößert.</summary>
  TAtlasIssueImageBox = class(TCustomControl)
  private
    FUrl: string;
    FAlt: string;
    FGraphic: TGraphic;
    FColors: TAtlasColors;
    FOnEnlarge: TNotifyEvent;
    procedure Fit;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Übernimmt AGraphic (gibt es frei).</summary>
    procedure SetGraphic(AGraphic: TGraphic);
    property Url: string read FUrl write FUrl;
    property Alt: string read FAlt write FAlt;
    property Graphic: TGraphic read FGraphic;
    property Colors: TAtlasColors read FColors write FColors;
    property OnEnlarge: TNotifyEvent read FOnEnlarge write FOnEnlarge;
  end;

  /// <summary>Felder als Abzeichen, umgebrochen auf die Breite; Tooltip je Abzeichen.</summary>
  TAtlasIssueBadgeBar = class(TCustomControl)
  private
    FTexts: TArray<string>;
    FHints: TArray<string>;
    FRects: TArray<TRect>;
    FColors: TAtlasColors;
    FHintIndex: Integer;
    procedure Arrange;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetBadges(const ATexts, AHints: TArray<string>; const AColors: TAtlasColors);
    property Texts: TArray<string> read FTexts;
    property Hints: TArray<string> read FHints;
  end;

  TAtlasIssueFrame = class(TFrame)
  private
    FTools: TPanel;
    FBack: TButton;
    FForward: TButton;
    FStart: TButton;
    FBrowse: TButton;
    FCopyKey: TButton;
    FAttach: TButton;
    FMenu: TPopupMenu;
    FAttachItem: TMenuItem;
    FRefresh: TButton;
    FEnd: TButton;
    FCommentPanel: TPanel;
    FCommentHint: TLabel;
    FComment: TAtlasCommentEditor;
    FCommentEdit: TMemo;
    FCommentSend: TButton;
    FCommentNote: TLabel;
    FCanWrite: Boolean;
    FCanEnd: Boolean;
    FCommentSending: Boolean;
    FOnEnd: TProc;
    FOnComment: TProc<string>;
    FProgress: TProgressBar;
    FStatus: TPanel;
    FStatusText: TLabel;
    FFix: TButton;
    FPages: TPageControl;
    FDetailsSheet: TTabSheet;
    FDevelopmentSheet: TTabSheet;
    /// <summary>Reiter „Entwicklung“ gewünscht; ApplyTabs setzt ihn, sobald es ein Fenster gibt.</summary>
    FShowDevelopment: Boolean;
    FDevelopment: TAtlasIssueDevelopmentView;
    FScroll: TScrollBox;
    FEmpty: TLabel;
    FKey: TLabel;
    FTitle: TLabel;
    FBadges: TAtlasIssueBadgeBar;
    FParts: TList<TControl>;
    FImages: TList<TAtlasIssueImageBox>;
    FDocs: TList<TAtlasIssueDocBox>;
    FAttachments: TListView;
    FLinks: TListView;
    FOlder: TLabel;
    FActions: TActionList;
    FBackAction: TAction;
    FForwardAction: TAction;
    FDetails: TAtlasTrackerDetails;
    FHasDetails: Boolean;
    FNow: TDateTime;
    FCommentsExpanded: Boolean;
    FCommentsOff: Boolean;
    FLoading: Boolean;
    FFixKind: TAtlasIssueFix;
    FColors: TAtlasColors;
    FMono: TFont;
    FCanStart: Boolean;
    FCanAttach: Boolean;
    FNextTop: Integer;
    FPendingRebuild: Boolean;
    FPendingLink: TAtlasTrackerLink;
    FHasPendingLink: Boolean;
    FChecklists: Boolean;
    FChecklistReadOnly: Boolean;
    FChecklistBusy: Boolean;
    FProgressText: string;
    FTaskBox: TAtlasIssueDocBox;
    FAddTask: TLabel;
    FPendingTask: Integer;
    FPendingAdd: Boolean;
    FRevealTasks: Boolean;
    FOnToggleTask: TProc<Integer>;
    FOnAddTask: TProc;
    // Anker einer Meldung (#1271): Zeit des ersten neuen Kommentars (UTC), der hervorgehobene Kommentar und
    // sein Kopf.
    FAnchor: TDateTime;
    FAnchorComment: Integer;
    FAnchorLabel: TLabel;
    FOnBack: TProc;
    FOnForward: TProc;
    FOnStart: TProc;
    FOnBrowse: TProc;
    FOnCopyKey: TProc;
    FOnAttach: TProc;
    FOnRefresh: TProc;
    FOnCancel: TProc;
    FOnFix: TProc<TAtlasIssueFix>;
    FOnOpenLink: TProc<TAtlasTrackerLink>;
    FOnOpenAttachment: TProc<TAtlasTrackerAttachment>;
    FOnOpenUrl: TProc<string>;
    FOnImages: TProc<TArray<string>>;
    FOnHidden: TProc;
    FOnCreateSubtask: TProc;
    FOnAddLink: TProc;
    // Verknüpfungen als Baum (#1279): Node.Data = Index + 1 in FTreeLinks, Gruppen nil.
    FLinksAsTree: Boolean;
    FCanWriteLinks: Boolean;
    FLinkTree: TTreeView;
    FTreeLinks: TArray<TAtlasTrackerLink>;
    FCreateSubtask: TButton;
    FAddLink: TButton;
    FOnDevelopmentShown: TProc;
    function AddButton(const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabel(const ACaption: string; ABold: Boolean): TLabel;
    function AddDoc(const ADoc: TAtlasDoc): TAtlasIssueDocBox;
    function AddList(const AColumns: TArray<string>): TListView;
    procedure AddMarkdown(const AText: string; ATasks: TAtlasMarkdownTasks);
    procedure AddTaskClick(Sender: TObject);
    procedure ScrollToTasks;
    procedure SetChecklists(AValue: Boolean);
    procedure SetChecklistReadOnly(AValue: Boolean);
    procedure ClearContent;
    procedure Rebuild;
    procedure UpdateButtons;
    function AgeText(ATime: TDateTime): string;
    function AbsoluteText(ATime: TDateTime): string;
    procedure BackClick(Sender: TObject);
    procedure ForwardClick(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure EndClick(Sender: TObject);
    procedure CommentSendClick(Sender: TObject);
    procedure SetCanWrite(AValue: Boolean);
    procedure SetCanEnd(AValue: Boolean);
    procedure BrowseClick(Sender: TObject);
    procedure CopyKeyClick(Sender: TObject);
    procedure AttachClick(Sender: TObject);
    procedure SetCanAttach(AValue: Boolean);
    procedure RefreshClick(Sender: TObject);
    procedure FixClick(Sender: TObject);
    procedure TitleClick(Sender: TObject);
    procedure OlderClick(Sender: TObject);
    procedure ImageEnlarge(Sender: TObject);
    procedure AttachmentsDblClick(Sender: TObject);
    procedure AttachmentsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LinksClick(Sender: TObject);
    procedure AddLinkList;
    procedure AddLinkTree;
    procedure FitLinkTree;
    procedure LinkTreeClick(Sender: TObject);
    procedure LinkTreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LinkTreeExpanded(Sender: TObject; Node: TTreeNode);
    procedure CreateSubtaskClick(Sender: TObject);
    procedure AddLinkClick(Sender: TObject);
    procedure LinkOpened(const AUrl: string);
    procedure ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure SetMonoFont(AValue: TFont);
    procedure Place(AControl: TControl);
    procedure Defer;
    procedure WMDeferred(var AMessage: TMessage); message WM_ATLAS_ISSUE_DEFERRED;
    procedure CMShowingChanged(var AMessage: TMessage); message CM_SHOWINGCHANGED;
    procedure PagesChange(Sender: TObject);
    function GetDevelopmentVisible: Boolean;
    procedure SetDevelopmentVisible(AValue: Boolean);
    procedure ApplyTabs;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Noch kein Issue (Fenster aus dem Desktop der IDE).</summary>
    procedure ShowEmpty;
    /// <summary>Laden läuft (Leiste, „Aktualisieren“ wird „Abbrechen“); der bisherige Inhalt bleibt.</summary>
    procedure SetLoading(AValue: Boolean);
    /// <summary>Issue zeigen. ANow (UTC) für relative Zeiten; AStale: Text der Zeile über dem Inhalt ('' ohne);
    /// ACommentsOff: issues.preview.comments aus.</summary>
    procedure ShowDetails(const ADetails: TAtlasTrackerDetails; ANow: TDateTime; const AStale: string;
      ACommentsOff: Boolean);
    /// <summary>Die nächsten ShowDetails öffnen am Kommentar zu AAnchor (UTC; erster neuer Kommentar einer Meldung,
    /// #1271) und heben ihn hervor, ältere Kommentare klappen dafür auf; 0 = oben wie bisher. Der Anker gilt, bis
    /// der Kommentar gefunden wurde.</summary>
    procedure SetAnchor(AAnchor: TDateTime);
    /// <summary>Fehler über dem Inhalt mit Knopf zum Beheben; ohne bisherigen Inhalt nur die Meldung.</summary>
    procedure ShowError(const AText: string; AFix: TAtlasIssueFix);
    /// <summary>Bild zu AUrl ist geladen (übernimmt AGraphic); nil = bleibt als Link.</summary>
    procedure SetImage(const AUrl: string; AGraphic: TGraphic);
    procedure SetHistory(ACanBack, ACanForward: Boolean);
    /// <summary>Kommentar wird gesendet (#1266): Feld und Knopf gesperrt.</summary>
    procedure SetCommentSending(AValue: Boolean);
    /// <summary>Ergebnis des Sendens: AError '' = gesendet (Feld leer), sonst der Grund unter dem Feld.</summary>
    procedure CommentDone(const AError: string);
    /// <summary>Beschreibung nach dem Zurückschreiben (#1273): neu setzen, Bildlauf bleibt.</summary>
    procedure ReplaceDescription(const AText: string);
    /// <summary>Zurückschreiben läuft (#1273): Zeile „Wird gespeichert …“, Klicks auf Kästchen ruhen.</summary>
    procedure SetChecklistBusy(AValue: Boolean);
    /// <summary>Zur Checkliste blättern (Klick im Statusfeld, #1273); gilt auch für den nächsten Inhalt.</summary>
    procedure RevealChecklist;
    /// <summary>Hinweis über dem Inhalt ohne Knopf (#1273: „Beschreibung wurde geändert …“).</summary>
    procedure ShowNotice(const AText: string);
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Für Tests: Text der Statuszeile, Abzeichen, Bildadressen, Zahl der Doku-Flächen.</summary>
    function StatusText: string;
    function ImageUrls: TArray<string>;
    function DocCount: Integer;
    /// <summary>Fortschritt in der Kopfzeile ("3/5"; '' ohne Checkliste oder mit Checklists = False).</summary>
    property ProgressText: string read FProgressText;
    /// <summary>Doku-Fläche mit dem ersten Kästchen; nil ohne.</summary>
    property TaskBox: TAtlasIssueDocBox read FTaskBox;
    /// <summary>„Punkt hinzufügen …“; nil ohne Checkliste, ohne Schreibrecht oder mit Checklists = False.</summary>
    property AddTaskLabel: TLabel read FAddTask;
    /// <summary>issues.preview.checklists (#1273): Häkchen und Zurückschreiben; aus = Text wie geschrieben.</summary>
    property Checklists: Boolean read FChecklists write SetChecklists;
    /// <summary>Keine Schreibrechte: Kästchen nur lesend mit Tooltip, kein „Punkt hinzufügen …“.</summary>
    property ChecklistReadOnly: Boolean read FChecklistReadOnly write SetChecklistReadOnly;
    property ChecklistBusy: Boolean read FChecklistBusy;
    /// <summary>Zeile des Baums (#1279): Symbol, Kennung, Titel, Zustand.</summary>
    class function LinkRowText(const ALink: TAtlasTrackerLink): string; static;
    /// <summary>Überschrift einer Gruppe des Baums (#1279), bei Unteraufgaben mit Fortschritt „2/3“.</summary>
    class function LinkGroupText(const AGroup: TAtlasTrackerLinkGroup): string; static;
    /// <summary>Reiter „Entwicklung“ ist ausgewählt (und sichtbar).</summary>
    function DevelopmentActive: Boolean;
    /// <summary>Reiter wählen (Tests, Tastatur).</summary>
    procedure SelectDevelopment;
    procedure SelectDetails;
    property Details: TAtlasTrackerDetails read FDetails;
    property HasDetails: Boolean read FHasDetails;
    property Loading: Boolean read FLoading;
    property CanStart: Boolean read FCanStart write FCanStart;
    /// <summary>Der Tracker kann schreiben und issues.syncState ist an (#1266): Kommentarfeld und „Beenden …“.
    /// </summary>
    property CanWrite: Boolean read FCanWrite write SetCanWrite;
    /// <summary>Das gezeigte Issue ist das aktuelle: „Beenden …“ geht.</summary>
    property CanEnd: Boolean read FCanEnd write SetCanEnd;
    property EndButton: TButton read FEnd;
    property CommentPanel: TPanel read FCommentPanel;
    /// <summary>Kommentar-Editor (#1278); CommentEdit ist sein Memo.</summary>
    property CommentEditor: TAtlasCommentEditor read FComment;
    property CommentEdit: TMemo read FCommentEdit;
    property CommentSendButton: TButton read FCommentSend;
    property CommentNote: TLabel read FCommentNote;
    /// <summary>„Anhängen …“ zeigen (issues.attach, #1276).</summary>
    property CanAttach: Boolean read FCanAttach write SetCanAttach;
    property CommentsExpanded: Boolean read FCommentsExpanded;
    /// <summary>Für Tests: hervorgehobener Kommentar (Index in Details.Comments); -1 ohne.</summary>
    property AnchorComment: Integer read FAnchorComment;
    property BackButton: TButton read FBack;
    property ForwardButton: TButton read FForward;
    property StartButton: TButton read FStart;
    property BrowseButton: TButton read FBrowse;
    property CopyKeyButton: TButton read FCopyKey;
    property AttachButton: TButton read FAttach;
    property AttachMenuItem: TMenuItem read FAttachItem;
    property RefreshButton: TButton read FRefresh;
    property FixButton: TButton read FFix;
    property BackAction: TAction read FBackAction;
    property ForwardAction: TAction read FForwardAction;
    property KeyLabel: TLabel read FKey;
    property TitleLabel: TLabel read FTitle;
    property EmptyLabel: TLabel read FEmpty;
    property Badges: TAtlasIssueBadgeBar read FBadges;
    property Attachments: TListView read FAttachments;
    property Links: TListView read FLinks;
    /// <summary>Verknüpfungen als Baum statt Liste (issues.preview.links, #1279); gilt ab dem nächsten
    /// ShowDetails.</summary>
    property LinksAsTree: Boolean read FLinksAsTree write FLinksAsTree;
    /// <summary>Der Tracker kann Unteraufgaben anlegen und verknüpfen: Knöpfe über dem Baum.</summary>
    property CanWriteLinks: Boolean read FCanWriteLinks write FCanWriteLinks;
    property LinkTree: TTreeView read FLinkTree;
    property CreateSubtaskButton: TButton read FCreateSubtask;
    property AddLinkButton: TButton read FAddLink;
    property OlderLabel: TLabel read FOlder;
    property Progress: TProgressBar read FProgress;
    property Pages: TPageControl read FPages;
    /// <summary>Inhalt des Reiters „Entwicklung“ (#1269).</summary>
    property Development: TAtlasIssueDevelopmentView read FDevelopment;
    /// <summary>issues.preview.development: Reiter „Entwicklung“ zeigen.</summary>
    property DevelopmentVisible: Boolean read GetDevelopmentVisible write SetDevelopmentVisible;
    /// <summary>Editorschrift für Code (Vorgabe Consolas).</summary>
    property MonoFont: TFont read FMono write SetMonoFont;
    property OnBack: TProc read FOnBack write FOnBack;
    property OnForward: TProc read FOnForward write FOnForward;
    property OnStart: TProc read FOnStart write FOnStart;
    /// <summary>„Beenden …“ (#1266) für das gezeigte, aktuelle Issue.</summary>
    property OnEnd: TProc read FOnEnd write FOnEnd;
    /// <summary>Kommentar senden (#1266); Ergebnis über CommentDone.</summary>
    property OnComment: TProc<string> read FOnComment write FOnComment;
    property OnBrowse: TProc read FOnBrowse write FOnBrowse;
    property OnCopyKey: TProc read FOnCopyKey write FOnCopyKey;
    /// <summary>„Anhängen …“ für das gezeigte Issue (#1276).</summary>
    property OnAttach: TProc read FOnAttach write FOnAttach;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    property OnCancel: TProc read FOnCancel write FOnCancel;
    property OnFix: TProc<TAtlasIssueFix> read FOnFix write FOnFix;
    property OnOpenLink: TProc<TAtlasTrackerLink> read FOnOpenLink write FOnOpenLink;
    property OnOpenAttachment: TProc<TAtlasTrackerAttachment> read FOnOpenAttachment write FOnOpenAttachment;
    /// <summary>Link aus Beschreibung oder Kommentar bzw. Titel; die IDE-Schicht prüft und öffnet.</summary>
    property OnOpenUrl: TProc<string> read FOnOpenUrl write FOnOpenUrl;
    /// <summary>Adressen der Bilder, die geladen werden sollen (nach ShowDetails).</summary>
    property OnImages: TProc<TArray<string>> read FOnImages write FOnImages;
    /// <summary>Fenster geschlossen bzw. Frame freigegeben: laufendes Laden abbrechen.</summary>
    property OnHidden: TProc read FOnHidden write FOnHidden;
    /// <summary>Kästchen Nummer N (ab 0, TAtlasTrackerChecklist) der Beschreibung angeklickt (#1273); nach dem
    /// Klick gemeldet.</summary>
    property OnToggleTask: TProc<Integer> read FOnToggleTask write FOnToggleTask;
    /// <summary>„Punkt hinzufügen …“ angeklickt (#1273); nach dem Klick gemeldet.</summary>
    property OnAddTask: TProc read FOnAddTask write FOnAddTask;
    /// <summary>„Unteraufgabe anlegen …“ bzw. „Verknüpfen …“ (#1279); Dialog und Senden in der IDE-Schicht.
    /// </summary>
    property OnCreateSubtask: TProc read FOnCreateSubtask write FOnCreateSubtask;
    property OnAddLink: TProc read FOnAddLink write FOnAddLink;
    /// <summary>Reiter „Entwicklung“ wurde gewählt: suchen, wenn noch nicht geschehen.</summary>
    property OnDevelopmentShown: TProc read FOnDevelopmentShown write FOnDevelopmentShown;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.DateUtils,
  System.UITypes,
  Atlas.Core.Style.Color,
  Atlas.Core.Tracker.Checklist,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.IssueTip;

{$R *.dfm}

type
  /// <summary>Vergrößertes Bild; gibt sich beim Schließen selbst frei.</summary>
  TImageWindow = class(TForm)
  protected
    procedure DoClose(var Action: TCloseAction); override;
  end;

procedure TImageWindow.DoClose(var Action: TCloseAction);
begin
  inherited;
  Action := caFree;
end;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasIssueImageBox }

constructor TAtlasIssueImageBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  Height := 24;
  Cursor := crHandPoint;
end;

destructor TAtlasIssueImageBox.Destroy;
begin
  FGraphic.Free;
  inherited;
end;

procedure TAtlasIssueImageBox.SetGraphic(AGraphic: TGraphic);
begin
  FreeAndNil(FGraphic);
  FGraphic := AGraphic;
  Hint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewImageHint);
  ShowHint := True;
  Fit;
  Invalidate;
end;

procedure TAtlasIssueImageBox.Fit;
var
  mHeight: Integer;
begin
  if (FGraphic = nil) or (FGraphic.Width <= 0) or (ClientWidth <= 0) then
    Exit;
  // Höchstens Originalgröße, sonst Fensterbreite.
  mHeight := FGraphic.Height;
  if FGraphic.Width > ClientWidth then
    mHeight := MulDiv(FGraphic.Height, ClientWidth, FGraphic.Width);
  mHeight := Max(mHeight, 8);
  if Height <> mHeight then
    Height := mHeight;
end;

procedure TAtlasIssueImageBox.Resize;
begin
  inherited;
  Fit;
end;

procedure TAtlasIssueImageBox.Paint;
var
  mRect: TRect;
  mWidth: Integer;
  mText: string;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if (FGraphic = nil) or (FGraphic.Width <= 0) then
  begin
    // Noch nicht geladen bzw. nicht ladbar: Alternativtext gedämpft.
    Canvas.Font := Font;
    Canvas.Font.Color := ToColor(FColors.Muted);
    mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewImageLink, [FAlt]);
    Canvas.TextOut(0, ScaleValue(2), mText);
    Exit;
  end;
  mWidth := Min(FGraphic.Width, ClientWidth);
  mRect := Rect(0, 0, mWidth, ClientHeight);
  Canvas.StretchDraw(mRect, FGraphic);
end;

procedure TAtlasIssueImageBox.Click;
begin
  inherited;
  if (FGraphic <> nil) and Assigned(FOnEnlarge) then
    FOnEnlarge(Self);
end;

{ TAtlasIssueBadgeBar }

constructor TAtlasIssueBadgeBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FHintIndex := -1;
  ShowHint := True;
  Height := 4;
end;

procedure TAtlasIssueBadgeBar.SetBadges(const ATexts, AHints: TArray<string>; const AColors: TAtlasColors);
begin
  FTexts := ATexts;
  FHints := AHints;
  FColors := AColors;
  Arrange;
  Invalidate;
end;

procedure TAtlasIssueBadgeBar.Arrange;
var
  mIndex, mX, mY, mWidth, mHeight, mPad, mGap: Integer;
begin
  FRects := nil;
  if not HandleAllocated then
  begin
    Height := 4;
    Exit;
  end;
  Canvas.Font := Font;
  mPad := MulDiv(6, CurrentPPI, 96);
  mGap := MulDiv(4, CurrentPPI, 96);
  mHeight := Canvas.TextHeight('Wg') + MulDiv(4, CurrentPPI, 96);
  mX := 0;
  mY := 0;
  for mIndex := 0 to High(FTexts) do
  begin
    mWidth := Canvas.TextWidth(FTexts[mIndex]) + 2 * mPad;
    if (mX > 0) and (mX + mWidth > ClientWidth) then
    begin
      mX := 0;
      Inc(mY, mHeight + mGap);
    end;
    FRects := FRects + [Rect(mX, mY, mX + mWidth, mY + mHeight)];
    Inc(mX, mWidth + mGap);
  end;
  if Length(FTexts) = 0 then
    Height := 4
  else if Height <> mY + mHeight + mGap then
    Height := mY + mHeight + mGap;
end;

procedure TAtlasIssueBadgeBar.Resize;
begin
  inherited;
  Arrange;
end;

procedure TAtlasIssueBadgeBar.Paint;
var
  mIndex, mRadius: Integer;
  mRect: TRect;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if Length(FRects) <> Length(FTexts) then
    Arrange;
  Canvas.Font := Font;
  mRadius := MulDiv(8, CurrentPPI, 96);
  for mIndex := 0 to High(FRects) do
  begin
    mRect := FRects[mIndex];
    Canvas.Brush.Color := ToColor(FColors.Gutter);
    Canvas.Pen.Color := ToColor(FColors.Line);
    Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, mRadius, mRadius);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(FColors.Text);
    DrawText(Canvas.Handle, PChar(FTexts[mIndex]), Length(FTexts[mIndex]), mRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TAtlasIssueBadgeBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mIndex, mHit: Integer;
begin
  inherited;
  mHit := -1;
  for mIndex := 0 to High(FRects) do
    if FRects[mIndex].Contains(Point(X, Y)) then
      mHit := mIndex;
  if mHit = FHintIndex then
    Exit;
  FHintIndex := mHit;
  if (mHit >= 0) and (mHit <= High(FHints)) then
    Hint := FHints[mHit]
  else
    Hint := '';
  Application.CancelHint;
end;

{ TAtlasIssueFrame }

constructor TAtlasIssueFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FAnchorComment := -1;
  FColors := TAtlasColors.Light;
  FMono := TFont.Create;
  FMono.Name := 'Consolas';
  FMono.Size := 10;
  FParts := TList<TControl>.Create;
  FImages := TList<TAtlasIssueImageBox>.Create;
  FDocs := TList<TAtlasIssueDocBox>.Create;
  FDetails := TAtlasTrackerDetails.Empty;
  FChecklists := True;
  FPendingTask := -1;

  FTools := TPanel.Create(Self);
  FTools.Parent := Self;
  FTools.Align := alTop;
  FTools.BevelOuter := bvNone;
  FTools.Height := 32;
  FTools.ShowCaption := False;
  FBack := AddButton('◀', BackClick);
  FBack.Hint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewBack);
  FBack.Width := 32;
  FForward := AddButton('▶', ForwardClick);
  FForward.Hint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewForward);
  FForward.Width := 32;
  FStart := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewStart), StartClick);
  FEnd := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewEnd), EndClick);
  FEnd.Hint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewEndHint);
  FEnd.Visible := False;
  FBrowse := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewBrowse), BrowseClick);
  FCopyKey := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewCopyKey), CopyKeyClick);
  FAttach := AddButton(TAtlasStrings.Text(TAtlasTextId.AttachPreviewButton), AttachClick);
  FAttach.Hint := TAtlasStrings.Text(TAtlasTextId.AttachStatusHint);
  FAttach.Visible := False;
  // Kontextmenü des Fensters (#1276): Kinder ohne eigenes Menü übernehmen es.
  FMenu := TPopupMenu.Create(Self);
  FAttachItem := TMenuItem.Create(FMenu);
  FAttachItem.Caption := TAtlasStrings.Text(TAtlasTextId.AttachCommand);
  FAttachItem.OnClick := AttachClick;
  FAttachItem.Visible := False;
  FMenu.Items.Add(FAttachItem);
  PopupMenu := FMenu;
  FRefresh := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewRefresh), RefreshClick);

  FProgress := TProgressBar.Create(Self);
  FProgress.Parent := Self;
  FProgress.Align := alTop;
  FProgress.Top := FTools.Height;
  FProgress.Height := 3;
  FProgress.Style := pbstMarquee;
  FProgress.Visible := False;

  FStatus := TPanel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.Top := FTools.Height + 10;
  FStatus.BevelOuter := bvNone;
  FStatus.Height := 30;
  FStatus.ShowCaption := False;
  FStatus.Visible := False;
  FFix := TButton.Create(Self);
  FFix.Parent := FStatus;
  FFix.Align := alRight;
  FFix.AlignWithMargins := True;
  FFix.Width := 150;
  FFix.OnClick := FixClick;
  FStatusText := TLabel.Create(Self);
  FStatusText.Parent := FStatus;
  FStatusText.Align := alClient;
  FStatusText.AlignWithMargins := True;
  FStatusText.Layout := tlCenter;
  FStatusText.ShowAccelChar := False;
  FStatusText.EllipsisPosition := epEndEllipsis;

  // Kommentar schreiben (#1266): unten, nur mit CanWrite.
  FCommentPanel := TPanel.Create(Self);
  FCommentPanel.Parent := Self;
  FCommentPanel.Align := alBottom;
  FCommentPanel.BevelOuter := bvNone;
  FCommentPanel.Height := 150;
  FCommentPanel.ShowCaption := False;
  FCommentPanel.Visible := False;
  FCommentHint := TLabel.Create(Self);
  FCommentHint.Parent := FCommentPanel;
  FCommentHint.Align := alTop;
  FCommentHint.AlignWithMargins := True;
  FCommentHint.ShowAccelChar := False;
  FCommentHint.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewCommentHint);
  FCommentNote := TLabel.Create(Self);
  FCommentNote.Parent := FCommentPanel;
  FCommentNote.Align := alBottom;
  FCommentNote.AlignWithMargins := True;
  FCommentNote.ShowAccelChar := False;
  FCommentNote.Caption := '';
  FCommentSend := TButton.Create(Self);
  FCommentSend.Parent := FCommentPanel;
  FCommentSend.Align := alRight;
  FCommentSend.AlignWithMargins := True;
  FCommentSend.Width := 90;
  FCommentSend.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewCommentSend);
  FCommentSend.OnClick := CommentSendClick;
  // Kommentar-Editor (#1278): Strg+Enter sendet; Vorschläge, Textbausteine und Entwurf, sobald die IDE ihn bindet.
  FComment := TAtlasCommentEditor.Create(Self);
  FComment.Parent := FCommentPanel;
  FComment.Align := alClient;
  FComment.AlignWithMargins := True;
  FComment.OnSend := CommentSendClick;
  FCommentEdit := FComment.Memo;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  // Ohne Reiter einhängen: Ein sichtbarer Reiter braucht das Fenster des PageControls (ApplyTabs in CreateWnd).
  FShowDevelopment := True;
  FDetailsSheet := TTabSheet.Create(Self);
  FDetailsSheet.TabVisible := False;
  FDetailsSheet.PageControl := FPages;
  FDetailsSheet.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewTabDetails);
  FDevelopmentSheet := TTabSheet.Create(Self);
  FDevelopmentSheet.TabVisible := False;
  FDevelopmentSheet.PageControl := FPages;
  FDevelopmentSheet.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewTabDevelopment);
  FPages.OnChange := PagesChange;
  FDevelopment := TAtlasIssueDevelopmentView.Create(Self);
  FDevelopment.Parent := FDevelopmentSheet;
  FDevelopment.Align := alClient;

  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := FDetailsSheet;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.HorzScrollBar.Visible := False;
  FScroll.Padding.SetBounds(8, 4, 8, 8);
  FScroll.OnMouseWheel := ScrollWheel;

  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := FScroll;
  FEmpty.Align := alTop;
  FEmpty.AlignWithMargins := True;
  FEmpty.WordWrap := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewEmpty);

  FActions := TActionList.Create(Self);
  FBackAction := TAction.Create(Self);
  FBackAction.ActionList := FActions;
  FBackAction.ShortCut := ShortCut(VK_LEFT, [ssAlt]);
  FBackAction.OnExecute := BackClick;
  FForwardAction := TAction.Create(Self);
  FForwardAction.ActionList := FActions;
  FForwardAction.ShortCut := ShortCut(VK_RIGHT, [ssAlt]);
  FForwardAction.OnExecute := ForwardClick;
  UpdateButtons;
end;

destructor TAtlasIssueFrame.Destroy;
begin
  // Entwurf sichern, solange das Memo sein Fenster hat.
  if FComment <> nil then
    FComment.Unbind;
  if Assigned(FOnHidden) then
    FOnHidden();
  FOnHidden := nil;
  FParts.Free;
  FImages.Free;
  FDocs.Free;
  FMono.Free;
  inherited;
end;

function TAtlasIssueFrame.AddButton(const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FTools;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  // Reihenfolge wie angelegt: hinter den bisherigen.
  Result.Left := FTools.ControlCount * 200;
  Result.Caption := ACaption;
  Result.ShowHint := True;
  Result.Width := Max(80, Length(ACaption) * 8);
  Result.OnClick := AClick;
end;

function TAtlasIssueFrame.AddLabel(const ACaption: string; ABold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Place(Result);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  Result.Font.Color := ToColor(FColors.Text);
  if ABold then
    Result.Font.Style := [fsBold];
  FParts.Add(Result);
end;

function TAtlasIssueFrame.AddDoc(const ADoc: TAtlasDoc): TAtlasIssueDocBox;
begin
  Result := TAtlasIssueDocBox.Create(Self);
  Place(Result);
  Result.SetDoc(ADoc, FColors, FMono);
  // Anonym: TProc<string> hat keinen const-Parameter, LinkOpened schon (E2010).
  Result.OnLink :=
    procedure(AUrl: string)
    begin
      LinkOpened(AUrl);
    end;
  FParts.Add(Result);
  FDocs.Add(Result);
end;

function TAtlasIssueFrame.AddList(const AColumns: TArray<string>): TListView;
var
  mCaption: string;
  mColumn: TListColumn;
begin
  Result := TListView.Create(Self);
  Place(Result);
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.ShowColumnHeaders := True;
  for mCaption in AColumns do
  begin
    mColumn := Result.Columns.Add;
    mColumn.Caption := mCaption;
    mColumn.AutoSize := True;
  end;
  FParts.Add(Result);
end;

procedure TAtlasIssueFrame.Place(AControl: TControl);
begin
  // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
  Inc(FNextTop, 1000);
  AControl.Parent := FScroll;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := FNextTop;
end;

procedure TAtlasIssueFrame.Defer;
begin
  if HandleAllocated then
    PostMessage(Handle, WM_ATLAS_ISSUE_DEFERRED, 0, 0);
end;

procedure TAtlasIssueFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  // Das X versteckt die Form samt Frame: wie Schließen.
  if not Showing and Assigned(FOnHidden) then
    FOnHidden();
end;

procedure TAtlasIssueFrame.WMDeferred(var AMessage: TMessage);
var
  mLink: TAtlasTrackerLink;
  mTask: Integer;
begin
  if FPendingRebuild then
  begin
    FPendingRebuild := False;
    Rebuild;
  end;
  if FHasPendingLink then
  begin
    FHasPendingLink := False;
    mLink := FPendingLink;
    if Assigned(FOnOpenLink) then
      FOnOpenLink(mLink);
  end;
  if FPendingTask >= 0 then
  begin
    mTask := FPendingTask;
    FPendingTask := -1;
    if Assigned(FOnToggleTask) then
      FOnToggleTask(mTask);
  end;
  if FPendingAdd then
  begin
    FPendingAdd := False;
    if Assigned(FOnAddTask) then
      FOnAddTask();
  end;
end;

procedure TAtlasIssueFrame.AddMarkdown(const AText: string; ATasks: TAtlasMarkdownTasks);
var
  mSegment: TAtlasMarkdownSegment;
  mImage: TAtlasIssueImageBox;
  mDoc: TAtlasIssueDocBox;
  mUrl: string;
begin
  for mSegment in TAtlasTrackerMarkdown.Segments(AText, ATasks) do
  begin
    if mSegment.Kind = TAtlasMarkdownSegmentKind.Doc then
    begin
      mDoc := AddDoc(mSegment.Doc);
      if ATasks = TAtlasMarkdownTasks.Clickable then
      begin
        mDoc.TasksLocked := FChecklistReadOnly;
        if FChecklistReadOnly then
          mDoc.TaskHint := TAtlasStrings.Text(TAtlasTextId.IssueChecklistReadOnly)
        else
          mDoc.TaskHint := TAtlasStrings.Text(TAtlasTextId.IssueChecklistToggleHint);
        if (FTaskBox = nil) and mDoc.HasTasks then
          FTaskBox := mDoc;
      end;
      Continue;
    end;
    // Relative Namen (YouTrack) sind Anhänge.
    mUrl := TAtlasIssuePreview.ImageUrl(FDetails, mSegment.Image.Url);
    mImage := TAtlasIssueImageBox.Create(Self);
    Place(mImage);
    mImage.Url := mUrl;
    mImage.Alt := mSegment.Image.Text;
    if mImage.Alt = '' then
      mImage.Alt := mSegment.Image.Url;
    mImage.Colors := FColors;
    mImage.OnEnlarge := ImageEnlarge;
    FParts.Add(mImage);
    FImages.Add(mImage);
  end;
end;

procedure TAtlasIssueFrame.ClearContent;
var
  mPart: TControl;
begin
  FScroll.DisableAlign;
  try
    for mPart in FParts do
      mPart.Free;
    FParts.Clear;
    FImages.Clear;
    FDocs.Clear;
    FKey := nil;
    FTitle := nil;
    FBadges := nil;
    FAttachments := nil;
    FLinks := nil;
    FLinkTree := nil;
    FTreeLinks := nil;
    FCreateSubtask := nil;
    FAddLink := nil;
    FOlder := nil;
    FTaskBox := nil;
    FAddTask := nil;
    FNextTop := 0;
  finally
    FScroll.EnableAlign;
  end;
end;

function TAtlasIssueFrame.AbsoluteText(ATime: TDateTime): string;
begin
  Result := '';
  if ATime > 0 then
    Result := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ATime));
end;

function TAtlasIssueFrame.AgeText(ATime: TDateTime): string;
begin
  Result := TAtlasIssueTip.AgeText(ATime, FNow);
end;

procedure TAtlasIssueFrame.Rebuild;
var
  mBadge: TAtlasIssueBadge;
  mTexts, mHints: TArray<string>;
  mText, mHint: string;
  mComments: TArray<TAtlasTrackerComment>;
  mIndex, mCollapsed: Integer;
  mItem: TListItem;
  mAttachment: TAtlasTrackerAttachment;
  mHead: TLabel;
  mUrls: TArray<string>;
  mImage: TAtlasIssueImageBox;
  mProgress: TAtlasChecklistProgress;
  mTasks: TAtlasMarkdownTasks;
  mAnchor: Integer;
begin
  FScroll.DisableAlign;
  try
    ClearContent;
    FProgressText := '';
    FAnchorLabel := nil;
    FAnchorComment := -1;
    FEmpty.Visible := not FHasDetails;
    if not FHasDetails then
      Exit;
    // Checklisten (#1273): Fortschritt in der Kopfzeile, Kästchen in der Beschreibung.
    mProgress := TAtlasChecklistProgress.Create(0, 0);
    if FChecklists then
      mProgress := TAtlasTrackerChecklist.Progress(FDetails.Description);
    FProgressText := mProgress.Text;
    if FProgressText <> '' then
    begin
      FKey := AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueChecklistStatusLine, [FDetails.Key, FProgressText]),
        False);
      FKey.Hint := TAtlasStrings.Fmt(TAtlasTextId.IssueChecklistProgress, [mProgress.Done, mProgress.Total]);
      FKey.ShowHint := True;
    end
    else
      FKey := AddLabel(FDetails.Key, False);
    FKey.Font.Name := FMono.Name;
    FKey.Font.Color := ToColor(FColors.Muted);
    FTitle := AddLabel(FDetails.Title, True);
    FTitle.Font.Height := MulDiv(Font.Height, 13, 10);
    FTitle.Cursor := crHandPoint;
    FTitle.OnClick := TitleClick;
    // Felder als Abzeichen; Zeiten relativ, Tooltip absolut.
    mTexts := nil;
    mHints := nil;
    for mBadge in TAtlasIssuePreview.Badges(FDetails) do
    begin
      case mBadge.Kind of
        TAtlasIssueBadgeKind.State:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldState);
        TAtlasIssueBadgeKind.Priority:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldPriority);
        TAtlasIssueBadgeKind.Kind:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldKind);
        TAtlasIssueBadgeKind.Assignee:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldAssignee);
        TAtlasIssueBadgeKind.Sprint:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldSprint);
        TAtlasIssueBadgeKind.LabelName:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldLabel);
      else
        mHint := '';
      end;
      mText := mBadge.Text;
      if mBadge.Kind = TAtlasIssueBadgeKind.Created then
      begin
        mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewBadgeCreated, [AgeText(mBadge.Time)]);
        mHint := AbsoluteText(mBadge.Time);
      end
      else if mBadge.Kind = TAtlasIssueBadgeKind.Updated then
      begin
        mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewBadgeUpdated, [AgeText(mBadge.Time)]);
        mHint := AbsoluteText(mBadge.Time);
      end
      else
        mHint := mHint + ': ' + mBadge.Text;
      mTexts := mTexts + [mText];
      mHints := mHints + [mHint];
    end;
    FBadges := TAtlasIssueBadgeBar.Create(Self);
    Place(FBadges);
    FParts.Add(FBadges);
    FBadges.SetBadges(mTexts, mHints, FColors);
    // Beschreibung; mit issues.preview.checklists aus die Aufgabenlisten als Text wie geschrieben.
    mTasks := TAtlasMarkdownTasks.Plain;
    if FChecklists then
      mTasks := TAtlasMarkdownTasks.Clickable;
    if Trim(FDetails.Description) = '' then
      AddLabel(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoDescription), False).Font.Color :=
        ToColor(FColors.Muted)
    else
      AddMarkdown(FDetails.Description, mTasks);
    if mProgress.Any and not FChecklistReadOnly then
    begin
      FAddTask := AddLabel(TAtlasStrings.Text(TAtlasTextId.IssueChecklistAdd), False);
      FAddTask.Font.Color := ToColor(FColors.Accent);
      FAddTask.Font.Style := [fsUnderline];
      FAddTask.Cursor := crHandPoint;
      FAddTask.OnClick := AddTaskClick;
    end;
    // Checklisten in Kommentaren nur als Kästchen (nicht geschrieben).
    mTasks := TAtlasMarkdownTasks.Plain;
    if FChecklists then
      mTasks := TAtlasMarkdownTasks.Boxes;
    // Kommentare: neueste unten, ältere eingeklappt.
    if FCommentsOff then
      AddLabel(TAtlasStrings.Text(TAtlasTextId.IssuePreviewCommentsOff), False).Font.Color := ToColor(FColors.Muted)
    else if Length(FDetails.Comments) > 0 then
    begin
      AddLabel(AnsiUpperCase(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewComments, [Length(FDetails.Comments)])),
        True).Font.Color := ToColor(FColors.Muted);
      mComments := FDetails.Comments;
      mAnchor := TAtlasIssuePreview.CommentAt(mComments, FAnchor);
      // Der neue Kommentar einer Meldung liegt bei den eingeklappten: aufklappen.
      if (mAnchor >= 0) and (mAnchor < TAtlasIssuePreview.CollapsedComments(Length(mComments), FCommentsExpanded)) then
        FCommentsExpanded := True;
      mCollapsed := TAtlasIssuePreview.CollapsedComments(Length(mComments), FCommentsExpanded);
      if mCollapsed > 0 then
      begin
        if mCollapsed = 1 then
          mText := TAtlasStrings.Text(TAtlasTextId.IssuePreviewOlderComment)
        else
          mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewOlderComments, [mCollapsed]);
        FOlder := AddLabel(mText, False);
        FOlder.Font.Color := ToColor(FColors.Accent);
        FOlder.Font.Style := [fsUnderline];
        FOlder.Cursor := crHandPoint;
        FOlder.OnClick := OlderClick;
      end;
      for mIndex := mCollapsed to High(mComments) do
      begin
        mHead := AddLabel(mComments[mIndex].Author + ' · ' + AgeText(mComments[mIndex].Created), True);
        mHead.Hint := AbsoluteText(mComments[mIndex].Created);
        mHead.ShowHint := True;
        if mIndex = mAnchor then
        begin
          mHead.Font.Color := ToColor(FColors.Accent);
          FAnchorLabel := mHead;
          FAnchorComment := mIndex;
        end;
        AddMarkdown(mComments[mIndex].Text, mTasks);
      end;
    end;
    // Anhänge: Name und Größe; Doppelklick öffnet.
    if Length(FDetails.Attachments) > 0 then
    begin
      AddLabel(AnsiUpperCase(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewAttachments,
        [Length(FDetails.Attachments)])), True).Font.Color := ToColor(FColors.Muted);
      FAttachments := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnName),
        TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnSize)));
      FAttachments.Items.BeginUpdate;
      try
        for mAttachment in FDetails.Attachments do
        begin
          mItem := FAttachments.Items.Add;
          mItem.Caption := mAttachment.Name;
          if mAttachment.Size >= 0 then
            mItem.SubItems.Add(FormatFloat('#,##0.0', mAttachment.Size / 1024) + ' KB')
          else
            mItem.SubItems.Add('–');
        end;
      finally
        FAttachments.Items.EndUpdate;
      end;
      FAttachments.Height := (Length(FDetails.Attachments) + 2) * MulDiv(20, CurrentPPI, 96);
      FAttachments.OnDblClick := AttachmentsDblClick;
      FAttachments.OnKeyDown := AttachmentsKeyDown;
    end;
    // Verknüpfte Issues: Klick öffnet sie im selben Fenster (bzw. im Browser); als Baum mit #1279.
    if FLinksAsTree then
      AddLinkTree
    else
      AddLinkList;
  finally
    FScroll.EnableAlign;
  end;
  // Bilder laden lassen (nur die mit Adresse).
  mUrls := nil;
  for mImage in FImages do
    if mImage.Url <> '' then
      mUrls := mUrls + [mImage.Url];
  if (Length(mUrls) > 0) and Assigned(FOnImages) then
    FOnImages(mUrls);
end;

procedure TAtlasIssueFrame.AddLinkList;
var
  mLink: TAtlasTrackerLink;
  mItem: TListItem;
begin
  if Length(FDetails.Links) = 0 then
    Exit;
  AddLabel(AnsiUpperCase(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewLinks, [Length(FDetails.Links)])),
    True).Font.Color := ToColor(FColors.Muted);
  FLinks := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnKey),
    TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnTitle),
    TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnRelation)));
  FLinks.Items.BeginUpdate;
  try
    for mLink in FDetails.Links do
    begin
      mItem := FLinks.Items.Add;
      mItem.Caption := mLink.Key;
      mItem.SubItems.Add(mLink.Title);
      if mLink.Relation = 'cross-referenced' then
        mItem.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.IssuePreviewRelationMentioned))
      else if mLink.Relation = 'pull request' then
        mItem.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.IssuePreviewRelationPull))
      else
        mItem.SubItems.Add(mLink.Relation);
    end;
  finally
    FLinks.Items.EndUpdate;
  end;
  FLinks.Height := (Length(FDetails.Links) + 2) * MulDiv(20, CurrentPPI, 96);
  FLinks.OnClick := LinksClick;
end;

class function TAtlasIssueFrame.LinkRowText(const ALink: TAtlasTrackerLink): string;
var
  mSymbol, mState: string;
begin
  case TAtlasTrackerLinks.Mark(ALink) of
    TAtlasTrackerLinkMark.Done:
      mSymbol := '✓';
    TAtlasTrackerLinkMark.Open:
      mSymbol := '○';
    TAtlasTrackerLinkMark.Blocking:
      mSymbol := '⛔';
  else
    mSymbol := '?';
  end;
  // Zustand wie im Tracker, sonst offen bzw. erledigt; dazu, ob es dieses Issue blockiert.
  if not ALink.StateKnown then
    mState := TAtlasStrings.Text(TAtlasTextId.IssueLinksUnknown)
  else if ALink.State <> '' then
    mState := ALink.State
  else if ALink.Resolved then
    mState := TAtlasStrings.Text(TAtlasTextId.IssueLinksDone)
  else
    mState := TAtlasStrings.Text(TAtlasTextId.IssueLinksOpen);
  if ALink.Blocking then
    mState := mState + ' · ' + TAtlasStrings.Text(TAtlasTextId.IssueLinksBlocking);
  Result := mSymbol + '  ' + ALink.Key;
  if ALink.Title <> '' then
    Result := Result + '  ' + ALink.Title;
  Result := Result + '  — ' + mState;
end;

class function TAtlasIssueFrame.LinkGroupText(const AGroup: TAtlasTrackerLinkGroup): string;
var
  mId: TAtlasTextId;
begin
  if AGroup.Kind = TAtlasTrackerLinkKind.Subtask then
    Exit(TAtlasStrings.Fmt(TAtlasTextId.IssueLinksSubtasks, [TAtlasTrackerLinks.ProgressText(AGroup.Done,
      AGroup.Total)]));
  case AGroup.Kind of
    TAtlasTrackerLinkKind.DependsOn:
      mId := TAtlasTextId.IssueLinksDependsOn;
    TAtlasTrackerLinkKind.Blocks:
      mId := TAtlasTextId.IssueLinksBlocks;
    TAtlasTrackerLinkKind.Parent:
      mId := TAtlasTextId.IssueLinksParent;
    TAtlasTrackerLinkKind.Duplicates:
      mId := TAtlasTextId.IssueLinksDuplicates;
    TAtlasTrackerLinkKind.DuplicatedBy:
      mId := TAtlasTextId.IssueLinksDuplicatedBy;
    TAtlasTrackerLinkKind.Relates:
      mId := TAtlasTextId.IssueLinksRelates;
    TAtlasTrackerLinkKind.Mentioned:
      mId := TAtlasTextId.IssueLinksMentioned;
    TAtlasTrackerLinkKind.PullRequest:
      mId := TAtlasTextId.IssueLinksPulls;
  else
    mId := TAtlasTextId.IssueLinksOther;
  end;
  Result := TAtlasStrings.Text(mId) + ' (' + IntToStr(AGroup.Total) + ')';
end;

procedure TAtlasIssueFrame.AddLinkTree;
var
  mGroups: TArray<TAtlasTrackerLinkGroup>;
  mGroup: TAtlasTrackerLinkGroup;
  mLink: TAtlasTrackerLink;
  mNode, mChild: TTreeNode;
  mTools: TPanel;
begin
  mGroups := TAtlasTrackerLinks.Groups(FDetails.Links);
  if (Length(mGroups) = 0) and not FCanWriteLinks then
    Exit;
  AddLabel(AnsiUpperCase(TAtlasStrings.Fmt(TAtlasTextId.IssueLinksCaption, [Length(FDetails.Links)])),
    True).Font.Color := ToColor(FColors.Muted);
  if FCanWriteLinks then
  begin
    mTools := TPanel.Create(Self);
    Place(mTools);
    mTools.BevelOuter := bvNone;
    mTools.ShowCaption := False;
    mTools.Height := MulDiv(30, CurrentPPI, 96);
    FParts.Add(mTools);
    FCreateSubtask := TButton.Create(Self);
    FCreateSubtask.Parent := mTools;
    FCreateSubtask.Align := alLeft;
    FCreateSubtask.AlignWithMargins := True;
    FCreateSubtask.Caption := TAtlasStrings.Text(TAtlasTextId.IssueLinksCreateSubtask);
    FCreateSubtask.Width := Max(120, Length(FCreateSubtask.Caption) * 8);
    FCreateSubtask.OnClick := CreateSubtaskClick;
    FAddLink := TButton.Create(Self);
    FAddLink.Parent := mTools;
    FAddLink.Align := alLeft;
    FAddLink.AlignWithMargins := True;
    FAddLink.Left := FCreateSubtask.Left + FCreateSubtask.Width + 1;
    FAddLink.Caption := TAtlasStrings.Text(TAtlasTextId.IssueLinksAddLink);
    FAddLink.Width := Max(100, Length(FAddLink.Caption) * 8);
    FAddLink.OnClick := AddLinkClick;
  end;
  if Length(mGroups) = 0 then
    Exit;
  FLinkTree := TTreeView.Create(Self);
  Place(FLinkTree);
  FParts.Add(FLinkTree);
  FLinkTree.ReadOnly := True;
  FLinkTree.RowSelect := True;
  FLinkTree.HideSelection := False;
  FLinkTree.ShowHint := True;
  FLinkTree.Color := ToColor(FColors.Surface);
  FLinkTree.Font.Color := ToColor(FColors.Text);
  FTreeLinks := nil;
  FLinkTree.Items.BeginUpdate;
  try
    for mGroup in mGroups do
    begin
      mNode := FLinkTree.Items.AddChild(nil, LinkGroupText(mGroup));
      mNode.Data := nil;
      for mLink in mGroup.Links do
      begin
        FTreeLinks := FTreeLinks + [mLink];
        mChild := FLinkTree.Items.AddChild(mNode, LinkRowText(mLink));
        mChild.Data := Pointer(NativeInt(Length(FTreeLinks)));
      end;
      // Duplikate, „bezieht sich auf“ und Erwähnungen bleiben eingeklappt.
      mNode.Expanded := not mGroup.Collapsed;
    end;
  finally
    FLinkTree.Items.EndUpdate;
  end;
  FLinkTree.OnClick := LinkTreeClick;
  FLinkTree.OnKeyDown := LinkTreeKeyDown;
  FLinkTree.OnExpanded := LinkTreeExpanded;
  FLinkTree.OnCollapsed := LinkTreeExpanded;
  FitLinkTree;
end;

procedure TAtlasIssueFrame.FitLinkTree;
var
  mNode: TTreeNode;
  mRows: Integer;
begin
  if FLinkTree = nil then
    Exit;
  // Ganze Höhe statt eigener Bildlaufleiste: die Vorschau rollt als Ganzes.
  mRows := 0;
  mNode := FLinkTree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    Inc(mRows);
    if mNode.Expanded then
      Inc(mRows, mNode.Count);
    mNode := mNode.getNextSibling;
  end;
  FLinkTree.Height := (mRows + 1) * MulDiv(20, CurrentPPI, 96);
end;

procedure TAtlasIssueFrame.LinkTreeExpanded(Sender: TObject; Node: TTreeNode);
begin
  FitLinkTree;
end;

procedure TAtlasIssueFrame.LinkTreeClick(Sender: TObject);
var
  mIndex: NativeInt;
begin
  if (FLinkTree = nil) or (FLinkTree.Selected = nil) or (FLinkTree.Selected.Data = nil) then
    Exit;
  mIndex := NativeInt(FLinkTree.Selected.Data) - 1;
  if (mIndex < 0) or (mIndex > High(FTreeLinks)) then
    Exit;
  // Öffnen ersetzt den Inhalt samt Baum: nicht im Klick des Baums.
  FPendingLink := FTreeLinks[mIndex];
  FHasPendingLink := True;
  Defer;
end;

procedure TAtlasIssueFrame.LinkTreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    LinkTreeClick(Sender);
    Key := 0;
  end;
end;

procedure TAtlasIssueFrame.CreateSubtaskClick(Sender: TObject);
begin
  if Assigned(FOnCreateSubtask) then
    FOnCreateSubtask();
end;

procedure TAtlasIssueFrame.AddLinkClick(Sender: TObject);
begin
  if Assigned(FOnAddLink) then
    FOnAddLink();
end;

procedure TAtlasIssueFrame.UpdateButtons;
begin
  FStart.Enabled := FHasDetails and FCanStart;
  // Ausgeblendete Knöpfe mit alLeft reihen sich nach Left ein: direkt hinter „Beginnen“.
  if FCanWrite and not FEnd.Visible then
    FEnd.Left := FStart.Left + FStart.Width + 1;
  FEnd.Visible := FCanWrite;
  FEnd.Enabled := FHasDetails and FCanEnd;
  FCommentPanel.Visible := FCanWrite and FHasDetails;
  FCommentSend.Enabled := FHasDetails and not FCommentSending;
  FBrowse.Enabled := FHasDetails;
  FCopyKey.Enabled := FHasDetails;
  FAttach.Visible := FCanAttach;
  FAttach.Enabled := FHasDetails;
  FAttachItem.Visible := FCanAttach;
  FAttachItem.Enabled := FHasDetails;
  FRefresh.Enabled := FHasDetails or FLoading;
  if FLoading then
    FRefresh.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewCancel)
  else
    FRefresh.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewRefresh);
  FBackAction.Enabled := FBack.Enabled;
  FForwardAction.Enabled := FForward.Enabled;
end;

procedure TAtlasIssueFrame.ShowEmpty;
begin
  FHasDetails := False;
  FDetails := TAtlasTrackerDetails.Empty;
  FStatus.Visible := False;
  Rebuild;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.SetLoading(AValue: Boolean);
begin
  FLoading := AValue;
  FProgress.Visible := AValue;
  if AValue then
  begin
    FStatusText.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewLoading);
    FFix.Visible := False;
    FStatus.Visible := not FHasDetails;
  end;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.ShowDetails(const ADetails: TAtlasTrackerDetails; ANow: TDateTime;
  const AStale: string; ACommentsOff: Boolean);
var
  mSame: Boolean;
  mPosition: Integer;
begin
  // Anderes Issue: ältere Kommentare wieder eingeklappt, oben anfangen. Dasselbe frisch geladen (auch nach dem
  // Zwischenspeicher): Bildlauf bleibt, z. B. an der Checkliste (#1273).
  mSame := FHasDetails and SameText(FDetails.Key, ADetails.Key);
  mPosition := FScroll.VertScrollBar.Position;
  if not mSame then
    FCommentsExpanded := False;
  FDetails := ADetails;
  FHasDetails := True;
  FNow := ANow;
  FCommentsOff := ACommentsOff;
  FStatusText.Caption := AStale;
  FFix.Visible := False;
  FStatus.Visible := AStale <> '';
  Rebuild;
  if mSame then
    FScroll.VertScrollBar.Position := mPosition
  else
    FScroll.VertScrollBar.Position := 0;
  if FRevealTasks then
    ScrollToTasks;
  if FAnchorLabel <> nil then
  begin
    // Kopf des Kommentars oben ins Bild.
    FScroll.VertScrollBar.Position := FAnchorLabel.Top - FAnchorLabel.Margins.Top;
    // Gefunden (nicht nur der letzte als Ersatz): Der Anker hat seinen Zweck erfüllt.
    if FDetails.Comments[FAnchorComment].Created >= FAnchor - TAtlasIssuePreview.AnchorSlackMs / MSecsPerDay then
      FAnchor := 0;
  end;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.ReplaceDescription(const AText: string);
var
  mPosition: Integer;
begin
  if not FHasDetails then
    Exit;
  mPosition := FScroll.VertScrollBar.Position;
  FDetails.Description := AText;
  Rebuild;
  FScroll.VertScrollBar.Position := mPosition;
end;

procedure TAtlasIssueFrame.SetChecklistBusy(AValue: Boolean);
begin
  FChecklistBusy := AValue;
  if AValue then
  begin
    FStatusText.Caption := TAtlasStrings.Text(TAtlasTextId.IssueChecklistSaving);
    FFix.Visible := False;
    FStatus.Visible := True;
  end
  else if FStatusText.Caption = TAtlasStrings.Text(TAtlasTextId.IssueChecklistSaving) then
    FStatus.Visible := False;
end;

procedure TAtlasIssueFrame.ShowNotice(const AText: string);
begin
  ShowError(AText, TAtlasIssueFix.None);
end;

procedure TAtlasIssueFrame.RevealChecklist;
begin
  FRevealTasks := True;
  if FHasDetails and (FTaskBox <> nil) then
    ScrollToTasks;
end;

procedure TAtlasIssueFrame.ScrollToTasks;
begin
  if FTaskBox = nil then
    Exit;
  FRevealTasks := False;
  FScroll.VertScrollBar.Position := Max(0, FTaskBox.Top + FScroll.VertScrollBar.Position - FScroll.Padding.Top);
end;

procedure TAtlasIssueFrame.SetChecklists(AValue: Boolean);
begin
  if FChecklists = AValue then
    Exit;
  FChecklists := AValue;
  if FHasDetails then
    Rebuild;
end;

procedure TAtlasIssueFrame.SetChecklistReadOnly(AValue: Boolean);
begin
  if FChecklistReadOnly = AValue then
    Exit;
  FChecklistReadOnly := AValue;
  if FHasDetails then
    Rebuild;
end;

procedure TAtlasIssueFrame.AddTaskClick(Sender: TObject);
begin
  // Der Dialog und das Neuzeichnen kommen nach dem Klick: Das Label gehört zum Inhalt.
  if FChecklistBusy or FChecklistReadOnly then
    Exit;
  FPendingAdd := True;
  Defer;
end;

procedure TAtlasIssueFrame.SetAnchor(AAnchor: TDateTime);
begin
  FAnchor := AAnchor;
end;

procedure TAtlasIssueFrame.ShowError(const AText: string; AFix: TAtlasIssueFix);
begin
  FFixKind := AFix;
  FStatusText.Caption := AText;
  FFix.Visible := AFix <> TAtlasIssueFix.None;
  case AFix of
    TAtlasIssueFix.EnterToken:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixToken);
    TAtlasIssueFix.Settings:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixSettings);
    TAtlasIssueFix.Browser:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewBrowse);
    TAtlasIssueFix.Retry:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixRetry);
    TAtlasIssueFix.None: ;
  end;
  FStatus.Visible := True;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.SetImage(const AUrl: string; AGraphic: TGraphic);
var
  mImage: TAtlasIssueImageBox;
  mOwned: Boolean;
  mCopy: TGraphic;
begin
  if AGraphic = nil then
    Exit;
  mOwned := False;
  try
    for mImage in FImages do
    begin
      if mImage.Url <> AUrl then
        Continue;
      // Dasselbe Bild mehrfach: jede Fläche bekommt ein eigenes.
      if not mOwned then
      begin
        mImage.SetGraphic(AGraphic);
        mOwned := True;
      end
      else
      begin
        mCopy := TGraphicClass(AGraphic.ClassType).Create;
        mCopy.Assign(AGraphic);
        mImage.SetGraphic(mCopy);
      end;
    end;
  finally
    if not mOwned then
      AGraphic.Free;
  end;
end;

procedure TAtlasIssueFrame.SetHistory(ACanBack, ACanForward: Boolean);
begin
  FBack.Enabled := ACanBack;
  FForward.Enabled := ACanForward;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FScroll.Color := ToColor(AColors.Surface);
  FScroll.ParentBackground := False;
  FDevelopment.ApplyColors(AColors);
  FEmpty.Font.Color := ToColor(AColors.Muted);
  FCommentHint.Font.Color := ToColor(AColors.Muted);
  FCommentNote.Font.Color := ToColor(AColors.Muted);
  FComment.ApplyColors(AColors);
  if FHasDetails then
    Rebuild;
end;

procedure TAtlasIssueFrame.SetMonoFont(AValue: TFont);
begin
  FMono.Assign(AValue);
  FComment.MonoFont := AValue;
  if FHasDetails then
    Rebuild;
end;

function TAtlasIssueFrame.StatusText: string;
begin
  Result := '';
  if FStatus.Visible then
    Result := FStatusText.Caption;
end;

function TAtlasIssueFrame.ImageUrls: TArray<string>;
var
  mImage: TAtlasIssueImageBox;
begin
  Result := nil;
  for mImage in FImages do
    Result := Result + [mImage.Url];
end;

function TAtlasIssueFrame.DocCount: Integer;
begin
  Result := FDocs.Count;
end;

procedure TAtlasIssueFrame.CreateWnd;
begin
  inherited CreateWnd;
  ApplyTabs;
end;

procedure TAtlasIssueFrame.ApplyTabs;
begin
  // Sichtbare Reiter brauchen das Fenster des PageControls; ohne bleibt es beim Wunsch in FShowDevelopment.
  if not HandleAllocated then
    Exit;
  if not FShowDevelopment and (FPages.ActivePage = FDevelopmentSheet) then
    FPages.ActivePage := FDetailsSheet;
  FDevelopmentSheet.TabVisible := FShowDevelopment;
  // Mit nur einem Reiter keine Reiterleiste.
  FDetailsSheet.TabVisible := FShowDevelopment;
  FPages.ActivePage := FDetailsSheet;
end;

function TAtlasIssueFrame.GetDevelopmentVisible: Boolean;
begin
  Result := FShowDevelopment;
end;

procedure TAtlasIssueFrame.SetDevelopmentVisible(AValue: Boolean);
begin
  if FShowDevelopment = AValue then
    Exit;
  FShowDevelopment := AValue;
  ApplyTabs;
end;

function TAtlasIssueFrame.DevelopmentActive: Boolean;
begin
  Result := FShowDevelopment and (FPages.ActivePage = FDevelopmentSheet);
end;

procedure TAtlasIssueFrame.SelectDevelopment;
begin
  if not FShowDevelopment or (FPages.ActivePage = FDevelopmentSheet) then
    Exit;
  FPages.ActivePage := FDevelopmentSheet;
  PagesChange(FPages);
end;

procedure TAtlasIssueFrame.SelectDetails;
begin
  FPages.ActivePage := FDetailsSheet;
end;

procedure TAtlasIssueFrame.PagesChange(Sender: TObject);
begin
  if DevelopmentActive and Assigned(FOnDevelopmentShown) then
    FOnDevelopmentShown();
end;

procedure TAtlasIssueFrame.BackClick(Sender: TObject);
begin
  if FBack.Enabled and Assigned(FOnBack) then
    FOnBack();
end;

procedure TAtlasIssueFrame.ForwardClick(Sender: TObject);
begin
  if FForward.Enabled and Assigned(FOnForward) then
    FOnForward();
end;

procedure TAtlasIssueFrame.StartClick(Sender: TObject);
begin
  if Assigned(FOnStart) then
    FOnStart();
end;

procedure TAtlasIssueFrame.EndClick(Sender: TObject);
begin
  if FHasDetails and FCanEnd and Assigned(FOnEnd) then
    FOnEnd();
end;

procedure TAtlasIssueFrame.CommentSendClick(Sender: TObject);
var
  mText: string;
begin
  mText := Trim(FCommentEdit.Text);
  if (mText = '') or FCommentSending or not FHasDetails or not FCanWrite or not Assigned(FOnComment) then
    Exit;
  FOnComment(StringReplace(mText, #13#10, #10, [rfReplaceAll]));
end;

procedure TAtlasIssueFrame.SetCanWrite(AValue: Boolean);
begin
  FCanWrite := AValue;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.SetCanEnd(AValue: Boolean);
begin
  FCanEnd := AValue;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.SetCommentSending(AValue: Boolean);
begin
  FCommentSending := AValue;
  FCommentEdit.ReadOnly := AValue;
  if AValue then
    FCommentNote.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewCommentSending);
  UpdateButtons;
end;

procedure TAtlasIssueFrame.CommentDone(const AError: string);
begin
  SetCommentSending(False);
  FCommentNote.Caption := AError;
  // Gesendet: Feld leeren und den Entwurf löschen; bei einem Fehler bleibt beides.
  if AError = '' then
    FComment.Sent;
end;

procedure TAtlasIssueFrame.BrowseClick(Sender: TObject);
begin
  if Assigned(FOnBrowse) then
    FOnBrowse();
end;

procedure TAtlasIssueFrame.CopyKeyClick(Sender: TObject);
begin
  if Assigned(FOnCopyKey) then
    FOnCopyKey();
end;

procedure TAtlasIssueFrame.AttachClick(Sender: TObject);
begin
  if FCanAttach and FHasDetails and Assigned(FOnAttach) then
    FOnAttach();
end;

procedure TAtlasIssueFrame.SetCanAttach(AValue: Boolean);
begin
  FCanAttach := AValue;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.RefreshClick(Sender: TObject);
begin
  if FLoading then
  begin
    if Assigned(FOnCancel) then
      FOnCancel();
  end
  else if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TAtlasIssueFrame.FixClick(Sender: TObject);
begin
  if Assigned(FOnFix) then
    FOnFix(FFixKind);
end;

procedure TAtlasIssueFrame.TitleClick(Sender: TObject);
begin
  if Assigned(FOnBrowse) then
    FOnBrowse();
end;

procedure TAtlasIssueFrame.OlderClick(Sender: TObject);
begin
  FCommentsExpanded := True;
  // Nicht im Klick des Labels, das dabei freigegeben wird.
  FPendingRebuild := True;
  Defer;
end;

procedure TAtlasIssueFrame.ImageEnlarge(Sender: TObject);
var
  mForm: TImageWindow;
  mBox: TScrollBox;
  mImage: TImage;
  mSource: TAtlasIssueImageBox;
begin
  mSource := Sender as TAtlasIssueImageBox;
  if mSource.Graphic = nil then
    Exit;
  mForm := TImageWindow.CreateNew(nil);
  mForm.Caption := mSource.Alt;
  mForm.Position := poScreenCenter;
  mForm.Width := Min(mSource.Graphic.Width + 40, Screen.WorkAreaWidth - 80);
  mForm.Height := Min(mSource.Graphic.Height + 60, Screen.WorkAreaHeight - 80);
  mBox := TScrollBox.Create(mForm);
  mBox.Parent := mForm;
  mBox.Align := alClient;
  mImage := TImage.Create(mForm);
  mImage.Parent := mBox;
  mImage.AutoSize := True;
  mImage.Picture.Assign(mSource.Graphic);
  mForm.Show;
end;

procedure TAtlasIssueFrame.AttachmentsDblClick(Sender: TObject);
begin
  if (FAttachments = nil) or (FAttachments.Selected = nil) then
    Exit;
  if (FAttachments.Selected.Index <= High(FDetails.Attachments)) and Assigned(FOnOpenAttachment) then
    FOnOpenAttachment(FDetails.Attachments[FAttachments.Selected.Index]);
end;

procedure TAtlasIssueFrame.AttachmentsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    AttachmentsDblClick(Sender);
    Key := 0;
  end;
end;

procedure TAtlasIssueFrame.LinksClick(Sender: TObject);
var
  mLink: TAtlasTrackerLink;
begin
  if (FLinks = nil) or (FLinks.Selected = nil) or (FLinks.Selected.Index > High(FDetails.Links)) then
    Exit;
  mLink := FDetails.Links[FLinks.Selected.Index];
  // Öffnen ersetzt den Inhalt samt Liste: nicht im Klick der Liste.
  FPendingLink := mLink;
  FHasPendingLink := True;
  Defer;
end;

procedure TAtlasIssueFrame.LinkOpened(const AUrl: string);
var
  mTask: Integer;
begin
  // Kästchen einer Checkliste (#1273): nach dem Klick melden, das Zurückschreiben baut den Inhalt neu.
  if TAtlasTrackerMarkdown.TaskIndexOf(AUrl, mTask) then
  begin
    if FChecklists and not FChecklistReadOnly and not FChecklistBusy then
    begin
      FPendingTask := mTask;
      Defer;
    end;
    Exit;
  end;
  if Assigned(FOnOpenUrl) then
    FOnOpenUrl(AUrl);
end;

procedure TAtlasIssueFrame.ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  FScroll.VertScrollBar.Position := FScroll.VertScrollBar.Position - WheelDelta div 2;
  Handled := True;
end;

end.
