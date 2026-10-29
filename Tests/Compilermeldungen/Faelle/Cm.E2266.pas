unit Cm.E2266;

// E2266 Only one of a set of overloaded methods can be published
// Erwartet: E2266

interface

type
  TKlasse = class
  published
    procedure Machen(AWert: Integer); overload;
    procedure Machen(const AText: string); overload; // <- E2266
  end;

implementation

procedure TKlasse.Machen(AWert: Integer);
begin
end;

procedure TKlasse.Machen(const AText: string);
begin
end;

end.
