unit Dcc.Published;

// #1328 (aus #1326), Regel published-type-invalid (E2188): Atlas meldet
// published-Properties mit dynamischem Array oder Record. Ob dcc sie zulässt,
// klärt dieser Lauf.

interface

type
  TZahlen = array of Integer;

  TPunkt = record
    X, Y: Integer;
  end;

  {$M+}
  TVeroeffentlicht = class
  private
    FListe: TArray<Integer>;
    FZahlen: TZahlen;
    FPunkt: TPunkt;
  published
    property Liste: TArray<Integer> read FListe write FListe; // PU1: generisches dynamisches Array
    property Zahlen: TZahlen read FZahlen write FZahlen; // PU2: benanntes dynamisches Array
    property Punkt: TPunkt read FPunkt write FPunkt; // PU3: Record
  end;
  {$M-}

implementation

end.
