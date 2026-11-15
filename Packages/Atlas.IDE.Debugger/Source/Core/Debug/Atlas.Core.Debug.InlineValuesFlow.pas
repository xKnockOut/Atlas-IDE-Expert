unit Atlas.Core.Debug.InlineValuesFlow;

// Entscheidungen der Werte im Editor (#508) ohne IDE, prüfbar (#1967): Schritt nach einem ausgewerteten Wert,
// Frist für verzögerte Werte, Ende einer Zeitscheibe und ob eine Zeile im Editor der abgeglichenen entspricht.
// Den Ablauf je Halt führt Atlas.Core.Debug.StopProgress; Atlas.IDE.Debug.InlineValues fragt Debugger, Server
// und Editor.

interface

uses
  Atlas.Core.Hover.DebugValue;

{$SCOPEDENUMS ON}

type
  /// <summary>Nach einem Wert: weiter, auf den verzögerten warten oder alles verworfen.</summary>
  TAtlasInlineStep = (Next, Wait, Dropped);

  TAtlasInlineValuesFlow = class
  public
    /// <summary>Schritt nach einem ausgewerteten Wert; ohne Zustand steht kein Prozess mehr (Dropped).</summary>
    class function StepOf(AState: TAtlasDebugValueState): TAtlasInlineStep; static;
    /// <summary>Verzögerter Wert seit AElapsedMs ausstehend, mindestens ATimeoutMs: ohne ihn weiter.</summary>
    class function DeferredExpired(AElapsedMs: UInt64; ATimeoutMs: Integer): Boolean; static;
    /// <summary>Alles ausgewertet: kein verzögerter Wert offen und keiner mehr in der Reihe.</summary>
    class function SliceDone(const ADeferredName: string; AHasPending: Boolean): Boolean; static;
    /// <summary>Kennung der Routine des Halts für die gemerkten Werte.</summary>
    class function ContextOf(const AFileName, ARoutine: string): string; static;
    /// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
    class function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer; static;
    /// <summary>Entspricht die Zeile im Editor AEditor der abgeglichenen AStored (Tabs aufgelöst, Leerraum am
    /// Ende egal)?</summary>
    class function SameLine(const AEditor, AStored: string; ATabWidth: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Editor.Pairs;

{ TAtlasInlineValuesFlow }

class function TAtlasInlineValuesFlow.StepOf(AState: TAtlasDebugValueState): TAtlasInlineStep;
begin
  case AState of
    TAtlasDebugValueState.Pending:
      Result := TAtlasInlineStep.Wait;
    TAtlasDebugValueState.Value, TAtlasDebugValueState.Failed:
      Result := TAtlasInlineStep.Next;
  else
    Result := TAtlasInlineStep.Dropped;
  end;
end;

class function TAtlasInlineValuesFlow.DeferredExpired(AElapsedMs: UInt64; ATimeoutMs: Integer): Boolean;
begin
  Result := AElapsedMs >= UInt64(ATimeoutMs);
end;

class function TAtlasInlineValuesFlow.SliceDone(const ADeferredName: string; AHasPending: Boolean): Boolean;
begin
  Result := (ADeferredName = '') and not AHasPending;
end;

class function TAtlasInlineValuesFlow.ContextOf(const AFileName, ARoutine: string): string;
begin
  Result := AFileName + '|' + ARoutine;
end;

class function TAtlasInlineValuesFlow.ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

class function TAtlasInlineValuesFlow.SameLine(const AEditor, AStored: string; ATabWidth: Integer): Boolean;
begin
  Result := TrimRight(TAtlasPairs.DisplayLine(AEditor, ATabWidth)) =
    TrimRight(TAtlasPairs.DisplayLine(AStored, ATabWidth));
end;

end.
