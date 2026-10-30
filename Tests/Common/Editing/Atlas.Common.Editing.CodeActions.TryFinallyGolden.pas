unit Atlas.Common.Editing.CodeActions.TryFinallyGolden; // lsp-ignore-file: unused-public-member -- Golden-Datei: Das Testprojekt übersetzt nur das Ergebnis der Aktion.

// Golden-Datei für "try/finally ergänzen" (#42): genau das, was die Aktion
// aus den Routinen ohne try erzeugt. Der Test wendet die Aktion auf jede
// Create-Zeile an und vergleicht mit dieser Datei; dass das Ergebnis
// übersetzt, zeigt der Delphi-Testlauf. Nicht von Hand ändern, sondern neu
// erzeugen.

interface

uses
  System.Classes,
  System.SysUtils;

type
  TFeldHalter = class
  private
    FListe: TStringList;
  public
    procedure Fuelle;
    procedure FuelleUeberSelf;
  end;

function Zeilen: Integer;
function InlineZeilen: Integer;
function Mehrzeilig: Integer;
procedure Freigabe;
function Liste: TStringList;

implementation

procedure TFeldHalter.Fuelle;
begin
  FListe := TStringList.Create;
  FListe.Add('Feld');
end;

procedure TFeldHalter.FuelleUeberSelf;
begin
  Self.FListe := TStringList.Create;
  Self.FListe.Add('Feld');
end;

function Zeilen: Integer;
var
  Text: TStringList;
begin
  Text := TStringList.Create;
  try
    Text.Add('a');

    Result := Text.Count;
  finally
    Text.Free;
  end;
end;

function InlineZeilen: Integer;
begin
  var Text := TStringList.Create;
  try
    Text.Add('a');
    Result := Text.Count;
  finally
    Text.Free;
  end;
end;

function Mehrzeilig: Integer;
var
  Text: TStringList;
begin
  Text := TStringList.Create(
    True);
  try
    Result := Text.Count;
  finally
    Text.Free;
  end;
end;

procedure Freigabe;
var
  Text: TStringList;
begin
  Text := TStringList.Create;
  try
    Text.Add('x');
  finally
    FreeAndNil(Text);
  end;
end;

function Liste: TStringList;
begin
  Result := TStringList.Create;
  try
    Result.Add('x');
  except
    Result.Free;
    raise;
  end;
end;

end.
