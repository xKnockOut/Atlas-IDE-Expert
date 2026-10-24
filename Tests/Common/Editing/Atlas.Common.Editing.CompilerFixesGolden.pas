unit Atlas.Common.Editing.CompilerFixesGolden;

// Golden-Datei für die Schnellkorrekturen an Compilermeldungen, Teil 2
// (#549): genau das, was die Korrekturen aus dem Vorher-Text in
// Atlas.Common.Editing.CompilerFixes.Tests erzeugen. Der Delphi-Testlauf
// zeigt, dass das Ergebnis ohne Warnung und Hinweis übersetzt. Nicht von
// Hand ändern, sondern neu erzeugen.

interface

uses
  System.JSON;

function Anzahl(AListe: TJSONArray): Integer;
function Zeilen(const AText: string): Integer;
function Erster(const AText: string): Integer;
function Doppelt(const AText: string): Integer;
function Breit(const AText: AnsiString): string;
function Schmal(const AText: string): AnsiString;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

function Anzahl(AListe: TJSONArray): Integer;
begin
  Result := AListe.Count;
end;

function Zeilen(const AText: string): Integer;
var
  Liste: TStringList;
begin
  Liste := TStringList.Create;
  try
    Liste.Text := AText;
    Result := Liste.Count;
  finally
    Liste.Free;
  end;
end;

function Erster(const AText: string): Integer;
begin
  Result := Default(Integer);
  if AText <> '' then
    Result := Ord(AText[1]);
end;

function Doppelt(const AText: string): Integer;
var
  Wert: Integer;
begin
  Zeilen(AText);
  Wert := 2;
  Result := Wert * 2;
end;

function Breit(const AText: AnsiString): string;
begin
  Result := string(AText);
end;

function Schmal(const AText: string): AnsiString;
begin
  Result := AnsiString(AText);
end;

end.
