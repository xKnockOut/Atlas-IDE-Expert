unit Atlas.Common.Compiler.OutputParser;

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
  Atlas.Common.Compiler.Contract;

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
  Atlas.Common.Projects.Paths;

function IsCodeAt(const AText: string; AIndex: Integer): Boolean;
var
  mOffset: Integer;
begin
  // Buchstabe E/W/H/F/X und vier Ziffern, davor Anfang oder Leerzeichen/Doppelpunkt, danach Ende oder
  // Leerzeichen/Doppelpunkt.
  Result := (AIndex + 4 <= Length(AText)) and CharInSet(AText[AIndex], ['E', 'W', 'H', 'F', 'X']) and
    ((AIndex = 1) or CharInSet(AText[AIndex - 1], [' ', ':'])) and
    ((AIndex + 5 > Length(AText)) or CharInSet(AText[AIndex + 5], [' ', ':']));
  if Result then
  begin
    for mOffset := 1 to 4 do
    begin
      if not CharInSet(AText[AIndex + mOffset], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Klammern der Fundstelle "(…)" vor dem ersten ")"; False ohne Klammern oder mit Meldungsnummer
/// davor.</summary>
function FindLocationParens(const AText: string; out AOpen, AClose: Integer): Boolean;
var
  mIndex: Integer;
begin
  AClose := Pos(')', AText);
  AOpen := AClose - 1;
  while (AOpen > 0) and (AText[AOpen] <> '(') do
  begin
    Dec(AOpen);
  end;
  Result := AOpen > 1;
  // Klammern im Meldungstext ("F1026 File not found: 'a(1).pas'") sind keine Fundstelle.
  mIndex := 1;
  while Result and (mIndex < AOpen) do
  begin
    Result := not IsCodeAt(AText, mIndex);
    Inc(mIndex);
  end;
end;

/// <summary>Liest "Zeile" oder "Zeile,Spalte" (1-basiert) als 0-basierte Werte; Spalte -1 ohne Komma.</summary>
function ReadLineColumn(const AInner: string; out ALine, AColumn: Integer): Boolean;
var
  mComma: Integer;
begin
  AColumn := -1;
  mComma := Pos(',', AInner);
  if mComma > 0 then
  begin
    Result := TryStrToInt(Trim(Copy(AInner, 1, mComma - 1)), ALine) and
      TryStrToInt(Trim(Copy(AInner, mComma + 1, MaxInt)), AColumn);
  end
  else
  begin
    Result := TryStrToInt(Trim(AInner), ALine);
  end;
  if Result then
  begin
    Dec(ALine);
    if mComma > 0 then
    begin
      Dec(AColumn);
    end;
  end;
end;

/// <summary>Liest "Datei(Zeile)" oder "Datei(Zeile,Spalte)" am Anfang; ARest ist der Text danach.</summary>
function ReadLocation(const AText: string; out AFileName: string; out ALine, AColumn: Integer;
  out ARest: string): Boolean;
var
  mOpen, mClose: Integer;
begin
  ALine := -1;
  AColumn := -1;
  AFileName := '';
  ARest := AText;
  Result := FindLocationParens(AText, mOpen, mClose) and
    ReadLineColumn(Copy(AText, mOpen + 1, mClose - mOpen - 1), ALine, AColumn);
  if Result then
  begin
    AFileName := Trim(Copy(AText, 1, mOpen - 1));
    ARest := Copy(AText, mClose + 1, MaxInt);
    Result := AFileName <> '';
  end
  else
  begin
    ALine := -1;
    AColumn := -1;
  end;
end;

/// <summary>Schweregrad aus dem Anfangsbuchstaben der Meldungsnummer.</summary>
function SeverityOf(ALetter: Char): TCompilerSeverity;
begin
  case ALetter of
    'E': Result := TCompilerSeverity.Error;
    'W': Result := TCompilerSeverity.Warning;
    'H': Result := TCompilerSeverity.Hint;
    // X1008 und Verwandte meldet dcc als Warnung (#1040).
    'X': Result := TCompilerSeverity.Warning;
  else
    Result := TCompilerSeverity.Fatal;
  end;
end;

/// <summary>Sucht die Meldungsnummer in ARest und füllt Code, Schweregrad und Text; False ohne Nummer.</summary>
function ReadCode(const ARest: string; var AMessage: TCompilerMessage): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 1 to Length(ARest) do
  begin
    if IsCodeAt(ARest, mIndex) then
    begin
      AMessage.Code := Copy(ARest, mIndex, 5);
      AMessage.Severity := SeverityOf(ARest[mIndex]);
      AMessage.Text := Trim(Copy(ARest, mIndex + 5, MaxInt));
      if (AMessage.Text <> '') and (AMessage.Text[1] = ':') then
      begin
        AMessage.Text := Trim(Copy(AMessage.Text, 2, MaxInt));
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TCompilerOutputParser }

class function TCompilerOutputParser.ParseLine(const ALine, AWorkingDir: string;
  out AMessage: TCompilerMessage): Boolean;
var
  mText, mRest, mFileName: string;
  mLine, mColumn: Integer;
begin
  AMessage := Default(TCompilerMessage);
  AMessage.Line := -1;
  AMessage.Column := -1;
  mText := Trim(ALine);
  // MSBuild: "[dcc32 Error] ..."
  if (mText <> '') and (mText[1] = '[') and (Pos(']', mText) > 0) then
  begin
    mText := Trim(Copy(mText, Pos(']', mText) + 1, MaxInt));
  end;
  mRest := mText;
  if ReadLocation(mText, mFileName, mLine, mColumn, mRest) then
  begin
    if TProjectPaths.IsAbsolute(mFileName) or (AWorkingDir = '') then
    begin
      AMessage.FileName := mFileName;
    end
    else
    begin
      AMessage.FileName := TProjectPaths.Combine(AWorkingDir, mFileName);
    end;
    AMessage.Line := mLine;
    AMessage.Column := mColumn;
  end;
  Result := ReadCode(mRest, AMessage);
end;

class function TCompilerOutputParser.Parse(const ALines: TArray<string>;
  const AWorkingDir: string): TArray<TCompilerMessage>;
var
  mLine, mKey: string;
  mItem: TCompilerMessage;
  mSeen: TDictionary<string, Boolean>;
  mFound: TList<TCompilerMessage>;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mFound := TList<TCompilerMessage>.Create;
  try
    for mLine in ALines do
    begin
      if ParseLine(mLine, AWorkingDir, mItem) then
      begin
        mKey := LowerCase(mItem.FileName) + '|' + IntToStr(mItem.Line) + '|' + IntToStr(mItem.Column) + '|' +
          mItem.Code + '|' + mItem.Text;
        if mSeen.ContainsKey(mKey) then
        begin
          Continue;
        end;
        mSeen.Add(mKey, True);
        mFound.Add(mItem);
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
    mSeen.Free;
  end;
end;

end.
