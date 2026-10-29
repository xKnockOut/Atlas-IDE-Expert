unit Dcc.Automation;

// #1373, Gegenproben zu automation-invalid: Das soll dcc ohne Fehler übersetzen
// (W1000 an automated erwartet), und Atlas meldet hier nichts.

interface

uses
  System.Variants;

type
  IAutoDisp = dispinterface
    ['{6B1F2C4E-3D7A-4E8B-9C0D-1A2B3C4D5E6F}']
    procedure Machen; dispid 1;
    property Wert: Integer readonly dispid 2;
  end;

  TAutoBasis = class
  private
    function GetWert: Integer;
    procedure SetWert(AWert: Integer);
  automated
    procedure Erste(AZahl: Integer; const AText: WideString); dispid 1; // AU1: erlaubte Typen
    procedure Zweite(var AWert: OleVariant; AKomma: Double); register; dispid 2; // AU2: register ausdrücklich
    procedure Virtuell; virtual; dispid 3; // AU3: virtual mit dispid
    property Wert: Integer read GetWert write SetWert dispid 4; // AU4: Getter und Setter als Methoden
    function Quelle: IDispatch; // AU5: Interface als Ergebnis
  end;

  TAutoKind = class(TAutoBasis)
  automated
    procedure Virtuell; override; // AU6: override ohne dispid
    procedure Eigene; dispid 1; // AU7: dieselbe Nummer wie im Vorfahren (Atlas still; meldet dcc E2180, fehlt der Regel dieser Fall)
  end;

procedure Aufrufe(AQuelle: IDispatch);

implementation

function TAutoBasis.GetWert: Integer;
begin
  Result := 0;
end;

procedure TAutoBasis.SetWert(AWert: Integer);
begin
end;

procedure TAutoBasis.Erste(AZahl: Integer; const AText: WideString);
begin
end;

procedure TAutoBasis.Zweite(var AWert: OleVariant; AKomma: Double);
begin
end;

procedure TAutoBasis.Virtuell;
begin
end;

function TAutoBasis.Quelle: IDispatch;
begin
  Result := nil;
end;

procedure TAutoKind.Virtuell;
begin
end;

procedure TAutoKind.Eigene;
begin
end;

procedure Aufrufe(AQuelle: IDispatch);
var
  mVar: Variant;
  mOle: OleVariant;
begin
  mVar := Unassigned;
  mOle := Unassigned;
  mVar.Machen(1, 'Text', mVar, AQuelle); // AU8: Zahl, String, Variant, Interface
  mOle.Machen(1, Wert := 2, Name := 'a'); // AU9: benannte nach unbenannten Argumenten
  mOle.Dokument.Oeffnen(Datei := 'a.docx'); // AU10: Kette über einen Variant
end;

end.
