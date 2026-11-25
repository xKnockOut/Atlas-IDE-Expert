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
    /// <summary>Anzahl mit Wort: „1 Wert“ mit AOne, sonst „3 Werte“ mit AMany.</summary>
    class function Counted(ACount: Int64; const AOne, AMany: string): string; static;
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

class function TTextNumbers.Counted(ACount: Int64; const AOne, AMany: string): string;
begin
  if ACount = 1 then
  begin
    Result := '1 ' + AOne;
  end
  else
  begin
    Result := IntToStr(ACount) + ' ' + AMany;
  end;
end;

end.
