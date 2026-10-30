unit Atlas.Common.Editing.ClassActions.OverrideGolden; // lsp-ignore-file: override-only-inherited -- Die Aktion erzeugt absichtlich Rümpfe nur mit inherited.

// Golden-Datei für die Code-Aktion „Name überschreiben“ (#42): genau das,
// was die Aktion für zwei virtuelle Methoden des Vorfahren erzeugt. Der Test
// vergleicht die Ausgabe mit dieser Datei; dass sie übersetzt, zeigt der
// Delphi-Testlauf. Nicht von Hand ändern, sondern neu erzeugen.

interface

type
  TGoldenBasis = class
  public
    procedure Zeichne; virtual;
    function Beschreibung(AKurz: Boolean): string; virtual;
  end;

  TGoldenFigur = class(TGoldenBasis)
  public
    procedure Zeichne; override;
  public
    function Beschreibung(AKurz: Boolean): string; override;
  end;

implementation

procedure TGoldenBasis.Zeichne;
begin
end;

function TGoldenBasis.Beschreibung(AKurz: Boolean): string;
begin
  Result := '';
  if AKurz then
    Result := 'Basis';
end;

procedure TGoldenFigur.Zeichne;
begin
  inherited;
end;

function TGoldenFigur.Beschreibung(AKurz: Boolean): string;
begin
  Result := inherited Beschreibung(AKurz);
end;

end.
