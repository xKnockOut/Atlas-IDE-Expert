unit Atlas.Linux.Documents.PathCanonicalizer;

// Platform-Feature "Documents" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Documents.PathCanonicalizer. Kanonisch ist unter Linux der Pfad
// ohne symbolische Verweise, "." und ".." (realpath der C-Laufzeit). Groß- und
// Kleinschreibung bleibt, wie sie ist: Linux unterscheidet sie.

interface

uses
  System.SysUtils;

type
  TLinuxPathCanonicalizer = class
  public
    /// <summary>Pfad ohne symbolische Verweise; unverändert, wenn es ihn nicht gibt.</summary>
    class function Canonicalize(const APath: string): string; static;
  end;

implementation

const
  cPathMax = 4096;

function realpath(APath, AResolved: PAnsiChar): PAnsiChar; cdecl; external 'c' name 'realpath';

class function TLinuxPathCanonicalizer.Canonicalize(const APath: string): string;
var
  mSource: UTF8String;
  mBuffer: array[0..cPathMax] of AnsiChar;
begin
  Result := APath;
  if APath = '' then
  begin
    Exit;
  end;
  mSource := UTF8String(APath);
  if realpath(PAnsiChar(mSource), @mBuffer[0]) = nil then
  begin
    Exit;
  end;
  Result := string(UTF8String(PAnsiChar(@mBuffer[0])));
end;

end.
