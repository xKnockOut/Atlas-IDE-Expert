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
//   Events.ToggleTask (die IDE-Schicht schreibt zurück), darunter „Punkt
//   hinzufügen …“ (Events.AddTask); ohne Schreibrecht nur lesend mit Tooltip;
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
// Gesucht wird erst, wenn der Reiter sichtbar wird (Events.DevelopmentShown).
// „Anhängen …“ (#1276) als Knopf und im Kontextmenü nur mit CanAttach
// (issues.attach); die IDE-Schicht öffnet den Dialog für dieses Issue.
// Ein Fenster, der Inhalt wechselt; Verlauf über Zurück/Vor (Alt+Links,
// Alt+Rechts). Schließen des Fensters (Events.Hidden) bricht das Laden ab. Laden, Netz, Verlauf und Zwischenspeicher
// liegen in der
// IDE-Schicht; der Frame meldet nur Wünsche (Events). Text in der Beschreibung
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
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.DocBox,
  Atlas.UI.Tracker.CommentEditor,
  Atlas.UI.Tracker.DevelopmentView,
  Atlas.UI.Tracker.IssueBoxes;

const
  /// <summary>Nachricht an den Frame: Inhalt neu bzw. verknüpftes Issue öffnen, nach dem auslösenden Klick (das
  /// Steuerelement des Klicks wird dabei freigegeben). Mit dem Fenster verfällt sie.</summary>
  cWM_ATLAS_ISSUE_DEFERRED = WM_APP + 1264;

type
  {$SCOPEDENUMS ON}
  /// <summary>Schalter des Frames (SetFlag).</summary>
  TAtlasIssueFlag = (
    /// <summary>„Beginnen“ möglich.</summary>
    CanStart,
    /// <summary>Der Tracker kann schreiben und issues.syncState ist an (#1266): Kommentarfeld und „Beenden …“.
    /// </summary>
    CanWrite,
    /// <summary>Das gezeigte Issue ist das aktuelle: „Beenden …“ geht.</summary>
    CanEnd,
    /// <summary>„Anhängen …“ zeigen (issues.attach, #1276).</summary>
    CanAttach,
    /// <summary>issues.preview.checklists (#1273): Häkchen und Zurückschreiben; aus = Text wie geschrieben.</summary>
    Checklists,
    /// <summary>Keine Schreibrechte: Kästchen nur lesend mit Tooltip, kein „Punkt hinzufügen …“.</summary>
    ChecklistReadOnly,
    /// <summary>Zurückschreiben läuft (#1273): Zeile „Wird gespeichert …“, Klicks auf Kästchen ruhen.</summary>
    ChecklistBusy,
    /// <summary>Kommentar wird gesendet (#1266): Feld und Knopf gesperrt.</summary>
    CommentSending,
    /// <summary>Laden läuft (Leiste, „Aktualisieren“ wird „Abbrechen“); der bisherige Inhalt bleibt.</summary>
    Loading,
    /// <summary>Verknüpfungen als Baum statt Liste (issues.preview.links, #1279); gilt ab dem nächsten
    /// ShowDetails.</summary>
    LinksAsTree,
    /// <summary>Der Tracker kann Unteraufgaben anlegen und verknüpfen: Knöpfe über dem Baum.</summary>
    CanWriteLinks,
    /// <summary>issues.preview.development: Reiter „Entwicklung“ zeigen.</summary>
    Development);
  {$SCOPEDENUMS OFF}
  TAtlasIssueFlags = set of TAtlasIssueFlag;

  /// <summary>Feste Steuerelemente des Frames; sie gehören dem Frame.</summary>
  TAtlasIssueFrameParts = record
    Tools: TPanel;
    Back: TButton;
    Forward: TButton;
    Start: TButton;
    /// <summary>„Beenden …“ (#1266).</summary>
    Finish: TButton;
    Browse: TButton;
    CopyKey: TButton;
    Attach: TButton;
    Menu: TPopupMenu;
    AttachItem: TMenuItem;
    Refresh: TButton;
    CommentPanel: TPanel;
    CommentHint: TLabel;
    /// <summary>Kommentar-Editor (#1278); CommentEdit ist sein Memo.</summary>
    Comment: TAtlasCommentEditor;
    CommentEdit: TMemo;
    CommentSend: TButton;
    CommentNote: TLabel;
    Progress: TProgressBar;
    Status: TPanel;
    StatusLabel: TLabel;
    Fix: TButton;
    Pages: TPageControl;
    DetailsSheet: TTabSheet;
    DevelopmentSheet: TTabSheet;
    /// <summary>Inhalt des Reiters „Entwicklung“ (#1269).</summary>
    Development: TAtlasIssueDevelopmentView;
    Scroll: TScrollBox;
    Empty: TLabel;
    Actions: TActionList;
    BackAction: TAction;
    ForwardAction: TAction;
  end;

  /// <summary>Inhalt des gezeigten Issues; entsteht bei jedem Neuaufbau, nil ohne den Teil.</summary>
  TAtlasIssueFrameContent = record
    /// <summary>Alle Teile des Inhalts (für das Aufräumen).</summary>
    Controls: TList<TControl>;
    Images: TList<TAtlasIssueImageBox>;
    Docs: TList<TAtlasIssueDocBox>;
    KeyLabel: TLabel;
    TitleLabel: TLabel;
    Badges: TAtlasIssueBadgeBar;
    Attachments: TListView;
    Links: TListView;
    /// <summary>Verknüpfungen als Baum (#1279): Node.Data = Index + 1 in TreeLinks, Gruppen nil.</summary>
    LinkTree: TTreeView;
    TreeLinks: TArray<TAtlasTrackerLink>;
    CreateSubtask: TButton;
    AddLink: TButton;
    /// <summary>„n ältere Kommentare“.</summary>
    Older: TLabel;
    /// <summary>Doku-Fläche mit dem ersten Kästchen; nil ohne.</summary>
    TaskBox: TAtlasIssueDocBox;
    /// <summary>„Punkt hinzufügen …“; nil ohne Checkliste, ohne Schreibrecht oder ohne Checklists.</summary>
    AddTask: TLabel;
    /// <summary>Kopf des hervorgehobenen Kommentars (#1271).</summary>
    AnchorLabel: TLabel;
    /// <summary>Hervorgehobener Kommentar (Index in Details.Comments); -1 ohne.</summary>
    AnchorComment: Integer;
    /// <summary>Fortschritt in der Kopfzeile ("3/5"; '' ohne Checkliste oder ohne Checklists).</summary>
    ProgressText: string;
    NextTop: Integer;
  end;

  /// <summary>Zustand des Frames zwischen den Aufrufen.</summary>
  TAtlasIssueFrameState = record
    Details: TAtlasTrackerDetails;
    HasDetails: Boolean;
    /// <summary>Jetzt (UTC) für relative Zeiten.</summary>
    Now: TDateTime;
    CommentsExpanded: Boolean;
    CommentsOff: Boolean;
    FixKind: TAtlasIssueFix;
    /// <summary>Anker einer Meldung (#1271): Zeit des ersten neuen Kommentars (UTC); 0 = oben.</summary>
    Anchor: TDateTime;
    /// <summary>Nach dem auslösenden Klick (cWM_ATLAS_ISSUE_DEFERRED): neu aufbauen, Link öffnen, Kästchen
    /// melden, „Punkt hinzufügen …“ melden.</summary>
    PendingRebuild: Boolean;
    PendingLink: TAtlasTrackerLink;
    HasPendingLink: Boolean;
    PendingTask: Integer;
    PendingAdd: Boolean;
    /// <summary>Zur Checkliste blättern, sobald sie zu sehen ist.</summary>
    RevealTasks: Boolean;
  end;

  /// <summary>Wünsche des Frames an die IDE-Schicht; nil = nichts.</summary>
  TAtlasIssueFrameEvents = record
    Back: TProc;
    Forward: TProc;
    Start: TProc;
    /// <summary>„Beenden …“ (#1266) für das gezeigte, aktuelle Issue.</summary>
    Finish: TProc;
    /// <summary>Kommentar senden (#1266); Ergebnis über CommentDone.</summary>
    Comment: TProc<string>;
    Browse: TProc;
    CopyKey: TProc;
    /// <summary>„Anhängen …“ für das gezeigte Issue (#1276).</summary>
    Attach: TProc;
    Refresh: TProc;
    Cancel: TProc;
    Fix: TProc<TAtlasIssueFix>;
    OpenLink: TProc<TAtlasTrackerLink>;
    OpenAttachment: TProc<TAtlasTrackerAttachment>;
    /// <summary>Link aus Beschreibung oder Kommentar bzw. Titel; die IDE-Schicht prüft und öffnet.</summary>
    OpenUrl: TProc<string>;
    /// <summary>Adressen der Bilder, die geladen werden sollen (nach ShowDetails).</summary>
    Images: TProc<TArray<string>>;
    /// <summary>Fenster geschlossen bzw. Frame freigegeben: laufendes Laden abbrechen.</summary>
    Hidden: TProc;
    /// <summary>Kästchen Nummer N (ab 0, TAtlasTrackerChecklist) der Beschreibung angeklickt (#1273); nach dem
    /// Klick gemeldet.</summary>
    ToggleTask: TProc<Integer>;
    /// <summary>„Punkt hinzufügen …“ angeklickt (#1273); nach dem Klick gemeldet.</summary>
    AddTask: TProc;
    /// <summary>„Unteraufgabe anlegen …“ bzw. „Verknüpfen …“ (#1279); Dialog und Senden in der IDE-Schicht.
    /// </summary>
    CreateSubtask: TProc;
    AddLink: TProc;
    /// <summary>Reiter „Entwicklung“ wurde gewählt: suchen, wenn noch nicht geschehen.</summary>
    DevelopmentShown: TProc;
  end;

  TAtlasIssueFrame = class(TFrame)
  private
    FParts: TAtlasIssueFrameParts;
    FContent: TAtlasIssueFrameContent;
    FState: TAtlasIssueFrameState;
    FFlags: TAtlasIssueFlags;
    FEvents: TAtlasIssueFrameEvents;
    FColors: TAtlasColors;
    FMono: TFont;
    /// <summary>Klick auf Knopf, Label, Liste, Bild, Reiter oder Aktion (Tag: Werkzeug bzw. Inhalt).</summary>
    procedure ControlClick(Sender: TObject);
    /// <summary>Eingabe in Anhängen und Verknüpfungsbaum: wie Klick.</summary>
    procedure ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LinkTreeExpanded(Sender: TObject; Node: TTreeNode);
    procedure ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure WMDeferred(var AMessage: TMessage); message cWM_ATLAS_ISSUE_DEFERRED;
    procedure CMShowingChanged(var AMessage: TMessage); message CM_SHOWINGCHANGED;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Noch kein Issue (Fenster aus dem Desktop der IDE).</summary>
    procedure ShowEmpty;
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
    /// <summary>Hinweis über dem Inhalt ohne Knopf (#1273: „Beschreibung wurde geändert …“).</summary>
    procedure ShowNotice(const AText: string);
    /// <summary>Bild zu AUrl ist geladen (übernimmt AGraphic); nil = bleibt als Link.</summary>
    procedure SetImage(const AUrl: string; AGraphic: TGraphic);
    procedure SetHistory(ACanBack, ACanForward: Boolean);
    /// <summary>Ergebnis des Sendens: AError '' = gesendet (Feld leer), sonst der Grund unter dem Feld.</summary>
    procedure CommentDone(const AError: string);
    /// <summary>Beschreibung nach dem Zurückschreiben (#1273): neu setzen, Bildlauf bleibt.</summary>
    procedure ReplaceDescription(const AText: string);
    /// <summary>Zur Checkliste blättern (Klick im Statusfeld, #1273); gilt auch für den nächsten Inhalt.</summary>
    procedure RevealChecklist;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Schalter AFlag setzen und sofort anwenden.</summary>
    procedure SetFlag(AFlag: TAtlasIssueFlag; AValue: Boolean);
    /// <summary>Editorschrift für Code (Vorgabe Consolas); übernimmt eine Kopie.</summary>
    procedure SetMonoFont(AValue: TFont);
    /// <summary>Text der Statuszeile; '' wenn sie verborgen ist.</summary>
    function StatusText: string;
    /// <summary>Reiter „Entwicklung“ ist ausgewählt (und sichtbar).</summary>
    function DevelopmentActive: Boolean;
    /// <summary>Reiter wählen (Tests, Tastatur): ADevelopment = „Entwicklung“, sonst „Details“.</summary>
    procedure SelectTab(ADevelopment: Boolean);
    property Parts: TAtlasIssueFrameParts read FParts;
    property Content: TAtlasIssueFrameContent read FContent;
    property State: TAtlasIssueFrameState read FState;
    property Flags: TAtlasIssueFlags read FFlags;
    property Events: TAtlasIssueFrameEvents read FEvents write FEvents;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.UITypes,
  Atlas.Core.Style.Color,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Links,
  Atlas.UI.Tracker.Strings;

{$R *.dfm}

type
  {$SCOPEDENUMS ON}
  /// <summary>Feste Knöpfe, Reiter und Aktionen (Tag = cToolTag + Ord).</summary>
  TIssueTool = (Back, Forward, Start, Finish, Browse, CopyKey, Attach, Refresh, Fix, CommentSend, Pages);
  /// <summary>Teile des Inhalts (Tag = cContentTag + Ord).</summary>
  TIssueContent = (Title, Older, AddTask, Image, Attachment, Link, LinkTree, CreateSubtask, AddLink);
  {$SCOPEDENUMS OFF}

const
  cToolTag = 1;
  cContentTag = 100;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

procedure Fire(const AEvent: TProc);
begin
  if Assigned(AEvent) then
  begin
    AEvent();
  end;
end;

/// <summary>AEvent nur, wenn ACondition gilt.</summary>
procedure FireIf(ACondition: Boolean; const AEvent: TProc);
begin
  if ACondition then
  begin
    Fire(AEvent);
  end;
end;

function HasFlag(AFrame: TAtlasIssueFrame; AFlag: TAtlasIssueFlag): Boolean;
begin
  Result := AFlag in AFrame.FFlags;
end;

/// <summary>Nach dem Klick weiterarbeiten (cWM_ATLAS_ISSUE_DEFERRED).</summary>
procedure Defer(AFrame: TAtlasIssueFrame);
begin
  if AFrame.HandleAllocated then
  begin
    PostMessage(AFrame.Handle, cWM_ATLAS_ISSUE_DEFERRED, 0, 0);
  end;
end;

{ Aufbau }

/// <summary>Knopf in der Werkzeugleiste hinter den bisherigen.</summary>
function AddTool(AFrame: TAtlasIssueFrame; const ACaption: string; ATool: TIssueTool): TButton;
begin
  Result := TButton.Create(AFrame);
  Result.Parent := AFrame.FParts.Tools;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  // Reihenfolge wie angelegt: hinter den bisherigen.
  Result.Left := AFrame.FParts.Tools.ControlCount * 200;
  Result.Caption := ACaption;
  Result.ShowHint := True;
  Result.Width := Result.ScaleValue(Max(80, Length(ACaption) * 8));
  Result.Tag := cToolTag + Ord(ATool);
  Result.OnClick := AFrame.ControlClick;
end;

/// <summary>Kontextmenü des Fensters (#1276): Kinder ohne eigenes Menü übernehmen es.</summary>
procedure AddMenu(AFrame: TAtlasIssueFrame);
begin
  AFrame.FParts.Menu := TPopupMenu.Create(AFrame);
  AFrame.FParts.AttachItem := TMenuItem.Create(AFrame.FParts.Menu);
  AFrame.FParts.AttachItem.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachCommand);
  AFrame.FParts.AttachItem.Tag := cToolTag + Ord(TIssueTool.Attach);
  AFrame.FParts.AttachItem.OnClick := AFrame.ControlClick;
  AFrame.FParts.AttachItem.Visible := False;
  AFrame.FParts.Menu.Items.Add(AFrame.FParts.AttachItem);
  AFrame.PopupMenu := AFrame.FParts.Menu;
end;

/// <summary>Werkzeugleiste: Zurück, Vor, Beginnen, Beenden, Browser, Kennung, Anhängen, Aktualisieren.</summary>
procedure AddToolbar(AFrame: TAtlasIssueFrame);
begin
  AFrame.FParts.Tools := TPanel.Create(AFrame);
  AFrame.FParts.Tools.Parent := AFrame;
  AFrame.FParts.Tools.Align := alTop;
  AFrame.FParts.Tools.BevelOuter := bvNone;
  AFrame.FParts.Tools.Height := AFrame.FParts.Tools.ScaleValue(32);
  AFrame.FParts.Tools.ShowCaption := False;
  AFrame.FParts.Back := AddTool(AFrame, '◀', TIssueTool.Back);
  AFrame.FParts.Back.Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewBack);
  AFrame.FParts.Back.Width := AFrame.FParts.Back.ScaleValue(32);
  AFrame.FParts.Forward := AddTool(AFrame, '▶', TIssueTool.Forward);
  AFrame.FParts.Forward.Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewForward);
  AFrame.FParts.Forward.Width := AFrame.FParts.Forward.ScaleValue(32);
  AFrame.FParts.Start := AddTool(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewStart),
    TIssueTool.Start);
  AFrame.FParts.Finish := AddTool(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewEnd),
    TIssueTool.Finish);
  AFrame.FParts.Finish.Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewEndHint);
  AFrame.FParts.Finish.Visible := False;
  AFrame.FParts.Browse := AddTool(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewBrowse),
    TIssueTool.Browse);
  AFrame.FParts.CopyKey := AddTool(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCopyKey),
    TIssueTool.CopyKey);
  AFrame.FParts.Attach := AddTool(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachPreviewButton),
    TIssueTool.Attach);
  AFrame.FParts.Attach.Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachStatusHint);
  AFrame.FParts.Attach.Visible := False;
  AddMenu(AFrame);
  AFrame.FParts.Refresh := AddTool(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewRefresh),
    TIssueTool.Refresh);
end;

/// <summary>Leiste beim Laden und Zeile für Stand, Fehler und Hinweise mit Knopf zum Beheben.</summary>
procedure AddStatus(AFrame: TAtlasIssueFrame);
begin
  AFrame.FParts.Progress := TProgressBar.Create(AFrame);
  AFrame.FParts.Progress.Parent := AFrame;
  AFrame.FParts.Progress.Align := alTop;
  AFrame.FParts.Progress.Top := AFrame.FParts.Tools.Height;
  AFrame.FParts.Progress.Height := AFrame.FParts.Progress.ScaleValue(3);
  AFrame.FParts.Progress.Style := pbstMarquee;
  AFrame.FParts.Progress.Visible := False;
  AFrame.FParts.Status := TPanel.Create(AFrame);
  AFrame.FParts.Status.Parent := AFrame;
  AFrame.FParts.Status.Align := alTop;
  AFrame.FParts.Status.Top := AFrame.FParts.Tools.Height + AFrame.FParts.Status.ScaleValue(10);
  AFrame.FParts.Status.BevelOuter := bvNone;
  AFrame.FParts.Status.Height := AFrame.FParts.Status.ScaleValue(30);
  AFrame.FParts.Status.ShowCaption := False;
  AFrame.FParts.Status.Visible := False;
  AFrame.FParts.Fix := TButton.Create(AFrame);
  AFrame.FParts.Fix.Parent := AFrame.FParts.Status;
  AFrame.FParts.Fix.Align := alRight;
  AFrame.FParts.Fix.AlignWithMargins := True;
  AFrame.FParts.Fix.Width := AFrame.FParts.Fix.ScaleValue(150);
  AFrame.FParts.Fix.Tag := cToolTag + Ord(TIssueTool.Fix);
  AFrame.FParts.Fix.OnClick := AFrame.ControlClick;
  AFrame.FParts.StatusLabel := TLabel.Create(AFrame);
  AFrame.FParts.StatusLabel.Parent := AFrame.FParts.Status;
  AFrame.FParts.StatusLabel.Align := alClient;
  AFrame.FParts.StatusLabel.AlignWithMargins := True;
  AFrame.FParts.StatusLabel.Layout := tlCenter;
  AFrame.FParts.StatusLabel.ShowAccelChar := False;
  AFrame.FParts.StatusLabel.EllipsisPosition := epEndEllipsis;
end;

function AddCommentLabel(AFrame: TAtlasIssueFrame; AAlign: TAlign; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AFrame);
  Result.Parent := AFrame.FParts.CommentPanel;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

/// <summary>Kommentar schreiben (#1266): unten, nur mit CanWrite.</summary>
procedure AddCommentPanel(AFrame: TAtlasIssueFrame);
begin
  AFrame.FParts.CommentPanel := TPanel.Create(AFrame);
  AFrame.FParts.CommentPanel.Parent := AFrame;
  AFrame.FParts.CommentPanel.Align := alBottom;
  AFrame.FParts.CommentPanel.BevelOuter := bvNone;
  AFrame.FParts.CommentPanel.Height := AFrame.FParts.CommentPanel.ScaleValue(150);
  AFrame.FParts.CommentPanel.ShowCaption := False;
  AFrame.FParts.CommentPanel.Visible := False;
  AFrame.FParts.CommentHint := AddCommentLabel(AFrame, alTop,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCommentHint));
  AFrame.FParts.CommentNote := AddCommentLabel(AFrame, alBottom, '');
  AFrame.FParts.CommentSend := TButton.Create(AFrame);
  AFrame.FParts.CommentSend.Parent := AFrame.FParts.CommentPanel;
  AFrame.FParts.CommentSend.Align := alRight;
  AFrame.FParts.CommentSend.AlignWithMargins := True;
  AFrame.FParts.CommentSend.Width := AFrame.FParts.CommentSend.ScaleValue(90);
  AFrame.FParts.CommentSend.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCommentSend);
  AFrame.FParts.CommentSend.Tag := cToolTag + Ord(TIssueTool.CommentSend);
  AFrame.FParts.CommentSend.OnClick := AFrame.ControlClick;
  // Kommentar-Editor (#1278): Strg+Enter sendet; Vorschläge, Textbausteine und Entwurf, sobald die IDE ihn bindet.
  AFrame.FParts.Comment := TAtlasCommentEditor.Create(AFrame);
  AFrame.FParts.Comment.Parent := AFrame.FParts.CommentPanel;
  AFrame.FParts.Comment.Align := alClient;
  AFrame.FParts.Comment.AlignWithMargins := True;
  AFrame.FParts.Comment.Tag := cToolTag + Ord(TIssueTool.CommentSend);
  AFrame.FParts.Comment.Events := TAtlasCommentEditorEvents.Create(AFrame.ControlClick, nil);
  AFrame.FParts.CommentEdit := AFrame.FParts.Comment.Memo;
end;

function AddSheet(AFrame: TAtlasIssueFrame; AText: TAtlasTrackerTextId): TTabSheet;
begin
  Result := TTabSheet.Create(AFrame);
  Result.TabVisible := False;
  Result.PageControl := AFrame.FParts.Pages;
  Result.Caption := TAtlasTrackerStrings.Text(AText);
end;

/// <summary>Reiter „Details“ (Bildlauf mit dem Inhalt) und „Entwicklung“ (#1269).</summary>
procedure AddPages(AFrame: TAtlasIssueFrame);
begin
  AFrame.FParts.Pages := TPageControl.Create(AFrame);
  AFrame.FParts.Pages.Parent := AFrame;
  AFrame.FParts.Pages.Align := alClient;
  // Ohne Reiter einhängen: Ein sichtbarer Reiter braucht das Fenster des PageControls (ApplyTabs in CreateWnd).
  AFrame.FParts.DetailsSheet := AddSheet(AFrame, TAtlasTrackerTextId.IssuePreviewTabDetails);
  AFrame.FParts.DevelopmentSheet := AddSheet(AFrame, TAtlasTrackerTextId.IssuePreviewTabDevelopment);
  AFrame.FParts.Pages.Tag := cToolTag + Ord(TIssueTool.Pages);
  AFrame.FParts.Pages.OnChange := AFrame.ControlClick;
  AFrame.FParts.Development := TAtlasIssueDevelopmentView.Create(AFrame);
  AFrame.FParts.Development.Parent := AFrame.FParts.DevelopmentSheet;
  AFrame.FParts.Development.Align := alClient;
  AFrame.FParts.Scroll := TScrollBox.Create(AFrame);
  AFrame.FParts.Scroll.Parent := AFrame.FParts.DetailsSheet;
  AFrame.FParts.Scroll.Align := alClient;
  AFrame.FParts.Scroll.BorderStyle := bsNone;
  AFrame.FParts.Scroll.VertScrollBar.Tracking := True;
  AFrame.FParts.Scroll.HorzScrollBar.Visible := False;
  AFrame.FParts.Scroll.Padding.SetBounds(8, 4, 8, 8);
  AFrame.FParts.Scroll.OnMouseWheel := AFrame.ScrollWheel;
  AFrame.FParts.Empty := TLabel.Create(AFrame);
  AFrame.FParts.Empty.Parent := AFrame.FParts.Scroll;
  AFrame.FParts.Empty.Align := alTop;
  AFrame.FParts.Empty.AlignWithMargins := True;
  AFrame.FParts.Empty.WordWrap := True;
  AFrame.FParts.Empty.ShowAccelChar := False;
  AFrame.FParts.Empty.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewEmpty);
end;

function AddAction(AFrame: TAtlasIssueFrame; AKey: Word; ATool: TIssueTool): TAction;
begin
  Result := TAction.Create(AFrame);
  Result.ActionList := AFrame.FParts.Actions;
  Result.ShortCut := ShortCut(AKey, [ssAlt]);
  Result.Tag := cToolTag + Ord(ATool);
  Result.OnExecute := AFrame.ControlClick;
end;

{ Inhalt }

procedure Place(AFrame: TAtlasIssueFrame; AControl: TControl);
begin
  // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
  Inc(AFrame.FContent.NextTop, 1000);
  AControl.Parent := AFrame.FParts.Scroll;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := AFrame.FContent.NextTop;
  AFrame.FContent.Controls.Add(AControl);
end;

function AddLabel(AFrame: TAtlasIssueFrame; const ACaption: string; ABold: Boolean): TLabel;
begin
  Result := TLabel.Create(AFrame);
  Place(AFrame, Result);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  Result.Font.Color := ToColor(AFrame.FColors.Text);
  if ABold then
  begin
    Result.Font.Style := [fsBold];
  end;
end;

/// <summary>Gedämpfte Zeile (Überschrift eines Abschnitts, Hinweis).</summary>
procedure AddMuted(AFrame: TAtlasIssueFrame; const ACaption: string; ABold: Boolean);
begin
  AddLabel(AFrame, ACaption, ABold).Font.Color := ToColor(AFrame.FColors.Muted);
end;

/// <summary>Unterstrichener Verweis in Akzentfarbe, Klick über ControlClick.</summary>
function AddLinkLabel(AFrame: TAtlasIssueFrame; const ACaption: string; AContent: TIssueContent): TLabel;
begin
  Result := AddLabel(AFrame, ACaption, False);
  Result.Font.Color := ToColor(AFrame.FColors.Accent);
  Result.Font.Style := [fsUnderline];
  Result.Cursor := crHandPoint;
  Result.Tag := cContentTag + Ord(AContent);
  Result.OnClick := AFrame.ControlClick;
end;

function AddList(AFrame: TAtlasIssueFrame; const AColumns: TArray<string>; AContent: TIssueContent): TListView;
var
  mCaption: string;
  mColumn: TListColumn;
begin
  Result := TListView.Create(AFrame);
  Place(AFrame, Result);
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
  Result.Tag := cContentTag + Ord(AContent);
end;

/// <summary>Link aus Beschreibung oder Kommentar; Kästchen einer Checkliste (#1273) melden nach dem Klick.</summary>
procedure LinkOpened(AFrame: TAtlasIssueFrame; const AUrl: string);
var
  mTask: Integer;
  mTasks: Boolean;
begin
  mTasks := HasFlag(AFrame, TAtlasIssueFlag.Checklists) and not HasFlag(AFrame, TAtlasIssueFlag.ChecklistReadOnly)
    and not HasFlag(AFrame, TAtlasIssueFlag.ChecklistBusy);
  if not TAtlasTrackerMarkdown.TaskIndexOf(AUrl, mTask) then
  begin
    if Assigned(AFrame.FEvents.OpenUrl) then
    begin
      AFrame.FEvents.OpenUrl(AUrl);
    end;
  end
  else if mTasks then
  begin
    // Das Zurückschreiben baut den Inhalt neu: nicht im Klick.
    AFrame.FState.PendingTask := mTask;
    Defer(AFrame);
  end;
end;

/// <summary>Doku-Fläche; Klick auf einen Link über LinkOpened.</summary>
function AddDocBox(AFrame: TAtlasIssueFrame; const ASegment: TAtlasMarkdownSegment): TAtlasIssueDocBox;
begin
  Result := TAtlasIssueDocBox.Create(AFrame);
  Place(AFrame, Result);
  Result.SetDoc(ASegment.Doc, AFrame.FColors, AFrame.FMono);
  Result.OnLink :=
    procedure(AUrl: string)
    begin
      LinkOpened(AFrame, AUrl);
    end;
  AFrame.FContent.Docs.Add(Result);
end;

/// <summary>Kästchen der Beschreibung: lesend mit Tooltip oder anklickbar; die erste Fläche merken.</summary>
procedure PrepareTasks(AFrame: TAtlasIssueFrame; ADoc: TAtlasIssueDocBox);
var
  mReadOnly: Boolean;
begin
  mReadOnly := HasFlag(AFrame, TAtlasIssueFlag.ChecklistReadOnly);
  ADoc.TasksLocked := mReadOnly;
  if mReadOnly then
  begin
    ADoc.TaskHint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistReadOnly);
  end
  else
  begin
    ADoc.TaskHint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistToggleHint);
  end;
  if (AFrame.FContent.TaskBox = nil) and ADoc.HasTasks then
  begin
    AFrame.FContent.TaskBox := ADoc;
  end;
end;

/// <summary>Bild als Vorschau; relative Namen (YouTrack) sind Anhänge.</summary>
procedure AddImage(AFrame: TAtlasIssueFrame; const ASegment: TAtlasMarkdownSegment);
var
  mImage: TAtlasIssueImageBox;
begin
  mImage := TAtlasIssueImageBox.Create(AFrame);
  Place(AFrame, mImage);
  mImage.Url := TAtlasIssuePreview.ImageUrl(AFrame.FState.Details, ASegment.Image.Url);
  mImage.Alt := ASegment.Image.Text;
  if mImage.Alt = '' then
  begin
    mImage.Alt := ASegment.Image.Url;
  end;
  mImage.Colors := AFrame.FColors;
  mImage.Tag := cContentTag + Ord(TIssueContent.Image);
  mImage.OnEnlarge := AFrame.ControlClick;
  AFrame.FContent.Images.Add(mImage);
end;

procedure AddMarkdown(AFrame: TAtlasIssueFrame; const AText: string; ATasks: TAtlasMarkdownTasks);
var
  mSegment: TAtlasMarkdownSegment;
  mDoc: TAtlasIssueDocBox;
begin
  for mSegment in TAtlasTrackerMarkdown.Segments(AText, ATasks) do
  begin
    if mSegment.Kind <> TAtlasMarkdownSegmentKind.Doc then
    begin
      AddImage(AFrame, mSegment);
    end
    else
    begin
      mDoc := AddDocBox(AFrame, mSegment);
      if ATasks = TAtlasMarkdownTasks.Clickable then
      begin
        PrepareTasks(AFrame, mDoc);
      end;
    end;
  end;
end;

procedure ClearContent(AFrame: TAtlasIssueFrame);
var
  mPart: TControl;
  mControls: TList<TControl>;
  mImages: TList<TAtlasIssueImageBox>;
  mDocs: TList<TAtlasIssueDocBox>;
begin
  mControls := AFrame.FContent.Controls;
  mImages := AFrame.FContent.Images;
  mDocs := AFrame.FContent.Docs;
  for mPart in mControls do
  begin
    mPart.Free;
  end;
  mControls.Clear;
  mImages.Clear;
  mDocs.Clear;
  AFrame.FContent := Default(TAtlasIssueFrameContent);
  AFrame.FContent.Controls := mControls;
  AFrame.FContent.Images := mImages;
  AFrame.FContent.Docs := mDocs;
  AFrame.FContent.AnchorComment := -1;
end;

function AgeText(AFrame: TAtlasIssueFrame; ATime: TDateTime): string;
begin
  Result := TAtlasIssueTimeText.Age(ATime, AFrame.FState.Now);
end;

function BadgeHint(AKind: TAtlasIssueBadgeKind): string;
begin
  case AKind of
    TAtlasIssueBadgeKind.State:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFieldState);
    TAtlasIssueBadgeKind.Priority:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFieldPriority);
    TAtlasIssueBadgeKind.Kind:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFieldKind);
    TAtlasIssueBadgeKind.Assignee:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFieldAssignee);
    TAtlasIssueBadgeKind.Sprint:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFieldSprint);
    TAtlasIssueBadgeKind.LabelName:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFieldLabel);
  else
    Result := '';
  end;
end;

/// <summary>Text und Tooltip eines Abzeichens; Zeiten relativ, Tooltip absolut.</summary>
procedure BadgeText(AFrame: TAtlasIssueFrame; const ABadge: TAtlasIssueBadge; out AText, AHint: string);
begin
  AText := ABadge.Text;
  AHint := BadgeHint(ABadge.Kind) + ': ' + ABadge.Text;
  if ABadge.Kind = TAtlasIssueBadgeKind.Created then
  begin
    AText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewBadgeCreated, [AgeText(AFrame, ABadge.Time)]);
    AHint := TAtlasIssueTimeText.Absolute(ABadge.Time);
  end
  else if ABadge.Kind = TAtlasIssueBadgeKind.Updated then
  begin
    AText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewBadgeUpdated, [AgeText(AFrame, ABadge.Time)]);
    AHint := TAtlasIssueTimeText.Absolute(ABadge.Time);
  end;
end;

procedure AddBadges(AFrame: TAtlasIssueFrame);
var
  mBadge: TAtlasIssueBadge;
  mTexts, mHints: TArray<string>;
  mText, mHint: string;
begin
  mTexts := nil;
  mHints := nil;
  for mBadge in TAtlasIssuePreview.Badges(AFrame.FState.Details) do
  begin
    BadgeText(AFrame, mBadge, mText, mHint);
    mTexts := mTexts + [mText];
    mHints := mHints + [mHint];
  end;
  AFrame.FContent.Badges := TAtlasIssueBadgeBar.Create(AFrame);
  Place(AFrame, AFrame.FContent.Badges);
  AFrame.FContent.Badges.SetBadges(mTexts, mHints, AFrame.FColors);
end;

/// <summary>Kennung (mit Fortschritt der Checkliste, #1273), Titel und Abzeichen.</summary>
procedure AddHeader(AFrame: TAtlasIssueFrame; const AProgress: TAtlasChecklistProgress);
var
  mKey: TLabel;
  mDetails: TAtlasTrackerDetails;
begin
  mDetails := AFrame.FState.Details;
  AFrame.FContent.ProgressText := AProgress.Text;
  if AFrame.FContent.ProgressText <> '' then
  begin
    mKey := AddLabel(AFrame, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueChecklistStatusLine, [mDetails.Key,
      AFrame.FContent.ProgressText]), False);
    mKey.Hint := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueChecklistProgress,
      [AProgress.Done, AProgress.Total]);
    mKey.ShowHint := True;
  end
  else
  begin
    mKey := AddLabel(AFrame, mDetails.Key, False);
  end;
  mKey.Font.Name := AFrame.FMono.Name;
  mKey.Font.Color := ToColor(AFrame.FColors.Muted);
  AFrame.FContent.KeyLabel := mKey;
  AFrame.FContent.TitleLabel := AddLinkLabel(AFrame, mDetails.Title, TIssueContent.Title);
  AFrame.FContent.TitleLabel.Font.Style := [fsBold];
  AFrame.FContent.TitleLabel.Font.Color := ToColor(AFrame.FColors.Text);
  AFrame.FContent.TitleLabel.Font.Height := MulDiv(AFrame.Font.Height, 13, 10);
  AddBadges(AFrame);
end;

/// <summary>Beschreibung; mit issues.preview.checklists aus die Aufgabenlisten als Text wie geschrieben.</summary>
procedure AddDescription(AFrame: TAtlasIssueFrame; const AProgress: TAtlasChecklistProgress);
var
  mTasks: TAtlasMarkdownTasks;
begin
  mTasks := TAtlasMarkdownTasks.Plain;
  if HasFlag(AFrame, TAtlasIssueFlag.Checklists) then
  begin
    mTasks := TAtlasMarkdownTasks.Clickable;
  end;
  if Trim(AFrame.FState.Details.Description) = '' then
  begin
    AddMuted(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewNoDescription), False);
  end
  else
  begin
    AddMarkdown(AFrame, AFrame.FState.Details.Description, mTasks);
  end;
  if AProgress.Any and not HasFlag(AFrame, TAtlasIssueFlag.ChecklistReadOnly) then
  begin
    AFrame.FContent.AddTask := AddLinkLabel(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistAdd),
      TIssueContent.AddTask);
  end;
end;

/// <summary>„n ältere Kommentare“, wenn welche eingeklappt sind.</summary>
procedure AddOlder(AFrame: TAtlasIssueFrame; ACollapsed: Integer);
var
  mText: string;
begin
  if ACollapsed <= 0 then
  begin
    Exit;
  end;
  if ACollapsed = 1 then
  begin
    mText := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewOlderComment);
  end
  else
  begin
    mText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewOlderComments, [ACollapsed]);
  end;
  AFrame.FContent.Older := AddLinkLabel(AFrame, mText, TIssueContent.Older);
end;

/// <summary>Kopf eines Kommentars; der Anker (#1271) in Akzentfarbe.</summary>
procedure AddCommentHead(AFrame: TAtlasIssueFrame; const AComment: TAtlasTrackerComment; AIndex, AAnchor: Integer);
var
  mHead: TLabel;
begin
  mHead := AddLabel(AFrame, AComment.Author + ' · ' + AgeText(AFrame, AComment.Created), True);
  mHead.Hint := TAtlasIssueTimeText.Absolute(AComment.Created);
  mHead.ShowHint := True;
  if AIndex = AAnchor then
  begin
    mHead.Font.Color := ToColor(AFrame.FColors.Accent);
    AFrame.FContent.AnchorLabel := mHead;
    AFrame.FContent.AnchorComment := AIndex;
  end;
end;

/// <summary>Kommentare: neueste unten, ältere eingeklappt; Checklisten darin nur als Kästchen.</summary>
procedure AddComments(AFrame: TAtlasIssueFrame);
var
  mComments: TArray<TAtlasTrackerComment>;
  mIndex, mCollapsed, mAnchor: Integer;
  mTasks: TAtlasMarkdownTasks;
begin
  mTasks := TAtlasMarkdownTasks.Plain;
  if HasFlag(AFrame, TAtlasIssueFlag.Checklists) then
  begin
    mTasks := TAtlasMarkdownTasks.Boxes;
  end;
  mComments := AFrame.FState.Details.Comments;
  if AFrame.FState.CommentsOff then
  begin
    AddMuted(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCommentsOff), False);
    Exit;
  end;
  if Length(mComments) = 0 then
  begin
    Exit;
  end;
  AddMuted(AFrame, AnsiUpperCase(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewComments,
    [Length(mComments)])), True);
  mAnchor := TAtlasIssuePreview.CommentAt(mComments, AFrame.FState.Anchor);
  // Der neue Kommentar einer Meldung liegt bei den eingeklappten: aufklappen.
  if (mAnchor >= 0) and
    (mAnchor < TAtlasIssuePreview.CollapsedComments(Length(mComments), AFrame.FState.CommentsExpanded)) then
  begin
    AFrame.FState.CommentsExpanded := True;
  end;
  mCollapsed := TAtlasIssuePreview.CollapsedComments(Length(mComments), AFrame.FState.CommentsExpanded);
  AddOlder(AFrame, mCollapsed);
  for mIndex := mCollapsed to High(mComments) do
  begin
    AddCommentHead(AFrame, mComments[mIndex], mIndex, mAnchor);
    AddMarkdown(AFrame, mComments[mIndex].Text, mTasks);
  end;
end;

function SizeText(ASize: Int64): string;
begin
  Result := '–';
  if ASize >= 0 then
  begin
    Result := FormatFloat('#,##0.0', ASize / 1024, FormatSettings) + ' KB';
  end;
end;

/// <summary>Anhänge: Name und Größe; Doppelklick öffnet.</summary>
procedure AddAttachments(AFrame: TAtlasIssueFrame);
var
  mAttachment: TAtlasTrackerAttachment;
  mItem: TListItem;
  mList: TListView;
  mAttachments: TArray<TAtlasTrackerAttachment>;
begin
  mAttachments := AFrame.FState.Details.Attachments;
  if Length(mAttachments) = 0 then
  begin
    Exit;
  end;
  AddMuted(AFrame, AnsiUpperCase(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewAttachments,
    [Length(mAttachments)])), True);
  mList := AddList(AFrame, TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewColumnName),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewColumnSize)), TIssueContent.Attachment);
  mList.Items.BeginUpdate;
  try
    for mAttachment in mAttachments do
    begin
      mItem := mList.Items.Add;
      mItem.Caption := mAttachment.Name;
      mItem.SubItems.Add(SizeText(mAttachment.Size));
    end;
  finally
    mList.Items.EndUpdate;
  end;
  mList.Height := (Length(mAttachments) + 2) * MulDiv(20, AFrame.CurrentPPI, 96);
  mList.OnDblClick := AFrame.ControlClick;
  mList.OnKeyDown := AFrame.ControlKeyDown;
  AFrame.FContent.Attachments := mList;
end;

function RelationText(const ALink: TAtlasTrackerLink): string;
begin
  Result := ALink.Relation;
  if ALink.Relation = 'cross-referenced' then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewRelationMentioned);
  end
  else if ALink.Relation = 'pull request' then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewRelationPull);
  end;
end;

/// <summary>Verknüpfte Issues als Liste: Klick öffnet sie im selben Fenster (bzw. im Browser).</summary>
procedure AddLinkList(AFrame: TAtlasIssueFrame);
var
  mLink: TAtlasTrackerLink;
  mItem: TListItem;
  mList: TListView;
  mLinks: TArray<TAtlasTrackerLink>;
begin
  mLinks := AFrame.FState.Details.Links;
  if Length(mLinks) = 0 then
  begin
    Exit;
  end;
  AddMuted(AFrame, AnsiUpperCase(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewLinks, [Length(mLinks)])),
    True);
  mList := AddList(AFrame, TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewColumnKey),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewColumnTitle),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewColumnRelation)), TIssueContent.Link);
  mList.Items.BeginUpdate;
  try
    for mLink in mLinks do
    begin
      mItem := mList.Items.Add;
      mItem.Caption := mLink.Key;
      mItem.SubItems.Add(mLink.Title);
      mItem.SubItems.Add(RelationText(mLink));
    end;
  finally
    mList.Items.EndUpdate;
  end;
  mList.Height := (Length(mLinks) + 2) * MulDiv(20, AFrame.CurrentPPI, 96);
  mList.OnClick := AFrame.ControlClick;
  AFrame.FContent.Links := mList;
end;

function AddLinkButton(AFrame: TAtlasIssueFrame; AParent: TWinControl; AText: TAtlasTrackerTextId;
  AMinWidth: Integer; AContent: TIssueContent): TButton;
begin
  Result := TButton.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Left := AParent.ControlCount * 200;
  Result.Caption := TAtlasTrackerStrings.Text(AText);
  Result.Width := Max(AMinWidth, Length(Result.Caption) * 8);
  Result.Tag := cContentTag + Ord(AContent);
  Result.OnClick := AFrame.ControlClick;
end;

/// <summary>[Unteraufgabe anlegen …] [Verknüpfen …] über dem Baum (#1279).</summary>
procedure AddLinkTools(AFrame: TAtlasIssueFrame);
var
  mTools: TPanel;
begin
  mTools := TPanel.Create(AFrame);
  Place(AFrame, mTools);
  mTools.BevelOuter := bvNone;
  mTools.ShowCaption := False;
  mTools.Height := MulDiv(30, AFrame.CurrentPPI, 96);
  AFrame.FContent.CreateSubtask := AddLinkButton(AFrame, mTools, TAtlasTrackerTextId.IssueLinksCreateSubtask, 120,
    TIssueContent.CreateSubtask);
  AFrame.FContent.AddLink := AddLinkButton(AFrame, mTools, TAtlasTrackerTextId.IssueLinksAddLink, 100,
    TIssueContent.AddLink);
end;

procedure FitLinkTree(AFrame: TAtlasIssueFrame);
var
  mNode: TTreeNode;
  mRows: Integer;
begin
  if AFrame.FContent.LinkTree = nil then
  begin
    Exit;
  end;
  // Ganze Höhe statt eigener Bildlaufleiste: die Vorschau rollt als Ganzes.
  mRows := 0;
  mNode := AFrame.FContent.LinkTree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    Inc(mRows);
    if mNode.Expanded then
    begin
      Inc(mRows, mNode.Count);
    end;
    mNode := mNode.getNextSibling;
  end;
  AFrame.FContent.LinkTree.Height := (mRows + 1) * MulDiv(20, AFrame.CurrentPPI, 96);
end;

/// <summary>Gruppen und Zeilen des Baums.</summary>
procedure FillLinkTree(AFrame: TAtlasIssueFrame; ATree: TTreeView; const AGroups: TArray<TAtlasTrackerLinkGroup>);
var
  mGroup: TAtlasTrackerLinkGroup;
  mLink: TAtlasTrackerLink;
  mNode, mChild: TTreeNode;
begin
  ATree.Items.BeginUpdate;
  try
    for mGroup in AGroups do
    begin
      mNode := ATree.Items.AddChild(nil, TAtlasIssueLinkText.Group(mGroup));
      mNode.Data := nil;
      for mLink in mGroup.Links do
      begin
        AFrame.FContent.TreeLinks := AFrame.FContent.TreeLinks + [mLink];
        mChild := ATree.Items.AddChild(mNode, TAtlasIssueLinkText.Row(mLink));
        mChild.Data := Pointer(NativeInt(Length(AFrame.FContent.TreeLinks)));
      end;
      // Duplikate, „bezieht sich auf“ und Erwähnungen bleiben eingeklappt.
      mNode.Expanded := not mGroup.Collapsed;
    end;
  finally
    ATree.Items.EndUpdate;
  end;
end;

/// <summary>Verknüpfungen als Baum (#1279); mit CanWriteLinks die Knöpfe darüber.</summary>
procedure AddLinkTree(AFrame: TAtlasIssueFrame);
var
  mGroups: TArray<TAtlasTrackerLinkGroup>;
  mTree: TTreeView;
  mWrite: Boolean;
begin
  mGroups := TAtlasTrackerLinks.Groups(AFrame.FState.Details.Links);
  mWrite := HasFlag(AFrame, TAtlasIssueFlag.CanWriteLinks);
  if (Length(mGroups) = 0) and not mWrite then
  begin
    Exit;
  end;
  AddMuted(AFrame, AnsiUpperCase(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueLinksCaption,
    [Length(AFrame.FState.Details.Links)])), True);
  if mWrite then
  begin
    AddLinkTools(AFrame);
  end;
  if Length(mGroups) = 0 then
  begin
    Exit;
  end;
  mTree := TTreeView.Create(AFrame);
  Place(AFrame, mTree);
  mTree.ReadOnly := True;
  mTree.RowSelect := True;
  mTree.HideSelection := False;
  mTree.ShowHint := True;
  mTree.Color := ToColor(AFrame.FColors.Surface);
  mTree.Font.Color := ToColor(AFrame.FColors.Text);
  AFrame.FContent.LinkTree := mTree;
  FillLinkTree(AFrame, mTree, mGroups);
  mTree.Tag := cContentTag + Ord(TIssueContent.LinkTree);
  mTree.OnClick := AFrame.ControlClick;
  mTree.OnKeyDown := AFrame.ControlKeyDown;
  mTree.OnExpanded := AFrame.LinkTreeExpanded;
  mTree.OnCollapsed := AFrame.LinkTreeExpanded;
  FitLinkTree(AFrame);
end;

/// <summary>Bilder laden lassen (nur die mit Adresse).</summary>
procedure RequestImages(AFrame: TAtlasIssueFrame);
var
  mUrls: TArray<string>;
  mImage: TAtlasIssueImageBox;
begin
  mUrls := nil;
  for mImage in AFrame.FContent.Images do
  begin
    if mImage.Url <> '' then
    begin
      mUrls := mUrls + [mImage.Url];
    end;
  end;
  if (Length(mUrls) > 0) and Assigned(AFrame.FEvents.Images) then
  begin
    AFrame.FEvents.Images(mUrls);
  end;
end;

procedure Rebuild(AFrame: TAtlasIssueFrame);
var
  mProgress: TAtlasChecklistProgress;
begin
  AFrame.FParts.Scroll.DisableAlign;
  try
    ClearContent(AFrame);
    AFrame.FParts.Empty.Visible := not AFrame.FState.HasDetails;
    if AFrame.FState.HasDetails then
    begin
      // Checklisten (#1273): Fortschritt in der Kopfzeile, Kästchen in der Beschreibung.
      mProgress := TAtlasChecklistProgress.Create(0, 0);
      if HasFlag(AFrame, TAtlasIssueFlag.Checklists) then
      begin
        mProgress := TAtlasTrackerChecklist.Progress(AFrame.FState.Details.Description);
      end;
      AddHeader(AFrame, mProgress);
      AddDescription(AFrame, mProgress);
      AddComments(AFrame);
      AddAttachments(AFrame);
      if HasFlag(AFrame, TAtlasIssueFlag.LinksAsTree) then
      begin
        AddLinkTree(AFrame);
      end
      else
      begin
        AddLinkList(AFrame);
      end;
    end;
  finally
    AFrame.FParts.Scroll.EnableAlign;
  end;
  RequestImages(AFrame);
end;

{ Zustand }

procedure UpdateButtons(AFrame: TAtlasIssueFrame);
var
  mParts: TAtlasIssueFrameParts;
  mHas, mWrite, mAttach, mLoading: Boolean;
begin
  mParts := AFrame.FParts;
  mHas := AFrame.FState.HasDetails;
  mWrite := HasFlag(AFrame, TAtlasIssueFlag.CanWrite);
  mAttach := HasFlag(AFrame, TAtlasIssueFlag.CanAttach);
  mLoading := HasFlag(AFrame, TAtlasIssueFlag.Loading);
  mParts.Start.Enabled := mHas and HasFlag(AFrame, TAtlasIssueFlag.CanStart);
  // Ausgeblendete Knöpfe mit alLeft reihen sich nach Left ein: direkt hinter „Beginnen“.
  if mWrite and not mParts.Finish.Visible then
  begin
    mParts.Finish.Left := mParts.Start.Left + mParts.Start.Width + 1;
  end;
  mParts.Finish.Visible := mWrite;
  mParts.Finish.Enabled := mHas and HasFlag(AFrame, TAtlasIssueFlag.CanEnd);
  mParts.CommentPanel.Visible := mWrite and mHas;
  mParts.CommentSend.Enabled := mHas and not HasFlag(AFrame, TAtlasIssueFlag.CommentSending);
  mParts.Browse.Enabled := mHas;
  mParts.CopyKey.Enabled := mHas;
  mParts.Attach.Visible := mAttach;
  mParts.Attach.Enabled := mHas;
  mParts.AttachItem.Visible := mAttach;
  mParts.AttachItem.Enabled := mHas;
  mParts.Refresh.Enabled := mHas or mLoading;
  mParts.Refresh.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewRefresh);
  if mLoading then
  begin
    mParts.Refresh.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCancel);
  end;
  mParts.BackAction.Enabled := mParts.Back.Enabled;
  mParts.ForwardAction.Enabled := mParts.Forward.Enabled;
end;

/// <summary>Statuszeile mit AText ohne Knopf zeigen.</summary>
procedure ShowStatusLine(AFrame: TAtlasIssueFrame; const AText: string; AVisible: Boolean);
begin
  AFrame.FParts.StatusLabel.Caption := AText;
  AFrame.FParts.Fix.Visible := False;
  AFrame.FParts.Status.Visible := AVisible;
end;

procedure LoadingChanged(AFrame: TAtlasIssueFrame; AValue: Boolean);
begin
  AFrame.FParts.Progress.Visible := AValue;
  if AValue then
  begin
    ShowStatusLine(AFrame, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewLoading),
      not AFrame.FState.HasDetails);
  end;
end;

procedure BusyChanged(AFrame: TAtlasIssueFrame; AValue: Boolean);
var
  mSaving: string;
begin
  mSaving := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistSaving);
  if AValue then
  begin
    ShowStatusLine(AFrame, mSaving, True);
  end
  else if AFrame.FParts.StatusLabel.Caption = mSaving then
  begin
    AFrame.FParts.Status.Visible := False;
  end;
end;

procedure SendingChanged(AFrame: TAtlasIssueFrame; AValue: Boolean);
begin
  AFrame.FParts.CommentEdit.ReadOnly := AValue;
  if AValue then
  begin
    AFrame.FParts.CommentNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCommentSending);
  end;
end;

procedure ApplyTabs(AFrame: TAtlasIssueFrame);
var
  mShow: Boolean;
begin
  // Sichtbare Reiter brauchen das Fenster des PageControls; ohne bleibt es beim Schalter Development.
  if not AFrame.HandleAllocated then
  begin
    Exit;
  end;
  mShow := HasFlag(AFrame, TAtlasIssueFlag.Development);
  AFrame.FParts.DevelopmentSheet.TabVisible := mShow;
  // Mit nur einem Reiter keine Reiterleiste.
  AFrame.FParts.DetailsSheet.TabVisible := mShow;
  AFrame.FParts.Pages.ActivePage := AFrame.FParts.DetailsSheet;
end;

procedure RebuildShown(AFrame: TAtlasIssueFrame);
begin
  if AFrame.FState.HasDetails then
  begin
    Rebuild(AFrame);
  end;
end;

/// <summary>Folgen eines gesetzten Schalters; AChanged: Wert hat sich geändert.</summary>
procedure ApplyFlag(AFrame: TAtlasIssueFrame; AFlag: TAtlasIssueFlag; AValue, AChanged: Boolean);
begin
  case AFlag of
    TAtlasIssueFlag.Checklists, TAtlasIssueFlag.ChecklistReadOnly:
      begin
        if AChanged then
        begin
          RebuildShown(AFrame);
        end;
      end;
    TAtlasIssueFlag.ChecklistBusy:
      BusyChanged(AFrame, AValue);
    TAtlasIssueFlag.CommentSending:
      SendingChanged(AFrame, AValue);
    TAtlasIssueFlag.Loading:
      LoadingChanged(AFrame, AValue);
    TAtlasIssueFlag.Development:
      begin
        if AChanged then
        begin
          ApplyTabs(AFrame);
        end;
      end;
    TAtlasIssueFlag.CanStart, TAtlasIssueFlag.CanWrite, TAtlasIssueFlag.CanEnd, TAtlasIssueFlag.CanAttach,
      TAtlasIssueFlag.LinksAsTree, TAtlasIssueFlag.CanWriteLinks:
      begin
        // Nur die Knöpfe; Baum und Knöpfe darüber gelten ab dem nächsten ShowDetails.
      end;
  end;
  UpdateButtons(AFrame);
end;

procedure ScrollToTasks(AFrame: TAtlasIssueFrame);
var
  mBar: TControlScrollBar;
begin
  if AFrame.FContent.TaskBox = nil then
  begin
    Exit;
  end;
  AFrame.FState.RevealTasks := False;
  mBar := AFrame.FParts.Scroll.VertScrollBar;
  mBar.Position := Max(0, AFrame.FContent.TaskBox.Top + mBar.Position - AFrame.FParts.Scroll.Padding.Top);
end;

{ Klicks }

/// <summary>Öffnen ersetzt den Inhalt samt Liste bzw. Baum: nicht im Klick.</summary>
procedure OpenLinkLater(AFrame: TAtlasIssueFrame; const ALink: TAtlasTrackerLink);
begin
  AFrame.FState.PendingLink := ALink;
  AFrame.FState.HasPendingLink := True;
  Defer(AFrame);
end;

procedure LinksClicked(AFrame: TAtlasIssueFrame);
var
  mList: TListView;
begin
  mList := AFrame.FContent.Links;
  if (mList <> nil) and (mList.Selected <> nil) and (mList.Selected.Index <= High(AFrame.FState.Details.Links)) then
  begin
    OpenLinkLater(AFrame, AFrame.FState.Details.Links[mList.Selected.Index]);
  end;
end;

procedure LinkTreeClicked(AFrame: TAtlasIssueFrame);
var
  mTree: TTreeView;
  mIndex: NativeInt;
begin
  mTree := AFrame.FContent.LinkTree;
  if (mTree = nil) or (mTree.Selected = nil) or (mTree.Selected.Data = nil) then
  begin
    Exit;
  end;
  mIndex := NativeInt(mTree.Selected.Data) - 1;
  if (mIndex >= 0) and (mIndex <= High(AFrame.FContent.TreeLinks)) then
  begin
    OpenLinkLater(AFrame, AFrame.FContent.TreeLinks[mIndex]);
  end;
end;

procedure AttachmentClicked(AFrame: TAtlasIssueFrame);
var
  mList: TListView;
begin
  mList := AFrame.FContent.Attachments;
  if (mList <> nil) and (mList.Selected <> nil) and (mList.Selected.Index <= High(AFrame.FState.Details.Attachments))
    and Assigned(AFrame.FEvents.OpenAttachment) then
  begin
    AFrame.FEvents.OpenAttachment(AFrame.FState.Details.Attachments[mList.Selected.Index]);
  end;
end;

procedure SendComment(AFrame: TAtlasIssueFrame);
var
  mText: string;
  mReady: Boolean;
begin
  mText := Trim(AFrame.FParts.CommentEdit.Text);
  mReady := (mText <> '') and AFrame.FState.HasDetails and HasFlag(AFrame, TAtlasIssueFlag.CanWrite) and
    not HasFlag(AFrame, TAtlasIssueFlag.CommentSending);
  if mReady and Assigned(AFrame.FEvents.Comment) then
  begin
    AFrame.FEvents.Comment(StringReplace(mText, #13#10, #10, [rfReplaceAll]));
  end;
end;

procedure RunFix(AFrame: TAtlasIssueFrame);
begin
  if Assigned(AFrame.FEvents.Fix) then
  begin
    AFrame.FEvents.Fix(AFrame.FState.FixKind);
  end;
end;

procedure RunTool(AFrame: TAtlasIssueFrame; ATool: TIssueTool);
var
  mHas, mLoading: Boolean;
begin
  mHas := AFrame.FState.HasDetails;
  mLoading := HasFlag(AFrame, TAtlasIssueFlag.Loading);
  case ATool of
    TIssueTool.Back:
      FireIf(AFrame.FParts.Back.Enabled, AFrame.FEvents.Back);
    TIssueTool.Forward:
      FireIf(AFrame.FParts.Forward.Enabled, AFrame.FEvents.Forward);
    TIssueTool.Start:
      Fire(AFrame.FEvents.Start);
    TIssueTool.Finish:
      FireIf(mHas and HasFlag(AFrame, TAtlasIssueFlag.CanEnd), AFrame.FEvents.Finish);
    TIssueTool.Browse:
      Fire(AFrame.FEvents.Browse);
    TIssueTool.CopyKey:
      Fire(AFrame.FEvents.CopyKey);
    TIssueTool.Attach:
      FireIf(mHas and HasFlag(AFrame, TAtlasIssueFlag.CanAttach), AFrame.FEvents.Attach);
    TIssueTool.Refresh:
      begin
        FireIf(mLoading, AFrame.FEvents.Cancel);
        FireIf(not mLoading, AFrame.FEvents.Refresh);
      end;
    TIssueTool.Fix:
      RunFix(AFrame);
    TIssueTool.CommentSend:
      SendComment(AFrame);
    TIssueTool.Pages:
      FireIf(AFrame.DevelopmentActive, AFrame.FEvents.DevelopmentShown);
  end;
end;

procedure RunContent(AFrame: TAtlasIssueFrame; AContent: TIssueContent; ASender: TObject);
var
  mTasks: Boolean;
begin
  mTasks := not HasFlag(AFrame, TAtlasIssueFlag.ChecklistBusy) and
    not HasFlag(AFrame, TAtlasIssueFlag.ChecklistReadOnly);
  case AContent of
    TIssueContent.Title:
      Fire(AFrame.FEvents.Browse);
    TIssueContent.Older:
      begin
        // Nicht im Klick des Labels, das dabei freigegeben wird.
        AFrame.FState.CommentsExpanded := True;
        AFrame.FState.PendingRebuild := True;
        Defer(AFrame);
      end;
    TIssueContent.AddTask:
      begin
        // Der Dialog und das Neuzeichnen kommen nach dem Klick: Das Label gehört zum Inhalt.
        AFrame.FState.PendingAdd := mTasks;
        Defer(AFrame);
      end;
    TIssueContent.Image:
      TAtlasIssueImageWindow.Enlarge(ASender as TAtlasIssueImageBox);
    TIssueContent.Attachment:
      AttachmentClicked(AFrame);
    TIssueContent.Link:
      LinksClicked(AFrame);
    TIssueContent.LinkTree:
      LinkTreeClicked(AFrame);
    TIssueContent.CreateSubtask:
      Fire(AFrame.FEvents.CreateSubtask);
    TIssueContent.AddLink:
      Fire(AFrame.FEvents.AddLink);
  end;
end;

{ TAtlasIssueFrame }

constructor TAtlasIssueFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FColors := TAtlasColors.Light;
  FMono := TFont.Create;
  FMono.Name := 'Consolas';
  FMono.Size := 10;
  FContent.Controls := TList<TControl>.Create;
  FContent.Images := TList<TAtlasIssueImageBox>.Create;
  FContent.Docs := TList<TAtlasIssueDocBox>.Create;
  FContent.AnchorComment := -1;
  FState.Details := TAtlasTrackerDetails.Empty;
  FState.PendingTask := -1;
  FFlags := [TAtlasIssueFlag.Checklists, TAtlasIssueFlag.Development];
  AddToolbar(Self);
  AddStatus(Self);
  AddCommentPanel(Self);
  AddPages(Self);
  FParts.Actions := TActionList.Create(Self);
  FParts.BackAction := AddAction(Self, VK_LEFT, TIssueTool.Back);
  FParts.ForwardAction := AddAction(Self, VK_RIGHT, TIssueTool.Forward);
  UpdateButtons(Self);
end;

destructor TAtlasIssueFrame.Destroy;
begin
  // Entwurf sichern, solange das Memo sein Fenster hat.
  if FParts.Comment <> nil then
  begin
    FParts.Comment.Unbind;
  end;
  Fire(FEvents.Hidden);
  FEvents := Default(TAtlasIssueFrameEvents);
  FContent.Controls.Free;
  FContent.Images.Free;
  FContent.Docs.Free;
  FMono.Free;
  inherited;
end;

procedure TAtlasIssueFrame.CreateWnd;
begin
  inherited CreateWnd;
  ApplyTabs(Self);
end;

procedure TAtlasIssueFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  // Das X versteckt die Form samt Frame: wie Schließen.
  FireIf(not Showing, FEvents.Hidden);
end;

procedure TAtlasIssueFrame.WMDeferred(var AMessage: TMessage);
var
  mTask: Integer;
begin
  if FState.PendingRebuild then
  begin
    FState.PendingRebuild := False;
    Rebuild(Self);
  end;
  if FState.HasPendingLink then
  begin
    FState.HasPendingLink := False;
    if Assigned(FEvents.OpenLink) then
    begin
      FEvents.OpenLink(FState.PendingLink);
    end;
  end;
  mTask := FState.PendingTask;
  FState.PendingTask := -1;
  if (mTask >= 0) and Assigned(FEvents.ToggleTask) then
  begin
    FEvents.ToggleTask(mTask);
  end;
  FireIf(FState.PendingAdd, FEvents.AddTask);
  FState.PendingAdd := False;
end;

procedure TAtlasIssueFrame.ControlClick(Sender: TObject);
var
  mTag: NativeInt;
begin
  mTag := (Sender as TComponent).Tag;
  if mTag >= cContentTag then
  begin
    RunContent(Self, TIssueContent(mTag - cContentTag), Sender);
  end
  else if mTag >= cToolTag then
  begin
    RunTool(Self, TIssueTool(mTag - cToolTag));
  end;
end;

procedure TAtlasIssueFrame.ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    ControlClick(Sender);
    Key := 0;
  end;
end;

procedure TAtlasIssueFrame.LinkTreeExpanded(Sender: TObject; Node: TTreeNode);
begin
  FitLinkTree(Self);
end;

procedure TAtlasIssueFrame.ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  FParts.Scroll.VertScrollBar.Position := FParts.Scroll.VertScrollBar.Position - WheelDelta div 2;
  Handled := True;
end;

procedure TAtlasIssueFrame.SetFlag(AFlag: TAtlasIssueFlag; AValue: Boolean);
var
  mChanged: Boolean;
begin
  mChanged := (AFlag in FFlags) <> AValue;
  if AValue then
  begin
    Include(FFlags, AFlag);
  end
  else
  begin
    Exclude(FFlags, AFlag);
  end;
  ApplyFlag(Self, AFlag, AValue, mChanged);
end;

procedure TAtlasIssueFrame.ShowEmpty;
begin
  FState.HasDetails := False;
  FState.Details := TAtlasTrackerDetails.Empty;
  FParts.Status.Visible := False;
  Rebuild(Self);
  UpdateButtons(Self);
end;

/// <summary>Kopf des hervorgehobenen Kommentars oben ins Bild; gefunden (nicht nur der letzte als Ersatz), hat
/// der Anker seinen Zweck erfüllt.</summary>
procedure RevealAnchor(AFrame: TAtlasIssueFrame);
var
  mLabel: TLabel;
begin
  mLabel := AFrame.FContent.AnchorLabel;
  if mLabel = nil then
  begin
    Exit;
  end;
  AFrame.FParts.Scroll.VertScrollBar.Position := mLabel.Top - mLabel.Margins.Top;
  if AFrame.FState.Details.Comments[AFrame.FContent.AnchorComment].Created >=
    AFrame.FState.Anchor - TAtlasIssuePreview.cAnchorSlackMs / MSecsPerDay then
  begin
    AFrame.FState.Anchor := 0;
  end;
end;

procedure TAtlasIssueFrame.ShowDetails(const ADetails: TAtlasTrackerDetails; ANow: TDateTime;
  const AStale: string; ACommentsOff: Boolean);
var
  mSame: Boolean;
  mPosition: Integer;
begin
  // Anderes Issue: ältere Kommentare wieder eingeklappt, oben anfangen. Dasselbe frisch geladen (auch nach dem
  // Zwischenspeicher): Bildlauf bleibt, z. B. an der Checkliste (#1273).
  mSame := FState.HasDetails and SameText(FState.Details.Key, ADetails.Key);
  mPosition := 0;
  if mSame then
  begin
    mPosition := FParts.Scroll.VertScrollBar.Position;
  end
  else
  begin
    FState.CommentsExpanded := False;
  end;
  FState.Details := ADetails;
  FState.HasDetails := True;
  FState.Now := ANow;
  FState.CommentsOff := ACommentsOff;
  ShowStatusLine(Self, AStale, AStale <> '');
  Rebuild(Self);
  FParts.Scroll.VertScrollBar.Position := mPosition;
  if FState.RevealTasks then
  begin
    ScrollToTasks(Self);
  end;
  RevealAnchor(Self);
  UpdateButtons(Self);
end;

procedure TAtlasIssueFrame.ReplaceDescription(const AText: string);
var
  mPosition: Integer;
begin
  if not FState.HasDetails then
  begin
    Exit;
  end;
  mPosition := FParts.Scroll.VertScrollBar.Position;
  FState.Details.Description := AText;
  Rebuild(Self);
  FParts.Scroll.VertScrollBar.Position := mPosition;
end;

procedure TAtlasIssueFrame.ShowNotice(const AText: string);
begin
  ShowError(AText, TAtlasIssueFix.None);
end;

procedure TAtlasIssueFrame.RevealChecklist;
begin
  FState.RevealTasks := True;
  if FState.HasDetails then
  begin
    ScrollToTasks(Self);
  end;
end;

procedure TAtlasIssueFrame.SetAnchor(AAnchor: TDateTime);
begin
  FState.Anchor := AAnchor;
end;

function FixCaption(AFix: TAtlasIssueFix): string;
begin
  Result := '';
  case AFix of
    TAtlasIssueFix.EnterToken:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFixToken);
    TAtlasIssueFix.Settings:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFixSettings);
    TAtlasIssueFix.Browser:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewBrowse);
    TAtlasIssueFix.Retry:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFixRetry);
    TAtlasIssueFix.None:
      begin
        // Kein Knopf.
      end;
  end;
end;

procedure TAtlasIssueFrame.ShowError(const AText: string; AFix: TAtlasIssueFix);
begin
  FState.FixKind := AFix;
  FParts.StatusLabel.Caption := AText;
  FParts.Fix.Visible := AFix <> TAtlasIssueFix.None;
  if FParts.Fix.Visible then
  begin
    FParts.Fix.Caption := FixCaption(AFix);
  end;
  FParts.Status.Visible := True;
  UpdateButtons(Self);
end;

procedure TAtlasIssueFrame.SetImage(const AUrl: string; AGraphic: TGraphic);
var
  mImage: TAtlasIssueImageBox;
  mOwned: Boolean;
  mCopy: TGraphic;
begin
  if AGraphic = nil then
  begin
    Exit;
  end;
  mOwned := False;
  try
    for mImage in FContent.Images do
    begin
      if mImage.Url <> AUrl then
      begin
        Continue;
      end;
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
    begin
      AGraphic.Free;
    end;
  end;
end;

procedure TAtlasIssueFrame.SetHistory(ACanBack, ACanForward: Boolean);
begin
  FParts.Back.Enabled := ACanBack;
  FParts.Forward.Enabled := ACanForward;
  UpdateButtons(Self);
end;

procedure TAtlasIssueFrame.CommentDone(const AError: string);
begin
  SetFlag(TAtlasIssueFlag.CommentSending, False);
  FParts.CommentNote.Caption := AError;
  // Gesendet: Feld leeren und den Entwurf löschen; bei einem Fehler bleibt beides.
  if AError = '' then
  begin
    FParts.Comment.Sent;
  end;
end;

procedure TAtlasIssueFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FParts.Scroll.Color := ToColor(AColors.Surface);
  FParts.Scroll.ParentBackground := False;
  FParts.Development.ApplyColors(AColors);
  FParts.Empty.Font.Color := ToColor(AColors.Muted);
  FParts.CommentHint.Font.Color := ToColor(AColors.Muted);
  FParts.CommentNote.Font.Color := ToColor(AColors.Muted);
  FParts.Comment.Preview.ApplyColors(AColors);
  RebuildShown(Self);
end;

procedure TAtlasIssueFrame.SetMonoFont(AValue: TFont);
begin
  FMono.Assign(AValue);
  FParts.Comment.Preview.Mono := AValue;
  RebuildShown(Self);
end;

function TAtlasIssueFrame.StatusText: string;
begin
  Result := '';
  if FParts.Status.Visible then
  begin
    Result := FParts.StatusLabel.Caption;
  end;
end;

function TAtlasIssueFrame.DevelopmentActive: Boolean;
begin
  Result := (TAtlasIssueFlag.Development in FFlags) and (FParts.Pages.ActivePage = FParts.DevelopmentSheet);
end;

procedure TAtlasIssueFrame.SelectTab(ADevelopment: Boolean);
begin
  if not ADevelopment then
  begin
    FParts.Pages.ActivePage := FParts.DetailsSheet;
  end
  else if (TAtlasIssueFlag.Development in FFlags) and (FParts.Pages.ActivePage <> FParts.DevelopmentSheet) then
  begin
    FParts.Pages.ActivePage := FParts.DevelopmentSheet;
    RunTool(Self, TIssueTool.Pages);
  end;
end;

end.
