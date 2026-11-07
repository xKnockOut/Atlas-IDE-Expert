unit Atlas.Core.Ci.Internals.Addresses;

// Adressen beim Abruf vom Build-Server (#763), ohne Netz und daher testbar:
// wohin Atlas einer Weiterleitung folgt und wann Benutzer und Token mitgehen.
// - Weiterleitung nur auf denselben Rechner; http → https ist erlaubt
//   (Jenkins hinter einem Proxy), alles andere nicht (das Token soll nie an
//   einen anderen Server gehen, z. B. an eine fremde Anmeldeseite).
// - Anmeldung nur über https und nur beim eingetragenen Server.

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract;

type
  TAtlasCiAddresses = class
  public
    /// <summary>Schema, Rechner und Port in Kleinbuchstaben; '' bei ungültiger Adresse.</summary>
    class function OriginOf(const AUrl: string): string; static;
    /// <summary>Rechner ohne Schema und Port.</summary>
    class function HostOf(const AOrigin: string): string; static;
    class function RedirectAllowed(const AFrom, ATo: string): Boolean; static;
    /// <summary>Ziel einer Weiterleitung; relative Angaben ("/job/…") gegen AFrom, sonst unverändert.</summary>
    class function Resolve(const AFrom, ALocation: string): string; static;
    /// <summary>Benutzer und Token dürfen an AUrl gehen: https und Server gleich AServer.</summary>
    class function MayAuthenticate(const AUrl, AServer: string): Boolean; static;
  end;

implementation

class function TAtlasCiAddresses.OriginOf(const AUrl: string): string;
begin
  Result := TAtlasCiJob.Create('', AUrl, '', False, '').Server;
end;

class function TAtlasCiAddresses.HostOf(const AOrigin: string): string;
var
  mIndex: Integer;
begin
  Result := AOrigin;
  mIndex := Pos('://', Result);
  if mIndex > 0 then
  begin
    Result := Copy(Result, mIndex + 3, MaxInt);
  end;
  mIndex := Pos(':', Result);
  if mIndex > 0 then
  begin
    Result := Copy(Result, 1, mIndex - 1);
  end;
end;

class function TAtlasCiAddresses.RedirectAllowed(const AFrom, ATo: string): Boolean;
var
  mFromOrigin, mToOrigin: string;
begin
  mFromOrigin := OriginOf(AFrom);
  mToOrigin := OriginOf(ATo);
  if (mFromOrigin = '') or (mToOrigin = '') then
  begin
    Exit(False);
  end;
  if mFromOrigin = mToOrigin then
  begin
    Exit(True);
  end;
  Result := mFromOrigin.StartsWith('http://') and mToOrigin.StartsWith('https://') and
    SameText(HostOf(mFromOrigin), HostOf(mToOrigin));
end;

class function TAtlasCiAddresses.Resolve(const AFrom, ALocation: string): string;
begin
  Result := Trim(ALocation);
  if Result.StartsWith('/') and not Result.StartsWith('//') then
  begin
    Result := OriginOf(AFrom) + Result;
  end;
end;

class function TAtlasCiAddresses.MayAuthenticate(const AUrl, AServer: string): Boolean;
var
  mOrigin: string;
begin
  mOrigin := OriginOf(AUrl);
  Result := (mOrigin <> '') and mOrigin.StartsWith('https://') and SameText(mOrigin, AServer);
end;

end.
