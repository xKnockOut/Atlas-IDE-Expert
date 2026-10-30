library CmE2287b;

// E2287 Cannot export '%s' multiple times
// Erwartet: E2287
// Vermutung (#1383): Denselben Eintrag zweimal ohne name übersetzt Delphi 13 (CmE2287); derselbe Exportname
// über name für zwei Routinen nicht.

procedure Erste; stdcall;
begin
end;

procedure Zweite; stdcall;
begin
end;

exports
  Erste name 'Start',
  Zweite name 'Start'; // <- E2287

begin
end.
