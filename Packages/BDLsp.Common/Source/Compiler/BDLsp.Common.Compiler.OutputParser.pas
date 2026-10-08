unit BDLsp.Common.Compiler.OutputParser;

// Liest Meldungen aus der Ausgabe von dcc32/dcc64 und MSBuild (#40), z. B.
//   C:\P\Unit1.pas(12) Error: E2003 Undeclared identifier: 'X'
//   Unit1.pas(12,5) Warning: W1036 Variable 'Y' might not have been initialized
//   [dcc32 Fehler] Unit1.pas(12): E2003 Undeklarierter Bezeichner: 'X'
//   [dcc64 Fatal Error] Projekt.dpr(5): F2613 Unit 'Foo' not found.
// Der Schweregrad kommt aus dem Anfangsbuchstaben der Meldungsnummer (E, W, H,
// F); das funktioniert unabhängig von der Sprache des Compilers. Zeilen ohne
// Meldungsnummer (Fortschritt, Statistik) werden übergangen.

interface

uses
  BDLsp.Common.Compiler.Contract;

type
  TCompilerOutputParser = class
  public
    /// <summary>Eine Zeile; relative Pfade werden auf AWorkingDir bezogen. False ohne Meldung.</summary>
    class function ParseLine(const ALine, AWorkingDir: string; out AMessage: TCompilerMessage): Boolean; static;
    /// <summary>Alle Meldungen der Ausgabe, doppelte (MSBuild wiederholt sie am Ende) nur einmal.</summary>
    class function Parse(const ALines: TArray<string>; const AWorkingDir: string): TArray<TCompilerMessage>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Projects.Paths;

function IsCodeAt(const AText: string; AIndex: Integer): Boolean;
var
  Offset: Integer;
begin
  // Buchstabe E/W/H/F und vier Ziffern, davor Anfang oder Leerzeichen/Doppelpunkt, danach Ende oder Leerzeichen/Doppelpunkt.
  Result := (AIndex + 4 <= Length(AText)) and CharInSet(AText[AIndex], ['E', 'W', 'H', 'F']) and
    ((AIndex = 1) or CharInSet(AText[AIndex - 1], [' ', ':'])) and
    ((AIndex + 5 > Length(AText)) or CharInSet(AText[AIndex + 5], [' ', ':']));
  if Result then
    for Offset := 1 to 4 do
      if not CharInSet(AText[AIndex + Offset], ['0'..'9']) then
        Exit(False);
end;

/// <summary>Liest "Datei(Zeile)" oder "Datei(Zeile,Spalte)" am Anfang; ARest ist der Text danach.</summary>
function ReadLocation(const AText: string; out AFileName: string; out ALine, AColumn: Integer;
  out ARest: string): Boolean;
var
  Open, Close, Comma, Index: Integer;
  Inner: string;
begin
  Result := False;
  ALine := -1;
  AColumn := -1;
  AFileName := '';
  ARest := AText;
  Close := Pos(')', AText);
  if Close = 0 then
    Exit;
  Open := Close - 1;
  while (Open > 0) and (AText[Open] <> '(') do
    Dec(Open);
  if Open <= 1 then
    Exit;
  // Klammern im Meldungstext ("F1026 File not found: 'a(1).pas'") sind keine Fundstelle.
  for Index := 1 to Open - 1 do
    if IsCodeAt(AText, Index) then
      Exit;
  Inner := Copy(AText, Open + 1, Close - Open - 1);
  Comma := Pos(',', Inner);
  if Comma > 0 then
  begin
    if not TryStrToInt(Trim(Copy(Inner, 1, Comma - 1)), ALine) or
      not TryStrToInt(Trim(Copy(Inner, Comma + 1, MaxInt)), AColumn) then
      Exit;
    Dec(AColumn);
  end
  else if not TryStrToInt(Trim(Inner), ALine) then
    Exit;
  Dec(ALine);
  AFileName := Trim(Copy(AText, 1, Open - 1));
  ARest := Copy(AText, Close + 1, MaxInt);
  Result := AFileName <> '';
end;

{ TCompilerOutputParser }

class function TCompilerOutputParser.ParseLine(const ALine, AWorkingDir: string;
  out AMessage: TCompilerMessage): Boolean;
var
  Text, Rest, FileName: string;
  Index, Line, Column: Integer;
begin
  AMessage := Default(TCompilerMessage);
  AMessage.Line := -1;
  AMessage.Column := -1;
  Text := Trim(ALine);
  // MSBuild: "[dcc32 Error] ..."
  if (Text <> '') and (Text[1] = '[') and (Pos(']', Text) > 0) then
    Text := Trim(Copy(Text, Pos(']', Text) + 1, MaxInt));
  Rest := Text;
  if ReadLocation(Text, FileName, Line, Column, Rest) then
  begin
    if TProjectPaths.IsAbsolute(FileName) or (AWorkingDir = '') then
      AMessage.FileName := FileName
    else
      AMessage.FileName := TProjectPaths.Combine(AWorkingDir, FileName);
    AMessage.Line := Line;
    AMessage.Column := Column;
  end;
  for Index := 1 to Length(Rest) do
    if IsCodeAt(Rest, Index) then
    begin
      AMessage.Code := Copy(Rest, Index, 5);
      case Rest[Index] of
        'E': AMessage.Severity := TCompilerSeverity.Error;
        'W': AMessage.Severity := TCompilerSeverity.Warning;
        'H': AMessage.Severity := TCompilerSeverity.Hint;
      else
        AMessage.Severity := TCompilerSeverity.Fatal;
      end;
      AMessage.Text := Trim(Copy(Rest, Index + 5, MaxInt));
      if (AMessage.Text <> '') and (AMessage.Text[1] = ':') then
        AMessage.Text := Trim(Copy(AMessage.Text, 2, MaxInt));
      Exit(True);
    end;
  Result := False;
end;

class function TCompilerOutputParser.Parse(const ALines: TArray<string>;
  const AWorkingDir: string): TArray<TCompilerMessage>;
var
  Line, Key: string;
  Item: TCompilerMessage;
  Seen: TDictionary<string, Boolean>;
  Found: TList<TCompilerMessage>;
begin
  Seen := TDictionary<string, Boolean>.Create;
  Found := TList<TCompilerMessage>.Create;
  try
    for Line in ALines do
      if ParseLine(Line, AWorkingDir, Item) then
      begin
        Key := LowerCase(Item.FileName) + '|' + IntToStr(Item.Line) + '|' + IntToStr(Item.Column) + '|' +
          Item.Code + '|' + Item.Text;
        if Seen.ContainsKey(Key) then
          Continue;
        Seen.Add(Key, True);
        Found.Add(Item);
      end;
    Result := Found.ToArray;
  finally
    Found.Free;
    Seen.Free;
  end;
end;

end.
