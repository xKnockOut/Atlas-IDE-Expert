unit Atlas.Common.Editing.ClassActions.InterfaceGolden; // lsp-ignore-file: unused-public-member -- Golden-Datei: Das Testprojekt übersetzt nur das Ergebnis der Aktion.

// Golden-Datei für die Code-Aktion „Methoden von IFoo implementieren“ (#42):
// genau das, was die Aktion für ein Interface im Kopf der Klasse erzeugt.
// Der Test vergleicht die Ausgabe mit dieser Datei; dass sie übersetzt,
// zeigt der Delphi-Testlauf. Nicht von Hand ändern, sondern neu erzeugen.

interface

type
  IGoldenZaehler = interface
    ['{6C1D5A3E-7F42-4B8A-9D0E-2A5F8C3B1E47}']
    function Wert: Integer;
    procedure Erhoehe(ASchritt: Integer);
  end;

  TGoldenZaehler = class(TInterfacedObject, IGoldenZaehler)
  public
    { IGoldenZaehler }
    function Wert: Integer;
    procedure Erhoehe(ASchritt: Integer);
  end;

implementation

function TGoldenZaehler.Wert: Integer;
begin
  Result := Default(Integer);
end;

procedure TGoldenZaehler.Erhoehe(ASchritt: Integer);
begin

end;

end.
