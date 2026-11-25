unit Atlas.IDE.Base.Core.Modules.Watch;

// Bereitgestellte Objekte eines Interfaces beobachten (#1455, Regel 2 und 3):
// Ein Verbraucher in Base (Rinne, Übersichtsleiste, Statusfeld …) hält die
// Objekte aller Module zu einer IID, ohne bei jedem Zeichnen die Registry zu
// fragen. Die Liste folgt jeder Bereitstellung und jedem Zurückziehen sofort
// (die Registry meldet synchron beim Abmelden), danach ruft sie OnChanged,
// nur wenn sich die Liste wirklich geändert hat. Nach Destroy oder ohne
// Registry ist die Liste leer. Nur im Hauptthread verwenden; die Registry
// meldet im Thread der Änderung.
// TAtlasRegistryWatch hört über eine Methodenreferenz auf die Registry: Wer nur auf Änderungen reagieren will,
// braucht so keine eigene Klasse, die IAtlasRegistryListener implementiert.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Plugin.Registration.Contract,
  Atlas.Plugin.Registration;

type
  /// <summary>Hört über eine Methodenreferenz auf die Registry (Regel 2).</summary>
  TAtlasRegistryWatch = class
  private type
    TListener = class(TAtlasRegistration, IAtlasRegistryListener)
    private
      FOnChange: TAtlasRegistryChangeProc;
      FSubscription: IAtlasRegistration;
    protected
      procedure DoRevoke; override;
    public
      procedure RegistryChanged(const AChange: TAtlasRegistryChange);
    end;
  public
    /// <summary>AOnChange bei jeder Änderung von ARegistry, bis Revoke der Anmeldung; nach Revoke kommt nichts
    /// mehr an. Ohne Registry nil.</summary>
    class function Subscribe(const ARegistry: IAtlasModuleRegistry;
      const AOnChange: TAtlasRegistryChangeProc): IAtlasRegistration; static;
  end;

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

uses
  Atlas.Text.Arrays;

{ TAtlasRegistryWatch.TListener }

procedure TAtlasRegistryWatch.TListener.RegistryChanged(const AChange: TAtlasRegistryChange);
var
  mOnChange: TAtlasRegistryChangeProc;
begin
  mOnChange := FOnChange;
  if Assigned(mOnChange) then
  begin
    mOnChange(AChange);
  end;
end;

procedure TAtlasRegistryWatch.TListener.DoRevoke;
var
  mSubscription: IAtlasRegistration;
begin
  FOnChange := nil;
  mSubscription := FSubscription;
  FSubscription := nil;
  if mSubscription <> nil then
  begin
    mSubscription.Revoke;
  end;
end;

{ TAtlasRegistryWatch }

class function TAtlasRegistryWatch.Subscribe(const ARegistry: IAtlasModuleRegistry;
  const AOnChange: TAtlasRegistryChangeProc): IAtlasRegistration;
var
  mListener: TListener;
  mListenerRef: IAtlasRegistryListener;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  mListener := TListener.Create;
  mListenerRef := mListener;
  mListener.FOnChange := AOnChange;
  mListener.FSubscription := ARegistry.Subscribe(mListenerRef);
  Result := mListener;
end;

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

procedure TAtlasProvidedWatch.Refresh;
var
  mItems: TArray<IInterface>;
begin
  mItems := FRegistry.FindAll(FIID);
  if TTextArrays.Same<IInterface>(mItems, FItems) then
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
