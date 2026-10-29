unit Cm.E2373;

// E2373 Call to abstract method %s.%s
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

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
  inherited Machen; // <- ohne Meldung
end;

end.
