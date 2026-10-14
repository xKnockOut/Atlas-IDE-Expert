unit Ref.Pruefung.Datenbank;

// Bewusst eingebaute Regelverstöße mit FireDAC, nur im optionalen Projekt
// RefDaten (#94). Markierung wie in Ref.Pruefung.Verstoesse, siehe README.md.

interface

uses
  FireDAC.Comp.Client;

procedure SqlVerkettet(AAbfrage: TFDQuery; const AName: string);
procedure SqlMitParameter(AAbfrage: TFDQuery; const AName: string);

implementation

uses
  FireDAC.Stan.Param;

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
