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
  mUpper: string;
begin
  mUpper := UpperCase(AText);
  Result := Pos(UpperCase(ANeedle), mUpper, AFrom);
end;

/// <summary>Wert des Attributs AName im Tag ATag; '' ohne.</summary>
function Attribute(const ATag, AName: string): string;
var
  mStart, mStop: Integer;
  mQuote: Char;
begin
  Result := '';
  mStart := FindText(AName + '=', ATag, 1);
  if mStart = 0 then
  begin
    Exit;
  end;
  mStart := mStart + Length(AName) + 1;
  if mStart > Length(ATag) then
  begin
    Exit;
  end;
  mQuote := ATag[mStart];
  if (mQuote <> '"') and (mQuote <> '''') then
  begin
    Exit;
  end;
  mStop := Pos(mQuote, ATag, mStart + 1);
  if mStop > 0 then
  begin
    Result := Copy(ATag, mStart + 1, mStop - mStart - 1);
  end;
end;

function WithoutSpaces(const AText: string): string;
var
  mCh: Char;
begin
  Result := '';
  for mCh in AText do
  begin
    if mCh > ' ' then
    begin
      Result := Result + mCh;
    end;
  end;
end;

/// <summary>Einrückung der Zeile, in der Position APos (ab 1) steht.</summary>
function IndentAt(const AText: string; APos: Integer): string;
var
  mStart, mIndex: Integer;
begin
  mStart := APos;
  while (mStart > 1) and (AText[mStart - 1] <> #10) do
  begin
    Dec(mStart);
  end;
  mIndex := mStart;
  while (mIndex <= Length(AText)) and ((AText[mIndex] = ' ') or (AText[mIndex] = #9)) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(AText, mStart, mIndex - mStart);
end;

/// <summary>Ohne Leerraum und abschließenden Pfadtrenner (Pfade in der .dproj nutzen \ oder /).</summary>
function ListItem(const AItem: string): string;
begin
  Result := Trim(AItem);
  while (Result <> '') and ((Result[Length(Result)] = '\') or (Result[Length(Result)] = '/')) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

{ TDprojEditor }

class function TDprojEditor.ConfigKey(const AText, AConfig: string): string;
var
  mStart, mTagEnd, mStop, mKeyStart, mKeyEnd: Integer;
begin
  if SameText(AConfig, 'Base') then
  begin
    Exit('Base');
  end;
  Result := '';
  mStart := FindText('<BuildConfiguration', AText, 1);
  while mStart > 0 do
  begin
    mTagEnd := Pos('>', AText, mStart);
    if mTagEnd = 0 then
    begin
      Exit;
    end;
    mStop := FindText('</BuildConfiguration>', AText, mTagEnd);
    if (mStop > 0) and SameText(Attribute(Copy(AText, mStart, mTagEnd - mStart + 1), 'Include'), AConfig) then
    begin
      mKeyStart := FindText('<Key>', AText, mTagEnd);
      mKeyEnd := FindText('</Key>', AText, mKeyStart);
      if (mKeyStart > 0) and (mKeyStart < mStop) and (mKeyEnd > 0) then
      begin
        Result := Trim(Copy(AText, mKeyStart + 5, mKeyEnd - mKeyStart - 5));
      end;
      Exit;
    end;
    mStart := FindText('<BuildConfiguration', AText, mTagEnd);
  end;
end;

class function TDprojEditor.ListContains(const AList, AValue: string): Boolean;
var
  mRest: string;
  mSeparator: Integer;
begin
  mRest := UnescapeXml(AList) + ';';
  mSeparator := Pos(';', mRest);
  while mSeparator > 0 do
  begin
    if SameText(ListItem(Copy(mRest, 1, mSeparator - 1)), ListItem(AValue)) then
    begin
      Exit(True);
    end;
    Delete(mRest, 1, mSeparator);
    mSeparator := Pos(';', mRest);
  end;
  Result := False;
end;

type
  /// <summary>PropertyGroup im Text: Anfang von "&lt;PropertyGroup", Ende des öffnenden Tags und Anfang von
  /// "&lt;/PropertyGroup&gt;".</summary>
  TPropertyGroupSpan = record
    Start: Integer;
    TagEnd: Integer;
    GroupEnd: Integer;
  end;

/// <summary>Erste PropertyGroup mit der Bedingung "'$(AKey)'!=''"; False ohne oder bei unvollständigem Text.</summary>
function FindGroup(const AText, AKey: string; out ASpan: TPropertyGroupSpan): Boolean;
var
  mWanted: string;
begin
  Result := False;
  mWanted := WithoutSpaces('''$(' + AKey + ')''!=''''');
  ASpan := Default(TPropertyGroupSpan);
  ASpan.Start := FindText('<PropertyGroup', AText, 1);
  while ASpan.Start > 0 do
  begin
    ASpan.TagEnd := Pos('>', AText, ASpan.Start);
    if ASpan.TagEnd = 0 then
    begin
      Exit;
    end;
    if SameText(WithoutSpaces(Attribute(Copy(AText, ASpan.Start, ASpan.TagEnd - ASpan.Start + 1), 'Condition')),
      mWanted) then
    begin
      ASpan.GroupEnd := FindText('</PropertyGroup>', AText, ASpan.TagEnd);
      Exit(ASpan.GroupEnd > 0);
    end;
    ASpan.Start := FindText('<PropertyGroup', AText, ASpan.TagEnd);
  end;
end;

/// <summary>Setzt AValue vorn in die vorhandene Eigenschaft ab AOpenPos.</summary>
function AddToValue(const AText, AProperty, AValue: string; AOpenPos, AGroupEnd: Integer;
  out ANewText: string): TDprojEditResult;
var
  mValueStart, mValueEnd: Integer;
  mSeparator: string;
begin
  mValueStart := AOpenPos + Length(AProperty) + 2;
  mValueEnd := FindText('</' + AProperty + '>', AText, mValueStart);
  if (mValueEnd = 0) or (mValueEnd > AGroupEnd) then
  begin
    Exit(TDprojEditResult.NoGroup);
  end;
  if TDprojEditor.ListContains(Copy(AText, mValueStart, mValueEnd - mValueStart), AValue) then
  begin
    Exit(TDprojEditResult.Present);
  end;
  mSeparator := ';';
  if mValueEnd = mValueStart then
  begin
    mSeparator := '';
  end;
  ANewText := Copy(AText, 1, mValueStart - 1) + EscapeXml(AValue) + mSeparator + Copy(AText, mValueStart, MaxInt);
  Result := TDprojEditResult.Added;
end;

/// <summary>Neue Zeile direkt nach dem öffnenden Tag, eingerückt wie die erste Eigenschaft.</summary>
function AddLine(const AText, AProperty, AValue: string; const ASpan: TPropertyGroupSpan;
  out ANewText: string): TDprojEditResult;
var
  mLineEnd: Integer;
  mIndent, mLine: string;
begin
  mLineEnd := Pos(#10, AText, ASpan.TagEnd);
  if mLineEnd = 0 then
  begin
    Exit(TDprojEditResult.NoGroup);
  end;
  mIndent := IndentAt(AText, mLineEnd + 1);
  if mLineEnd + 1 + Length(mIndent) >= ASpan.GroupEnd then
  begin
    mIndent := IndentAt(AText, ASpan.Start) + '    ';
  end;
  mLine := Format('%s<%s>%s;$(%s)</%s>', [mIndent, AProperty, EscapeXml(AValue), AProperty, AProperty]) +
    TTextLines.LineBreakOf(AText);
  ANewText := Copy(AText, 1, mLineEnd) + mLine + Copy(AText, mLineEnd + 1, MaxInt);
  Result := TDprojEditResult.Added;
end;

class function TDprojEditor.AddToList(const AText, AKey, AProperty, AValue: string;
  out ANewText: string): TDprojEditResult;
var
  mSpan: TPropertyGroupSpan;
  mOpenPos: Integer;
begin
  ANewText := AText;
  if not FindGroup(AText, AKey, mSpan) then
  begin
    Exit(TDprojEditResult.NoGroup);
  end;
  mOpenPos := FindText('<' + AProperty + '>', AText, mSpan.TagEnd);
  if (mOpenPos > 0) and (mOpenPos < mSpan.GroupEnd) then
  begin
    Result := AddToValue(AText, AProperty, AValue, mOpenPos, mSpan.GroupEnd, ANewText);
  end
  else
  begin
    Result := AddLine(AText, AProperty, AValue, mSpan, ANewText);
  end;
  if Result <> TDprojEditResult.Added then
  begin
    ANewText := AText;
  end;
end;

end.
