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
// - Bilder: nur vom Server des Tokens (TAtlasIssuePreview.MayLoad), im
//   Hintergrund über IAtlasCiDownload, höchstens MaxImages je Issue.
// - Anhänge: Doppelklick lädt nach %TEMP%\Atlas\issues\<Kennung>\ und öffnet
//   mit dem zugeordneten Programm; ausführbare Dateien zeigt Atlas nur im
//   Explorer. Dateien anderer Server (GitHub) öffnen im Browser.
// - Links aus dem Text öffnen nur im Browser (http/https ohne Benutzer).
// - issues.preview.comments aus: Kommentare werden nicht abgefragt.
// - Tracker nachführen (#1266): Mit issues.syncState und einem Tracker, der
//   schreiben kann (Hook CanWrite), gibt es unten „Kommentar schreiben …“
//   (Strg+Enter sendet, danach wird das Issue neu geladen) und für das
//   aktuelle Issue (Hook IsActive) den Knopf „Beenden …“ (Hook EndIssue).
// - Checklisten (#1273, issues.preview.checklists): Klick auf ein Kästchen
//   bzw. „Punkt hinzufügen …“ lädt im Hintergrund die aktuelle Beschreibung
//   (IAtlasTrackerDescriptions), prüft die Zeile (TAtlasTrackerChecklist),
//   schreibt zurück und zeigt den neuen Text; ein Schreiben zur Zeit. Wurde
//   die Beschreibung inzwischen geändert, schreibt Atlas nichts, lädt neu und
//   meldet es. Lehnt der Tracker ab (401/403) oder kann der Anbieter nicht
//   schreiben, bleibt die Liste für dieses Issue in der Sitzung nur lesbar.
// - Statusfeld (#1273, issues.checklistStatus): ChecklistProgress liest den
//   Fortschritt aus dem Zwischenspeicher, Prefetch frischt ihn höchstens alle
//   PrefetchMinutes im Hintergrund auf, ShowChecklist öffnet an der Liste.
// - Verknüpfungen (#1279, issues.preview.links): Baum statt Liste; kann der
//   Anbieter schreiben (IAtlasTrackerLinkWriter), legen „Unteraufgabe
//   anlegen …“ und „Verknüpfen …“ nach dem Dialog im Hintergrund an
//   (Zeitgrenze 15 s), danach lädt das Fenster neu und meldet das Ergebnis
//   über dem Inhalt. CheckBlocked liest für „Beginnen“ (issues.warnBlocked) die
//   Verknüpfungen frisch (5 s, ohne Kommentare), ohne Netz aus dem
//   Zwischenspeicher.
// - Kommentar-Editor (#1278): Das Kommentarfeld wird je gezeigtem Issue an
//   Hook CommentAssist gebunden (Vorschläge, Textbausteine, Entwurf des Felds
//   "preview"); beim Wechsel des Issues bleibt der Entwurf gespeichert und das
//   Feld wird leer. Kommt das Senden zurück, wenn schon ein anderes Issue
//   gezeigt wird, löscht Hook CommentSent den Entwurf des gesendeten.
// - Zuletzt geöffnet (#1270): jedes gezeigte Issue kommt in
//   TAtlasRecentIssues (<Zwischenspeicher>\recent.json); die Befehlspalette
//   zeigt sie bei leerem "#".
// - Reiter „Entwicklung“ (#1269): TAtlasIdeIssueDevelopment folgt dem
//   gezeigten Issue, „Aktualisieren“ und „Abbrechen“ gelten auch dort.
// - „Anhängen …“ (#1276, issues.attach) im Fenster ruft den Hook Attach mit
//   Tracker und Kennung des gezeigten Issues.
// - Protokoll anonym: nur Anbieter, Ergebnis und Fehlerart, nie Adresse,
//   Kennung, Titel oder Token.
// - Kurzabfrage für den Hover über Kennungen im Editor (#1265): Peek liest nur
//   den Zwischenspeicher (kein Netz), Lookup fragt im Hintergrund ohne
//   Kommentare; gleiche Wünsche laufen einmal, nicht gefundene Kennungen
//   fragt Atlas MissingMs lang nicht erneut. Vorhandene Kommentare im
//   Zwischenspeicher bleiben erhalten.
// Anbieter, Transport, Zugang, „Beginnen“ und die Einstellungsseite kommen
// über Hooks (Komposition bzw. „Meine Issues“).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.IssueCache,
  Atlas.Core.Tracker.PaletteSearch,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.EndDialog,
  Atlas.IDE.Tracker.Development;

type
  TAtlasIssuePreviewProviderHook = reference to function(const AName: string): IAtlasTrackerProvider;
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token. Läuft im Hintergrund.</summary>
  TAtlasIssuePreviewTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  TAtlasIssuePreviewCredentialsHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): Boolean;

  /// <summary>Kommentar zu AKey schreiben (#1266); ADone im Hauptthread, genau einmal.</summary>
  TAtlasIssuePreviewCommentHook = reference to procedure(const ATarget: TAtlasTrackerTarget;
    const AKey, AText: string; const ADone: TAtlasTrackerSendDone);
  /// <summary>Kommentar-Editor für das Kommentarfeld zu AKey (#1278); nil mit issues.commentEditor aus.</summary>
  TAtlasIssuePreviewAssistHook = reference to function(const ATarget: TAtlasTrackerTarget;
    const AKey: string): IAtlasCommentAssist;
  TAtlasIssuePreviewSentHook = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string);

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

  /// <summary>Ende einer Kurzabfrage (#1265); im Hauptthread.</summary>
  TAtlasIssueLookupDone = reference to procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails;
    AError: TAtlasCiFetchError);

  /// <summary>Schreibender Auftrag im Hintergrund (#1279); AKey: Kennung des angelegten bzw. verknüpften Issues.
  /// </summary>
  TAtlasIssueWriteWork = reference to function(const AWriter: IAtlasTrackerLinkWriter;
    const ATransport: IAtlasCiTransport; out AKey: string; out AError: TAtlasCiFetchError): Boolean;
  /// <summary>Ende eines schreibenden Auftrags, im Hauptthread.</summary>
  TAtlasIssueWriteDone = reference to procedure(ASucceeded: Boolean; const AKey: string;
    AError: TAtlasCiFetchError);
  /// <summary>Ergebnis von CheckBlocked im Hauptthread: AKnown = frisch geladen oder aus dem Zwischenspeicher.
  /// </summary>
  TAtlasIssueBlockedDone = reference to procedure(AKnown: Boolean; const ADetails: TAtlasTrackerDetails);

  TAtlasIdeIssuePreview = class(TInterfacedObject)
  public const
    MaxImages = 10;
    /// <summary>So lange gilt ein Stand im Zwischenspeicher für den Hover als frisch (keine neue Abfrage).</summary>
    FreshMs = 10 * 60 * 1000;
    /// <summary>So lange fragt der Hover eine nicht gefundene Kennung nicht erneut.</summary>
    MissingMs = 10 * 60 * 1000;
    /// <summary>So lange gilt der Fortschritt einer Checkliste im Zwischenspeicher fürs Statusfeld (#1273).</summary>
    PrefetchMinutes = 10;
    /// <summary>Zeitgrenze für Anlegen und Verknüpfen (#1279).</summary>
    WriteTimeoutMs = 15000;
    /// <summary>Zeitgrenze der Prüfung vor „Beginnen“ (#1279).</summary>
    BlockedTimeoutMs = 5000;
  private type
    TChecklistChange = (Toggle, Append);
  private
    FHooks: TAtlasIssuePreviewHooks;
    FHistory: TAtlasIssueHistory;
    FCache: TAtlasTrackerIssueCache;
    FStarted: Boolean;
    FCurrent: TAtlasIssueHistoryEntry;
    FHasCurrent: Boolean;
    FThread: TThread;
    FCancel: IAtlasCiCancel;
    FPending: TAtlasIssueHistoryEntry;
    FHasPending: Boolean;
    FImageThread: TThread;
    FImageCancel: IAtlasCiCancel;
    FWorkers: TList<TThread>;
    FGeneration: Integer;
    // Laufende Kurzabfragen (Tracker|Kennung → Rückrufe) und nicht gefundene Kennungen (→ Zeitpunkt).
    FLookups: TDictionary<string, TArray<TAtlasIssueLookupDone>>;
    FMissing: TDictionary<string, UInt64>;
    // Checklisten (#1273): ein Schreiben zur Zeit, Hinweis nach dem Neuladen, nur lesbare Issues der Sitzung.
    FWriting: Boolean;
    FPendingNotice: string;
    FReadOnly: TStringList;
    // Statusfeld: zuletzt angestoßene Auffrischung (Kennung und Zeit, UTC).
    FPrefetchKey: string;
    FPrefetchAt: TDateTime;
    FPrefetching: Boolean;
    // Meldung nach Anlegen bzw. Verknüpfen, gezeigt mit dem frisch geladenen Stand (#1279).
    FNotice: string;
    FRecent: TAtlasRecentIssues;
    FRecentFile: string;
    /// <summary>Tracker und Kennung, an die das Kommentarfeld gebunden ist; '' = ungebunden.</summary>
    FBoundKey: string;
    FBoundActive: Boolean;
    FDevelopment: TAtlasIdeIssueDevelopment;
    FDevelopmentRef: IInterface;
    function Frame: TAtlasIssueFrame;
    procedure PrepareFrame(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry);
    function ReadOnlyKey(const AEntry: TAtlasIssueHistoryEntry): string;
    procedure ToggleTask(AIndex: Integer);
    procedure AddTask;
    procedure ChangeChecklist(AChange: TChecklistChange; const AItem: TAtlasChecklistItem; const AText: string);
    procedure ChecklistWritten(const AEntry: TAtlasIssueHistoryEntry; AApplied, AChanged, ADenied: Boolean;
      AError: TAtlasCiFetchError; const AText: string);
    procedure Prefetched(const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails);
    /// <summary>Kommentarfeld an das gezeigte Issue binden (#1278).</summary>
    procedure BindComment(AFrame: TAtlasIssueFrame; AWrite: Boolean);
    /// <summary>AIssue zuerst unter „zuletzt geöffnet“ und speichern.</summary>
    procedure Remember(const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue);
    procedure CreateDevelopment;
    procedure Wire(AFrame: TAtlasIssueFrame);
    function ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    procedure Load(const AEntry: TAtlasIssueHistoryEntry);
    procedure Loaded(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
    procedure LoadImages(const AUrls: TArray<string>);
    procedure ImageLoaded(AGeneration: Integer; const AUrl: string; const ABytes: TBytes);
    procedure OpenAttachment(const AAttachment: TAtlasTrackerAttachment);
    procedure AttachmentLoaded(const AFileName: string; ASucceeded: Boolean; const AName: string);
    procedure ShowCurrent;
    procedure UpdateHistory;
    procedure CancelLoad;
    procedure CancelImages;
    procedure ReleaseThreads(AWait: Boolean);
    function StaleText(const ADetails: TAtlasTrackerDetails; const AReason: string): string;
    procedure Fix(AFix: TAtlasIssueFix);
    procedure LookedUp(const AId: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
    class function LookupId(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    class procedure Deliver(const ADone: TAtlasIssueLookupDone; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError); static;
    procedure SendComment(const AText: string);
    procedure ShowOn(AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails; const AStatus: string);
    procedure CreateSubtask;
    procedure AddLink;
    procedure RunWrite(const ATarget: TAtlasTrackerTarget; const AWork: TAtlasIssueWriteWork;
      const ADone: TAtlasIssueWriteDone);
    procedure Written(const AText: string);
    procedure WriteFailed(const AText: string; AError: TAtlasCiFetchError);
    class function NowUtc: TDateTime; static;
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
    /// <summary>Letzter Stand von AKey aus dem Zwischenspeicher (#1265); ohne Netz.</summary>
    function Peek(const ATarget: TAtlasTrackerTarget; const AKey: string; out ADetails: TAtlasTrackerDetails): Boolean;
    /// <summary>Stand jünger als FreshMs?</summary>
    class function Fresh(const ADetails: TAtlasTrackerDetails): Boolean; static;
    /// <summary>AKey im Hintergrund ohne Kommentare abfragen und in den Zwischenspeicher legen (#1265); ADone im
    /// Hauptthread, auch sofort (kein Anbieter, kein Token, kürzlich nicht gefunden). Nach Stop wirkungslos.
    /// </summary>
    procedure Lookup(const ATarget: TAtlasTrackerTarget; const AKey: string; const ADone: TAtlasIssueLookupDone);
    /// <summary>Kommentarfeld und „Beenden …“ nach issues.syncState und dem aktuellen Issue (#1266); nach
    /// „Beginnen“, „Beenden“ und geänderten Einstellungen.</summary>
    procedure UpdateWrite;
    /// <summary>Wie Show und dann zur Checkliste blättern (Klick im Statusfeld, #1273).</summary>
    procedure ShowChecklist(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>Fortschritt der Checkliste von AKey aus dem Zwischenspeicher (ohne Netz); False ohne Stand.</summary>
    function ChecklistProgress(const ATarget: TAtlasTrackerTarget; const AKey: string;
      out AProgress: TAtlasChecklistProgress): Boolean;
    /// <summary>Stand von AKey im Hintergrund auffrischen, wenn er fehlt oder älter als PrefetchMinutes ist; je
    /// Kennung höchstens einmal in PrefetchMinutes (auch nach einem Fehler). Ohne Fenster.</summary>
    procedure Prefetch(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>Verknüpfungen von AKey für die Warnung beim Beginnen (#1279): frisch im Hintergrund, ohne Antwort
    /// der letzte Stand; ADone im Hauptthread (sofort, wenn kein Transport da ist).</summary>
    procedure CheckBlocked(const ATarget: TAtlasTrackerTarget; const AKey: string;
      const ADone: TAtlasIssueBlockedDone);
    /// <summary>Verknüpftes Issue zeigen: im Fenster, wenn es im selben Tracker liegt und die Vorschau an ist,
    /// sonst im Browser.</summary>
    procedure ShowLink(const ATarget: TAtlasTrackerTarget; const ALink: TAtlasTrackerLink);
    /// <summary>issues.preview an?</summary>
    class function Active: Boolean; static;
    /// <summary>Zuletzt gezeigte Issues des Trackers ATarget, neueste zuerst (#1270).</summary>
    function RecentIssues(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
  end;

implementation

uses
  Winapi.Windows,
  ToolsAPI,
  System.IOUtils,
  System.StrUtils,
  System.DateUtils,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Vcl.Dialogs,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Tracker.CommentEditor,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tracker.LinkDialogs,
  Atlas.IDE.Tracker.IssueWindow;

/// <summary>Ergebnis eines Abrufs fürs Log: "geladen" oder "nicht geladen (Fehlerkennung)".</summary>
function LoadState(ASucceeded: Boolean; AError: TAtlasCiFetchError): string;
begin
  if ASucceeded then
  begin
    Result := 'geladen';
  end
  else
  begin
    Result := 'nicht geladen (' + TAtlasCiBuild.ErrorKey(AError) + ')';
  end;
end;

{ TAtlasIdeIssuePreview }

constructor TAtlasIdeIssuePreview.Create(const AHooks: TAtlasIssuePreviewHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FHistory := TAtlasIssueHistory.Create;
  FCache := TAtlasTrackerIssueCache.Create(ACacheFolder);
  FWorkers := TList<TThread>.Create;
  FLookups := TDictionary<string, TArray<TAtlasIssueLookupDone>>.Create;
  FMissing := TDictionary<string, UInt64>.Create;
  FReadOnly := TStringList.Create;
  FReadOnly.Sorted := True;
  FReadOnly.Duplicates := dupIgnore;
  FRecent := TAtlasRecentIssues.Create;
  if ACacheFolder <> '' then
  begin
    FRecentFile := TPath.Combine(ACacheFolder, 'recent.json');
  end;
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
  FReadOnly.Free;
  FWorkers.Free;
  FLookups.Free;
  FMissing.Free;
  FRecent.Free;
  FCache.Free;
  FHistory.Free;
  inherited;
end;

procedure TAtlasIdeIssuePreview.CreateDevelopment;
var
  mHooks: TAtlasIssueDevelopmentHooks;
  mOwner: TAtlasIdeIssuePreview;
begin
  // Eigene Routine: Die anonymen Methoden halten nur Self. Stop der Entwicklung löst sie wieder.
  mOwner := Self;
  mHooks := Default(TAtlasIssueDevelopmentHooks);
  mHooks.Provider :=
    function(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider
    begin
      Result := mOwner.ProviderOf(ATarget);
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := nil;
      if Assigned(mOwner.FHooks.Transport) then
      begin
        Result := mOwner.FHooks.Transport(AProvider, ATarget);
      end;
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
      Result := mOwner.Frame;
    end;
  FDevelopment := TAtlasIdeIssueDevelopment.Create(mHooks);
  FDevelopmentRef := FDevelopment;
end;

class function TAtlasIdeIssuePreview.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
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
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeIssueWindow.OnFrame :=
    procedure(AFrame: TAtlasIssueFrame)
    begin
      if (mKeep <> nil) and mOwner.FStarted then
      begin
        mOwner.Wire(AFrame);
      end;
    end;
  FDevelopment.Start;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeIssueWindow.Prepare;
  FCache.Prune(NowUtc);
  // Fehlt, unbrauchbar oder gesperrt: leer anfangen (TAtlasDataFile protokolliert).
  if FRecentFile <> '' then
  begin
    FRecent.LoadFromFile(FRecentFile);
  end;
end;

procedure TAtlasIdeIssuePreview.Remember(const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue);
begin
  FRecent.Add(ATarget, AIssue);
  if FRecentFile = '' then
  begin
    Exit;
  end;
  try
    FRecent.SaveToFile(FRecentFile);
  except
    // Die Liste bleibt im Speicher; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(FRecent.Kind, E);
  end;
end;

function TAtlasIdeIssuePreview.RecentIssues(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
begin
  Result := FRecent.Items(ATarget);
end;

procedure TAtlasIdeIssuePreview.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  Inc(FGeneration);
  CancelLoad;
  CancelImages;
  FDevelopment.Stop;
  ReleaseThreads(True);
  // Rückrufe des Editors nicht mehr aufrufen.
  FLookups.Clear;
  TAtlasIdeIssueWindow.Release;
  FHooks := Default(TAtlasIssuePreviewHooks);
end;

procedure TAtlasIdeIssuePreview.ReleaseThreads(AWait: Boolean);
var
  mIndex: Integer;
  mThread: TThread;
  mWait: TArray<TThread>;
begin
  if FThread <> nil then
  begin
    FWorkers.Add(FThread);
  end;
  if FImageThread <> nil then
  begin
    FWorkers.Add(FImageThread);
  end;
  FThread := nil;
  FImageThread := nil;
  if AWait then
  begin
    mWait := nil;
    for mIndex := 0 to FWorkers.Count - 1 do
    begin
      mWait := mWait + [FWorkers[mIndex]];
    end;
    if Length(mWait) > 0 then
    begin
      TAtlasShutdown.WaitForThreads(mWait);
    end;
  end;
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    mThread := FWorkers[mIndex];
    if mThread.Finished then
    begin
      mThread.Free;
      FWorkers.Delete(mIndex);
    end
    else if AWait then
    begin
      // Läuft noch (Zeitgrenze): räumt sich selbst auf.
      mThread.FreeOnTerminate := True;
      FWorkers.Delete(mIndex);
    end;
  end;
end;

function TAtlasIdeIssuePreview.Frame: TAtlasIssueFrame;
begin
  Result := TAtlasIdeIssueWindow.ExistingFrame;
end;

procedure TAtlasIdeIssuePreview.Wire(AFrame: TAtlasIssueFrame);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mMono: TFont;
  mEditor: IOTAEditorServices;
begin
  mKeep := Self;
  mOwner := Self;
  // Neues Fenster: das Kommentarfeld ist noch nicht gebunden.
  FBoundKey := '';
  FBoundActive := False;
  AFrame.ApplyColors(TAtlasIdeStyle.Colors);
  mMono := TFont.Create;
  try
    mMono.Name := 'Consolas';
    mMono.Size := 10;
    if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) and (mEditor.EditOptions <> nil) then
    begin
      mMono.Name := mEditor.EditOptions.FontName;
      mMono.Size := mEditor.EditOptions.FontSize;
    end;
    AFrame.MonoFont := mMono;
  finally
    mMono.Free;
  end;
  AFrame.OnBack :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.GoBack;
      end;
    end;
  AFrame.OnForward :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.GoForward;
      end;
    end;
  AFrame.OnRefresh :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Refresh;
      end;
    end;
  AFrame.OnCancel :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.CancelLoad;
        mOwner.FDevelopment.Cancel;
      end;
    end;
  AFrame.OnHidden :=
    procedure
    begin
      // Fenster geschlossen: Laden und Bilder abbrechen.
      if mKeep <> nil then
      begin
        mOwner.CancelLoad;
        mOwner.CancelImages;
        mOwner.FDevelopment.Cancel;
      end;
    end;
  AFrame.OnStart :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := mOwner.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.HasDetails and Assigned(mOwner.FHooks.Start) then
      begin
        mOwner.FHooks.Start(mFrame.Details.Issue);
      end;
    end;
  AFrame.OnBrowse :=
    procedure
    begin
      if (mKeep <> nil) and mOwner.FHasCurrent then
      begin
        mOwner.Fix(TAtlasIssueFix.Browser);
      end;
    end;
  AFrame.OnCopyKey :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := mOwner.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.HasDetails then
      begin
        Clipboard.AsText := mFrame.Details.Key;
      end;
    end;
  AFrame.OnFix :=
    procedure(AFix: TAtlasIssueFix)
    begin
      if mKeep <> nil then
      begin
        mOwner.Fix(AFix);
      end;
    end;
  AFrame.OnOpenLink :=
    procedure(ALink: TAtlasTrackerLink)
    begin
      if (mKeep = nil) or not mOwner.FHasCurrent then
      begin
        Exit;
      end;
      if ALink.Local then
      begin
        mOwner.Show(mOwner.FCurrent.Target, ALink.Key);
      end
      else
      begin
        TAtlasIssuePreview.Browse(ALink.Page);
      end;
    end;
  AFrame.OnOpenAttachment :=
    procedure(AAttachment: TAtlasTrackerAttachment)
    begin
      if mKeep <> nil then
      begin
        mOwner.OpenAttachment(AAttachment);
      end;
    end;
  AFrame.OnOpenUrl :=
    procedure(AUrl: string)
    begin
      // Braucht den Besitzer nicht; nach dem Abmelden öffnet die leere Shell nichts mehr.
      TAtlasIssuePreview.Browse(AUrl);
    end;
  AFrame.OnImages :=
    procedure(AUrls: TArray<string>)
    begin
      if mKeep <> nil then
      begin
        mOwner.LoadImages(AUrls);
      end;
    end;
  AFrame.OnEnd :=
    procedure
    begin
      if (mKeep <> nil) and mOwner.FHasCurrent and Assigned(mOwner.FHooks.EndIssue) then
      begin
        mOwner.FHooks.EndIssue(mOwner.FCurrent.Key);
      end;
    end;
  AFrame.OnComment :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.SendComment(AText);
      end;
    end;
  AFrame.OnToggleTask :=
    procedure(AIndex: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.ToggleTask(AIndex);
      end;
    end;
  AFrame.OnAddTask :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.AddTask;
      end;
    end;
  AFrame.OnCreateSubtask :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.CreateSubtask;
      end;
    end;
  AFrame.OnAddLink :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.AddLink;
      end;
    end;
  AFrame.OnAttach :=
    procedure
    begin
      if (mKeep <> nil) and mOwner.FHasCurrent and Assigned(mOwner.FHooks.Attach) then
      begin
        mOwner.FHooks.Attach(mOwner.FCurrent.Target, mOwner.FCurrent.Key);
      end;
    end;
  if Assigned(FHooks.CanStart) then
  begin
    AFrame.CanStart := FHooks.CanStart();
  end;
  FDevelopment.Wire(AFrame);
  AFrame.CanAttach := Assigned(FHooks.CanAttach) and FHooks.CanAttach();
  ShowCurrent;
end;

function TAtlasIdeIssuePreview.ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FHooks.Provider) then
  begin
    Result := FHooks.Provider(ATarget.Provider);
  end;
end;

procedure TAtlasIdeIssuePreview.UpdateHistory;
var
  mFrame: TAtlasIssueFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.SetHistory(FHistory.CanBack, FHistory.CanForward);
  end;
end;

procedure TAtlasIdeIssuePreview.Show(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  Show(ATarget, AKey, 0);
end;

procedure TAtlasIdeIssuePreview.Show(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if not FStarted or not Active or (Trim(AKey) = '') then
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
  if not FHasCurrent then
  begin
    Exit;
  end;
  FDevelopment.Refresh;
  Load(FCurrent);
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
  FHasPending := False;
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
end;

procedure TAtlasIdeIssuePreview.CancelImages;
begin
  if FImageCancel <> nil then
  begin
    FImageCancel.Cancel;
  end;
end;

function TAtlasIdeIssuePreview.StaleText(const ADetails: TAtlasTrackerDetails; const AReason: string): string;
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

procedure TAtlasIdeIssuePreview.UpdateWrite;
var
  mFrame: TAtlasIssueFrame;
  mWrite: Boolean;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mWrite := FStarted and FHasCurrent and Assigned(FHooks.CanWrite) and FHooks.CanWrite(FCurrent.Target);
  mFrame.CanWrite := mWrite;
  mFrame.CanEnd := mWrite and Assigned(FHooks.IsActive) and FHooks.IsActive(FCurrent.Key);
  BindComment(mFrame, mWrite);
end;

procedure TAtlasIdeIssuePreview.BindComment(AFrame: TAtlasIssueFrame; AWrite: Boolean);
var
  mKey: string;
  mActive: Boolean;
  mAssist: IAtlasCommentAssist;
  mEditor: TAtlasCommentEditor;
begin
  mKey := '';
  if AWrite then
  begin
    mKey := TAtlasCommentDrafts.TrackerKey(FCurrent.Target) + '|' + FCurrent.Key;
  end;
  mActive := TAtlasIdeSettings.Current.IssuesCommentEditor;
  // Dasselbe Issue mit derselben Einstellung: die Bindung (und der getippte Text) bleibt.
  if SameText(mKey, FBoundKey) and (mActive = FBoundActive) then
  begin
    Exit;
  end;
  mEditor := AFrame.CommentEditor;
  // Der Entwurf des bisherigen Issues bleibt gespeichert; das Feld beginnt leer. Ohne Bindung (Editor aus)
  // bleibt der Text wie bisher stehen.
  if mEditor.Assist <> nil then
  begin
    mEditor.Unbind;
    mEditor.SetText('');
  end;
  FBoundKey := mKey;
  FBoundActive := mActive;
  mAssist := nil;
  if (mKey <> '') and mActive and Assigned(FHooks.CommentAssist) then
  begin
    mAssist := FHooks.CommentAssist(FCurrent.Target, FCurrent.Key);
  end;
  mEditor.Enhanced := mAssist <> nil;
  mEditor.Bind(mAssist);
end;

procedure TAtlasIdeIssuePreview.SendComment(const AText: string);
var
  mFrame: TAtlasIssueFrame;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mKey: string;
  mTarget: TAtlasTrackerTarget;
begin
  mFrame := Frame;
  if (mFrame = nil) or not FStarted or not FHasCurrent or not Assigned(FHooks.Comment) then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  mKey := FCurrent.Key;
  mTarget := FCurrent.Target;
  mFrame.SetCommentSending(True);
  FHooks.Comment(FCurrent.Target, mKey, AText,
    procedure(const AResult: TAtlasTrackerWriteResult)
    var
      mDone: TAtlasIssueFrame;
    begin
      if (mKeep = nil) or not mOwner.FStarted then
      begin
        Exit;
      end;
      mDone := mOwner.Frame;
      // Zeigt das Feld inzwischen ein anderes Issue, gehört sein Text nicht zum gesendeten Kommentar.
      if mOwner.FHasCurrent and SameText(mOwner.FCurrent.Key, mKey) then
      begin
        if mDone <> nil then
        begin
          mDone.CommentDone(TAtlasTrackerEndDialog.ErrorText(mKey, AResult));
        end;
      end
      else
      begin
        if mDone <> nil then
        begin
          mDone.SetCommentSending(False);
        end;
        if AResult.Succeeded and Assigned(mOwner.FHooks.CommentSent) then
        begin
          mOwner.FHooks.CommentSent(mTarget, mKey);
        end;
      end;
      // Den neuen Kommentar zeigen: dasselbe Issue neu laden.
      if AResult.Succeeded and mOwner.FHasCurrent and SameText(mOwner.FCurrent.Key, mKey) then
      begin
        mOwner.Refresh;
      end;
    end);
end;

procedure TAtlasIdeIssuePreview.ShowCurrent;
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  UpdateHistory;
  UpdateWrite;
  if FHasCurrent then
  begin
    PrepareFrame(mFrame, FCurrent);
  end;
  if FHasCurrent and FCache.Get(FCurrent.Target, FCurrent.Key, NowUtc, mDetails) then
  begin
    ShowOn(mFrame, mDetails, '');
  end
  else if not FHasCurrent then
  begin
    mFrame.ShowEmpty;
  end;
end;

procedure TAtlasIdeIssuePreview.Load(const AEntry: TAtlasIssueHistoryEntry);
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
  mProvider: IAtlasTrackerProvider;
  mTransports: TAtlasIssuePreviewTransportHook;
  mComments: Boolean;
  mGeneration: Integer;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mTransport: IAtlasCiTransport;
begin
  if not FStarted then
  begin
    Exit;
  end;
  // Eine Abfrage zur Zeit: die laufende abbrechen, dieser Wunsch folgt ihr.
  ReleaseThreads(False);
  if FThread <> nil then
  begin
    FPending := AEntry;
    FHasPending := True;
    if FCancel <> nil then
    begin
      FCancel.Cancel;
    end;
    Exit;
  end;
  CancelImages;
  FCurrent := AEntry;
  FHasCurrent := True;
  UpdateWrite;
  FDevelopment.Select(AEntry.Target, AEntry.Key);
  Inc(FGeneration);
  mGeneration := FGeneration;
  mFrame := Frame;
  UpdateHistory;
  mComments := TAtlasIdeSettings.Current.IssuesPreviewComments;
  // Sofort der letzte Stand; frisch geladen ersetzt ihn.
  if mFrame <> nil then
  begin
    PrepareFrame(mFrame, AEntry);
    if FCache.Get(AEntry.Target, AEntry.Key, NowUtc, mDetails) then
    begin
      ShowOn(mFrame, mDetails, StaleText(mDetails, ''));
      Remember(AEntry.Target, mDetails.Issue);
    end;
    mFrame.SetLoading(True);
  end;
  mProvider := ProviderOf(AEntry.Target);
  if (mProvider = nil) or not Assigned(FHooks.Transport) then
  begin
    Loaded(mGeneration, AEntry, False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.NotConfigured);
    Exit;
  end;
  mTransports := FHooks.Transport;
  mKeep := Self;
  mOwner := Self;
  // Der Transport entsteht hier, damit „Abbrechen“ ihn erreicht; er liest das Token ohne Dialog.
  mTransport := mTransports(mProvider, AEntry.Target);
  if mTransport = nil then
  begin
    Loaded(mGeneration, AEntry, False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  FThread := TThread.CreateAnonymousThread(
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
        mOk := mProvider.Details(TAtlasTrackerCall.Create(AEntry.Target, mTransport, TAtlasIssuePreview.TimeoutMs),
          AEntry.Key, mComments, mResult, mError);
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
            mOwner.Loaded(mGeneration, AEntry, mOk, mResult, mError);
          end;
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeIssuePreview.Loaded(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
  ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
var
  mFrame: TAtlasIssueFrame;
  mDetails, mCached: TAtlasTrackerDetails;
  mProvider: IAtlasTrackerProvider;
begin
  FCancel := nil;
  ReleaseThreads(False);
  if not FStarted then
  begin
    Exit;
  end;
  mProvider := ProviderOf(AEntry.Target);
  if mProvider <> nil then
  begin
    TAtlasGuard.Log(Format('Issue-Vorschau: %s, %s', [mProvider.Name, LoadState(ASucceeded, AError)]));
  end;
  // Ein anderer Wunsch wartet: der zählt.
  if FHasPending then
  begin
    FHasPending := False;
    Load(FPending);
    Exit;
  end;
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  mFrame := Frame;
  if ASucceeded then
  begin
    mDetails := ADetails;
    mDetails.Fetched := NowUtc;
    FCache.Put(AEntry.Target, mDetails);
    Remember(AEntry.Target, mDetails.Issue);
    if mFrame <> nil then
    begin
      mFrame.SetLoading(False);
      if Assigned(FHooks.CanStart) then
      begin
        mFrame.CanStart := FHooks.CanStart();
      end;
      mFrame.CanAttach := Assigned(FHooks.CanAttach) and FHooks.CanAttach();
      PrepareFrame(mFrame, AEntry);
      // Meldung nach dem Anlegen bzw. Verknüpfen (#1279) über dem frischen Stand.
      ShowOn(mFrame, mDetails, FNotice);
      UpdateWrite;
      // Nach einem abgewiesenen Abhaken (Beschreibung geändert): Hinweis über dem neuen Stand.
      if FPendingNotice <> '' then
      begin
        mFrame.ShowNotice(FPendingNotice);
      end;
    end;
    FPendingNotice := '';
    FNotice := '';
    Exit;
  end;
  FPendingNotice := '';
  if mFrame = nil then
  begin
    Exit;
  end;
  mFrame.SetLoading(False);
  // Abgebrochen (Knopf oder Fenster zu): nichts melden.
  if AError = TAtlasCiFetchError.Cancelled then
  begin
    Exit;
  end;
  // Ohne Netz der letzte Stand mit Grund, kein Dialog.
  if FCache.Get(AEntry.Target, AEntry.Key, NowUtc, mCached) then
  begin
    ShowOn(mFrame, mCached, StaleText(mCached, TAtlasIssueTip.ErrorText(AError, AEntry.Key)));
  end
  else
  begin
    mFrame.ShowError(TAtlasIssueTip.ErrorText(AError, AEntry.Key), TAtlasIssuePreview.FixOf(AError));
  end;
end;

function TAtlasIdeIssuePreview.ReadOnlyKey(const AEntry: TAtlasIssueHistoryEntry): string;
begin
  Result := TAtlasTrackerIssueCache.TrackerId(AEntry.Target) + '#' + LowerCase(AEntry.Key);
end;

procedure TAtlasIdeIssuePreview.PrepareFrame(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry);
var
  mProvider: IAtlasTrackerProvider;
begin
  AFrame.Checklists := TAtlasIdeSettings.Current.IssuesPreviewChecklists;
  // Nur lesbar: Anbieter kann nicht schreiben, oder der Tracker hat in dieser Sitzung abgelehnt.
  mProvider := ProviderOf(AEntry.Target);
  AFrame.ChecklistReadOnly := (mProvider = nil) or not Supports(mProvider, IAtlasTrackerDescriptions) or
    (FReadOnly.IndexOf(ReadOnlyKey(AEntry)) >= 0);
end;

procedure TAtlasIdeIssuePreview.ToggleTask(AIndex: Integer);
var
  mFrame: TAtlasIssueFrame;
  mItem: TAtlasChecklistItem;
begin
  mFrame := Frame;
  if not FStarted or not FHasCurrent or FWriting or (mFrame = nil) or not mFrame.HasDetails or
    mFrame.ChecklistReadOnly then
  begin
    Exit;
  end;
  // Der Punkt, wie er angezeigt wurde; ChangeChecklist vergleicht ihn mit dem aktuellen Text.
  if TAtlasTrackerChecklist.Find(mFrame.Details.Description, AIndex, mItem) then
  begin
    ChangeChecklist(TChecklistChange.Toggle, mItem, '');
  end;
end;

procedure TAtlasIdeIssuePreview.AddTask;
var
  mFrame: TAtlasIssueFrame;
  mText: string;
begin
  mFrame := Frame;
  if not FStarted or not FHasCurrent or FWriting or (mFrame = nil) or not mFrame.HasDetails or
    mFrame.ChecklistReadOnly then
  begin
    Exit;
  end;
  mText := '';
  if not InputQuery(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistAdd),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistAddPrompt), mText) or (Trim(mText) = '') then
  begin
    Exit;
  end;
  // Während des Dialogs kann das Fenster gewechselt haben.
  if FStarted and FHasCurrent and not FWriting then
  begin
    ChangeChecklist(TChecklistChange.Append, Default(TAtlasChecklistItem), mText);
  end;
end;

procedure TAtlasIdeIssuePreview.ChangeChecklist(AChange: TChecklistChange; const AItem: TAtlasChecklistItem;
  const AText: string);
var
  mEntry: TAtlasIssueHistoryEntry;
  mProvider: IAtlasTrackerProvider;
  mEditor: IAtlasTrackerDescriptions;
  mTransport: IAtlasCiTransport;
  mFrame: TAtlasIssueFrame;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mWorker: TThread;
begin
  mEntry := FCurrent;
  mProvider := ProviderOf(mEntry.Target);
  if (mProvider = nil) or not Supports(mProvider, IAtlasTrackerDescriptions, mEditor) then
  begin
    ChecklistWritten(mEntry, False, False, True, TAtlasCiFetchError.Unauthorized, '');
    Exit;
  end;
  mTransport := nil;
  if Assigned(FHooks.Transport) then
  begin
    mTransport := FHooks.Transport(mProvider, mEntry.Target);
  end;
  // Ohne Token darf Atlas nicht schreiben: wie eine Ablehnung des Trackers.
  if mTransport = nil then
  begin
    ChecklistWritten(mEntry, False, False, True, TAtlasCiFetchError.Unauthorized, '');
    Exit;
  end;
  FWriting := True;
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.SetChecklistBusy(True);
  end;
  ReleaseThreads(False);
  mKeep := Self;
  mOwner := Self;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mCurrent, mNew: string;
      mError: TAtlasCiFetchError;
      mApplied, mChanged, mDenied, mOk: Boolean;
    begin
      mApplied := False;
      mChanged := False;
      mDenied := False;
      mNew := '';
      mError := TAtlasCiFetchError.Network;
      try
        // Erst den aktuellen Stand lesen: Nur wenn der Punkt dort unverändert steht, wird geschrieben.
        if mEditor.Description(mEntry.Target, mTransport, mEntry.Key, TAtlasIssuePreview.TimeoutMs, mCurrent,
          mError) then
        begin
          if AChange = TChecklistChange.Toggle then
          begin
            mOk := TAtlasTrackerChecklist.Toggle(mCurrent, AItem, mNew);
          end
          else
          begin
            mOk := TAtlasTrackerChecklist.Append(mCurrent, AText, mNew);
          end;
          if not mOk then
          begin
            mChanged := True;
            mError := TAtlasCiFetchError.None;
          end
          else if mEditor.UpdateDescription(mEntry.Target, mTransport, mEntry.Key, mNew,
            TAtlasIssuePreview.TimeoutMs, mError) then
          begin
            mApplied := True;
          end
          else
          begin
            // Nur eine Ablehnung beim Schreiben heißt „keine Schreibrechte“; Lesefehler nicht.
            mDenied := mError = TAtlasCiFetchError.Unauthorized;
          end;
        end;
      except
        on E: Exception do
        begin
          mApplied := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Vorschau: Checkliste mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      mEditor := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
          begin
            mOwner.ChecklistWritten(mEntry, mApplied, mChanged, mDenied, mError, mNew);
          end;
        end);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TAtlasIdeIssuePreview.ChecklistWritten(const AEntry: TAtlasIssueHistoryEntry;
  AApplied, AChanged, ADenied: Boolean; AError: TAtlasCiFetchError; const AText: string);
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
  mProvider: IAtlasTrackerProvider;
  mCurrent: Boolean;
  mResult: string;
begin
  FWriting := False;
  ReleaseThreads(False);
  if not FStarted then
  begin
    Exit;
  end;
  mProvider := ProviderOf(AEntry.Target);
  if AApplied then
  begin
    mResult := 'geschrieben';
  end
  else if AChanged then
  begin
    mResult := 'Beschreibung geändert';
  end
  else
  begin
    mResult := 'nicht geschrieben (' + TAtlasCiBuild.ErrorKey(AError) + ')';
  end;
  if mProvider <> nil then
  begin
    TAtlasGuard.Log(Format('Issue-Vorschau: Checkliste bei %s %s', [mProvider.Name, mResult]));
  end;
  if AApplied and FCache.Get(AEntry.Target, AEntry.Key, NowUtc, mDetails) then
  begin
    // Der geschriebene Text ist der neue Stand, auch fürs Statusfeld.
    mDetails.Description := AText;
    mDetails.Fetched := NowUtc;
    FCache.Put(AEntry.Target, mDetails);
  end;
  if ADenied then
  begin
    FReadOnly.Add(ReadOnlyKey(AEntry));
  end;
  mFrame := Frame;
  mCurrent := FHasCurrent and FCurrent.SameAs(AEntry);
  if mFrame <> nil then
  begin
    mFrame.SetChecklistBusy(False);
  end;
  if (mFrame = nil) or not mCurrent then
  begin
    Exit;
  end;
  if AApplied then
  begin
    mFrame.ReplaceDescription(AText);
  end
  else if AChanged then
  begin
    // Nichts angewendet: neu laden, danach der Hinweis.
    FPendingNotice := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistChanged);
    Load(AEntry);
  end
  else if ADenied then
  begin
    mFrame.ChecklistReadOnly := True;
    mFrame.ShowNotice(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueChecklistDenied));
  end
  else if AError <> TAtlasCiFetchError.Cancelled then
  begin
    mFrame.ShowNotice(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueChecklistFailed,
      [TAtlasIssueTip.ErrorText(AError, AEntry.Key)]));
  end;
end;

procedure TAtlasIdeIssuePreview.ShowChecklist(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mFrame: TAtlasIssueFrame;
begin
  Show(ATarget, AKey);
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.RevealChecklist;
  end;
end;

function TAtlasIdeIssuePreview.ChecklistProgress(const ATarget: TAtlasTrackerTarget; const AKey: string;
  out AProgress: TAtlasChecklistProgress): Boolean;
var
  mDetails: TAtlasTrackerDetails;
begin
  AProgress := TAtlasChecklistProgress.Create(0, 0);
  Result := (Trim(AKey) <> '') and FCache.Get(ATarget, AKey, NowUtc, mDetails);
  if Result then
  begin
    AProgress := TAtlasTrackerChecklist.Progress(mDetails.Description);
  end;
end;

procedure TAtlasIdeIssuePreview.Prefetch(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mDetails: TAtlasTrackerDetails;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mEntry: TAtlasIssueHistoryEntry;
  mComments: Boolean;
  mKey: string;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mWorker: TThread;
begin
  if not FStarted or FPrefetching or (Trim(AKey) = '') or not Assigned(FHooks.Transport) then
  begin
    Exit;
  end;
  mEntry := TAtlasIssueHistoryEntry.Create(ATarget, AKey);
  mKey := ReadOnlyKey(mEntry);
  // Frischer Stand im Zwischenspeicher, oder diese Kennung wurde eben erst versucht.
  if FCache.Get(ATarget, mEntry.Key, NowUtc, mDetails) and
    (NowUtc - mDetails.Fetched < PrefetchMinutes / MinsPerDay) then
  begin
    Exit;
  end;
  if SameText(FPrefetchKey, mKey) and (NowUtc - FPrefetchAt < PrefetchMinutes / MinsPerDay) then
  begin
    Exit;
  end;
  FPrefetchKey := mKey;
  FPrefetchAt := NowUtc;
  mProvider := ProviderOf(ATarget);
  if mProvider = nil then
  begin
    Exit;
  end;
  mTransport := FHooks.Transport(mProvider, ATarget);
  if mTransport = nil then
  begin
    Exit;
  end;
  mComments := TAtlasIdeSettings.Current.IssuesPreviewComments;
  FPrefetching := True;
  ReleaseThreads(False);
  mKeep := Self;
  mOwner := Self;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasTrackerDetails;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mResult := TAtlasTrackerDetails.Empty;
      mOk := False;
      try
        mOk := mProvider.Details(TAtlasTrackerCall.Create(mEntry.Target, mTransport, TAtlasIssuePreview.TimeoutMs),
          mEntry.Key, mComments, mResult, mError);
      except
        on Exception do
          mOk := False;
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
            mOwner.Prefetched(mEntry, mOk, mResult);
          end;
        end);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TAtlasIdeIssuePreview.Prefetched(const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
  const ADetails: TAtlasTrackerDetails);
var
  mDetails: TAtlasTrackerDetails;
begin
  FPrefetching := False;
  ReleaseThreads(False);
  if not FStarted or not ASucceeded then
  begin
    Exit;
  end;
  mDetails := ADetails;
  mDetails.Fetched := NowUtc;
  FCache.Put(AEntry.Target, mDetails);
end;

procedure TAtlasIdeIssuePreview.ShowOn(AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails;
  const AStatus: string);
var
  mProvider: IAtlasTrackerProvider;
begin
  // Baum oder Liste (#1279); die Knöpfe nur, wenn der Anbieter schreiben kann.
  mProvider := nil;
  if FHasCurrent then
  begin
    mProvider := ProviderOf(FCurrent.Target);
  end;
  AFrame.LinksAsTree := TAtlasIdeSettings.Current.IssuesPreviewLinks;
  AFrame.CanWriteLinks := AFrame.LinksAsTree and Supports(mProvider, IAtlasTrackerLinkWriter);
  AFrame.ShowDetails(ADetails, NowUtc, AStatus, not TAtlasIdeSettings.Current.IssuesPreviewComments);
end;

/// <summary>Projekt einer YouTrack-Kennung ("ATL-12" → "ATL"); '' ohne Bindestrich.</summary>
function ProjectOfKey(const AKey: string): string;
var
  mAt: Integer;
begin
  Result := '';
  mAt := LastDelimiter('-', AKey);
  if mAt > 1 then
  begin
    Result := Copy(AKey, 1, mAt - 1);
  end;
end;

procedure TAtlasIdeIssuePreview.CreateSubtask;
var
  mFrame: TAtlasIssueFrame;
  mTarget: TAtlasTrackerTarget;
  mParent, mProject, mTitle, mDescription: string;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  mFrame := Frame;
  if not FStarted or not FHasCurrent or (mFrame = nil) or not mFrame.HasDetails then
  begin
    Exit;
  end;
  mTarget := FCurrent.Target;
  mParent := mFrame.Details.Key;
  // Vorbelegt: das Projekt des übergeordneten Issues (GitHub owner/repo, YouTrack Kürzel).
  mProject := mTarget.Project;
  if mProject = '' then
  begin
    mProject := ProjectOfKey(mParent);
  end;
  if not TAtlasSubtaskDialog.Execute(mParent, mProject, mTitle, mDescription) then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  RunWrite(mTarget,
    function(const AWriter: IAtlasTrackerLinkWriter; const ATransport: IAtlasCiTransport; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean
    begin
      Result := AWriter.CreateSubtask(TAtlasTrackerCall.Create(mTarget, ATransport, WriteTimeoutMs), mParent, mTitle,
        mDescription, AKey, AError);
    end,
    procedure(ASucceeded: Boolean; const AKey: string; AError: TAtlasCiFetchError)
    begin
      if mKeep = nil then
      begin
        Exit;
      end;
      if ASucceeded then
      begin
        mOwner.Written(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueSubtaskCreated, [AKey]));
      end
      else if AKey <> '' then
      begin
        mOwner.WriteFailed(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueSubtaskNotLinked, [AKey,
          TAtlasIssueTip.ErrorText(AError, mParent)]), AError);
      end
      else
      begin
        mOwner.WriteFailed(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueSubtaskFailed,
          [TAtlasIssueTip.ErrorText(AError, mParent)]),
          AError);
      end;
    end);
end;

procedure TAtlasIdeIssuePreview.AddLink;
var
  mFrame: TAtlasIssueFrame;
  mTarget: TAtlasTrackerTarget;
  mKey, mOther: string;
  mKind: TAtlasTrackerLinkKind;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  mFrame := Frame;
  if not FStarted or not FHasCurrent or (mFrame = nil) or not mFrame.HasDetails then
  begin
    Exit;
  end;
  mTarget := FCurrent.Target;
  mKey := mFrame.Details.Key;
  if not TAtlasIssueLinkDialog.Execute(mKey, mTarget.Provider, mKind, mOther) then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  RunWrite(mTarget,
    function(const AWriter: IAtlasTrackerLinkWriter; const ATransport: IAtlasCiTransport; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean
    begin
      AKey := mOther;
      Result := AWriter.AddLink(TAtlasTrackerCall.Create(mTarget, ATransport, WriteTimeoutMs), mKey, mKind, mOther,
        AError);
    end,
    procedure(ASucceeded: Boolean; const AKey: string; AError: TAtlasCiFetchError)
    begin
      if mKeep = nil then
      begin
        Exit;
      end;
      if ASucceeded then
      begin
        mOwner.Written(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueLinkAdded, [mKey, mOther]));
      end
      else
      begin
        mOwner.WriteFailed(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueLinkFailed,
          [TAtlasIssueTip.ErrorText(AError, mOther)]),
          AError);
      end;
    end);
end;

procedure TAtlasIdeIssuePreview.RunWrite(const ATarget: TAtlasTrackerTarget; const AWork: TAtlasIssueWriteWork;
  const ADone: TAtlasIssueWriteDone);
var
  mProvider: IAtlasTrackerProvider;
  mWriter: IAtlasTrackerLinkWriter;
  mTransport: IAtlasCiTransport;
  mThread: TThread;
  mFrame: TAtlasIssueFrame;
begin
  mProvider := ProviderOf(ATarget);
  if not Supports(mProvider, IAtlasTrackerLinkWriter, mWriter) or not Assigned(FHooks.Transport) then
  begin
    ADone(False, '', TAtlasCiFetchError.NotConfigured);
    Exit;
  end;
  // Liest das Token ohne Dialog; ohne Token wie eine abgelehnte Anmeldung (Knopf „Token hinterlegen …“).
  mTransport := FHooks.Transport(mProvider, ATarget);
  if mTransport = nil then
  begin
    ADone(False, '', TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.ShowError(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinkWorking), TAtlasIssueFix.None);
  end;
  ReleaseThreads(False);
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mKey: string;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mKey := '';
      mError := TAtlasCiFetchError.Network;
      mOk := False;
      try
        mOk := AWork(mWriter, mTransport, mKey, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Vorschau: Schreiben mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      mWriter := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          ADone(mOk, mKey, mError);
        end);
    end);
  mThread.FreeOnTerminate := False;
  FWorkers.Add(mThread);
  mThread.Start;
end;

procedure TAtlasIdeIssuePreview.Written(const AText: string);
begin
  if not FStarted then
  begin
    Exit;
  end;
  TAtlasGuard.Log('Issue-Vorschau: Verknüpfung geschrieben');
  // Neu laden: Der Baum zeigt die neue Unteraufgabe bzw. Verknüpfung, die Meldung steht darüber.
  FNotice := AText;
  Refresh;
end;

procedure TAtlasIdeIssuePreview.WriteFailed(const AText: string; AError: TAtlasCiFetchError);
var
  mFrame: TAtlasIssueFrame;
begin
  if not FStarted then
  begin
    Exit;
  end;
  TAtlasGuard.Log('Issue-Vorschau: Schreiben nicht möglich (' + TAtlasCiBuild.ErrorKey(AError) + ')');
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.ShowError(AText, TAtlasIssuePreview.FixOf(AError));
  end;
end;

procedure TAtlasIdeIssuePreview.CheckBlocked(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const ADone: TAtlasIssueBlockedDone);
var
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mCached: TAtlasTrackerDetails;
  mKnown: Boolean;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mThread: TThread;
begin
  mCached := TAtlasTrackerDetails.Empty;
  mKnown := FStarted and FCache.Get(ATarget, AKey, NowUtc, mCached);
  mProvider := nil;
  mTransport := nil;
  if FStarted then
  begin
    mProvider := ProviderOf(ATarget);
  end;
  if (mProvider <> nil) and Assigned(FHooks.Transport) then
  begin
    mTransport := FHooks.Transport(mProvider, ATarget);
  end;
  if mTransport = nil then
  begin
    ADone(mKnown, mCached);
    Exit;
  end;
  mTarget := ATarget;
  mKey := AKey;
  ReleaseThreads(False);
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mDetails: TAtlasTrackerDetails;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mDetails := TAtlasTrackerDetails.Empty;
      mOk := False;
      try
        mOk := mProvider.Details(TAtlasTrackerCall.Create(mTarget, mTransport, BlockedTimeoutMs), mKey, False,
          mDetails, mError);
      except
        on E: Exception do
        begin
          mOk := False;
          TAtlasGuard.Log('Issue-Vorschau: Prüfung vor „Beginnen“ mit ' + E.ClassName + ' abgebrochen');
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
          // Ohne Antwort der letzte Stand aus dem Zwischenspeicher.
          if mOk then
          begin
            ADone(True, mDetails);
          end
          else
          begin
            ADone(mKnown, mCached);
          end;
        end);
    end);
  mThread.FreeOnTerminate := False;
  FWorkers.Add(mThread);
  mThread.Start;
end;

procedure TAtlasIdeIssuePreview.ShowLink(const ATarget: TAtlasTrackerTarget; const ALink: TAtlasTrackerLink);
begin
  if ALink.Local and FStarted and Active then
  begin
    Show(ATarget, ALink.Key);
    Exit;
  end;
  if ALink.Page <> '' then
  begin
    TAtlasIssuePreview.Browse(ALink.Page);
    Exit;
  end;
  // Nur die Seite aus der eingetragenen Adresse.
  TAtlasIssuePreview.BrowseIssue(ProviderOf(ATarget), ATarget, ALink.Key);
end;

procedure TAtlasIdeIssuePreview.Fix(AFix: TAtlasIssueFix);
var
  mProvider: IAtlasTrackerProvider;
begin
  if not FHasCurrent then
  begin
    Exit;
  end;
  case AFix of
    TAtlasIssueFix.EnterToken:
      begin
        mProvider := ProviderOf(FCurrent.Target);
        if (mProvider <> nil) and Assigned(FHooks.Credentials) and FHooks.Credentials(mProvider, FCurrent.Target) then
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
      TAtlasIssuePreview.BrowseIssue(ProviderOf(FCurrent.Target), FCurrent.Target, FCurrent.Key);
    TAtlasIssueFix.Retry:
      Refresh;
    TAtlasIssueFix.None: ;
  end;
end;

class function TAtlasIdeIssuePreview.LookupId(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := TAtlasTrackerIssueCache.TrackerId(ATarget) + '|' + UpperCase(Trim(AKey));
end;

function TAtlasIdeIssuePreview.Peek(const ATarget: TAtlasTrackerTarget; const AKey: string;
  out ADetails: TAtlasTrackerDetails): Boolean;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  Result := (Trim(AKey) <> '') and FCache.Get(ATarget, AKey, NowUtc, ADetails);
end;

class function TAtlasIdeIssuePreview.Fresh(const ADetails: TAtlasTrackerDetails): Boolean;
begin
  Result := (ADetails.Fetched > 0) and (MilliSecondsBetween(NowUtc, ADetails.Fetched) < FreshMs);
end;

procedure TAtlasIdeIssuePreview.Lookup(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const ADone: TAtlasIssueLookupDone);
var
  mId: string;
  mWaiting: TArray<TAtlasIssueLookupDone>;
  mCount: Integer;
  mAt: UInt64;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mWorker: TThread;
begin
  if not FStarted or (Trim(AKey) = '') or not Assigned(ADone) then
  begin
    Exit;
  end;
  mId := LookupId(ATarget, AKey);
  // Kürzlich nicht gefunden: nicht erneut fragen.
  if FMissing.TryGetValue(mId, mAt) then
  begin
    if TThread.GetTickCount64 - mAt < MissingMs then
    begin
      ADone(False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.NotFound);
      Exit;
    end;
    FMissing.Remove(mId);
  end;
  // Läuft schon: nur anhängen.
  if FLookups.TryGetValue(mId, mWaiting) then
  begin
    mCount := Length(mWaiting);
    SetLength(mWaiting, mCount + 1);
    mWaiting[mCount] := ADone;
    FLookups[mId] := mWaiting;
    Exit;
  end;
  mProvider := ProviderOf(ATarget);
  if (mProvider = nil) or not Assigned(FHooks.Transport) then
  begin
    ADone(False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.NotConfigured);
    Exit;
  end;
  // Ohne Token kein Netz (wie die Vorschau, ohne Dialog).
  mTransport := FHooks.Transport(mProvider, ATarget);
  if mTransport = nil then
  begin
    ADone(False, TAtlasTrackerDetails.Empty, TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  SetLength(mWaiting, 1);
  mWaiting[0] := ADone;
  FLookups.Add(mId, mWaiting);
  ReleaseThreads(False);
  mKeep := Self;
  mOwner := Self;
  mWorker := TThread.CreateAnonymousThread(
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
        mOk := mProvider.Details(TAtlasTrackerCall.Create(ATarget, mTransport, TAtlasIssuePreview.TimeoutMs), AKey,
          False, mResult, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Kennung: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.IssueLinks,
        procedure
        begin
          if mKeep <> nil then
          begin
            mOwner.LookedUp(mId, ATarget, mOk, mResult, mError);
          end;
        end);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TAtlasIdeIssuePreview.LookedUp(const AId: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
var
  mWaiting: TArray<TAtlasIssueLookupDone>;
  mDone: TAtlasIssueLookupDone;
  mDetails, mCached: TAtlasTrackerDetails;
begin
  ReleaseThreads(False);
  if not FStarted or not FLookups.TryGetValue(AId, mWaiting) then
  begin
    Exit;
  end;
  FLookups.Remove(AId);
  mDetails := ADetails;
  if ASucceeded then
  begin
    mDetails.Fetched := NowUtc;
    // Ohne Kommentare gefragt: die der Vorschau nicht verlieren.
    if not mDetails.CommentsLoaded and FCache.Get(ATarget, mDetails.Key, NowUtc, mCached) and
      mCached.CommentsLoaded then
    begin
      mDetails.CommentsLoaded := True;
      mDetails.Comments := mCached.Comments;
    end;
    FCache.Put(ATarget, mDetails);
  end
  else if AError = TAtlasCiFetchError.NotFound then
  begin
    FMissing.AddOrSetValue(AId, TThread.GetTickCount64);
  end;
  // Anonym: nie Kennung oder Titel.
  TAtlasGuard.Log('Issue-Kennung: ' + LoadState(ASucceeded, AError));
  for mDone in mWaiting do
  begin
    Deliver(mDone, ASucceeded, mDetails, AError);
  end;
end;

class procedure TAtlasIdeIssuePreview.Deliver(const ADone: TAtlasIssueLookupDone; ASucceeded: Boolean;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
begin
  // Eigene Routine: Die anonyme Methode fängt nur ihre Argumente, nicht die Schleife von LookedUp.
  TAtlasGuard.Run(TAtlasFeature.IssueLinks,
    procedure
    begin
      ADone(ASucceeded, ADetails, AError);
    end);
end;

procedure TAtlasIdeIssuePreview.LoadImages(const AUrls: TArray<string>);
var
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mDownload: IAtlasCiDownload;
  mUrls: TArray<string>;
  mUrl: string;
  mServer: string;
  mGeneration: Integer;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
begin
  if not FStarted or not FHasCurrent or not Assigned(FHooks.Transport) then
  begin
    Exit;
  end;
  CancelImages;
  ReleaseThreads(False);
  mProvider := ProviderOf(FCurrent.Target);
  if mProvider = nil then
  begin
    Exit;
  end;
  // Nur Bilder vom Server, an den das Token geht; alles andere bleibt ein Link.
  mServer := mProvider.ApiServer(FCurrent.Target);
  mUrls := nil;
  for mUrl in AUrls do
  begin
    if TAtlasIssuePreview.MayLoad(mUrl, mServer) and (Length(mUrls) < MaxImages) and
      (IndexText(mUrl, mUrls) < 0) then
    begin
      mUrls := mUrls + [mUrl];
    end;
  end;
  if Length(mUrls) = 0 then
  begin
    Exit;
  end;
  mTransport := FHooks.Transport(mProvider, FCurrent.Target);
  if not Supports(mTransport, IAtlasCiDownload, mDownload) then
  begin
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FImageCancel) then
  begin
    FImageCancel := nil;
  end;
  mGeneration := FGeneration;
  mKeep := Self;
  mOwner := Self;
  FImageThread := TThread.CreateAnonymousThread(
    procedure
    var
      mIndex, mStatus: Integer;
      mBytes: TBytes;
      mError: TAtlasCiFetchError;
      mImageUrl: string;
    begin
      for mIndex := 0 to High(mUrls) do
      begin
        if TAtlasShutdown.Signalled then
        begin
          Exit;
        end;
        mImageUrl := mUrls[mIndex];
        mBytes := nil;
        try
          if not mDownload.GetBytes(mImageUrl, TAtlasIssuePreview.TimeoutMs, TAtlasIssuePreview.MaxImageBytes,
            mStatus, mBytes, mError) then
          begin
            if mError = TAtlasCiFetchError.Cancelled then
            begin
              Exit;
            end;
            Continue;
          end;
          if mStatus <> 200 then
          begin
            Continue;
          end;
        except
          on Exception do
            Continue;
        end;
        TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
          procedure
          begin
            if mKeep <> nil then
            begin
              mOwner.ImageLoaded(mGeneration, mImageUrl, mBytes);
            end;
          end);
      end;
      mDownload := nil;
    end);
  FImageThread.FreeOnTerminate := False;
  FImageThread.Start;
end;

procedure TAtlasIdeIssuePreview.ImageLoaded(AGeneration: Integer; const AUrl: string; const ABytes: TBytes);
var
  mFrame: TAtlasIssueFrame;
  mStream: TBytesStream;
  mImage: TWICImage;
begin
  if not FStarted or (AGeneration <> FGeneration) or (Length(ABytes) = 0) then
  begin
    Exit;
  end;
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  // PNG, JPEG, GIF, BMP und TIFF über WIC; Unlesbares bleibt ein Link.
  mImage := TWICImage.Create;
  mStream := TBytesStream.Create(ABytes);
  try
    try
      mImage.LoadFromStream(mStream);
    except
      on Exception do
        FreeAndNil(mImage);
    end;
  finally
    mStream.Free;
  end;
  if mImage <> nil then
  begin
    mFrame.SetImage(AUrl, mImage);
  end;
end;

procedure TAtlasIdeIssuePreview.OpenAttachment(const AAttachment: TAtlasTrackerAttachment);
var
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mDownload: IAtlasCiDownload;
  mFolder, mFile, mName, mUrl: string;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mWorker: TThread;
begin
  if not FStarted or not FHasCurrent then
  begin
    Exit;
  end;
  mProvider := ProviderOf(FCurrent.Target);
  if mProvider = nil then
  begin
    Exit;
  end;
  mUrl := AAttachment.Url;
  // Dateien anderer Server (GitHub) bzw. ohne Token: im Browser.
  if AAttachment.External or not TAtlasIssuePreview.MayLoad(mUrl, mProvider.ApiServer(FCurrent.Target)) or
    not Assigned(FHooks.Transport) then
  begin
    TAtlasIssuePreview.Browse(mUrl);
    Exit;
  end;
  mTransport := FHooks.Transport(mProvider, FCurrent.Target);
  if not Supports(mTransport, IAtlasCiDownload, mDownload) then
  begin
    Exit;
  end;
  mFolder := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetTempPath, 'Atlas'), 'issues'),
    TAtlasTrackerIssueCache.SafeName(FCurrent.Key));
  mName := TAtlasIssuePreview.SafeFileName(AAttachment.Name);
  mFile := TPath.Combine(mFolder, mName);
  mKeep := Self;
  mOwner := Self;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mStatus: Integer;
      mBytes: TBytes;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mOk := False;
      try
        if mDownload.GetBytes(mUrl, TAtlasIssuePreview.TimeoutMs * 3, TAtlasIssuePreview.MaxAttachmentBytes,
          mStatus, mBytes, mError) and (mStatus = 200) then
        begin
          ForceDirectories(mFolder);
          TFile.WriteAllBytes(mFile, mBytes);
          mOk := True;
        end;
      except
        on Exception do
          mOk := False;
      end;
      mDownload := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
          begin
            mOwner.AttachmentLoaded(mFile, mOk, mName);
          end;
        end);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TAtlasIdeIssuePreview.AttachmentLoaded(const AFileName: string; ASucceeded: Boolean;
  const AName: string);
var
  mFrame: TAtlasIssueFrame;
begin
  ReleaseThreads(False);
  if not FStarted then
  begin
    Exit;
  end;
  if not ASucceeded then
  begin
    mFrame := Frame;
    if mFrame <> nil then
    begin
      mFrame.ShowError(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewAttachmentFailed, [AName]),
        TAtlasIssueFix.None);
    end;
    Exit;
  end;
  // Ausführbares nie starten: im Explorer zeigen.
  TAtlasIssuePreview.OpenDownloaded(AFileName);
end;

end.
