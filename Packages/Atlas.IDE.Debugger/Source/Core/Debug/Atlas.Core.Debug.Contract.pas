unit Atlas.Core.Debug.Contract;

// Verträge des Debuggers ohne Open Tools API, die die IDE-Schicht erfüllt und
// die Tests fälschen:
//   - IAtlasDebugTarget: der Debugger, wie ihn die Phasen der Sitzung sehen
//     (Atlas.Core.Debug.Phases).
//   - IAtlasDebugEvaluator: Auswerten und Ändern im angehaltenen Thread für die
//     Auswertung in Zeitscheiben (Atlas.Core.Debug.EvalSlices).
//   - IAtlasProcessMemory: lesender Zugriff auf den Speicher des Programms für
//     die Objektzählung (#858, Atlas.Core.Debug.ObjectCount).

interface

uses
  System.SysUtils,
  Atlas.Core.Hover.Contract.DebugValue;

type
  {$SCOPEDENUMS ON}
  /// <summary>Zustand des Prozesses, wie ihn der Debugger meldet; Other für alle übrigen (beendet, ohne).
  /// </summary>
  TAtlasDebugProcessState = (Other, Running, Stopped, Exception, Fault);
  {$SCOPEDENUMS OFF}

  /// <summary>Der Debugger, wie ihn die Phasen sehen; in der IDE über IOTADebuggerServices.</summary>
  IAtlasDebugTarget = interface
    ['{B4D17E2A-6C93-4F0B-8E51-2A7C9D03F6B8}']
    /// <summary>Anzahl der Prozesse der Sitzung.</summary>
    function ProcessCount: Integer;
    /// <summary>Zustand des aktuellen Prozesses; Other ohne Prozess.</summary>
    function CurrentState: TAtlasDebugProcessState;
    /// <summary>Ist der aktuelle Prozess angehalten und hat er einen aktuellen Thread?</summary>
    function HasStoppedThread: Boolean;
    /// <summary>TAtlasDebugPhases.Tick einmal aufrufen, sobald die Benachrichtigung des Debuggers vorbei ist.
    /// </summary>
    procedure RequestTick;
    /// <summary>AProc geschützt ausführen (Zuhörer, Filter); ein Fehler darf die übrigen nicht aufhalten.
    /// </summary>
    procedure Run(const AProc: TProc);
  end;

  /// <summary>Verzögert kommender Wert einer Auswertung.</summary>
  TAtlasDebugValueDone = reference to procedure(const AValue: TAtlasDebugValue);

  /// <summary>Auswertung im angehaltenen Thread.</summary>
  IAtlasDebugEvaluator = interface
    ['{3A27E153-140A-4972-9BE0-FC10ACB9CE65}']
    /// <summary>AExpression an AFileName, ALine (1-basiert) auswerten; ASideEffects erlaubt Aufrufe und Getter.
    /// Ergebnis Value oder Failed; Pending: Der Wert kommt einmal über ADone, außer nach Cancel; None: kein
    /// angehaltener Prozess.</summary>
    function Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
      const ADone: TAtlasDebugValueDone): TAtlasDebugValue;
    /// <summary>Laufende verzögerte Auswertung verwerfen; ihr Rückruf kommt nicht mehr.</summary>
    procedure Cancel;
    /// <summary>AExpression an AFileName, ALine (1-basiert) auf ANewValue setzen. AResult: neuer Wert bzw.
    /// Fehlertext; leer, wenn der Debugger verzögert antwortet.</summary>
    function Modify(const AExpression, AFileName: string; ALine: Integer; const ANewValue: string;
      out AResult: string): Boolean;
  end;

  /// <summary>Neue Auswertung im angehaltenen Thread.</summary>
  TAtlasDebugEvaluatorFactory = reference to function: IAtlasDebugEvaluator;

  {$SCOPEDENUMS ON}
  TAtlasMemoryRegionKind = (Data, Image);
  {$SCOPEDENUMS OFF}

  TAtlasMemoryRegion = record
    Base: UInt64;
    Size: UInt64;
    Kind: TAtlasMemoryRegionKind;
    class function Make(ABase, ASize: UInt64; AKind: TAtlasMemoryRegionKind): TAtlasMemoryRegion; static;
  end;

  /// <summary>Lesender Zugriff auf den Speicher eines Prozesses.</summary>
  IAtlasProcessMemory = interface
    ['{6C0E2B7A-3D51-4F1E-9A8C-5B2D7E41C903}']
    /// <summary>4 (32-Bit-Programm) oder 8 (64-Bit-Programm).</summary>
    function PointerSize: Integer;
    /// <summary>Belegte Bereiche: privater beschreibbarer Speicher (Data) und Abbilder (Image), aufsteigend.
    /// </summary>
    function Regions: TArray<TAtlasMemoryRegion>;
    /// <summary>Bis zu ASize Bytes ab AAddress nach ABuffer; Ergebnis = gelesene Bytes (0 bei Fehler).</summary>
    function Read(AAddress: UInt64; var ABuffer; ASize: Integer): Integer;
  end;

implementation

{ TAtlasMemoryRegion }

class function TAtlasMemoryRegion.Make(ABase, ASize: UInt64; AKind: TAtlasMemoryRegionKind): TAtlasMemoryRegion;
begin
  Result.Base := ABase;
  Result.Size := ASize;
  Result.Kind := AKind;
end;

end.
