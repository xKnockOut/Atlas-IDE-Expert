unit Atlas.Core.Notifications.Listeners;

// Beobachter einer Liste mit Änderungsmeldung (Benachrichtigungszentrale #601,
// Statusfeld #591, Bereiche der Willkommensseite #753), ohne VCL: Anmelden gibt
// einen Griff zurück, mit dem der Beobachter sich wieder abmeldet. Changed
// erhöht die Version (Zähler aller Änderungen) und ruft die Beobachter außerhalb
// der Sperre, damit sie die meldende Liste lesen dürfen; ein Fehler im
// Beobachter darf die meldende Funktion nicht stören. Threadsicher.
// - TAtlasNotificationListeners: Beobachter ohne Angabe (TProc).
// - TAtlasListeners<T>: Beobachter erhalten mit jeder Meldung einen Wert, etwa
//   die Kennung des geänderten Eintrags (TProc<T>).
// Gesperrt wird mit Acquire/Release statt mit den inline-Fassungen Enter/Leave: Generische Rümpfe werden in den
// Units der Module ausgeprägt, die System.SyncObjs nicht einbinden (H2443).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
  /// <summary>Anmelden, Abmelden und Version der Beobachter; die Ableitungen rufen sie.</summary>
  TAtlasListenerList<TListener> = class
  private
    FLock: TCriticalSection;
    FListeners: TDictionary<Integer, TListener>;
    FNextHandle: Integer;
    FVersion: Integer;
  protected
    /// <summary>Version erhöhen und die zur Zeit angemeldeten Beobachter liefern (unter der Sperre).</summary>
    function Changing: TArray<TListener>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AListener anmelden; Ergebnis ist der Griff für Remove.</summary>
    function Add(const AListener: TListener): Integer;
    /// <summary>Beobachter mit dem Griff AHandle abmelden; unbekannte Griffe werden übergangen.</summary>
    procedure Remove(AHandle: Integer);
    /// <summary>Zahl der Änderungen bisher (steigt mit jeder Meldung).</summary>
    function Version: Integer;
  end;

  TAtlasNotificationListeners = class(TAtlasListenerList<TProc>)
  public
    /// <summary>Version erhöhen und alle Beobachter rufen.</summary>
    procedure Changed;
  end;

  TAtlasListeners<T> = class(TAtlasListenerList<TProc<T>>)
  public
    /// <summary>Version erhöhen und alle Beobachter mit AValue rufen.</summary>
    procedure Changed(const AValue: T);
  end;

implementation


uses
  Atlas.Text.Reporting;

{ TAtlasListenerList<TListener> }

constructor TAtlasListenerList<TListener>.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FListeners := TDictionary<Integer, TListener>.Create;
end;

destructor TAtlasListenerList<TListener>.Destroy;
begin
  FListeners.Free;
  FLock.Free;
  inherited Destroy;
end;

function TAtlasListenerList<TListener>.Add(const AListener: TListener): Integer;
begin
  FLock.Acquire;
  try
    Inc(FNextHandle);
    Result := FNextHandle;
    FListeners.Add(Result, AListener);
  finally
    FLock.Release;
  end;
end;

procedure TAtlasListenerList<TListener>.Remove(AHandle: Integer);
begin
  FLock.Acquire;
  try
    FListeners.Remove(AHandle);
  finally
    FLock.Release;
  end;
end;

function TAtlasListenerList<TListener>.Changing: TArray<TListener>;
begin
  FLock.Acquire;
  try
    Inc(FVersion);
    Result := FListeners.Values.ToArray;
  finally
    FLock.Release;
  end;
end;

function TAtlasListenerList<TListener>.Version: Integer;
begin
  // Nur lesen: Changing erhöht den Zähler unter der Sperre.
  Result := TInterlocked.Add(FVersion, 0);
end;

{ TAtlasNotificationListeners }

procedure TAtlasNotificationListeners.Changed;
var
  mListener: TProc;
begin
  // Außerhalb der Sperre: Beobachter dürfen die meldende Liste lesen.
  for mListener in Changing do
    try
      mListener();
    except
      // Ein Fehler im Beobachter darf die meldende Funktion nicht stören.
      on E: Exception do
      begin
        TReporting.Failed('Beobachter', E); // german-ok Protokoll
      end;
    end;
end;

{ TAtlasListeners<T> }

procedure TAtlasListeners<T>.Changed(const AValue: T);
var
  mListener: TProc<T>;
begin
  // Außerhalb der Sperre: Beobachter dürfen die meldende Liste lesen.
  for mListener in Changing do
    try
      mListener(AValue);
    except
      // Ein Fehler im Beobachter darf die meldende Funktion nicht stören.
      on E: Exception do
      begin
        TReporting.Failed('Beobachter', E); // german-ok Protokoll
      end;
    end;
end;

end.
