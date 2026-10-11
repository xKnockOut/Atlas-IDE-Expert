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
    /// <summary>Ende des Bezeichners ab ACharacter (0-basiert, exklusiv); ACharacter, wenn dort keiner weitergeht.</summary>
    class function EndAfter(const ALine: string; ACharacter: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasWord }

class function TAtlasWord.IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

class function TAtlasWord.StartBefore(const ALine: string; ACharacter: Integer): Integer;
begin
  Result := ACharacter;
  if Result > Length(ALine) then
    Result := Length(ALine);
  while (Result > 0) and IsIdentifierChar(ALine[Result]) do
    Dec(Result);
end;

class function TAtlasWord.EndAfter(const ALine: string; ACharacter: Integer): Integer;
begin
  Result := ACharacter;
  if Result < 0 then
    Result := 0;
  while (Result < Length(ALine)) and IsIdentifierChar(ALine[Result + 1]) do
    Inc(Result);
end;

end.
