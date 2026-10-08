unit Ref.Komponenten.Registrierung;

interface

procedure Register;

implementation

uses
  System.Classes,
  Ref.Komponenten.Anzeige;

procedure Register;
begin
  RegisterComponents('Referenz', [TRefAnzeige]);
end;

end.
