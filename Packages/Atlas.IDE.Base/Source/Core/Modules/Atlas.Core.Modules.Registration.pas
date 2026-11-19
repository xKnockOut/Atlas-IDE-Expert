unit Atlas.Core.Modules.Registration;

// Gemeinsame Grundlage der Anmeldungen in Base (#1455, Regel 4): Revoke löst
// eine Anmeldung genau einmal; Detach markiert sie als gelöst, ohne den
// Besitzer zu rufen, wenn die Ablage vor ihr abgebaut wird (sonst zeigte ein
// späteres Revoke in freigegebenen Speicher). TAtlasListenerList hält die
// Hörer einer Ablage mit ihren Anmeldungen.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Modules.Contract;

type
  TAtlasRegistration = class(TInterfacedObject, IAtlasRegistration)
  private
    FLock: TCriticalSection;
    FRevoked: Boolean;
    function TryClaim: Boolean;
  protected
    /// <summary>Löst die Anmeldung bei ihrer Ablage; genau einmal gerufen, nie nach Detach.</summary>
    procedure DoRevoke; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Revoke;
    function IsRevoked: Boolean;
    /// <summary>Ablage abgebaut: als gelöst markieren, ohne DoRevoke.</summary>
    procedure Detach;
  end;

  /// <summary>Hörer einer Ablage (T: Interface des Hörers) mit ihren Anmeldungen, aus jedem Thread. Visit ruft die
  /// Hörer außerhalb der Sperre, damit ein Hörer sich oder andere lösen darf; Destroy trennt alle Anmeldungen ab
  /// (Detach).</summary>
  TAtlasListenerList<T> = class
  private type
    TEntry = record
      Listener: T;
      OwnerId: string;
      Item: TAtlasRegistration;
      Ref: IAtlasRegistration;
    end;
  private
    FLock: TCriticalSection;
    FEntries: TList<TEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AListener mit seiner Anmeldung AItem (deren DoRevoke ruft Remove) aufnehmen; AOwnerId nennt den
    /// Besitzer in Fehlermeldungen. Ergebnis: die Anmeldung.</summary>
    function Add(const AListener: T; const AOwnerId: string; AItem: TAtlasRegistration): IAtlasRegistration;
    /// <summary>Den Hörer der Anmeldung AItem entfernen.</summary>
    procedure Remove(AItem: TAtlasRegistration);
    /// <summary>AVisit(Hörer, Besitzer) für jeden Hörer, der beim Aufruf noch angemeldet ist; ohne Sperre.</summary>
    procedure Visit(const AVisit: TProc<T, string>);
  end;

implementation

{ TAtlasRegistration }

constructor TAtlasRegistration.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TAtlasRegistration.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAtlasRegistration.TryClaim: Boolean;
begin
  FLock.Acquire;
  try
    Result := not FRevoked;
    FRevoked := True;
  finally
    FLock.Release;
  end;
end;

procedure TAtlasRegistration.Revoke;
begin
  if TryClaim then
  begin
    DoRevoke;
  end;
end;

function TAtlasRegistration.IsRevoked: Boolean;
begin
  FLock.Acquire;
  try
    Result := FRevoked;
  finally
    FLock.Release;
  end;
end;

procedure TAtlasRegistration.Detach;
begin
  TryClaim;
end;

{ TAtlasListenerList<T> }

constructor TAtlasListenerList<T>.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEntries := TList<TEntry>.Create;
end;

destructor TAtlasListenerList<T>.Destroy;
var
  mEntry: TEntry;
begin
  if FEntries <> nil then
  begin
    for mEntry in FEntries do
    begin
      mEntry.Item.Detach;
    end;
  end;
  FEntries.Free;
  FLock.Free;
  inherited;
end;

function TAtlasListenerList<T>.Add(const AListener: T; const AOwnerId: string;
  AItem: TAtlasRegistration): IAtlasRegistration;
var
  mEntry: TEntry;
begin
  mEntry.Listener := AListener;
  mEntry.OwnerId := AOwnerId;
  mEntry.Item := AItem;
  mEntry.Ref := AItem;
  FLock.Acquire;
  try
    FEntries.Add(mEntry);
  finally
    FLock.Release;
  end;
  Result := mEntry.Ref;
end;

procedure TAtlasListenerList<T>.Remove(AItem: TAtlasRegistration);
var
  mIndex: Integer;
begin
  // Wer Revoke ruft, hält selbst eine Referenz: AItem lebt über das Löschen hinaus.
  FLock.Acquire;
  try
    for mIndex := 0 to FEntries.Count - 1 do
    begin
      if FEntries[mIndex].Item = AItem then
      begin
        FEntries.Delete(mIndex);
        Break;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TAtlasListenerList<T>.Visit(const AVisit: TProc<T, string>);
var
  mEntries: TArray<TEntry>;
  mEntry: TEntry;
begin
  FLock.Acquire;
  try
    mEntries := FEntries.ToArray;
  finally
    FLock.Release;
  end;
  for mEntry in mEntries do
  begin
    // Ein früherer Hörer kann diesen gelöst haben (Regel 3).
    if not mEntry.Item.IsRevoked then
    begin
      AVisit(mEntry.Listener, mEntry.OwnerId);
    end;
  end;
end;

end.
