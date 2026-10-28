unit Dcc.Published.Gegen;

// #1328, Gegentests zu published-type-invalid: Hier soll dcc melden (E2188).

interface

type
  TFeld = array[0..3] of Integer;

  {$M+}
  TGegenVeroeffentlicht = class
  private
    FFeld: TFeld;
    FZeiger: Pointer;
  published
    property Feld: TFeld read FFeld write FFeld; // PV1: statisches Array
    property Zeiger: Pointer read FZeiger write FZeiger; // PV2: Zeiger
  end;
  {$M-}

implementation

end.
