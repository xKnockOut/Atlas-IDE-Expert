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
// - Verknüpfungen (#1279, issues.preview.links): Baum statt Liste; kann der
//   Anbieter schreiben (IAtlasTrackerLinkWriter), legen „Unteraufgabe
//   anlegen …“ und „Verknüpfen …“ nach dem Dialog im Hintergrund an
//   (Zeitgrenze 15 s), danach lädt das Fenster neu und meldet das Ergebnis
//   über dem Inhalt. CheckBlocked liest für „Beginnen“ (issues.warnBlocked) die
//   Verknüpfungen frisch (5 s, ohne Kommentare), ohne Netz aus dem
//   Zwischenspeicher.
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
  Atlas.Core.Tracker.IssueCache,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.EndDialog;

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
  end;

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
    /// <summary>Zeitgrenze für Anlegen und Verknüpfen (#1279).</summary>
    WriteTimeoutMs = 15000;
    /// <summary>Zeitgrenze der Prüfung vor „Beginnen“ (#1279).</summary>
    BlockedTimeoutMs = 5000;
    /// <summary>Endungen, die Atlas nicht startet, sondern im Explorer zeigt.</summary>
    RiskyExtensions = '.exe.com.bat.cmd.scr.pif.msi.msp.ps1.psm1.vbs.vbe.js.jse.wsf.wsh.hta.lnk.reg.cpl.jar.dll.' +
      'appref-ms.application.';
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
    FWorkers: TList;
    FGeneration: Integer;
    // Meldung nach Anlegen bzw. Verknüpfen, gezeigt mit dem frisch geladenen Stand (#1279).
    FNotice: string;
    function Frame: TAtlasIssueFrame;
    procedure Wire(AFrame: TAtlasIssueFrame);
    function ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    procedure Load(const AEntry: TAtlasIssueHistoryEntry);
    procedure Loaded(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
    procedure LoadImages(const AUrls: TArray<string>);
    procedure ImageLoaded(AGeneration: Integer; const AUrl: string; const ABytes: TBytes);
    procedure OpenAttachment(const AAttachment: TAtlasTrackerAttachment);
    procedure AttachmentLoaded(const AFileName: string; ASucceeded: Boolean; const AName: string);
    procedure Browse(const AUrl: string);
    procedure ShowCurrent;
    procedure UpdateHistory;
    procedure CancelLoad;
    procedure CancelImages;
    procedure ReleaseThreads(AWait: Boolean);
    function ErrorText(AError: TAtlasCiFetchError; const AKey: string): string;
    function StaleText(const ADetails: TAtlasTrackerDetails; const AReason: string): string;
    procedure Fix(AFix: TAtlasIssueFix);
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
    procedure Show(const ATarget: TAtlasTrackerTarget; const AKey: string);
    procedure Refresh;
    procedure GoBack;
    procedure GoForward;
    /// <summary>Kommentarfeld und „Beenden …“ nach issues.syncState und dem aktuellen Issue (#1266); nach
    /// „Beginnen“, „Beenden“ und geänderten Einstellungen.</summary>
    procedure UpdateWrite;
    /// <summary>Verknüpfungen von AKey für die Warnung beim Beginnen (#1279): frisch im Hintergrund, ohne Antwort
    /// der letzte Stand; ADone im Hauptthread (sofort, wenn kein Transport da ist).</summary>
    procedure CheckBlocked(const ATarget: TAtlasTrackerTarget; const AKey: string;
      const ADone: TAtlasIssueBlockedDone);
    /// <summary>Verknüpftes Issue zeigen: im Fenster, wenn es im selben Tracker liegt und die Vorschau an ist,
    /// sonst im Browser.</summary>
    procedure ShowLink(const ATarget: TAtlasTrackerTarget; const ALink: TAtlasTrackerLink);
    /// <summary>issues.preview an?</summary>
    class function Active: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  ToolsAPI,
  System.IOUtils,
  System.StrUtils,
  System.DateUtils,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tracker.LinkDialogs,
  Atlas.IDE.Tracker.IssueWindow;

{ TAtlasIdeIssuePreview }

constructor TAtlasIdeIssuePreview.Create(const AHooks: TAtlasIssuePreviewHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FHistory := TAtlasIssueHistory.Create;
  FCache := TAtlasTrackerIssueCache.Create(ACacheFolder);
  FWorkers := TList.Create;
end;

destructor TAtlasIdeIssuePreview.Destroy;
begin
  ReleaseThreads(True);
  FWorkers.Free;
  FCache.Free;
  FHistory.Free;
  inherited;
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
    Exit;
  FStarted := True;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeIssueWindow.OnFrame :=
    procedure(AFrame: TAtlasIssueFrame)
    begin
      if (mKeep <> nil) and mOwner.FStarted then
        mOwner.Wire(AFrame);
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeIssueWindow.Prepare;
  FCache.Prune(NowUtc);
end;

procedure TAtlasIdeIssuePreview.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  Inc(FGeneration);
  CancelLoad;
  CancelImages;
  ReleaseThreads(True);
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
    FWorkers.Add(FThread);
  if FImageThread <> nil then
    FWorkers.Add(FImageThread);
  FThread := nil;
  FImageThread := nil;
  if AWait then
  begin
    mWait := nil;
    for mIndex := 0 to FWorkers.Count - 1 do
      mWait := mWait + [TThread(FWorkers[mIndex])];
    if Length(mWait) > 0 then
      TAtlasShutdown.WaitForThreads(mWait);
  end;
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    mThread := TThread(FWorkers[mIndex]);
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
        mOwner.GoBack;
    end;
  AFrame.OnForward :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.GoForward;
    end;
  AFrame.OnRefresh :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.Refresh;
    end;
  AFrame.OnCancel :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.CancelLoad;
    end;
  AFrame.OnHidden :=
    procedure
    begin
      // Fenster geschlossen: Laden und Bilder abbrechen.
      if mKeep <> nil then
      begin
        mOwner.CancelLoad;
        mOwner.CancelImages;
      end;
    end;
  AFrame.OnStart :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := mOwner.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.HasDetails and Assigned(mOwner.FHooks.Start) then
        mOwner.FHooks.Start(mFrame.Details.Issue);
    end;
  AFrame.OnBrowse :=
    procedure
    var
      mProvider: IAtlasTrackerProvider;
    begin
      if (mKeep = nil) or not mOwner.FHasCurrent then
        Exit;
      mProvider := mOwner.ProviderOf(mOwner.FCurrent.Target);
      // Nur die Seite aus der eingetragenen Adresse, nie eine aus der Antwort.
      if mProvider <> nil then
        mOwner.Browse(mProvider.IssuePage(mOwner.FCurrent.Target, mOwner.FCurrent.Key));
    end;
  AFrame.OnCopyKey :=
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mFrame := mOwner.Frame;
      if (mKeep <> nil) and (mFrame <> nil) and mFrame.HasDetails then
        Clipboard.AsText := mFrame.Details.Key;
    end;
  AFrame.OnFix :=
    procedure(AFix: TAtlasIssueFix)
    begin
      if mKeep <> nil then
        mOwner.Fix(AFix);
    end;
  AFrame.OnOpenLink :=
    procedure(ALink: TAtlasTrackerLink)
    begin
      if (mKeep = nil) or not mOwner.FHasCurrent then
        Exit;
      if ALink.Local then
        mOwner.Show(mOwner.FCurrent.Target, ALink.Key)
      else
        mOwner.Browse(ALink.Page);
    end;
  AFrame.OnOpenAttachment :=
    procedure(AAttachment: TAtlasTrackerAttachment)
    begin
      if mKeep <> nil then
        mOwner.OpenAttachment(AAttachment);
    end;
  AFrame.OnOpenUrl :=
    procedure(AUrl: string)
    begin
      if mKeep <> nil then
        mOwner.Browse(AUrl);
    end;
  AFrame.OnImages :=
    procedure(AUrls: TArray<string>)
    begin
      if mKeep <> nil then
        mOwner.LoadImages(AUrls);
    end;
  AFrame.OnEnd :=
    procedure
    begin
      if (mKeep <> nil) and mOwner.FHasCurrent and Assigned(mOwner.FHooks.EndIssue) then
        mOwner.FHooks.EndIssue(mOwner.FCurrent.Key);
    end;
  AFrame.OnComment :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
        mOwner.SendComment(AText);
    end;
  AFrame.OnCreateSubtask :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.CreateSubtask;
    end;
  AFrame.OnAddLink :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.AddLink;
    end;
  if Assigned(FHooks.CanStart) then
    AFrame.CanStart := FHooks.CanStart();
  ShowCurrent;
end;

function TAtlasIdeIssuePreview.ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FHooks.Provider) then
    Result := FHooks.Provider(ATarget.Provider);
end;

procedure TAtlasIdeIssuePreview.Browse(const AUrl: string);
begin
  // Nur Web-Adressen ohne Benutzer; nie eine Datei oder ein anderes Schema aus dem Issue-Text.
  if TAtlasIssuePreview.MayBrowse(AUrl) then
    ShellExecute(0, 'open', PChar(AUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure TAtlasIdeIssuePreview.UpdateHistory;
var
  mFrame: TAtlasIssueFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
    mFrame.SetHistory(FHistory.CanBack, FHistory.CanForward);
end;

procedure TAtlasIdeIssuePreview.Show(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if not FStarted or not Active or (Trim(AKey) = '') then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mFrame: TAtlasIssueFrame;
    begin
      mEntry := TAtlasIssueHistoryEntry.Create(ATarget, AKey);
      FHistory.Visit(mEntry);
      mFrame := TAtlasIdeIssueWindow.Show;
      if mFrame <> nil then
        TAtlasIdeIssueWindow.ApplyTheme;
      Load(mEntry);
    end);
end;

procedure TAtlasIdeIssuePreview.Refresh;
begin
  if FHasCurrent then
    Load(FCurrent);
end;

procedure TAtlasIdeIssuePreview.GoBack;
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if FHistory.GoBack(mEntry) then
    Load(mEntry);
end;

procedure TAtlasIdeIssuePreview.GoForward;
var
  mEntry: TAtlasIssueHistoryEntry;
begin
  if FHistory.GoForward(mEntry) then
    Load(mEntry);
end;

procedure TAtlasIdeIssuePreview.CancelLoad;
begin
  FHasPending := False;
  if FCancel <> nil then
    FCancel.Cancel;
end;

procedure TAtlasIdeIssuePreview.CancelImages;
begin
  if FImageCancel <> nil then
    FImageCancel.Cancel;
end;

function TAtlasIdeIssuePreview.StaleText(const ADetails: TAtlasTrackerDetails; const AReason: string): string;
var
  mWhen: string;
begin
  mWhen := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ADetails.Fetched));
  if AReason = '' then
    Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewStale, [mWhen])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewStaleOffline, [mWhen, AReason]);
end;

function TAtlasIdeIssuePreview.ErrorText(AError: TAtlasCiFetchError; const AKey: string): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewErrorNotFound, [AKey]);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorConfig);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork);
  end;
end;

procedure TAtlasIdeIssuePreview.UpdateWrite;
var
  mFrame: TAtlasIssueFrame;
  mWrite: Boolean;
begin
  mFrame := Frame;
  if mFrame = nil then
    Exit;
  mWrite := FStarted and FHasCurrent and Assigned(FHooks.CanWrite) and FHooks.CanWrite(FCurrent.Target);
  mFrame.CanWrite := mWrite;
  mFrame.CanEnd := mWrite and Assigned(FHooks.IsActive) and FHooks.IsActive(FCurrent.Key);
end;

procedure TAtlasIdeIssuePreview.SendComment(const AText: string);
var
  mFrame: TAtlasIssueFrame;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssuePreview;
  mKey: string;
begin
  mFrame := Frame;
  if (mFrame = nil) or not FStarted or not FHasCurrent or not Assigned(FHooks.Comment) then
    Exit;
  mKeep := Self;
  mOwner := Self;
  mKey := FCurrent.Key;
  mFrame.SetCommentSending(True);
  FHooks.Comment(FCurrent.Target, mKey, AText,
    procedure(const AResult: TAtlasTrackerWriteResult)
    var
      mDone: TAtlasIssueFrame;
    begin
      if (mKeep = nil) or not mOwner.FStarted then
        Exit;
      mDone := mOwner.Frame;
      if mDone <> nil then
        mDone.CommentDone(TAtlasTrackerEndDialog.ErrorText(mKey, AResult));
      // Den neuen Kommentar zeigen: dasselbe Issue neu laden.
      if AResult.Succeeded and mOwner.FHasCurrent and SameText(mOwner.FCurrent.Key, mKey) then
        mOwner.Refresh;
    end);
end;

procedure TAtlasIdeIssuePreview.ShowCurrent;
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
begin
  mFrame := Frame;
  if mFrame = nil then
    Exit;
  UpdateHistory;
  UpdateWrite;
  if FHasCurrent and FCache.Get(FCurrent.Target, FCurrent.Key, NowUtc, mDetails) then
    ShowOn(mFrame, mDetails, '')
  else if not FHasCurrent then
    mFrame.ShowEmpty;
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
    Exit;
  // Eine Abfrage zur Zeit: die laufende abbrechen, dieser Wunsch folgt ihr.
  ReleaseThreads(False);
  if FThread <> nil then
  begin
    FPending := AEntry;
    FHasPending := True;
    if FCancel <> nil then
      FCancel.Cancel;
    Exit;
  end;
  CancelImages;
  FCurrent := AEntry;
  FHasCurrent := True;
  UpdateWrite;
  Inc(FGeneration);
  mGeneration := FGeneration;
  mFrame := Frame;
  UpdateHistory;
  mComments := TAtlasIdeSettings.Current.IssuesPreviewComments;
  // Sofort der letzte Stand; frisch geladen ersetzt ihn.
  if mFrame <> nil then
  begin
    if FCache.Get(AEntry.Target, AEntry.Key, NowUtc, mDetails) then
      ShowOn(mFrame, mDetails, StaleText(mDetails, ''));
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
    FCancel := nil;
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
        mOk := mProvider.Details(AEntry.Target, mTransport, AEntry.Key, mComments, TAtlasIssuePreview.TimeoutMs,
          mResult, mError);
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
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
            mOwner.Loaded(mGeneration, AEntry, mOk, mResult, mError);
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
    Exit;
  mProvider := ProviderOf(AEntry.Target);
  if mProvider <> nil then
    TAtlasGuard.Log(Format('Issue-Vorschau: %s, %s', [mProvider.Name,
      IfThen(ASucceeded, 'geladen', 'nicht geladen (' + TAtlasCiBuild.ErrorKey(AError) + ')')]));
  // Ein anderer Wunsch wartet: der zählt.
  if FHasPending then
  begin
    FHasPending := False;
    Load(FPending);
    Exit;
  end;
  if AGeneration <> FGeneration then
    Exit;
  mFrame := Frame;
  if ASucceeded then
  begin
    mDetails := ADetails;
    mDetails.Fetched := NowUtc;
    FCache.Put(AEntry.Target, mDetails);
    if mFrame <> nil then
    begin
      mFrame.SetLoading(False);
      if Assigned(FHooks.CanStart) then
        mFrame.CanStart := FHooks.CanStart();
      // Meldung nach dem Anlegen bzw. Verknüpfen (#1279) über dem frischen Stand.
      ShowOn(mFrame, mDetails, FNotice);
      UpdateWrite;
    end;
    FNotice := '';
    Exit;
  end;
  if mFrame = nil then
    Exit;
  mFrame.SetLoading(False);
  // Abgebrochen (Knopf oder Fenster zu): nichts melden.
  if AError = TAtlasCiFetchError.Cancelled then
    Exit;
  // Ohne Netz der letzte Stand mit Grund, kein Dialog.
  if FCache.Get(AEntry.Target, AEntry.Key, NowUtc, mCached) then
    ShowOn(mFrame, mCached, StaleText(mCached, ErrorText(AError, AEntry.Key)))
  else
    mFrame.ShowError(ErrorText(AError, AEntry.Key), TAtlasIssuePreview.FixOf(AError));
end;

procedure TAtlasIdeIssuePreview.ShowOn(AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails;
  const AStatus: string);
var
  mProvider: IAtlasTrackerProvider;
begin
  // Baum oder Liste (#1279); die Knöpfe nur, wenn der Anbieter schreiben kann.
  mProvider := nil;
  if FHasCurrent then
    mProvider := ProviderOf(FCurrent.Target);
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
    Result := Copy(AKey, 1, mAt - 1);
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
    Exit;
  mTarget := FCurrent.Target;
  mParent := mFrame.Details.Key;
  // Vorbelegt: das Projekt des übergeordneten Issues (GitHub owner/repo, YouTrack Kürzel).
  mProject := mTarget.Project;
  if mProject = '' then
    mProject := ProjectOfKey(mParent);
  if not TAtlasSubtaskDialog.Execute(mParent, mProject, mTitle, mDescription) then
    Exit;
  mKeep := Self;
  mOwner := Self;
  RunWrite(mTarget,
    function(const AWriter: IAtlasTrackerLinkWriter; const ATransport: IAtlasCiTransport; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean
    begin
      Result := AWriter.CreateSubtask(mTarget, ATransport, mParent, mTitle, mDescription, WriteTimeoutMs, AKey,
        AError);
    end,
    procedure(ASucceeded: Boolean; const AKey: string; AError: TAtlasCiFetchError)
    begin
      if mKeep = nil then
        Exit;
      if ASucceeded then
        mOwner.Written(TAtlasStrings.Fmt(TAtlasTextId.IssueSubtaskCreated, [AKey]))
      else if AKey <> '' then
        mOwner.WriteFailed(TAtlasStrings.Fmt(TAtlasTextId.IssueSubtaskNotLinked, [AKey,
          mOwner.ErrorText(AError, mParent)]), AError)
      else
        mOwner.WriteFailed(TAtlasStrings.Fmt(TAtlasTextId.IssueSubtaskFailed, [mOwner.ErrorText(AError, mParent)]),
          AError);
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
    Exit;
  mTarget := FCurrent.Target;
  mKey := mFrame.Details.Key;
  if not TAtlasIssueLinkDialog.Execute(mKey, mTarget.Provider, mKind, mOther) then
    Exit;
  mKeep := Self;
  mOwner := Self;
  RunWrite(mTarget,
    function(const AWriter: IAtlasTrackerLinkWriter; const ATransport: IAtlasCiTransport; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean
    begin
      AKey := mOther;
      Result := AWriter.AddLink(mTarget, ATransport, mKey, mKind, mOther, WriteTimeoutMs, AError);
    end,
    procedure(ASucceeded: Boolean; const AKey: string; AError: TAtlasCiFetchError)
    begin
      if mKeep = nil then
        Exit;
      if ASucceeded then
        mOwner.Written(TAtlasStrings.Fmt(TAtlasTextId.IssueLinkAdded, [mKey, mOther]))
      else
        mOwner.WriteFailed(TAtlasStrings.Fmt(TAtlasTextId.IssueLinkFailed, [mOwner.ErrorText(AError, mOther)]),
          AError);
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
    mFrame.ShowError(TAtlasStrings.Text(TAtlasTextId.IssueLinkWorking), TAtlasIssueFix.None);
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
        Exit;
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
    Exit;
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
    Exit;
  TAtlasGuard.Log('Issue-Vorschau: Schreiben nicht möglich (' + TAtlasCiBuild.ErrorKey(AError) + ')');
  mFrame := Frame;
  if mFrame <> nil then
    mFrame.ShowError(AText, TAtlasIssuePreview.FixOf(AError));
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
    mProvider := ProviderOf(ATarget);
  if (mProvider <> nil) and Assigned(FHooks.Transport) then
    mTransport := FHooks.Transport(mProvider, ATarget);
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
        mOk := mProvider.Details(mTarget, mTransport, mKey, False, BlockedTimeoutMs, mDetails, mError);
      except
        on E: Exception do
        begin
          mOk := False;
          TAtlasGuard.Log('Issue-Vorschau: Prüfung vor „Beginnen“ mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          // Ohne Antwort der letzte Stand aus dem Zwischenspeicher.
          if mOk then
            ADone(True, mDetails)
          else
            ADone(mKnown, mCached);
        end);
    end);
  mThread.FreeOnTerminate := False;
  FWorkers.Add(mThread);
  mThread.Start;
end;

procedure TAtlasIdeIssuePreview.ShowLink(const ATarget: TAtlasTrackerTarget; const ALink: TAtlasTrackerLink);
var
  mProvider: IAtlasTrackerProvider;
begin
  if ALink.Local and FStarted and Active then
  begin
    Show(ATarget, ALink.Key);
    Exit;
  end;
  if ALink.Page <> '' then
  begin
    Browse(ALink.Page);
    Exit;
  end;
  // Nur die Seite aus der eingetragenen Adresse.
  mProvider := ProviderOf(ATarget);
  if mProvider <> nil then
    Browse(mProvider.IssuePage(ATarget, ALink.Key));
end;

procedure TAtlasIdeIssuePreview.Fix(AFix: TAtlasIssueFix);
var
  mProvider: IAtlasTrackerProvider;
begin
  if not FHasCurrent then
    Exit;
  case AFix of
    TAtlasIssueFix.EnterToken:
      begin
        mProvider := ProviderOf(FCurrent.Target);
        if (mProvider <> nil) and Assigned(FHooks.Credentials) and FHooks.Credentials(mProvider, FCurrent.Target) then
          Refresh;
      end;
    TAtlasIssueFix.Settings:
      if Assigned(FHooks.Settings) then
        FHooks.Settings();
    TAtlasIssueFix.Browser:
      begin
        mProvider := ProviderOf(FCurrent.Target);
        if mProvider <> nil then
          Browse(mProvider.IssuePage(FCurrent.Target, FCurrent.Key));
      end;
    TAtlasIssueFix.Retry:
      Refresh;
  end;
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
    Exit;
  CancelImages;
  ReleaseThreads(False);
  mProvider := ProviderOf(FCurrent.Target);
  if mProvider = nil then
    Exit;
  // Nur Bilder vom Server, an den das Token geht; alles andere bleibt ein Link.
  mServer := mProvider.ApiServer(FCurrent.Target);
  mUrls := nil;
  for mUrl in AUrls do
    if TAtlasIssuePreview.MayLoad(mUrl, mServer) and (Length(mUrls) < MaxImages) and
      (IndexText(mUrl, mUrls) < 0) then
      mUrls := mUrls + [mUrl];
  if Length(mUrls) = 0 then
    Exit;
  mTransport := FHooks.Transport(mProvider, FCurrent.Target);
  if not Supports(mTransport, IAtlasCiDownload, mDownload) then
    Exit;
  if not Supports(mTransport, IAtlasCiCancel, FImageCancel) then
    FImageCancel := nil;
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
          Exit;
        mImageUrl := mUrls[mIndex];
        mBytes := nil;
        try
          if not mDownload.GetBytes(mImageUrl, TAtlasIssuePreview.TimeoutMs, TAtlasIssuePreview.MaxImageBytes,
            mStatus, mBytes, mError) then
          begin
            if mError = TAtlasCiFetchError.Cancelled then
              Exit;
            Continue;
          end;
          if mStatus <> 200 then
            Continue;
        except
          on Exception do
            Continue;
        end;
        TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
          procedure
          begin
            if mKeep <> nil then
              mOwner.ImageLoaded(mGeneration, mImageUrl, mBytes);
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
    Exit;
  mFrame := Frame;
  if mFrame = nil then
    Exit;
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
    mFrame.SetImage(AUrl, mImage);
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
    Exit;
  mProvider := ProviderOf(FCurrent.Target);
  if mProvider = nil then
    Exit;
  mUrl := AAttachment.Url;
  // Dateien anderer Server (GitHub) bzw. ohne Token: im Browser.
  if AAttachment.External or not TAtlasIssuePreview.MayLoad(mUrl, mProvider.ApiServer(FCurrent.Target)) or
    not Assigned(FHooks.Transport) then
  begin
    Browse(mUrl);
    Exit;
  end;
  mTransport := FHooks.Transport(mProvider, FCurrent.Target);
  if not Supports(mTransport, IAtlasCiDownload, mDownload) then
    Exit;
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
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
            mOwner.AttachmentLoaded(mFile, mOk, mName);
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
  mExtension: string;
begin
  ReleaseThreads(False);
  if not FStarted then
    Exit;
  if not ASucceeded then
  begin
    mFrame := Frame;
    if mFrame <> nil then
      mFrame.ShowError(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewAttachmentFailed, [AName]),
        TAtlasIssueFix.None);
    Exit;
  end;
  mExtension := LowerCase(ExtractFileExt(AFileName));
  // Ausführbares nie starten: im Explorer zeigen.
  if (mExtension = '') or (Pos(mExtension + '.', RiskyExtensions) > 0) then
    ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + AFileName + '"'), nil, SW_SHOWNORMAL)
  else
    ShellExecute(0, 'open', PChar(AFileName), nil, PChar(ExtractFilePath(AFileName)), SW_SHOWNORMAL);
end;

end.
