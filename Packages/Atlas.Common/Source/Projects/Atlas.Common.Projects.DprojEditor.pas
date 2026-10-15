unit Atlas.Common.Projects.DprojEditor;

// Kleine Änderungen an einer .dproj als Text (#301): Listen-Eigenschaften wie
// DCC_Define oder DCC_UnitSearchPath einer Konfiguration ergänzen. Der übrige
// Text bleibt Zeichen für Zeichen erhalten (Einrückung, Zeilenumbrüche,
// Reihenfolge), damit RAD Studio keine Fremdänderung meldet und ein Diff nur
// die geänderte Zeile zeigt.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TDprojEditResult = (Added, Present, NoGroup);
  {$SCOPEDENUMS OFF}

  TDprojEditor = class
  public
    /// <summary>Schlüssel der Konfiguration (Base, Cfg_1 …) aus BuildConfiguration; '' wenn unbekannt.</summary>
    class function ConfigKey(const AText, AConfig: string): string; static;
    /// <summary>Steht AValue (ohne Groß-/Kleinschreibung) in der Liste AList ("A;B;$(X)")?</summary>
    class function ListContains(const AList, AValue: string): Boolean; static;
    /// <summary>Setzt AValue vorn in die Liste AProperty der PropertyGroup mit Bedingung
    /// "'$(AKey)'!=''". Fehlt die Eigenschaft, kommt eine Zeile "AValue;$(AProperty)" dazu.</summary>
    class function AddToList(const AText, AKey, AProperty, AValue: string; out ANewText: string): TDprojEditResult;
      static;
  end;

implementation

uses
  Atlas.Text.Lines;

function EscapeXml(const AValue: string): string;
begin
  Result := StringReplace(AValue, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

function UnescapeXml(const AValue: string): string;
begin
  Result := StringReplace(AValue, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

/// <summary>Position (ab 1) von ANeedle in AText ab AFrom, ohne Groß-/Kleinschreibung; 0 wenn nicht da.</summary>
function FindText(const ANeedle, AText: string; AFrom: Integer): Integer;
var
  Upper: string;
begin
  Upper := UpperCase(AText);
  Result := Pos(UpperCase(ANeedle), Upper, AFrom);
end;

/// <summary>Wert des Attributs AName im Tag ATag; '' ohne.</summary>
function Attribute(const ATag, AName: string): string;
var
  Start, Stop: Integer;
  Quote: Char;
begin
  Result := '';
  Start := FindText(AName + '=', ATag, 1);
  if Start = 0 then
    Exit;
  Start := Start + Length(AName) + 1;
  if Start > Length(ATag) then
    Exit;
  Quote := ATag[Start];
  if (Quote <> '"') and (Quote <> '''') then
    Exit;
  Stop := Pos(Quote, ATag, Start + 1);
  if Stop > 0 then
    Result := Copy(ATag, Start + 1, Stop - Start - 1);
end;

function WithoutSpaces(const AText: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in AText do
    if Ch > ' ' then
      Result := Result + Ch;
end;

/// <summary>Einrückung der Zeile, in der Position APos (ab 1) steht.</summary>
function IndentAt(const AText: string; APos: Integer): string;
var
  Start, Index: Integer;
begin
  Start := APos;
  while (Start > 1) and (AText[Start - 1] <> #10) do
    Dec(Start);
  Index := Start;
  while (Index <= Length(AText)) and ((AText[Index] = ' ') or (AText[Index] = #9)) do
    Inc(Index);
  Result := Copy(AText, Start, Index - Start);
end;

/// <summary>Ohne Leerraum und abschließenden Pfadtrenner (Pfade in der .dproj nutzen \ oder /).</summary>
function ListItem(const AItem: string): string;
begin
  Result := Trim(AItem);
  while (Result <> '') and ((Result[Length(Result)] = '\') or (Result[Length(Result)] = '/')) do
    Delete(Result, Length(Result), 1);
end;

{ TDprojEditor }

class function TDprojEditor.ConfigKey(const AText, AConfig: string): string;
var
  Start, TagEnd, Stop, KeyStart, KeyEnd: Integer;
begin
  if SameText(AConfig, 'Base') then
    Exit('Base');
  Result := '';
  Start := FindText('<BuildConfiguration', AText, 1);
  while Start > 0 do
  begin
    TagEnd := Pos('>', AText, Start);
    if TagEnd = 0 then
      Exit;
    Stop := FindText('</BuildConfiguration>', AText, TagEnd);
    if (Stop > 0) and SameText(Attribute(Copy(AText, Start, TagEnd - Start + 1), 'Include'), AConfig) then
    begin
      KeyStart := FindText('<Key>', AText, TagEnd);
      KeyEnd := FindText('</Key>', AText, KeyStart);
      if (KeyStart > 0) and (KeyStart < Stop) and (KeyEnd > 0) then
        Result := Trim(Copy(AText, KeyStart + 5, KeyEnd - KeyStart - 5));
      Exit;
    end;
    Start := FindText('<BuildConfiguration', AText, TagEnd);
  end;
end;

class function TDprojEditor.ListContains(const AList, AValue: string): Boolean;
var
  Rest: string;
  Separator: Integer;
begin
  Rest := UnescapeXml(AList) + ';';
  Separator := Pos(';', Rest);
  while Separator > 0 do
  begin
    if SameText(ListItem(Copy(Rest, 1, Separator - 1)), ListItem(AValue)) then
      Exit(True);
    Delete(Rest, 1, Separator);
    Separator := Pos(';', Rest);
  end;
  Result := False;
end;

class function TDprojEditor.AddToList(const AText, AKey, AProperty, AValue: string;
  out ANewText: string): TDprojEditResult;
var
  Start, TagEnd, GroupEnd, OpenPos, ValueStart, ValueEnd, LineEnd: Integer;
  Wanted, Indent, Line: string;
begin
  ANewText := AText;
  Wanted := WithoutSpaces('''$(' + AKey + ')''!=''''');
  Start := FindText('<PropertyGroup', AText, 1);
  while Start > 0 do
  begin
    TagEnd := Pos('>', AText, Start);
    if TagEnd = 0 then
      Break;
    if SameText(WithoutSpaces(Attribute(Copy(AText, Start, TagEnd - Start + 1), 'Condition')), Wanted) then
    begin
      GroupEnd := FindText('</PropertyGroup>', AText, TagEnd);
      if GroupEnd = 0 then
        Break;
      OpenPos := FindText('<' + AProperty + '>', AText, TagEnd);
      if (OpenPos > 0) and (OpenPos < GroupEnd) then
      begin
        ValueStart := OpenPos + Length(AProperty) + 2;
        ValueEnd := FindText('</' + AProperty + '>', AText, ValueStart);
        if (ValueEnd = 0) or (ValueEnd > GroupEnd) then
          Break;
        if ListContains(Copy(AText, ValueStart, ValueEnd - ValueStart), AValue) then
          Exit(TDprojEditResult.Present);
        if ValueEnd = ValueStart then
          ANewText := Copy(AText, 1, ValueStart - 1) + EscapeXml(AValue) + Copy(AText, ValueStart, MaxInt)
        else
          ANewText := Copy(AText, 1, ValueStart - 1) + EscapeXml(AValue) + ';' + Copy(AText, ValueStart, MaxInt);
        Exit(TDprojEditResult.Added);
      end;
      // Neue Zeile direkt nach dem öffnenden Tag, eingerückt wie die erste Eigenschaft.
      LineEnd := Pos(#10, AText, TagEnd);
      if LineEnd = 0 then
        Break;
      Indent := IndentAt(AText, LineEnd + 1);
      if LineEnd + 1 + Length(Indent) >= GroupEnd then
        Indent := IndentAt(AText, Start) + '    ';
      Line := Format('%s<%s>%s;$(%s)</%s>', [Indent, AProperty, EscapeXml(AValue), AProperty, AProperty]) +
        TTextLines.LineBreakOf(AText);
      ANewText := Copy(AText, 1, LineEnd) + Line + Copy(AText, LineEnd + 1, MaxInt);
      Exit(TDprojEditResult.Added);
    end;
    Start := FindText('<PropertyGroup', AText, TagEnd);
  end;
  Result := TDprojEditResult.NoGroup;
end;

end.
