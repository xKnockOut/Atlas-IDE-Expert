unit Atlas.IDE.Vcs.Service;

// Versionsverwaltung in der IDE (#571): Einstieg für alle Funktionen des
// Plugins, die Branch, Revision, geänderte Dateien, Dateiinhalt einer
// Revision oder Zeilenherkunft brauchen (Willkommensseite: Projektzustand
// #592, nicht gesicherte Arbeit #762 …).
//   - ForFolder: Umsetzung für einen Ordner nach vcs.provider aus
//     %APPDATA%\Atlas\settings.json (neu gelesen, wenn sich die Datei ändert);
//     prüft nur Dateien und darf im Hauptthread laufen
//   - Run: Aufruf im Hintergrund, Ergebnis im Hauptthread; der Prozessläufer
//     lehnt den Hauptthread ab, beendet git bzw. svn nach dem Zeitlimit und
//     beim Entladen (TAtlasShutdown)
//   - fehlt git bzw. svn bei einer gefundenen Arbeitskopie, steht das einmal
//     je Sitzung in der Meldungsansicht und im Protokoll; Atlas arbeitet ohne
//     Versionsangaben weiter
// Start und Stop ruft die Komposition beim Laden bzw. Entladen.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasIdeVcsMessage = reference to procedure(const AText: string);

  TAtlasIdeVcs = class
  public
    /// <summary>Beim Laden: AMessage zeigt eine Zeile in der Meldungsansicht (Hauptthread).</summary>
    class procedure Start(const AMessage: TAtlasIdeVcsMessage); static;
    /// <summary>Beim Entladen: laufende Aufrufe abbrechen, keine Ergebnisse mehr zustellen.</summary>
    class procedure Stop; static;
    /// <summary>Wirksamer Wert von vcs.provider.</summary>
    class function Provider: TAtlasVcsProvider; static;
    /// <summary>Umsetzung für AFolder (z. B. Ordner des Projekts); leer, wenn abgeschaltet oder ohne
    /// Arbeitskopie.</summary>
    class function ForFolder(const AFolder: string): IAtlasVersionControl; overload; static;
    /// <summary>Wie oben mit eigenem Zeitlimit je Aufruf (Willkommensseite: 1 s, #592).</summary>
    class function ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl; overload; static;
    /// <summary>AWork im Hintergrund, danach ADone im Hauptthread; nach Stop wirkungslos.</summary>
    class procedure Run(const AWork, ADone: TProc); static;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Vcs.Worker,
  Atlas.Core.Vcs.Composition,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Adapters.ProcessRunner;

var
  Worker: TAtlasVcsWorker;
  Runner: IAtlasVcsRunner;
  Message_: TAtlasIdeVcsMessage;
  Lock: TCriticalSection;
  // vcs.provider mit Zeitstempel der Datei, aus der er stammt.
  CachedProvider: TAtlasVcsProvider = TAtlasVcsProvider.Auto;
  CachedAge: TDateTime = -1;

function SettingsFile: string;
begin
  Result := TAtlasSettingsFiles.GlobalFile(GetEnvironmentVariable('APPDATA'));
end;

function ReadProvider(const AFileName: string): TAtlasVcsProvider;
var
  Root: TJSONObject;
begin
  Result := TAtlasVcsProvider.Auto;
  try
    Root := TAtlasJsonText.Parse(TAtlasTextFile.Load(AFileName).Text);
    try
      if Root <> nil then
        Result := AtlasVcsProviderOf(TAtlasJsonText.ValueAt(Root, 'vcs.provider'));
    finally
      Root.Free;
    end;
  except
    // Gesperrt oder unlesbar: Vorgabe auto.
    on Exception do
      Result := TAtlasVcsProvider.Auto;
  end;
end;

class function TAtlasIdeVcs.Provider: TAtlasVcsProvider;
var
  FileName: string;
  Age: TDateTime;
begin
  FileName := SettingsFile;
  if (FileName = '') or not FileAge(FileName, Age) then
    Exit(TAtlasVcsProvider.Auto);
  Lock.Enter;
  try
    if Age = CachedAge then
      Exit(CachedProvider);
  finally
    Lock.Leave;
  end;
  Result := ReadProvider(FileName);
  Lock.Enter;
  try
    CachedProvider := Result;
    CachedAge := Age;
  finally
    Lock.Leave;
  end;
end;

procedure ToolMissing(AKind: TAtlasVcsKind);
var
  Name, Text: string;
begin
  Name := AtlasVcsKindName(AKind);
  TAtlasGuard.Log(Format('Versionsverwaltung: %s nicht gefunden, weiter ohne', [Name]));
  Text := Format(TAtlasStrings.Text(TAtlasTextId.VcsToolMissing), [Name, Name]);
  // Kann aus einem Hintergrund-Thread kommen; die Meldungsansicht nur im Hauptthread.
  TThread.ForceQueue(nil,
    procedure
    begin
      if Assigned(Message_) and not TAtlasShutdown.Signalled then
        Message_(Text);
    end);
end;

class procedure TAtlasIdeVcs.Start(const AMessage: TAtlasIdeVcsMessage);
begin
  Message_ := AMessage;
  if Runner = nil then
    Runner := TAtlasVcsProcessRunner.Create(False,
      function: Boolean
      begin
        Result := TAtlasShutdown.Signalled;
      end);
  if Worker = nil then
    Worker := TAtlasVcsWorker.Create;
  TAtlasVcsNotices.OnToolMissing := ToolMissing;
end;

class procedure TAtlasIdeVcs.Stop;
begin
  TAtlasVcsNotices.OnToolMissing := nil;
  Message_ := nil;
  if Worker <> nil then
    Worker.Stop(TAtlasShutdown.StopMs);
  FreeAndNil(Worker);
  Runner := nil;
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string): IAtlasVersionControl;
var
  RunnerRef: IAtlasVcsRunner;
begin
  RunnerRef := Runner;
  if RunnerRef = nil then
    RunnerRef := TAtlasVcsProcessRunner.Create;
  Result := TAtlasVersionControl.Open(AFolder, Provider, RunnerRef);
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
var
  RunnerRef: IAtlasVcsRunner;
begin
  RunnerRef := Runner;
  if RunnerRef = nil then
    RunnerRef := TAtlasVcsProcessRunner.Create;
  Result := TAtlasVersionControl.Open(AFolder, Provider, RunnerRef,
    function(AKind: TAtlasVcsKind): string
    begin
      Result := TAtlasVcsTools.Find(AKind);
    end,
    ATimeoutMs);
end;

class procedure TAtlasIdeVcs.Run(const AWork, ADone: TProc);
begin
  if Worker <> nil then
    Worker.Run(AWork, ADone);
end;

initialization
  Lock := TCriticalSection.Create;

finalization
  TAtlasIdeVcs.Stop;
  FreeAndNil(Lock);

end.
