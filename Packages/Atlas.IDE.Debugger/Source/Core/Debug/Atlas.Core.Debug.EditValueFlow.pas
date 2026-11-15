unit Atlas.Core.Debug.EditValueFlow;

// Entscheidungen beim Ändern von Werten (#868) außerhalb von Prüfung und Ablage, ohne IDE prüfbar (#1967): Stelle des
// Werts, welche Aktion hierher gehört, ob eine Antwort noch zählt, welcher Text gesetzt wird, was „Rückgängig“ setzt
// und was gemerkt wird. Atlas.IDE.Debug.EditValue fragt Editor, Debugger und Server.

interface

uses
  Atlas.Core.Debug.EditValue;

type
  /// <summary>Stelle des Werts: Datei, Zeile (1-basiert), Ausdruck und angezeigter Wert. Direct: neuer Wert ohne
  /// Dialog (Umschalten, Rückgängig); Undoing: Rückgängig, die Änderung wird danach vergessen.</summary>
  TAtlasEditPlace = record
    FileName: string;
    Line: Integer;
    Expression: string;
    Value: string;
    Direct: string;
    Undoing: Boolean;
  end;

  TAtlasEditValueFlow = class
  public const
    /// <summary>Ids der Aktionen im Debug-Hover.</summary>
    cEditAction = 868;
    cToggleAction = 8681;
    cUndoAction = 8682;
  public
    /// <summary>Gehört die Aktion AAction zu „Werte ändern“?</summary>
    class function OwnAction(AAction: Integer): Boolean; static;
    /// <summary>Zählt die Antwort zur Anfrage ARequest noch: keine neuere (ACurrent), Prozess steht (AStopped)?
    /// </summary>
    class function Current(ARequest, ACurrent: Integer; AStopped: Boolean): Boolean; static;
    /// <summary>Zu setzender Text: ANew; bei Umschalten und Rückgängig (ADirect) wie der Dialog umgesetzt, wenn die
    /// Prüfung ACheck gelingt.</summary>
    class function Final(const ADirect, ANew: string; const ACheck: TAtlasEditCheck): string; static;
    /// <summary>APlace für „Rückgängig“ aus der gemerkten Änderung AChange: alter Wert als Direct.</summary>
    class procedure ApplyUndo(var APlace: TAtlasEditPlace; const AChange: TAtlasEditChange); static;
    /// <summary>Gemerkte Änderung: ANew bzw. der Wert, den der Debugger nach dem Ändern meldet (AOutcome).</summary>
    class function ChangeOf(const APlace: TAtlasEditPlace; const ANew, AOutcome: string): TAtlasEditChange; static;
  end;

implementation

{ TAtlasEditValueFlow }

class function TAtlasEditValueFlow.OwnAction(AAction: Integer): Boolean;
begin
  Result := (AAction = cEditAction) or (AAction = cToggleAction) or (AAction = cUndoAction);
end;

class function TAtlasEditValueFlow.Current(ARequest, ACurrent: Integer; AStopped: Boolean): Boolean;
begin
  Result := (ARequest = ACurrent) and AStopped;
end;

class function TAtlasEditValueFlow.Final(const ADirect, ANew: string; const ACheck: TAtlasEditCheck): string;
begin
  Result := ANew;
  // Umschalten und Rückgängig: wie der Dialog umsetzen (Typpräfix, Hochkommas), sonst unverändert.
  if (ADirect <> '') and ACheck.Ok then
  begin
    Result := ACheck.Value;
  end;
end;

class procedure TAtlasEditValueFlow.ApplyUndo(var APlace: TAtlasEditPlace; const AChange: TAtlasEditChange);
begin
  APlace.Line := AChange.Line;
  APlace.Value := AChange.NewValue;
  APlace.Direct := AChange.OldValue;
  APlace.Undoing := True;
end;

class function TAtlasEditValueFlow.ChangeOf(const APlace: TAtlasEditPlace; const ANew,
  AOutcome: string): TAtlasEditChange;
begin
  Result := Default(TAtlasEditChange);
  Result.FileName := APlace.FileName;
  Result.Line := APlace.Line;
  Result.Expression := APlace.Expression;
  Result.OldValue := APlace.Value;
  Result.NewValue := ANew;
  if AOutcome <> '' then
  begin
    Result.NewValue := AOutcome;
  end;
end;

end.
