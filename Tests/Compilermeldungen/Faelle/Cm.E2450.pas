unit Cm.E2450;

// E2450 There is no overloaded version of array property '%s' that can be used with these arguments
// Erwartet: E2450

interface

type
  TListe = class
  private
    function GetEintrag(AIndex: Integer): string;
  public
    property Eintrag[AIndex: Integer]: string read GetEintrag; default;
  end;

implementation

function TListe.GetEintrag(AIndex: Integer): string;
begin
  Result := '';
end;

function Fall(AListe: TListe): string;
begin
  Result := AListe['a']; // <- E2450
end;

end.
