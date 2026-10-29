unit Cm.W1055b;

// W1055 PUBLISHED caused RTTI ($M+) to be added to type
// Erwartet: -
// Gegenfall (#1381): RTTI über {$M+}, über den Vorfahren TPersistent und über einen Vorfahren mit RTTI.

interface

uses
  System.Classes;

type
{$M+}
  TMitSchalter = class
  published
    procedure Machen;
  end;
{$M-}

  TMitVorfahr = class(TPersistent)
  published
    procedure Machen;
  end;

  TNachfahr = class(TMitSchalter)
  published
    procedure Weiter;
  end;

implementation

procedure TMitSchalter.Machen;
begin
end;

procedure TMitVorfahr.Machen;
begin
end;

procedure TNachfahr.Weiter;
begin
end;

end.
