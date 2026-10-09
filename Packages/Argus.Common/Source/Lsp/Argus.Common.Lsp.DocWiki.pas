unit Argus.Common.Lsp.DocWiki;

// Links zur Embarcadero DocWiki für RTL- und VCL-Symbole im Hover (#27).
// Schema: https://docwiki.embarcadero.com/Libraries/<Release>/en/<Unit>.<Typ>.<Name>
// Der Release-Name folgt der Delphi-Version aus argus.json (BDS-Version
// wie "23.0"); ohne Angabe gilt die neueste bekannte.

interface

uses
  System.SysUtils;

type
  TDocWiki = class
  public const
    BaseUri = 'https://docwiki.embarcadero.com/Libraries/';
  public
    /// <summary>Release-Name der DocWiki, z. B. "Athens" für 23.0.</summary>
    class function ReleaseName(const ADelphiVersion: string): string; static;
    /// <summary>True für Units aus RTL, VCL und den mitgelieferten Bibliotheken.</summary>
    class function IsLibraryUnit(const AUnitName: string): Boolean; static;
    /// <summary>Link für Unit, Container (Typ, darf leer sein) und Name (leer = die Unit selbst); '' für fremde Units.</summary>
    class function Url(const ADelphiVersion, AUnitName, AContainer, AName: string): string; static;
  end;

implementation

uses
  System.StrUtils;

type
  TRelease = record
    Version: string;
    Name: string;
  end;

const
  Releases: array[0..10] of TRelease = (
    (Version: '14.0'; Name: 'XE6'), (Version: '15.0'; Name: 'XE7'), (Version: '16.0'; Name: 'XE8'),
    (Version: '17.0'; Name: 'Seattle'), (Version: '18.0'; Name: 'Berlin'), (Version: '19.0'; Name: 'Tokyo'),
    (Version: '20.0'; Name: 'Rio'), (Version: '21.0'; Name: 'Sydney'), (Version: '22.0'; Name: 'Alexandria'),
    (Version: '23.0'; Name: 'Athens'), (Version: '37.0'; Name: 'Florence'));

  LibraryPrefixes: array[0..11] of string = ('System', 'Vcl', 'Winapi', 'Data', 'Xml', 'Soap', 'Datasnap',
    'FireDAC', 'REST', 'Web', 'IBX', 'FMX');

class function TDocWiki.ReleaseName(const ADelphiVersion: string): string;
var
  Release: TRelease;
begin
  for Release in Releases do
    if SameText(Release.Version, Trim(ADelphiVersion)) then
      Exit(Release.Name);
  Result := Releases[High(Releases)].Name;
end;

class function TDocWiki.IsLibraryUnit(const AUnitName: string): Boolean;
var
  Prefix: string;
begin
  for Prefix in LibraryPrefixes do
    if SameText(AUnitName, Prefix) or StartsText(Prefix + '.', AUnitName) then
      Exit(True);
  Result := False;
end;

class function TDocWiki.Url(const ADelphiVersion, AUnitName, AContainer, AName: string): string;
begin
  if not IsLibraryUnit(AUnitName) then
    Exit('');
  Result := BaseUri + ReleaseName(ADelphiVersion) + '/en/' + AUnitName;
  if AContainer <> '' then
    Result := Result + '.' + AContainer;
  if AName <> '' then
    Result := Result + '.' + AName;
end;

end.
