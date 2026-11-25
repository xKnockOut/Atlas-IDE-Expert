unit Atlas.Plugin.Hover.Contract.DebugValue;

// Wert eines Ausdrucks im angehaltenen Debugger (#891), wie ihn der Hover
// zeigt und die Auswertung der Debug-Schicht liefert (IAtlasDebugEvaluator im
// Modul Debugger): Zustand (ausstehend, Wert, Fehler), Erklärung eines Fehlers
// „kein Zugriff“ (#840), Aktionen, alter Wert und aufgeklappte Zeilen (#895).
// Die Texte setzt die Debug-Schicht; hier stehen nur die Daten. Ohne VCL und
// Open Tools API.

interface

type
  {$SCOPEDENUMS ON}
  TAtlasDebugValueState = (None, Pending, Value, Failed);
  {$SCOPEDENUMS OFF}

  /// <summary>Korrektur unter der Erklärung (#840): Kennung der Debug-Schicht und Beschriftung.</summary>
  TAtlasDebugValueFix = record
    Id: Integer;
    Caption: string;
    class function Create(AId: Integer; const ACaption: string): TAtlasDebugValueFix; static;
  end;

  /// <summary>Erklärung eines Fehlers „kein Zugriff“ (#840); Caption = '' ohne.</summary>
  TAtlasDebugValueNote = record
    /// <summary>„‹kein Zugriff›“.</summary>
    Caption: string;
    /// <summary>Die Ursache wird noch ermittelt (Anfrage an den Server).</summary>
    Pending: Boolean;
    Reason: string;
    /// <summary>Herkunft des Schalters („{$O+} in Kunden.pas, Zeile 12“); '' ohne.</summary>
    Origin: string;
    /// <summary>Bei unbekannter Ursache: die geprüften Punkte.</summary>
    Checked: TArray<string>;
    Fixes: TArray<TAtlasDebugValueFix>;
  end;

  /// <summary>Zeile des aufgeklappten Werts (#895). Expandable: lässt sich auf- bzw. zuklappen (Expanded);
  /// Lazy: Getter, erst nach Klick ausgewertet; More: „weitere …“; OldText: Wert beim vorigen Halt, '' wenn
  /// unverändert.</summary>
  TAtlasDebugValueRow = record
    Expression: string;
    Name: string;
    Text: string;
    OldText: string;
    Depth: Integer;
    Expandable: Boolean;
    Expanded: Boolean;
    Pending: Boolean;
    Lazy: Boolean;
    More: Boolean;
  end;

  /// <summary>Wert eines Ausdrucks im angehaltenen Debugger.</summary>
  TAtlasDebugValue = record
  public const
    /// <summary>Höchstlänge eines ausgewerteten Werts.</summary>
    cMaxTextLength = 2000;
  public
    State: TAtlasDebugValueState;
    Expression: string;
    Text: string;
    /// <summary>Erklärung eines Fehlers „kein Zugriff“ (#840).</summary>
    Note: TAtlasDebugValueNote;
    /// <summary>Aktionen unter dem Wert (Anheften #526); Id und Beschriftung setzt die Debug-Schicht.</summary>
    Actions: TArray<TAtlasDebugValueFix>;
    /// <summary>Wert beim vorigen Halt, wenn er sich geändert hat (#895); '' sonst.</summary>
    OldText: string;
    /// <summary>Lässt sich aufklappen (#895); Rows sind dann die sichtbaren Kinder.</summary>
    Expandable: Boolean;
    Expanded: Boolean;
    Rows: TArray<TAtlasDebugValueRow>;
    class function Pending(const AExpression: string): TAtlasDebugValue; static;
    /// <summary>Ausgewerteter Wert, auf cMaxTextLength gekürzt.</summary>
    class function Evaluated(const AExpression, AText: string): TAtlasDebugValue; static;
    class function Failed(const AExpression, AText: string): TAtlasDebugValue; static;
    /// <summary>Zeigt der Tooltip den Abschnitt (ausstehend, Wert oder erklärter Fehler)?</summary>
    function Visible: Boolean;
    /// <summary>Fehler mit Erklärung „kein Zugriff“ (#840).</summary>
    function Explained: Boolean;
    /// <summary>„Ausdruck = Wert“ als Klartext für den Tooltip der IDE; '' ohne Wert.</summary>
    function PlainText: string;
    /// <summary>Höchstens AMaxLength Zeichen, gekürzt mit „…“.</summary>
    class function Shorten(const AText: string; AMaxLength: Integer): string; static;
  end;

implementation

{ TAtlasDebugValue }

class function TAtlasDebugValue.Pending(const AExpression: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.State := TAtlasDebugValueState.Pending;
  Result.Expression := AExpression;
end;

class function TAtlasDebugValue.Evaluated(const AExpression, AText: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.State := TAtlasDebugValueState.Value;
  Result.Expression := AExpression;
  Result.Text := Shorten(AText, cMaxTextLength);
end;

class function TAtlasDebugValue.Failed(const AExpression, AText: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.State := TAtlasDebugValueState.Failed;
  Result.Expression := AExpression;
  Result.Text := AText;
end;

function TAtlasDebugValue.Visible: Boolean;
begin
  Result := (Expression <> '') and ((State in [TAtlasDebugValueState.Pending, TAtlasDebugValueState.Value]) or
    Explained);
end;

function TAtlasDebugValue.Explained: Boolean;
begin
  Result := (State = TAtlasDebugValueState.Failed) and (Note.Caption <> '');
end;

function TAtlasDebugValue.PlainText: string;
begin
  Result := '';
  if Expression = '' then
  begin
    Exit;
  end;
  if State = TAtlasDebugValueState.Value then
  begin
    Result := Expression + ' = ' + Text;
  end
  else if Explained then
  begin
    Result := Expression + ' = ' + Note.Caption;
    if Note.Reason <> '' then
    begin
      Result := Result + sLineBreak + Note.Reason;
    end;
  end;
end;

{ TAtlasDebugValueFix }

class function TAtlasDebugValueFix.Create(AId: Integer; const ACaption: string): TAtlasDebugValueFix;
begin
  Result.Id := AId;
  Result.Caption := ACaption;
end;

class function TAtlasDebugValue.Shorten(const AText: string; AMaxLength: Integer): string;
begin
  Result := AText;
  if (AMaxLength > 0) and (Length(Result) > AMaxLength) then
  begin
    Result := Copy(Result, 1, AMaxLength) + ' …';
  end;
end;

end.
