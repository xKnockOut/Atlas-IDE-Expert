unit Ref.Pruefung.Verstoesse;

// Bewusst eingebaute Regelverstöße. Jede Zeile mit "// ERWARTET: <regel>"
// muss genau diesen Treffer liefern, Zeilen mit "// KEIN-TREFFER: <regel>"
// dürfen ihn nicht liefern. Siehe README.md. Die Verstöße mit FireDAC stehen
// in Ref.Pruefung.Datenbank (nur im optionalen Projekt RefDaten).
//
// Einige Verstöße erzeugen beim Übersetzen gewollt Hinweise oder Warnungen;
// die Liste steht in erwartete-meldungen.txt.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TPunkt = record
    X, Y: Integer;
  end;

function OhneErgebnis(AWert: Integer): Integer; // ERWARTET-PROJEKT: unused-public-member
procedure MitWith(var APunkt: TPunkt); // ERWARTET-PROJEKT: unused-public-member
procedure UngenutzteVariable; // ERWARTET-PROJEKT: unused-public-member
procedure Leck; // ERWARTET-PROJEKT: unused-public-member
procedure KeinLeck; // ERWARTET-PROJEKT: unused-public-member
procedure LeererExceptBlock; // ERWARTET-PROJEKT: unused-public-member
procedure Unerreichbar; // ERWARTET-PROJEKT: unused-public-member

implementation

function OhneErgebnis(AWert: Integer): Integer; // ERWARTET: result-not-set
begin
  if AWert > 0 then
    Result := AWert;
end;

procedure MitWith(var APunkt: TPunkt);
begin
  with APunkt do // ERWARTET: with-statement
    X := Y;
end;

procedure UngenutzteVariable;
var
  Unbenutzt: Integer; // ERWARTET: unused-local
  Benutzt: Integer; // KEIN-TREFFER: unused-local
begin
  Benutzt := 1;
  if Benutzt > 0 then
    Exit;
end;

procedure Leck;
var
  Liste: TStringList;
begin
  Liste := TStringList.Create; // ERWARTET: possible-leak
  Liste.Add('x');
end;

procedure KeinLeck;
var
  Liste: TStringList;
begin
  Liste := TStringList.Create; // KEIN-TREFFER: possible-leak
  try
    Liste.Add('x');
  finally
    Liste.Free;
  end;
end;

procedure LeererExceptBlock;
begin
  try
    Abort;
  except end; // ERWARTET: empty-except
end;

procedure Unerreichbar;
begin
  Exit;
  Abort; // ERWARTET: unreachable-code
end;

function RueckwaertsSummieren(const AWerte: TArray<Integer>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := High(AWerte) to Low(AWerte) do // ERWARTET: for-high-to-low
    Inc(Result, AWerte[I]);
end;

procedure NameUebernehmen(var AName: string);
begin
  AName := AName; // ERWARTET: self-assignment
end;

end.
