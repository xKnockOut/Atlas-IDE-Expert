unit Atlas.Core.Notifications.Listeners;

// Beobachter einer Liste mit Änderungsmeldung (Benachrichtigungszentrale #601,
// Statusfeld #591), ohne VCL: Anmelden gibt einen Griff zurück, mit dem der
// Beobachter sich wieder abmeldet. Changed erhöht die Version (Zähler aller
// Änderungen) und ruft die Beobachter außerhalb der Sperre, damit sie die
// meldende Liste lesen dürfen; ein Fehler im Beobachter darf die meldende
// Funktion nicht stören. Threadsicher.
// RemoveOwned meldet alle Beobachter ab, deren Code einem Modul gehört, das
// gerade entladen wird (TAtlasOwnedCode); sonst riefe die nächste Meldung
// Code, der nicht mehr im Speicher liegt.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
  /// <summary>Gehört die Methodenreferenz bzw. das Interface an AReference (der Zeiger auf die Schnittstelle) dem
  /// Modul, das gerade abgemeldet wird? Die Komposition entscheidet über das Modul des Codes; Tests über die
  /// Instanz. Ein Typ für alle Listen, die Rückrufe von Modulen halten: TFunc der RTL, damit Aufrufer ihn ohne
  /// diese Unit bilden können (Delphi 12 hält gleich gebaute Methodenreferenztypen auseinander).</summary>
  TAtlasOwnedCode = TFunc<Pointer, Boolean>;

  TAtlasNotificationListeners = class
  private
    FLock: TCriticalSection;
    FListeners: TDictionary<Integer, TProc>;
    FNextHandle: Integer;
    FVersion: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AListener anmelden; Ergebnis ist der Griff für Remove.</summary>
    function Add(const AListener: TProc): Integer;
    /// <summary>Beobachter mit dem Griff AHandle abmelden; unbekannte Griffe werden übergangen.</summary>
    procedure Remove(AHandle: Integer);
    /// <summary>Alle Beobachter abmelden, deren Code AOwned gehört; Ergebnis: ihre Zahl. Freigegeben werden sie
    /// außerhalb der Sperre.</summary>
    function RemoveOwned(const AOwned: TAtlasOwnedCode): Integer;
    /// <summary>Version erhöhen und alle Beobachter rufen.</summary>
    procedure Changed;
    /// <summary>Zahl der Änderungen bisher (steigt mit jedem Changed).</summary>
    function Version: Integer;
  end;

implementation

{ TAtlasNotificationListeners }

constructor TAtlasNotificationListeners.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FListeners := TDictionary<Integer, TProc>.Create;
end;

destructor TAtlasNotificationListeners.Destroy;
begin
  FListeners.Free;
  FLock.Free;
  inherited Destroy;
end;

function TAtlasNotificationListeners.Add(const AListener: TProc): Integer;
begin
  FLock.Enter;
  try
    Inc(FNextHandle);
    Result := FNextHandle;
    FListeners.Add(Result, AListener);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasNotificationListeners.Remove(AHandle: Integer);
begin
  FLock.Enter;
  try
    FListeners.Remove(AHandle);
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationListeners.RemoveOwned(const AOwned: TAtlasOwnedCode): Integer;
var
  mPair: TPair<Integer, TProc>;
  mHandles: TArray<Integer>;
  mDropped: TArray<TProc>;
  mIndex: Integer;
begin
  mHandles := nil;
  mDropped := nil;
  FLock.Enter;
  try
    for mPair in FListeners do
    begin
      if AOwned(PPointer(@mPair.Value)^) then
      begin
        SetLength(mHandles, Length(mHandles) + 1);
        mHandles[High(mHandles)] := mPair.Key;
      end;
    end;
    SetLength(mDropped, Length(mHandles));
    for mIndex := 0 to High(mHandles) do
    begin
      mDropped[mIndex] := FListeners[mHandles[mIndex]];
      FListeners.Remove(mHandles[mIndex]);
    end;
  finally
    FLock.Leave;
  end;
  // mDropped wird erst beim Verlassen frei, außerhalb der Sperre.
  Result := Length(mDropped);
end;

procedure TAtlasNotificationListeners.Changed;
var
  mListeners: TArray<TProc>;
  mListener: TProc;
begin
  FLock.Enter;
  try
    Inc(FVersion);
    mListeners := FListeners.Values.ToArray;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die meldende Liste lesen.
  for mListener in mListeners do
    try
      mListener();
    except
      // Ein Fehler im Beobachter darf die meldende Funktion nicht stören.
      on Exception do
        ;
    end;
end;

function TAtlasNotificationListeners.Version: Integer;
begin
  // Nur lesen: Changed erhöht den Zähler unter der Sperre.
  Result := TInterlocked.Add(FVersion, 0);
end;

end.
