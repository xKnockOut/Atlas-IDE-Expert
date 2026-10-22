unit Atlas.IDE.Status.Lines;

// Feste Zeilen des Atlas-Statusfelds (#591) in der IDE:
// - „Server“: Phase, mittlere Antwortzeit der letzten 50 Anfragen und Version
//   vom Code Insight-Manager.
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
    FServerInfo: TFunc<TAtlasServerInfo>;
    FIndexing: TAtlasIndexingFunc;
    FQuery: TAtlasStatusQueryFunc;
    FReport: TProc<string>;
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
    constructor Create(const ARegistry: IAtlasStatusRegistry; const AServerInfo: TFunc<TAtlasServerInfo>;
      const AIndexing: TAtlasIndexingFunc; const AQuery: TAtlasStatusQueryFunc; const AReport: TProc<string>);
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
  end;

implementation

uses
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.TextFile;

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
  const AServerInfo: TFunc<TAtlasServerInfo>; const AIndexing: TAtlasIndexingFunc;
  const AQuery: TAtlasStatusQueryFunc; const AReport: TProc<string>);
begin
  inherited Create;
  FRegistry := ARegistry;
  FServerInfo := AServerInfo;
  FIndexing := AIndexing;
  FQuery := AQuery;
  FReport := AReport;
  FUnits := TUnits.Create;
  FUnits.Value := -1;
  FUnitsRef := FUnits;
  FCache := TDictionary<string, TCached>.Create;
  FTargets := TDictionary<string, TAtlasFileFormat>.Create;
  FIndexFile := TAtlasIndexStore.DefaultFile;
  FTracker := TAtlasIndexTracker.Create(TAtlasIndexStore.Load(FIndexFile));
  FServer := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.ServerId, TAtlasStatusLines.ServerOrder);
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
  FServer.Detach;
  FIndex.Detach;
  FFile.Detach;
  FRegistry.Remove(TAtlasStatusLines.ServerId);
  FRegistry.Remove(TAtlasStatusLines.IndexId);
  FRegistry.Remove(TAtlasStatusLines.FileId);
  // Lief der Server bis jetzt, gilt sein letzter Stand als „Stand vom …“ beim nächsten Start.
  if FTracker.Observe(False, False, -1, Now) then
    TAtlasIndexStore.Save(FIndexFile, FTracker.Snapshot);
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
var
  Units: TUnits;
  Holder: IInterface;
  Registry: IAtlasStatusRegistry;
begin
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      // Antwortzeit und Units; ohne laufenden Server startet nichts.
      Units := FUnits;
      Holder := FUnitsRef;
      Registry := FRegistry;
      FQuery(
        procedure(AJson: string)
        var
          Count: Integer;
        begin
          // Im Hintergrund-Thread; Holder hält das Ergebnis am Leben.
          if Holder = nil then
            Exit;
          Count := TAtlasStatusLines.UnitsOf(AJson);
          if Count >= 0 then
            AtomicExchange(Units.Value, Count);
          if AJson <> '' then
          begin
            TMonitor.Enter(Units);
            try
              Units.Json := AJson;
            finally
              TMonitor.Exit(Units);
            end;
          end;
          Registry.Changed;
        end);
      RefreshServer;
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
  Info: TAtlasServerInfo;
begin
  Info := FServerInfo();
  FServer.Update(TAtlasStatusLines.ServerText(Info), TAtlasStatusLines.ServerState(Info),
    TAtlasStatusLines.ServerSummary(Info), TAtlasStatusLines.ServerBrief(Info), TAtlasStatusLines.ServerDetail(Info));
  // Nach einem Neustart sind die Units erst wieder nach der nächsten Abfrage bekannt.
  if Info.Phase <> TAtlasServerPhase.Running then
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
  Info: TAtlasIndexInfo;
  Running, Indexing: Boolean;
  Percent, Units: Integer;
begin
  Running := FServerInfo().Phase = TAtlasServerPhase.Running;
  Percent := -1;
  Indexing := Running and FIndexing(Percent);
  Units := -1;
  if Running then
    Units := FUnits.Value;
  // Letzten Stand merken; geschrieben wird nur bei einer Änderung und wenn der Server aufhört (#754).
  if FTracker.Observe(Running, Indexing, Units, Now) then
    TAtlasIndexStore.Save(FIndexFile, FTracker.Snapshot);
  // Ohne laufenden Server die gespeicherten Werte mit „Stand vom …“.
  Info := FTracker.Info(Running, Indexing, Percent, Units);
  FIndex.Update(TAtlasStatusLines.IndexText(Info), TAtlasStatusLines.IndexState(Info),
    TAtlasStatusLines.IndexSummary(Info), TAtlasStatusLines.IndexBrief(Info), TAtlasStatusLines.IndexDetail(Info));
end;

function TAtlasIdeStatusLines.ActiveFile: string;
var
  Editor: IOTAEditorServices;
  Buffer: IOTAEditBuffer;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
    Exit;
  Buffer := Editor.TopBuffer;
  if Buffer <> nil then
    Result := Buffer.FileName;
end;

function TAtlasIdeStatusLines.DiskFormat(const AFileName: string; out AFormat: TAtlasFileFormat): Boolean;
var
  Cached: TCached;
  Stamp: TDateTime;
begin
  Result := (AFileName <> '') and FileExists(AFileName);
  if not Result then
    Exit;
  Stamp := TFile.GetLastWriteTime(AFileName);
  if FCache.TryGetValue(Key(AFileName), Cached) and (Cached.Stamp = Stamp) then
  begin
    AFormat := Cached.Format;
    Exit;
  end;
  try
    Cached.Format := TAtlasFileFormats.Detect(TAtlasTextFile.ReadAllBytes(AFileName));
  except
    on Exception do
      Exit(False);
  end;
  Cached.Stamp := Stamp;
  FCache.AddOrSetValue(Key(AFileName), Cached);
  AFormat := Cached.Format;
end;

procedure TAtlasIdeStatusLines.RefreshFile;
var
  Info: TAtlasFileInfo;
  Bytes: TBytes;
begin
  FActiveFile := ActiveFile;
  Info := Default(TAtlasFileInfo);
  Info.Name := ExtractFileName(FActiveFile);
  Info.Known := DiskFormat(FActiveFile, Info.Format);
  Info.HasTarget := Info.Known and FTargets.TryGetValue(Key(FActiveFile), Info.Target);
  if Info.HasTarget then
  begin
    // Schon im gewählten Format: kein Pfeil.
    try
      Bytes := TAtlasTextFile.ReadAllBytes(FActiveFile);
      Info.HasTarget := not TAtlasFileFormats.Satisfies(Bytes, Info.Target);
    except
      on Exception do
        ;
    end;
  end;
  FFile.Update(TAtlasStatusLines.FileText(Info), TAtlasStatusLines.FileState(Info));
end;

procedure TAtlasIdeStatusLines.ShowFormatMenu;
var
  Format, Current: TAtlasFileFormat;
  Item: TMenuItem;
  Index: Integer;
  Targets: TArray<TAtlasFileFormat>;
begin
  FMenuFile := ActiveFile;
  if not DiskFormat(FMenuFile, Current) then
    Exit;
  FTargets.TryGetValue(Key(FMenuFile), Current);
  FreeAndNil(FMenu);
  FMenu := TPopupMenu.Create(nil);
  Targets := TAtlasFileFormats.Targets;
  for Index := 0 to High(Targets) do
  begin
    Format := Targets[Index];
    Item := TMenuItem.Create(FMenu);
    Item.Caption := Format.Text;
    Item.Tag := Index;
    Item.RadioItem := True;
    Item.Checked := Format.Equals(Current);
    Item.OnClick := FormatClick;
    FMenu.Items.Add(Item);
  end;
  FMenu.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
end;

procedure TAtlasIdeStatusLines.FormatClick(Sender: TObject);
var
  Targets: TArray<TAtlasFileFormat>;
  Index: Integer;
begin
  Targets := TAtlasFileFormats.Targets;
  Index := (Sender as TMenuItem).Tag;
  if (Index < 0) or (Index > High(Targets)) or (FMenuFile = '') then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      SetTarget(FMenuFile, Targets[Index]);
    end);
end;

procedure TAtlasIdeStatusLines.SetTarget(const AFileName: string; const ATarget: TAtlasFileFormat);
var
  Bytes: TBytes;
  Losses: Integer;
begin
  if (AFileName = '') or not FileExists(AFileName) then
    Exit;
  Bytes := TAtlasTextFile.ReadAllBytes(AFileName);
  if TAtlasFileFormats.Satisfies(Bytes, ATarget) then
    FTargets.Remove(Key(AFileName))
  else
  begin
    FTargets.AddOrSetValue(Key(AFileName), ATarget);
    if ATarget.Encoding = TAtlasFileEncoding.Ansi then
    begin
      Losses := TAtlasFileFormats.AnsiLosses(TAtlasFileFormats.Decode(Bytes,
        TAtlasFileFormats.Detect(Bytes).Encoding));
      if (Losses > 0) and Assigned(FReport) then
        FReport(System.SysUtils.Format('%s: %d Zeichen lassen sich in ANSI nicht darstellen und werden zu „?“',
          [ExtractFileName(AFileName), Losses]));
    end;
    // Die IDE soll speichern wollen: gewählt ist eine Änderung der Datei.
    MarkModified(AFileName);
  end;
  RefreshFile;
end;

procedure TAtlasIdeStatusLines.MarkModified(const AFileName: string);
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Source: IOTASourceEditor;
  Index: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Module := Modules.FindModule(AFileName);
  if Module = nil then
    Exit;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Source) and
      SameText(Source.FileName, AFileName) then
      Source.MarkModified;
end;

procedure TAtlasIdeStatusLines.Saved(const AFileName: string);
var
  Target: TAtlasFileFormat;
  Bytes: TBytes;
  Stamp: TDateTime;
begin
  if not FTargets.TryGetValue(Key(AFileName), Target) or not FileExists(AFileName) then
    Exit;
  Bytes := TAtlasTextFile.ReadAllBytes(AFileName);
  if not TAtlasFileFormats.Satisfies(Bytes, Target) then
  begin
    Stamp := TFile.GetLastWriteTime(AFileName);
    TFile.WriteAllBytes(AFileName, TAtlasFileFormats.Convert(Bytes, Target));
    // Zeitstempel des Speicherns der IDE behalten: sonst meldet sie die Datei als extern geändert.
    TFile.SetLastWriteTime(AFileName, Stamp);
    FCache.Remove(Key(AFileName));
    if Assigned(FReport) then
      FReport(Format('%s gespeichert als %s', [ExtractFileName(AFileName), Target.Text]));
  end;
  if SameText(AFileName, FActiveFile) then
    RefreshFile;
end;

end.
