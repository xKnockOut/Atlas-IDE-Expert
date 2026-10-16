unit Atlas.IDE.Foundation.TeamFile;

// Projektdatei .atlas des aktiven Projekts (#486) für alle Teile des Plugins.
// Foundation (A-09): nur Open Tools API, VCL-Zeitgeber und Atlas.Core; Lesen
// und Prüfen in Atlas.Core.Settings.TeamFile.
// - Current: gelesener Stand für das aktive Projekt; ohne Projekt, ohne Datei,
//   mit ausgeschalteter Einstellung TeamFile oder vor Start leer (Empty). Eine
//   fehlerhafte Datei ergibt Valid = False: Es gelten die persönlichen
//   Einstellungen.
// - Ein Zeitgeber prüft alle 2 s im Hauptthread, ob sich aktives Projekt,
//   Ort oder Zeitstempel der Datei geändert haben; nur dann wird neu gelesen
//   und OnChanged gerufen. Ist die Datei gerade gesperrt, folgt der nächste
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
    FOnChanged: TProc;
    FVersion: Integer;
  private
    FTimer: TTimer;
    FCurrent: TAtlasTeamSettings;
    FStamp: string;
    procedure Tick(Sender: TObject);
    procedure Check;
    class function Wanted: Boolean; static;
    class function PathExists(const APath: string): Boolean; static;
    /// <summary>Liest AFileName; False, wenn die Datei nicht lesbar ist (gesperrt, gelöscht).</summary>
    class function Load(const AFileName: string; out ATeam: TAtlasTeamSettings): Boolean; static;
    class procedure Report(const ATeam: TAtlasTeamSettings); static;
    class procedure MessageLine(const AText: string); static;
  public
    constructor Create;
    destructor Destroy; override;
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
    /// <summary>.dproj des aktiven Projekts; '' ohne.</summary>
    class function ActiveProject: string; static;
    /// <summary>Sofort neu lesen (nach Speichern der Optionen oder Anlegen der Datei).</summary>
    class procedure Refresh; static;
    /// <summary>Befehl Atlas.TeamFile: anlegen, falls nötig, und im Editor öffnen.</summary>
    class procedure OpenInEditor; static;
    /// <summary>Nach jedem neu gelesenen Stand (z. B. Code-Vorlagen neu laden).</summary>
    class property OnChanged: TProc read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.TextFile,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Strings;

const
  CheckMs = 2000;

{ TAtlasIdeTeamFile }

constructor TAtlasIdeTeamFile.Create;
begin
  inherited Create;
  FCurrent := TAtlasTeamFile.Empty;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := CheckMs;
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

class function TAtlasIdeTeamFile.ActiveProject: string;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Project := Services.GetActiveProject;
  if Project <> nil then
    Result := Project.FileName;
end;

class function TAtlasIdeTeamFile.Load(const AFileName: string; out ATeam: TAtlasTeamSettings): Boolean;
var
  Content: TAtlasTextFileContent;
begin
  ATeam := TAtlasTeamFile.Empty;
  try
    Content := TAtlasTextFile.Load(AFileName);
  except
    // Gesperrt (gerade gespeichert) oder gelöscht: wie noch nicht gelesen.
    on Exception do
      Exit(False);
  end;
  ATeam := TAtlasTeamFile.Parse(Content.Text, AFileName,
    TAtlasTeamFile.RootOf(ExtractFileDir(AFileName), PathExists));
  Result := True;
end;

class function TAtlasIdeTeamFile.Read(const AProject: string): TAtlasTeamSettings;
var
  FileName: string;
begin
  Result := TAtlasTeamFile.Empty;
  if AProject <> '' then
  begin
    FileName := TAtlasTeamFile.Locate(ExtractFileDir(AProject), PathExists);
    if (FileName <> '') and not Load(FileName, Result) then
    begin
      // Nicht lesbar: als fehlerhaft zeigen, es gelten die persönlichen Einstellungen.
      Result := TAtlasTeamFile.Parse('', FileName, '');
    end;
  end;
  Result.Project := AProject;
end;

class function TAtlasIdeTeamFile.ForProject(const AProject: string): TAtlasTeamSettings;
begin
  if (FInstance <> nil) and SameText(FInstance.FCurrent.Project, AProject) then
    Exit(FInstance.FCurrent);
  Result := TAtlasTeamFile.Empty;
  Result.Project := AProject;
  if Wanted then
    Result := Read(AProject);
end;

class procedure TAtlasIdeTeamFile.MessageLine(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  Messages.AddTitleMessage(AText, Group);
end;

class procedure TAtlasIdeTeamFile.Report(const ATeam: TAtlasTeamSettings);
var
  Issue: TAtlasTeamIssue;
begin
  for Issue in ATeam.Issues do
    case Issue.Kind of
      TAtlasTeamIssueKind.Syntax:
        MessageLine(TAtlasStrings.Text(TAtlasTextId.TeamFileIssueSyntax));
      TAtlasTeamIssueKind.Version:
        MessageLine(TAtlasStrings.Text(TAtlasTextId.TeamFileIssueVersion));
      TAtlasTeamIssueKind.UnknownKey:
        MessageLine(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueUnknownKey, [Issue.Path]));
      TAtlasTeamIssueKind.WrongType:
        MessageLine(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueWrongType, [Issue.Path]));
      TAtlasTeamIssueKind.InvalidValue:
        MessageLine(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueInvalidValue, [Issue.Path]));
      TAtlasTeamIssueKind.Credential:
        MessageLine(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueCredential, [Issue.Path]));
      TAtlasTeamIssueKind.AbsolutePath:
        MessageLine(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueAbsolutePath, [Issue.Path]));
      TAtlasTeamIssueKind.OutsidePath:
        MessageLine(TAtlasStrings.Fmt(TAtlasTextId.TeamFileIssueOutsidePath, [Issue.Path]));
    end;
end;

procedure TAtlasIdeTeamFile.Check;
var
  Project, FileName, Stamp: string;
  Team: TAtlasTeamSettings;
  Age: TDateTime;
begin
  Project := '';
  if Wanted then
    Project := ActiveProject;
  FileName := '';
  if Project <> '' then
    FileName := TAtlasTeamFile.Locate(ExtractFileDir(Project), PathExists);
  Stamp := Project + '|' + FileName;
  if (FileName <> '') and FileAge(FileName, Age) then
    Stamp := Stamp + '|' + FloatToStr(Age);
  if Stamp = FStamp then
    Exit;
  Team := TAtlasTeamFile.Empty;
  if (FileName <> '') and not Load(FileName, Team) then
    Exit;
  Team.Project := Project;
  FStamp := Stamp;
  FCurrent := Team;
  Inc(FVersion);
  Report(Team);
  if Assigned(FOnChanged) then
    FOnChanged();
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
    Exit;
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
    Exit(TAtlasTeamFile.Empty);
  Result := FInstance.FCurrent;
end;

class procedure TAtlasIdeTeamFile.Refresh;
begin
  if FInstance = nil then
    Exit;
  FInstance.FStamp := '';
  FInstance.Check;
end;

class procedure TAtlasIdeTeamFile.OpenInEditor;
var
  Project, FileName: string;
  Content: TAtlasTextFileContent;
  Actions: IOTAActionServices;
begin
  Project := ActiveProject;
  if Project = '' then
  begin
    MessageLine(TAtlasStrings.Text(TAtlasTextId.TeamFileNoProject));
    Exit;
  end;
  FileName := TAtlasTeamFile.Locate(ExtractFileDir(Project), PathExists);
  if FileName = '' then
  begin
    FileName := TPath.Combine(ExtractFileDir(Project), TAtlasTeamFile.FileName);
    Content := Default(TAtlasTextFileContent);
    Content.Text := TAtlasTeamFile.Skeleton;
    Content.Encoding := TAtlasTextEncoding.Utf8;
    try
      TAtlasTextFile.Save(FileName, Content);
    except
      on E: Exception do
      begin
        MessageLine(TAtlasStrings.Fmt(TAtlasTextId.TeamFileCreateFailed, [E.Message]));
        Exit;
      end;
    end;
    MessageLine(TAtlasStrings.Text(TAtlasTextId.TeamFileCreated));
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    Actions.OpenFile(FileName);
  Refresh;
end;

end.
