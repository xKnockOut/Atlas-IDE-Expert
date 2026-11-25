unit Atlas.Common.Compiler.Releases;

// Release-Namen der Delphi-Versionen (BDS-Version wie "23.0" aus atlas.json → "Athens"), etwa für Links in die
// DocWiki (Hover #27, Compilermeldungen #54). Ohne oder mit unbekannter Version gilt die neueste bekannte.

interface

type
  TDelphiReleases = record
    /// <summary>Release-Name zu ADelphiVersion, z. B. "Athens" für 23.0; Leerzeichen zählen nicht.</summary>
    class function Name(const ADelphiVersion: string): string; static;
  end;

implementation

uses
  System.SysUtils;

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

{ TDelphiReleases }

class function TDelphiReleases.Name(const ADelphiVersion: string): string;
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

end.
