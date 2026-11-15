unit Atlas.Core.Signature.EditorPlan;

// Entscheidungen des Parameter-Hints im Editor (Atlas.IDE.Signature.Editor), ohne VCL und Open Tools API: welche Taste
// der Hint nimmt, was nach einer Bewegung des Cursors geschieht (schließen, äußeren Aufruf zeigen, Parameter
// nachziehen, #438), ob die Antwort des Servers noch passt, die im Detailpanel gewählte Überladung (#425), Wieder
// öffnen nach entfernter „)“ (nicht nach Esc), die Ruhe vor einer neuen Platzhalter-Anfrage (#451), die linke Kante
// an der öffnenden Klammer und das Mitwandern beim Scrollen.

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  Atlas.Core.Signature.CallScanner;

type
  /// <summary>Taste im offenen Hint.</summary>
  TAtlasSignatureKey = (
    /// <summary>Nicht nehmen.</summary>
    None,
    /// <summary>Esc: schließen und für diesen Aufruf nicht wieder von selbst öffnen.</summary>
    Dismiss,
    /// <summary>Alt+↑: vorige Überladung.</summary>
    PreviousOverload,
    /// <summary>Alt+↓: nächste Überladung.</summary>
    NextOverload);

  /// <summary>Was nach einer Bewegung des Cursors mit dem offenen Hint geschieht.</summary>
  TAtlasSignatureStep = (
    /// <summary>Aufruf verlassen (auch durch „)“) oder in einen anderen gewechselt.</summary>
    Close,
    /// <summary>Inneren Aufruf nach vorn verlassen: den äußeren zeigen (#438).</summary>
    ShowOuter,
    /// <summary>Im selben Aufruf: Parameter nachziehen.</summary>
    Update);

  /// <summary>Zeile vor der letzten Änderung (Wieder öffnen nach entfernter „)“).</summary>
  TAtlasSignatureLastLine = record
    FileName: string;
    Line: Integer;
    Text: string;
  end;

  /// <summary>Mit Esc geschlossener Aufruf.</summary>
  TAtlasSignatureDismissed = record
    FileName: string;
    OpenParen: Integer;
  end;

  /// <summary>Stand der letzten Platzhalter-Anfrage (#451): Text, Cursor und Takte bis zur nächsten.</summary>
  TAtlasSignatureFormatState = record
    Text: string;
    Caret: Integer;
    Due: Integer;
  end;

  TAtlasSignatureEditorPlan = record
  public const
    /// <summary>Tastencodes wie in Winapi.Windows.</summary>
    cVkEscape = $1B;
    cVkUp = $26;
    cVkDown = $28;
    /// <summary>Takte ohne Änderung, bis die Platzhalter neu angefragt werden (#451).</summary>
    cFormatQuietTicks = 3;
  public
    /// <summary>Taste AKey mit AShift bei offenem Hint (AActive) mit ACount Überladungen.</summary>
    class function Key(AKey: Word; AShift: TShiftState; AActive: Boolean; ACount: Integer): TAtlasSignatureKey;
      static;
    /// <summary>Schritt für den Aufruf ASite am Cursor, wenn der Hint an der Klammer AOpenParen hängt.</summary>
    class function Step(const ASite: TAtlasCallSite; AOpenParen: Integer): TAtlasSignatureStep; static;
    /// <summary>Gilt die Antwort des Servers noch? Der Cursor steht im selben Aufruf (Klammer AOpenParen).</summary>
    class function StillAtCall(const ASite: TAtlasCallSite; AOpenParen: Integer): Boolean; static;
    /// <summary>Im Detailpanel gewählte Überladung AIndex für APreferredName übernehmen, wenn der Aufruf AName heißt
    /// und es ACount Signaturen gibt?</summary>
    class function TakesOverload(const APreferredName, AName: string; AIndex, ACount: Integer): Boolean; static;
    /// <summary>Nach einer entfernten „)“ wieder öffnen: Aufruf ASite in AFileName, nicht der mit Esc geschlossene.
    /// </summary>
    class function Reopens(const ASite: TAtlasCallSite; const ADismissed: TAtlasSignatureDismissed;
      const AFileName: string): Boolean; static;
    /// <summary>Hat die Änderung in AFileName, Zeile ALine (neuer Text ALineText) bei geschlossenem Hint genau eine
    /// „)“ entfernt? ALast ist die Zeile vor der Änderung.</summary>
    class function RemovedParen(const ALast: TAtlasSignatureLastLine; const AFileName: string; ALine: Integer;
      const ALineText: string; AActive: Boolean): Boolean; static;
    /// <summary>Nächster Takt für die Platzhalter (#451): True, wenn nach Ruhe jetzt neu angefragt wird. Ändern sich
    /// Text oder Cursor, beginnt die Ruhe neu.</summary>
    class function FormatDue(var AState: TAtlasSignatureFormatState; const AText: string; ACaret: Integer): Boolean;
      static;
    /// <summary>Text von der öffnenden Klammer AOpenParen bis zum Cursor ACaret, wenn sie in derselben Zeile davor
    /// steht (ACharacter Zeichen vor dem Cursor in der Zeile); sonst ''. Daran rückt die linke Kante des Hints.
    /// </summary>
    class function ParenRun(const AText: string; ACaret, AOpenParen, ACharacter: Integer): string; static;
    /// <summary>Verschiebung des Hints in Pixeln, wenn die oberste Zeile von AOpenedTop nach ANowTop wechselt.
    /// </summary>
    class function ScrollShift(AOpenedTop, ANowTop, ARowHeight: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasSignatureEditorPlan }

class function TAtlasSignatureEditorPlan.Key(AKey: Word; AShift: TShiftState; AActive: Boolean; ACount: Integer):
  TAtlasSignatureKey;
begin
  Result := TAtlasSignatureKey.None;
  if not AActive then
  begin
    Exit;
  end;
  if (AKey = cVkEscape) and (AShift = []) then
  begin
    Result := TAtlasSignatureKey.Dismiss;
  end
  else if (AShift = [ssAlt]) and (ACount > 1) and (AKey = cVkUp) then
  begin
    Result := TAtlasSignatureKey.PreviousOverload;
  end
  else if (AShift = [ssAlt]) and (ACount > 1) and (AKey = cVkDown) then
  begin
    Result := TAtlasSignatureKey.NextOverload;
  end;
end;

class function TAtlasSignatureEditorPlan.Step(const ASite: TAtlasCallSite; AOpenParen: Integer):
  TAtlasSignatureStep;
begin
  if not ASite.Found or (ASite.OpenParen > AOpenParen) then
  begin
    Result := TAtlasSignatureStep.Close;
  end
  else if ASite.OpenParen < AOpenParen then
  begin
    Result := TAtlasSignatureStep.ShowOuter;
  end
  else
  begin
    Result := TAtlasSignatureStep.Update;
  end;
end;

class function TAtlasSignatureEditorPlan.StillAtCall(const ASite: TAtlasCallSite; AOpenParen: Integer): Boolean;
begin
  Result := ASite.Found and (ASite.OpenParen = AOpenParen);
end;

class function TAtlasSignatureEditorPlan.TakesOverload(const APreferredName, AName: string; AIndex,
  ACount: Integer): Boolean;
begin
  Result := (APreferredName <> '') and SameText(APreferredName, AName) and (AIndex > 0) and (AIndex < ACount);
end;

class function TAtlasSignatureEditorPlan.Reopens(const ASite: TAtlasCallSite;
  const ADismissed: TAtlasSignatureDismissed; const AFileName: string): Boolean;
begin
  Result := ASite.Found and not ((ASite.OpenParen = ADismissed.OpenParen) and
    SameText(AFileName, ADismissed.FileName));
end;

class function TAtlasSignatureEditorPlan.RemovedParen(const ALast: TAtlasSignatureLastLine; const AFileName: string;
  ALine: Integer; const ALineText: string; AActive: Boolean): Boolean;
begin
  Result := not AActive and SameText(AFileName, ALast.FileName) and (ALine = ALast.Line) and
    TAtlasCallScanner.RemovedClosingParen(ALast.Text, ALineText);
end;

class function TAtlasSignatureEditorPlan.FormatDue(var AState: TAtlasSignatureFormatState; const AText: string;
  ACaret: Integer): Boolean;
begin
  Result := False;
  // Erst nach kurzer Ruhe: Jede Anfrage gleicht den Puffer mit dem Server ab.
  if (ACaret <> AState.Caret) or (AText <> AState.Text) then
  begin
    AState.Text := AText;
    AState.Caret := ACaret;
    AState.Due := cFormatQuietTicks;
    Exit;
  end;
  if AState.Due <= 0 then
  begin
    Exit;
  end;
  Dec(AState.Due);
  Result := AState.Due = 0;
end;

class function TAtlasSignatureEditorPlan.ParenRun(const AText: string; ACaret, AOpenParen,
  ACharacter: Integer): string;
begin
  Result := '';
  if ACaret - AOpenParen <= ACharacter then
  begin
    Result := Copy(AText, AOpenParen + 1, ACaret - AOpenParen);
  end;
end;

class function TAtlasSignatureEditorPlan.ScrollShift(AOpenedTop, ANowTop, ARowHeight: Integer): Integer;
begin
  Result := (AOpenedTop - ANowTop) * ARowHeight;
end;

end.
