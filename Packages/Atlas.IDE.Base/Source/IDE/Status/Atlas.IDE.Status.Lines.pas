unit Atlas.IDE.Status.Lines;

// Feste Zeilen des Atlas-Statusfelds (#591) in der IDE:
// - „Server“: Phase, mittlere Antwortzeit der letzten 50 Anfragen und Version
//   vom Code Insight-Manager. Mit server.statusWindow öffnet ein Klick auf
//   die Zeile das Fenster „Atlas-Server“ (#1356); QueryNow fragt für dessen
//   Knopf „Aktualisieren“ sofort ab.
// - „Index“: Fortschritt aus $/progress, Anzahl Units aus atlas.server.status.
//   Alle 5 s fragt ein Hintergrund-Thread den Status ab (einzige Abfrage im
//   Zeitgeber, liefert nebenbei die Antwortzeit), nur solange der Server läuft.
//   Die letzte Antwort hält StatusJson für die Einrichtung (#625: Index je
//   Projekt, Bibliotheks-Cache), damit sie den Server nicht selbst abfragt.
//   Für die Zustandskachel (#754): Server mit „seit“ bzw. Zeitpunkt des
//   Absturzes, Index mit Zeitpunkt der letzten vollständigen Indizierung;
//   den letzten Index-Stand hält TAtlasIndexTracker in
//   %LOCALAPPDATA%\Atlas\index-state.json, damit die Zeile ohne laufenden
//   Server „Stand vom …“ zeigt.
// - „Datei“: Kodierung und Zeilenende der aktiven Datei (#121), gelesen von
//   der Platte, solange sie sich nicht ändert aus dem Zwischenspeicher. Ein
//   Klick öffnet die Auswahl (UTF-8 mit/ohne BOM, ANSI; CRLF/LF). Die Wahl
//   markiert die Datei als geändert; nach jedem Speichern schreibt Atlas sie
//   im gewählten Format und setzt den Zeitstempel der IDE wieder, damit diese
//   nicht nach Neuladen fragt. Die Wahl gilt bis zum Ende der Sitzung.
//   Gelesen wird mit TAtlasTextFile.ReadAllBytes, das Löschen teilt: Ersetzt
//   Atlas die Datei gerade (Umbenennen, Ausblenden), scheitert das nicht an
//   dieser Zeile (Bericht M5).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Status.IndexStore,
  Atlas.Core.Files.Format;

type
  TAtlasIndexingFunc = reference to function(out APercent: Integer): Boolean;
  TAtlasStatusQueryFunc = reference to function(const ADone: TProc<string>): Boolean;

  /// <summary>Quellen der Zeilen; eingesetzt von der Kompositionswurzel.</summary>
  TAtlasStatusLineSources = record
    ServerInfo: TFunc<TAtlasServerInfo>;
    Indexing: TAtlasIndexingFunc;
    Query: TAtlasStatusQueryFunc;
    /// <summary>Zeile für die Meldungsansicht oder nil.</summary>
    Report: TProc<string>;
    /// <summary>Aktion der Zeile „Server“ (Fenster „Atlas-Server“, #1356) oder nil; gilt nur, solange
    /// ServerActionEnabled True liefert.</summary>
    ServerAction: TProc;
    ServerActionEnabled: TFunc<Boolean>;
  end;

  TAtlasIdeStatusLines = class
  private type
    TCached = record
      Stamp: TDateTime;
      Format: TAtlasFileFormat;
    end;
    /// <summary>Ergebnis der Abfrage im Hintergrund; überlebt das Objekt, falls der Thread länger läuft.</summary>
    TUnits = class(TInterfacedObject)
    public
      Value: Integer;
      /// <summary>Letzte Antwort von atlas.server.status; nur unter TMonitor des Objekts lesen und schreiben.</summary>
      Json: string;
    end;
  private
    FRegistry: IAtlasStatusRegistry;
    FServer: TAtlasStatusLine;
    FIndex: TAtlasStatusLine;
    FFile: TAtlasStatusLine;
    FServerRef: IAtlasStatusItem;
    FIndexRef: IAtlasStatusItem;
    FFileRef: IAtlasStatusItem;
    FSources: TAtlasStatusLineSources;
    FUnits: TUnits;
    FUnitsRef: IInterface;
    // Letzter Index-Stand (#754); nur im Hauptthread.
    FTracker: TAtlasIndexTracker;
    FIndexFile: string;
    FPoll: TTimer;
    FCache: TDictionary<string, TCached>;
    FTargets: TDictionary<string, TAtlasFileFormat>;
    FMenu: TPopupMenu;
    FMenuFile: string;
    FActiveFile: string;
    procedure PollTick(Sender: TObject);
    /// <summary>atlas.server.status im Hintergrund; ADone (oder nil) danach im Hauptthread. False ohne Abfrage.
    /// </summary>
    function StartQuery(const ADone: TProc): Boolean;
    procedure RefreshServer;
    procedure RefreshIndex;
    procedure RefreshFile;
    function ActiveFile: string;
    function DiskFormat(const AFileName: string; out AFormat: TAtlasFileFormat): Boolean;
    procedure ShowFormatMenu;
    procedure FormatClick(Sender: TObject);
    procedure MarkModified(const AFileName: string);
    class function Key(const AFileName: string): string; static;
  public
    constructor Create(const ARegistry: IAtlasStatusRegistry; const ASources: TAtlasStatusLineSources);
    destructor Destroy; override;
    /// <summary>Alle Zeilen nachführen (Hauptthread, vor jedem Zeichnen des Felds).</summary>
    procedure Refresh;
    /// <summary>AFileName wurde gespeichert: gewähltes Format schreiben.</summary>
    procedure Saved(const AFileName: string);
    /// <summary>Format für AFileName wählen (wie im Menü); schreibt beim nächsten Speichern.</summary>
    procedure SetTarget(const AFileName: string; const ATarget: TAtlasFileFormat);
    /// <summary>Units im Index aus der letzten Abfrage; -1 = unbekannt (Kopf der Willkommensseite, #753).</summary>
    function Units: Integer;
    /// <summary>Letzte Antwort von atlas.server.status als JSON; '' ohne laufenden Server oder vor der ersten
    /// Abfrage (Einrichtung, #625). Aus jedem Thread.</summary>
    function StatusJson: string;
    /// <summary>Status sofort abfragen (Knopf „Aktualisieren“ im Fenster „Atlas-Server“, #1356); ADone danach
    /// im Hauptthread, StatusJson hat dann die neue Antwort. False ohne laufenden Server oder während einer
    /// Abfrage (die nächste Antwort kommt dann ohnehin).</summary>
    function QueryNow(const ADone: TProc): Boolean;
  end;

implementation

uses
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TIdeStatusLinesText = (CharactersCannotBeRepresentedIn, SavedAs);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TIdeStatusLinesText] of string = (
    ('%s: %d Zeichen lassen sich in ANSI nicht darstellen und werden zu „?“',
     '%s gespeichert als %s'),
    ('%s: %d characters cannot be represented in ANSI and become "?"',
     '%s saved as %s'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TIdeStatusLinesText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasIdeStatusLines }

function TAtlasIdeStatusLines.Units: Integer;
begin
  Result := FUnits.Value;
end;

function TAtlasIdeStatusLines.StatusJson: string;
begin
  TMonitor.Enter(FUnits);
  try
    Result := FUnits.Json;
  finally
    TMonitor.Exit(FUnits);
  end;
end;

constructor TAtlasIdeStatusLines.Create(const ARegistry: IAtlasStatusRegistry;
  const ASources: TAtlasStatusLineSources);
begin
  inherited Create;
  FRegistry := ARegistry;
  FSources := ASources;
  FUnits := TUnits.Create;
  FUnits.Value := -1;
  FUnitsRef := FUnits;
  FCache := TDictionary<string, TCached>.Create;
  FTargets := TDictionary<string, TAtlasFileFormat>.Create;
  FIndexFile := TAtlasIndexStore.DefaultFile;
  FTracker := TAtlasIndexTracker.Create(TAtlasIndexStore.Load(FIndexFile));
  FServer := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.ServerId, TAtlasStatusLines.ServerOrder,
    ASources.ServerAction, ASources.ServerActionEnabled);
  FServerRef := FServer;
  FIndex := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.IndexId, TAtlasStatusLines.IndexOrder);
  FIndexRef := FIndex;
  FFile := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.FileId, TAtlasStatusLines.FileOrder,
    procedure
    begin
      ShowFormatMenu;
    end);
  FFileRef := FFile;
  RefreshServer;
  RefreshIndex;
  FFile.Update(TAtlasStatusLines.FileText(Default(TAtlasFileInfo)), TAtlasStatusState.Neutral);
  FRegistry.Add(FServerRef);
  FRegistry.Add(FIndexRef);
  FRegistry.Add(FFileRef);
  FPoll := TTimer.Create(nil);
  FPoll.Interval := TAtlasStatusLines.PollMs;
  FPoll.OnTimer := PollTick;
  FPoll.Enabled := True;
end;

destructor TAtlasIdeStatusLines.Destroy;
begin
  FreeAndNil(FPoll);
  if FServer <> nil then
  begin
    FServer.Detach;
  end;
  if FIndex <> nil then
  begin
    FIndex.Detach;
  end;
  if FFile <> nil then
  begin
    FFile.Detach;
  end;
  FRegistry.Remove(TAtlasStatusLines.ServerId);
  FRegistry.Remove(TAtlasStatusLines.IndexId);
  FRegistry.Remove(TAtlasStatusLines.FileId);
  // Lief der Server bis jetzt, gilt sein letzter Stand als „Stand vom …“ beim nächsten Start.
  if FTracker.Observe(False, False, -1, Now) then
  begin
    TAtlasIndexStore.Save(FIndexFile, FTracker.Snapshot);
  end;
  FreeAndNil(FTracker);
  FreeAndNil(FMenu);
  FTargets.Free;
  FCache.Free;
  inherited;
end;

class function TAtlasIdeStatusLines.Key(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

procedure TAtlasIdeStatusLines.PollTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      // Antwortzeit und Units; ohne laufenden Server startet nichts.
      StartQuery(nil);
      RefreshServer;
    end);
end;

function TAtlasIdeStatusLines.QueryNow(const ADone: TProc): Boolean;
begin
  Result := StartQuery(ADone);
end;

function TAtlasIdeStatusLines.StartQuery(const ADone: TProc): Boolean;
var
  mUnits: TUnits;
  mHolder: IInterface;
  mRegistry: IAtlasStatusRegistry;
  mDone: TProc;
begin
  mUnits := FUnits;
  mHolder := FUnitsRef;
  mRegistry := FRegistry;
  mDone := ADone;
  Result := FSources.Query(
    procedure(AJson: string)
    var
      Count: Integer;
    begin
      // Im Hintergrund-Thread; Holder hält das Ergebnis am Leben.
      if mHolder = nil then
      begin
        Exit;
      end;
      Count := TAtlasStatusLines.UnitsOf(AJson);
      if Count >= 0 then
      begin
        AtomicExchange(mUnits.Value, Count);
      end;
      if AJson <> '' then
      begin
        TMonitor.Enter(mUnits);
        try
          mUnits.Json := AJson;
        finally
          TMonitor.Exit(mUnits);
        end;
      end;
      mRegistry.Changed;
      if Assigned(mDone) then
      begin
        TAtlasMainThread.Queue(TAtlasFeature.Status,
          procedure
          begin
            mDone();
          end);
      end;
    end);
end;

procedure TAtlasIdeStatusLines.Refresh;
begin
  RefreshServer;
  RefreshIndex;
  RefreshFile;
end;

procedure TAtlasIdeStatusLines.RefreshServer;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := FSources.ServerInfo();
  FServer.Update(TAtlasStatusLines.ServerText(mInfo), TAtlasStatusLines.ServerState(mInfo),
    TAtlasStatusLines.ServerSummary(mInfo), TAtlasStatusLines.ServerBrief(mInfo), TAtlasStatusLines.ServerDetail(mInfo));
  // Nach einem Neustart sind die Units erst wieder nach der nächsten Abfrage bekannt.
  if mInfo.Phase <> TAtlasServerPhase.Running then
  begin
    AtomicExchange(FUnits.Value, -1);
    TMonitor.Enter(FUnits);
    try
      FUnits.Json := '';
    finally
      TMonitor.Exit(FUnits);
    end;
  end;
end;

procedure TAtlasIdeStatusLines.RefreshIndex;
var
  mInfo: TAtlasIndexInfo;
  mRunning, mIndexing: Boolean;
  mPercent, mUnits: Integer;
begin
  mRunning := FSources.ServerInfo().Phase = TAtlasServerPhase.Running;
  mPercent := -1;
  mIndexing := mRunning and FSources.Indexing(mPercent);
  mUnits := -1;
  if mRunning then
  begin
    mUnits := FUnits.Value;
  end;
  // Letzten Stand merken; geschrieben wird nur bei einer Änderung und wenn der Server aufhört (#754).
  if FTracker.Observe(mRunning, mIndexing, mUnits, Now) then
  begin
    TAtlasIndexStore.Save(FIndexFile, FTracker.Snapshot);
  end;
  // Ohne laufenden Server die gespeicherten Werte mit „Stand vom …“.
  mInfo := FTracker.Info(mRunning, mIndexing, mPercent, mUnits);
  FIndex.Update(TAtlasStatusLines.IndexText(mInfo), TAtlasStatusLines.IndexState(mInfo),
    TAtlasStatusLines.IndexSummary(mInfo), TAtlasStatusLines.IndexBrief(mInfo), TAtlasStatusLines.IndexDetail(mInfo));
end;

function TAtlasIdeStatusLines.ActiveFile: string;
var
  mEditor: IOTAEditorServices;
  mBuffer: IOTAEditBuffer;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    Exit;
  end;
  mBuffer := mEditor.TopBuffer;
  if mBuffer <> nil then
  begin
    Result := mBuffer.FileName;
  end;
end;

function TAtlasIdeStatusLines.DiskFormat(const AFileName: string; out AFormat: TAtlasFileFormat): Boolean;
var
  mCached: TCached;
  mStamp: TDateTime;
begin
  Result := (AFileName <> '') and FileExists(AFileName);
  if not Result then
  begin
    Exit;
  end;
  mStamp := TFile.GetLastWriteTime(AFileName);
  if FCache.TryGetValue(Key(AFileName), mCached) and (mCached.Stamp = mStamp) then
  begin
    AFormat := mCached.Format;
    Exit;
  end;
  try
    mCached.Format := TAtlasFileFormats.Detect(TAtlasTextFile.ReadAllBytes(AFileName));
  except
    on Exception do
      Exit(False);
  end;
  mCached.Stamp := mStamp;
  FCache.AddOrSetValue(Key(AFileName), mCached);
  AFormat := mCached.Format;
end;

procedure TAtlasIdeStatusLines.RefreshFile;
var
  mInfo: TAtlasFileInfo;
  mBytes: TBytes;
begin
  FActiveFile := ActiveFile;
  mInfo := Default(TAtlasFileInfo);
  mInfo.Name := ExtractFileName(FActiveFile);
  mInfo.Known := DiskFormat(FActiveFile, mInfo.Format);
  mInfo.HasTarget := mInfo.Known and FTargets.TryGetValue(Key(FActiveFile), mInfo.Target);
  if mInfo.HasTarget then
  begin
    // Schon im gewählten Format: kein Pfeil.
    try
      mBytes := TAtlasTextFile.ReadAllBytes(FActiveFile);
      mInfo.HasTarget := not TAtlasFileFormats.Satisfies(mBytes, mInfo.Target);
    except
      on Exception do
        ;
    end;
  end;
  FFile.Update(TAtlasStatusLines.FileText(mInfo), TAtlasStatusLines.FileState(mInfo));
end;

procedure TAtlasIdeStatusLines.ShowFormatMenu;
var
  mFormat, mCurrent: TAtlasFileFormat;
  mItem: TMenuItem;
  mIndex: Integer;
  mTargets: TArray<TAtlasFileFormat>;
begin
  FMenuFile := ActiveFile;
  if not DiskFormat(FMenuFile, mCurrent) then
  begin
    Exit;
  end;
  FTargets.TryGetValue(Key(FMenuFile), mCurrent);
  FreeAndNil(FMenu);
  FMenu := TPopupMenu.Create(nil);
  mTargets := TAtlasFileFormats.Targets;
  for mIndex := 0 to High(mTargets) do
  begin
    mFormat := mTargets[mIndex];
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := mFormat.Text;
    mItem.Tag := mIndex;
    mItem.RadioItem := True;
    mItem.Checked := mFormat.Equals(mCurrent);
    mItem.OnClick := FormatClick;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
end;

procedure TAtlasIdeStatusLines.FormatClick(Sender: TObject);
var
  mTargets: TArray<TAtlasFileFormat>;
  mIndex: Integer;
begin
  mTargets := TAtlasFileFormats.Targets;
  mIndex := (Sender as TMenuItem).Tag;
  if (mIndex < 0) or (mIndex > High(mTargets)) or (FMenuFile = '') then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      SetTarget(FMenuFile, mTargets[mIndex]);
    end);
end;

procedure TAtlasIdeStatusLines.SetTarget(const AFileName: string; const ATarget: TAtlasFileFormat);
var
  mBytes: TBytes;
  mLosses: Integer;
begin
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  mBytes := TAtlasTextFile.ReadAllBytes(AFileName);
  if TAtlasFileFormats.Satisfies(mBytes, ATarget) then
  begin
    FTargets.Remove(Key(AFileName));
  end
  else
  begin
    FTargets.AddOrSetValue(Key(AFileName), ATarget);
    if ATarget.Encoding = TAtlasFileEncoding.Ansi then
    begin
      mLosses := TAtlasFileFormats.AnsiLosses(TAtlasFileFormats.Decode(mBytes,
        TAtlasFileFormats.Detect(mBytes).Encoding));
      if (mLosses > 0) and Assigned(FSources.Report) then
      begin
        FSources.Report(System.SysUtils.Format(UiText(TIdeStatusLinesText.CharactersCannotBeRepresentedIn),
          [ExtractFileName(AFileName), mLosses]));
      end;
    end;
    // Die IDE soll speichern wollen: gewählt ist eine Änderung der Datei.
    MarkModified(AFileName);
  end;
  RefreshFile;
end;

procedure TAtlasIdeStatusLines.MarkModified(const AFileName: string);
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mSource: IOTASourceEditor;
  mIndex: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.FindModule(AFileName);
  if mModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mModule.ModuleFileCount - 1 do
  begin
    if Supports(mModule.ModuleFileEditors[mIndex], IOTASourceEditor, mSource) and
      SameText(mSource.FileName, AFileName) then
    begin
      mSource.MarkModified;
    end;
  end;
end;

procedure TAtlasIdeStatusLines.Saved(const AFileName: string);
var
  mTarget: TAtlasFileFormat;
  mBytes: TBytes;
  mStamp: TDateTime;
begin
  if not FTargets.TryGetValue(Key(AFileName), mTarget) or not FileExists(AFileName) then
  begin
    Exit;
  end;
  mBytes := TAtlasTextFile.ReadAllBytes(AFileName);
  if not TAtlasFileFormats.Satisfies(mBytes, mTarget) then
  begin
    mStamp := TFile.GetLastWriteTime(AFileName);
    // Atomar (Bericht N3): An Ort und Stelle geschrieben, kostete ein Abbruch die Quelltextdatei.
    TAtlasTextFile.Replace(AFileName, TAtlasFileFormats.Convert(mBytes, mTarget));
    // Zeitstempel des Speicherns der IDE behalten: sonst meldet sie die Datei als extern geändert.
    TFile.SetLastWriteTime(AFileName, mStamp);
    FCache.Remove(Key(AFileName));
    if Assigned(FSources.Report) then
    begin
      FSources.Report(Format(UiText(TIdeStatusLinesText.SavedAs), [ExtractFileName(AFileName), mTarget.Text]));
    end;
  end;
  if SameText(AFileName, FActiveFile) then
  begin
    RefreshFile;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.Status.Lines', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
