unit Atlas.Core.Outline.Directives;

// Compilerdirektiven im Text (#1763), Kern ohne VCL und OTA: {$…} und (*$…*)
// mit Name und Argument und ihrer Stelle. Direktiven in Kommentaren ({ },
// (* *), //) und Strings zählen nicht; eine Direktive darf über mehrere
// Zeilen gehen. Grundlage für Bedingungszweige und Regionen in der
// Brotkrumenleiste.

interface

type
  TAtlasDirective = record
    /// <summary>Name groß („IFDEF“, „ENDIF“).</summary>
    Name: string;
    /// <summary>Text hinter dem Namen ohne Leerraum am Rand („MSWINDOWS“); Zeilenumbrüche als Leerzeichen.</summary>
    Argument: string;
    /// <summary>Anfang ({ bzw. (), 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Hinter dem Ende (} bzw. *)), 0-basiert.</summary>
    EndLine: Integer;
    EndCharacter: Integer;
  end;

  TAtlasDirectives = TArray<TAtlasDirective>;

  TAtlasDirectiveScanner = class
  public
    /// <summary>Alle Direktiven in Quelltextreihenfolge.</summary>
    class function Scan(const ALines: TArray<string>): TAtlasDirectives; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Chars;

type
  /// <summary>Läuft Zeichen für Zeichen über den Text; merkt offene Kommentare, Strings und Direktiven.</summary>
  TScanner = class
  private
    FDirectives: TAtlasDirectives;
    /// <summary>Offener Kommentar bzw. offene Direktive: '{', '(' für (* *), #0 = keiner.</summary>
    FComment: Char;
    FInDirective: Boolean;
    FText: string;
    FCurrent: TAtlasDirective;
    procedure Finish(ALine, ACharacter: Integer);
    /// <summary>Im Kommentar oder in der Direktive: verarbeitet das Zeichen an APos (1-basiert).</summary>
    procedure InComment(const ALine: string; ALineIndex: Integer; var APos: Integer);
    /// <summary>Code an APos: öffnet Kommentar, Direktive oder String; False bei //.</summary>
    function InCode(const ALine: string; ALineIndex: Integer; var APos: Integer): Boolean;
    procedure ScanLine(const ALine: string; ALineIndex: Integer);
  public
    function Run(const ALines: TArray<string>): TAtlasDirectives;
  end;

function NextIs(const ALine: string; APos: Integer; AChar: Char): Boolean;
begin
  Result := (APos < Length(ALine)) and (ALine[APos + 1] = AChar);
end;

procedure TScanner.Finish(ALine, ACharacter: Integer);
var
  mText: string;
  mPos: Integer;
begin
  mText := Trim(FText);
  mPos := 1;
  while (mPos <= Length(mText)) and TTextChars.IsIdentChar(mText[mPos]) do
  begin
    Inc(mPos);
  end;
  FCurrent.Name := UpperCase(Copy(mText, 1, mPos - 1));
  FCurrent.Argument := Trim(Copy(mText, mPos, MaxInt));
  FCurrent.EndLine := ALine;
  FCurrent.EndCharacter := ACharacter;
  FDirectives := FDirectives + [FCurrent];
  FInDirective := False;
  FText := '';
end;

procedure TScanner.InComment(const ALine: string; ALineIndex: Integer; var APos: Integer);
begin
  if (FComment = '{') and (ALine[APos] = '}') then
  begin
    FComment := #0;
    if FInDirective then
    begin
      Finish(ALineIndex, APos);
    end;
  end
  else if (FComment = '(') and (ALine[APos] = '*') and NextIs(ALine, APos, ')') then
  begin
    FComment := #0;
    Inc(APos);
    if FInDirective then
    begin
      Finish(ALineIndex, APos);
    end;
  end
  else if FInDirective then
  begin
    FText := FText + ALine[APos];
  end;
end;

function TScanner.InCode(const ALine: string; ALineIndex: Integer; var APos: Integer): Boolean;
var
  mStart: Integer;
begin
  Result := True;
  mStart := APos;
  case ALine[APos] of
    '''':
      begin
        // Strings enden spätestens am Zeilenende.
        Inc(APos);
        while (APos <= Length(ALine)) and (ALine[APos] <> '''') do
        begin
          Inc(APos);
        end;
      end;
    '{':
      FComment := '{';
    '(':
      if NextIs(ALine, APos, '*') then
      begin
        FComment := '(';
        Inc(APos);
      end;
    '/':
      Result := not NextIs(ALine, APos, '/');
  end;
  if (FComment <> #0) and NextIs(ALine, APos, '$') then
  begin
    FInDirective := True;
    FText := '';
    FCurrent := Default(TAtlasDirective);
    FCurrent.Line := ALineIndex;
    FCurrent.Character := mStart - 1;
    Inc(APos);
  end;
end;

procedure TScanner.ScanLine(const ALine: string; ALineIndex: Integer);
var
  mPos: Integer;
begin
  mPos := 1;
  while mPos <= Length(ALine) do
  begin
    if FComment <> #0 then
    begin
      InComment(ALine, ALineIndex, mPos);
    end
    else if not InCode(ALine, ALineIndex, mPos) then
    begin
      Break;
    end;
    Inc(mPos);
  end;
  if FInDirective then
  begin
    FText := FText + ' ';
  end;
end;

function TScanner.Run(const ALines: TArray<string>): TAtlasDirectives;
var
  mIndex: Integer;
begin
  FDirectives := nil;
  FComment := #0;
  FInDirective := False;
  for mIndex := 0 to High(ALines) do
  begin
    ScanLine(ALines[mIndex], mIndex);
  end;
  Result := FDirectives;
end;

class function TAtlasDirectiveScanner.Scan(const ALines: TArray<string>): TAtlasDirectives;
var
  mScanner: TScanner;
begin
  mScanner := TScanner.Create;
  try
    Result := mScanner.Run(ALines);
  finally
    mScanner.Free;
  end;
end;

end.
