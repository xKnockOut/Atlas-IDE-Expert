unit Atlas.Core.Completion.Word;

// Wortgrenzen in einer Editorzeile für die Vervollständigung: Anfang des
// Bezeichners vor dem Cursor (Präfix) und sein Ende hinter dem Cursor. Beim
// Übernehmen mitten im Wort wird das ganze Wort ersetzt, sonst bliebe der Rest
// stehen ("TStringL|ist" + TStringList → "TStringListist").

interface

type
  TAtlasWord = class
  public
    class function IsIdentifierChar(AChar: Char): Boolean; static;
    /// <summary>Anfang des Bezeichners vor ACharacter (0-basiert, Zeichen vor dem Cursor).</summary>
    class function StartBefore(const ALine: string; ACharacter: Integer): Integer; static;
    /// <summary>Ende des Bezeichners ab ACharacter (0-basiert, exklusiv); ACharacter, wenn dort keiner
    /// weitergeht.</summary>
    class function EndAfter(const ALine: string; ACharacter: Integer): Integer; static;
    /// <summary>Steht der Cursor (ACharacter Zeichen vor ihm) im ersten String-Argument von FieldByName,
    /// FindField oder ParamByName (#461)? Dort öffnet Atlas die Vervollständigung trotz String (#435).</summary>
    class function InDataNameString(const ALine: string; ACharacter: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.RegularExpressions;

{ TAtlasWord }

class function TAtlasWord.IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

class function TAtlasWord.StartBefore(const ALine: string; ACharacter: Integer): Integer;
begin
  Result := ACharacter;
  if Result > Length(ALine) then
  begin
    Result := Length(ALine);
  end;
  while (Result > 0) and IsIdentifierChar(ALine[Result]) do
  begin
    Dec(Result);
  end;
end;

class function TAtlasWord.EndAfter(const ALine: string; ACharacter: Integer): Integer;
begin
  Result := ACharacter;
  if Result < 0 then
  begin
    Result := 0;
  end;
  while (Result < Length(ALine)) and IsIdentifierChar(ALine[Result + 1]) do
  begin
    Inc(Result);
  end;
end;

class function TAtlasWord.InDataNameString(const ALine: string; ACharacter: Integer): Boolean;
var
  mIndex, mOpen: Integer;
begin
  // Öffnendes Anführungszeichen des Strings, in dem der Cursor steht; '' zählt als Inhalt.
  mOpen := 0;
  mIndex := 1;
  while (mIndex <= ACharacter) and (mIndex <= Length(ALine)) do
  begin
    if ALine[mIndex] = '''' then
    begin
      if mOpen = 0 then
      begin
        mOpen := mIndex;
      end
      else if (mIndex < Length(ALine)) and (mIndex < ACharacter) and (ALine[mIndex + 1] = '''') then
      begin
        Inc(mIndex);
      end
      else
      begin
        mOpen := 0;
      end;
    end
    else if (mOpen = 0) and (ALine[mIndex] = '/') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = '/') then
    begin
      Exit(False);
    end;
    Inc(mIndex);
  end;
  Result := (mOpen > 0) and TRegEx.IsMatch(Copy(ALine, 1, mOpen - 1),
    '\w\s*\.\s*(FieldByName|FindField|ParamByName)\s*\(\s*$', [roIgnoreCase]);
end;

end.
