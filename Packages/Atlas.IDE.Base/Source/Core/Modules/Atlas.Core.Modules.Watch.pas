unit Atlas.Core.Modules.Watch;

// Bereitgestellte Objekte eines Interfaces beobachten (#1455, Regel 2 und 3):
// Ein Verbraucher in Base (Rinne, Übersichtsleiste, Statusfeld …) hält die
// Objekte aller Module zu einer IID, ohne bei jedem Zeichnen die Registry zu
// fragen. Die Liste folgt jeder Bereitstellung und jedem Zurückziehen sofort
// (die Registry meldet synchron beim Abmelden), danach ruft sie OnChanged,
// nur wenn sich die Liste wirklich geändert hat. Nach Destroy oder ohne
// Registry ist die Liste leer. Nur im Hauptthread verwenden; die Registry
// meldet im Thread der Änderung.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasProvidedWatch = class
  private type
    TListener = class(TInterfacedObject, IAtlasRegistryListener)
    private
      FOwner: TAtlasProvidedWatch;
    public
      procedure RegistryChanged(const AChange: TAtlasRegistryChange);
    end;
  private
    FRegistry: IAtlasModuleRegistry;
    FIID: TGUID;
    FItems: TArray<IInterface>;
    FOnChanged: TProc;
    FListener: TListener;
    FListenerRef: IAtlasRegistryListener;
    FSubscription: IAtlasRegistration;
    procedure Refresh;
    class function SameItems(const A, B: TArray<IInterface>): Boolean; static;
  public
    /// <summary>ARegistry darf nil sein (dann bleibt die Liste leer).</summary>
    constructor Create(const ARegistry: IAtlasModuleRegistry; const AIID: TGUID);
    destructor Destroy; override;
    /// <summary>Bereitgestellte Objekte in Reihenfolge der Bereitstellung.</summary>
    property Items: TArray<IInterface> read FItems;
    /// <summary>Nach jeder Änderung der Liste.</summary>
    property OnChanged: TProc read FOnChanged write FOnChanged;
  end;

implementation

{ TAtlasProvidedWatch.TListener }

procedure TAtlasProvidedWatch.TListener.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  if FOwner = nil then
  begin
    Exit;
  end;
  case AChange.Kind of
    rcProvided, rcRevoked:
      if IsEqualGUID(AChange.IID, FOwner.FIID) then
      begin
        FOwner.Refresh;
      end;
    rcModuleRemoved:
      // Sicherheitsnetz: Ein abgemeldetes Modul hat seine Objekte schon zurückgezogen (rcRevoked).
      FOwner.Refresh;
  else
    // Ein neues Modul ohne Objekte dieser IID und die Liste bekannter Module ändern nichts.
  end;
end;

{ TAtlasProvidedWatch }

constructor TAtlasProvidedWatch.Create(const ARegistry: IAtlasModuleRegistry; const AIID: TGUID);
begin
  inherited Create;
  FRegistry := ARegistry;
  FIID := AIID;
  if FRegistry = nil then
  begin
    Exit;
  end;
  FListener := TListener.Create;
  FListener.FOwner := Self;
  FListenerRef := FListener;
  FSubscription := FRegistry.Subscribe(FListenerRef);
  FItems := FRegistry.FindAll(FIID);
end;

destructor TAtlasProvidedWatch.Destroy;
begin
  if FListener <> nil then
  begin
    FListener.FOwner := nil;
  end;
  if FSubscription <> nil then
  begin
    FSubscription.Revoke;
  end;
  FSubscription := nil;
  FListenerRef := nil;
  FItems := nil;
  FOnChanged := nil;
  FRegistry := nil;
  inherited;
end;

class function TAtlasProvidedWatch.SameItems(const A, B: TArray<IInterface>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if A[mIndex] <> B[mIndex] then
    begin
      Exit(False);
    end;
  end;
end;

procedure TAtlasProvidedWatch.Refresh;
var
  mItems: TArray<IInterface>;
begin
  mItems := FRegistry.FindAll(FIID);
  if SameItems(mItems, FItems) then
  begin
    Exit;
  end;
  FItems := mItems;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

end.
