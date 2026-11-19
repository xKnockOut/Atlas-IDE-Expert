unit Atlas.Text.Csv;

// CSV mit Semikolon als Trenner (gemeinsam für Server und Plugin, z. B. die
// Ausgabe von Abfragen): Ein Feld mit Trenner, Anführungszeichen oder
// Zeilenumbruch steht in Anführungszeichen, innere Anführungszeichen doppelt.

interface

type
  TTextCsv = class
  public
    /// <summary>AText als Feld einer CSV-Zeile mit Semikolon als Trenner.</summary>
    class function Cell(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TTextCsv }

class function TTextCsv.Cell(const AText: string): string;
begin
  if (Pos(';', AText) > 0) or (Pos('"', AText) > 0) or (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0) then
  begin
    Result := '"' + StringReplace(AText, '"', '""', [rfReplaceAll]) + '"';
  end
  else
  begin
    Result := AText;
  end;
end;

end.
