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
  Atlas.Core.Ci.Contract;

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
  Index: Integer;
begin
  Result := AOrigin;
  Index := Pos('://', Result);
  if Index > 0 then
    Result := Copy(Result, Index + 3, MaxInt);
  Index := Pos(':', Result);
  if Index > 0 then
    Result := Copy(Result, 1, Index - 1);
end;

class function TAtlasCiAddresses.RedirectAllowed(const AFrom, ATo: string): Boolean;
var
  FromOrigin, ToOrigin: string;
begin
  FromOrigin := OriginOf(AFrom);
  ToOrigin := OriginOf(ATo);
  if (FromOrigin = '') or (ToOrigin = '') then
    Exit(False);
  if FromOrigin = ToOrigin then
    Exit(True);
  Result := FromOrigin.StartsWith('http://') and ToOrigin.StartsWith('https://') and
    SameText(HostOf(FromOrigin), HostOf(ToOrigin));
end;

class function TAtlasCiAddresses.Resolve(const AFrom, ALocation: string): string;
begin
  Result := Trim(ALocation);
  if Result.StartsWith('/') and not Result.StartsWith('//') then
    Result := OriginOf(AFrom) + Result;
end;

class function TAtlasCiAddresses.MayAuthenticate(const AUrl, AServer: string): Boolean;
var
  Origin: string;
begin
  Origin := OriginOf(AUrl);
  Result := (Origin <> '') and Origin.StartsWith('https://') and SameText(Origin, AServer);
end;

end.
