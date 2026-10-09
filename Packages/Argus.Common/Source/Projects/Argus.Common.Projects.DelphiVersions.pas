unit Argus.Common.Projects.DelphiVersions;

// Auswahl der Delphi-Version je Projekt (#47).
//
// Reihenfolge: "delphiVersion" aus der Konfiguration, sonst die zur
// <ProjectVersion> der .dproj passende Installation, sonst die neueste.
// Die Zuordnung ProjectVersion -> BDS-Version ist eine Näherung: Die IDE
// schreibt beim Speichern ihre eigene ProjectVersion, Zwischenstände einer
// Hauptversion liegen in einem Bereich.

interface

uses
  System.SysUtils;

type
  TDelphiVersions = record
  public
    /// <summary>Inhalt von &lt;ProjectVersion&gt; einer .dproj; '' wenn nicht vorhanden.</summary>
    class function ProjectVersionOf(const ADprojText: string): string; static;
    /// <summary>BDS-Version (z. B. "22.0") für eine ProjectVersion (z. B. "19.5"); '' wenn unbekannt.</summary>
    class function BdsForProjectVersion(const AProjectVersion: string): string; static;
    /// <summary>Produktname, z. B. "Delphi 12" für "23.0"; sonst "BDS 23.0".</summary>
    class function ProductName(const ABdsVersion: string): string; static;
    /// <summary>Zu verwendende Version aus den installierten (aufsteigend sortiert).
    /// Konfigurierte Version gewinnt immer, auch wenn sie nicht installiert ist.
    /// Sonst die passende, sonst die nächsthöhere, sonst die neueste Installation.</summary>
    class function Choose(const AConfigured, AProjectVersion: string;
      const AInstalled: TArray<string>): string; static;
  end;

implementation

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
    Exit;
  Inc(Start, Length('<ProjectVersion>'));
  Stop := Pos('</ProjectVersion>', ADprojText);
  if Stop > Start then
    Result := Trim(Copy(ADprojText, Start, Stop - Start));
end;

class function TDelphiVersions.BdsForProjectVersion(const AProjectVersion: string): string;
var
  Value: Double;
  Index: Integer;
begin
  Result := '';
  Value := ToNumber(AProjectVersion);
  if Value < Ranges[0].FromProject then
    Exit;
  for Index := 0 to High(Ranges) - 1 do
    if (Value >= Ranges[Index].FromProject) and (Value < Ranges[Index + 1].FromProject) then
      Exit(Ranges[Index].Bds);
end;

class function TDelphiVersions.ProductName(const ABdsVersion: string): string;
var
  Range: TVersionRange;
begin
  for Range in Ranges do
    if (Range.Bds <> '') and (ToNumber(Range.Bds) = ToNumber(ABdsVersion)) then
      Exit(Range.Name);
  Result := 'BDS ' + ABdsVersion;
end;

class function TDelphiVersions.Choose(const AConfigured, AProjectVersion: string;
  const AInstalled: TArray<string>): string;
var
  Wanted: string;
  Version: string;
begin
  if AConfigured <> '' then
    Exit(AConfigured);
  if Length(AInstalled) = 0 then
    Exit('');
  Wanted := BdsForProjectVersion(AProjectVersion);
  if Wanted <> '' then
    for Version in AInstalled do
      if ToNumber(Version) >= ToNumber(Wanted) then
        Exit(Version);
  Result := AInstalled[High(AInstalled)];
end;

end.
