unit Atlas.Core.Notifications.Listeners;

// Beobachter einer Liste mit Änderungsmeldung (Benachrichtigungszentrale #601,
// Statusfeld #591), ohne VCL: Anmelden gibt einen Griff zurück, mit dem der
// Beobachter sich wieder abmeldet. Changed erhöht die Version (Zähler aller
// Änderungen) und ruft die Beobachter außerhalb der Sperre, damit sie die
// meldende Liste lesen dürfen; ein Fehler im Beobachter darf die meldende
// Funktion nicht stören. Threadsicher.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
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
