unit Cm.E2530;

// E2530 Type parameters not allowed on global procedure or function
// Erwartet: E2530

interface

implementation

procedure Fall<T>(AWert: T); // <- E2530
begin
end;

end.
