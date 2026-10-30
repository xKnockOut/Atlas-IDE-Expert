unit Atlas.Common.Editing.ClassActions.PropertyGolden; // lsp-ignore-file: unused-public-member -- Golden-Datei: Das Testprojekt übersetzt nur das Ergebnis der Aktion.

// Golden-Datei für die Code-Aktion „Getter, Setter und Feld erzeugen“ (#42):
// genau das, was die Aktion aus "property Name: string;" ohne read/write
// erzeugt. Der Test vergleicht die Ausgabe mit dieser Datei; dass sie
// übersetzt, zeigt der Delphi-Testlauf. Nicht von Hand ändern, sondern neu
// erzeugen.

interface

type
  TGoldenKunde = class
  public
    constructor Create;
  private
    FName: string;
    function GetName: string;
    procedure SetName(const Value: string);
  public
    property Name: string read GetName write SetName;
  end;

implementation

constructor TGoldenKunde.Create;
begin
  inherited Create;
end;

function TGoldenKunde.GetName: string;
begin
  Result := FName;
end;

procedure TGoldenKunde.SetName(const Value: string);
begin
  if FName <> Value then
    FName := Value;
end;

end.
