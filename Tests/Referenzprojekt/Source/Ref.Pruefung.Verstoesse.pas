unit Ref.Pruefung.Verstoesse;

// Bewusst eingebaute Regelverstöße. Jede Zeile mit "// ERWARTET: <regel>"
// muss genau diesen Treffer liefern, Zeilen mit "// KEIN-TREFFER: <regel>"
// dürfen ihn nicht liefern. Siehe README.md.

interface

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  FireDAC.Comp.Client;

type
  TPunkt = record
    X, Y: Integer;
  end;

function OhneErgebnis(AWert: Integer): Integer;
procedure MitWith(var APunkt: TPunkt);
procedure UngenutzteVariable;
procedure Leck;
procedure KeinLeck;
procedure LeererExceptBlock;
procedure Unerreichbar;
procedure SqlVerkettet(AAbfrage: TFDQuery; const AName: string);
procedure SqlMitParameter(AAbfrage: TFDQuery; const AName: string);

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
  except // ERWARTET: empty-except
  end;
end;

procedure Unerreichbar;
begin
  Exit;
  Abort; // ERWARTET: unreachable-code
end;

procedure SqlVerkettet(AAbfrage: TFDQuery; const AName: string);
begin
  AAbfrage.SQL.Text := 'SELECT * FROM Kunden WHERE Name = ''' + AName + ''''; // ERWARTET: security-sql-injection
  AAbfrage.Open;
end;

procedure SqlMitParameter(AAbfrage: TFDQuery; const AName: string);
begin
  AAbfrage.SQL.Text := 'SELECT * FROM Kunden WHERE Name = :Name'; // KEIN-TREFFER: security-sql-injection
  AAbfrage.ParamByName('Name').AsString := AName;
  AAbfrage.Open;
end;

end.
