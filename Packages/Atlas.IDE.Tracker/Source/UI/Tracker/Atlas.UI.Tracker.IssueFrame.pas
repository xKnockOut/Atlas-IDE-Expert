unit Atlas.UI.Tracker.IssueFrame;

// Inhalt des andockbaren Fensters „Atlas-Issue“ (#1264), reine VCL ohne Open
// Tools API:
//   [◀] [▶]  [Beginnen] [Beenden …] [Im Browser öffnen] [Kennung kopieren] [Anhängen …] [Aktualisieren]
//   (die Leiste bricht bei schmalem Fenster um)
//   ───────────────── dünne Leiste beim Laden ─────────────────
//   (Stand vom …  bzw. Fehler mit Knopf zum Beheben)
//   ┌ Kopf als abgesetzte Karte ──────────────────────────────────────────
//   │ ATL-123 · 3/5   (Fortschritt der Checkliste, #1273)
//   │ Titel des Issues (Klick öffnet den Tracker)
//   │ (In Arbeit) (Hoch) (Bug) (M. Muster) (Sprint 12) (ui) (erstellt vor 3 Tg.)
//   └─────────────────────────────────────────────────────────────────────
//   Abschnitte beginnen mit einer Überschrift und einer Linie bis zum Rand.
//   Texte brechen um und passen ihre Höhe jeder Breite an (TAtlasWrapLabel).
//   Beschreibung: Markdown gesetzt wie die XMLDoc im Hover (TAtlasDocView):
//   Überschriften, Listen, fett/kursiv, Links, Tabellen, Zitate, Codeblöcke
//   (Delphi eingefärbt); alleinstehende Bilder als Vorschau in Fensterbreite,
//   Klick vergrößert. Aufgabenlisten (#1273) als Häkchen: Klick meldet
//   Events.ToggleTask (die IDE-Schicht schreibt zurück), darunter „Punkt
//   hinzufügen …“ (Events.AddTask); ohne Schreibrecht nur lesend mit Tooltip;
//   mit Checklists = False als Text wie geschrieben. In Kommentaren nur
//   Kästchen ohne Klick.
//   Kommentare (n): je Kommentar eine Karte, neueste unten, ältere hinter
//   „12 ältere Kommentare“.
//   Aus einer Meldung (#1271, SetAnchor) öffnet der Inhalt am ersten neuen
//   Kommentar; sein Kopf ist hervorgehoben.
//   Anhänge (n): Name und Größe; Doppelklick öffnet.
//   Verknüpfte Issues (n): Kennung, Titel, Art; Klick öffnet im Fenster.
//   ───────────────── unten (#1266, nur mit issues.syncState) ─────────────────
//   Kommentar schreiben … (Markdown, Strg+Enter sendet)          [Senden]
// „Beenden …“ (#1266) gibt es nur für das aktuelle Issue (CanEnd), Feld und
// Knopf nur, wenn der Tracker schreiben kann (CanWrite).
//   Mit LinksAsTree (#1279, issues.preview.links) stattdessen
//   Verknüpfungen (n) als Baum: Hängt ab von, Blockiert, Unteraufgaben 2/3,
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
// Aufteilung: Der Frame hält Zustand und Schalter und entscheidet, was ein Klick
// bewirkt. Die festen Steuerelemente baut TAtlasIssueChrome (.Chrome), den Inhalt
// TAtlasIssueSections (.Sections) über TAtlasIssueLayout (.Layout); Wünsche nach
// dem Klick merkt TAtlasIssueDeferred (.Deferred).

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame.Contract,
  Atlas.UI.Tracker.IssueFrame.Chrome,
  Atlas.UI.Tracker.IssueFrame.Sections,
  Atlas.UI.Tracker.IssueFrame.Deferred;

const
  /// <summary>Nachricht an den Frame: Inhalt neu bzw. verknüpftes Issue öffnen, nach dem auslösenden Klick (das
  /// Steuerelement des Klicks wird dabei freigegeben). Mit dem Fenster verfällt sie.</summary>
  cWM_ATLAS_ISSUE_DEFERRED = WM_APP + 1264;

type
  TAtlasIssueFrame = class(TFrame)
  private
    /// <summary>Teile des Frames; sie gehören ihm (TComponent) und gehen mit ihm.</summary>
    FChrome: TAtlasIssueChrome;
    FSections: TAtlasIssueSections;
    FDeferred: TAtlasIssueDeferred;
    FState: TAtlasIssueFrameState;
    FFlags: TAtlasIssueFlags;
    FEvents: TAtlasIssueFrameEvents;
    /// <summary>Klick auf Knopf, Label, Liste, Bild, Reiter oder Aktion (Tag: Werkzeug bzw. Teil des Inhalts).
    /// </summary>
    procedure ControlClick(Sender: TObject);
    procedure RunTool(ATool: TAtlasIssueTool);
    procedure RunPart(APart: TAtlasIssuePart; ASender: TObject);
    /// <summary>Link aus Beschreibung oder Kommentar; Kästchen einer Checkliste (#1273) melden nach dem Klick.
    /// </summary>
    procedure LinkOpened(AUrl: string);
    /// <summary>Inhalt zum Zustand neu bauen und die Bilder laden lassen.</summary>
    procedure Rebuild;
    function GetParts: TAtlasIssueFrameParts;
    function GetContent: TAtlasIssueFrameContent;
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
    property Parts: TAtlasIssueFrameParts read GetParts;
    property Content: TAtlasIssueFrameContent read GetContent;
    property State: TAtlasIssueFrameState read FState;
    property Flags: TAtlasIssueFlags read FFlags;
    property Events: TAtlasIssueFrameEvents read FEvents write FEvents;
  end;

implementation

uses
  Atlas.Core.Tracker.Markdown,
  Atlas.UI.Tracker.IssueBoxes;

{$R *.dfm}

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

/// <summary>Kommentar senden (#1266), wenn Text da ist und AReady (Issue, Schreibrecht, nicht schon beim Senden).
/// </summary>
procedure SendComment(const AEvents: TAtlasIssueFrameEvents; const AText: string; AReady: Boolean);
begin
  if AReady and (AText <> '') and Assigned(AEvents.Comment) then
  begin
    AEvents.Comment(AText);
  end;
end;

{ TAtlasIssueFrame }

constructor TAtlasIssueFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FState.Details := TAtlasTrackerDetails.Empty;
  FFlags := [TAtlasIssueFlag.Checklists, TAtlasIssueFlag.Development];
  FChrome := TAtlasIssueChrome.Create(Self, ControlClick);
  FSections := TAtlasIssueSections.Create(Self, FChrome.Parts.Scroll, ControlClick, LinkOpened);
  FDeferred := TAtlasIssueDeferred.Create(Self, cWM_ATLAS_ISSUE_DEFERRED);
  FChrome.UpdateButtons(False, FFlags);
end;

destructor TAtlasIssueFrame.Destroy;
begin
  // Entwurf sichern, solange das Memo sein Fenster hat.
  if FChrome <> nil then
  begin
    FChrome.Parts.Comment.Unbind;
  end;
  Fire(FEvents.Hidden);
  FEvents := Default(TAtlasIssueFrameEvents);
  inherited;
end;

procedure TAtlasIssueFrame.CreateWnd;
begin
  inherited CreateWnd;
  if FChrome <> nil then
  begin
    FChrome.ApplyTabs(TAtlasIssueFlag.Development in FFlags);
  end;
end;

function TAtlasIssueFrame.GetParts: TAtlasIssueFrameParts;
begin
  Result := FChrome.Parts;
end;

function TAtlasIssueFrame.GetContent: TAtlasIssueFrameContent;
begin
  Result := FSections.Content;
end;

procedure TAtlasIssueFrame.ControlClick(Sender: TObject);
var
  mTag: NativeInt;
begin
  mTag := (Sender as TComponent).Tag;
  if mTag >= cAtlasIssuePartTag then
  begin
    RunPart(TAtlasIssuePart(mTag - cAtlasIssuePartTag), Sender);
  end
  else if mTag >= cAtlasIssueToolTag then
  begin
    RunTool(TAtlasIssueTool(mTag - cAtlasIssueToolTag));
  end;
end;

procedure TAtlasIssueFrame.RunTool(ATool: TAtlasIssueTool);
var
  mHas, mLoading: Boolean;
begin
  mHas := FState.HasDetails;
  mLoading := TAtlasIssueFlag.Loading in FFlags;
  case ATool of
    TAtlasIssueTool.Back:
      FireIf(FChrome.Parts.Back.Enabled, FEvents.Back);
    TAtlasIssueTool.Forward:
      FireIf(FChrome.Parts.Forward.Enabled, FEvents.Forward);
    TAtlasIssueTool.Start:
      Fire(FEvents.Start);
    TAtlasIssueTool.Finish:
      FireIf(mHas and (TAtlasIssueFlag.CanEnd in FFlags), FEvents.Finish);
    TAtlasIssueTool.Review:
      FireIf(mHas and (TAtlasIssueFlag.CanReview in FFlags), FEvents.Review);
    TAtlasIssueTool.Browse:
      Fire(FEvents.Browse);
    TAtlasIssueTool.CopyKey:
      Fire(FEvents.CopyKey);
    TAtlasIssueTool.Attach:
      FireIf(mHas and (TAtlasIssueFlag.CanAttach in FFlags), FEvents.Attach);
    TAtlasIssueTool.Refresh:
      begin
        FireIf(mLoading, FEvents.Cancel);
        FireIf(not mLoading, FEvents.Refresh);
      end;
    TAtlasIssueTool.Fix:
      begin
        if Assigned(FEvents.Fix) then
        begin
          FEvents.Fix(FChrome.FixKind);
        end;
      end;
    TAtlasIssueTool.CommentSend:
      SendComment(FEvents, FChrome.CommentText, mHas and (FFlags * [TAtlasIssueFlag.CanWrite,
        TAtlasIssueFlag.CommentSending] = [TAtlasIssueFlag.CanWrite]));
    TAtlasIssueTool.Pages:
      FireIf(DevelopmentActive, FEvents.DevelopmentShown);
  end;
end;

procedure TAtlasIssueFrame.RunPart(APart: TAtlasIssuePart; ASender: TObject);
var
  mLink: TAtlasTrackerLink;
  mAttachment: TAtlasTrackerAttachment;
begin
  case APart of
    TAtlasIssuePart.Title:
      Fire(FEvents.Browse);
    TAtlasIssuePart.Older:
      begin
        // Nicht im Klick des Labels, das dabei freigegeben wird.
        FState.CommentsExpanded := True;
        FDeferred.Rebuild;
      end;
    TAtlasIssuePart.AddTask:
      begin
        // Der Dialog und das Neuzeichnen kommen nach dem Klick: Das Label gehört zum Inhalt.
        if FFlags * [TAtlasIssueFlag.ChecklistBusy, TAtlasIssueFlag.ChecklistReadOnly] = [] then
        begin
          FDeferred.AddTask;
        end;
      end;
    TAtlasIssuePart.Image:
      TAtlasIssueImageWindow.Enlarge(ASender as TAtlasIssueImageBox);
    TAtlasIssuePart.Attachment:
      begin
        if FSections.SelectedAttachment(mAttachment) and Assigned(FEvents.OpenAttachment) then
        begin
          FEvents.OpenAttachment(mAttachment);
        end;
      end;
    TAtlasIssuePart.Link, TAtlasIssuePart.LinkTree:
      begin
        // Öffnen ersetzt den Inhalt samt Liste bzw. Baum: nicht im Klick.
        if FSections.SelectedLink(APart, mLink) then
        begin
          FDeferred.OpenLink(mLink);
        end;
      end;
    TAtlasIssuePart.CreateSubtask:
      Fire(FEvents.CreateSubtask);
    TAtlasIssuePart.AddLink:
      Fire(FEvents.AddLink);
  end;
end;

procedure TAtlasIssueFrame.LinkOpened(AUrl: string);
var
  mTask: Integer;
begin
  if not TAtlasTrackerMarkdown.TaskIndexOf(AUrl, mTask) then
  begin
    if Assigned(FEvents.OpenUrl) then
    begin
      FEvents.OpenUrl(AUrl);
    end;
  end
  else if (TAtlasIssueFlag.Checklists in FFlags) and
    (FFlags * [TAtlasIssueFlag.ChecklistReadOnly, TAtlasIssueFlag.ChecklistBusy] = []) then
  begin
    // Das Zurückschreiben baut den Inhalt neu: nicht im Klick.
    FDeferred.ToggleTask(mTask);
  end;
end;

procedure TAtlasIssueFrame.Rebuild;
var
  mUrls: TArray<string>;
begin
  FChrome.Parts.Scroll.DisableAlign;
  try
    FChrome.Parts.Empty.Visible := not FState.HasDetails;
    FSections.Build(FState, FFlags);
  finally
    FChrome.Parts.Scroll.EnableAlign;
  end;
  mUrls := FSections.ImageUrls;
  if (Length(mUrls) > 0) and Assigned(FEvents.Images) then
  begin
    FEvents.Images(mUrls);
  end;
end;

procedure TAtlasIssueFrame.WMDeferred(var AMessage: TMessage);
begin
  FDeferred.Run(FEvents,
    procedure
    begin
      Rebuild;
    end);
end;

procedure TAtlasIssueFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  // Das X versteckt die Form samt Frame: wie Schließen.
  FireIf(not Showing, FEvents.Hidden);
end;

procedure TAtlasIssueFrame.ShowEmpty;
begin
  FState.HasDetails := False;
  FState.Details := TAtlasTrackerDetails.Empty;
  FChrome.HideStatus;
  Rebuild;
  FChrome.UpdateButtons(FState.HasDetails, FFlags);
end;

procedure TAtlasIssueFrame.SetAnchor(AAnchor: TDateTime);
begin
  FState.Anchor := AAnchor;
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
    mPosition := FChrome.Parts.Scroll.VertScrollBar.Position;
  end
  else
  begin
    FState.CommentsExpanded := False;
  end;
  FState.Details := ADetails;
  FState.HasDetails := True;
  FState.Now := ANow;
  FState.CommentsOff := ACommentsOff;
  FChrome.ShowStatusLine(AStale, AStale <> '');
  Rebuild;
  FChrome.Parts.Scroll.VertScrollBar.Position := mPosition;
  if FState.RevealTasks and FSections.ScrollToTasks then
  begin
    FState.RevealTasks := False;
  end;
  if FSections.RevealAnchor then
  begin
    FState.Anchor := 0;
  end;
  FChrome.UpdateButtons(FState.HasDetails, FFlags);
end;

procedure TAtlasIssueFrame.ShowError(const AText: string; AFix: TAtlasIssueFix);
begin
  FChrome.ShowError(AText, AFix);
  FChrome.UpdateButtons(FState.HasDetails, FFlags);
end;

procedure TAtlasIssueFrame.ShowNotice(const AText: string);
begin
  ShowError(AText, TAtlasIssueFix.None);
end;

procedure TAtlasIssueFrame.SetImage(const AUrl: string; AGraphic: TGraphic);
begin
  FSections.SetImage(AUrl, AGraphic);
end;

procedure TAtlasIssueFrame.SetHistory(ACanBack, ACanForward: Boolean);
begin
  FChrome.SetHistory(ACanBack, ACanForward);
  FChrome.UpdateButtons(FState.HasDetails, FFlags);
end;

procedure TAtlasIssueFrame.CommentDone(const AError: string);
begin
  SetFlag(TAtlasIssueFlag.CommentSending, False);
  FChrome.CommentDone(AError);
end;

procedure TAtlasIssueFrame.ReplaceDescription(const AText: string);
var
  mPosition: Integer;
begin
  if not FState.HasDetails then
  begin
    Exit;
  end;
  mPosition := FChrome.Parts.Scroll.VertScrollBar.Position;
  FState.Details.Description := AText;
  Rebuild;
  FChrome.Parts.Scroll.VertScrollBar.Position := mPosition;
end;

procedure TAtlasIssueFrame.RevealChecklist;
begin
  FState.RevealTasks := True;
  if FState.HasDetails and FSections.ScrollToTasks then
  begin
    FState.RevealTasks := False;
  end;
end;

procedure TAtlasIssueFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FChrome.ApplyColors(AColors);
  FSections.Layout.Colors := AColors;
  if FState.HasDetails then
  begin
    Rebuild;
  end;
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
  case AFlag of
    TAtlasIssueFlag.Checklists, TAtlasIssueFlag.ChecklistReadOnly:
      begin
        if mChanged and FState.HasDetails then
        begin
          Rebuild;
        end;
      end;
    TAtlasIssueFlag.ChecklistBusy:
      FChrome.BusyChanged(AValue);
    TAtlasIssueFlag.CommentSending:
      FChrome.SendingChanged(AValue);
    TAtlasIssueFlag.Loading:
      FChrome.LoadingChanged(AValue, FState.HasDetails);
    TAtlasIssueFlag.Development:
      begin
        if mChanged then
        begin
          FChrome.ApplyTabs(AValue);
        end;
      end;
    TAtlasIssueFlag.CanStart, TAtlasIssueFlag.CanWrite, TAtlasIssueFlag.CanEnd, TAtlasIssueFlag.CanAttach,
      TAtlasIssueFlag.CanReview, TAtlasIssueFlag.LinksAsTree, TAtlasIssueFlag.CanWriteLinks:
      begin
        // Nur die Knöpfe; Baum und Knöpfe darüber gelten ab dem nächsten ShowDetails.
      end;
  end;
  FChrome.UpdateButtons(FState.HasDetails, FFlags);
end;

procedure TAtlasIssueFrame.SetMonoFont(AValue: TFont);
begin
  FSections.Layout.Mono.Assign(AValue);
  FChrome.Parts.Comment.Preview.Mono := AValue;
  if FState.HasDetails then
  begin
    Rebuild;
  end;
end;

function TAtlasIssueFrame.StatusText: string;
begin
  Result := FChrome.StatusText;
end;

function TAtlasIssueFrame.DevelopmentActive: Boolean;
begin
  Result := (TAtlasIssueFlag.Development in FFlags) and FChrome.DevelopmentSelected;
end;

procedure TAtlasIssueFrame.SelectTab(ADevelopment: Boolean);
begin
  if not ADevelopment then
  begin
    FChrome.SelectPage(False);
  end
  else if (TAtlasIssueFlag.Development in FFlags) and FChrome.SelectPage(True) then
  begin
    RunTool(TAtlasIssueTool.Pages);
  end;
end;

end.
