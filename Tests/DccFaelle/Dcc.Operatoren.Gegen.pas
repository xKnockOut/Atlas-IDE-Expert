unit Dcc.Operatoren.Gegen;

// #1328, Gegentests zu operator-declaration-invalid: Hier soll dcc melden.

interface

type
  TFeld = record
    Name: string;
    class operator Equal(const ALinks: TFeld): Boolean; // OG1: ein Parameter statt zwei
    class operator Negative(const ALinks, ARechts: TFeld): TFeld; // OG2: zwei Parameter statt einem
  end;

implementation

class operator TFeld.Equal(const ALinks: TFeld): Boolean;
begin
  Result := ALinks.Name = '';
end;

class operator TFeld.Negative(const ALinks, ARechts: TFeld): TFeld;
begin
  Result := ALinks;
end;

end.
