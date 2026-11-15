unit Atlas.Core.StartProfiles.Picker;

// Entscheidungen der Startprofile in der IDE (#575), ohne VCL und Open Tools
// API. Atlas.IDE.StartProfiles.Service liest und schreibt die Startoptionen
// des Projekts; hier steht, was es dabei entscheidet:
// - Kennungen der Einträge der Auswahl und was ein gewählter Eintrag tut
//   (Profil setzen, kein Profil, aktuelle Startoptionen speichern, Dateien
//   bearbeiten).
// - Was das Statusfeld zeigt: nichts (kein Projekt oder keine Profile ohne
//   aktives), „–“ (Profile, aber keins aktiv), das aktive Profil oder ein
//   gemerktes, das es nicht mehr gibt.
// - Der Stempel, an dem der Zeitgeber Änderungen von Projekt, Konfiguration,
//   Plattform, .atlas und lokaler Datei merkt.
// - Die Umgebungsvariablen in der Kurzbeschreibung eines Profils.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Settings.TeamFile;

type
  /// <summary>Was ein gewählter Eintrag der Auswahl tut.</summary>
  TAtlasStartProfilePick = (
    /// <summary>Unbekannte Kennung: nichts.</summary>
    Unknown,
    /// <summary>Profil setzen (Name in AName).</summary>
    Profile,
    /// <summary>Kein Startprofil: Startoptionen von vorher.</summary>
    NoProfile,
    /// <summary>Aktuelle Startoptionen als persönliches Profil speichern.</summary>
    SaveCurrent,
    /// <summary>Persönliche Datei bearbeiten.</summary>
    EditPersonal,
    /// <summary>Projektdatei .atlas bearbeiten.</summary>
    EditTeam);

  /// <summary>Was das Statusfeld zeigt.</summary>
  TAtlasStartProfileStatusKind = (
    /// <summary>Kein Feld.</summary>
    Hidden,
    /// <summary>Profile vorhanden, keins aktiv („–“).</summary>
    NoneActive,
    /// <summary>Das aktive Profil.</summary>
    Active,
    /// <summary>Gemerktes Profil, das es nicht mehr gibt.</summary>
    Missing);

  /// <summary>Änderungszeit einer Datei für den Stempel; Known False = Datei fehlt.</summary>
  TAtlasStartProfileFileAge = record
    Known: Boolean;
    Age: TDateTime;
    class function Make(AKnown: Boolean; AAge: TDateTime): TAtlasStartProfileFileAge; static;
  end;

  TAtlasStartProfilePicker = record
  public const
    cNoneId = 'atlas:none';
    cSaveId = 'atlas:save';
    cEditPersonalId = 'atlas:personal';
    cEditTeamId = 'atlas:team';
    cProfilePrefix = 'profile:';
  public
    /// <summary>Kennung des Eintrags für das Profil AName.</summary>
    class function ProfileId(const AName: string): string; static;
    /// <summary>Was der Eintrag mit der Kennung AId tut; AName ist der Profilname bei Profile.</summary>
    class function Parse(const AId: string; out AName: string): TAtlasStartProfilePick; static;
    /// <summary>„Kein Startprofil“ steht nur in der Auswahl, wenn eines aktiv ist.</summary>
    class function OffersNone(const AActive: string): Boolean; static;
    /// <summary>Inhalt des Statusfelds: AProject '' = kein Projekt, AProfileCount Profile des Projekts, AActive
    /// gemerktes aktives Profil, AFound: es steht unter den Profilen.</summary>
    class function StatusKind(const AProject: string; AProfileCount: Integer; const AActive: string;
      AFound: Boolean): TAtlasStartProfileStatusKind; static;
    /// <summary>Stempel für Projekt, Konfiguration, Plattform, .atlas und lokale Datei; '' ohne Projekt.</summary>
    class function Stamp(const AProject, AConfiguration, APlatform, ATeamFile: string;
      const ATeamAge, APersonalAge: TAtlasStartProfileFileAge): string; static;
    /// <summary>„Name=Wert, Name=Wert“; '' ohne Variablen.</summary>
    class function EnvironmentText(const AVariables: TArray<TAtlasTeamVariable>): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasStartProfileFileAge }

class function TAtlasStartProfileFileAge.Make(AKnown: Boolean; AAge: TDateTime): TAtlasStartProfileFileAge;
begin
  Result.Known := AKnown;
  Result.Age := AAge;
end;

{ TAtlasStartProfilePicker }

class function TAtlasStartProfilePicker.ProfileId(const AName: string): string;
begin
  Result := cProfilePrefix + AName;
end;

class function TAtlasStartProfilePicker.Parse(const AId: string; out AName: string): TAtlasStartProfilePick;
begin
  AName := '';
  Result := TAtlasStartProfilePick.Unknown;
  if AId = cNoneId then
  begin
    Result := TAtlasStartProfilePick.NoProfile;
  end
  else if AId = cSaveId then
  begin
    Result := TAtlasStartProfilePick.SaveCurrent;
  end
  else if AId = cEditPersonalId then
  begin
    Result := TAtlasStartProfilePick.EditPersonal;
  end
  else if AId = cEditTeamId then
  begin
    Result := TAtlasStartProfilePick.EditTeam;
  end
  else if Copy(AId, 1, Length(cProfilePrefix)) = cProfilePrefix then
  begin
    AName := Copy(AId, Length(cProfilePrefix) + 1, MaxInt);
    Result := TAtlasStartProfilePick.Profile;
  end;
end;

class function TAtlasStartProfilePicker.OffersNone(const AActive: string): Boolean;
begin
  Result := AActive <> '';
end;

class function TAtlasStartProfilePicker.StatusKind(const AProject: string; AProfileCount: Integer;
  const AActive: string; AFound: Boolean): TAtlasStartProfileStatusKind;
begin
  Result := TAtlasStartProfileStatusKind.Hidden;
  if AProject = '' then
  begin
    Exit;
  end;
  if AActive = '' then
  begin
    // Ohne Profile kein Feld; mit Profilen zeigt es „–“.
    if AProfileCount > 0 then
    begin
      Result := TAtlasStartProfileStatusKind.NoneActive;
    end;
  end
  else if AFound then
  begin
    Result := TAtlasStartProfileStatusKind.Active;
  end
  else
  begin
    Result := TAtlasStartProfileStatusKind.Missing;
  end;
end;

class function TAtlasStartProfilePicker.Stamp(const AProject, AConfiguration, APlatform, ATeamFile: string;
  const ATeamAge, APersonalAge: TAtlasStartProfileFileAge): string;
begin
  Result := '';
  if AProject = '' then
  begin
    Exit;
  end;
  Result := AProject + '|' + AConfiguration + '|' + APlatform + '|' + ATeamFile;
  if (ATeamFile <> '') and ATeamAge.Known then
  begin
    Result := Result + '|' + FloatToStr(ATeamAge.Age, TFormatSettings.Invariant);
  end;
  if APersonalAge.Known then
  begin
    Result := Result + '|' + FloatToStr(APersonalAge.Age, TFormatSettings.Invariant);
  end;
end;

class function TAtlasStartProfilePicker.EnvironmentText(const AVariables: TArray<TAtlasTeamVariable>): string;
var
  mVariable: TAtlasTeamVariable;
begin
  Result := '';
  for mVariable in AVariables do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mVariable.Name + '=' + mVariable.Value;
  end;
end;

end.
