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

/// <summary>Trennt Laufwerk, UNC-Server oder Wurzel vom Pfad ab; ARest behält den Rest.</summary>
function PathPrefix(var ARest: string; ASeparator: Char): string;
begin
  if (Length(ARest) >= 2) and (ARest[2] = ':') then
  begin
    Result := Copy(ARest, 1, 2) + ASeparator;
    ARest := Copy(ARest, 3, MaxInt);
  end
  else if (Length(ARest) >= 2) and (ARest[1] = ASeparator) and (ARest[2] = ASeparator) then
  begin
    Result := ASeparator + ASeparator;
    ARest := Copy(ARest, 3, MaxInt);
  end
  else if (ARest <> '') and (ARest[1] = ASeparator) then
  begin
    Result := ASeparator;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Nimmt den Pfadteil APart auf: "." und leere Teile fallen weg, ".." nimmt den letzten Teil zurück.
/// </summary>
procedure AddPart(AParts: TList<string>; const APart: string; AAtRoot: Boolean);
begin
  if (APart = '') or (APart = '.') then
  begin
    Exit;
  end;
  if APart <> '..' then
  begin
    AParts.Add(APart);
  end
  else if (AParts.Count > 0) and (AParts.Last <> '..') then
  begin
    AParts.Delete(AParts.Count - 1);
  end
  else if not AAtRoot then
  begin
    // Relativer Pfad über den Anfang hinaus; an der Wurzel bleibt es bei der Wurzel.
    AParts.Add(APart);
  end;
end;

class function TProjectPaths.Normalize(const APath: string): string;
var
  mSeparator: Char;
  mPrefix, mRest, mPart: string;
  mParts: TList<string>;
begin
  if APath = '' then
  begin
    Exit('');
  end;
  mSeparator := SeparatorFor(APath);
  mRest := StringReplace(APath, '/', mSeparator, [rfReplaceAll]);
  mRest := StringReplace(mRest, '\', mSeparator, [rfReplaceAll]);
  mPrefix := PathPrefix(mRest, mSeparator);
  mParts := TList<string>.Create;
  try
    for mPart in mRest.Split([mSeparator]) do
    begin
      AddPart(mParts, mPart, mPrefix <> '');
    end;
    Result := mPrefix + string.Join(mSeparator, mParts.ToArray);
  finally
    mParts.Free;
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

/// <summary>Wert der Variablen AName aus AVariables; False, wenn es sie nicht gibt.</summary>
function TryVariable(const AVariables: TArray<TPair<string, string>>; const AName: string;
  out AValue: string): Boolean;
var
  mVariable: TPair<string, string>;
begin
  for mVariable in AVariables do
  begin
    if SameText(mVariable.Key, AName) then
    begin
      AValue := mVariable.Value;
      Exit(True);
    end;
  end;
  AValue := '';
  Result := False;
end;

class function TProjectPaths.ExpandVariables(const AText: string;
  const AVariables: TArray<TPair<string, string>>): string;
var
  mBuilder: TStringBuilder;
  mIndex, mClose: Integer;
  mValue: string;
begin
  if Pos('$(', AText) = 0 then
  begin
    Exit(AText);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      mClose := 0;
      if (AText[mIndex] = '$') and (mIndex < Length(AText)) and (AText[mIndex + 1] = '(') then
      begin
        mClose := Pos(')', AText, mIndex + 2);
      end;
      if mClose = 0 then
      begin
        mBuilder.Append(AText[mIndex]);
        Inc(mIndex);
        Continue;
      end;
      if not TryVariable(AVariables, Copy(AText, mIndex + 2, mClose - mIndex - 2), mValue) then
      begin
        mValue := Copy(AText, mIndex, mClose - mIndex + 1);
      end;
      mBuilder.Append(mValue);
      mIndex := mClose + 1;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
