unit Dcc.Sichtbarkeit.Basis;

// #1328, Regel inaccessible-member: Typen, deren geschützte Mitglieder aus einer
// anderen Unit benutzt werden (Spring4D Collections).

interface

type
  TKnoten<T> = class sealed
  protected
    FNaechster: TKnoten<T>;
    FWert: T;
  public
    constructor Create(const AWert: T);
  end;

  TBaumBasis = class
  protected
    FAnzahl: Integer;
    function Suche(AWert: Integer): Pointer;
  end;

  TBaum<T> = class(TBaumBasis)
  protected
    function Finde(const AWert: T): Pointer;
  end;

  TEinfach = class
  protected
    FWert: Integer;
  end;

  TInspektor = class
  private
    class constructor Create;
  end;

  TAktiv = class
  public
    function Waehle(const AText: string): Integer; overload;
    class function Waehle(AKlasse: TClass; const AText: string): Integer; overload;
    class function NachName(const AName: string): Integer;
  end;

implementation

constructor TKnoten<T>.Create(const AWert: T);
begin
  inherited Create;
  FWert := AWert;
end;

function TBaumBasis.Suche(AWert: Integer): Pointer;
begin
  Result := Pointer(NativeInt(AWert + FAnzahl));
end;

function TBaum<T>.Finde(const AWert: T): Pointer;
begin
  Result := Suche(SizeOf(AWert));
end;

class constructor TInspektor.Create;
begin
end;

function TAktiv.Waehle(const AText: string): Integer;
begin
  Result := Length(AText);
end;

class function TAktiv.Waehle(AKlasse: TClass; const AText: string): Integer;
begin
  Result := Length(AKlasse.ClassName + AText);
end;

class function TAktiv.NachName(const AName: string): Integer;
begin
  Result := Waehle(TAktiv, AName); // IM5: Überladung als Klassenmethode in einer Klassenmethode (DMVC ActiveRecord)
end;

end.
