unit Dcc.Automation.Gegen;

// #1373, Gegentests zu automation-invalid im Abschnitt automated: Hier soll dcc
// melden. Die Fälle aus Tests/Compilermeldungen sind bestätigt; diese Formen
// leitet die Regel aus der Sprachreferenz ab und prüft sie hier.

interface

type
  TPunkt = record
    X, Y: Integer;
  end;
  PPunkt = ^TPunkt;
  TFarbe = (Rot, Gruen);
  TFarben = set of TFarbe;

  TAutoGegen = class
  private
    function GetWert: Integer;
  automated
    destructor Destroy; override; // AG1: Destruktor (E2177)
    procedure Nachricht(var AMsg); message 1; // AG2: message (E2178)
    procedure Sicher; safecall; // AG3: safecall (E2179)
    procedure Zeiger(AZeiger: Pointer); // AG4: Pointer (E2176)
    procedure Typisiert(AZeiger: PPunkt); // AG5: typisierter Zeiger (E2176)
    function Farben: TFarben; // AG6: Menge als Ergebnis (E2176)
    function Ort: TPunkt; // AG13: Record als Ergebnis (E2176)
    property Wo: TPunkt read Ort; // AG7: Record als Property (E2176)
    property Gespeichert: Integer read GetWert stored False; // AG8: stored (E2182)
    property Vorgabe: Integer read GetWert default 0; // AG9: default (E2182)
    property Ohne: Integer read GetWert nodefault; // AG10: nodefault (E2182)
    procedure Hex; dispid $10;
    procedure Dezimal; dispid 16; // AG11: dieselbe dispid als Hex und dezimal (E2180)
    property Nummer: Integer read GetWert dispid 16; // AG12: dieselbe dispid an einer Property (E2180)
  end;

implementation

end.
