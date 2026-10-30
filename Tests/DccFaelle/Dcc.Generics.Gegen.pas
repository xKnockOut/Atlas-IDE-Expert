unit Dcc.Generics.Gegen;

// #1376, Gegentest zu generic-declaration-invalid und generic-inference-failed:
// Formen, die Atlas über die Fälle aus Tests/Compilermeldungen hinaus meldet.
// Hier soll dcc melden.

interface

uses
  System.Classes;

type
  TKlasse = class
  public
    constructor Create<T>(A: T); // GG1: E2528 auch mit Parameter
  end;

  TWerkzeug = class
  public
    function Neu<T>: Integer;
  end;

  TEigeneZahlen = type TArray<Integer>; // GG3: E2574 bei TArray<T>

  TStromBehaelter<T: TStream, record> = class // GG4: E2552 mit record, Klasse aus System.Classes
  end;

  TFabrik = class
  public
    class function Neu<T>: T; static;
    class procedure Paar<T>(A, B: T); static;
  end;

procedure Fall;

implementation

constructor TKlasse.Create<T>(A: T);
begin
end;

function TWerkzeug.Neu<T>: Integer;

  function Zaehlen: Integer; // GG2: E2570 in einer generischen Methode
  begin
    Result := 1;
  end;

begin
  Result := Zaehlen;
end;

class function TFabrik.Neu<T>: T;
begin
  Result := Default(T);
end;

class procedure TFabrik.Paar<T>(A, B: T);
begin
end;

procedure Fall;
var
  mZahl: Integer;
  mText: string;
begin
  mZahl := 1;
  mText := 'a';
  TFabrik.Neu; // GG5: E2531 als Anweisung
  mZahl := TFabrik.Neu(); // GG5: E2531 mit Klammern
  TFabrik.Paar(mZahl, mText); // GG6: E2532 mit Variablen
  TFabrik.Paar(True, -1); // GG6: E2532 Boolean und Zahl
end;

end.
