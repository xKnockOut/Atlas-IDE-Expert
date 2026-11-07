unit Atlas.Core.Hover.Declaration;

// Deklaration im Hover lesen (#835, #1455): Der Tooltip rechnet den Typ aus
// der Deklaration selbst und gibt ihn den Modulen (Visualisierer des
// Debuggers) als ersten Eintrag der Typkette. Lag bis #1455 im Debugger-Kern
// (TAtlasVisualizers); Base darf das Debugger-Modul nicht kennen.

interface

type
  TAtlasHoverDeclaration = class
  public
    /// <summary>Typ aus der Deklaration im Hover: „var Kunden: TObjectList&lt;TKunde&gt;“ →
    /// „TObjectList&lt;TKunde&gt;“,
    /// „property Items: TList&lt;Integer&gt; read FItems“ → „TList&lt;Integer&gt;“, „function F(A: Integer): TPoint“ →
    /// „TPoint“;
    /// '' ohne Typ.</summary>
    class function DeclaredType(const ADeclaration: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

/// <summary>Erster Doppelpunkt außerhalb von Klammern (Parameter) und spitzen Klammern (Typargumente); 0 ohne.
/// </summary>
function FirstColon(const AText: string): Integer;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  for mIndex := 1 to Length(AText) do
  begin
    case AText[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        if mDepth > 0 then
        begin
          Dec(mDepth);
        end;
      ':':
        if mDepth = 0 then
        begin
          Exit(mIndex);
        end;
    end;
  end;
  Result := 0;
end;

function SkipSpaces(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] = ' ') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Endet der Typname vor AChar? ADepth zählt offene spitze Klammern.</summary>
function EndsType(AChar: Char; var ADepth: Integer): Boolean;
begin
  Result := False;
  case AChar of
    'A'..'Z', 'a'..'z', '0'..'9', '_', '.':
      ;
    '<':
      Inc(ADepth);
    '>':
      begin
        Result := ADepth = 0;
        if not Result then
        begin
          Dec(ADepth);
        end;
      end;
    ',', ' ':
      Result := ADepth = 0;
  else
    Result := (ADepth = 0) and (Ord(AChar) < 128);
  end;
end;

class function TAtlasHoverDeclaration.DeclaredType(const ADeclaration: string): string;
var
  mIndex, mDepth, mStart: Integer;
begin
  Result := '';
  mIndex := FirstColon(ADeclaration);
  if mIndex = 0 then
  begin
    Exit;
  end;
  mStart := SkipSpaces(ADeclaration, mIndex + 1);
  mIndex := mStart;
  // Name mit Units und Typargumenten; „array of Byte“ und „set of …“ als Ganzes.
  if StartsText('array of ', Copy(ADeclaration, mStart, MaxInt)) then
  begin
    mIndex := SkipSpaces(ADeclaration, mStart + Length('array of '));
  end;
  mDepth := 0;
  while (mIndex <= Length(ADeclaration)) and not EndsType(ADeclaration[mIndex], mDepth) do
  begin
    Inc(mIndex);
  end;
  Result := Trim(Copy(ADeclaration, mStart, mIndex - mStart));
end;

end.
