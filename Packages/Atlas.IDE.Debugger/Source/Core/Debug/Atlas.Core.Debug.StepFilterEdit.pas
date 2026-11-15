unit Atlas.Core.Debug.StepFilterEdit;

// Entscheidungen des Schrittfilters (#850) außerhalb von Urteil und Ablauf, ohne IDE prüfbar (#1967): was ein F7
// für den Lauf bedeutet, ob ein Haltepunkt des Benutzers an der neuen Routine steht und wie „Routine überspringen“
// bzw. „nicht mehr überspringen“ die Muster ändern. Atlas.IDE.Debug.StepFilter fragt Debugger, Editor und Server
// und meldet die Texte.

interface

uses
  Atlas.Core.Debug.StepFilter;

{$SCOPEDENUMS ON}

type
  /// <summary>Was ein Schritt hinein für den Schrittfilter bedeutet: ohne Filter (Umschalt+F7, „Trotzdem
  /// hineinspringen“), eigener Schritt von Atlas im laufenden Lauf, neuer F7 des Benutzers.</summary>
  TAtlasStepTrace = (Bypass, OwnStep, UserStep);

  /// <summary>Ergebnis von „Routine überspringen“.</summary>
  TAtlasStepSkipOutcome = (Already, Added);

  /// <summary>Ergebnis von „nicht mehr überspringen“: filtert noch über ein Muster bzw. eine Art, Muster
  /// entfernt, wurde gar nicht übersprungen.</summary>
  TAtlasStepUnskipOutcome = (StillByPattern, StillByKind, Removed, NotSkipped);

  TAtlasStepSkipEdit = record
    Outcome: TAtlasStepSkipOutcome;
    /// <summary>Urteil vor der Änderung (Already) bzw. nach ihr (Unskip).</summary>
    Verdict: TAtlasStepVerdict;
    /// <summary>Muster nach der Änderung.</summary>
    Patterns: TArray<string>;
    /// <summary>Haben sich die Muster geändert (speichern)?</summary>
    Changed: Boolean;
  end;

  TAtlasStepUnskipEdit = record
    Outcome: TAtlasStepUnskipOutcome;
    Verdict: TAtlasStepVerdict;
    Patterns: TArray<string>;
    Changed: Boolean;
  end;

  /// <summary>Haltepunkt der IDE für BreakpointAt.</summary>
  TAtlasStepBreakpoint = record
    FileName: string;
    /// <summary>1-basiert wie in der IDE.</summary>
    Line: Integer;
    Enabled: Boolean;
    class function Create(const AFileName: string; ALine: Integer; AEnabled: Boolean): TAtlasStepBreakpoint;
      static;
  end;

  TAtlasStepFilterEdit = class
  public
    /// <summary>Art des Schritts: Bis zur nächsten Quelltextzeile (AToSource) oder ein ausdrücklicher Umweg
    /// (ABypass) gehen ohne Filter; ein Schritt von Atlas selbst (AFromAtlas) gehört zum laufenden Lauf.</summary>
    class function Trace(AToSource, ABypass, AFromAtlas: Boolean): TAtlasStepTrace; static;
    /// <summary>Gehört der Halt AStopCount zum Lauf, der beim Halt AStepStop weiterlief?</summary>
    class function BelongsToRun(AStopCount, AStepStop: Integer): Boolean; static;
    /// <summary>Steht ein eingeschalteter Haltepunkt an Zeile ALine (0-basiert) von AFileName bzw. der gefundenen
    /// Quelle AResolved?</summary>
    class function BreakpointAt(const ABreakpoints: TArray<TAtlasStepBreakpoint>; const AFileName,
      AResolved: string; ALine: Integer): Boolean; static;
    /// <summary>ARoutine überspringen: schon gefiltert (Already), sonst Muster mit ihrem Namen.</summary>
    class function Skip(const AOptions: TAtlasStepFilterOptions; const ARoutine: TAtlasStepRoutine): TAtlasStepSkipEdit;
      static;
    /// <summary>ARoutine nicht mehr überspringen: ihr Muster entfernen; was danach noch filtert, sagt Outcome.
    /// </summary>
    class function Unskip(const AOptions: TAtlasStepFilterOptions;
      const ARoutine: TAtlasStepRoutine): TAtlasStepUnskipEdit; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.StepFilter;

{ TAtlasStepBreakpoint }

class function TAtlasStepBreakpoint.Create(const AFileName: string; ALine: Integer;
  AEnabled: Boolean): TAtlasStepBreakpoint;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Enabled := AEnabled;
end;

{ TAtlasStepFilterEdit }

class function TAtlasStepFilterEdit.Trace(AToSource, ABypass, AFromAtlas: Boolean): TAtlasStepTrace;
begin
  if AToSource or ABypass then
  begin
    Result := TAtlasStepTrace.Bypass;
  end
  else if AFromAtlas then
  begin
    Result := TAtlasStepTrace.OwnStep;
  end
  else
  begin
    Result := TAtlasStepTrace.UserStep;
  end;
end;

class function TAtlasStepFilterEdit.BelongsToRun(AStopCount, AStepStop: Integer): Boolean;
begin
  // Nur der Halt direkt nach dem Schritt bzw. nach „Bis zur Rückkehr“.
  Result := AStopCount = AStepStop + 1;
end;

class function TAtlasStepFilterEdit.BreakpointAt(const ABreakpoints: TArray<TAtlasStepBreakpoint>;
  const AFileName, AResolved: string; ALine: Integer): Boolean;
var
  mBreakpoint: TAtlasStepBreakpoint;
begin
  Result := False;
  for mBreakpoint in ABreakpoints do
  begin
    if mBreakpoint.Enabled and (mBreakpoint.Line = ALine + 1) and
      (SameText(mBreakpoint.FileName, AFileName) or SameText(mBreakpoint.FileName, AResolved)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasStepFilterEdit.Skip(const AOptions: TAtlasStepFilterOptions;
  const ARoutine: TAtlasStepRoutine): TAtlasStepSkipEdit;
begin
  Result := Default(TAtlasStepSkipEdit);
  Result.Verdict := TAtlasStepFilter.Verdict(AOptions, ARoutine);
  Result.Patterns := AOptions.Patterns;
  if Result.Verdict.Filtered then
  begin
    Result.Outcome := TAtlasStepSkipOutcome.Already;
    Exit;
  end;
  Result.Outcome := TAtlasStepSkipOutcome.Added;
  Result.Patterns := TStepFilterNames.WithPattern(AOptions.Patterns, ARoutine.Name);
  Result.Changed := True;
end;

class function TAtlasStepFilterEdit.Unskip(const AOptions: TAtlasStepFilterOptions;
  const ARoutine: TAtlasStepRoutine): TAtlasStepUnskipEdit;
var
  mOptions: TAtlasStepFilterOptions;
begin
  Result := Default(TAtlasStepUnskipEdit);
  mOptions := AOptions;
  Result.Changed := TStepFilterNames.IndexOfPattern(mOptions.Patterns, ARoutine.Name) >= 0;
  if Result.Changed then
  begin
    mOptions.Patterns := TStepFilterNames.WithoutPattern(mOptions.Patterns, ARoutine.Name);
  end;
  Result.Patterns := mOptions.Patterns;
  // Weitere Muster oder Arten bleiben, wie sie sind: Der Benutzer erfährt, was noch filtert.
  Result.Verdict := TAtlasStepFilter.Verdict(mOptions, ARoutine);
  case Result.Verdict.Kind of
    TAtlasStepVerdictKind.Pattern:
      Result.Outcome := TAtlasStepUnskipOutcome.StillByPattern;
    TAtlasStepVerdictKind.Kind:
      Result.Outcome := TAtlasStepUnskipOutcome.StillByKind;
  else
    if Result.Changed then
    begin
      Result.Outcome := TAtlasStepUnskipOutcome.Removed;
    end
    else
    begin
      Result.Outcome := TAtlasStepUnskipOutcome.NotSkipped;
    end;
  end;
end;

end.
