unit Atlas.Common.Projects.Paths;

// Pfadhilfen für Projektdateien. Delphi-Projekte enthalten Windows-Pfade mit
// "\"; die Funktionen behandeln "\" und "/" gleich und arbeiten rein auf
// Zeichenketten, ohne Dateisystem. So verhalten sie sich auf jedem System
// gleich.

interface

uses
  System.SysUtils,
  System.Math,
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
    /// <summary>Tiefster Ordner, der A und B enthält (ganze Ordnernamen, Groß-/Kleinschreibung egal), in der
    /// Schreibweise von A ohne abschließenden Trenner; '' bei verschiedenen Laufwerken oder leerem A bzw. B.
    /// </summary>
    class function CommonFolder(const A, B: string): string; static;
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

/// <summary>Trenner für APath: Ein Windows-Anfang (Laufwerk, "\\server", "\") gibt "\", ein POSIX-Anfang ("/")
/// gibt "/" vor (#1109: unter Linux steht der Projektordner mit "/" vor den "\"-Pfaden aus dem .dproj). Ein
/// relativer Pfad behält "\", wenn er einen enthält.</summary>
function SeparatorFor(const APath: string): Char;
begin
  if ((Length(APath) >= 2) and (APath[2] = ':')) or APath.StartsWith('\') then
  begin
    Result := '\';
  end
  else if APath.StartsWith('/') then
  begin
    Result := '/';
  end
  else if Pos('\', APath) > 0 then
  begin
    Result := '\';
  end
  else
  begin
    Result := '/';
  end;
end;

function LastSeparator(const APath: string): Integer;
var
  Index: Integer;
begin
  for Index := Length(APath) downto 1 do
  begin
    if CharInSet(APath[Index], ['\', '/']) then
    begin
      Exit(Index);
    end;
  end;
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
  begin
    Exit('');
  end;
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
  begin
    Prefix := Separator;
  end
  else
  begin
    Prefix := '';
  end;
  Parts := TList<string>.Create;
  try
    Start := 1;
    for Index := 1 to Length(Rest) + 1 do
    begin
      if (Index > Length(Rest)) or (Rest[Index] = Separator) then
      begin
        Part := Copy(Rest, Start, Index - Start);
        Start := Index + 1;
        if (Part = '') or (Part = '.') then
        begin
          Continue;
        end;
        if Part <> '..' then
        begin
          Parts.Add(Part);
        end
        else if (Parts.Count > 0) and (Parts.Last <> '..') then
        begin
          Parts.Delete(Parts.Count - 1);
        end
        else if Prefix = '' then
        begin
          // Relativer Pfad über den Anfang hinaus; an der Wurzel bleibt es bei der Wurzel.
          Parts.Add(Part);
        end;
      end;
    end;
    Result := Prefix + string.Join(Separator, Parts.ToArray);
  finally
    Parts.Free;
  end;
end;

class function TProjectPaths.Combine(const ABase, APath: string): string;
begin
  if (APath = '') then
  begin
    Result := Normalize(ABase);
  end
  else if IsAbsolute(APath) or (ABase = '') then
  begin
    Result := Normalize(APath);
  end
  else
  begin
    Result := Normalize(ABase + SeparatorFor(ABase + APath) + APath);
  end;
end;

class function TProjectPaths.DirectoryOf(const AFileName: string): string;
var
  Index: Integer;
begin
  Index := LastSeparator(AFileName);
  if Index = 0 then
  begin
    Result := '';
  end
  else if (Index = 3) and (AFileName[2] = ':') then
  begin
    Result := Copy(AFileName, 1, 3);
  end
  else
  begin
    Result := Copy(AFileName, 1, Index - 1);
  end;
end;

class function TProjectPaths.CommonFolder(const A, B: string): string;
var
  mLeft, mRight: TArray<string>;
  mIndex, mCount: Integer;
  mSeparator: Char;
begin
  Result := '';
  if (A = '') or (B = '') then
  begin
    Exit;
  end;
  mSeparator := SeparatorFor(A);
  mLeft := Normalize(A).Split(['\', '/']);
  mRight := Normalize(B).Split(['\', '/']);
  mCount := 0;
  for mIndex := 0 to Min(High(mLeft), High(mRight)) do
  begin
    if not SameText(mLeft[mIndex], mRight[mIndex]) then
    begin
      Break;
    end;
    Inc(mCount);
  end;
  if mCount = 0 then
  begin
    Exit;
  end;
  Result := string.Join(mSeparator, Copy(mLeft, 0, mCount));
  // Laufwerk allein ("C:") als Ordner "C:\"; POSIX-Wurzel ("" vor dem ersten "/") als "/".
  if (Length(Result) = 2) and (Result[2] = ':') then
  begin
    Result := Result + mSeparator;
  end
  else if Result = '' then
  begin
    Result := mSeparator;
  end;
end;

class function TProjectPaths.BaseName(const AFileName: string): string;
var
  Dot: Integer;
begin
  Result := Copy(AFileName, LastSeparator(AFileName) + 1, MaxInt);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
  begin
    Result := Copy(Result, 1, Dot - 1);
  end;
end;

class function TProjectPaths.Extension(const AFileName: string): string;
var
  Name: string;
  Dot: Integer;
begin
  Name := Copy(AFileName, LastSeparator(AFileName) + 1, MaxInt);
  Dot := LastDelimiter('.', Name);
  if Dot = 0 then
  begin
    Result := '';
  end
  else
  begin
    Result := LowerCase(Copy(Name, Dot, MaxInt));
  end;
end;

class function TProjectPaths.SplitList(const AValue: string): TArray<string>;
var
  Items: TList<string>;
  Item: string;
begin
  Items := TList<string>.Create;
  try
    for Item in AValue.Split([';']) do
    begin
      if Trim(Item) <> '' then
      begin
        Items.Add(Trim(Item));
      end;
    end;
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
  begin
    Exit(AText);
  end;
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
          begin
            if SameText(Variable.Key, Name) then
            begin
              Builder.Append(Variable.Value);
              Found := True;
              Break;
            end;
          end;
          if not Found then
          begin
            Builder.Append(Copy(AText, Index, Close - Index + 1));
          end;
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
