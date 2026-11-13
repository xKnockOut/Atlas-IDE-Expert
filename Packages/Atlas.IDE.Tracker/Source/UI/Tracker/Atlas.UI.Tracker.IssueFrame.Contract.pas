unit Atlas.UI.Tracker.IssueFrame.Contract;

// Typen des Fensters „Atlas-Issue“ (#1264) für Frame und IDE-Schicht: Schalter (SetFlag), feste Steuerelemente,
// Inhalt des gezeigten Issues, Zustand zwischen den Aufrufen und Wünsche an die IDE-Schicht. Der Frame selbst steht
// in Atlas.UI.Tracker.IssueFrame.

interface

uses
  System.SysUtils,
  System.Actions,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.ActnList,
  Vcl.Forms,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.DocBox,
  Atlas.UI.Tracker.DevelopmentView,
  Atlas.UI.Tracker.IssueBoxes;

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
    /// <summary>Das gezeigte Issue steht in einem Prüfzustand (#2126): „Prüfen …“ zeigen.</summary>
    CanReview,
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
    /// <summary>Werkzeugleiste; bricht bei schmalem Fenster in eine zweite Zeile um.</summary>
    Tools: TFlowPanel;
    Back: TButton;
    Forward: TButton;
    Start: TButton;
    /// <summary>„Beenden …“ (#1266).</summary>
    Finish: TButton;
    /// <summary>„Prüfen …“ (#2126) für ein Issue im Prüfzustand.</summary>
    Review: TButton;
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
    /// <summary>Behälter für Place: nil = Bildlauf, sonst eine Karte (Kopf, Kommentar).</summary>
    Target: TAtlasIssueCard;
    /// <summary>Kopf mit Kennung, Titel und Abzeichen.</summary>
    Head: TAtlasIssueCard;
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
    /// <summary>„Prüfen …“ (#2126) für das gezeigte Issue.</summary>
    Review: TProc;
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

implementation

end.
