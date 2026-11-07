unit Atlas.Common.Lsp.DocWiki;

// Links zur Embarcadero DocWiki für RTL- und VCL-Symbole im Hover (#27).
// Schema: https://docwiki.embarcadero.com/Libraries/<Release>/en/<Unit>.<Typ>.<Name>
// Der Release-Name folgt der Delphi-Version aus atlas.json (BDS-Version
// wie "23.0"); ohne Angabe gilt die neueste bekannte.

interface

uses
  System.SysUtils;

type
  TDocWiki = class
  public const
    cBaseUri = 'https://docwiki.embarcadero.com/Libraries/';
  public
    /// <summary>Release-Name der DocWiki, z. B. "Athens" für 23.0.</summary>
    class function ReleaseName(const ADelphiVersion: string): string; static;
    /// <summary>True für Units aus RTL, VCL und den mitgelieferten Bibliotheken.</summary>
    class function IsLibraryUnit(const AUnitName: string): Boolean; static;
    /// <summary>Link für Unit, Container (Typ, darf leer sein) und Name (leer = die Unit selbst); '' für fremde
    /// Units.</summary>
    class function Url(const ADelphiVersion, AUnitName, AContainer, AName: string): string; static;
  end;

implementation

uses
  Atlas.Common.Index.LibraryUnits;

type
  TRelease = record
    Version: string;
    Name: string;
  end;

const
  cReleases: array[0..10] of TRelease = (
    (Version: '14.0'; Name: 'XE6'), (Version: '15.0'; Name: 'XE7'), (Version: '16.0'; Name: 'XE8'),
    (Version: '17.0'; Name: 'Seattle'), (Version: '18.0'; Name: 'Berlin'), (Version: '19.0'; Name: 'Tokyo'),
    (Version: '20.0'; Name: 'Rio'), (Version: '21.0'; Name: 'Sydney'), (Version: '22.0'; Name: 'Alexandria'),
    (Version: '23.0'; Name: 'Athens'), (Version: '37.0'; Name: 'Florence'));


class function TDocWiki.ReleaseName(const ADelphiVersion: string): string;
var
  mRelease: TRelease;
begin
  for mRelease in cReleases do
  begin
    if SameText(mRelease.Version, Trim(ADelphiVersion)) then
    begin
      Exit(mRelease.Name);
    end;
  end;
  Result := cReleases[High(cReleases)].Name;
end;

class function TDocWiki.IsLibraryUnit(const AUnitName: string): Boolean;
begin
  Result := TLibraryUnits.IsLibraryUnit(AUnitName);
end;

class function TDocWiki.Url(const ADelphiVersion, AUnitName, AContainer, AName: string): string;
begin
  if not IsLibraryUnit(AUnitName) then
  begin
    Exit('');
  end;
  Result := cBaseUri + ReleaseName(ADelphiVersion) + '/en/' + AUnitName;
  if AContainer <> '' then
  begin
    Result := Result + '.' + AContainer;
  end;
  if AName <> '' then
  begin
    Result := Result + '.' + AName;
  end;
end;

end.
