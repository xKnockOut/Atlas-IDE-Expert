unit Atlas.Core.Modules.Handshake;

// Versions-Handschlag zwischen Base und Modul (#1455, Regel 7): Base
// exportiert AtlasCoreContractVersion unter festem Namen. Ein Modul fragt sie
// als Erstes in seinem Register über GetProcAddress ab, nicht über einen
// Import: Passt die Binärschnittstelle nicht, liefe ein Aufruf über die
// Methodentabellen ins Leere (Delphi prüft das zwischen Packages nicht). Bei
// Abweichung meldet sich das Modul nicht an und zeigt seinen Hinweis
// „Atlas-Kern passt nicht zu diesem Modul“ (Text im Modul, ADR 0017
// Entscheidung 4).

interface

uses
  Winapi.Windows,
  Atlas.Core.Modules.Contract;

type
  /// <summary>Ergebnis: passt, Base ohne Export (nicht geladen oder kein Atlas-Base), andere Vertragsversion.</summary>
  TAtlasContractCheck = (ccMatch, ccMissing, ccMismatch);

  TAtlasContractVersionFunction = function: Integer; stdcall;

  TAtlasContractHandshake = class
  public
    /// <summary>Ergebnis für eine gefundene (AFound) Version AVersion gegen die erwartete AExpected.</summary>
    class function Compare(AFound: Boolean; AVersion, AExpected: Integer): TAtlasContractCheck; static;
    /// <summary>Vertragsversion des Moduls AModule über GetProcAddress; False ohne Export.</summary>
    class function Query(AModule: HMODULE; out AVersion: Integer): Boolean; static;
    /// <summary>Query und Compare in einem: AModule gegen AExpected (das Modul übergibt die
    /// cAtlasCoreContractVersion, gegen die es übersetzt wurde).</summary>
    class function Check(AModule: HMODULE; AExpected: Integer): TAtlasContractCheck; static;
  end;

/// <summary>Vertragsversion dieses Base (cAtlasCoreContractVersion); exportiert unter
/// cAtlasCoreContractExport.</summary>
function AtlasCoreContractVersion: Integer; stdcall;

implementation

function AtlasCoreContractVersion: Integer; stdcall;
begin
  Result := cAtlasCoreContractVersion;
end;

// Unter festem Namen, nicht nur mit dem verzierten Namen des Packages: Ein Modul findet ihn mit GetProcAddress.
exports
  AtlasCoreContractVersion name cAtlasCoreContractExport;

{ TAtlasContractHandshake }

class function TAtlasContractHandshake.Compare(AFound: Boolean; AVersion, AExpected: Integer): TAtlasContractCheck;
begin
  if not AFound then
  begin
    Result := ccMissing;
  end
  else if AVersion <> AExpected then
  begin
    Result := ccMismatch;
  end
  else
  begin
    Result := ccMatch;
  end;
end;

class function TAtlasContractHandshake.Query(AModule: HMODULE; out AVersion: Integer): Boolean;
var
  mFunction: TAtlasContractVersionFunction;
begin
  AVersion := 0;
  Result := False;
  if AModule = 0 then
  begin
    Exit;
  end;
  @mFunction := GetProcAddress(AModule, PAnsiChar(cAtlasCoreContractExport));
  Result := Assigned(mFunction);
  if Result then
  begin
    AVersion := mFunction();
  end;
end;

class function TAtlasContractHandshake.Check(AModule: HMODULE; AExpected: Integer): TAtlasContractCheck;
var
  mVersion: Integer;
  mFound: Boolean;
begin
  mFound := Query(AModule, mVersion);
  Result := Compare(mFound, mVersion, AExpected);
end;

end.
