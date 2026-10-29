unit Cm.W1075;

// W1075 Overloading a similar index type by declaring an array property
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

type
  TListe = class
  private
    function GetNachZahl(AIndex: Integer): string;
    function GetNachByte(AIndex: Byte): string;
  public
    property Eintrag[AIndex: Integer]: string read GetNachZahl; default;
    property Eintrag[AIndex: Byte]: string read GetNachByte; default; // <- ohne Meldung
  end;

implementation

function TListe.GetNachZahl(AIndex: Integer): string;
begin
  Result := '';
end;

function TListe.GetNachByte(AIndex: Byte): string;
begin
  Result := '';
end;

end.
