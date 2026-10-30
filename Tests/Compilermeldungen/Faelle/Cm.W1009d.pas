unit Cm.W1009d;

// W1009 Redeclaration hides a member in the base class
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: statische Methode mit gleicher Signatur
// verdeckt die des Vorfahren.

interface

type
  TBasis = class
  public
    procedure Machen;
  end;

  TKind = class(TBasis)
  public
    procedure Machen; // <- ohne Meldung
  end;

implementation

procedure TBasis.Machen;
begin
end;

procedure TKind.Machen;
begin
end;

end.
