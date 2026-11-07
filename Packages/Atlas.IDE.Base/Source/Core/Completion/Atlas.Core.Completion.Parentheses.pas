unit Atlas.Core.Completion.Parentheses;

// Klammern beim Übernehmen (#430): Nach "Add(|)" verfolgt Atlas die
// automatisch eingefügte schließende Klammer in ihrer Zeile. Tippt man ")"
// direkt davor, wird die automatische übersprungen (entfernt), statt dass "))"
// entsteht. Jede Änderung der Zeile wird mit dem Stand davor verglichen:
// Einfügungen und Löschungen vor der Klammer verschieben sie; wird sie selbst
// gelöscht oder ändert sich mehr als ein Zeichen, endet die Verfolgung.
// Dazu der Auslöser für „Methode aus Aufruf anlegen“ (#472): "(" direkt
// hinter einem Bezeichner, der kein Schlüsselwort ist.

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
  private
    function FirstDifference(const ANew: string): Integer;
    /// <summary>Ein Zeichen an AIndex eingefügt: Lage nachführen; False beendet die Verfolgung (ARemoveAt: zu
    /// entfernende ")" oder -1).</summary>
    function Inserted(const ANew: string; AIndex: Integer; out ARemoveAt: Integer): Boolean;
    /// <summary>Ein Zeichen an AIndex gelöscht: Lage nachführen; False beendet die Verfolgung.</summary>
    function Deleted(const ANew: string; AIndex: Integer): Boolean;
  end;

  TAtlasParentheses = class
  public
    /// <summary>Klammern ergänzen? Nur Routinen mit Parametern, nicht wenn schon "(" folgt.</summary>
    class function Wanted(AIsRoutine, AHasParameters: Boolean; ANextChar: Char): Boolean; static;
    /// <summary>Steht vor dem Cursor (0-basiert ACharacter in ALine) ein "(" direkt hinter einem Bezeichner, der
    /// kein Schlüsselwort ist? Dann fragt Atlas, ob es die Methode anlegen soll (#472).</summary>
    class function CallOpened(const ALine: string; ACharacter: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Anfang (0-basiert) der Folge gleicher Zeichen, die an AIndex (0-basiert) in AText endet.</summary>
function RunStart(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result > 0) and (AText[Result] = AText[AIndex + 1]) do
  begin
    Dec(Result);
  end;
end;
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

function TAtlasAutoParen.FirstDifference(const ANew: string): Integer;
begin
  Result := 0;
  while (Result < Length(Text)) and (Result < Length(ANew)) and (Text[Result + 1] = ANew[Result + 1]) do
  begin
    Inc(Result);
  end;
end;

function TAtlasAutoParen.Inserted(const ANew: string; AIndex: Integer; out ARemoveAt: Integer): Boolean;
var
  mRunStart: Integer;
begin
  ARemoveAt := -1;
  // Ein Zeichen eingefügt; nur gültig, wenn der Rest gleich ist.
  if Copy(ANew, AIndex + 2, MaxInt) <> Copy(Text, AIndex + 1, MaxInt) then
  begin
    Exit(False);
  end;
  // Gleiche Zeichen davor: Die Einfügung kann irgendwo in dieser Folge liegen ("()" + ")" = "())").
  mRunStart := RunStart(ANew, AIndex);
  if (ANew[AIndex + 1] = ')') and (Close >= mRunStart) and (Close <= AIndex) then
  begin
    // ")" direkt vor der automatischen: eine der Klammern hinter dem Cursor entfernen.
    ARemoveAt := Close + 1;
    Exit(False);
  end;
  if AIndex <= Close then
  begin
    Inc(Close);
  end;
  Result := True;
end;

function TAtlasAutoParen.Deleted(const ANew: string; AIndex: Integer): Boolean;
var
  mRunStart: Integer;
begin
  if Copy(ANew, AIndex + 1, MaxInt) <> Copy(Text, AIndex + 2, MaxInt) then
  begin
    Exit(False);
  end;
  // Gelöscht in einer Folge gleicher Zeichen, zu der die automatische Klammer gehört: nicht eindeutig, aufhören.
  mRunStart := RunStart(Text, AIndex);
  if (Close >= mRunStart) and (Close <= AIndex) and (Text[AIndex + 1] = ')') then
  begin
    Exit(False);
  end;
  if AIndex < Close then
  begin
    Dec(Close);
  end;
  Result := True;
end;

procedure TAtlasAutoParen.Update(const ANew: string; out ARemoveAt: Integer);
var
  mIndex: Integer;
  mKeep: Boolean;
begin
  ARemoveAt := -1;
  if not Active then
  begin
    Exit;
  end;
  // Erste Abweichung (0-basiert).
  mIndex := FirstDifference(ANew);
  if Length(ANew) = Length(Text) + 1 then
  begin
    mKeep := Inserted(ANew, mIndex, ARemoveAt);
  end
  else if Length(ANew) = Length(Text) - 1 then
  begin
    mKeep := Deleted(ANew, mIndex);
  end
  else
  begin
    mKeep := ANew = Text;
  end;
  if mKeep then
  begin
    Text := ANew;
  end;
  if not mKeep or (Close < 0) or (Close >= Length(Text)) or (Text[Close + 1] <> ')') then
  begin
    Stop;
  end;
end;

{ TAtlasParentheses }

class function TAtlasParentheses.Wanted(AIsRoutine, AHasParameters: Boolean; ANextChar: Char): Boolean;
begin
  Result := AIsRoutine and AHasParameters and (ANextChar <> '(');
end;

class function TAtlasParentheses.CallOpened(const ALine: string; ACharacter: Integer): Boolean;
const
  cKeywords: array[0..22] of string = ('if', 'while', 'until', 'not', 'and', 'or', 'xor', 'then', 'do', 'of', 'in',
    'case', 'div', 'mod', 'procedure', 'function', 'array', 'set', 'record', 'with', 'is', 'as', 'inherited');
var
  mStart, mIndex: Integer;
  mWord: string;
begin
  Result := False;
  if (ACharacter < 2) or (ACharacter > Length(ALine)) or (ALine[ACharacter] <> '(') then
  begin
    Exit;
  end;
  mStart := ACharacter - 1;
  while (mStart >= 1) and CharInSet(ALine[mStart], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Dec(mStart);
  end;
  mWord := Copy(ALine, mStart + 1, ACharacter - 1 - mStart);
  if (mWord = '') or CharInSet(mWord[1], ['0'..'9']) then
  begin
    Exit;
  end;
  for mIndex := Low(cKeywords) to High(cKeywords) do
  begin
    if SameText(mWord, cKeywords[mIndex]) then
    begin
      Exit;
    end;
  end;
  // Kein Kommentar und kein String davor in der Zeile.
  if (Pos('//', Copy(ALine, 1, mStart)) > 0) or Odd(Length(Copy(ALine, 1, mStart)) -
    Length(StringReplace(Copy(ALine, 1, mStart), '''', '', [rfReplaceAll]))) then
  begin
    Exit;
  end;
  Result := True;
end;

end.
