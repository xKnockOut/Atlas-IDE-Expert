unit Atlas.Common.Pascal.Cancellation;

// Abbruchsignal für den Parser aus einer Funktion: Wer lange Läufe abbrechen will
// (z. B. mit dem Token einer Anfrage), gibt nur die Prüfung mit; das Signal dazu
// baut dieses Feature. So implementiert kein anderes Feature IPascalCancellation selbst.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract;

type
  TPascalCancellations = record
  public
    /// <summary>Signal, das abbricht, sobald AIsCancelled True liefert; nil bricht nie ab.</summary>
    class function FromCheck(const AIsCancelled: TFunc<Boolean>): IPascalCancellation; static;
  end;

implementation

type
  TCheckedCancellation = class(TInterfacedObject, IPascalCancellation)
  private
    FIsCancelled: TFunc<Boolean>;
  public
    constructor Create(const AIsCancelled: TFunc<Boolean>);
    function IsCancelled: Boolean;
  end;

{ TCheckedCancellation }

constructor TCheckedCancellation.Create(const AIsCancelled: TFunc<Boolean>);
begin
  inherited Create;
  FIsCancelled := AIsCancelled;
end;

function TCheckedCancellation.IsCancelled: Boolean;
begin
  Result := Assigned(FIsCancelled) and FIsCancelled();
end;

{ TPascalCancellations }

class function TPascalCancellations.FromCheck(const AIsCancelled: TFunc<Boolean>): IPascalCancellation;
begin
  Result := TCheckedCancellation.Create(AIsCancelled);
end;

end.
