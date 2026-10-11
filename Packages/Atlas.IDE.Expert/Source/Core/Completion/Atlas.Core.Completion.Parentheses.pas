unit Atlas.Core.Completion.Parentheses;

// Klammern beim Übernehmen (#430): Nach "Add(|)" verfolgt Atlas die
// automatisch eingefügte schließende Klammer in ihrer Zeile. Tippt man ")"
// direkt davor, wird die automatische übersprungen (entfernt), statt dass "))"
// entsteht. Jede Änderung der Zeile wird mit dem Stand davor verglichen:
// Einfügungen und Löschungen vor der Klammer verschieben sie; wird sie selbst
// gelöscht oder ändert sich mehr als ein Zeichen, endet die Verfolgung.

interface

type
  TAtlasAutoParen = record
    /// <summary>Zeile (1-basiert wie in der IDE); 0 = keine Verfolgung.</summary>
    Line: Integer;
    /// <summary>0-basierter Index der automatischen ")" in der Zeile.</summary>
    Close: Integer;
    /// <summary>Zeile, wie sie nach der letzten bekannten Änderung aussah.</summary>
    Text: string;
    class function Start(ALine, AClose: Integer; const AText: string): TAtlasAutoParen; static;
    function Active: Boolean;
    procedure Stop;
    /// <summary>Neue Fassung ANew der Zeile: Lage nachführen. ARemoveAt: 0-basierter Index einer zu
    /// entfernenden ")" (die automatische nach einer getippten), sonst -1.</summary>
    procedure Update(const ANew: string; out ARemoveAt: Integer);
  end;

  TAtlasParentheses = class
  public
    /// <summary>Klammern ergänzen? Nur Routinen mit Parametern, nicht wenn schon "(" folgt.</summary>
    class function Wanted(AIsRoutine, AHasParameters: Boolean; ANextChar: Char): Boolean; static;
  end;

implementation

{ TAtlasAutoParen }

class function TAtlasAutoParen.Start(ALine, AClose: Integer; const AText: string): TAtlasAutoParen;
begin
  Result.Line := ALine;
  Result.Close := AClose;
  Result.Text := AText;
end;

function TAtlasAutoParen.Active: Boolean;
begin
  Result := Line > 0;
end;

procedure TAtlasAutoParen.Stop;
begin
  Line := 0;
  Close := -1;
  Text := '';
end;

procedure TAtlasAutoParen.Update(const ANew: string; out ARemoveAt: Integer);
var
  Index, RunStart: Integer;
begin
  ARemoveAt := -1;
  if not Active then
    Exit;
  // Erste Abweichung (0-basiert).
  Index := 0;
  while (Index < Length(Text)) and (Index < Length(ANew)) and (Text[Index + 1] = ANew[Index + 1]) do
    Inc(Index);
  if Length(ANew) = Length(Text) + 1 then
  begin
    // Ein Zeichen eingefügt; nur gültig, wenn der Rest gleich ist.
    if Copy(ANew, Index + 2, MaxInt) <> Copy(Text, Index + 1, MaxInt) then
    begin
      Stop;
      Exit;
    end;
    // Gleiche Zeichen davor: Die Einfügung kann irgendwo in dieser Folge liegen ("()" + ")" = "())").
    RunStart := Index;
    while (RunStart > 0) and (ANew[RunStart] = ANew[Index + 1]) do
      Dec(RunStart);
    if (ANew[Index + 1] = ')') and (Close >= RunStart) and (Close <= Index) then
    begin
      // ")" direkt vor der automatischen: eine der Klammern hinter dem Cursor entfernen.
      ARemoveAt := Close + 1;
      Stop;
      Exit;
    end;
    if Index <= Close then
      Inc(Close);
  end
  else if Length(ANew) = Length(Text) - 1 then
  begin
    if Copy(ANew, Index + 1, MaxInt) <> Copy(Text, Index + 2, MaxInt) then
    begin
      Stop;
      Exit;
    end;
    // Gelöscht in einer Folge gleicher Zeichen, zu der die automatische Klammer gehört: nicht eindeutig, aufhören.
    RunStart := Index;
    while (RunStart > 0) and (Text[RunStart] = Text[Index + 1]) do
      Dec(RunStart);
    if (Close >= RunStart) and (Close <= Index) and (Text[Index + 1] = ')') then
    begin
      Stop;
      Exit;
    end;
    if Index < Close then
      Dec(Close);
  end
  else if ANew <> Text then
  begin
    Stop;
    Exit;
  end;
  Text := ANew;
  if (Close < 0) or (Close >= Length(Text)) or (Text[Close + 1] <> ')') then
    Stop;
end;

{ TAtlasParentheses }

class function TAtlasParentheses.Wanted(AIsRoutine, AHasParameters: Boolean; ANextChar: Char): Boolean;
begin
  Result := AIsRoutine and AHasParameters and (ANextChar <> '(');
end;

end.
