{$WARN TYPEINFO_IMPLICITLY_ADDED ON}
unit Cm.W1055;

// W1055 PUBLISHED caused RTTI ($M+) to be added to type
// Erwartet: W1055

interface

type
  TOhneRtti = class
  published
    procedure Machen; // <- W1055
  end;

implementation

procedure TOhneRtti.Machen;
begin
end;

end.
