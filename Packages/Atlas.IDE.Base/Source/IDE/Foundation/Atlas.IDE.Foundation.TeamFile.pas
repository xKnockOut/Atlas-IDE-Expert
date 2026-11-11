unit Atlas.IDE.Foundation.TeamFile;

// Projektdatei .atlas des aktiven Projekts (#486) für alle Teile des Plugins.
// Foundation: nur Open Tools API, VCL-Zeitgeber und Atlas.Core; Lesen
// und Prüfen in Atlas.Core.Settings.TeamFile.
// - Current: gelesener Stand für das aktive Projekt; ohne Projekt, ohne Datei,
//   mit ausgeschalteter Einstellung TeamFile oder vor Start leer (Empty). Eine
//   fehlerhafte Datei ergibt Valid = False: Es gelten die persönlichen
//   Einstellungen.
// - Ort: TAtlasTeamFile.Locate mit dem Ordner der .dproj und dem der
//   geöffneten .groupproj (LocateFor).
// - Ein Zeitgeber prüft alle 2 s im Hauptthread, ob sich aktives Projekt,
//   Ort oder Zeitstempel der Datei geändert haben; nur dann wird neu gelesen
//   und die Version erhöht. Den Ort sucht er (Ordner aufwärts bis zur Wurzel
//   des Repositorys) nur bei anderem Projekt oder anderer Gruppe, nach
//   Refresh, wenn die Datei verschwunden ist, und sonst alle 10 s; je Takt
//   fragt er nur den Zeitstempel der Datei (Dateizugriffe im Hauptthread). Ist die Datei gerade gesperrt, folgt der
//   nächste
//   Versuch beim nächsten Takt.
// - Meldungen zur Datei (fehlerhaft, Zugangsdaten, absolute Pfade …) stehen
//   einmal je gelesenem Stand in der Meldungsansicht (Gruppe Atlas), nie als
//   Dialog und nicht im Protokoll (sie nennen Einträge der Datei).
// - ForProject: Stand für eine beliebige .dproj ohne Meldungen (etwa für die
//   Willkommensseite: Build-Server #763, Tracker #765, Startprofile #764).
// - Version zählt jeden neu gelesenen Stand (für Zwischenspeicher wie die
//   ausgeblendeten Stellen, #628).
// - OpenInEditor: legt die Datei mit Gerüst (TAtlasTeamFile.Skeleton, UTF-8
//   ohne BOM) neben der .dproj an, wenn es noch keine gibt, und öffnet sie.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Settings.TeamFile;

type
  TAtlasIdeTeamFile = class
  private class var
    FInstance: TAtlasIdeTeamFile;
    FVersion: Integer;
  private
    FTimer: TTimer;
    FCurrent: TAtlasTeamSettings;
    FStamp: string;
    /// <summary>Projekt und Gruppe der letzten Suche nach dem Ort, ihr Ergebnis und Zeitpunkt.</summary>
    FLocateKey: string;
    FLocated: string;
    FLocatedAt: UInt64;
    procedure Tick(Sender: TObject);
    /// <summary>Ort der Datei für AProject; sucht nur neu, wenn nötig (siehe Kopf).</summary>
    function LocatedFor(const AProject: string): string;
    procedure Check;
    class function PathExists(const APath: string): Boolean; static;
    /// <summary>Liest AFileName; False, wenn die Datei nicht lesbar ist (gesperrt, gelöscht).</summary>
    class function Load(const AFileName: string; out ATeam: TAtlasTeamSettings): Boolean; static;
    class procedure Report(const ATeam: TAtlasTeamSettings); static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Gilt die .atlas (Hauptschalter und Einstellung TeamFile)? Nur im Hauptthread.</summary>
    class function Wanted: Boolean; static;
    /// <summary>Zeitgeber anlegen und gleich prüfen (Feature TeamFile).</summary>
    class procedure Start; static;
    class procedure Stop; static;
    class function Started: Boolean; static;
    /// <summary>Stand für das aktive Projekt (siehe Kopf).</summary>
    class function Current: TAtlasTeamSettings; static;
    /// <summary>Zählt jeden neu gelesenen Stand von Current (auch Start und Stop).</summary>
    class function Version: Integer; static;
    /// <summary>Stand für AProject (.dproj) ohne Meldungen; leer, wenn die Einstellung TeamFile aus ist.</summary>
    class function ForProject(const AProject: string): TAtlasTeamSettings; static;
    /// <summary>Wie ForProject, aber auch bei ausgeschalteter Einstellung (Anzeige auf der Optionsseite).</summary>
    class function Read(const AProject: string): TAtlasTeamSettings; static;
    /// <summary>Ordner der geöffneten .groupproj; '' ohne Projektgruppe.</summary>
    class function ActiveGroupFolder: string; static;
    /// <summary>Projektdatei für AProject (.dproj) samt geöffneter Projektgruppe; '' ohne.</summary>
    class function LocateFor(const AProject: string): string; static;
    /// <summary>Sofort neu lesen (nach Speichern der Optionen oder Anlegen der Datei).</summary>
    class procedure Refresh; static;
    /// <summary>Befehl Atlas.TeamFile: anlegen, falls nötig, und im Editor öffnen.</summary>
    class procedure OpenInEditor; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.TextFile,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Host;

const
  cCheckMs = 2000;
  /// <summary>Spätestens nach dieser Zeit den Ort neu suchen (neu angelegte Datei weiter oben).</summary>
  cRelocateMs = 10000;

{ TAtlasIdeTeamFile }

constructor TAtlasIdeTeamFile.Create;
begin
  inherited Create;
  FCurrent := TAtlasTeamFile.Empty;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cCheckMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeTeamFile.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

class function TAtlasIdeTeamFile.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.TeamFile;
end;

class function TAtlasIdeTeamFile.PathExists(const APath: string): Boolean;
begin
  // .git ist ein Ordner oder bei Worktrees eine Datei.
  Result := FileExists(APath) or DirectoryExists(APath);
end;

class function TAtlasIdeTeamFile.ActiveGroupFolder: string;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  // Ohne gespeicherte Gruppe ist der Name ohne Ordner (z. B. „ProjectGroup1.groupproj“).
  if (mGroup <> nil) and (ExtractFileDir(mGroup.FileName) <> '') then
  begin
    Result := ExtractFileDir(mGroup.FileName);
  end;
end;

class function TAtlasIdeTeamFile.LocateFor(const AProject: string): string;
begin
  Result := '';
  if AProject <> '' then
  begin
    Result := TAtlasTeamFile.Locate(ExtractFileDir(AProject), ActiveGroupFolder, PathExists);
  end;
end;

class function TAtlasIdeTeamFile.Load(const AFileName: string; out ATeam: TAtlasTeamSettings): Boolean;
var
  mContent: TAtlasTextFileContent;
begin
  ATeam := TAtlasTeamFile.Empty;
  try
    mContent := TAtlasTextFile.Load(AFileName);
  except
    // Gesperrt (gerade gespeichert) oder gelöscht: wie noch nicht gelesen.
    on Exception do
      Exit(False);
  end;
  ATeam := TAtlasTeamFile.Parse(mContent.Text, AFileName,
    TAtlasTeamFile.RootOf(ExtractFileDir(AFileName), PathExists));
  Result := True;
end;

class function TAtlasIdeTeamFile.Read(const AProject: string): TAtlasTeamSettings;
var
  mFileName: string;
begin
  Result := TAtlasTeamFile.Empty;
  if AProject <> '' then
  begin
    mFileName := LocateFor(AProject);
    if (mFileName <> '') and not Load(mFileName, Result) then
    begin
      // Nicht lesbar: als fehlerhaft zeigen, es gelten die persönlichen Einstellungen.
      Result := TAtlasTeamFile.Parse('', mFileName, '');
    end;
  end;
  Result.Project := AProject;
end;

class function TAtlasIdeTeamFile.ForProject(const AProject: string): TAtlasTeamSettings;
begin
  if (FInstance <> nil) and SameText(FInstance.FCurrent.Project, AProject) then
  begin
    Exit(FInstance.FCurrent);
  end;
  Result := TAtlasTeamFile.Empty;
  Result.Project := AProject;
  if Wanted then
  begin
    Result := Read(AProject);
  end;
end;

class procedure TAtlasIdeTeamFile.Report(const ATeam: TAtlasTeamSettings);
var
  mIssue: TAtlasTeamIssue;
begin
  for mIssue in ATeam.Issues do
    case mIssue.Kind of
      TAtlasTeamIssueKind.Syntax:
        if mIssue.Line > 0 then
        begin
          TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueSyntaxAt, [ATeam.FileName, mIssue.Line,
            mIssue.Column]));
        end
        else
        begin
          TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.TeamFileIssueSyntax));
        end;
      TAtlasTeamIssueKind.Version:
        TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.TeamFileIssueVersion));
      TAtlasTeamIssueKind.UnknownKey:
        TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueUnknownKey, [mIssue.Path]));
      TAtlasTeamIssueKind.WrongType:
        TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueWrongType, [mIssue.Path]));
      TAtlasTeamIssueKind.InvalidValue:
        TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueInvalidValue, [mIssue.Path]));
      TAtlasTeamIssueKind.Credential:
        TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueCredential, [mIssue.Path]));
      TAtlasTeamIssueKind.AbsolutePath:
        TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueAbsolutePath, [mIssue.Path]));
      TAtlasTeamIssueKind.OutsidePath:
        TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueOutsidePath, [mIssue.Path]));
    end;
end;

procedure TAtlasIdeTeamFile.Check;
var
  mProject, mFileName, mStamp: string;
  mTeam: TAtlasTeamSettings;
  mAge: TDateTime;
begin
  mProject := '';
  if Wanted then
  begin
    mProject := TAtlasIdeFiles.ActiveProjectFile;
  end;
  mFileName := LocatedFor(mProject);
  mStamp := mProject + '|' + mFileName;
  if mFileName <> '' then
  begin
    if FileAge(mFileName, mAge) then
    begin
      mStamp := mStamp + '|' + FloatToStr(mAge, TFormatSettings.Invariant);
    end
    else
    begin
      // Verschwunden: beim nächsten Takt den Ort neu suchen.
      FLocatedAt := 0;
    end;
  end;
  if mStamp = FStamp then
  begin
    Exit;
  end;
  mTeam := TAtlasTeamFile.Empty;
  if (mFileName <> '') and not Load(mFileName, mTeam) then
  begin
    Exit;
  end;
  mTeam.Project := mProject;
  FStamp := mStamp;
  FCurrent := mTeam;
  Inc(FVersion);
  Report(mTeam);
end;

function TAtlasIdeTeamFile.LocatedFor(const AProject: string): string;
var
  mKey: string;
  mNow: UInt64;
begin
  mKey := AProject + '|' + ActiveGroupFolder;
  mNow := GetTickCount64;
  if (mKey <> FLocateKey) or (FLocatedAt = 0) or (mNow - FLocatedAt >= cRelocateMs) then
  begin
    FLocated := LocateFor(AProject);
    FLocateKey := mKey;
    FLocatedAt := mNow;
  end;
  Result := FLocated;
end;

procedure TAtlasIdeTeamFile.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      Check;
    end);
end;

class procedure TAtlasIdeTeamFile.Start;
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TAtlasIdeTeamFile.Create;
  FInstance.Check;
end;

class procedure TAtlasIdeTeamFile.Stop;
begin
  FreeAndNil(FInstance);
  Inc(FVersion);
end;

class function TAtlasIdeTeamFile.Version: Integer;
begin
  Result := FVersion;
end;

class function TAtlasIdeTeamFile.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeTeamFile.Current: TAtlasTeamSettings;
begin
  if FInstance = nil then
  begin
    Exit(TAtlasTeamFile.Empty);
  end;
  Result := FInstance.FCurrent;
end;

class procedure TAtlasIdeTeamFile.Refresh;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.FStamp := '';
  FInstance.FLocatedAt := 0;
  FInstance.Check;
end;

class procedure TAtlasIdeTeamFile.OpenInEditor;
var
  mProject, mFileName: string;
  mContent: TAtlasTextFileContent;
  mActions: IOTAActionServices;
begin
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  if mProject = '' then
  begin
    TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.TeamFileNoProject));
    Exit;
  end;
  mFileName := LocateFor(mProject);
  if mFileName = '' then
  begin
    mFileName := TPath.Combine(ExtractFileDir(mProject), TAtlasTeamFile.cFileName);
    mContent := Default(TAtlasTextFileContent);
    mContent.Text := TAtlasTeamFile.Skeleton;
    mContent.Encoding := TAtlasTextEncoding.Utf8;
    try
      TAtlasTextFile.Save(mFileName, mContent);
    except
      on E: Exception do
      begin
        TAtlasIdeHost.Message(TAtlasStrings.Fmt(TAtlasTextId.TeamFileCreateFailed, [E.Message]));
        Exit;
      end;
    end;
    TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.TeamFileCreated));
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.OpenFile(mFileName);
  end;
  Refresh;
end;

end.
