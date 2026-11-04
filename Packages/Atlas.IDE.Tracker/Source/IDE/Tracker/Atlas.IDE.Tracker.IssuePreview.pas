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
// - Eine Abfrage zur Zeit: Ein neuer Wunsch bricht die laufende ab und folgt
//   ihr.
// - Aus einer Meldung zu meinen Issues (#1271) öffnet Show mit Anker am
//   ersten neuen Kommentar.
// - Links aus dem Text öffnen nur im Browser (http/https ohne Benutzer).
// - issues.preview.comments aus: Kommentare werden nicht abgefragt.
// - Teile: gemeinsamer Stand TAtlasIdeIssueContext, Kurzabfrage für den Hover
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
  System.SysUtils,
  System.Classes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.IDE.Tracker.Development,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.IDE.Tracker.IssueLookups,
  Atlas.IDE.Tracker.IssueChecklists,
  Atlas.IDE.Tracker.IssueLinkWrites,
  Atlas.IDE.Tracker.IssueMedia,
  Atlas.IDE.Tracker.IssueComments;

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

  /// <summary>Laufende Abfrage des gezeigten Issues und der Wunsch, der ihr folgt.</summary>
  TAtlasIssueLoadState = record
    Thread: TThread;
    Cancel: IAtlasCiCancel;
    Pending: TAtlasIssueHistoryEntry;
    HasPending: Boolean;
  end;

  TAtlasIdeIssuePreview = class(TInterfacedObject)
  private
    FHooks: TAtlasIssuePreviewHooks;
    FHistory: TAtlasIssueHistory;
    FContext: TAtlasIdeIssueContext;
    FLoad: TAtlasIssueLoadState;
    FDevelopment: TAtlasIdeIssueDevelopment;
    FDevelopmentRef: IInterface;
    FLookups: TAtlasIdeIssueLookups;
    FChecklists: TAtlasIdeIssueChecklists;
    FLinkWrites: TAtlasIdeIssueLinkWrites;
    FMedia: TAtlasIdeIssueMedia;
    FComments: TAtlasIdeIssueComments;
    procedure CreateParts(const ACacheFolder: string);
    procedure CreateDevelopment;
    procedure Wire(AFrame: TAtlasIssueFrame);
    procedure Load(const AEntry: TAtlasIssueHistoryEntry);
    procedure Loaded(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
    procedure ShowCurrent;
    procedure CancelLoad;
    procedure ReleaseThreads(AWait: Boolean);
    procedure Fix(AFix: TAtlasIssueFix);
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
    property Lookups: TAtlasIdeIssueLookups read FLookups;
    /// <summary>Fortschritt und Auffrischen der Checklisten fürs Statusfeld (#1273).</summary>
    property Checklists: TAtlasIdeIssueChecklists read FChecklists;
    /// <summary>Verknüpfungen, auch die Prüfung vor „Beginnen“ (#1279).</summary>
    property LinkWrites: TAtlasIdeIssueLinkWrites read FLinkWrites;
  end;

implementation

uses
  ToolsAPI,
  System.DateUtils,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.IssueTip,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.IssueWindow;

function StaleText(const ADetails: TAtlasTrackerDetails; const AReason: string): string;
var
  mWhen: string;
begin
  mWhen := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ADetails.Fetched), FormatSettings);
  if AReason = '' then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewStale, [mWhen]);
  end
  else
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewStaleOffline, [mWhen, AReason]);
  end;
end;

procedure UpdateHistory(AOwner: TAtlasIdeIssuePreview);
var
  mFrame: TAtlasIssueFrame;
begin
  mFrame := AOwner.FContext.Frame;
  if mFrame <> nil then
  begin
    mFrame.SetHistory(AOwner.FHistory.CanBack, AOwner.FHistory.CanForward);
  end;
end;

/// <summary>Issue im Frame zeigen; Baum oder Liste (#1279), die Knöpfe nur, wenn der Anbieter schreiben kann.
/// </summary>
procedure ShowOn(AOwner: TAtlasIdeIssuePreview; AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails;
  const AStatus: string);
var
  mProvider: IAtlasTrackerProvider;
  mLinks: Boolean;
begin
  mProvider := nil;
  if AOwner.FContext.HasCurrent then
  begin
    mProvider := AOwner.FContext.ProviderOf(AOwner.FContext.Current.Target);
  end;
  mLinks := TAtlasIdeSettings.Current.IssuesPreviewLinks;
  AFrame.SetFlag(TAtlasIssueFlag.LinksAsTree, mLinks);
  AFrame.SetFlag(TAtlasIssueFlag.CanWriteLinks, mLinks and Supports(mProvider, IAtlasTrackerLinkWriter));
  AFrame.ShowDetails(ADetails, TAtlasIdeIssueContext.NowUtc, AStatus,
    not TAtlasIdeSettings.Current.IssuesPreviewComments);
end;

/// <summary>Schalter aus den Hooks: „Beginnen“ und „Anhängen …“.</summary>
procedure ApplyHookFlags(AOwner: TAtlasIdeIssuePreview; AFrame: TAtlasIssueFrame);
begin
  if Assigned(AOwner.FHooks.CanStart) then
  begin
    AFrame.SetFlag(TAtlasIssueFlag.CanStart, AOwner.FHooks.CanStart());
  end;
  AFrame.SetFlag(TAtlasIssueFlag.CanAttach, Assigned(AOwner.FHooks.CanAttach) and AOwner.FHooks.CanAttach());
end;

{ Ereignisse des Frames }

/// <summary>Zurück, Vor, Aktualisieren, Abbrechen, Schließen und Browser.</summary>
procedure AddMoveEvents(AOwner: TAtlasIdeIssuePreview; const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
begin
  mKeep := AKeep;
  AEvents.Back :=
    procedure
    begin
      if mKeep <> nil then
      begin
        AOwner.GoBack;
      end;
    end;
  AEvents.Forward :=
    procedure
    begin
      if mKeep <> nil then
      begin
        AOwner.GoForward;
      end;
    end;
  AEvents.Refresh :=
    procedure
    begin
      if mKeep <> nil then
      begin
        AOwner.Refresh;
      end;
    end;
  AEvents.Cancel :=
    procedure
    begin
      if mKeep <> nil then
      begin
        AOwner.CancelLoad;
        AOwner.FDevelopment.Cancel;
      end;
    end;
  AEvents.Hidden :=
    procedure
    begin
      // Fenster geschlossen: Laden und Bilder abbrechen.
      if mKeep <> nil then
      begin
        AOwner.CancelLoad;
        AOwner.FMedia.Cancel;
        AOwner.FDevelopment.Cancel;
      end;
    end;
  AEvents.Browse :=
    procedure
    begin
      if (mKeep <> nil) and AOwner.FContext.HasCurrent then
      begin
        AOwner.Fix(TAtlasIssueFix.Browser);
      end;
    end;
end;

/// <summary>Beginnen, Beenden, Kennung kopieren und Anhängen.</summary>
procedure AddIssueEvents(AOwner: TAtlasIdeIssuePreview; const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
begin
  mKeep := AKeep;
  AEvents.Start :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := AOwner.FContext.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.State.HasDetails and Assigned(AOwner.FHooks.Start) then
      begin
        AOwner.FHooks.Start(mFrame.State.Details.Issue);
      end;
    end;
  AEvents.Finish :=
    procedure
    begin
      if (mKeep <> nil) and AOwner.FContext.HasCurrent and Assigned(AOwner.FHooks.EndIssue) then
      begin
        AOwner.FHooks.EndIssue(AOwner.FContext.Current.Key);
      end;
    end;
  AEvents.CopyKey :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := AOwner.FContext.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.State.HasDetails then
      begin
        Clipboard.AsText := mFrame.State.Details.Key;
      end;
    end;
  AEvents.Attach :=
    procedure
    begin
      if (mKeep <> nil) and AOwner.FContext.HasCurrent and Assigned(AOwner.FHooks.Attach) then
      begin
        AOwner.FHooks.Attach(AOwner.FContext.Current.Target, AOwner.FContext.Current.Key);
      end;
    end;
end;

/// <summary>Verknüpftes Issue, Beheben, Anhang, Adresse und Bilder öffnen bzw. laden.</summary>
procedure AddOpenEvents(AOwner: TAtlasIdeIssuePreview; const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
begin
  mKeep := AKeep;
  AEvents.OpenLink :=
    procedure(ALink: TAtlasTrackerLink)
    begin
      if (mKeep = nil) or not AOwner.FContext.HasCurrent then
      begin
        Exit;
      end;
      if ALink.Local then
      begin
        AOwner.Show(AOwner.FContext.Current.Target, ALink.Key);
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
        AOwner.Fix(AFix);
      end;
    end;
  AEvents.OpenAttachment :=
    procedure(AAttachment: TAtlasTrackerAttachment)
    begin
      if mKeep <> nil then
      begin
        AOwner.FMedia.OpenAttachment(AAttachment);
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
        AOwner.FMedia.LoadImages(AUrls);
      end;
    end;
end;

/// <summary>Kommentar, Checkliste (#1273) und Verknüpfungen (#1279) schreiben.</summary>
procedure AddWriteEvents(AOwner: TAtlasIdeIssuePreview; const AKeep: IInterface; var AEvents: TAtlasIssueFrameEvents);
var
  mKeep: IInterface;
begin
  mKeep := AKeep;
  AEvents.Comment :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
      begin
        AOwner.FComments.Send(AText);
      end;
    end;
  AEvents.ToggleTask :=
    procedure(AIndex: Integer)
    begin
      if mKeep <> nil then
      begin
        AOwner.FChecklists.Toggle(AIndex);
      end;
    end;
  AEvents.AddTask :=
    procedure
    begin
      if mKeep <> nil then
      begin
        AOwner.FChecklists.AddTask;
      end;
    end;
  AEvents.CreateSubtask :=
    procedure
    begin
      if mKeep <> nil then
      begin
        AOwner.FLinkWrites.CreateSubtask;
      end;
    end;
  AEvents.AddLink :=
    procedure
    begin
      if mKeep <> nil then
      begin
        AOwner.FLinkWrites.AddLink;
      end;
    end;
end;

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

{ Laden }

/// <summary>Frisch geladen: Zwischenspeicher, zuletzt geöffnet und Fenster mit den Meldungen der Teile.</summary>
procedure ShowLoaded(AOwner: TAtlasIdeIssuePreview; AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry;
  const ADetails: TAtlasTrackerDetails);
var
  mDetails: TAtlasTrackerDetails;
  mNotice: string;
begin
  mDetails := ADetails;
  mDetails.Fetched := TAtlasIdeIssueContext.NowUtc;
  AOwner.FContext.Cache.Put(AEntry.Target, mDetails);
  AOwner.FContext.Remember(AEntry.Target, mDetails.Issue);
  // Nach einem abgewiesenen Abhaken (Beschreibung geändert): Hinweis über dem neuen Stand.
  mNotice := AOwner.FChecklists.TakeNotice;
  if AFrame = nil then
  begin
    AOwner.FLinkWrites.TakeNotice;
    Exit;
  end;
  AFrame.SetFlag(TAtlasIssueFlag.Loading, False);
  ApplyHookFlags(AOwner, AFrame);
  AOwner.FChecklists.Prepare(AFrame, AEntry);
  // Meldung nach dem Anlegen bzw. Verknüpfen (#1279) über dem frischen Stand.
  ShowOn(AOwner, AFrame, mDetails, AOwner.FLinkWrites.TakeNotice);
  AOwner.FComments.UpdateWrite;
  if mNotice <> '' then
  begin
    AFrame.ShowNotice(mNotice);
  end;
end;

/// <summary>Nicht geladen: ohne Netz der letzte Stand mit Grund, sonst die Meldung; abgebrochen nichts.</summary>
procedure ShowFailed(AOwner: TAtlasIdeIssuePreview; AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry;
  AError: TAtlasCiFetchError);
var
  mCached: TAtlasTrackerDetails;
begin
  AOwner.FChecklists.TakeNotice;
  if AFrame = nil then
  begin
    Exit;
  end;
  AFrame.SetFlag(TAtlasIssueFlag.Loading, False);
  if AError = TAtlasCiFetchError.Cancelled then
  begin
    Exit;
  end;
  if AOwner.FContext.Cache.Get(AEntry.Target, AEntry.Key, TAtlasIdeIssueContext.NowUtc, mCached) then
  begin
    ShowOn(AOwner, AFrame, mCached, StaleText(mCached, TAtlasIssueTip.ErrorText(AError, AEntry.Key)));
  end
  else
  begin
    AFrame.ShowError(TAtlasIssueTip.ErrorText(AError, AEntry.Key), TAtlasIssuePreview.FixOf(AError));
  end;
end;

/// <summary>Sofort der letzte Stand aus dem Zwischenspeicher; frisch geladen ersetzt ihn.</summary>
procedure ShowCached(AOwner: TAtlasIdeIssuePreview; const AEntry: TAtlasIssueHistoryEntry);
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
begin
  mFrame := AOwner.FContext.Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  AOwner.FChecklists.Prepare(mFrame, AEntry);
  if AOwner.FContext.Cache.Get(AEntry.Target, AEntry.Key, TAtlasIdeIssueContext.NowUtc, mDetails) then
  begin
    ShowOn(AOwner, mFrame, mDetails, StaleText(mDetails, ''));
    AOwner.FContext.Remember(AEntry.Target, mDetails.Issue);
  end;
  mFrame.SetFlag(TAtlasIssueFlag.Loading, True);
end;

/// <summary>Abfrage im Hintergrund; das Ergebnis über Loaded im Hauptthread.</summary>
procedure StartLoad(AOwner: TAtlasIdeIssuePreview; AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
  const AProvider: IAtlasTrackerProvider; const ATransport: IAtlasCiTransport);
var
  mKeep: IInterface;
  mEntry: TAtlasIssueHistoryEntry;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mComments: Boolean;
begin
  mKeep := AOwner.FContext.Keep;
  mEntry := AEntry;
  mProvider := AProvider;
  mTransport := ATransport;
  mComments := TAtlasIdeSettings.Current.IssuesPreviewComments;
  AOwner.FLoad.Thread := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasTrackerDetails;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mResult := TAtlasTrackerDetails.Empty;
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        mOk := mProvider.Details(TAtlasTrackerCall.Create(mEntry.Target, mTransport, TAtlasIssuePreview.TimeoutMs),
          mEntry.Key, mComments, mResult, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Vorschau: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
          begin
            AOwner.Loaded(AGeneration, mEntry, mOk, mResult, mError);
          end;
        end);
    end);
  AOwner.FLoad.Thread.FreeOnTerminate := False;
  AOwner.FLoad.Thread.Start;
end;

{ TAtlasIdeIssuePreview }

constructor TAtlasIdeIssuePreview.Create(const AHooks: TAtlasIssuePreviewHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FHistory := TAtlasIssueHistory.Create;
  CreateParts(ACacheFolder);
  CreateDevelopment;
end;

destructor TAtlasIdeIssuePreview.Destroy;
begin
  if FDevelopment <> nil then
  begin
    FDevelopment.Stop;
  end;
  FDevelopment := nil;
  FDevelopmentRef := nil;
  ReleaseThreads(True);
  FComments.Free;
  FMedia.Free;
  FLinkWrites.Free;
  FChecklists.Free;
  FLookups.Free;
  FContext.Free;
  FHistory.Free;
  inherited;
end;

procedure TAtlasIdeIssuePreview.CreateParts(const ACacheFolder: string);
var
  mOwner: TAtlasIdeIssuePreview;
  mComments: TAtlasIssueCommentHooks;
begin
  // Eigene Routine: Die anonymen Methoden halten nur Self; die Teile gibt der Destruktor frei.
  mOwner := Self;
  FContext := TAtlasIdeIssueContext.Create(Self, FHooks.Provider, FHooks.Transport, ACacheFolder);
  FLookups := TAtlasIdeIssueLookups.Create(FContext);
  FChecklists := TAtlasIdeIssueChecklists.Create(FContext,
    procedure(AEntry: TAtlasIssueHistoryEntry)
    begin
      mOwner.Load(AEntry);
    end);
  FLinkWrites := TAtlasIdeIssueLinkWrites.Create(FContext,
    procedure
    begin
      mOwner.Refresh;
    end);
  FMedia := TAtlasIdeIssueMedia.Create(FContext);
  mComments := Default(TAtlasIssueCommentHooks);
  mComments.CanWrite := FHooks.CanWrite;
  mComments.IsActive := FHooks.IsActive;
  mComments.Comment := FHooks.Comment;
  mComments.CommentAssist := FHooks.CommentAssist;
  mComments.CommentSent := FHooks.CommentSent;
  FComments := TAtlasIdeIssueComments.Create(FContext, mComments,
    procedure
    begin
      mOwner.Refresh;
    end);
end;

procedure TAtlasIdeIssuePreview.CreateDevelopment;
var
  mHooks: TAtlasIssueDevelopmentHooks;
  mOwner: TAtlasIdeIssuePreview;
  mContext: TAtlasIdeIssueContext;
begin
  // Eigene Routine: Die anonymen Methoden halten nur Self und den Kontext. Stop der Entwicklung löst sie wieder.
  mOwner := Self;
  mContext := FContext;
  mHooks := Default(TAtlasIssueDevelopmentHooks);
  mHooks.Provider :=
    function(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider
    begin
      Result := mContext.ProviderOf(ATarget);
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := mContext.TransportOf(AProvider, ATarget);
    end;
  mHooks.Project :=
    function: string
    begin
      Result := '';
      if Assigned(mOwner.FHooks.Project) then
      begin
        Result := mOwner.FHooks.Project();
      end;
    end;
  mHooks.Browse :=
    procedure(AUrl: string)
    begin
      TAtlasIssuePreview.Browse(AUrl);
    end;
  mHooks.Frame :=
    function: TAtlasIssueFrame
    begin
      Result := mContext.Frame;
    end;
  FDevelopment := TAtlasIdeIssueDevelopment.Create(mHooks);
  FDevelopmentRef := FDevelopment;
end;

class function TAtlasIdeIssuePreview.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesPreview;
end;

procedure TAtlasIdeIssuePreview.Start;
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  if FContext.Started then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeIssueWindow.OnFrame :=
    procedure(AFrame: TAtlasIssueFrame)
    begin
      if (mKeep <> nil) and mOwner.FContext.Started then
      begin
        mOwner.Wire(AFrame);
      end;
    end;
  FDevelopment.Start;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeIssueWindow.Prepare;
  FContext.Start;
end;

function TAtlasIdeIssuePreview.RecentIssues(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
begin
  Result := FContext.RecentIssues(ATarget);
end;

procedure TAtlasIdeIssuePreview.Stop;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  FContext.Stop;
  CancelLoad;
  FMedia.Cancel;
  FDevelopment.Stop;
  ReleaseThreads(True);
  // Rückrufe des Editors nicht mehr aufrufen.
  FLookups.Clear;
  FComments.Stop;
  TAtlasIdeIssueWindow.Release;
  FHooks := Default(TAtlasIssuePreviewHooks);
end;

procedure TAtlasIdeIssuePreview.ReleaseThreads(AWait: Boolean);
begin
  FContext.Retire(FLoad.Thread);
  FLoad.Thread := nil;
  FMedia.Retire;
  FContext.ReleaseThreads(AWait);
end;

procedure TAtlasIdeIssuePreview.Wire(AFrame: TAtlasIssueFrame);
var
  mKeep: IInterface;
  mEvents: TAtlasIssueFrameEvents;
begin
  mKeep := Self;
  FComments.Unbind;
  AFrame.ApplyColors(TAtlasIdeStyle.Colors);
  ApplyMonoFont(AFrame);
  mEvents := Default(TAtlasIssueFrameEvents);
  AddMoveEvents(Self, mKeep, mEvents);
  AddIssueEvents(Self, mKeep, mEvents);
  AddOpenEvents(Self, mKeep, mEvents);
  AddWriteEvents(Self, mKeep, mEvents);
  AFrame.Events := mEvents;
  if Assigned(FHooks.CanStart) then
  begin
    AFrame.SetFlag(TAtlasIssueFlag.CanStart, FHooks.CanStart());
  end;
  FDevelopment.Wire(AFrame);
  AFrame.SetFlag(TAtlasIssueFlag.CanAttach, Assigned(FHooks.CanAttach) and FHooks.CanAttach());
  ShowCurrent;
end;

procedure TAtlasIdeIssuePreview.Show(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  Show(ATarget, AKey, 0);
end;

procedure TAtlasIdeIssuePreview.Show(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if not FContext.Started or not Active or (Trim(AKey) = '') then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
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
      Load(mEntry);
    end);
end;

procedure TAtlasIdeIssuePreview.Refresh;
begin
  if not FContext.HasCurrent then
  begin
    Exit;
  end;
  FDevelopment.Refresh;
  Load(FContext.Current);
end;

procedure TAtlasIdeIssuePreview.GoBack;
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if FHistory.GoBack(mEntry) then
  begin
    Load(mEntry);
  end;
end;

procedure TAtlasIdeIssuePreview.GoForward;
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if FHistory.GoForward(mEntry) then
  begin
    Load(mEntry);
  end;
end;

procedure TAtlasIdeIssuePreview.CancelLoad;
begin
  FLoad.HasPending := False;
  if FLoad.Cancel <> nil then
  begin
    FLoad.Cancel.Cancel;
  end;
end;

procedure TAtlasIdeIssuePreview.UpdateWrite;
begin
  FComments.UpdateWrite;
end;

procedure TAtlasIdeIssuePreview.ShowCurrent;
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
  mCurrent: TAtlasIssueHistoryEntry;
begin
  mFrame := FContext.Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  UpdateHistory(Self);
  FComments.UpdateWrite;
  if not FContext.HasCurrent then
  begin
    mFrame.ShowEmpty;
    Exit;
  end;
  mCurrent := FContext.Current;
  FChecklists.Prepare(mFrame, mCurrent);
  if FContext.Cache.Get(mCurrent.Target, mCurrent.Key, TAtlasIdeIssueContext.NowUtc, mDetails) then
  begin
    ShowOn(Self, mFrame, mDetails, '');
  end;
end;

procedure TAtlasIdeIssuePreview.Load(const AEntry: TAtlasIssueHistoryEntry);
var
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mGeneration: Integer;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  // Eine Abfrage zur Zeit: die laufende abbrechen, dieser Wunsch folgt ihr.
  ReleaseThreads(False);
  if FLoad.Thread <> nil then
  begin
    FLoad.Pending := AEntry;
    FLoad.HasPending := True;
    if FLoad.Cancel <> nil then
    begin
      FLoad.Cancel.Cancel;
    end;
    Exit;
  end;
  FMedia.Cancel;
  mGeneration := FContext.Select(AEntry);
  FComments.UpdateWrite;
  FDevelopment.Select(AEntry.Target, AEntry.Key);
  UpdateHistory(Self);
  ShowCached(Self, AEntry);
  mProvider := FContext.ProviderOf(AEntry.Target);
  // Der Transport entsteht hier, damit „Abbrechen“ ihn erreicht; er liest das Token ohne Dialog.
  mTransport := FContext.TransportOf(mProvider, AEntry.Target);
  if mTransport = nil then
  begin
    if (mProvider = nil) or not FContext.CanTransport then
    begin
      Loaded(mGeneration, AEntry, False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.NotConfigured);
    end
    else
    begin
      Loaded(mGeneration, AEntry, False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.Unauthorized);
    end;
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FLoad.Cancel) then
  begin
    FLoad.Cancel := nil;
  end;
  StartLoad(Self, mGeneration, AEntry, mProvider, mTransport);
end;

procedure TAtlasIdeIssuePreview.Loaded(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
  ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
var
  mProvider: IAtlasTrackerProvider;
begin
  FLoad.Cancel := nil;
  ReleaseThreads(False);
  if not FContext.Started then
  begin
    Exit;
  end;
  mProvider := FContext.ProviderOf(AEntry.Target);
  if mProvider <> nil then
  begin
    TAtlasGuard.Log(Format('Issue-Vorschau: %s, %s', [mProvider.Name, TAtlasIdeIssueContext.LoadState(ASucceeded, AError)]));
  end;
  // Ein anderer Wunsch wartet: der zählt.
  if FLoad.HasPending then
  begin
    FLoad.HasPending := False;
    Load(FLoad.Pending);
  end
  else if AGeneration <> FContext.Generation then
  begin
    // Veraltet: ein neuerer Wunsch läuft.
  end
  else if ASucceeded then
  begin
    ShowLoaded(Self, FContext.Frame, AEntry, ADetails);
  end
  else
  begin
    ShowFailed(Self, FContext.Frame, AEntry, AError);
  end;
end;

procedure TAtlasIdeIssuePreview.ShowChecklist(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mFrame: TAtlasIssueFrame;
begin
  Show(ATarget, AKey);
  mFrame := FContext.Frame;
  if mFrame <> nil then
  begin
    mFrame.RevealChecklist;
  end;
end;

procedure TAtlasIdeIssuePreview.ShowLink(const ATarget: TAtlasTrackerTarget; const ALink: TAtlasTrackerLink);
begin
  if ALink.Local and FContext.Started and Active then
  begin
    Show(ATarget, ALink.Key);
  end
  else if ALink.Page <> '' then
  begin
    TAtlasIssuePreview.Browse(ALink.Page);
  end
  else
  begin
    // Nur die Seite aus der eingetragenen Adresse.
    TAtlasIssuePreview.BrowseIssue(FContext.ProviderOf(ATarget), ATarget, ALink.Key);
  end;
end;

procedure TAtlasIdeIssuePreview.Fix(AFix: TAtlasIssueFix);
var
  mProvider: IAtlasTrackerProvider;
  mCurrent: TAtlasIssueHistoryEntry;
begin
  if not FContext.HasCurrent then
  begin
    Exit;
  end;
  mCurrent := FContext.Current;
  case AFix of
    TAtlasIssueFix.EnterToken:
      begin
        mProvider := FContext.ProviderOf(mCurrent.Target);
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
      TAtlasIssuePreview.BrowseIssue(FContext.ProviderOf(mCurrent.Target), mCurrent.Target, mCurrent.Key);
    TAtlasIssueFix.Retry:
      Refresh;
    TAtlasIssueFix.None:
      begin
        // Nichts zu beheben.
      end;
  end;
end;

end.
