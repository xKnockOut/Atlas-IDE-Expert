unit Atlas.Core.Hover.Declaration;

// Deklaration im Hover lesen (#835, #1455): Der Tooltip rechnet den Typ aus
// der Deklaration selbst und gibt ihn den Modulen (Visualisierer des
// Debuggers) als ersten Eintrag der Typkette. Lag bis #1455 im Debugger-Kern
// (TAtlasVisualizers); Base darf das Debugger-Modul nicht kennen.

interface

type
  TAtlasHoverDeclaration = class
  public
    /// <summary>Typ aus der Deklaration im Hover: „var Kunden: TObjectList&lt;TKunde&gt;“ → „TObjectList&lt;TKunde&gt;“,
    /// „property Items: TList&lt;Integer&gt; read FItems“ → „TList&lt;Integer&gt;“, „function F(A: Integer): TPoint“ → „TPoint“;
    /// '' ohne Typ.</summary>
    class function DeclaredType(const ADeclaration: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

class function TAtlasHoverDeclaration.DeclaredType(const ADeclaration: string): string;
var
  Index, Depth, Start: Integer;
  Found: Boolean;
begin
  Result := '';
  // Erster Doppelpunkt außerhalb von Klammern (Parameter) und spitzen Klammern (Typargumente).
  Depth := 0;
  Found := False;
  Index := 1;
  while Index <= Length(ADeclaration) do
  begin
    case ADeclaration[Index] of
      '(', '[', '<':
        Inc(Depth);
      ')', ']', '>':
        if Depth > 0 then
        begin
          Dec(Depth);
        end;
      ':':
        if Depth = 0 then
        begin
          Found := True;
          Break;
        end;
    end;
    Inc(Index);
  end;
  if not Found then
  begin
    Exit;
  end;
  Inc(Index);
  while (Index <= Length(ADeclaration)) and (ADeclaration[Index] = ' ') do
  begin
    Inc(Index);
  end;
  // Name mit Units und Typargumenten; „array of Byte“ und „set of …“ als Ganzes.
  if StartsText('array of ', Copy(ADeclaration, Index, MaxInt)) then
  begin
    Start := Index;
    Inc(Index, Length('array of '));
    while (Index <= Length(ADeclaration)) and (ADeclaration[Index] = ' ') do
    begin
      Inc(Index);
    end;
  end
  else
  begin
    Start := Index;
  end;
  Depth := 0;
  while Index <= Length(ADeclaration) do
  begin
    case ADeclaration[Index] of
      'A'..'Z', 'a'..'z', '0'..'9', '_', '.':
        ;
      '<':
        Inc(Depth);
      '>':
        if Depth = 0 then
        begin
          Break;
        end
        else
        begin
          Dec(Depth);
        end;
      ',', ' ':
        if Depth = 0 then
        begin
          Break;
        end;
    else
      if (Depth = 0) and (Ord(ADeclaration[Index]) < 128) then
      begin
        Break;
      end;
    end;
    Inc(Index);
  end;
  Result := Trim(Copy(ADeclaration, Start, Index - Start));
end;

end.
