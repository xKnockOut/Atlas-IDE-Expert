unit Cm.E2131;

// E2131 Class already has a default property
// Erwartet: E2131
// Zwei Default-Properties mit verschiedenen Namen.

interface

type
  TListe = class
  private
    function GetA(AIndex: Integer): string;
    function GetB(AIndex: string): string;
  public
    property A[AIndex: Integer]: string read GetA; default;
    property B[AIndex: string]: string read GetB; default; // <- E2131
  end;

implementation

function TListe.GetA(AIndex: Integer): string;
begin
  Result := '';
end;

function TListe.GetB(AIndex: string): string;
begin
  Result := '';
end;

end.
