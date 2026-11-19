unit Atlas.Text.Numbers;

// Zahlen als Text für Anzeigen in Server und Plugin.

interface

uses
  System.SysUtils;

type
  TTextNumbers = class
  public
    /// <summary>AValue mit Vorzeichen: „+3“, „0“, „-2“ (Änderungen, Abstände).</summary>
    class function Signed(AValue: Integer): string; static;
  end;

implementation

{ TTextNumbers }

class function TTextNumbers.Signed(AValue: Integer): string;
begin
  Result := IntToStr(AValue);
  if AValue > 0 then
  begin
    Result := '+' + Result;
  end;
end;

end.
