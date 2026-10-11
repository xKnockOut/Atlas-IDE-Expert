unit Atlas.Common.Projects.Paths;

// Pfadhilfen für Projektdateien. Delphi-Projekte enthalten Windows-Pfade mit
// "\"; die Funktionen behandeln "\" und "/" gleich und arbeiten rein auf
// Zeichenketten, ohne Dateisystem. So verhalten sie sich auf jedem System
// gleich.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TProjectPaths = class
  public
    /// <summary>True für "C:\...", "\\server\..." und "/...".</summary>
    class function IsAbsolute(const APath: string): Boolean; static;
    /// <summary>Verbindet ABase und APath (wenn APath relativ ist) und löst "." und ".." auf.</summary>
    class function Combine(const ABase, APath: string): string; static;
    /// <summary>Löst "." und ".." auf und vereinheitlicht die Trenner; ohne abschließenden Trenner.</summary>
    class function Normalize(const APath: string): string; static;
    /// <summary>Ordner der Datei ohne abschließenden Trenner.</summary>
    class function DirectoryOf(const AFileName: string): string; static;
    /// <summary>Dateiname ohne Ordner und ohne Endung.</summary>
    class function BaseName(const AFileName: string): string; static;
    /// <summary>Endung mit Punkt in Kleinschreibung, z. B. ".pas".</summary>
    class function Extension(const AFileName: string): string; static;
    /// <summary>Teilt eine durch ";" getrennte Liste, ohne leere Einträge.</summary>
    class function SplitList(const AValue: string): TArray<string>; static;
    /// <summary>
    /// Ersetzt $(Name) durch Werte aus AVariables (ohne Beachtung der
    /// Groß-/Kleinschreibung); unbekannte Namen bleiben stehen.
    /// </summary>
    class function ExpandVariables(const AText: string; const AVariables: TArray<TPair<string, string>>): string; static;
  end;

implementation

function SeparatorFor(const APath: string): Char;
begin
  if (Pos('\', APath) > 0) or ((Length(APath) >= 2) and (APath[2] = ':')) then
    Result := '\'
  else
    Result := '/';
end;

function LastSeparator(const APath: string): Integer;
var
  Index: Integer;
begin
  for Index := Length(APath) downto 1 do
    if CharInSet(APath[Index], ['\', '/']) then
      Exit(Index);
  Result := 0;
end;

class function TProjectPaths.IsAbsolute(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or
    ((APath <> '') and CharInSet(APath[1], ['\', '/']));
end;

class function TProjectPaths.Normalize(const APath: string): string;
var
  Separator: Char;
  Prefix: string;
  Rest: string;
  Parts: TList<string>;
  Part: string;
  Start: Integer;
  Index: Integer;
begin
  if APath = '' then
    Exit('');
  Separator := SeparatorFor(APath);
  Rest := StringReplace(APath, '/', Separator, [rfReplaceAll]);
  Rest := StringReplace(Rest, '\', Separator, [rfReplaceAll]);
  // Präfix: Laufwerk, UNC-Server oder Wurzel bleiben stehen.
  if (Length(Rest) >= 2) and (Rest[2] = ':') then
  begin
    Prefix := Copy(Rest, 1, 2) + Separator;
    Rest := Copy(Rest, 3, MaxInt);
  end
  else if (Length(Rest) >= 2) and (Rest[1] = Separator) and (Rest[2] = Separator) then
  begin
    Prefix := Separator + Separator;
    Rest := Copy(Rest, 3, MaxInt);
  end
  else if (Rest <> '') and (Rest[1] = Separator) then
    Prefix := Separator
  else
    Prefix := '';
  Parts := TList<string>.Create;
  try
    Start := 1;
    for Index := 1 to Length(Rest) + 1 do
      if (Index > Length(Rest)) or (Rest[Index] = Separator) then
      begin
        Part := Copy(Rest, Start, Index - Start);
        Start := Index + 1;
        if (Part = '') or (Part = '.') then
          Continue;
        if Part <> '..' then
          Parts.Add(Part)
        else if (Parts.Count > 0) and (Parts.Last <> '..') then
          Parts.Delete(Parts.Count - 1)
        else if Prefix = '' then
          // Relativer Pfad über den Anfang hinaus; an der Wurzel bleibt es bei der Wurzel.
          Parts.Add(Part);
      end;
    Result := Prefix + string.Join(Separator, Parts.ToArray);
  finally
    Parts.Free;
  end;
end;

class function TProjectPaths.Combine(const ABase, APath: string): string;
begin
  if (APath = '') then
    Result := Normalize(ABase)
  else if IsAbsolute(APath) or (ABase = '') then
    Result := Normalize(APath)
  else
    Result := Normalize(ABase + SeparatorFor(ABase + APath) + APath);
end;

class function TProjectPaths.DirectoryOf(const AFileName: string): string;
var
  Index: Integer;
begin
  Index := LastSeparator(AFileName);
  if Index = 0 then
    Result := ''
  else if (Index = 3) and (AFileName[2] = ':') then
    Result := Copy(AFileName, 1, 3)
  else
    Result := Copy(AFileName, 1, Index - 1);
end;

class function TProjectPaths.BaseName(const AFileName: string): string;
var
  Dot: Integer;
begin
  Result := Copy(AFileName, LastSeparator(AFileName) + 1, MaxInt);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, 1, Dot - 1);
end;

class function TProjectPaths.Extension(const AFileName: string): string;
var
  Name: string;
  Dot: Integer;
begin
  Name := Copy(AFileName, LastSeparator(AFileName) + 1, MaxInt);
  Dot := LastDelimiter('.', Name);
  if Dot = 0 then
    Result := ''
  else
    Result := LowerCase(Copy(Name, Dot, MaxInt));
end;

class function TProjectPaths.SplitList(const AValue: string): TArray<string>;
var
  Items: TList<string>;
  Item: string;
begin
  Items := TList<string>.Create;
  try
    for Item in AValue.Split([';']) do
      if Trim(Item) <> '' then
        Items.Add(Trim(Item));
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

class function TProjectPaths.ExpandVariables(const AText: string;
  const AVariables: TArray<TPair<string, string>>): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  Close: Integer;
  Name: string;
  Variable: TPair<string, string>;
  Found: Boolean;
begin
  if Pos('$(', AText) = 0 then
    Exit(AText);
  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      if (AText[Index] = '$') and (Index < Length(AText)) and (AText[Index + 1] = '(') then
      begin
        Close := Pos(')', AText, Index + 2);
        if Close > 0 then
        begin
          Name := Copy(AText, Index + 2, Close - Index - 2);
          Found := False;
          for Variable in AVariables do
            if SameText(Variable.Key, Name) then
            begin
              Builder.Append(Variable.Value);
              Found := True;
              Break;
            end;
          if not Found then
            Builder.Append(Copy(AText, Index, Close - Index + 1));
          Index := Close + 1;
          Continue;
        end;
      end;
      Builder.Append(AText[Index]);
      Inc(Index);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
