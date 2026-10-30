unit Cm.E2373b;

// E2373 Call to abstract method %s.%s
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: inherited ohne Methodennamen (Cm.E2373
// mit Namen bleibt still).

interface

type
  TBasis = class
  public
    procedure Machen; virtual; abstract;
  end;

  TKind = class(TBasis)
  public
    procedure Machen; override;
  end;

implementation

procedure TKind.Machen;
begin
  inherited; // <- ohne Meldung
end;

end.
