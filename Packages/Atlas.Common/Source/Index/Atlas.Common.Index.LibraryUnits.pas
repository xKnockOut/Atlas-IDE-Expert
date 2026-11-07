unit Atlas.Common.Index.LibraryUnits;

// Erkennt Units aus RTL, VCL, FMX und den mitgelieferten Bibliotheken am
// Namen (System, Vcl, Winapi, Data, FireDAC …). Gemeinsam für die Links zur
// DocWiki (#27), die semantische Hervorhebung (defaultLibrary) und die
// Vererbungstiefe ohne Bibliotheksklassen (metric-inheritance-depth, #980).
// IsLibrary nimmt zusätzlich die Markierung Library_ des Index dazu: Units,
// die nur über eine uses-Liste aus dem Bibliothekspfad nachgeladen wurden.

interface

uses
  Atlas.Common.Index.Contract;

type
  TLibraryUnits = class
  public
    /// <summary>True für Units aus RTL, VCL, FMX und den mitgelieferten Bibliotheken, z. B. System.SysUtils,
    /// Vcl.Forms oder der Namensraum Vcl selbst.</summary>
    class function IsLibraryUnit(const AUnitName: string): Boolean; static;
    /// <summary>IsLibraryUnit oder im Index als nachgeladene Bibliotheks-Unit (Library_) eingetragen; AIndex darf
    /// nil sein.</summary>
    class function IsLibrary(const AIndex: ISymbolIndex; const AUnitName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  cLibraryPrefixes: array[0..15] of string = ('System', 'Vcl', 'Winapi', 'Data', 'Xml', 'Soap', 'Datasnap',
    'FireDAC', 'REST', 'Web', 'IBX', 'FMX', 'Posix', 'Macapi', 'Androidapi', 'iOSapi');

class function TLibraryUnits.IsLibraryUnit(const AUnitName: string): Boolean;
var
  mPrefix: string;
begin
  for mPrefix in cLibraryPrefixes do
  begin
    if SameText(AUnitName, mPrefix) or StartsText(mPrefix + '.', AUnitName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TLibraryUnits.IsLibrary(const AIndex: ISymbolIndex; const AUnitName: string): Boolean;
var
  mFound: TUnitIndex;
begin
  Result := IsLibraryUnit(AUnitName);
  if not Result and (AIndex <> nil) and (AUnitName <> '') and AIndex.FindUnit(AUnitName, mFound) then
  begin
    Result := mFound.Library_;
  end;
end;

end.
