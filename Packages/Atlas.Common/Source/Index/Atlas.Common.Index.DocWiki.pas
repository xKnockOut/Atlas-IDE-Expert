unit Atlas.Common.Index.DocWiki;

// Links zur Embarcadero DocWiki für RTL- und VCL-Symbole im Hover (#27).
// Schema: https://docwiki.embarcadero.com/Libraries/<Release>/en/<Unit>.<Typ>.<Name>
// Der Release-Name folgt der Delphi-Version aus atlas.json (TDelphiReleases).

interface

type
  TDocWiki = class
  public const
    cBaseUri = 'https://docwiki.embarcadero.com/Libraries/';
  public
    /// <summary>True für Units aus RTL, VCL und den mitgelieferten Bibliotheken.</summary>
    class function IsLibraryUnit(const AUnitName: string): Boolean; static;
    /// <summary>Link für Unit, Container (Typ, darf leer sein) und Name (leer = die Unit selbst); '' für fremde
    /// Units.</summary>
    class function Url(const ADelphiVersion, AUnitName, AContainer, AName: string): string; static;
  end;

implementation

uses
  Atlas.Common.Index.LibraryUnits,
  Atlas.Common.Compiler.Releases;

{ TDocWiki }

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
  Result := cBaseUri + TDelphiReleases.Name(ADelphiVersion) + '/en/' + AUnitName;
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
