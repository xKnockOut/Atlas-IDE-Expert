unit Atlas.Core.Outline.Overloads;

// Überladungen in der Brotkrumenleiste (#1784), Kern ohne VCL und OTA:
// - Find nennt alle Überladungen einer Routine: gleichnamige Methoden bzw.
//   Routinen mit demselben Elternknoten (derselbe Typ bzw. die Unit-Ebene),
//   in Quelltextreihenfolge, jede einmal (Rümpfe mit Deklaration zählen
//   über ihre Deklaration). Ohne zweite gleichnamige Routine ist die Liste
//   leer.
// - ParamsOf liest die Parameterliste aus dem Kopf hinter dem Namen, mit
//   Klammern und zusammengezogenem Leerraum; ohne Parameter „()“.
// - Caption ist Name und Parameter, Shorten kürzt lange Listen mit „…“.

interface

uses
  Atlas.Core.Outline.Model;

type
  TAtlasOverloads = class
  public
    /// <summary>Überladungen der Routine ANode (Deklaration) in Quelltextreihenfolge; leer ohne zweite.</summary>
    class function Find(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>; static;
    /// <summary>Parameterliste mit Klammern, Leerraum zusammengezogen; „()“ ohne Parameter, '' ohne Routine.
    /// </summary>
    class function ParamsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      ANode: Integer): string; static;
    /// <summary>Name ohne Besitzer und Parameterliste, auf AMax Zeichen gekürzt.</summary>
    class function Caption(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode,
      AMax: Integer): string; static;
    /// <summary>AText, bei mehr als AMax Zeichen auf AMax gekürzt und mit „…“ am Ende.</summary>
    class function Shorten(const AText: string; AMax: Integer): string; static;
  end;

implementation

uses
  System.SysUtils;

function IsRoutine(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := ANode.Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine];
end;

function BareName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

class function TAtlasOverloads.Find(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>;
var
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  if (ANode < 0) or (ANode > High(ANodes)) or not IsRoutine(ANodes[ANode]) then
  begin
    Exit;
  end;
  mName := BareName(ANodes[ANode].Name);
  for mIndex := 0 to High(ANodes) do
  begin
    if not ANodes[mIndex].Hidden and IsRoutine(ANodes[mIndex]) and (ANodes[mIndex].Parent = ANodes[ANode].Parent) and
      SameText(BareName(ANodes[mIndex].Name), mName) then
    begin
      Result := Result + [mIndex];
    end;
  end;
  if Length(Result) < 2 then
  begin
    Result := nil;
  end;
end;

/// <summary>Zeichen ab Zeile ALine, Spalte ACharacter (0-basiert) als ein Text mit #10 an Zeilenenden, höchstens
/// AMaxLines Zeilen.</summary>
function TextFrom(const ALines: TArray<string>; ALine, ACharacter, AMaxLines: Integer): string;
var
  mLine: Integer;
begin
  Result := Copy(ALines[ALine], ACharacter + 1, MaxInt);
  mLine := ALine + 1;
  while (mLine <= High(ALines)) and (mLine < ALine + AMaxLines) do
  begin
    Result := Result + #10 + ALines[mLine];
    Inc(mLine);
  end;
end;

/// <summary>Leerraum (auch Zeilenenden) zu einem Leerzeichen zusammengezogen, ohne Leerraum innen an den
/// Klammern.</summary>
function Collapse(const AText: string): string;
var
  mChar: Char;
  mSpace: Boolean;
begin
  Result := '';
  mSpace := False;
  for mChar in AText do
  begin
    if CharInSet(mChar, [' ', #9, #10, #13]) then
    begin
      mSpace := True;
      Continue;
    end;
    if mSpace and (Result <> '') and (Result[Length(Result)] <> '(') and (mChar <> ')') then
    begin
      Result := Result + ' ';
    end;
    mSpace := False;
    Result := Result + mChar;
  end;
end;

/// <summary>Index hinter dem Namen ab AIndex (mit Besitzer und generischen Parametern) und dem Leerraum danach.
/// </summary>
function SkipName(const AText: string; AIndex: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := AIndex;
  mDepth := 0;
  while (Result <= Length(AText)) and ((mDepth > 0) or CharInSet(AText[Result], ['a'..'z', 'A'..'Z', '0'..'9',
    '_', '.', '&', '<'])) do
  begin
    if AText[Result] = '<' then
    begin
      Inc(mDepth);
    end
    else if AText[Result] = '>' then
    begin
      Dec(mDepth);
    end;
    Inc(Result);
  end;
  while (Result <= Length(AText)) and CharInSet(AText[Result], [' ', #9, #10, #13]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Klammer ab AStart bis zur passenden schließenden, zusammengefasst; '()' ohne Gegenstück.</summary>
function ParenFrom(const AText: string; AStart: Integer): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '()';
  mDepth := 0;
  for mIndex := AStart to Length(AText) do
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(Collapse(Copy(AText, AStart, mIndex - AStart + 1)));
      end;
    end;
  end;
end;

class function TAtlasOverloads.ParamsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ANode: Integer): string;
var
  mText: string;
  mIndex: Integer;
begin
  Result := '';
  if (ANode < 0) or (ANode > High(ANodes)) or not IsRoutine(ANodes[ANode]) or (ANodes[ANode].NameLine < 0) or
    (ANodes[ANode].NameLine > High(ALines)) then
  begin
    Exit;
  end;
  mText := TextFrom(ALines, ANodes[ANode].NameLine, ANodes[ANode].NameCharacter, 20);
  mIndex := SkipName(mText, 1);
  Result := '()';
  if (mIndex <= Length(mText)) and (mText[mIndex] = '(') then
  begin
    Result := ParenFrom(mText, mIndex);
  end;
end;

class function TAtlasOverloads.Caption(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode,
  AMax: Integer): string;
begin
  Result := '';
  if (ANode >= 0) and (ANode <= High(ANodes)) then
  begin
    Result := Shorten(BareName(ANodes[ANode].Name) + ParamsOf(ANodes, ALines, ANode), AMax);
  end;
end;

class function TAtlasOverloads.Shorten(const AText: string; AMax: Integer): string;
begin
  Result := AText;
  if (AMax > 1) and (Length(AText) > AMax) then
  begin
    Result := Copy(AText, 1, AMax - 1) + '…';
  end;
end;

end.
