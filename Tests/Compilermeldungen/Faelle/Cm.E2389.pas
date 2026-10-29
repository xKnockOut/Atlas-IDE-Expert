unit Cm.E2389;

// E2389 Protected member '%s' is inaccessible here
// Erwartet: E2362
// Delphi 13 meldet hier E2362 statt E2389.
// Vermutung; Delphi meldet hier vermutlich E2362.

interface

uses
  Cm.Hilfe.E2389;

type
  TKind = class(TBasis)
  public
    procedure Rufen(AAndere: TBasis);
  end;

implementation

procedure TKind.Rufen(AAndere: TBasis);
begin
  AAndere.Geschuetzt; // <- E2362
end;

end.
