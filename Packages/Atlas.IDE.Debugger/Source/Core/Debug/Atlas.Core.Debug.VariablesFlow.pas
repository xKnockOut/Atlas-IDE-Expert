unit Atlas.Core.Debug.VariablesFlow;

// Entscheidungen des Fensters „Variablen“ (#853), ohne IDE prüfbar (#1967): Text unten im Fenster (ohne Server,
// Anzahl, Stand der Suche), vorige Zeile für atlas.server.debugVariables und ob ein Ausdruck als neue Überwachung
// taugt. Die IDE (Atlas.IDE.Debug.Variables) liest den Halt, fragt den Server und zeigt an.

interface

uses
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables;

{$SCOPEDENUMS ON}

type
  /// <summary>Was unten im Fenster steht.</summary>
  TAtlasVariablesStatusKind = (NoServer, Count, Searching, Truncated, Hits);

  TAtlasVariablesStatus = record
    Kind: TAtlasVariablesStatusKind;
    /// <summary>Zeilen des Reiters (Count).</summary>
    Count: Integer;
    /// <summary>Auswertungen der Suche (Searching, Truncated).</summary>
    Evaluations: Integer;
    /// <summary>Treffer der Suche (Truncated, Hits).</summary>
    Hits: Integer;
  end;

  TAtlasVariablesFlow = class
  public
    /// <summary>Text unten für den Reiter ATab mit ACount Zeilen: ohne Server (nicht im Reiter Überwachung) der
    /// Hinweis, ohne Suche die Anzahl, sonst der Stand der Suche ASearch.</summary>
    class function Status(ASearch: TAtlasVariableSearch; ATab: TAtlasVariablesTab; ACount: Integer;
      ASearchDone, AHasServer: Boolean): TAtlasVariablesStatus; static;
    /// <summary>Zeile des vorigen Halts für den Server: nur in derselben Datei, sonst -1.</summary>
    class function PreviousLine(const APreviousFile: string; APreviousLine: Integer;
      const AFileName: string): Integer; static;
    /// <summary>Taugt AExpression als neue Überwachung in AWatches (nicht leer, noch nicht da)?</summary>
    class function CanAddWatch(AWatches: TAtlasEvalList; const AExpression: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasVariablesFlow }

class function TAtlasVariablesFlow.Status(ASearch: TAtlasVariableSearch; ATab: TAtlasVariablesTab; ACount: Integer;
  ASearchDone, AHasServer: Boolean): TAtlasVariablesStatus;
begin
  Result := Default(TAtlasVariablesStatus);
  Result.Count := ACount;
  Result.Evaluations := ASearch.Evaluations;
  Result.Hits := ASearch.HitCount;
  if not AHasServer and (ATab <> TAtlasVariablesTab.Watch) then
  begin
    Result.Kind := TAtlasVariablesStatusKind.NoServer;
  end
  else if not ASearch.Active then
  begin
    Result.Kind := TAtlasVariablesStatusKind.Count;
  end
  else if not ASearchDone then
  begin
    Result.Kind := TAtlasVariablesStatusKind.Searching;
  end
  else if ASearch.Truncated then
  begin
    Result.Kind := TAtlasVariablesStatusKind.Truncated;
  end
  else
  begin
    Result.Kind := TAtlasVariablesStatusKind.Hits;
  end;
end;

class function TAtlasVariablesFlow.PreviousLine(const APreviousFile: string; APreviousLine: Integer;
  const AFileName: string): Integer;
begin
  Result := -1;
  if SameText(APreviousFile, AFileName) then
  begin
    Result := APreviousLine;
  end;
end;

class function TAtlasVariablesFlow.CanAddWatch(AWatches: TAtlasEvalList; const AExpression: string): Boolean;
begin
  Result := (Trim(AExpression) <> '') and (AWatches.Find(Trim(AExpression)) = nil);
end;

end.
