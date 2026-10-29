unit Cm.W1001;

// W1001 Symbol is specific to a library
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt W1001.

interface

implementation

procedure Alt; library;
begin
end;

procedure Benutze;
begin
  Alt; // <- E2029
end;

end.
