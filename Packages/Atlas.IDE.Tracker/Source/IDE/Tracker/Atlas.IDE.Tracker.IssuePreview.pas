unit Atlas.IDE.Tracker.IssuePreview;

// Steuerung des Fensters „Atlas-Issue“ (#1264): ein Fenster, dessen Inhalt
// wechselt (TAtlasIdeIssueWindow, TAtlasIssueFrame).
// - Show(Ziel, Kennung): Verlauf (Zurück/Vor), sofort der letzte Stand aus dem
//   Zwischenspeicher (Speicher bzw. %LOCALAPPDATA%\Atlas\issues, höchstens 7
//   Tage), dann Laden im Hintergrund (Zeitgrenze 10 s, abbrechbar über
//   „Abbrechen“ und beim Schließen des Fensters). Ohne Netz bleibt der letzte
//   Stand mit „Stand vom …“, ohne Dialog; ohne Stand eine Meldung mit Knopf
//   zum Beheben (Token hinterlegen, Tracker-Einstellungen, Im Browser öffnen,
//   erneut versuchen).
// - Laden und Zeigen: Atlas.IDE.Tracker.IssueLoad. Eine Abfrage zur Zeit:
//   Ein neuer Wunsch bricht die laufende ab und folgt ihr.
// - Aus einer Meldung zu meinen Issues (#1271) öffnet Show mit Anker am
//   ersten neuen Kommentar.
// - Links aus dem Text öffnen nur im Browser (http/https ohne Benutzer).
// - issues.preview.comments aus: Kommentare werden nicht abgefragt.
// - Teile (Atlas.IDE.Tracker.IssueParts): gemeinsamer Stand TAtlasIdeIssueContext, Kurzabfrage für den Hover
//   TAtlasIdeIssueLookups (Lookups, #1265), Checklisten und Statusfeld
//   TAtlasIdeIssueChecklists (Checklists, #1273), Verknüpfungen
//   TAtlasIdeIssueLinkWrites (LinkWrites, #1279), Bilder und Anhänge
//   TAtlasIdeIssueMedia, Kommentarfeld TAtlasIdeIssueComments (#1266, #1278).
// - Zuletzt geöffnet (#1270): jedes gezeigte Issue kommt in
//   TAtlasRecentIssues (<Zwischenspeicher>\recent.json); die Befehlspalette
//   zeigt sie bei leerem "#".
// - Reiter „Entwicklung“ (#1269): TAtlasIdeIssueDevelopment folgt dem
//   gezeigten Issue, „Aktualisieren“ und „Abbrechen“ gelten auch dort.
// - „Anhängen …“ (#1276, issues.attach) im Fenster ruft den Hook Attach mit
//   Tracker und Kennung des gezeigten Issues.
// - Protokoll anonym: nur Anbieter, Ergebnis und Fehlerart, nie Adresse,
//   Kennung, Titel oder Token.
// Anbieter, Transport, Zugang, „Beginnen“ und die Einstellungsseite kommen
// über Hooks (Komposition bzw. „Meine Issues“).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.IssueFrame.Contract,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.IDE.Tracker.IssueLookups,
  Atlas.IDE.Tracker.IssueChecklists,
  Atlas.IDE.Tracker.IssueLinkWrites,
  Atlas.IDE.Tracker.IssueComments,
  Atlas.IDE.Tracker.IssueParts,
  Atlas.IDE.Tracker.IssueLoad;

type
  TAtlasIssuePreviewCredentialsHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): Boolean;

  TAtlasIssuePreviewHooks = record
    Provider: TAtlasIssuePreviewProviderHook;
    Transport: TAtlasIssuePreviewTransportHook;
    Credentials: TAtlasIssuePreviewCredentialsHook;
    /// <summary>„Beginnen“ wie in „Meine Issues“.</summary>
    Start: TProc<TAtlasTrackerIssue>;
    /// <summary>„Beginnen“ möglich (Projekt mit Versionsverwaltung bzw. „nur merken“).</summary>
    CanStart: TFunc<Boolean>;
    /// <summary>Tools › Optionen › Atlas › Issue-Tracker.</summary>
    Settings: TProc;
    /// <summary>issues.syncState an und der Tracker kann schreiben (#1266).</summary>
    CanWrite: TFunc<TAtlasTrackerTarget, Boolean>;
    /// <summary>Die Kennung ist das aktuelle Issue (#1266).</summary>
    IsActive: TFunc<string, Boolean>;
    /// <summary>„Beenden …“ für das aktuelle Issue (#1266).</summary>
    EndIssue: TProc<string>;
    /// <summary>„Prüfen …“ zeigen (#2126): Zustand des Issues in issues.reviewStates, nicht das aktuelle.
    /// </summary>
    CanReview: TFunc<TAtlasTrackerTarget, TAtlasTrackerIssue, Boolean>;
    /// <summary>„Prüfen …“ für das gezeigte Issue (#2126).</summary>
    Review: TProc<TAtlasTrackerIssue>;
    Comment: TAtlasIssuePreviewCommentHook;
    CommentAssist: TAtlasIssuePreviewAssistHook;
    /// <summary>Kommentar zu AKey gesendet, das Feld zeigt schon ein anderes Issue: dessen Entwurf löschen.
    /// </summary>
    CommentSent: TAtlasIssuePreviewSentHook;
    /// <summary>Projektdatei des aktuellen Projekts für den Reiter „Entwicklung“ ('' ohne).</summary>
    Project: TFunc<string>;
    /// <summary>„Anhängen …“ für das gezeigte Issue (#1276).</summary>
    Attach: TProc<TAtlasTrackerTarget, string>;
    /// <summary>„Anhängen …“ zeigen (issues.attach).</summary>
    CanAttach: TFunc<Boolean>;
  end;

  TAtlasIdeIssuePreview = class(TInterfacedObject)
  private
    FHooks: TAtlasIssuePreviewHooks;
    FHistory: TAtlasIssueHistory;
    FParts: TAtlasIdeIssueParts;
    FLoad: TAtlasIdeIssueLoad;
    /// <summary>Anmeldung bei den Maustasten Zurück/Vor (#1889); -1 ohne.</summary>
    FMouseHistory: Integer;
    function MouseStep(AWindow: HWND; AForward: Boolean): Boolean;
    procedure CreateParts(const ACacheFolder: string);
    procedure Wire(AFrame: TAtlasIssueFrame);
    procedure Fix(AFix: TAtlasIssueFix);
    /// <summary>Zurück, Vor, Aktualisieren, Abbrechen, Schließen und Browser.</summary>
    procedure AddMoveEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
    /// <summary>„Prüfen …“ (#2126) für das gezeigte Issue.</summary>
    procedure AddReviewEvent(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
    /// <summary>Beginnen, Beenden, Kennung kopieren und Anhängen.</summary>
    procedure AddIssueEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
    /// <summary>Verknüpftes Issue, Beheben, Anhang, Adresse und Bilder öffnen bzw. laden.</summary>
    procedure AddOpenEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
    /// <summary>Kommentar, Checkliste (#1273) und Verknüpfungen (#1279) schreiben.</summary>
    procedure AddWriteEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
    function GetLookups: TAtlasIdeIssueLookups;
    function GetChecklists: TAtlasIdeIssueChecklists;
    function GetLinkWrites: TAtlasIdeIssueLinkWrites;
  public
    /// <summary>ACacheFolder: Ordner des Zwischenspeichers auf der Platte ('' = nur im Speicher).</summary>
    constructor Create(const AHooks: TAtlasIssuePreviewHooks; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Fenster anmelden (Desktop), alten Zwischenspeicher aufräumen.</summary>
    procedure Start;
    /// <summary>Abbrechen, kurz auf die Abfragen warten, Fenster abmelden; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Issue AKey des Trackers ATarget im Fenster zeigen (öffnet es).</summary>
    procedure Show(const ATarget: TAtlasTrackerTarget; const AKey: string); overload;
    /// <summary>Wie oben, am Kommentar zu AAnchor (UTC, erster neuer Kommentar einer Meldung, #1271); 0 = oben.
    /// </summary>
    procedure Show(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime); overload;
    procedure Refresh;
    procedure GoBack;
    procedure GoForward;
    /// <summary>Kommentarfeld und „Beenden …“ nach issues.syncState und dem aktuellen Issue (#1266); nach
    /// „Beginnen“, „Beenden“ und geänderten Einstellungen.</summary>
    procedure UpdateWrite;
    /// <summary>Wie Show und dann zur Checkliste blättern (Klick im Statusfeld, #1273).</summary>
    procedure ShowChecklist(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>Verknüpftes Issue zeigen: im Fenster, wenn es im selben Tracker liegt und die Vorschau an ist,
    /// sonst im Browser.</summary>
    procedure ShowLink(const ATarget: TAtlasTrackerTarget; const ALink: TAtlasTrackerLink);
    /// <summary>issues.preview an?</summary>
    class function Active: Boolean; static;
    /// <summary>Zuletzt gezeigte Issues des Trackers ATarget, neueste zuerst (#1270).</summary>
    function RecentIssues(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
    /// <summary>Kurzabfrage für den Hover über Kennungen (#1265).</summary>
    property Lookups: TAtlasIdeIssueLookups read GetLookups;
    /// <summary>Fortschritt und Auffrischen der Checklisten fürs Statusfeld (#1273).</summary>
    property Checklists: TAtlasIdeIssueChecklists read GetChecklists;
    /// <summary>Verknüpfungen, auch die Prüfung vor „Beginnen“ (#1279).</summary>
    property LinkWrites: TAtlasIdeIssueLinkWrites read GetLinkWrites;
  end;

implementation

uses
  ToolsAPI,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.MouseButtons,
  Atlas.IDE.Contracts.MouseHistory,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.IssueWindow;

/// <summary>Editorschrift der IDE für Code im Fenster (Vorgabe Consolas 10).</summary>
procedure ApplyMonoFont(AFrame: TAtlasIssueFrame);
var
  mMono: TFont;
  mEditor: IOTAEditorServices;
begin
  mMono := TFont.Create;
  try
    mMono.Name := 'Consolas';
    mMono.Size := 10;
    if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) and (mEditor.EditOptions <> nil) then
    begin
      mMono.Name := mEditor.EditOptions.FontName;
      mMono.Size := mEditor.EditOptions.FontSize;
    end;
    AFrame.SetMonoFont(mMono);
  finally
    mMono.Free;
  end;
end;

{ TAtlasIdeIssuePreview }

constructor TAtlasIdeIssuePreview.Create(const AHooks: TAtlasIssuePreviewHooks; const ACacheFolder: string);
var
  mLoad: TAtlasIssueLoadHooks;
begin
  inherited Create;
  FMouseHistory := -1;
  FHooks := AHooks;
  FHistory := TAtlasIssueHistory.Create;
  CreateParts(ACacheFolder);
  mLoad := Default(TAtlasIssueLoadHooks);
  mLoad.CanStart := FHooks.CanStart;
  mLoad.CanAttach := FHooks.CanAttach;
  mLoad.CanReview := FHooks.CanReview;
  FLoad := TAtlasIdeIssueLoad.Create(FParts, FHistory, mLoad);
end;

destructor TAtlasIdeIssuePreview.Destroy;
begin
  if FParts <> nil then
  begin
    FParts.Development.Stop;
  end;
  if FLoad <> nil then
  begin
    FLoad.ReleaseThreads(True);
  end;
  FLoad.Free;
  FParts.Free;
  FHistory.Free;
  inherited;
end;

function TAtlasIdeIssuePreview.GetLookups: TAtlasIdeIssueLookups;
begin
  Result := FParts.Lookups;
end;

function TAtlasIdeIssuePreview.GetChecklists: TAtlasIdeIssueChecklists;
begin
  Result := FParts.Checklists;
end;

function TAtlasIdeIssuePreview.GetLinkWrites: TAtlasIdeIssueLinkWrites;
begin
  Result := FParts.LinkWrites;
end;

function TAtlasIdeIssuePreview.MouseStep(AWindow: HWND; AForward: Boolean): Boolean;
var
  mFrame: TAtlasIssueFrame;
begin
  mFrame := FParts.Context.Frame;
  Result := FParts.Context.Started and (mFrame <> nil) and mFrame.HandleAllocated and
    ((AWindow = mFrame.Handle) or IsChild(mFrame.Handle, AWindow));
  if not Result then
  begin
    Exit;
  end;
  if AForward then
  begin
    GoForward;
  end
  else
  begin
    GoBack;
  end;
end;

procedure TAtlasIdeIssuePreview.CreateParts(const ACacheFolder: string);
var
  mOwner: TAtlasIdeIssuePreview;
  mHooks: TAtlasIssuePartsHooks;
begin
  // Eigene Routine: Die anonymen Methoden halten nur Self; die Teile gibt der Destruktor frei.
  mOwner := Self;
  mHooks := Default(TAtlasIssuePartsHooks);
  mHooks.Provider := FHooks.Provider;
  mHooks.Transport := FHooks.Transport;
  mHooks.Comments.CanWrite := FHooks.CanWrite;
  mHooks.Comments.IsActive := FHooks.IsActive;
  mHooks.Comments.Comment := FHooks.Comment;
  mHooks.Comments.CommentAssist := FHooks.CommentAssist;
  mHooks.Comments.CommentSent := FHooks.CommentSent;
  // Nach Stop sind die Hooks leer: dann kein Projekt mehr.
  mHooks.Project :=
    function: string
    begin
      Result := '';
      if Assigned(mOwner.FHooks.Project) then
      begin
        Result := mOwner.FHooks.Project();
      end;
    end;
  mHooks.Reload :=
    procedure(AEntry: TAtlasIssueHistoryEntry)
    begin
      mOwner.FLoad.Load(AEntry);
    end;
  mHooks.Refresh :=
    procedure
    begin
      mOwner.Refresh;
    end;
  FParts := TAtlasIdeIssueParts.Create(Self, mHooks, ACacheFolder);
end;

procedure TAtlasIdeIssuePreview.AddMoveEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  mKeep := AKeep;
  mOwner := Self;
  AEvents.Back :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.GoBack;
      end;
    end;
  AEvents.Forward :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.GoForward;
      end;
    end;
  AEvents.Refresh :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Refresh;
      end;
    end;
  AEvents.Cancel :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.FLoad.CancelLoad;
        mOwner.FParts.Development.Cancel;
      end;
    end;
  AEvents.Hidden :=
    procedure
    begin
      // Fenster geschlossen: Laden und Bilder abbrechen.
      if mKeep <> nil then
      begin
        mOwner.FLoad.CancelLoad;
        mOwner.FParts.Media.Cancel;
        mOwner.FParts.Development.Cancel;
      end;
    end;
  AEvents.Browse :=
    procedure
    begin
      if (mKeep <> nil) and mOwner.FParts.Context.HasCurrent then
      begin
        mOwner.Fix(TAtlasIssueFix.Browser);
      end;
    end;
end;

procedure TAtlasIdeIssuePreview.AddReviewEvent(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  mKeep := AKeep;
  mOwner := Self;
  AEvents.Review :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := mOwner.FParts.Context.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.State.HasDetails and Assigned(mOwner.FHooks.Review) then
      begin
        mOwner.FHooks.Review(mFrame.State.Details.Issue);
      end;
    end;
end;

procedure TAtlasIdeIssuePreview.AddIssueEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  mKeep := AKeep;
  mOwner := Self;
  AEvents.Start :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := mOwner.FParts.Context.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.State.HasDetails and Assigned(mOwner.FHooks.Start) then
      begin
        mOwner.FHooks.Start(mFrame.State.Details.Issue);
      end;
    end;
  AEvents.Finish :=
    procedure
    begin
      if (mKeep <> nil) and mOwner.FParts.Context.HasCurrent and Assigned(mOwner.FHooks.EndIssue) then
      begin
        mOwner.FHooks.EndIssue(mOwner.FParts.Context.Current.Key);
      end;
    end;
  AEvents.CopyKey :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := mOwner.FParts.Context.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.State.HasDetails then
      begin
        Clipboard.AsText := mFrame.State.Details.Key;
      end;
    end;
  AEvents.Attach :=
    procedure
    begin
      if (mKeep <> nil) and mOwner.FParts.Context.HasCurrent and Assigned(mOwner.FHooks.Attach) then
      begin
        mOwner.FHooks.Attach(mOwner.FParts.Context.Current.Target, mOwner.FParts.Context.Current.Key);
      end;
    end;
end;

procedure TAtlasIdeIssuePreview.AddOpenEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  mKeep := AKeep;
  mOwner := Self;
  AEvents.OpenLink :=
    procedure(ALink: TAtlasTrackerLink)
    begin
      if (mKeep = nil) or not mOwner.FParts.Context.HasCurrent then
      begin
        Exit;
      end;
      if ALink.Local then
      begin
        mOwner.Show(mOwner.FParts.Context.Current.Target, ALink.Key);
      end
      else
      begin
        TAtlasIssuePreview.Browse(ALink.Page);
      end;
    end;
  AEvents.Fix :=
    procedure(AFix: TAtlasIssueFix)
    begin
      if mKeep <> nil then
      begin
        mOwner.Fix(AFix);
      end;
    end;
  AEvents.OpenAttachment :=
    procedure(AAttachment: TAtlasTrackerAttachment)
    begin
      if mKeep <> nil then
      begin
        mOwner.FParts.Media.OpenAttachment(AAttachment);
      end;
    end;
  AEvents.OpenUrl :=
    procedure(AUrl: string)
    begin
      // Braucht den Besitzer nicht; nach dem Abmelden öffnet die leere Shell nichts mehr.
      TAtlasIssuePreview.Browse(AUrl);
    end;
  AEvents.Images :=
    procedure(AUrls: TArray<string>)
    begin
      if mKeep <> nil then
      begin
        mOwner.FParts.Media.LoadImages(AUrls);
      end;
    end;
end;

procedure TAtlasIdeIssuePreview.AddWriteEvents(const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  mKeep := AKeep;
  mOwner := Self;
  AEvents.Comment :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.FParts.Comments.Send(AText);
      end;
    end;
  AEvents.ToggleTask :=
    procedure(AIndex: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.FParts.Checklists.Toggle(AIndex);
      end;
    end;
  AEvents.AddTask :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.FParts.Checklists.AddTask;
      end;
    end;
  AEvents.CreateSubtask :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.FParts.LinkWrites.CreateSubtask;
      end;
    end;
  AEvents.AddLink :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.FParts.LinkWrites.AddLink;
      end;
    end;
end;

procedure TAtlasIdeIssuePreview.Wire(AFrame: TAtlasIssueFrame);
var
  mKeep: IInterface;
  mEvents: TAtlasIssueFrameEvents;
begin
  mKeep := Self;
  FParts.Comments.Unbind;
  AFrame.ApplyColors(TAtlasIdeStyle.WindowColorsIf(TAtlasIdeSettings.Current.IssuesIdeColors));
  ApplyMonoFont(AFrame);
  mEvents := Default(TAtlasIssueFrameEvents);
  AddMoveEvents(mKeep, mEvents);
  AddIssueEvents(mKeep, mEvents);
  AddReviewEvent(mKeep, mEvents);
  AddOpenEvents(mKeep, mEvents);
  AddWriteEvents(mKeep, mEvents);
  AFrame.Events := mEvents;
  FParts.Development.Wire(AFrame);
  FLoad.ApplyHookFlags(AFrame);
  FLoad.ShowCurrent;
end;

procedure TAtlasIdeIssuePreview.Fix(AFix: TAtlasIssueFix);
var
  mProvider: IAtlasTrackerProvider;
  mCurrent: TAtlasIssueHistoryEntry;
begin
  if not FParts.Context.HasCurrent then
  begin
    Exit;
  end;
  mCurrent := FParts.Context.Current;
  case AFix of
    TAtlasIssueFix.EnterToken:
      begin
        mProvider := FParts.Context.ProviderOf(mCurrent.Target);
        if (mProvider <> nil) and Assigned(FHooks.Credentials) and FHooks.Credentials(mProvider, mCurrent.Target) then
        begin
          Refresh;
        end;
      end;
    TAtlasIssueFix.Settings:
      if Assigned(FHooks.Settings) then
      begin
        FHooks.Settings();
      end;
    TAtlasIssueFix.Browser:
      // Nur die Seite aus der eingetragenen Adresse, nie eine aus der Antwort.
      TAtlasIssuePreview.BrowseIssue(FParts.Context.ProviderOf(mCurrent.Target), mCurrent.Target, mCurrent.Key);
    TAtlasIssueFix.Retry:
      Refresh;
    TAtlasIssueFix.None:
      begin
        // Nichts zu beheben.
      end;
  end;
end;

procedure TAtlasIdeIssuePreview.Start;
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  if FParts.Context.Started then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeIssueWindow.OnFrame :=
    procedure(AFrame: TAtlasIssueFrame)
    begin
      if (mKeep <> nil) and mOwner.FParts.Context.Started then
      begin
        mOwner.Wire(AFrame);
      end;
    end;
  FParts.Development.Start;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeIssueWindow.Prepare;
  FParts.Context.Start;
  // Zurück-/Vor-Taste der Maus über dem Fenster blättern in dessen Verlauf (#1889).
  FMouseHistory := TAtlasMouseHistory.Register(
    function(AWindow: HWND; ADirection: TAtlasNavDirection): Boolean
    begin
      Result := mOwner.MouseStep(AWindow, ADirection = TAtlasNavDirection.Forward);
    end);
end;

procedure TAtlasIdeIssuePreview.Stop;
begin
  if not FParts.Context.Started then
  begin
    Exit;
  end;
  TAtlasMouseHistory.Unregister(FMouseHistory);
  FMouseHistory := -1;
  FParts.Context.Stop;
  FLoad.CancelLoad;
  FParts.Media.Cancel;
  FParts.Development.Stop;
  FLoad.ReleaseThreads(True);
  // Rückrufe des Editors nicht mehr aufrufen.
  FParts.Lookups.Clear;
  FParts.Comments.Stop;
  TAtlasIdeIssueWindow.Release;
  FLoad.Stop;
  FHooks := Default(TAtlasIssuePreviewHooks);
end;

procedure TAtlasIdeIssuePreview.Show(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  Show(ATarget, AKey, 0);
end;

procedure TAtlasIdeIssuePreview.Show(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if not FParts.Context.Started or not Active or (Trim(AKey) = '') then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mEntry := TAtlasIssueHistoryEntry.Create(ATarget, AKey);
      FHistory.Visit(mEntry);
      mFrame := TAtlasIdeIssueWindow.Show;
      if mFrame <> nil then
      begin
        TAtlasIdeIssueWindow.ApplyTheme;
        mFrame.SetAnchor(AAnchor);
      end;
      FLoad.Load(mEntry);
    end);
end;

procedure TAtlasIdeIssuePreview.Refresh;
begin
  if not FParts.Context.HasCurrent then
  begin
    Exit;
  end;
  FParts.Development.Refresh;
  FLoad.Load(FParts.Context.Current);
end;

procedure TAtlasIdeIssuePreview.GoBack;
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if FHistory.GoBack(mEntry) then
  begin
    FLoad.Load(mEntry);
  end;
end;

procedure TAtlasIdeIssuePreview.GoForward;
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if FHistory.GoForward(mEntry) then
  begin
    FLoad.Load(mEntry);
  end;
end;

procedure TAtlasIdeIssuePreview.UpdateWrite;
begin
  FParts.Comments.UpdateWrite;
end;

procedure TAtlasIdeIssuePreview.ShowChecklist(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mFrame: TAtlasIssueFrame;
begin
  Show(ATarget, AKey);
  mFrame := FParts.Context.Frame;
  if mFrame <> nil then
  begin
    mFrame.RevealChecklist;
  end;
end;

procedure TAtlasIdeIssuePreview.ShowLink(const ATarget: TAtlasTrackerTarget; const ALink: TAtlasTrackerLink);
begin
  case TAtlasIssuePreview.LinkOpen(ALink, FParts.Context.Started and Active) of
    TAtlasIssueLinkOpen.Preview:
      Show(ATarget, ALink.Key);
    TAtlasIssueLinkOpen.Page:
      TAtlasIssuePreview.Browse(ALink.Page);
    TAtlasIssueLinkOpen.IssuePage:
      TAtlasIssuePreview.BrowseIssue(FParts.Context.ProviderOf(ATarget), ATarget, ALink.Key);
  end;
end;

class function TAtlasIdeIssuePreview.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesPreview;
end;

function TAtlasIdeIssuePreview.RecentIssues(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
begin
  Result := FParts.Context.RecentIssues(ATarget);
end;

end.
