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
  LibraryPrefixes: array[0..15] of string = ('System', 'Vcl', 'Winapi', 'Data', 'Xml', 'Soap', 'Datasnap',
    'FireDAC', 'REST', 'Web', 'IBX', 'FMX', 'Posix', 'Macapi', 'Androidapi', 'iOSapi');

class function TLibraryUnits.IsLibraryUnit(const AUnitName: string): Boolean;
var
  Prefix: string;
begin
  for Prefix in LibraryPrefixes do
    if SameText(AUnitName, Prefix) or StartsText(Prefix + '.', AUnitName) then
      Exit(True);
  Result := False;
end;

class function TLibraryUnits.IsLibrary(const AIndex: ISymbolIndex; const AUnitName: string): Boolean;
var
  Found: TUnitIndex;
begin
  Result := IsLibraryUnit(AUnitName);
  if not Result and (AIndex <> nil) and (AUnitName <> '') and AIndex.FindUnit(AUnitName, Found) then
    Result := Found.Library_;
end;

end.
