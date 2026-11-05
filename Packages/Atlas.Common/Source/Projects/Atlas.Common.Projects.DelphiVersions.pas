unit Atlas.Common.Projects.DelphiVersions;

// Auswahl der Delphi-Version je Projekt (#47).
//
// Reihenfolge: "delphiVersion" aus der Konfiguration, wenn sie installiert ist,
// sonst die zur <ProjectVersion> der .dproj passende Installation, sonst die
// nächsthöhere, sonst die neueste. Eine konfigurierte, aber fehlende Version
// ergibt eine Warnung an "delphiVersion" in atlas.json (ConfigurationIssues).
// Ohne jede Installation (Linux, CI, Cloud) gilt die Version, die das Projekt
// erwartet: die konfigurierte, sonst die zur ProjectVersion, sonst die neueste
// bekannte. Sie bestimmt dann nur CompilerVersion, RTLVersion und VERxxx, damit
// {$IF CompilerVersion ...} wie in der IDE ausgewertet wird (#1321).
// Die Zuordnung ProjectVersion -> BDS-Version ist eine Näherung: Die IDE
// schreibt beim Speichern ihre eigene ProjectVersion, Zwischenstände einer
// Hauptversion liegen in einem Bereich.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract;

type
  TDelphiVersions = record
  public
    /// <summary>Inhalt von &lt;ProjectVersion&gt; einer .dproj; '' wenn nicht vorhanden.</summary>
    class function ProjectVersionOf(const ADprojText: string): string; static;
    /// <summary>BDS-Version (z. B. "22.0") für eine ProjectVersion (z. B. "19.5"); '' wenn unbekannt.</summary>
    class function BdsForProjectVersion(const AProjectVersion: string): string; static;
    /// <summary>Produktname, z. B. "Delphi 12" für "23.0"; sonst "BDS 23.0".</summary>
    class function ProductName(const ABdsVersion: string): string; static;
    /// <summary>Ist ABdsVersion unter AInstalled (Zahlenvergleich, "23" = "23.0")?</summary>
    class function IsInstalled(const ABdsVersion: string; const AInstalled: TArray<string>): Boolean; static;
    /// <summary>Neueste BDS-Version, die Atlas kennt (z. B. "37.0" für Delphi 13).</summary>
    class function LatestKnown: string; static;
    /// <summary>Zu verwendende Version aus den installierten (aufsteigend sortiert): die konfigurierte, wenn
    /// sie installiert ist, sonst die passende, sonst die nächsthöhere, sonst die neueste Installation.
    /// Ist nichts installiert, die erwartete Version: die konfigurierte, sonst die zur ProjectVersion, sonst
    /// LatestKnown (#1321); ob sie installiert ist, sagt IsInstalled.
    /// AConfiguredMissing = konfiguriert, aber nicht installiert.</summary>
    class function Choose(const AConfigured, AProjectVersion: string; const AInstalled: TArray<string>;
      out AConfiguredMissing: Boolean): string; overload; static;
    /// <summary>Wie oben, ohne Rückmeldung zur konfigurierten Version.</summary>
    class function Choose(const AConfigured, AProjectVersion: string;
      const AInstalled: TArray<string>): string; overload; static;
    /// <summary>Warnung an "delphiVersion", wenn die Version aus ASettings nicht installiert ist (#47).</summary>
    class function ConfigurationIssues(const ASettings: TServerSettings;
      const AInstalled: TArray<string>): TArray<TConfigurationIssue>; static;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDelphiVersionsText = (BDSIsNotInstalledAnd, BDSIsNotInstalledAtlas);

const
  cTexts: array[TDelphiVersionsText] of TAtlasText = (
    (De: '%s (BDS %s) ist nicht installiert und keine andere Delphi-Version gefunden; Bibliothekspfade und ' +
      'RTL-Quellen fehlen';
     En: '%s (BDS %s) is not installed and no other Delphi version was found; library paths and RTL sources are ' +
      'missing'),
    (De: '%s (BDS %s) ist nicht installiert; Atlas wählt die Version automatisch (je Projekt nach ProjectVersion der ' +
      '.dproj, sonst %s)';
     En: '%s (BDS %s) is not installed; Atlas chooses the version automatically (per project by ProjectVersion of ' +
      'the .dproj, otherwise %s)'));

{$SCOPEDENUMS OFF}

type
  TVersionRange = record
    FromProject: Double;
    Bds: string;
    Name: string;
  end;

const
  // Aufsteigend nach erster ProjectVersion der jeweiligen Hauptversion.
  Ranges: array[0..7] of TVersionRange = (
    (FromProject: 15.0; Bds: '14.0'; Name: 'Delphi XE6'),
    (FromProject: 18.0; Bds: '19.0'; Name: 'Delphi 10.2'),
    (FromProject: 18.5; Bds: '20.0'; Name: 'Delphi 10.3'),
    (FromProject: 19.0; Bds: '21.0'; Name: 'Delphi 10.4'),
    (FromProject: 19.3; Bds: '22.0'; Name: 'Delphi 11'),
    (FromProject: 20.0; Bds: '23.0'; Name: 'Delphi 12'),
    (FromProject: 20.3; Bds: '37.0'; Name: 'Delphi 13'),
    (FromProject: 99.0; Bds: ''; Name: ''));

function ToNumber(const AText: string): Double;
begin
  Result := StrToFloatDef(Trim(AText), 0, TFormatSettings.Invariant);
end;

class function TDelphiVersions.ProjectVersionOf(const ADprojText: string): string;
var
  Start, Stop: Integer;
begin
  Result := '';
  Start := Pos('<ProjectVersion>', ADprojText);
  if Start = 0 then
  begin
    Exit;
  end;
  Inc(Start, Length('<ProjectVersion>'));
  Stop := Pos('</ProjectVersion>', ADprojText);
  if Stop > Start then
  begin
    Result := Trim(Copy(ADprojText, Start, Stop - Start));
  end;
end;

class function TDelphiVersions.BdsForProjectVersion(const AProjectVersion: string): string;
var
  Value: Double;
  Index: Integer;
begin
  Result := '';
  Value := ToNumber(AProjectVersion);
  if Value < Ranges[0].FromProject then
  begin
    Exit;
  end;
  for Index := 0 to High(Ranges) - 1 do
  begin
    if (Value >= Ranges[Index].FromProject) and (Value < Ranges[Index + 1].FromProject) then
    begin
      Exit(Ranges[Index].Bds);
    end;
  end;
end;

class function TDelphiVersions.ProductName(const ABdsVersion: string): string;
var
  Range: TVersionRange;
begin
  for Range in Ranges do
  begin
    if (Range.Bds <> '') and (ToNumber(Range.Bds) = ToNumber(ABdsVersion)) then
    begin
      Exit(Range.Name);
    end;
  end;
  Result := 'BDS ' + ABdsVersion;
end;

class function TDelphiVersions.IsInstalled(const ABdsVersion: string; const AInstalled: TArray<string>): Boolean;
var
  Version: string;
begin
  Result := False;
  if ToNumber(ABdsVersion) = 0 then
  begin
    Exit;
  end;
  for Version in AInstalled do
  begin
    if ToNumber(Version) = ToNumber(ABdsVersion) then
    begin
      Exit(True);
    end;
  end;
end;

class function TDelphiVersions.LatestKnown: string;
begin
  Result := Ranges[High(Ranges) - 1].Bds;
end;

class function TDelphiVersions.Choose(const AConfigured, AProjectVersion: string;
  const AInstalled: TArray<string>): string;
var
  Missing: Boolean;
begin
  Result := Choose(AConfigured, AProjectVersion, AInstalled, Missing);
end;

/// <summary>Wahl ohne Installation: die eingestellte Version, sonst die zum Projekt passende, sonst die neueste
/// bekannte.</summary>
function ChooseWithoutInstallation(const AConfigured, AWanted: string): string;
begin
  if ToNumber(AConfigured) > 0 then
  begin
    Result := AConfigured;
  end
  else if AWanted <> '' then
  begin
    Result := AWanted;
  end
  else
  begin
    Result := TDelphiVersions.LatestKnown;
  end;
end;

/// <summary>Erste installierte Version ab AWanted, sonst die letzte installierte.</summary>
function ChooseInstalled(const AWanted: string; const AInstalled: TArray<string>): string;
var
  mVersion: string;
begin
  if AWanted <> '' then
  begin
    for mVersion in AInstalled do
    begin
      if ToNumber(mVersion) >= ToNumber(AWanted) then
      begin
        Exit(mVersion);
      end;
    end;
  end;
  Result := AInstalled[High(AInstalled)];
end;

class function TDelphiVersions.Choose(const AConfigured, AProjectVersion: string; const AInstalled: TArray<string>;
  out AConfiguredMissing: Boolean): string;
var
  mWanted: string;
begin
  AConfiguredMissing := False;
  if AConfigured <> '' then
  begin
    if IsInstalled(AConfigured, AInstalled) then
    begin
      Exit(AConfigured);
    end;
    // Fehlt sie, liefe das Projekt ohne Bibliothekspfade; die automatische Wahl greift (#47).
    AConfiguredMissing := True;
  end;
  mWanted := BdsForProjectVersion(AProjectVersion);
  // Ohne Installation fehlten sonst CompilerVersion und VERxxx, und beide Zweige von
  // {$IF CompilerVersion >= 36}A{$ELSE}B{$ENDIF} blieben stehen (#1321).
  if Length(AInstalled) = 0 then
  begin
    Result := ChooseWithoutInstallation(AConfigured, mWanted);
  end
  else
  begin
    Result := ChooseInstalled(mWanted, AInstalled);
  end;
end;

class function TDelphiVersions.ConfigurationIssues(const ASettings: TServerSettings;
  const AInstalled: TArray<string>): TArray<TConfigurationIssue>;
var
  Issue: TConfigurationIssue;
  Fallback: string;
  Missing: Boolean;
begin
  Result := nil;
  if (ASettings.DelphiVersion = '') or IsInstalled(ASettings.DelphiVersion, AInstalled) then
  begin
    Exit;
  end;
  Issue := Default(TConfigurationIssue);
  Issue.Range := ASettings.DelphiVersionRange;
  Issue.IsError := False;
  if Length(AInstalled) = 0 then
  begin
    Issue.Message := cTexts[TDelphiVersionsText.BDSIsNotInstalledAnd].Fmt([ProductName(ASettings.DelphiVersion),
      ASettings.DelphiVersion]);
  end
  else
  begin
    Fallback := Choose(ASettings.DelphiVersion, '', AInstalled, Missing);
    Issue.Message := cTexts[TDelphiVersionsText.BDSIsNotInstalledAtlas].Fmt([ProductName(ASettings.DelphiVersion),
      ASettings.DelphiVersion, ProductName(Fallback)]);
  end;
  Result := [Issue];
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Projects.DelphiVersions', cTexts);

end.
