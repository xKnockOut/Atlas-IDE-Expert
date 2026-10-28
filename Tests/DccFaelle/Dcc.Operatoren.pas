unit Dcc.Operatoren;

// #1328, Regel operator-declaration-invalid (E2520): Vergleichsoperatoren, die
// kein Boolean liefern (Spring4D Persistence.Criteria).

interface

type
  TAusdruck = record
    Text: string;
  end;

  TFeld = record
    Name: string;
    class operator Equal(const ALinks, ARechts: TFeld): TAusdruck; overload; // OP1
    class operator Equal(const ALinks: TFeld; const ARechts: Variant): TAusdruck; overload; // OP2
    class operator NotEqual(const ALinks, ARechts: TFeld): TAusdruck; // OP3
    class operator LessThan(const ALinks, ARechts: TFeld): Integer; // OP4
  end;

function Vergleiche(const ALinks, ARechts: TFeld): TAusdruck;

implementation

class operator TFeld.Equal(const ALinks, ARechts: TFeld): TAusdruck;
begin
  Result.Text := ALinks.Name + '=' + ARechts.Name;
end;

class operator TFeld.Equal(const ALinks: TFeld; const ARechts: Variant): TAusdruck;
begin
  Result.Text := ALinks.Name + '=?';
end;

class operator TFeld.NotEqual(const ALinks, ARechts: TFeld): TAusdruck;
begin
  Result.Text := ALinks.Name + '<>' + ARechts.Name;
end;

class operator TFeld.LessThan(const ALinks, ARechts: TFeld): Integer;
begin
  Result := Length(ALinks.Name) - Length(ARechts.Name);
end;

function Vergleiche(const ALinks, ARechts: TFeld): TAusdruck;
begin
  Result := ALinks = ARechts; // OP5: Benutzung
end;

end.
