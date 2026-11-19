unit Atlas.Core.StartProfiles.Flow;

// Ablauf der Startprofile (#575) ohne VCL und Open Tools API: Profil setzen,
// kein Profil (Startoptionen von vorher zurück), gemerktes Profil erneut
// setzen, aktuelle Startoptionen als persönliches Profil speichern, Inhalt des
// Statusfelds. Die Startoptionen des Projekts liest und schreibt der Aufrufer
// über TAtlasStartProfileAccess (in der IDE Atlas.IDE.StartProfiles.Service
// über Atlas.IDE.Foundation.StartOptions); die lokale Datei liegt unter
// Folder (Atlas.Core.StartProfiles.Store). Texte bildet der Aufrufer aus dem
// Ergebnis.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.StartProfiles.Store,
  Atlas.Core.StartProfiles.Picker;

type
  /// <summary>Projektdatei .atlas für AProject (leer, wenn sie ausgeschaltet ist).</summary>
  TAtlasStartTeamOf = reference to function(const AProject: string): TAtlasTeamSettings;
  /// <summary>Startoptionen des geöffneten AProject; False, wenn das Projekt nicht offen ist.</summary>
  TAtlasStartOptionsRead = reference to function(const AProject: string; out AOptions: TAtlasStartOptions): Boolean;
  /// <summary>Startoptionen von AProject schreiben; False mit Grund.</summary>
  TAtlasStartOptionsWrite = reference to function(const AProject: string; const AOptions: TAtlasStartOptions;
    out AReason: string): Boolean;

  /// <summary>Zugriff auf Projekt und Dateien.</summary>
  TAtlasStartProfileAccess = record
    /// <summary>Ordner der lokalen Dateien (startprofiles).</summary>
    Folder: string;
    TeamOf: TAtlasStartTeamOf;
    ReadOptions: TAtlasStartOptionsRead;
    WriteOptions: TAtlasStartOptionsWrite;
  end;

  /// <summary>Ergebnis eines Schritts.</summary>
  TAtlasStartProfileOutcome = (
    /// <summary>Nichts zu tun oder still erledigt.</summary>
    Done,
    /// <summary>Profil Name gesetzt, Options geschrieben.</summary>
    Applied,
    /// <summary>Kein Profil mehr; die Startoptionen von vorher gelten wieder.</summary>
    Restored,
    /// <summary>Persönliches Profil Name gespeichert.</summary>
    Saved,
    /// <summary>Das Projekt ist nicht offen.</summary>
    NotOpen,
    /// <summary>Profil Name gibt es für das Projekt nicht.</summary>
    Unknown,
    /// <summary>Leerer Profilname.</summary>
    InvalidName,
    /// <summary>Schreiben der Startoptionen scheiterte; Reason nennt den Grund.</summary>
    WriteFailed,
    /// <summary>Die lokale Datei ließ sich nicht speichern.</summary>
    SaveFailed);

  TAtlasStartProfileResult = record
    Outcome: TAtlasStartProfileOutcome;
    /// <summary>Profilname (bei Applied, Saved, Unknown).</summary>
    Name: string;
    /// <summary>Geschriebene Startoptionen (bei Applied).</summary>
    Options: TAtlasStartOptions;
    /// <summary>Grund bei WriteFailed.</summary>
    Reason: string;
    class function Make(AOutcome: TAtlasStartProfileOutcome; const AName: string): TAtlasStartProfileResult;
      static;
    /// <summary>Kein Fehler (Done, Applied, Restored, Saved).</summary>
    function Succeeded: Boolean;
  end;

  /// <summary>Inhalt des Statusfelds: Kind, gemerktes aktives Profil, bei Active sein Eintrag.</summary>
  TAtlasStartProfileStatus = record
    Kind: TAtlasStartProfileStatusKind;
    Active: string;
    Entry: TAtlasStartProfileEntry;
  end;

  TAtlasStartProfileFlow = class
  private
    FAccess: TAtlasStartProfileAccess;
    function Team(const AProject: string): TAtlasTeamSettings;
    function WriteTo(const AProject: string; const AOptions: TAtlasStartOptions;
      var AResult: TAtlasStartProfileResult): Boolean;
    function Save(const AState: TAtlasStartProfileState; var AResult: TAtlasStartProfileResult): Boolean;
    function Restore(const AProject: string; var AState: TAtlasStartProfileState): TAtlasStartProfileResult;
    function Apply(const AProject, AName: string; var AState: TAtlasStartProfileState;
      const ACurrent: TAtlasStartOptions): TAtlasStartProfileResult;
  public
    constructor Create(const AAccess: TAtlasStartProfileAccess);
    /// <summary>Profile für AProject: aus .atlas, dann die persönlichen; leer ohne Projekt.</summary>
    function Profiles(const AProject: string): TArray<TAtlasStartProfileEntry>;
    /// <summary>Gemerktes aktives Profil von AProject; '' ohne.</summary>
    function ActiveName(const AProject: string): string;
    /// <summary>Was das Statusfeld für AProject zeigt ('' = kein Projekt).</summary>
    function Status(const AProject: string): TAtlasStartProfileStatus;
    /// <summary>Profil AName für das geöffnete AProject setzen und merken; AName '' = kein Profil (Startoptionen
    /// von vorher). Erst wird gemerkt, was vorher galt, dann geschrieben: Scheitert das Schreiben, bleibt die
    /// lokale Datei, wie sie war.</summary>
    function Activate(const AProject, AName: string): TAtlasStartProfileResult;
    /// <summary>Gemerktes Profil von AProject erneut setzen (Projekt, Konfiguration oder Dateien geändert); Done
    /// ohne aktives oder mit fehlendem Profil.</summary>
    function Reapply(const AProject: string): TAtlasStartProfileResult;
    /// <summary>Aktuelle Startoptionen von AProject als persönliches Profil AName speichern (Saved mit dem
    /// getrimmten Namen); aktiv wird es erst mit Activate.</summary>
    function SaveCurrent(const AProject, AName: string): TAtlasStartProfileResult;
    /// <summary>Lokale Datei von AProject, bei Bedarf leer angelegt; False, wenn sie sich nicht anlegen lässt.
    /// </summary>
    function PersonalFile(const AProject: string; out AFileName: string): Boolean;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasStartProfileResult }

class function TAtlasStartProfileResult.Make(AOutcome: TAtlasStartProfileOutcome;
  const AName: string): TAtlasStartProfileResult;
begin
  Result := Default(TAtlasStartProfileResult);
  Result.Outcome := AOutcome;
  Result.Name := AName;
end;

function TAtlasStartProfileResult.Succeeded: Boolean;
begin
  Result := Outcome in [TAtlasStartProfileOutcome.Done, TAtlasStartProfileOutcome.Applied,
    TAtlasStartProfileOutcome.Restored, TAtlasStartProfileOutcome.Saved];
end;

{ TAtlasStartProfileFlow }

constructor TAtlasStartProfileFlow.Create(const AAccess: TAtlasStartProfileAccess);
begin
  inherited Create;
  FAccess := AAccess;
end;

function TAtlasStartProfileFlow.Team(const AProject: string): TAtlasTeamSettings;
begin
  Result := Default(TAtlasTeamSettings);
  if Assigned(FAccess.TeamOf) then
  begin
    Result := FAccess.TeamOf(AProject);
  end;
end;

function TAtlasStartProfileFlow.Profiles(const AProject: string): TArray<TAtlasStartProfileEntry>;
begin
  Result := nil;
  if AProject = '' then
  begin
    Exit;
  end;
  Result := TAtlasStartProfiles.ForProject(FAccess.Folder, AProject, Team(AProject));
end;

function TAtlasStartProfileFlow.ActiveName(const AProject: string): string;
begin
  Result := '';
  if AProject <> '' then
  begin
    Result := TAtlasStartProfiles.Load(FAccess.Folder, AProject).Active;
  end;
end;

function TAtlasStartProfileFlow.Status(const AProject: string): TAtlasStartProfileStatus;
var
  mEntries: TArray<TAtlasStartProfileEntry>;
  mFound: Boolean;
begin
  Result := Default(TAtlasStartProfileStatus);
  mEntries := Profiles(AProject);
  Result.Active := ActiveName(AProject);
  mFound := (Result.Active <> '') and TAtlasStartProfiles.Find(mEntries, Result.Active, Result.Entry);
  Result.Kind := TAtlasStartProfilePicker.StatusKind(AProject, Length(mEntries), Result.Active, mFound);
end;

function TAtlasStartProfileFlow.WriteTo(const AProject: string; const AOptions: TAtlasStartOptions;
  var AResult: TAtlasStartProfileResult): Boolean;
var
  mReason: string;
begin
  mReason := '';
  Result := Assigned(FAccess.WriteOptions) and FAccess.WriteOptions(AProject, AOptions, mReason);
  if not Result then
  begin
    AResult := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.WriteFailed, AResult.Name);
    AResult.Reason := mReason;
  end;
end;

function TAtlasStartProfileFlow.Save(const AState: TAtlasStartProfileState;
  var AResult: TAtlasStartProfileResult): Boolean;
begin
  Result := TAtlasStartProfiles.Save(FAccess.Folder, AState);
  if not Result then
  begin
    AResult := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.SaveFailed, AResult.Name);
  end;
end;

function TAtlasStartProfileFlow.Restore(const AProject: string;
  var AState: TAtlasStartProfileState): TAtlasStartProfileResult;
var
  mOptions: TAtlasStartOptions;
begin
  // Ohne gemerkte Startoptionen bleiben die jetzigen.
  Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.Restored, '');
  if TAtlasStartProfiles.Deactivate(AState, mOptions) and not WriteTo(AProject, mOptions, Result) then
  begin
    Exit;
  end;
  Save(AState, Result);
end;

function TAtlasStartProfileFlow.Apply(const AProject, AName: string; var AState: TAtlasStartProfileState;
  const ACurrent: TAtlasStartOptions): TAtlasStartProfileResult;
var
  mEntry: TAtlasStartProfileEntry;
begin
  if not TAtlasStartProfiles.Find(TAtlasStartProfiles.Merge(Team(AProject), AState), AName, mEntry) then
  begin
    Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.Unknown, AName);
    Exit;
  end;
  Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.Applied, mEntry.Profile.Name);
  Result.Options := TAtlasStartProfiles.OptionsOf(mEntry);
  TAtlasStartProfiles.Activate(AState, mEntry.Profile.Name, ACurrent);
  if WriteTo(AProject, Result.Options, Result) then
  begin
    Save(AState, Result);
  end;
end;

function TAtlasStartProfileFlow.Activate(const AProject, AName: string): TAtlasStartProfileResult;
var
  mCurrent: TAtlasStartOptions;
  mState: TAtlasStartProfileState;
begin
  if not Assigned(FAccess.ReadOptions) or not FAccess.ReadOptions(AProject, mCurrent) then
  begin
    Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.NotOpen, '');
    Exit;
  end;
  mState := TAtlasStartProfiles.Load(FAccess.Folder, AProject);
  if Trim(AName) = '' then
  begin
    Result := Restore(AProject, mState);
  end
  else
  begin
    Result := Apply(AProject, AName, mState, mCurrent);
  end;
end;

function TAtlasStartProfileFlow.Reapply(const AProject: string): TAtlasStartProfileResult;
var
  mActive: string;
  mEntry: TAtlasStartProfileEntry;
begin
  Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.Done, '');
  mActive := ActiveName(AProject);
  if (mActive = '') or not TAtlasStartProfiles.Find(Profiles(AProject), mActive, mEntry) then
  begin
    Exit;
  end;
  Result.Name := mEntry.Profile.Name;
  WriteTo(AProject, TAtlasStartProfiles.OptionsOf(mEntry), Result);
end;

function TAtlasStartProfileFlow.SaveCurrent(const AProject, AName: string): TAtlasStartProfileResult;
var
  mOptions: TAtlasStartOptions;
  mState: TAtlasStartProfileState;
begin
  if Trim(AName) = '' then
  begin
    Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.InvalidName, '');
    Exit;
  end;
  if not Assigned(FAccess.ReadOptions) or not FAccess.ReadOptions(AProject, mOptions) then
  begin
    Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.NotOpen, '');
    Exit;
  end;
  Result := TAtlasStartProfileResult.Make(TAtlasStartProfileOutcome.Saved, Trim(AName));
  mState := TAtlasStartProfiles.Load(FAccess.Folder, AProject);
  TAtlasStartProfiles.PutPersonal(mState, TAtlasStartProfiles.ProfileFromOptions(AName, mOptions));
  Save(mState, Result);
end;

function TAtlasStartProfileFlow.PersonalFile(const AProject: string; out AFileName: string): Boolean;
begin
  AFileName := TAtlasStartProfiles.FileFor(FAccess.Folder, AProject);
  Result := FileExists(AFileName) or TAtlasStartProfiles.Save(FAccess.Folder, TAtlasStartProfiles.Empty(AProject));
end;

end.
